# frozen_string_literal: true

require "json"
require "time"
require_relative "database"
require_relative "semantic_index"

module Holocron
  class BriefingContextAssembler
    CONTEXT_VERSION = "briefing-context-v3"
    RETRIEVAL_STRATEGIES = %w[linked_recency semantic hybrid].freeze
    MAX_PEOPLE = 12
    MAX_CURRENT_INTERACTIONS_PER_PERSON = 2
    MAX_PRIOR_INTERACTIONS_PER_PERSON = 5
    MAX_INTERACTIONS = 15
    MAX_CONTEXT_CHARACTERS = 60_000
    ROLE_RANK = {"requester" => 0, "required" => 1, "optional" => 2, "staff" => 3}.freeze

    class NotFoundError < StandardError; end

    def initialize(workspace:, strategy: "linked_recency", embedding_provider: nil)
      raise ArgumentError, "Unsupported retrieval strategy: #{strategy}." unless RETRIEVAL_STRATEGIES.include?(strategy)

      @workspace = workspace
      @strategy = strategy
      @embedding_provider = embedding_provider
      @db = Database.db
    end

    def call(briefing:)
      meeting = @db[:meetings].where(id: briefing[:meeting_id], workspace_id: workspace_id).first
      raise NotFoundError, "Meeting is not available in this workspace." unless meeting

      request = @db[:scheduling_requests]
        .where(id: meeting[:scheduling_request_id], workspace_id: workspace_id)
        .first
      raise NotFoundError, "Scheduling request is not available in this workspace." unless request

      people, omitted_people = request_people(request[:id])
      organizations = request_organizations(people)
      interactions, omitted_interactions, strategy_metadata = if semantic_strategy?
        semantic_interactions(
          request: request,
          meeting: meeting,
          people: people,
          attendee_balanced: @strategy == "hybrid"
        )
      else
        selected, omitted = request_interactions(request[:id], people)
        [selected, omitted, {}]
      end
      candidate_windows = @db[:request_candidate_windows]
        .where(scheduling_request_id: request[:id])
        .order(:position)
        .all

      essential_sources = [
        request_source(request, candidate_windows),
        meeting_source(meeting)
      ]
      essential_sources.concat(people.map { |person| person_source(person) })
      essential_sources.concat(organizations.map { |organization| organization_source(organization) })

      selected_sources = essential_sources
      interactions.each do |interaction|
        candidate = interaction_source(interaction)
        candidate_sources = selected_sources + [candidate]
        break if serialized_size(candidate_sources) > MAX_CONTEXT_CHARACTERS

        selected_sources = candidate_sources
      end
      budget_omissions = interactions.length - (selected_sources.length - essential_sources.length)
      omitted_interactions += budget_omissions

      sources = selected_sources.each_with_index.map do |source, index|
        source.merge("source_ref" => format("SRC-%03d", index + 1))
      end
      prior_interactions = sources.count do |source|
        source["source_type"] == "interaction" && !source.dig("facts", "current_request")
      end

      limitations = []
      limitations << "#{omitted_people} linked people were omitted by the context limit." if omitted_people.positive?
      if omitted_interactions.positive?
        reason = semantic_strategy? ? "context limits" : "recency or context limits"
        limitations << "#{omitted_interactions} interactions were omitted by #{reason}."
      end
      if prior_interactions.zero?
        limitation = semantic_strategy? ?
          "No semantically relevant prior interaction history was found in this workspace." :
          "No prior interaction history was available for the linked people."
        limitations << limitation
      end

      manifest = {
        "context_version" => CONTEXT_VERSION,
        "workspace_timezone" => @workspace[:timezone],
        "briefing_id" => briefing[:id],
        "meeting_id" => meeting[:id],
        "scheduling_request_id" => request[:id],
        "sources" => sources,
        "limitations" => limitations,
        "retrieval" => {
          "strategy" => @strategy,
          "linked_people_selected" => people.length,
          "linked_people_omitted" => omitted_people,
          "interactions_selected" => sources.count { |source| source["source_type"] == "interaction" },
          "interactions_omitted" => omitted_interactions,
          "source_count" => sources.length
        }.merge(strategy_metadata)
      }
      manifest["section_source_refs"] = hybrid_section_source_refs(sources) if @strategy == "hybrid"
      manifest["retrieval"]["context_characters"] = JSON.generate(manifest).length
      manifest
    end

    private

    def request_people(request_id)
      links = @db[:scheduling_request_people]
        .where(scheduling_request_id: request_id)
        .all
      people_by_id = @db[:people]
        .where(workspace_id: workspace_id, id: links.map { |link| link[:person_id] })
        .all
        .to_h { |person| [person[:id], person] }

      people = links.group_by { |link| link[:person_id] }.filter_map do |person_id, person_links|
        person = people_by_id[person_id]
        next unless person

        roles = person_links.map { |link| link[:role] }.uniq.sort_by { |role| ROLE_RANK.fetch(role, 99) }
        person.merge(request_roles: roles)
      end.sort_by do |person|
        [person[:request_roles].map { |role| ROLE_RANK.fetch(role, 99) }.min, person[:display_name].downcase]
      end

      [people.first(MAX_PEOPLE), [people.length - MAX_PEOPLE, 0].max]
    end

    def request_organizations(people)
      ids = people.filter_map { |person| person[:organization_id] }.uniq
      organizations = @db[:organizations]
        .where(workspace_id: workspace_id, id: ids)
        .all
        .to_h { |organization| [organization[:id], organization] }
      ids.filter_map { |id| organizations[id] }
    end

    def request_interactions(request_id, people)
      per_person = people.map do |person|
        current_dataset = @db[:interactions]
          .where(workspace_id: workspace_id, person_id: person[:id], scheduling_request_id: request_id)
        current_count = current_dataset.count
        current = current_dataset
          .reverse_order(:occurred_at, :id)
          .limit(MAX_CURRENT_INTERACTIONS_PER_PERSON)
          .all
        prior_dataset = @db[:interactions]
          .where(workspace_id: workspace_id, person_id: person[:id])
          .where(Sequel.|({scheduling_request_id: nil}, Sequel.~(scheduling_request_id: request_id)))
        prior_count = prior_dataset.count
        prior = prior_dataset
          .reverse_order(:occurred_at, :id)
          .limit(MAX_PRIOR_INTERACTIONS_PER_PERSON)
          .all

        selected = current.first(MAX_CURRENT_INTERACTIONS_PER_PERSON).map do |interaction|
          interaction.merge(person_name: person[:display_name], current_request: true)
        end
        selected.concat(prior.first(MAX_PRIOR_INTERACTIONS_PER_PERSON).map do |interaction|
          interaction.merge(person_name: person[:display_name], current_request: false)
        end)
        omitted = [current_count - current.length, 0].max
        omitted += [prior_count - prior.length, 0].max
        [selected, omitted]
      end

      round_robin = []
      longest = per_person.map { |interactions, _omitted| interactions.length }.max.to_i
      longest.times do |index|
        per_person.each do |interactions, _omitted|
          round_robin << interactions[index] if interactions[index]
        end
      end
      selected = round_robin.first(MAX_INTERACTIONS)
      omitted = per_person.sum { |_interactions, count| count }
      omitted += [round_robin.length - MAX_INTERACTIONS, 0].max
      [selected, omitted]
    end

    def semantic_interactions(request:, meeting:, people:, attendee_balanced: false)
      current = current_request_interactions(request[:id], people)
      result = SemanticIndex.new(
        workspace: @workspace,
        embedding_provider: @embedding_provider
      ).search_interactions(
        query: semantic_query(request, meeting),
        exclude_request_id: request[:id],
        limit: MAX_INTERACTIONS - current.length,
        balanced_person_ids: attendee_balanced ? people.map { |person| person[:id] } : [],
        per_person_limit: 2
      )
      selected = (current + result.fetch(:interactions)).uniq { |interaction| interaction[:id] }.first(MAX_INTERACTIONS)
      metadata = {
        "semantic_records_indexed" => result[:indexed_records],
        "semantic_records_refreshed" => result[:refreshed_records],
        "embedding_provider" => result[:embedding_provider],
        "embedding_model" => result[:embedding_model],
        "vector_backend" => result[:vector_backend],
        "embedding_indexing_tokens" => result[:indexing_tokens],
        "embedding_query_tokens" => result[:query_tokens],
        "minimum_similarity" => result[:minimum_similarity],
        "semantic_matches_selected" => result.fetch(:interactions).length,
        "attendee_balancing_enabled" => attendee_balanced,
        "attendee_balanced_matches_selected" => result[:attendee_balanced_matches_selected],
        "attendees_with_history_selected" => result[:attendees_with_history_selected]
      }
      [selected, 0, metadata]
    end

    def current_request_interactions(request_id, people)
      people.flat_map do |person|
        @db[:interactions]
          .where(workspace_id: workspace_id, person_id: person[:id], scheduling_request_id: request_id)
          .reverse_order(:occurred_at, :id)
          .limit(MAX_CURRENT_INTERACTIONS_PER_PERSON)
          .all
          .map do |interaction|
            interaction.merge(person_name: person[:display_name], current_request: true)
          end
      end
    end

    def semantic_query(request, meeting)
      [
        meeting[:title],
        request[:purpose],
        request[:availability_notes],
        request[:original_request_text]
      ].compact.join("\n")
    end

    def semantic_strategy?
      %w[semantic hybrid].include?(@strategy)
    end

    def hybrid_section_source_refs(sources)
      refs_for = lambda do |&block|
        sources.select(&block).map { |source| source.fetch("source_ref") }
      end
      prior_interaction = lambda do |source|
        source["source_type"] == "interaction" && !source.dig("facts", "current_request")
      end

      {
        "overview" => refs_for.call { |source| %w[scheduling_request meeting].include?(source["source_type"]) },
        "attendees" => refs_for.call { |source| %w[scheduling_request person organization].include?(source["source_type"]) },
        "prior_history" => refs_for.call(&prior_interaction),
        "objectives" => refs_for.call do |source|
          source["source_type"] == "scheduling_request" || prior_interaction.call(source)
        end,
        "logistics" => refs_for.call { |source| %w[meeting scheduling_request].include?(source["source_type"]) }
      }
    end

    def request_source(request, candidate_windows)
      candidates = candidate_windows.map do |window|
        {
          "candidate_date" => window[:candidate_date],
          "starts_at" => iso8601(window[:starts_at]),
          "ends_at" => iso8601(window[:ends_at]),
          "notes" => bounded(window[:notes], 500)
        }
      end
      facts = {
        "requester_name" => request[:requester_name],
        "requester_email" => request[:requester_email],
        "requester_organization" => request[:requester_organization],
        "purpose" => bounded(request[:purpose], 2_000),
        "requested_duration_minutes" => request[:requested_duration_minutes],
        "availability_notes" => bounded(request[:availability_notes], 1_500),
        "candidate_windows" => candidates
      }
      source(
        type: "scheduling_request",
        id: request[:id],
        label: "Scheduling request: #{request[:requester_name]}",
        excerpt: [facts["purpose"], "#{facts['requested_duration_minutes']} minutes", facts["availability_notes"]].compact.join(" | "),
        facts: facts
      )
    end

    def meeting_source(meeting)
      facts = {
        "title" => meeting[:title],
        "starts_at" => iso8601(meeting[:starts_at]),
        "ends_at" => iso8601(meeting[:ends_at]),
        "location" => meeting[:location]
      }
      source(
        type: "meeting",
        id: meeting[:id],
        label: "Meeting: #{meeting[:title]}",
        excerpt: compact_facts(facts),
        facts: facts
      )
    end

    def person_source(person)
      organization = person[:organization_id] && @db[:organizations]
        .where(id: person[:organization_id], workspace_id: workspace_id)
        .first
      facts = {
        "display_name" => person[:display_name],
        "primary_email" => person[:primary_email],
        "job_title" => person[:job_title],
        "organization_id" => organization&.fetch(:id, nil),
        "organization_name" => organization&.fetch(:name, nil),
        "request_roles" => person[:request_roles],
        "notes" => bounded(person[:notes], 1_000)
      }
      source(
        type: "person",
        id: person[:id],
        label: person[:display_name],
        excerpt: [
          facts["job_title"],
          facts["organization_name"],
          facts["request_roles"].map { |role| humanize(role) }.join(" / "),
          facts["primary_email"],
          facts["notes"]
        ].reject { |value| value.nil? || value == "" }.join(" | "),
        facts: facts
      )
    end

    def organization_source(organization)
      facts = {
        "name" => organization[:name],
        "website_url" => organization[:website_url],
        "notes" => bounded(organization[:notes], 1_000)
      }
      source(
        type: "organization",
        id: organization[:id],
        label: organization[:name],
        excerpt: facts["notes"] || facts["website_url"],
        facts: facts
      )
    end

    def interaction_source(interaction)
      facts = {
        "person_name" => interaction[:person_name],
        "interaction_type" => interaction[:interaction_type],
        "occurred_at" => iso8601(interaction[:occurred_at]),
        "summary" => bounded(interaction[:summary], 2_000),
        "current_request" => interaction[:current_request]
      }
      facts["semantic_similarity"] = interaction[:semantic_similarity].round(4) if interaction[:semantic_similarity]
      source(
        type: "interaction",
        id: interaction[:id],
        label: "#{humanize(interaction[:interaction_type])} with #{interaction[:person_name]}",
        excerpt: facts["summary"],
        facts: facts
      )
    end

    def source(type:, id:, label:, excerpt:, facts:)
      {
        "source_type" => type,
        "source_id" => id,
        "source_label" => label,
        "source_excerpt" => excerpt,
        "facts" => facts
      }
    end

    def compact_facts(facts)
      facts.filter_map do |key, value|
        next if value.nil? || value == "" || value == []

        rendered = value.is_a?(Array) ? JSON.generate(value) : value.to_s
        "#{humanize(key)}: #{rendered}"
      end.join(" | ")
    end

    def serialized_size(sources)
      JSON.generate(sources).length
    end

    def bounded(value, limit)
      return nil if value.nil?

      value.to_s[0, limit]
    end

    def workspace_id
      @workspace.fetch(:id)
    end

    def humanize(value)
      value.to_s.split("_").map(&:capitalize).join(" ")
    end

    def iso8601(value)
      value&.iso8601
    end
  end
end
