# frozen_string_literal: true

require "json"
require "securerandom"
require "time"
require_relative "database"
require_relative "relationships"

module Holocron
  module Briefings
    STATUSES = %w[draft in_review approved changes_requested].freeze
    SECTION_TYPES = %w[overview attendees relationship_context prior_history objectives logistics notes].freeze
    SOURCE_TYPES = %w[scheduling_request person organization interaction].freeze

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

    module_function

    def list(workspace:)
      Database.db[:briefings]
        .where(workspace_id: workspace[:id])
        .reverse_order(:updated_at)
        .all
        .map { |briefing| serialize_list_item(briefing) }
    end

    def fetch(id:, workspace:)
      briefing = Database.db[:briefings].where(id: id, workspace_id: workspace[:id]).first
      briefing && serialize_detail(briefing)
    end

    def create_for_request(request_id:, attributes:, workspace:, actor:)
      meeting_attributes = normalize_meeting(attributes)
      db = Database.db
      briefing_id = SecureRandom.uuid

      db.transaction do
        request = db[:scheduling_requests].where(id: request_id, workspace_id: workspace[:id]).first
        return nil unless request

        unless request[:status] == "scheduled"
          raise StateError.new("Only a scheduled request can produce a meeting and briefing.", current_status: request[:status])
        end

        if db[:meetings].where(scheduling_request_id: request_id).any?
          raise StateError.new("This scheduling request already has a meeting and briefing.", current_status: request[:status])
        end

        now = Time.now.utc
        correlation_id = SecureRandom.uuid
        meeting_id = SecureRandom.uuid
        context = Relationships.context_for_request(request_id: request_id, workspace: workspace)

        db[:meetings].insert(
          id: meeting_id,
          workspace_id: workspace[:id],
          scheduling_request_id: request_id,
          created_by_workspace_member_id: actor[:id],
          **meeting_attributes,
          created_at: now,
          updated_at: now
        )
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

        write_audit(
          workspace: workspace,
          actor: actor,
          event_type: "meeting.created",
          subject_type: "meeting",
          subject_id: meeting_id,
          payload: {scheduling_request_id: request_id, briefing_id: briefing_id},
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

        {section_type: section_type, title: title, body: body, sources: sources}
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
      context = Relationships.context_for_request(request_id: request_id, workspace: workspace)
      references = [{source_type: "scheduling_request", source_id: request_id}]
      references.concat(context[:people].map { |person| {source_type: "person", source_id: person[:id]} })
      references.concat(context[:organizations].map { |organization| {source_type: "organization", source_id: organization[:id]} })
      references.concat(context[:interactions].map { |interaction| {source_type: "interaction", source_id: interaction[:id]} })
      references.filter_map do |reference|
        source_snapshot(**reference, workspace: workspace)
      end.uniq { |source| [source[:source_type], source[:source_id]] }
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
      when "person"
        person = db[:people].where(id: source_id, workspace_id: workspace[:id]).first
        organization = person && person[:organization_id] && db[:organizations].where(id: person[:organization_id]).first
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
        person = interaction && db[:people].where(id: interaction[:person_id]).first
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

    def insert_version(briefing_id:, actor:, version_number:, status:, change_summary:, sections:, occurred_at:)
      db = Database.db
      version_id = SecureRandom.uuid
      db[:briefing_versions].insert(
        id: version_id,
        briefing_id: briefing_id,
        created_by_workspace_member_id: actor[:id],
        version_number: version_number,
        status: status,
        change_summary: change_summary,
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

    def serialize_list_item(briefing)
      db = Database.db
      meeting = db[:meetings].where(id: briefing[:meeting_id]).first
      request = db[:scheduling_requests].where(id: meeting[:scheduling_request_id]).first
      version = current_version_dataset(briefing).first
      {
        id: briefing[:id],
        status: briefing[:status],
        lock_version: briefing[:lock_version],
        current_version_number: briefing[:current_version_number],
        meeting: serialize_meeting(meeting),
        requester_name: request[:requester_name],
        requester_organization: request[:requester_organization],
        purpose: request[:purpose],
        section_count: db[:briefing_sections].where(briefing_version_id: version[:id]).count,
        updated_at: iso8601(briefing[:updated_at])
      }
    end

    def serialize_detail(briefing)
      db = Database.db
      meeting = db[:meetings].where(id: briefing[:meeting_id]).first
      request = db[:scheduling_requests].where(id: meeting[:scheduling_request_id]).first
      versions = db[:briefing_versions]
        .where(briefing_id: briefing[:id])
        .reverse_order(:version_number)
        .all
        .map { |version| serialize_version(version) }
      creator = db[:workspace_members].where(id: briefing[:created_by_workspace_member_id]).first

      {
        id: briefing[:id],
        status: briefing[:status],
        lock_version: briefing[:lock_version],
        current_version_number: briefing[:current_version_number],
        meeting: serialize_meeting(meeting),
        request: {
          id: request[:id],
          requester_name: request[:requester_name],
          requester_organization: request[:requester_organization],
          purpose: request[:purpose],
          status: request[:status]
        },
        created_by: serialize_member(creator),
        versions: versions,
        source_catalog: source_catalog(meeting: meeting, workspace: {id: briefing[:workspace_id]}),
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

    def serialize_version(version)
      db = Database.db
      author = db[:workspace_members].where(id: version[:created_by_workspace_member_id]).first
      reviewer = version[:reviewed_by_workspace_member_id] && db[:workspace_members]
        .where(id: version[:reviewed_by_workspace_member_id])
        .first
      sections = db[:briefing_sections]
        .where(briefing_version_id: version[:id])
        .order(:position)
        .all
        .map { |section| serialize_section(section) }
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
        sections: sections,
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
        sources: parse_sources(section[:sources_json])
      }
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
