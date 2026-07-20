# frozen_string_literal: true

require "json"
require "time"
require_relative "database"
require_relative "semantic_index"

module Holocron
  class BriefingContextAssembler
    CONTEXT_VERSION = "briefing-context-v7"
    RETRIEVAL_STRATEGIES = %w[linked_recency semantic hybrid fused].freeze
    MAX_PEOPLE = 12
    MAX_CURRENT_INTERACTIONS_PER_PERSON = 2
    MAX_PRIOR_INTERACTIONS_PER_PERSON = 5
    MAX_INTERACTIONS = 15
    FUSED_MIN_INTERACTIONS = 10
    FUSED_MAX_INTERACTIONS = 12
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
          attendee_balanced: %w[hybrid fused].include?(@strategy),
          fused: @strategy == "fused"
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
      manifest["section_source_refs"] = section_source_refs(sources)
      manifest["retrieval"]["section_evidence_counts"] = manifest["section_source_refs"]
        .transform_values(&:length)
      manifest["retrieval"]["audit_context_characters"] = JSON.generate(manifest).length
      manifest["retrieval"]["context_characters"] = JSON.generate(
        {
          "context_version" => manifest["context_version"],
          "workspace_timezone" => manifest["workspace_timezone"],
          "sources" => manifest["sources"],
          "limitations" => manifest["limitations"]
        }
      ).length
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

    def semantic_interactions(request:, meeting:, people:, attendee_balanced: false, fused: false)
      current = current_request_interactions(request[:id], people)
      result = SemanticIndex.new(
        workspace: @workspace,
        embedding_provider: @embedding_provider
      ).search_interactions(
        query: semantic_query(request, meeting),
        exclude_request_id: request[:id],
        limit: MAX_INTERACTIONS - current.length,
        balanced_person_ids: attendee_balanced ? people.map { |person| person[:id] } : [],
        per_person_limit: 2,
        max_per_person: attendee_balanced ? 3 : nil,
        fused: fused
      )
      candidates = result.fetch(:interactions)
      prior = fused ? select_fused_interactions(candidates, people: people, current: current) : candidates
      selected = (current + prior).uniq { |interaction| interaction[:id] }.first(MAX_INTERACTIONS)
      metadata = {
        "semantic_records_indexed" => result[:indexed_records],
        "semantic_interactions_indexed" => result[:indexed_interactions],
        "semantic_overview_records" => result[:overview_records],
        "semantic_burst_records" => result[:burst_records],
        "semantic_records_refreshed" => result[:refreshed_records],
        "semantic_records_removed" => result[:removed_records],
        "embedding_provider" => result[:embedding_provider],
        "embedding_model" => result[:embedding_model],
        "vector_backend" => result[:vector_backend],
        "embedding_indexing_tokens" => result[:indexing_tokens],
        "embedding_query_tokens" => result[:query_tokens],
        "minimum_similarity" => result[:minimum_similarity],
        "fusion_enabled" => result[:fusion_enabled],
        "fusion_method" => result[:fusion_method],
        "rrf_k" => result[:rrf_k],
        "vector_candidates" => result[:vector_candidates],
        "lexical_candidates" => result[:lexical_candidates],
        "attendee_candidates" => result[:attendee_candidates],
        "semantic_matches_considered" => candidates.length,
        "semantic_matches_selected" => prior.length,
        "adaptive_selection_enabled" => fused,
        "adaptive_minimum_interactions" => fused ? FUSED_MIN_INTERACTIONS : nil,
        "adaptive_maximum_interactions" => fused ? FUSED_MAX_INTERACTIONS : nil,
        "selected_candidates" => prior.map do |interaction|
          {
            "interaction_id" => interaction[:id],
            "person_id" => interaction[:person_id],
            "rrf_score" => interaction[:rrf_score]&.round(6),
            "retrieval_signals" => interaction[:retrieval_signals]
          }.compact
        end,
        "attendee_balancing_enabled" => attendee_balanced,
        "maximum_matches_per_person" => attendee_balanced ? 3 : nil,
        "attendee_balanced_matches_selected" => result[:attendee_balanced_matches_selected],
        "attendees_with_history_selected" => result[:attendees_with_history_selected]
      }
      [selected, 0, metadata]
    end

    def select_fused_interactions(candidates, people:, current:)
      minimum_prior = [FUSED_MIN_INTERACTIONS - current.length, 0].max
      maximum_prior = [FUSED_MAX_INTERACTIONS - current.length, 0].max
      return candidates.first(maximum_prior) if candidates.length <= minimum_prior

      covered_person_ids = current.map { |interaction| interaction[:person_id] }.uniq
      selected = people.reject { |person| covered_person_ids.include?(person[:id]) }.filter_map do |person|
        candidates.find { |candidate| candidate[:person_id] == person[:id] }
      end.uniq { |candidate| candidate[:id] }.first(maximum_prior)
      target_minimum = [minimum_prior, candidates.length].min
      target_maximum = [maximum_prior, candidates.length].min

      while selected.length < target_minimum
        candidate = best_diverse_candidate(candidates - selected, selected)
        break unless candidate

        selected << candidate
      end

      while selected.length < target_maximum
        candidate = best_diverse_candidate(candidates - selected, selected)
        break unless candidate && distinctive_candidate?(candidate, selected)

        selected << candidate
      end

      candidate_rank = candidates.each_with_index.to_h { |candidate, index| [candidate[:id], index] }
      selected.sort_by { |candidate| candidate_rank.fetch(candidate[:id]) }
    end

    def best_diverse_candidate(candidates, selected)
      maximum_score = candidates.map { |candidate| candidate[:rrf_score].to_f }.max.to_f
      candidates.max_by do |candidate|
        relevance = maximum_score.zero? ? 0.0 : candidate[:rrf_score].to_f / maximum_score
        redundancy = selected.map { |chosen| text_overlap(candidate, chosen) }.max.to_f
        (0.82 * relevance) + (0.18 * (1.0 - redundancy))
      end
    end

    def distinctive_candidate?(candidate, selected)
      return true if selected.none? { |chosen| chosen[:person_id] == candidate[:person_id] }
      return true if selected.map { |chosen| text_overlap(candidate, chosen) }.max.to_f < 0.62

      candidate_kinds = evidence_kinds(candidate)
      selected_kinds = selected.flat_map { |chosen| evidence_kinds(chosen) }.uniq
      (candidate_kinds - selected_kinds).any?
    end

    def evidence_kinds(interaction)
      Array(interaction[:matched_evidence_spans]).filter_map { |span| span["kind"] }.uniq
    end

    def text_overlap(left, right)
      left_tokens = retrieval_text(left).downcase.scan(/[a-z0-9]{3,}/).uniq
      right_tokens = retrieval_text(right).downcase.scan(/[a-z0-9]{3,}/).uniq
      union = left_tokens | right_tokens
      union.empty? ? 0.0 : (left_tokens & right_tokens).length.to_f / union.length
    end

    def retrieval_text(interaction)
      spans = Array(interaction[:matched_evidence_spans]).filter_map { |span| span["text"] }
      spans.empty? ? interaction[:summary].to_s : spans.join(" ")
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
      %w[semantic hybrid fused].include?(@strategy)
    end

    def section_source_refs(sources)
      refs_for = lambda do |&block|
        sources.select(&block).map { |source| source.fetch("source_ref") }
      end
      prior_interaction = lambda do |source|
        source["source_type"] == "interaction" && !source.dig("facts", "current_request")
      end

      request_refs = refs_for.call { |source| source["source_type"] == "scheduling_request" }
      current_refs = refs_for.call do |source|
        source["source_type"] == "interaction" && source.dig("facts", "current_request")
      end
      prior_sources = sources.select(&prior_interaction)
      prior_refs = prior_sources.map { |source| source.fetch("source_ref") }
      interaction_refs = (current_refs + prior_refs).uniq
      identity_refs = refs_for.call { |source| %w[person organization].include?(source["source_type"]) }

      {
        "meeting_ask" => (request_refs + current_refs).first(4),
        "desired_outcomes" => (request_refs + interaction_refs).uniq,
        "decision_context" => (prior_refs + identity_refs).uniq,
        "talking_points" => (request_refs + interaction_refs).uniq,
        "risks" => (request_refs + interaction_refs).uniq,
        "open_questions" => (request_refs + interaction_refs).uniq
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
      evidence_spans = Array(interaction[:matched_evidence_spans]).filter_map do |span|
        text = bounded(span["text"], 1_000)
        next unless text

        {"kind" => span["kind"], "text" => text}.compact
      end
      facts = {
        "person_name" => interaction[:person_name],
        "interaction_type" => interaction[:interaction_type],
        "occurred_at" => iso8601(interaction[:occurred_at]),
        "current_request" => interaction[:current_request]
      }
      if evidence_spans.any?
        facts["evidence_spans"] = evidence_spans
      else
        facts["summary"] = bounded(interaction[:summary], 2_000)
      end
      excerpt = if evidence_spans.any?
        evidence_spans.map { |span| span.fetch("text") }.join(" • ")
      else
        facts["summary"]
      end
      source(
        type: "interaction",
        id: interaction[:id],
        label: "#{humanize(interaction[:interaction_type])} with #{interaction[:person_name]}",
        excerpt: bounded(excerpt, 2_000),
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
