# frozen_string_literal: true

require "json"
require "securerandom"
require "time"
require "date"
require "uri"
require_relative "database"
require_relative "relationships"
require_relative "scheduling_request_workflow"
require_relative "tasks"

module Holocron
  module SchedulingRequests
    SOURCE_CHANNELS = %w[email phone web staff other].freeze
    PARTICIPANT_ROLES = %w[required optional staff].freeze
    EMAIL_PATTERN = URI::MailTo::EMAIL_REGEXP

    class ValidationError < StandardError
      attr_reader :fields

      def initialize(fields)
        super("Validation failed.")
        @fields = fields
      end
    end

    module_function

    def list(workspace:)
      db = Database.db
      requests = db[:scheduling_requests]
        .left_join(:workspace_members, id: :assigned_scheduler_member_id)
        .where(Sequel[:scheduling_requests][:workspace_id] => workspace[:id])
        .select_all(:scheduling_requests)
        .select_append(Sequel[:workspace_members][:display_name].as(:assigned_scheduler_name))
        .reverse_order(Sequel[:scheduling_requests][:updated_at])
        .all

      window_counts = db[:request_candidate_windows]
        .join(:scheduling_requests, id: :scheduling_request_id)
        .where(Sequel[:scheduling_requests][:workspace_id] => workspace[:id])
        .group(:scheduling_request_id)
        .select(:scheduling_request_id, Sequel.function(:count, Sequel[:request_candidate_windows][:id]).as(:count))
        .to_hash(:scheduling_request_id, :count)

      requests.map do |request|
        serialize_list_item(request, window_counts.fetch(request[:id], 0))
      end
    end

    def fetch(id:, workspace:)
      request = Database.db[:scheduling_requests]
        .where(id: id, workspace_id: workspace[:id])
        .first
      return nil unless request

      serialize_detail(request)
    end

    def create(attributes:, workspace:, principal:, actor:)
      extraction_id = request_extraction_id(attributes)
      normalization_attributes = attributes.dup
      normalization_attributes["source_channel"] = "email" if extraction_id
      normalized = normalize(normalization_attributes, workspace: workspace)
      now = Time.now.utc
      request_id = SecureRandom.uuid
      correlation_id = SecureRandom.uuid
      interaction_id = nil

      Database.db.transaction do
        extraction = extraction_id && Database.db[:request_extractions]
          .where(
            id: extraction_id,
            workspace_id: workspace[:id],
            status: "succeeded",
            scheduling_request_id: nil,
            accepted_at: nil
          )
          .first
        if extraction_id && !extraction
          raise ValidationError, {
            "request_extraction_id" => "Select a successful, unaccepted request extraction from this workspace."
          }
        end
        if extraction
          normalized[:request][:source_channel] = "email"
          normalized[:request][:original_request_text] = extraction[:input_text]
          unless attributes.key?("briefing_context")
            proposal = extraction[:output_json] && JSON.parse(extraction[:output_json])
            normalized[:request][:briefing_context_json] = JSON.generate(
              normalize_briefing_context(proposal && proposal["briefing_context"], {})
            )
          end
        end

        Database.db[:scheduling_requests].insert(
          id: request_id,
          workspace_id: workspace[:id],
          principal_id: principal[:id],
          assigned_scheduler_member_id: normalized.fetch(:assigned_scheduler_member_id),
          created_by_workspace_member_id: actor[:id],
          **normalized.fetch(:request),
          status: "submitted",
          lock_version: 1,
          created_at: now,
          updated_at: now
        )
        replace_children(request_id, normalized, now)
        interaction_id = Relationships.sync_request_context(
          request_id: request_id,
          normalized: normalized,
          workspace: workspace,
          actor: actor,
          occurred_at: now,
          correlation_id: correlation_id
        )
        SchedulingRequestWorkflow.record_initial_transition(
          request_id: request_id,
          actor: actor,
          occurred_at: now,
          correlation_id: correlation_id
        )
        write_audit_event(
          workspace: workspace,
          actor: actor,
          request_id: request_id,
          event_type: "scheduling_request.created",
          payload: audit_payload(normalized).merge(request_extraction_id: extraction_id),
          correlation_id: correlation_id,
          occurred_at: now
        )
        if extraction
          accepted = Database.db[:request_extractions]
            .where(
              id: extraction_id,
              workspace_id: workspace[:id],
              status: "succeeded",
              scheduling_request_id: nil,
              accepted_at: nil
            )
            .update(scheduling_request_id: request_id, accepted_at: now)
          if accepted.zero?
            raise ValidationError, {
              "request_extraction_id" => "This request extraction was already accepted."
            }
          end
          write_extraction_accepted_audit(
            extraction: extraction,
            workspace: workspace,
            actor: actor,
            request_id: request_id,
            correlation_id: correlation_id,
            occurred_at: now
          )
        end
      end

      SemanticIndexJobs.process_inline!(workspace: workspace, interaction_id: interaction_id)
      fetch(id: request_id, workspace: workspace)
    end

    def update(id:, attributes:, workspace:, actor:)
      existing = Database.db[:scheduling_requests].where(id: id, workspace_id: workspace[:id]).first
      return nil unless existing

      normalization_attributes = attributes.dup
      unless normalization_attributes.key?("briefing_context")
        normalization_attributes["briefing_context"] = parse_briefing_context(existing[:briefing_context_json])
      end
      normalized = normalize(normalization_attributes, workspace: workspace)
      expected_lock_version = Integer(attributes["expected_lock_version"], exception: false)
      unless expected_lock_version&.positive?
        raise ValidationError, {"expected_lock_version" => "Expected lock version must be a positive integer."}
      end
      now = Time.now.utc
      correlation_id = SecureRandom.uuid
      interaction_id = nil

      Database.db.transaction do
        request = Database.db[:scheduling_requests].where(id: id, workspace_id: workspace[:id]).first
        return nil unless request

        if request[:lock_version] != expected_lock_version
          raise SchedulingRequestWorkflow::ConflictError.new(
            current_lock_version: request[:lock_version],
            current_status: request[:status]
          )
        end

        updated = Database.db[:scheduling_requests]
          .where(id: id, workspace_id: workspace[:id], lock_version: expected_lock_version)
          .update(
          assigned_scheduler_member_id: normalized.fetch(:assigned_scheduler_member_id),
          **normalized.fetch(:request),
          lock_version: expected_lock_version + 1,
          updated_at: now
        )
        if updated.zero?
          current = Database.db[:scheduling_requests].where(id: id, workspace_id: workspace[:id]).first
          raise SchedulingRequestWorkflow::ConflictError.new(
            current_lock_version: current&.fetch(:lock_version),
            current_status: current&.fetch(:status)
          )
        end
        replace_children(id, normalized, now)
        interaction_id = Relationships.sync_request_context(
          request_id: id,
          normalized: normalized,
          workspace: workspace,
          actor: actor,
          occurred_at: now,
          correlation_id: correlation_id
        )
        write_audit_event(
          workspace: workspace,
          actor: actor,
          request_id: id,
          event_type: "scheduling_request.updated",
          payload: audit_payload(normalized),
          correlation_id: correlation_id,
          occurred_at: now
        )
      end

      SemanticIndexJobs.process_inline!(workspace: workspace, interaction_id: interaction_id)
      fetch(id: id, workspace: workspace)
    end

    def serialize_detail(request)
      db = Database.db
      scheduler = db[:workspace_members].where(id: request[:assigned_scheduler_member_id]).first
      participants = db[:request_participants]
        .where(scheduling_request_id: request[:id])
        .order(:created_at)
        .all
        .map { |participant| serialize_participant(participant) }
      candidate_windows = db[:request_candidate_windows]
        .where(scheduling_request_id: request[:id])
        .order(:position)
        .all
        .map { |window| serialize_candidate_window(window) }
      audit_events = db[:audit_events]
        .where(subject_type: "scheduling_request", subject_id: request[:id])
        .reverse_order(:occurred_at)
        .all
        .map { |event| serialize_audit_event(event) }
      transitions = serialize_transitions(request[:id])
      extraction = db[:request_extractions].where(scheduling_request_id: request[:id]).first
      meeting = db[:meetings].where(scheduling_request_id: request[:id]).first
      briefing = meeting && db[:briefings].where(meeting_id: meeting[:id]).first

      {
        id: request[:id],
        status: request[:status],
        lock_version: request[:lock_version],
        requester: {
          name: request[:requester_name],
          email: request[:requester_email],
          organization: request[:requester_organization]
        },
        purpose: request[:purpose],
        requested_duration_minutes: request[:requested_duration_minutes],
        preferred_location: request[:preferred_location],
        availability_notes: request[:availability_notes],
        source_channel: request[:source_channel],
        original_request_text: request[:original_request_text],
        briefing_context: parse_briefing_context(request[:briefing_context_json]),
        assigned_scheduler: scheduler && serialize_member(scheduler),
        participants: participants,
        candidate_windows: candidate_windows,
        request_extraction: extraction && {
          id: extraction[:id],
          provider: extraction[:provider],
          model: extraction[:model],
          prompt_version: extraction[:prompt_version],
          accepted_at: iso8601(extraction[:accepted_at])
        },
        briefing: briefing && {
          id: briefing[:id],
          status: briefing[:status],
          tasks: Tasks.for_meeting(meeting_id: meeting[:id], workspace: {id: request[:workspace_id]}),
          meeting: {
            id: meeting[:id],
            scheduling_request_id: meeting[:scheduling_request_id],
            title: meeting[:title],
            starts_at: iso8601(meeting[:starts_at]),
            ends_at: iso8601(meeting[:ends_at]),
            location: meeting[:location]
          }
        },
        relationship_context: Relationships.context_for_request(request_id: request[:id], workspace: {id: request[:workspace_id]}),
        available_transitions: SchedulingRequestWorkflow.available_transitions(request[:status]),
        transitions: transitions,
        audit_events: audit_events,
        created_at: iso8601(request[:created_at]),
        updated_at: iso8601(request[:updated_at])
      }
    end

    def normalize(attributes, workspace:)
      errors = {}
      request = {
        requester_name: required_text(attributes, "requester_name", "Requester name", errors, limit: 160),
        requester_email: optional_email(attributes, "requester_email", "Requester email", errors),
        requester_organization: optional_text(attributes, "requester_organization", limit: 250),
        purpose: required_text(attributes, "purpose", "Purpose", errors, limit: 2_000),
        requested_duration_minutes: duration(attributes, errors),
        preferred_location: optional_text(attributes, "preferred_location", limit: 500),
        availability_notes: optional_text(attributes, "availability_notes", limit: 4_000),
        source_channel: source_channel(attributes, errors),
        original_request_text: optional_text(attributes, "original_request_text", limit: 8_000),
        briefing_context_json: JSON.generate(normalize_briefing_context(attributes["briefing_context"], errors))
      }
      scheduler_id = assigned_scheduler_id(attributes, workspace, errors)
      participants = normalize_participants(attributes["participants"], errors)
      candidate_windows = normalize_candidate_windows(attributes["candidate_windows"], errors)

      raise ValidationError, errors unless errors.empty?

      {request: request, assigned_scheduler_member_id: scheduler_id, participants: participants, candidate_windows: candidate_windows}
    end

    def normalize_briefing_context(value, errors)
      return empty_briefing_context if value.nil?
      unless value.is_a?(Hash)
        errors["briefing_context"] = "Briefing context must be an object."
        return empty_briefing_context
      end

      agenda = value["agenda_items"]
      constraints = value["constraints"]
      deliverables = value["promised_deliverables"]
      questions = value["unresolved_questions"]
      errors["briefing_context.agenda_items"] = "Agenda items must be a list." unless agenda.is_a?(Array)
      errors["briefing_context.constraints"] = "Constraints must be a list of strings." unless string_list?(constraints)
      errors["briefing_context.promised_deliverables"] = "Promised deliverables must be a list." unless deliverables.is_a?(Array)
      errors["briefing_context.unresolved_questions"] = "Unresolved questions must be a list of strings." unless string_list?(questions)

      normalized_agenda = Array(agenda).first(12).each_with_index.filter_map do |item, index|
        unless item.is_a?(Hash)
          errors["briefing_context.agenda_items.#{index}"] = "Agenda item must be an object."
          next
        end
        dependencies = item["dependencies"]
        errors["briefing_context.agenda_items.#{index}.dependencies"] = "Dependencies must be a list of strings." unless string_list?(dependencies)
        normalized = %w[topic ask decision_needed desired_outcome owner decision_maker deadline readiness_standard evidence_excerpt].to_h do |key|
          [key, optional_text(item, key, limit: 500)]
        end
        normalized["dependencies"] = normalized_string_list(dependencies, max: 12)
        normalized
      end

      normalized_deliverables = Array(deliverables).first(12).each_with_index.filter_map do |item, index|
        unless item.is_a?(Hash)
          errors["briefing_context.promised_deliverables.#{index}"] = "Promised deliverable must be an object."
          next
        end
        deliverable = optional_text(item, "deliverable", limit: 500)
        unless deliverable
          errors["briefing_context.promised_deliverables.#{index}.deliverable"] = "Deliverable is required."
          next
        end
        {
          "deliverable" => deliverable,
          "owner" => optional_text(item, "owner", limit: 200),
          "deadline" => optional_text(item, "deadline", limit: 200),
          "status" => optional_text(item, "status", limit: 300)
        }
      end

      {
        "agenda_items" => normalized_agenda,
        "constraints" => normalized_string_list(constraints, max: 20),
        "promised_deliverables" => normalized_deliverables,
        "unresolved_questions" => normalized_string_list(questions, max: 20)
      }
    end

    def empty_briefing_context
      {"agenda_items" => [], "constraints" => [], "promised_deliverables" => [], "unresolved_questions" => []}
    end

    def string_list?(value)
      value.is_a?(Array) && value.all? { |item| item.is_a?(String) }
    end

    def normalized_string_list(value, max:)
      Array(value).filter_map { |item| item.is_a?(String) ? item.strip[0, 500] : nil }.reject(&:empty?).uniq.first(max)
    end

    def request_extraction_id(attributes)
      value = attributes["request_extraction_id"]
      return nil if value.nil? || (value.is_a?(String) && value.strip.empty?)
      unless value.is_a?(String) && value.strip.length <= 36
        raise ValidationError, {"request_extraction_id" => "Select a valid request extraction."}
      end

      value.strip
    end

    def required_text(attributes, key, label, errors, limit:)
      value = optional_text(attributes, key, limit: limit)
      errors[key] = "#{label} is required." if value.nil?
      value
    end

    def optional_text(attributes, key, limit:)
      value = attributes[key]
      return nil if value.nil?
      return nil if value.is_a?(String) && value.strip.empty?

      unless value.is_a?(String)
        return nil
      end

      normalized = value.strip
      return normalized if normalized.length <= limit

      normalized[0, limit]
    end

    def optional_email(attributes, key, label, errors)
      value = optional_text(attributes, key, limit: 254)
      return nil if value.nil?

      unless value.match?(EMAIL_PATTERN)
        errors[key] = "#{label} must be a valid email address."
        return nil
      end

      value.downcase
    end

    def duration(attributes, errors)
      value = attributes["requested_duration_minutes"]
      duration = Integer(value, exception: false)
      unless duration&.between?(15, 480)
        errors["requested_duration_minutes"] = "Duration must be between 15 and 480 minutes."
        return nil
      end
      duration
    end

    def source_channel(attributes, errors)
      value = optional_text(attributes, "source_channel", limit: 30)
      unless SOURCE_CHANNELS.include?(value)
        errors["source_channel"] = "Select a valid source channel."
        return nil
      end
      value
    end

    def assigned_scheduler_id(attributes, workspace, errors)
      id = optional_text(attributes, "assigned_scheduler_member_id", limit: 36)
      member = id && Database.db[:workspace_members]
        .where(id: id, workspace_id: workspace[:id], status: "active")
        .first
      unless member && %w[owner chief_of_staff scheduler].include?(member[:role])
        errors["assigned_scheduler_member_id"] = "Assign an active scheduling team member."
        return nil
      end
      member[:id]
    end

    def normalize_participants(value, errors)
      return [] if value.nil?
      unless value.is_a?(Array)
        errors["participants"] = "Participants must be a list."
        return []
      end
      if value.length > 25
        errors["participants"] = "Add no more than 25 participants."
        return []
      end

      value.each_with_index.map do |participant, index|
        if !participant.is_a?(Hash)
          errors["participants.#{index}"] = "Participant must be an object."
          nil
        else
          name = required_text(participant, "name", "Participant name", errors, limit: 160)
          email = optional_email(participant, "email", "Participant email", errors)
          role = optional_text(participant, "role", limit: 30)
          unless PARTICIPANT_ROLES.include?(role)
            errors["participants.#{index}.role"] = "Select a valid participant role."
          end
          name && PARTICIPANT_ROLES.include?(role) ? {
            name: name,
            email: email,
            organization: optional_text(participant, "organization", limit: 250),
            role: role
          } : nil
        end
      end.compact
    end

    def normalize_candidate_windows(value, errors)
      return [] if value.nil?
      unless value.is_a?(Array)
        errors["candidate_windows"] = "Candidate windows must be a list."
        return []
      end
      if value.length > 10
        errors["candidate_windows"] = "Add no more than 10 candidate windows."
        return []
      end

      value.each_with_index.map do |window, index|
        if !window.is_a?(Hash)
          errors["candidate_windows.#{index}"] = "Candidate window must be an object."
          nil
        else
          candidate_date = optional_text(window, "candidate_date", limit: 10)
          begin
            Date.iso8601(candidate_date) if candidate_date
          rescue ArgumentError
            candidate_date = nil
          end
          errors["candidate_windows.#{index}.candidate_date"] = "Enter a valid candidate date." unless candidate_date

          starts_input = window["starts_at"].to_s
          ends_input = window["ends_at"].to_s
          starts_at = parse_time(starts_input)
          ends_at = parse_time(ends_input)
          window_valid = candidate_date
          if starts_input.empty? != ends_input.empty?
            errors["candidate_windows.#{index}.starts_at"] = "Enter both a start and end time."
            window_valid = false
          elsif (!starts_input.empty? && !starts_at) || (!ends_input.empty? && !ends_at)
            errors["candidate_windows.#{index}.starts_at"] = "Enter valid ISO 8601 times."
            window_valid = false
          elsif starts_at && ends_at && ends_at <= starts_at
            errors["candidate_windows.#{index}.ends_at"] = "End time must be after the start time."
            window_valid = false
          end

          window_valid ? {
            candidate_date: candidate_date,
            starts_at: starts_at,
            ends_at: ends_at,
            notes: optional_text(window, "notes", limit: 1_000),
            position: index
          } : nil
        end
      end.compact
    end

    def parse_time(value)
      return nil if value.nil? || value.to_s.empty?

      Time.iso8601(value.to_s).utc
    rescue ArgumentError
      nil
    end

    def replace_children(request_id, normalized, now)
      db = Database.db
      db[:request_participants].where(scheduling_request_id: request_id).delete
      db[:request_candidate_windows].where(scheduling_request_id: request_id).delete
      normalized.fetch(:participants).each do |participant|
        db[:request_participants].insert(id: SecureRandom.uuid, scheduling_request_id: request_id, **participant, created_at: now, updated_at: now)
      end
      normalized.fetch(:candidate_windows).each do |window|
        db[:request_candidate_windows].insert(id: SecureRandom.uuid, scheduling_request_id: request_id, **window, created_at: now, updated_at: now)
      end
    end

    def write_audit_event(workspace:, actor:, request_id:, event_type:, payload:, correlation_id:, occurred_at:)
      Database.db[:audit_events].insert(
        id: SecureRandom.uuid,
        workspace_id: workspace[:id],
        actor_workspace_member_id: actor[:id],
        event_type: event_type,
        subject_type: "scheduling_request",
        subject_id: request_id,
        payload: JSON.generate(payload),
        correlation_id: correlation_id,
        occurred_at: occurred_at
      )
    end

    def write_extraction_accepted_audit(extraction:, workspace:, actor:, request_id:, correlation_id:, occurred_at:)
      Database.db[:audit_events].insert(
        id: SecureRandom.uuid,
        workspace_id: workspace[:id],
        actor_workspace_member_id: actor[:id],
        event_type: "request_extraction.accepted",
        subject_type: "request_extraction",
        subject_id: extraction[:id],
        payload: JSON.generate(
          scheduling_request_id: request_id,
          provider: extraction[:provider],
          model: extraction[:model],
          prompt_version: extraction[:prompt_version]
        ),
        correlation_id: correlation_id,
        occurred_at: occurred_at
      )
    end

    def audit_payload(normalized)
      briefing_context = parse_briefing_context(normalized.dig(:request, :briefing_context_json))
      {
        requester_name: normalized.dig(:request, :requester_name),
        purpose: normalized.dig(:request, :purpose),
        briefing_agenda_item_count: briefing_context.fetch("agenda_items").length,
        participant_count: normalized.fetch(:participants).length,
        candidate_window_count: normalized.fetch(:candidate_windows).length
      }
    end

    def serialize_list_item(request, candidate_window_count)
      {
        id: request[:id],
        status: request[:status],
        lock_version: request[:lock_version],
        requester_name: request[:requester_name],
        requester_organization: request[:requester_organization],
        purpose: request[:purpose],
        requested_duration_minutes: request[:requested_duration_minutes],
        source_channel: request[:source_channel],
        assigned_scheduler_name: request[:assigned_scheduler_name],
        candidate_window_count: candidate_window_count,
        created_at: iso8601(request[:created_at]),
        updated_at: iso8601(request[:updated_at])
      }
    end

    def serialize_transitions(request_id)
      db = Database.db
      decisions = db[:request_decisions]
        .where(scheduling_request_id: request_id)
        .to_hash(:request_state_transition_id)

      db[:request_state_transitions]
        .left_join(
          :workspace_members,
          Sequel[:workspace_members][:id] => Sequel[:request_state_transitions][:actor_workspace_member_id]
        )
        .where(Sequel[:request_state_transitions][:scheduling_request_id] => request_id)
        .select_all(:request_state_transitions)
        .select_append(Sequel[:workspace_members][:display_name].as(:actor_display_name))
        .order(Sequel[:request_state_transitions][:occurred_at])
        .all
        .map do |transition|
          decision = decisions[transition[:id]]
          {
            id: transition[:id],
            from_status: transition[:from_status],
            to_status: transition[:to_status],
            reason_code: transition[:reason_code],
            notes: transition[:notes],
            actor: transition[:actor_workspace_member_id] && {
              id: transition[:actor_workspace_member_id],
              display_name: transition[:actor_display_name]
            },
            decision: decision && {
              id: decision[:id],
              decision: decision[:decision],
              reason_code: decision[:reason_code],
              decided_by_workspace_member_id: decision[:decided_by_workspace_member_id],
              decided_at: iso8601(decision[:decided_at])
            },
            correlation_id: transition[:correlation_id],
            occurred_at: iso8601(transition[:occurred_at])
          }
        end
    end

    def serialize_member(member)
      {
        id: member[:id],
        display_name: member[:display_name],
        email: member[:email],
        job_title: member[:job_title],
        role: member[:role]
      }
    end

    def serialize_participant(participant)
      {
        id: participant[:id],
        name: participant[:name],
        email: participant[:email],
        organization: participant[:organization],
        role: participant[:role]
      }
    end

    def parse_briefing_context(value)
      parsed = value && JSON.parse(value)
      parsed.is_a?(Hash) ? empty_briefing_context.merge(parsed) : empty_briefing_context
    rescue JSON::ParserError
      empty_briefing_context
    end

    def serialize_candidate_window(window)
      {
        id: window[:id],
        candidate_date: window[:candidate_date],
        starts_at: iso8601(window[:starts_at]),
        ends_at: iso8601(window[:ends_at]),
        notes: window[:notes],
        position: window[:position]
      }
    end

    def serialize_audit_event(event)
      {
        id: event[:id],
        event_type: event[:event_type],
        payload: JSON.parse(event[:payload]),
        occurred_at: iso8601(event[:occurred_at])
      }
    end

    def iso8601(value)
      value&.iso8601
    end
  end
end
