# frozen_string_literal: true

Sequel.migration do
  up do
    create_table(:scheduling_requests) do
      String :id, primary_key: true
      foreign_key :workspace_id, :workspaces, type: String, null: false, on_delete: :restrict
      foreign_key :principal_id, :principals, type: String, null: false, on_delete: :restrict
      foreign_key :assigned_scheduler_member_id, :workspace_members, type: String, null: false, on_delete: :restrict
      foreign_key :created_by_workspace_member_id, :workspace_members, type: String, null: false, on_delete: :restrict
      String :requester_name, null: false
      String :requester_email, collate: "NOCASE"
      String :requester_organization
      String :purpose, text: true, null: false
      Integer :requested_duration_minutes, null: false
      String :availability_notes, text: true
      String :source_channel, null: false
      String :original_request_text, text: true
      DateTime :created_at, null: false
      DateTime :updated_at, null: false

      check(source_channel: %w[email phone web staff other])
      check { (requested_duration_minutes >= 15) & (requested_duration_minutes <= 480) }
      index %i[workspace_id created_at]
      index %i[principal_id created_at]
      index :assigned_scheduler_member_id
    end

    create_table(:request_participants) do
      String :id, primary_key: true
      foreign_key :scheduling_request_id, :scheduling_requests, type: String, null: false, on_delete: :cascade
      String :name, null: false
      String :email, collate: "NOCASE"
      String :organization
      String :role, null: false
      DateTime :created_at, null: false
      DateTime :updated_at, null: false

      check(role: %w[required optional staff])
      index :scheduling_request_id
    end

    create_table(:request_candidate_windows) do
      String :id, primary_key: true
      foreign_key :scheduling_request_id, :scheduling_requests, type: String, null: false, on_delete: :cascade
      String :candidate_date, null: false
      DateTime :starts_at
      DateTime :ends_at
      String :notes, text: true
      Integer :position, null: false
      DateTime :created_at, null: false
      DateTime :updated_at, null: false

      constraint(:candidate_window_times, "(starts_at IS NULL AND ends_at IS NULL) OR (starts_at IS NOT NULL AND ends_at IS NOT NULL AND ends_at > starts_at)")
      index %i[scheduling_request_id position], unique: true
    end
  end

  down do
    drop_table(:request_candidate_windows)
    drop_table(:request_participants)
    drop_table(:scheduling_requests)
  end
end
