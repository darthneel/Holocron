# frozen_string_literal: true

Sequel.migration do
  up do
    create_table(:semantic_index_jobs) do
      String :id, primary_key: true
      foreign_key :workspace_id, :workspaces, type: String, null: false, on_delete: :cascade
      foreign_key :interaction_id, :interactions, type: String, null: false, on_delete: :cascade
      String :status, null: false, default: "pending"
      Integer :revision, null: false, default: 1
      Integer :attempts, null: false, default: 0
      DateTime :available_at, null: false
      DateTime :locked_at
      String :locked_by
      String :last_error, text: true
      DateTime :last_indexed_at
      DateTime :created_at, null: false
      DateTime :updated_at, null: false

      check(status: %w[pending running completed])
      index :interaction_id, unique: true, name: :semantic_index_jobs_interaction
      index %i[status available_at], name: :semantic_index_jobs_available
    end
  end

  down do
    drop_table(:semantic_index_jobs)
  end
end
