# frozen_string_literal: true

Sequel.migration do
  up do
    alter_table(:briefings) do
      add_column :generation_status, String, null: false, default: "ready"
      add_index %i[workspace_id generation_status updated_at], name: :briefings_generation_status
    end

    create_table(:briefing_generation_jobs) do
      String :id, primary_key: true
      foreign_key :workspace_id, :workspaces, type: String, null: false, on_delete: :cascade
      foreign_key :briefing_id, :briefings, type: String, null: false, on_delete: :cascade
      String :status, null: false, default: "pending"
      Integer :revision, null: false, default: 1
      Integer :attempts, null: false, default: 0
      DateTime :available_at, null: false
      DateTime :locked_at
      String :locked_by
      String :last_error, text: true
      DateTime :completed_at
      DateTime :created_at, null: false
      DateTime :updated_at, null: false

      check(status: %w[pending running completed failed])
      index :briefing_id, unique: true, name: :briefing_generation_jobs_briefing
      index %i[status available_at], name: :briefing_generation_jobs_available
    end
  end

  down do
    drop_table(:briefing_generation_jobs)
    alter_table(:briefings) do
      drop_index %i[workspace_id generation_status updated_at], name: :briefings_generation_status
      drop_column :generation_status
    end
  end
end
