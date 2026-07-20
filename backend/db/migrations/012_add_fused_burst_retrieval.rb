# frozen_string_literal: true

Sequel.migration do
  up do
    alter_table(:semantic_documents) do
      add_column :unit_type, String, null: false, default: "overview"
      add_column :unit_key, String, null: false, default: "overview"
      add_column :position, Integer
      add_column :metadata_json, String, text: true
      drop_index %i[workspace_id source_type source_id]
      add_index %i[workspace_id source_type source_id unit_type unit_key],
        unique: true,
        name: :semantic_documents_source_unit
      add_constraint(:valid_semantic_document_unit_type, "unit_type IN ('overview', 'burst')")
    end

    run <<~SQL
      ALTER TABLE semantic_documents
      ADD COLUMN search_vector tsvector
      GENERATED ALWAYS AS (to_tsvector('english', content)) STORED
    SQL
    run <<~SQL
      CREATE INDEX semantic_documents_search_vector_gin
      ON semantic_documents
      USING gin (search_vector)
    SQL

    alter_table(:briefing_versions) do
      drop_constraint :valid_retrieval_strategy
      add_constraint(
        :valid_retrieval_strategy,
        "retrieval_strategy IS NULL OR retrieval_strategy IN ('linked_recency', 'semantic', 'hybrid', 'fused')"
      )
    end
  end

  down do
    alter_table(:briefing_versions) do
      drop_constraint :valid_retrieval_strategy
      add_constraint(
        :valid_retrieval_strategy,
        "retrieval_strategy IS NULL OR retrieval_strategy IN ('linked_recency', 'semantic', 'hybrid')"
      )
    end

    run "DROP INDEX IF EXISTS semantic_documents_search_vector_gin"
    alter_table(:semantic_documents) do
      drop_column :search_vector
      drop_constraint :valid_semantic_document_unit_type
      drop_index %i[workspace_id source_type source_id unit_type unit_key],
        name: :semantic_documents_source_unit
      add_index %i[workspace_id source_type source_id], unique: true
      drop_column :metadata_json
      drop_column :position
      drop_column :unit_key
      drop_column :unit_type
    end
  end
end
