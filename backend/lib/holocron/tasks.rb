# frozen_string_literal: true

require "json"
require "securerandom"
require_relative "database"

module Holocron
  module Tasks
    STATUSES = %w[open in_progress completed cancelled].freeze
    BRIEFING_PREPARATION_DESCRIPTION = "Review and finalize the meeting briefing before the meeting begins."

    module_function

    def list(workspace:)
      tasks = Database.db[:tasks]
        .where(workspace_id: workspace[:id])
        .order(Sequel.asc(:due_at, nulls: :last), :created_at)
        .all
      serialize_many(tasks)
    end

    def for_meeting(meeting_id:, workspace:)
      tasks = Database.db[:tasks]
        .where(workspace_id: workspace[:id], meeting_id: meeting_id)
        .order(Sequel.asc(:due_at, nulls: :last), :created_at)
        .all
      serialize_many(tasks)
    end

    def create_briefing_preparation!(meeting:, request:, workspace:, actor:, correlation_id:, occurred_at:)
      db = Database.db
      task_id = SecureRandom.uuid
      origin_key = "meeting:#{meeting.fetch(:id)}:briefing_preparation"

      db[:tasks].insert(
        id: task_id,
        workspace_id: workspace[:id],
        meeting_id: meeting.fetch(:id),
        scheduling_request_id: request.fetch(:id),
        assigned_to_workspace_member_id: request.fetch(:assigned_scheduler_member_id),
        created_by_workspace_member_id: actor[:id],
        title: "Prepare briefing: #{meeting.fetch(:title)}",
        description: BRIEFING_PREPARATION_DESCRIPTION,
        status: "open",
        priority: "normal",
        origin: "system",
        origin_key: origin_key,
        due_at: meeting.fetch(:starts_at),
        completed_at: nil,
        lock_version: 1,
        created_at: occurred_at,
        updated_at: occurred_at
      )
      db[:task_state_transitions].insert(
        id: SecureRandom.uuid,
        task_id: task_id,
        actor_workspace_member_id: actor[:id],
        from_status: nil,
        to_status: "open",
        reason_code: "meeting_created",
        notes: nil,
        correlation_id: correlation_id,
        occurred_at: occurred_at
      )
      db[:audit_events].insert(
        id: SecureRandom.uuid,
        workspace_id: workspace[:id],
        actor_workspace_member_id: actor[:id],
        event_type: "task.created",
        subject_type: "task",
        subject_id: task_id,
        payload: JSON.generate(
          meeting_id: meeting.fetch(:id),
          scheduling_request_id: request.fetch(:id),
          assigned_to_workspace_member_id: request.fetch(:assigned_scheduler_member_id),
          origin: "system",
          origin_key: origin_key
        ),
        correlation_id: correlation_id,
        occurred_at: occurred_at
      )

      db[:tasks].where(id: task_id).first
    end

    def serialize_many(tasks)
      member_ids = tasks.flat_map do |task|
        [task[:assigned_to_workspace_member_id], task[:created_by_workspace_member_id]]
      end.compact.uniq
      members_by_id = Database.db[:workspace_members]
        .where(id: member_ids)
        .all
        .to_h { |member| [member[:id], member] }
      tasks.map { |task| serialize(task, members_by_id: members_by_id) }
    end

    def serialize(task, members_by_id: nil)
      members_by_id ||= Database.db[:workspace_members]
        .where(id: [task[:assigned_to_workspace_member_id], task[:created_by_workspace_member_id]].compact)
        .all
        .to_h { |member| [member[:id], member] }
      assignee = members_by_id[task[:assigned_to_workspace_member_id]]
      creator = members_by_id[task[:created_by_workspace_member_id]]

      {
        id: task[:id],
        meeting_id: task[:meeting_id],
        scheduling_request_id: task[:scheduling_request_id],
        title: task[:title],
        description: task[:description],
        status: task[:status],
        priority: task[:priority],
        origin: task[:origin],
        assignee: serialize_member(assignee),
        created_by: serialize_member(creator),
        due_at: iso8601(task[:due_at]),
        completed_at: iso8601(task[:completed_at]),
        lock_version: task[:lock_version],
        created_at: iso8601(task[:created_at]),
        updated_at: iso8601(task[:updated_at])
      }
    end

    def serialize_member(member)
      member && {
        id: member[:id],
        display_name: member[:display_name],
        email: member[:email],
        job_title: member[:job_title],
        role: member[:role],
        status: member[:status]
      }
    end

    def iso8601(value)
      value&.iso8601
    end
  end
end
