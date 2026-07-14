# frozen_string_literal: true

require "securerandom"

Sequel.migration do
  up do
    request_statuses = %w[submitted needs_information under_review approved declined scheduled]

    alter_table(:scheduling_requests) do
      add_column :status, String, null: false, default: "submitted"
      add_column :lock_version, Integer, null: false, default: 1
      add_constraint(:valid_scheduling_request_status, status: request_statuses)
      add_constraint(:positive_scheduling_request_lock_version) { lock_version > 0 }
      add_index %i[workspace_id status updated_at]
    end

    create_table(:request_state_transitions) do
      String :id, primary_key: true
      foreign_key :scheduling_request_id, :scheduling_requests, type: String, null: false, on_delete: :cascade
      foreign_key :actor_workspace_member_id, :workspace_members, type: String, on_delete: :restrict
      String :from_status
      String :to_status, null: false
      String :reason_code, null: false
      String :notes, text: true
      String :correlation_id, null: false
      DateTime :occurred_at, null: false

      constraint(:valid_transition_from_status, "from_status IS NULL OR from_status IN ('submitted', 'needs_information', 'under_review', 'approved', 'declined', 'scheduled')")
      check(to_status: request_statuses)
      index %i[scheduling_request_id occurred_at]
      index :correlation_id
    end

    create_table(:request_decisions) do
      String :id, primary_key: true
      foreign_key :scheduling_request_id, :scheduling_requests, type: String, null: false, on_delete: :cascade
      foreign_key :request_state_transition_id, :request_state_transitions, type: String, null: false, unique: true, on_delete: :cascade
      foreign_key :decided_by_workspace_member_id, :workspace_members, type: String, null: false, on_delete: :restrict
      String :decision, null: false
      String :reason_code, null: false
      String :notes, text: true
      DateTime :decided_at, null: false

      check(decision: %w[approved declined])
      index %i[scheduling_request_id decided_at]
    end

    self[:scheduling_requests].all.each do |request|
      self[:request_state_transitions].insert(
        id: SecureRandom.uuid,
        scheduling_request_id: request[:id],
        actor_workspace_member_id: nil,
        from_status: nil,
        to_status: "submitted",
        reason_code: "migrated_existing_request",
        notes: nil,
        correlation_id: SecureRandom.uuid,
        occurred_at: request[:created_at]
      )
    end
  end

  down do
    drop_table(:request_decisions)
    drop_table(:request_state_transitions)

    alter_table(:scheduling_requests) do
      drop_column :lock_version
      drop_column :status
    end
  end
end
