# frozen_string_literal: true

require "digest"
require "securerandom"
require "time"
require_relative "ai/embeddings"
require_relative "database"

module Holocron
  class SemanticIndex
    DEFAULT_LIMIT = 8
    DEFAULT_MINIMUM_SIMILARITY = 0.18

    def initialize(workspace:, embedding_provider: nil)
      @workspace = workspace
      @embedding_provider = embedding_provider
      @db = Database.db
      @db.extension(:pg_array)
    end

    def search_interactions(query:, exclude_request_id: nil, limit: DEFAULT_LIMIT)
      refresh = refresh_interactions!
      query_embedding = AI::Embeddings.embed([query], provider: @embedding_provider)
      model = query_embedding.model
      vector = vector_literal(query_embedding.vectors.first)
      minimum_similarity = Float(
        ENV.fetch("SEMANTIC_MINIMUM_SIMILARITY", DEFAULT_MINIMUM_SIMILARITY.to_s),
        exception: false
      ) || DEFAULT_MINIMUM_SIMILARITY

      rows = ranked_documents(vector: vector, raw_vector: query_embedding.vectors.first, model: model, limit: limit * 3)

      interaction_ids = rows.map { |row| row[:source_id] }
      interactions = @db[:interactions]
        .where(workspace_id: workspace_id, id: interaction_ids)
        .all
        .to_h { |interaction| [interaction[:id], interaction] }
      people = @db[:people]
        .where(workspace_id: workspace_id, id: interactions.values.map { |interaction| interaction[:person_id] })
        .all
        .to_h { |person| [person[:id], person] }

      selected = rows.filter_map do |row|
        interaction = interactions[row[:source_id]]
        next unless interaction
        next if exclude_request_id && interaction[:scheduling_request_id] == exclude_request_id
        next if row[:similarity].to_f < minimum_similarity

        person = people[interaction[:person_id]]
        interaction.merge(
          person_name: person&.fetch(:display_name, "Unknown person"),
          current_request: false,
          semantic_similarity: row[:similarity].to_f
        )
      end.first(limit)

      {
        interactions: selected,
        indexed_records: refresh[:indexed_records],
        refreshed_records: refresh[:refreshed_records],
        indexing_tokens: refresh[:embedding_tokens],
        query_tokens: query_embedding.input_tokens,
        embedding_provider: query_embedding.provider,
        embedding_model: model,
        vector_backend: pgvector? ? "pgvector_hnsw" : "postgres_array_local",
        minimum_similarity: minimum_similarity
      }
    end

    def refresh_interactions!
      documents = interaction_documents
      existing = @db[:semantic_documents]
        .where(workspace_id: workspace_id, source_type: "interaction")
        .all
        .to_h { |document| [document[:source_id], document] }
      provider = @embedding_provider || AI::Embeddings.configured_provider
      model = provider.model
      stale = documents.select do |document|
        stored = existing[document[:source_id]]
        !stored || stored[:content_hash] != document[:content_hash] || stored[:embedding_model] != model
      end

      embedding_tokens = 0
      unless stale.empty?
        embedded = AI::Embeddings.embed(stale.map { |document| document[:content] }, provider: provider)
        embedding_tokens = embedded.input_tokens.to_i
        now = Time.now.utc
        stale.each_with_index do |document, index|
          values = {
            content: document[:content],
            content_hash: document[:content_hash],
            embedding_model: embedded.model,
            embedding_tokens: nil,
            embedding: stored_vector(embedded.vectors[index]),
            updated_at: now
          }
          dataset = @db[:semantic_documents].where(
            workspace_id: workspace_id,
            source_type: "interaction",
            source_id: document[:source_id]
          )
          if dataset.any?
            dataset.update(values)
          else
            dataset.insert(
              values.merge(
                id: SecureRandom.uuid,
                workspace_id: workspace_id,
                source_type: "interaction",
                source_id: document[:source_id],
                created_at: now
              )
            )
          end
        end
      end

      {
        indexed_records: documents.length,
        refreshed_records: stale.length,
        embedding_tokens: embedding_tokens
      }
    end

    private

    def interaction_documents
      interactions = @db[:interactions]
        .where(workspace_id: workspace_id)
        .order(:id)
        .all
      people = @db[:people]
        .where(workspace_id: workspace_id, id: interactions.map { |interaction| interaction[:person_id] })
        .all
        .to_h { |person| [person[:id], person] }
      organization_ids = people.values.filter_map { |person| person[:organization_id] }.uniq
      organizations = @db[:organizations]
        .where(workspace_id: workspace_id, id: organization_ids)
        .all
        .to_h { |organization| [organization[:id], organization] }

      interactions.map do |interaction|
        person = people[interaction[:person_id]]
        organization = person && organizations[person[:organization_id]]
        content = [
          "Interaction type: #{interaction[:interaction_type]}",
          "Person: #{person&.fetch(:display_name, 'Unknown person')}",
          organization && "Organization: #{organization[:name]}",
          "Summary: #{interaction[:summary]}"
        ].compact.join("\n")
        {
          source_id: interaction[:id],
          content: content,
          content_hash: Digest::SHA256.hexdigest(content)
        }
      end
    end

    def workspace_id
      @workspace.fetch(:id)
    end

    def vector_literal(vector)
      "[#{vector.map { |value| format('%.9f', value) }.join(',')}]"
    end

    def ranked_documents(vector:, raw_vector:, model:, limit:)
      dataset = @db[:semantic_documents]
        .where(workspace_id: workspace_id, source_type: "interaction", embedding_model: model)
      if pgvector?
        distance = Sequel.lit("embedding <=> ?::vector", vector)
        dataset
          .select_all(:semantic_documents)
          .select_append(Sequel.as(1.0 - distance, :similarity))
          .order(distance)
          .limit(limit)
          .all
      else
        dataset.all
          .map { |row| row.merge(similarity: cosine_similarity(row[:embedding], raw_vector)) }
          .sort_by { |row| -row[:similarity] }
          .first(limit)
      end
    end

    def stored_vector(vector)
      pgvector? ? Sequel.lit("?::vector", vector_literal(vector)) : Sequel.pg_array(vector, :float8)
    end

    def pgvector?
      @pgvector ||= @db.schema(:semantic_documents)
        .to_h
        .fetch(:embedding)
        .fetch(:db_type)
        .start_with?("vector")
    end

    def cosine_similarity(left, right)
      dot = 0.0
      left_magnitude = 0.0
      right_magnitude = 0.0
      left.each_with_index do |value, index|
        right_value = right[index].to_f
        value = value.to_f
        dot += value * right_value
        left_magnitude += value * value
        right_magnitude += right_value * right_value
      end
      denominator = Math.sqrt(left_magnitude) * Math.sqrt(right_magnitude)
      denominator.zero? ? 0.0 : dot / denominator
    end
  end
end
