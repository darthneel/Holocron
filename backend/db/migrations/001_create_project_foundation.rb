# frozen_string_literal: true

Sequel.migration do
  up do
    run "CREATE EXTENSION IF NOT EXISTS citext"

    create_table(:workspaces) do
      String :id, primary_key: true
      column :slug, "citext", null: false, unique: true
      String :name, null: false
      String :timezone, null: false
      Integer :retention_days, null: false, default: 365
      DateTime :created_at, null: false
      DateTime :updated_at, null: false

      check { retention_days > 0 }
    end

    create_table(:workspace_members) do
      String :id, primary_key: true
      foreign_key :workspace_id, :workspaces, type: String, null: false, on_delete: :restrict
      String :display_name, null: false
      column :email, "citext"
      String :job_title
      String :role, null: false
      String :status, null: false, default: "active"
      DateTime :created_at, null: false
      DateTime :updated_at, null: false

      check(role: %w[owner chief_of_staff scheduler advisor principal viewer])
      check(status: %w[active inactive])
      index %i[workspace_id email], unique: true, where: Sequel.~(email: nil)
      index %i[workspace_id role]
    end

    create_table(:principals) do
      String :id, primary_key: true
      foreign_key :workspace_id, :workspaces, type: String, null: false, unique: true, on_delete: :restrict
      foreign_key :workspace_member_id, :workspace_members, type: String, null: false, unique: true, on_delete: :restrict
      String :title, null: false
      String :status, null: false, default: "active"
      DateTime :created_at, null: false
      DateTime :updated_at, null: false

      check(status: %w[active archived])
    end

    create_table(:audit_events) do
      String :id, primary_key: true
      foreign_key :workspace_id, :workspaces, type: String, null: false, on_delete: :restrict
      foreign_key :actor_workspace_member_id, :workspace_members, type: String, on_delete: :restrict
      String :event_type, null: false
      String :subject_type, null: false
      String :subject_id
      String :payload, text: true, null: false, default: "{}"
      String :correlation_id, null: false
      DateTime :occurred_at, null: false

      index %i[workspace_id occurred_at]
      index :correlation_id
      index %i[subject_type subject_id]
    end
  end

  down do
    drop_table(:audit_events)
    drop_table(:principals)
    drop_table(:workspace_members)
    drop_table(:workspaces)
  end
end
