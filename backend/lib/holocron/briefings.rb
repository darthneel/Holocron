# frozen_string_literal: true

require "json"
require "securerandom"
require "time"
require_relative "briefing_context_assembler"
require_relative "briefing_generation"
require_relative "database"
require_relative "relationships"
require_relative "tasks"

module Holocron
  module Briefings
    STATUSES = %w[draft in_review approved changes_requested].freeze
    SECTION_TYPES = %w[
      overview attendees relationship_context prior_history objectives logistics notes
      meeting_snapshot meeting_ask desired_outcomes decision_context talking_points risks open_questions
    ].freeze
    SOURCE_TYPES = %w[scheduling_request meeting person organization interaction].freeze
    RETRIEVAL_STRATEGIES = BriefingContextAssembler::RETRIEVAL_STRATEGIES

    class ValidationError < StandardError
      attr_reader :fields

      def initialize(fields)
        super("Validation failed.")
        @fields = fields
      end
    end

    class ConflictError < StandardError
      attr_reader :current_lock_version, :current_status, :current_version_number

      def initialize(briefing)
        super("Briefing changed since it was loaded.")
        @current_lock_version = briefing&.fetch(:lock_version, nil)
        @current_status = briefing&.fetch(:status, nil)
        @current_version_number = briefing&.fetch(:current_version_number, nil)
      end
    end

    class StateError < StandardError
      attr_reader :current_status

      def initialize(message, current_status: nil)
        super(message)
        @current_status = current_status
      end
    end

    class ScheduleConflictError < StandardError
      attr_reader :current_lock_version, :current_status

      def initialize(request)
        super("Proposed meeting changed since it was loaded.")
        @current_lock_version = request&.fetch(:lock_version, nil)
        @current_status = request&.fetch(:status, nil)
      end
    end

    class GenerationError < StandardError
      attr_reader :provider, :model, :validation_errors

      def initialize(message, provider:, model:, validation_errors: {})
        super(message)
        @provider = provider
        @model = model
        @validation_errors = validation_errors
      end
    end

    module_function

    def list(workspace:)
      db = Database.db
      briefings = db[:briefings]
        .where(workspace_id: workspace[:id])
        .reverse_order(:updated_at)
        .all
      return [] if briefings.empty?

      meetings = db[:meetings]
        .where(id: briefings.map { |briefing| briefing[:meeting_id] })
        .all
        .to_h { |meeting| [meeting[:id], meeting] }
      requests = db[:scheduling_requests]
        .where(id: meetings.values.map { |meeting| meeting[:scheduling_request_id] })
        .all
        .to_h { |request| [request[:id], request] }
      current_version_numbers = briefings.to_h do |briefing|
        [briefing[:id], briefing[:current_version_number]]
      end
      current_versions = db[:briefing_versions]
        .where(briefing_id: briefings.map { |briefing| briefing[:id] })
        .all
        .select do |version|
          current_version_numbers[version[:briefing_id]] == version[:version_number]
        end
        .to_h { |version| [version[:briefing_id], version] }
      section_counts = db[:briefing_sections]
        .where(briefing_version_id: current_versions.values.map { |version| version[:id] })
        .exclude(section_type: "relationship_context", body: "")
        .group(:briefing_version_id)
        .select(:briefing_version_id, Sequel.function(:count, Sequel.lit("*")).as(:count))
        .to_hash(:briefing_version_id, :count)

      briefings.map do |briefing|
        meeting = meetings.fetch(briefing[:meeting_id])
        request = requests.fetch(meeting[:scheduling_request_id])
        version = current_versions.fetch(briefing[:id])
        serialize_list_item(
          briefing,
          meeting: meeting,
          request: request,
          section_count: section_counts.fetch(version[:id], 0)
        )
      end
    end

    def fetch(id:, workspace:, include_history: true, include_source_catalog: true)
      briefing = Database.db[:briefings].where(id: id, workspace_id: workspace[:id]).first
      briefing && serialize_detail(
        briefing,
        include_history: include_history,
        include_source_catalog: include_source_catalog
      )
    end

    def create_for_request(request_id:, attributes:, workspace:, actor:)
      meeting_attributes = normalize_meeting(attributes)
      expected_request_lock_version = expected_schedule_lock_version(attributes)
      db = Database.db
      briefing_id = SecureRandom.uuid

      db.transaction do
        request = db[:scheduling_requests].where(id: request_id, workspace_id: workspace[:id]).first
        return nil unless request

        unless request[:status] == "proposed"
          raise StateError.new("Only a proposed meeting can be scheduled.", current_status: request[:status])
        end

        unless request[:lock_version] == expected_request_lock_version
          raise ScheduleConflictError.new(request)
        end

        if db[:meetings].where(scheduling_request_id: request_id).any?
          raise StateError.new("This proposed meeting has already been scheduled.", current_status: request[:status])
        end

        now = Time.now.utc
        correlation_id = SecureRandom.uuid
        meeting_id = SecureRandom.uuid
        context = Relationships.context_for_request(request_id: request_id, workspace: workspace)
        scheduled = db[:scheduling_requests]
          .where(
            id: request_id,
            workspace_id: workspace[:id],
            status: "proposed",
            lock_version: expected_request_lock_version
          )
          .update(
            status: "scheduled",
            lock_version: expected_request_lock_version + 1,
            updated_at: now
          )
        raise ScheduleConflictError.new(db[:scheduling_requests].where(id: request_id).first) if scheduled.zero?

        meeting = {
          id: meeting_id,
          workspace_id: workspace[:id],
          scheduling_request_id: request_id,
          created_by_workspace_member_id: actor[:id],
          **meeting_attributes,
          created_at: now,
          updated_at: now
        }
        db[:meetings].insert(meeting)
        db[:briefings].insert(
          id: briefing_id,
          workspace_id: workspace[:id],
          meeting_id: meeting_id,
          created_by_workspace_member_id: actor[:id],
          status: "draft",
          current_version_number: 1,
          lock_version: 1,
          created_at: now,
          updated_at: now
        )

        sections = initial_sections(
          request: request,
          meeting: meeting_attributes,
          context: context,
          workspace: workspace
        )
        version_id = insert_version(
          briefing_id: briefing_id,
          actor: actor,
          version_number: 1,
          status: "draft",
          change_summary: "Initial briefing assembled from scheduling and relationship records.",
          sections: sections,
          occurred_at: now
        )

        task = Tasks.create_briefing_preparation!(
          meeting: meeting,
          request: request,
          workspace: workspace,
          actor: actor,
          correlation_id: correlation_id,
          occurred_at: now
        )

        write_audit(
          workspace: workspace,
          actor: actor,
          event_type: "scheduling_request.scheduled",
          subject_type: "scheduling_request",
          subject_id: request_id,
          payload: {meeting_id: meeting_id, briefing_id: briefing_id},
          correlation_id: correlation_id,
          occurred_at: now
        )
        write_audit(
          workspace: workspace,
          actor: actor,
          event_type: "meeting.created",
          subject_type: "meeting",
          subject_id: meeting_id,
          payload: {scheduling_request_id: request_id, briefing_id: briefing_id, task_id: task[:id]},
          correlation_id: correlation_id,
          occurred_at: now
        )
        write_audit(
          workspace: workspace,
          actor: actor,
          event_type: "briefing.created",
          subject_type: "briefing",
          subject_id: briefing_id,
          payload: {meeting_id: meeting_id, version_id: version_id, version_number: 1},
          correlation_id: correlation_id,
          occurred_at: now
        )
      end

      fetch(id: briefing_id, workspace: workspace)
    end

    def create_version(id:, attributes:, workspace:, actor:)
      expected_lock_version = expected_lock_version(attributes)
      change_summary = optional_text(attributes["change_summary"], limit: 500)
      sections = normalize_sections(attributes["sections"], workspace: workspace)
      db = Database.db

      db.transaction do
        briefing = db[:briefings].where(id: id, workspace_id: workspace[:id]).first
        return nil unless briefing

        verify_lock!(briefing, expected_lock_version)
        if briefing[:status] == "in_review"
          raise StateError.new("A briefing under review cannot be edited.", current_status: briefing[:status])
        end

        now = Time.now.utc
        next_version_number = briefing[:current_version_number] + 1
        correlation_id = SecureRandom.uuid
        update_projection!(
          briefing: briefing,
          status: "draft",
          version_number: next_version_number,
          occurred_at: now
        )
        version_id = insert_version(
          briefing_id: id,
          actor: actor,
          version_number: next_version_number,
          status: "draft",
          change_summary: change_summary,
          sections: sections,
          occurred_at: now
        )
        write_audit(
          workspace: workspace,
          actor: actor,
          event_type: "briefing.version_created",
          subject_type: "briefing",
          subject_id: id,
          payload: {
            version_id: version_id,
            version_number: next_version_number,
            previous_version_number: briefing[:current_version_number],
            section_count: sections.length
          },
          correlation_id: correlation_id,
          occurred_at: now
        )
      end

      fetch(id: id, workspace: workspace)
    end

    def generate_version(id:, attributes:, workspace:, actor:, router: nil)
      expected = expected_lock_version(attributes)
      strategy = optional_text(attributes["retrieval_strategy"], limit: 40) || "linked_recency"
      unless RETRIEVAL_STRATEGIES.include?(strategy)
        raise ValidationError, {"retrieval_strategy" => "Select linked/recency, semantic, hybrid, or fused retrieval."}
      end
      db = Database.db
      briefing = db[:briefings].where(id: id, workspace_id: workspace[:id]).first
      return nil unless briefing

      verify_lock!(briefing, expected)
      ensure_editable!(briefing)
      manifest = BriefingContextAssembler.new(workspace: workspace, strategy: strategy).call(briefing: briefing)
      outcome = BriefingGeneration.generate(manifest: manifest, router: router)
      unless outcome.status == "succeeded"
        record_generation_failure(
          briefing: briefing,
          workspace: workspace,
          actor: actor,
          outcome: outcome,
          manifest: manifest
        )
        raise GenerationError.new(
          outcome.failure_reason || "Briefing generation failed.",
          provider: outcome.provider,
          model: outcome.model,
          validation_errors: outcome.validation_errors
        )
      end

      db.transaction do
        briefing = db[:briefings].where(id: id, workspace_id: workspace[:id]).first
        return nil unless briefing

        verify_lock!(briefing, expected)
        ensure_editable!(briefing)
        now = Time.now.utc
        next_version_number = briefing[:current_version_number] + 1
        correlation_id = SecureRandom.uuid
        update_projection!(
          briefing: briefing,
          status: "draft",
          version_number: next_version_number,
          occurred_at: now
        )
        version_id = insert_version(
          briefing_id: id,
          actor: actor,
          version_number: next_version_number,
          status: "draft",
          change_summary: case strategy
          when "semantic"
            "AI-generated draft using semantic workspace retrieval."
          when "hybrid"
            "AI-generated draft using attendee-balanced hybrid retrieval."
          when "fused"
            "AI-generated draft using fused lexical, semantic, attendee, and recency retrieval."
          else
            "AI-generated draft using linked and recent workspace context."
          end,
          sections: outcome.sections,
          occurred_at: now,
          generation: generation_metadata(outcome: outcome, manifest: manifest)
        )
        write_audit(
          workspace: workspace,
          actor: actor,
          event_type: "briefing.generated",
          subject_type: "briefing",
          subject_id: id,
          payload: generation_audit_payload(
            outcome: outcome,
            manifest: manifest,
            version_id: version_id,
            version_number: next_version_number
          ),
          correlation_id: correlation_id,
          occurred_at: now
        )
      end

      fetch(id: id, workspace: workspace)
    rescue AI::ConfigurationError, AI::ProviderError, AI::TransientError => error
      raise GenerationError.new(
        "Semantic retrieval failed: #{error.message}",
        provider: ENV.fetch("AI_EMBEDDING_PROVIDER", "fake"),
        model: ENV.fetch("AI_EMBEDDING_MODEL", "unconfigured"),
        validation_errors: {}
      )
    end

    def evaluate_version(id:, attributes:, workspace:, actor:)
      version_number = Integer(attributes["version_number"], exception: false)
      useful_claims = Integer(attributes["useful_cited_claims"], exception: false)
      raise ValidationError, {"version_number" => "Select a generated version."} unless version_number&.positive?
      raise ValidationError, {"useful_cited_claims" => "Enter a non-negative useful claim count."} unless useful_claims&.>= 0

      db = Database.db
      briefing = db[:briefings].where(id: id, workspace_id: workspace[:id]).first
      return nil unless briefing
      version = db[:briefing_versions].where(briefing_id: id, version_number: version_number).first
      raise ValidationError, {"version_number" => "Select a generated version."} unless version&.fetch(:retrieval_strategy, nil)
      if useful_claims > version[:cited_claim_count].to_i
        raise ValidationError, {"useful_cited_claims" => "Useful claims cannot exceed the #{version[:cited_claim_count]} cited claims."}
      end

      now = Time.now.utc
      db.transaction do
        db[:briefing_versions].where(id: version[:id]).update(useful_cited_claims: useful_claims)
        write_audit(
          workspace: workspace,
          actor: actor,
          event_type: "briefing.generation_evaluated",
          subject_type: "briefing",
          subject_id: id,
          payload: {
            version_id: version[:id],
            version_number: version_number,
            retrieval_strategy: version[:retrieval_strategy],
            useful_cited_claims: useful_claims,
            cited_claim_count: version[:cited_claim_count]
          },
          correlation_id: SecureRandom.uuid,
          occurred_at: now
        )
      end
      fetch(id: id, workspace: workspace)
    end

    def submit_for_review(id:, attributes:, workspace:, actor:)
      expected_lock_version = expected_lock_version(attributes)
      db = Database.db

      db.transaction do
        briefing = db[:briefings].where(id: id, workspace_id: workspace[:id]).first
        return nil unless briefing

        verify_lock!(briefing, expected_lock_version)
        unless briefing[:status] == "draft"
          raise StateError.new("Only a draft briefing can be submitted for review.", current_status: briefing[:status])
        end

        now = Time.now.utc
        correlation_id = SecureRandom.uuid
        update_projection!(briefing: briefing, status: "in_review", occurred_at: now)
        current_version_dataset(briefing).update(status: "in_review")
        write_audit(
          workspace: workspace,
          actor: actor,
          event_type: "briefing.submitted_for_review",
          subject_type: "briefing",
          subject_id: id,
          payload: {version_number: briefing[:current_version_number]},
          correlation_id: correlation_id,
          occurred_at: now
        )
      end

      fetch(id: id, workspace: workspace)
    end

    def review(id:, attributes:, workspace:, actor:)
      expected_lock_version = expected_lock_version(attributes)
      decision = optional_text(attributes["decision"], limit: 40)
      notes = optional_text(attributes["notes"], limit: 4_000)
      errors = {}
      errors["decision"] = "Select approve or request changes." unless %w[approved changes_requested].include?(decision)
      errors["notes"] = "Explain the requested changes." if decision == "changes_requested" && notes.nil?
      raise ValidationError, errors unless errors.empty?

      db = Database.db
      db.transaction do
        briefing = db[:briefings].where(id: id, workspace_id: workspace[:id]).first
        return nil unless briefing

        verify_lock!(briefing, expected_lock_version)
        unless briefing[:status] == "in_review"
          raise StateError.new("Only a briefing under review can receive a decision.", current_status: briefing[:status])
        end

        version = current_version_dataset(briefing).first
        if version[:review_decision]
          raise StateError.new("This briefing version already has a review decision.", current_status: briefing[:status])
        end

        now = Time.now.utc
        correlation_id = SecureRandom.uuid
        update_projection!(briefing: briefing, status: decision, occurred_at: now)
        db[:briefing_versions].where(id: version[:id]).update(
          status: decision,
          review_decision: decision,
          review_notes: notes,
          reviewed_by_workspace_member_id: actor[:id],
          reviewed_at: now
        )
        write_audit(
          workspace: workspace,
          actor: actor,
          event_type: "briefing.#{decision}",
          subject_type: "briefing",
          subject_id: id,
          payload: {
            version_id: version[:id],
            version_number: briefing[:current_version_number],
            decision: decision
          },
          correlation_id: correlation_id,
          occurred_at: now
        )
      end

      fetch(id: id, workspace: workspace)
    end

    def normalize_meeting(attributes)
      errors = {}
      title = required_text(attributes["title"], "Meeting title", errors, "title", limit: 200)
      starts_at = parse_time(attributes["starts_at"])
      ends_at = parse_time(attributes["ends_at"])
      errors["starts_at"] = "Enter a valid meeting start time." unless starts_at
      errors["ends_at"] = "Enter a valid meeting end time." unless ends_at
      errors["ends_at"] = "Meeting end time must be after the start time." if starts_at && ends_at && ends_at <= starts_at
      raise ValidationError, errors unless errors.empty?

      {
        title: title,
        starts_at: starts_at,
        ends_at: ends_at,
        location: optional_text(attributes["location"], limit: 500)
      }
    end

    def expected_schedule_lock_version(attributes)
      value = Integer(attributes["expected_request_lock_version"], exception: false)
      unless value&.positive?
        raise ValidationError, {
          "expected_request_lock_version" => "Expected proposed meeting lock version must be a positive integer."
        }
      end
      value
    end

    def normalize_sections(value, workspace:)
      errors = {}
      unless value.is_a?(Array) && value.any?
        raise ValidationError, {"sections" => "Include at least one briefing section."}
      end
      if value.length > 20
        raise ValidationError, {"sections" => "Include no more than 20 briefing sections."}
      end

      sections = value.each_with_index.map do |section, index|
        unless section.is_a?(Hash)
          errors["sections.#{index}"] = "Section must be an object."
          next
        end

        section_type = optional_text(section["section_type"], limit: 40)
        unless SECTION_TYPES.include?(section_type)
          errors["sections.#{index}.section_type"] = "Select a valid section type."
        end
        title = required_text(section["title"], "Section title", errors, "sections.#{index}.title", limit: 160)
        body = optional_text(section["body"], limit: 20_000) || ""
        sources = normalize_sources(section["sources"], index: index, workspace: workspace, errors: errors)
        next unless SECTION_TYPES.include?(section_type) && title

        {section_type: section_type, title: title, body: body, items: [], sources: sources}
      end.compact

      raise ValidationError, errors unless errors.empty?
      sections
    end

    def normalize_sources(value, index:, workspace:, errors:)
      return [] if value.nil?
      unless value.is_a?(Array)
        errors["sections.#{index}.sources"] = "Sources must be a list."
        return []
      end
      if value.length > 25
        errors["sections.#{index}.sources"] = "Attach no more than 25 sources to one section."
        return []
      end

      value.each_with_index.filter_map do |source, source_index|
        unless source.is_a?(Hash)
          errors["sections.#{index}.sources.#{source_index}"] = "Source must be an object."
          next
        end

        source_type = optional_text(source["source_type"], limit: 40)
        source_id = optional_text(source["source_id"], limit: 64)
        snapshot = source_type && source_id && source_snapshot(source_type: source_type, source_id: source_id, workspace: workspace)
        unless snapshot
          errors["sections.#{index}.sources.#{source_index}"] = "Select a valid workspace source."
          next
        end
        snapshot
      end.uniq { |source| [source[:source_type], source[:source_id]] }
    end

    def source_catalog(meeting:, workspace:)
      request_id = meeting[:scheduling_request_id]
      request = Database.db[:scheduling_requests].where(id: request_id, workspace_id: workspace[:id]).first
      context = Relationships.context_for_request(request_id: request_id, workspace: workspace)
      references = [
        request && {
          source_type: "scheduling_request",
          source_id: request_id,
          source_label: "Scheduling request: #{request[:requester_name]}",
          source_excerpt: request[:purpose]
        },
        {
          source_type: "meeting",
          source_id: meeting[:id],
          source_label: "Meeting: #{meeting[:title]}",
          source_excerpt: [meeting[:starts_at]&.iso8601, meeting[:ends_at]&.iso8601, meeting[:location]].compact.join(" | ")
        }
      ]
      references.concat(context[:people].map do |person|
        person_context = [person[:job_title], person.dig(:organization, :name)].compact.join(", ")
        {
          source_type: "person",
          source_id: person[:id],
          source_label: person[:display_name],
          source_excerpt: person_context.empty? ? person[:primary_email] : person_context
        }
      end)
      references.concat(context[:organizations].map do |organization|
        {
          source_type: "organization",
          source_id: organization[:id],
          source_label: organization[:name],
          source_excerpt: organization[:notes] || organization[:website_url]
        }
      end)
      references.concat(context[:interactions].map do |interaction|
        {
          source_type: "interaction",
          source_id: interaction[:id],
          source_label: "#{humanize(interaction[:interaction_type])} with #{interaction.dig(:person, :display_name) || "unknown person"}",
          source_excerpt: interaction[:summary]
        }
      end)
      references.compact.uniq { |source| [source[:source_type], source[:source_id]] }
    end

    def source_snapshot(source_type:, source_id:, workspace:)
      return nil unless SOURCE_TYPES.include?(source_type)

      db = Database.db
      case source_type
      when "scheduling_request"
        request = db[:scheduling_requests].where(id: source_id, workspace_id: workspace[:id]).first
        request && {
          source_type: source_type,
          source_id: source_id,
          source_label: "Scheduling request: #{request[:requester_name]}",
          source_excerpt: request[:purpose]
        }
      when "meeting"
        meeting = db[:meetings].where(id: source_id, workspace_id: workspace[:id]).first
        meeting && {
          source_type: source_type,
          source_id: source_id,
          source_label: "Meeting: #{meeting[:title]}",
          source_excerpt: [meeting[:starts_at]&.iso8601, meeting[:ends_at]&.iso8601, meeting[:location]].compact.join(" | ")
        }
      when "person"
        person = db[:people].where(id: source_id, workspace_id: workspace[:id]).first
        organization = person && person[:organization_id] && db[:organizations]
          .where(id: person[:organization_id], workspace_id: workspace[:id])
          .first
        context = [person&.fetch(:job_title, nil), organization&.fetch(:name, nil)].compact.join(", ")
        person && {
          source_type: source_type,
          source_id: source_id,
          source_label: person[:display_name],
          source_excerpt: context.empty? ? person[:primary_email] : context
        }
      when "organization"
        organization = db[:organizations].where(id: source_id, workspace_id: workspace[:id]).first
        organization && {
          source_type: source_type,
          source_id: source_id,
          source_label: organization[:name],
          source_excerpt: organization[:notes] || organization[:website_url]
        }
      when "interaction"
        interaction = db[:interactions].where(id: source_id, workspace_id: workspace[:id]).first
        person = interaction && db[:people]
          .where(id: interaction[:person_id], workspace_id: workspace[:id])
          .first
        interaction && {
          source_type: source_type,
          source_id: source_id,
          source_label: "#{humanize(interaction[:interaction_type])} with #{person&.fetch(:display_name, "unknown person")}",
          source_excerpt: interaction[:summary]
        }
      end
    end

    def initial_sections(request:, meeting:, context:, workspace:)
      request_source = source_snapshot(source_type: "scheduling_request", source_id: request[:id], workspace: workspace)
      person_sources = context[:people].filter_map do |person|
        source_snapshot(source_type: "person", source_id: person[:id], workspace: workspace)
      end
      organization_sources = context[:organizations].filter_map do |organization|
        source_snapshot(source_type: "organization", source_id: organization[:id], workspace: workspace)
      end
      prior_interactions = context[:interactions].reject { |interaction| interaction[:current_request] }
      interaction_sources = prior_interactions.filter_map do |interaction|
        source_snapshot(source_type: "interaction", source_id: interaction[:id], workspace: workspace)
      end

      attendee_lines = context[:people].map do |person|
        organization = person[:organization]
        role_context = [person[:job_title], organization && organization[:name]].compact.join(", ")
        suffix = role_context.empty? ? "" : " - #{role_context}"
        "#{person[:display_name]}#{suffix} (#{humanize(person[:request_role] || "participant")})"
      end
      relationship_lines = context[:people].map do |person|
        organization_name = person.dig(:organization, :name) || "No organization"
        "#{person[:display_name]}: #{organization_name}; #{person[:interaction_count]} recorded interactions"
      end
      history_lines = prior_interactions.map do |interaction|
        "#{interaction[:occurred_at][0, 10]} - #{interaction[:summary]}"
      end
      logistics = [
        "Starts: #{meeting[:starts_at].iso8601}",
        "Ends: #{meeting[:ends_at].iso8601}",
        "Location: #{meeting[:location] || "Not specified"}"
      ]

      [
        {
          section_type: "overview",
          title: "Meeting overview",
          body: "#{request[:purpose]}\n\nDuration: #{request[:requested_duration_minutes]} minutes",
          sources: [request_source].compact
        },
        {
          section_type: "attendees",
          title: "Attendees",
          body: attendee_lines.join("\n"),
          sources: (person_sources + organization_sources).uniq { |source| [source[:source_type], source[:source_id]] }
        },
        {
          section_type: "relationship_context",
          title: "Relationship context",
          body: relationship_lines.join("\n"),
          sources: (person_sources + organization_sources).uniq { |source| [source[:source_type], source[:source_id]] }
        },
        {
          section_type: "prior_history",
          title: "Prior history",
          body: history_lines.join("\n"),
          sources: interaction_sources
        },
        {section_type: "objectives", title: "Objectives and talking points", body: "", sources: []},
        {
          section_type: "logistics",
          title: "Logistics",
          body: logistics.join("\n"),
          sources: [request_source].compact
        }
      ]
    end

    def insert_version(briefing_id:, actor:, version_number:, status:, change_summary:, sections:, occurred_at:, generation: nil)
      db = Database.db
      version_id = SecureRandom.uuid
      db[:briefing_versions].insert(
        id: version_id,
        briefing_id: briefing_id,
        created_by_workspace_member_id: actor[:id],
        version_number: version_number,
        status: status,
        change_summary: change_summary,
        **(generation || {}),
        created_at: occurred_at
      )
      sections.each_with_index do |section, position|
        section_id = SecureRandom.uuid
        db[:briefing_sections].insert(
          id: section_id,
          briefing_version_id: version_id,
          section_type: section[:section_type],
          title: section[:title],
          body: section[:body],
          position: position,
          sources_json: JSON.generate(section[:sources]),
          items_json: JSON.generate(section[:items] || []),
          created_at: occurred_at
        )
      end
      version_id
    end

    def update_projection!(briefing:, status:, occurred_at:, version_number: briefing[:current_version_number])
      db = Database.db
      updated = db[:briefings]
        .where(id: briefing[:id], lock_version: briefing[:lock_version], status: briefing[:status])
        .update(
          status: status,
          current_version_number: version_number,
          lock_version: briefing[:lock_version] + 1,
          updated_at: occurred_at
        )
      return unless updated.zero?

      raise ConflictError.new(db[:briefings].where(id: briefing[:id]).first)
    end

    def ensure_editable!(briefing)
      return unless briefing[:status] == "in_review"

      raise StateError.new("A briefing under review cannot be regenerated.", current_status: briefing[:status])
    end

    def record_generation_failure(briefing:, workspace:, actor:, outcome:, manifest:)
      now = Time.now.utc
      Database.db.transaction do
        write_audit(
          workspace: workspace,
          actor: actor,
          event_type: "briefing.generation_failed",
          subject_type: "briefing",
          subject_id: briefing[:id],
          payload: generation_audit_payload(outcome: outcome, manifest: manifest),
          correlation_id: SecureRandom.uuid,
          occurred_at: now
        )
      end
    end

    def generation_audit_payload(outcome:, manifest:, version_id: nil, version_number: nil)
      {
        provider: outcome.provider,
        model: outcome.model,
        prompt_version: BriefingGeneration::PROMPT_VERSION,
        context_version: manifest["context_version"],
        provider_request_id: outcome.provider_request_id,
        attempt_count: outcome.attempt_count,
        input_tokens: outcome.input_tokens,
        output_tokens: outcome.output_tokens,
        duration_ms: outcome.duration_ms,
        failure_reason: outcome.failure_reason,
        validation_errors: outcome.validation_errors,
        retrieval: manifest["retrieval"],
        version_id: version_id,
        version_number: version_number
      }.compact
    end

    def generation_metadata(outcome:, manifest:)
      {
        retrieval_strategy: manifest.dig("retrieval", "strategy"),
        generation_provider: outcome.provider,
        generation_model: outcome.model,
        prompt_version: BriefingGeneration::PROMPT_VERSION,
        context_version: manifest["context_version"],
        provider_request_id: outcome.provider_request_id,
        attempt_count: outcome.attempt_count,
        input_tokens: outcome.input_tokens,
        output_tokens: outcome.output_tokens,
        duration_ms: outcome.duration_ms,
        retrieval_json: JSON.generate(manifest["retrieval"]),
        cited_claim_count: count_cited_claims(outcome.sections)
      }
    end

    def count_cited_claims(sections)
      sections.sum do |section|
        items = section[:items] || []
        if items.any?
          next items.count { |item| Array(item[:sources]).any? }
        end
        next 0 if section[:sources].nil? || section[:sources].empty?

        section[:body].to_s.lines.sum do |line|
          normalized = line.strip.sub(/\A[-*]\s+/, "")
          next 0 if normalized.empty?

          [normalized.split(/(?<=[.!?])\s+/).length, 1].max
        end
      end
    end

    def verify_lock!(briefing, expected)
      raise ConflictError.new(briefing) unless briefing[:lock_version] == expected
    end

    def current_version_dataset(briefing)
      Database.db[:briefing_versions].where(
        briefing_id: briefing[:id],
        version_number: briefing[:current_version_number]
      )
    end

    def expected_lock_version(attributes)
      value = Integer(attributes["expected_lock_version"], exception: false)
      raise ValidationError, {"expected_lock_version" => "Expected lock version must be a positive integer."} unless value&.positive?
      value
    end

    def serialize_list_item(briefing, meeting:, request:, section_count:)
      {
        id: briefing[:id],
        status: briefing[:status],
        lock_version: briefing[:lock_version],
        current_version_number: briefing[:current_version_number],
        meeting: serialize_meeting(meeting),
        requester_name: request[:requester_name],
        requester_organization: request[:requester_organization],
        purpose: request[:purpose],
        section_count: section_count,
        updated_at: iso8601(briefing[:updated_at])
      }
    end

    def serialize_detail(briefing, include_history: true, include_source_catalog: true)
      db = Database.db
      meeting = db[:meetings].where(id: briefing[:meeting_id]).first
      request = db[:scheduling_requests].where(id: meeting[:scheduling_request_id]).first
      version_rows = db[:briefing_versions]
        .where(briefing_id: briefing[:id])
        .reverse_order(:version_number)
        .all
      loaded_version_rows = include_history ? version_rows : version_rows.select do |version|
        version[:version_number] == briefing[:current_version_number]
      end
      member_ids = (
        [request[:assigned_scheduler_member_id], briefing[:created_by_workspace_member_id]] +
        version_rows.flat_map { |version| [version[:created_by_workspace_member_id], version[:reviewed_by_workspace_member_id]] }
      ).compact.uniq
      members_by_id = db[:workspace_members]
        .where(id: member_ids)
        .all
        .to_h { |member| [member[:id], member] }
      section_rows_by_version = db[:briefing_sections]
        .where(briefing_version_id: loaded_version_rows.map { |version| version[:id] })
        .order(:briefing_version_id, :position)
        .all
        .group_by { |section| section[:briefing_version_id] }
      versions = loaded_version_rows.map do |version|
        serialize_version(
          version,
          members_by_id: members_by_id,
          sections: section_rows_by_version.fetch(version[:id], [])
        )
      end
      version_summaries = version_rows.map do |version|
        serialize_version_summary(version, members_by_id: members_by_id)
      end

      {
        id: briefing[:id],
        detail_level: include_history && include_source_catalog ? "full" : "current",
        status: briefing[:status],
        lock_version: briefing[:lock_version],
        current_version_number: briefing[:current_version_number],
        meeting: serialize_meeting(meeting),
        request: {
          id: request[:id],
          requester_name: request[:requester_name],
          requester_organization: request[:requester_organization],
          purpose: request[:purpose],
          status: request[:status],
          assigned_scheduler: serialize_member(members_by_id[request[:assigned_scheduler_member_id]])
        },
        created_by: serialize_member(members_by_id[briefing[:created_by_workspace_member_id]]),
        tasks: Tasks.for_meeting(meeting_id: meeting[:id], workspace: {id: briefing[:workspace_id]}),
        versions: versions,
        version_summaries: version_summaries,
        source_catalog: include_source_catalog ? source_catalog(meeting: meeting, workspace: {id: briefing[:workspace_id]}) : [],
        created_at: iso8601(briefing[:created_at]),
        updated_at: iso8601(briefing[:updated_at])
      }
    end

    def serialize_meeting(meeting)
      {
        id: meeting[:id],
        scheduling_request_id: meeting[:scheduling_request_id],
        title: meeting[:title],
        starts_at: iso8601(meeting[:starts_at]),
        ends_at: iso8601(meeting[:ends_at]),
        location: meeting[:location]
      }
    end

    def serialize_version(version, members_by_id:, sections:)
      author = members_by_id[version[:created_by_workspace_member_id]]
      reviewer = members_by_id[version[:reviewed_by_workspace_member_id]]
      {
        id: version[:id],
        version_number: version[:version_number],
        status: version[:status],
        change_summary: version[:change_summary],
        created_by: serialize_member(author),
        review: version[:review_decision] && {
          decision: version[:review_decision],
          notes: version[:review_notes],
          reviewed_by: serialize_member(reviewer),
          reviewed_at: iso8601(version[:reviewed_at])
        },
        generation: version[:retrieval_strategy] && {
          retrieval_strategy: version[:retrieval_strategy],
          provider: version[:generation_provider],
          model: version[:generation_model],
          prompt_version: version[:prompt_version],
          context_version: version[:context_version],
          input_tokens: version[:input_tokens],
          output_tokens: version[:output_tokens],
          duration_ms: version[:duration_ms],
          cited_claim_count: version[:cited_claim_count],
          useful_cited_claims: version[:useful_cited_claims],
          useful_claims_per_1k_input_tokens: useful_claims_per_1k_tokens(version),
          retrieval: parse_json_object(version[:retrieval_json])
        },
        sections: sections.map { |section| serialize_section(section) },
        created_at: iso8601(version[:created_at])
      }
    end

    def serialize_version_summary(version, members_by_id:)
      {
        id: version[:id],
        version_number: version[:version_number],
        status: version[:status],
        change_summary: version[:change_summary],
        created_by: serialize_member(members_by_id[version[:created_by_workspace_member_id]]),
        created_at: iso8601(version[:created_at])
      }
    end

    def serialize_section(section)
      {
        id: section[:id],
        section_type: section[:section_type],
        title: section[:title],
        body: section[:body],
        position: section[:position],
        items: parse_items(section[:items_json]),
        sources: parse_sources(section[:sources_json])
      }
    end

    def parse_items(value)
      JSON.parse(value || "[]").filter_map do |item|
        next unless item.is_a?(Hash) && item["text"].is_a?(String)

        {
          label: item["label"].to_s,
          text: item["text"],
          sources: Array(item["sources"]).filter_map do |source|
            next unless source.is_a?(Hash)
            {
              source_type: source["source_type"], source_id: source["source_id"],
              source_label: source["source_label"], source_excerpt: source["source_excerpt"]
            }
          end
        }
      end
    rescue JSON::ParserError
      []
    end

    def parse_sources(value)
      JSON.parse(value || "[]").filter_map do |source|
        next unless source.is_a?(Hash)

        {
          source_type: source["source_type"],
          source_id: source["source_id"],
          source_label: source["source_label"],
          source_excerpt: source["source_excerpt"]
        }
      end
    rescue JSON::ParserError
      []
    end

    def parse_json_object(value)
      parsed = JSON.parse(value || "{}")
      parsed.is_a?(Hash) ? parsed : {}
    rescue JSON::ParserError
      {}
    end

    def useful_claims_per_1k_tokens(version)
      return nil unless version[:useful_cited_claims] && version[:input_tokens].to_i.positive?

      ((version[:useful_cited_claims].to_f / version[:input_tokens]) * 1_000).round(2)
    end

    def write_audit(workspace:, actor:, event_type:, subject_type:, subject_id:, payload:, correlation_id:, occurred_at:)
      Database.db[:audit_events].insert(
        id: SecureRandom.uuid,
        workspace_id: workspace[:id],
        actor_workspace_member_id: actor[:id],
        event_type: event_type,
        subject_type: subject_type,
        subject_id: subject_id,
        payload: JSON.generate(payload),
        correlation_id: correlation_id,
        occurred_at: occurred_at
      )
    end

    def required_text(value, label, errors, key, limit:)
      normalized = optional_text(value, limit: limit)
      errors[key] = "#{label} is required." unless normalized
      normalized
    end

    def optional_text(value, limit:)
      return nil unless value.is_a?(String)

      normalized = value.strip
      return nil if normalized.empty?
      normalized[0, limit]
    end

    def parse_time(value)
      return nil unless value.is_a?(String) && !value.strip.empty?
      Time.iso8601(value).utc
    rescue ArgumentError
      nil
    end

    def humanize(value)
      value.to_s.split("_").map(&:capitalize).join(" ")
    end

    def serialize_member(member)
      member && {id: member[:id], display_name: member[:display_name]}
    end

    def iso8601(value)
      value&.iso8601
    end
  end
end
