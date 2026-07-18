# frozen_string_literal: true

Sequel.migration do
  up do
    vector_available = fetch("SELECT 1 FROM pg_available_extensions WHERE name = 'vector'").any?
    run "CREATE EXTENSION IF NOT EXISTS vector" if vector_available

    create_table(:semantic_documents) do
      String :id, primary_key: true
      foreign_key :workspace_id, :workspaces, type: String, null: false, on_delete: :cascade
      String :source_type, null: false
      String :source_id, null: false
      String :content, text: true, null: false
      String :content_hash, null: false
      String :embedding_model, null: false
      Integer :embedding_tokens
      column :embedding, vector_available ? "vector(1536)" : "double precision[]", null: false
      DateTime :created_at, null: false
      DateTime :updated_at, null: false

      check(source_type: %w[interaction])
      index %i[workspace_id source_type source_id], unique: true
      index %i[workspace_id source_type embedding_model], name: :semantic_documents_scope
    end

    if vector_available
      run <<~SQL
        CREATE INDEX semantic_documents_embedding_hnsw
        ON semantic_documents
        USING hnsw (embedding vector_cosine_ops)
      SQL
    end

    alter_table(:briefing_versions) do
      add_column :retrieval_strategy, String
      add_column :generation_provider, String
      add_column :generation_model, String
      add_column :prompt_version, String
      add_column :context_version, String
      add_column :provider_request_id, String
      add_column :attempt_count, Integer
      add_column :input_tokens, Integer
      add_column :output_tokens, Integer
      add_column :duration_ms, Integer
      add_column :retrieval_json, String, text: true
      add_column :cited_claim_count, Integer
      add_column :useful_cited_claims, Integer
    end

    alter_table(:briefing_versions) do
      add_constraint(
        :valid_retrieval_strategy,
        "retrieval_strategy IS NULL OR retrieval_strategy IN ('linked_recency', 'semantic')"
      )
      add_constraint(
        :valid_useful_cited_claims,
        "useful_cited_claims IS NULL OR " \
          "(useful_cited_claims >= 0 AND cited_claim_count IS NOT NULL AND useful_cited_claims <= cited_claim_count)"
      )
    end
  end

  down do
    alter_table(:briefing_versions) do
      drop_constraint :valid_useful_cited_claims
      drop_constraint :valid_retrieval_strategy
      drop_column :useful_cited_claims
      drop_column :cited_claim_count
      drop_column :retrieval_json
      drop_column :duration_ms
      drop_column :output_tokens
      drop_column :input_tokens
      drop_column :attempt_count
      drop_column :provider_request_id
      drop_column :context_version
      drop_column :prompt_version
      drop_column :generation_model
      drop_column :generation_provider
      drop_column :retrieval_strategy
    end
    drop_table(:semantic_documents)
  end
end
