# frozen_string_literal: true

require "json"
require "securerandom"
require "time"
require_relative "database"

module Holocron
  module SchedulingRequestWorkflow
    STATES = %w[submitted needs_information under_review approved declined scheduled].freeze

    TRANSITIONS = {
      "submitted" => [
        {
          to_status: "under_review",
          label: "Start review",
          reasons: [
            {code: "review_started", label: "Ready for review"},
            {code: "priority_review", label: "Priority review"}
          ]
        },
        {
          to_status: "needs_information",
          label: "Request information",
          reasons: [
            {code: "missing_attendee_details", label: "Missing attendee details"},
            {code: "missing_availability", label: "Missing availability"},
            {code: "scope_clarification", label: "Purpose needs clarification"},
            {code: "other_information_needed", label: "Other information needed"}
          ]
        },
        {
          to_status: "declined",
          label: "Decline",
          reasons: [
            {code: "outside_scope", label: "Outside office scope"},
            {code: "insufficient_priority", label: "Insufficient priority"},
            {code: "duplicate_request", label: "Duplicate request"},
            {code: "scheduling_conflict", label: "Scheduling conflict"},
            {code: "other_decline_reason", label: "Other reason"}
          ]
        }
      ],
      "needs_information" => [
        {
          to_status: "submitted",
          label: "Information received",
          reasons: [
            {code: "information_received", label: "Requested information received"}
          ]
        },
        {
          to_status: "declined",
          label: "Decline",
          reasons: [
            {code: "information_not_provided", label: "Information not provided"},
            {code: "outside_scope", label: "Outside office scope"},
            {code: "other_decline_reason", label: "Other reason"}
          ]
        }
      ],
      "under_review" => [
        {
          to_status: "needs_information",
          label: "Request information",
          reasons: [
            {code: "missing_attendee_details", label: "Missing attendee details"},
            {code: "missing_availability", label: "Missing availability"},
            {code: "scope_clarification", label: "Purpose needs clarification"},
            {code: "other_information_needed", label: "Other information needed"}
          ]
        },
        {
          to_status: "approved",
          label: "Approve",
          reasons: [
            {code: "ready_to_schedule", label: "Ready to schedule"},
            {code: "principal_priority", label: "Principal priority"},
            {code: "community_value", label: "Community value"},
            {code: "required_follow_up", label: "Required follow-up"}
          ]
        },
        {
          to_status: "declined",
          label: "Decline",
          reasons: [
            {code: "outside_scope", label: "Outside office scope"},
            {code: "insufficient_priority", label: "Insufficient priority"},
            {code: "duplicate_request", label: "Duplicate request"},
            {code: "scheduling_conflict", label: "Scheduling conflict"},
            {code: "other_decline_reason", label: "Other reason"}
          ]
        }
      ],
      "approved" => [
        {
          to_status: "needs_information",
          label: "Request information",
          reasons: [
            {code: "approval_details_changed", label: "Approval details changed"},
            {code: "missing_availability", label: "Missing availability"}
          ]
        },
        {
          to_status: "scheduled",
          label: "Mark scheduled",
          reasons: [
            {code: "time_confirmed", label: "Meeting time confirmed"}
          ]
        }
      ],
      "declined" => [],
      "scheduled" => []
    }.freeze

    class ValidationError < StandardError
      attr_reader :fields

      def initialize(fields)
        super("Validation failed.")
        @fields = fields
      end
    end

    class InvalidTransitionError < StandardError
      attr_reader :current_status, :requested_status

      def initialize(current_status:, requested_status:)
        super("Cannot transition from #{current_status} to #{requested_status}.")
        @current_status = current_status
        @requested_status = requested_status
      end
    end

    class ConflictError < StandardError
      attr_reader :current_lock_version, :current_status

      def initialize(current_lock_version:, current_status:)
        super("Scheduling request changed since it was loaded.")
        @current_lock_version = current_lock_version
        @current_status = current_status
      end
    end

    module_function

    def available_transitions(status)
      TRANSITIONS.fetch(status, []).map do |transition|
        {
          to_status: transition.fetch(:to_status),
          label: transition.fetch(:label),
          reasons: transition.fetch(:reasons).map(&:dup)
        }
      end
    end

    def transition(id:, attributes:, workspace:, actor:)
      to_status = normalize_text(attributes["to_status"], limit: 40)
      reason_code = normalize_text(attributes["reason_code"], limit: 100)
      notes = normalize_text(attributes["notes"], limit: 2_000)
      expected_lock_version = Integer(attributes["expected_lock_version"], exception: false)
      errors = {}
      errors["to_status"] = "Select a valid target status." unless STATES.include?(to_status)
      errors["expected_lock_version"] = "Expected lock version must be a positive integer." unless expected_lock_version&.positive?
      raise ValidationError, errors unless errors.empty?

      db = Database.db
      result = nil

      db.transaction do
        request = db[:scheduling_requests].where(id: id, workspace_id: workspace[:id]).first
        next unless request

        if request[:lock_version] != expected_lock_version
          raise ConflictError.new(current_lock_version: request[:lock_version], current_status: request[:status])
        end

        definition = TRANSITIONS.fetch(request[:status], []).find { |candidate| candidate[:to_status] == to_status }
        unless definition
          raise InvalidTransitionError.new(current_status: request[:status], requested_status: to_status)
        end

        allowed_reasons = definition.fetch(:reasons).map { |reason| reason.fetch(:code) }
        unless allowed_reasons.include?(reason_code)
          raise ValidationError, {"reason_code" => "Select a valid reason for this transition."}
        end

        now = Time.now.utc
        correlation_id = SecureRandom.uuid
        transition_id = SecureRandom.uuid
        updated = db[:scheduling_requests]
          .where(
            id: id,
            workspace_id: workspace[:id],
            status: request[:status],
            lock_version: expected_lock_version
          )
          .update(
            status: to_status,
            lock_version: expected_lock_version + 1,
            updated_at: now
          )

        if updated.zero?
          current = db[:scheduling_requests].where(id: id, workspace_id: workspace[:id]).first
          raise ConflictError.new(
            current_lock_version: current&.fetch(:lock_version),
            current_status: current&.fetch(:status)
          )
        end

        db[:request_state_transitions].insert(
          id: transition_id,
          scheduling_request_id: id,
          actor_workspace_member_id: actor[:id],
          from_status: request[:status],
          to_status: to_status,
          reason_code: reason_code,
          notes: notes,
          correlation_id: correlation_id,
          occurred_at: now
        )

        if %w[approved declined].include?(to_status)
          db[:request_decisions].insert(
            id: SecureRandom.uuid,
            scheduling_request_id: id,
            request_state_transition_id: transition_id,
            decided_by_workspace_member_id: actor[:id],
            decision: to_status,
            reason_code: reason_code,
            notes: notes,
            decided_at: now
          )
        end

        db[:audit_events].insert(
          id: SecureRandom.uuid,
          workspace_id: workspace[:id],
          actor_workspace_member_id: actor[:id],
          event_type: "scheduling_request.#{to_status}",
          subject_type: "scheduling_request",
          subject_id: id,
          payload: JSON.generate(
            from_status: request[:status],
            to_status: to_status,
            reason_code: reason_code,
            transition_id: transition_id
          ),
          correlation_id: correlation_id,
          occurred_at: now
        )

        result = {transition_id: transition_id, lock_version: expected_lock_version + 1}
      end

      result
    end

    def record_initial_transition(request_id:, actor:, occurred_at:, correlation_id:)
      Database.db[:request_state_transitions].insert(
        id: SecureRandom.uuid,
        scheduling_request_id: request_id,
        actor_workspace_member_id: actor[:id],
        from_status: nil,
        to_status: "submitted",
        reason_code: "request_created",
        notes: nil,
        correlation_id: correlation_id,
        occurred_at: occurred_at
      )
    end

    def normalize_text(value, limit:)
      return nil unless value.is_a?(String)

      normalized = value.strip
      return nil if normalized.empty?

      normalized[0, limit]
    end
  end
end
