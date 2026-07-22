# frozen_string_literal: true

# This follows the production task and detail-loading migrations (014 and 015).
Sequel.migration do
  up do
    create_table(:semantic_labeling_runs) do
      String :id, primary_key: true
      foreign_key :workspace_id, :workspaces, type: String, null: false, on_delete: :cascade
      String :status, null: false
      String :classifier_provider
      String :classifier_model
      String :configuration_json, text: true, null: false
      String :summary_json, text: true
      String :failure_reason, text: true
      DateTime :created_at, null: false
      DateTime :completed_at

      check(status: %w[running completed failed])
      index %i[workspace_id created_at], name: :semantic_labeling_runs_workspace_created
    end

    create_table(:semantic_labeling_baseline_documents) do
      String :id, primary_key: true
      foreign_key :run_id, :semantic_labeling_runs, type: String, null: false, on_delete: :cascade
      String :semantic_document_id, null: false
      String :source_id, null: false
      String :unit_type, null: false
      String :unit_key, null: false
      Integer :position
      String :content, text: true, null: false
      String :content_hash, null: false
      String :embedding_model, null: false
      String :metadata_json, text: true
      DateTime :captured_at, null: false

      check(unit_type: %w[overview burst])
      index %i[run_id source_id unit_type unit_key], unique: true,
        name: :semantic_labeling_baseline_documents_run_unit
    end

    create_table(:semantic_labeling_candidates) do
      String :id, primary_key: true
      foreign_key :run_id, :semantic_labeling_runs, type: String, null: false, on_delete: :cascade
      String :source_id, null: false
      String :unit_key, null: false
      Integer :position, null: false
      String :excerpt, text: true, null: false
      String :heuristic_kind, null: false
      TrueClass :is_high_signal
      String :kind
      Float :confidence
      String :supporting_excerpt, text: true
      TrueClass :accepted, null: false, default: false
      String :provider
      String :model
      String :provider_request_id
      String :model_output_json, text: true
      String :failure_reason, text: true
      DateTime :created_at, null: false

      check(heuristic_kind: %w[signal background])
      check(kind: %w[decision commitment concern request other])
      index %i[run_id source_id unit_key], unique: true, name: :semantic_labeling_candidates_run_unit
    end

    create_table(:semantic_labeling_burst_proposals) do
      String :id, primary_key: true
      foreign_key :run_id, :semantic_labeling_runs, type: String, null: false, on_delete: :cascade
      String :source_id, null: false
      String :unit_key, null: false
      Integer :position
      String :excerpt, text: true, null: false
      String :signal_kind
      String :classification_source, null: false
      Float :classification_confidence
      String :supporting_excerpt, text: true
      String :metadata_json, text: true
      String :baseline_document_id
      String :change_type, null: false
      DateTime :created_at, null: false

      check(signal_kind: %w[decision commitment concern request signal background])
      check(classification_source: %w[heuristic llm baseline])
      check(change_type: %w[added changed unchanged removed])
      index %i[run_id source_id unit_key], unique: true, name: :semantic_labeling_burst_proposals_run_unit
      index %i[run_id change_type], name: :semantic_labeling_burst_proposals_run_change
    end
  end

  down do
    drop_table(:semantic_labeling_burst_proposals)
    drop_table(:semantic_labeling_candidates)
    drop_table(:semantic_labeling_baseline_documents)
    drop_table(:semantic_labeling_runs)
  end
end
