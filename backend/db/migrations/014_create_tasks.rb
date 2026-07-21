# frozen_string_literal: true

Sequel.migration do
  up do
    task_statuses = %w[open in_progress completed cancelled]

    create_table(:tasks) do
      String :id, primary_key: true
      foreign_key :workspace_id, :workspaces, type: String, null: false, on_delete: :restrict
      foreign_key :meeting_id, :meetings, type: String, on_delete: :cascade
      foreign_key :scheduling_request_id, :scheduling_requests, type: String, on_delete: :cascade
      foreign_key :assigned_to_workspace_member_id, :workspace_members, type: String, on_delete: :restrict
      foreign_key :created_by_workspace_member_id, :workspace_members, type: String, null: false, on_delete: :restrict
      String :title, null: false
      String :description, text: true
      String :status, null: false, default: "open"
      String :priority, null: false, default: "normal"
      String :origin, null: false
      String :origin_key
      DateTime :due_at
      DateTime :completed_at
      Integer :lock_version, null: false, default: 1
      DateTime :created_at, null: false
      DateTime :updated_at, null: false

      check(status: task_statuses)
      check(priority: %w[low normal high])
      check(origin: %w[system manual agent])
      constraint(:positive_task_lock_version) { lock_version > 0 }
      constraint(
        :completed_task_timestamp_matches_status,
        "(status = 'completed' AND completed_at IS NOT NULL) OR (status <> 'completed' AND completed_at IS NULL)"
      )
      index %i[workspace_id status due_at]
      index %i[workspace_id origin_key], unique: true
      index :meeting_id
      index :scheduling_request_id
      index :assigned_to_workspace_member_id
    end

    create_table(:task_state_transitions) do
      String :id, primary_key: true
      foreign_key :task_id, :tasks, type: String, null: false, on_delete: :cascade
      foreign_key :actor_workspace_member_id, :workspace_members, type: String, on_delete: :restrict
      String :from_status
      String :to_status, null: false
      String :reason_code, null: false
      String :notes, text: true
      String :correlation_id, null: false
      DateTime :occurred_at, null: false

      constraint(
        :valid_task_transition_from_status,
        "from_status IS NULL OR from_status IN ('open', 'in_progress', 'completed', 'cancelled')"
      )
      check(to_status: task_statuses)
      index %i[task_id occurred_at]
      index :correlation_id
    end
  end

  down do
    drop_table(:task_state_transitions)
    drop_table(:tasks)
  end
end
