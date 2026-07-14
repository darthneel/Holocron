# frozen_string_literal: true

Sequel.migration do
  up do
    create_table(:request_extractions) do
      String :id, primary_key: true
      foreign_key :workspace_id, :workspaces, type: String, null: false, on_delete: :restrict
      foreign_key :requested_by_workspace_member_id, :workspace_members, type: String, null: false, on_delete: :restrict
      foreign_key :scheduling_request_id, :scheduling_requests, type: String, on_delete: :set_null
      String :status, null: false
      String :provider, null: false
      String :model, null: false
      String :prompt_version, null: false
      String :input_text, text: true, null: false
      String :output_json, text: true
      String :validation_errors_json, text: true, null: false, default: "{}"
      String :warnings_json, text: true, null: false, default: "[]"
      Integer :attempt_count, null: false
      String :failure_reason, text: true
      String :provider_request_id
      Integer :input_tokens
      Integer :output_tokens
      Integer :duration_ms
      DateTime :created_at, null: false
      DateTime :completed_at, null: false
      DateTime :accepted_at

      check(status: %w[succeeded failed refused])
      constraint(:positive_attempt_count) { attempt_count > 0 }
      constraint(:successful_extraction_has_output, "status != 'succeeded' OR output_json IS NOT NULL")
      constraint(
        :accepted_extraction_is_linked,
        "(scheduling_request_id IS NULL AND accepted_at IS NULL) OR " \
          "(scheduling_request_id IS NOT NULL AND accepted_at IS NOT NULL AND status = 'succeeded')"
      )
      index :scheduling_request_id, unique: true
      index %i[workspace_id created_at]
      index %i[requested_by_workspace_member_id created_at]
      index %i[workspace_id status]
    end
  end

  down do
    drop_table(:request_extractions)
  end
end
