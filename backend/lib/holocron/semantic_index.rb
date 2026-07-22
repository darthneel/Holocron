# frozen_string_literal: true

require "digest"
require "json"
require "securerandom"
require "time"
require_relative "ai/embeddings"
require_relative "database"
require_relative "semantic_burst_rules"

module Holocron
  class SemanticIndex
    DEFAULT_LIMIT = 8
    DEFAULT_MINIMUM_SIMILARITY = 0.18
    DEFAULT_EMBEDDING_BATCH_SIZE = 100
    RRF_K = 60.0
    BURST_MINIMUM_SOURCE_LENGTH = SemanticBurstRules::MINIMUM_SOURCE_LENGTH
    BURST_MINIMUM_LENGTH = SemanticBurstRules::MINIMUM_LENGTH
    BURST_SIGNAL_PATTERN = SemanticBurstRules::SIGNAL_PATTERN
    IDENTIFIER_PATTERN = SemanticBurstRules::IDENTIFIER_PATTERN

    def initialize(workspace:, embedding_provider: nil)
      @workspace = workspace
      @embedding_provider = embedding_provider
      @db = Database.db
      @db.extension(:pg_array)
    end

    def search_interactions(
      query:,
      exclude_request_id: nil,
      limit: DEFAULT_LIMIT,
      balanced_person_ids: [],
      per_person_limit: 2,
      max_per_person: nil,
      fused: false
    )
      refresh = refresh_interactions!
      query_embedding = AI::Embeddings.embed([query], provider: @embedding_provider)
      model = query_embedding.model
      vector = vector_literal(query_embedding.vectors.first)
      minimum_similarity = Float(
        ENV.fetch("SEMANTIC_MINIMUM_SIMILARITY", DEFAULT_MINIMUM_SIMILARITY.to_s),
        exception: false
      ) || DEFAULT_MINIMUM_SIMILARITY

      vector_rows = collapse_by_source(
        ranked_documents(
          vector: vector,
          raw_vector: query_embedding.vectors.first,
          model: model,
          limit: limit * 3,
          include_bursts: fused
        ).select { |row| row[:similarity].to_f >= minimum_similarity }
      )
      balanced_rows = balanced_ranked_documents(
        person_ids: balanced_person_ids,
        exclude_request_id: exclude_request_id,
        per_person_limit: per_person_limit,
        vector: vector,
        raw_vector: query_embedding.vectors.first,
        model: model,
        minimum_similarity: minimum_similarity,
        include_bursts: fused
      )

      lexical_rows = []
      rows = if fused
        lexical_rows = collapse_by_source(
          lexical_ranked_documents(query: query, model: model, limit: limit * 2)
        )
        candidate_source_ids = (vector_rows + lexical_rows + balanced_rows).map { |row| row[:source_id] }.uniq
        recency_rows = recency_ranked_documents(candidate_source_ids)
        reciprocal_rank_fusion(
          vector: vector_rows,
          lexical: lexical_rows,
          attendee: balanced_rows,
          recency: recency_rows
        )
      else
        (balanced_rows + vector_rows).uniq { |row| row[:source_id] }
      end

      interaction_ids = rows.map { |row| row[:source_id] }
      interactions = @db[:interactions]
        .where(workspace_id: workspace_id, id: interaction_ids)
        .all
        .to_h { |interaction| [interaction[:id], interaction] }
      people = @db[:people]
        .where(workspace_id: workspace_id, id: interactions.values.map { |interaction| interaction[:person_id] })
        .all
        .to_h { |person| [person[:id], person] }

      per_person_counts = Hash.new(0)
      selected = rows.filter_map do |row|
        interaction = interactions[row[:source_id]]
        next unless interaction
        next if exclude_request_id && interaction[:scheduling_request_id] == exclude_request_id

        person = people[interaction[:person_id]]
        next if max_per_person && per_person_counts[interaction[:person_id]] >= max_per_person

        per_person_counts[interaction[:person_id]] += 1
        metadata = parsed_metadata(row[:metadata_json])
        interaction.merge(
          person_name: person&.fetch(:display_name, "Unknown person"),
          current_request: false,
          semantic_similarity: row[:similarity]&.to_f,
          lexical_score: row[:lexical_score]&.to_f,
          rrf_score: row[:rrf_score]&.to_f,
          matched_unit_type: row[:unit_type],
          matched_excerpt: metadata["excerpt"],
          matched_evidence_spans: row[:matched_bursts],
          retrieval_signals: row[:retrieval_signals]
        )
      end.first(limit)
      balanced_source_ids = balanced_rows.to_h { |row| [row[:source_id], true] }
      balanced_selected = selected.select { |interaction| balanced_source_ids[interaction[:id]] }

      {
        interactions: selected,
        indexed_records: refresh[:indexed_records],
        indexed_interactions: refresh[:indexed_interactions],
        overview_records: refresh[:overview_records],
        burst_records: refresh[:burst_records],
        refreshed_records: refresh[:refreshed_records],
        removed_records: refresh[:removed_records],
        indexing_tokens: refresh[:embedding_tokens],
        query_tokens: query_embedding.input_tokens,
        embedding_provider: query_embedding.provider,
        embedding_model: model,
        vector_backend: pgvector? ? "pgvector_hnsw" : "postgres_array_local",
        minimum_similarity: minimum_similarity,
        fusion_enabled: fused,
        fusion_method: fused ? "reciprocal_rank_fusion" : nil,
        rrf_k: fused ? RRF_K.to_i : nil,
        vector_candidates: vector_rows.length,
        lexical_candidates: lexical_rows.length,
        attendee_candidates: balanced_rows.length,
        attendee_balanced_matches_selected: balanced_selected.length,
        attendees_with_history_selected: balanced_selected.map { |interaction| interaction[:person_id] }.uniq.length
      }
    end

    def refresh_interactions!
      documents = interaction_documents
      existing = @db[:semantic_documents]
        .where(workspace_id: workspace_id, source_type: "interaction")
        .all
        .to_h { |document| [document_key(document), document] }
      provider = @embedding_provider || AI::Embeddings.configured_provider
      model = provider.model
      stale = documents.select do |document|
        stored = existing[document_key(document)]
        !stored || stored[:content_hash] != document[:content_hash] || stored[:embedding_model] != model
      end

      embedding_tokens = 0
      stale.each_slice(embedding_batch_size) do |batch|
        embedded = AI::Embeddings.embed(batch.map { |document| document[:content] }, provider: provider)
        embedding_tokens += embedded.input_tokens.to_i
        now = Time.now.utc
        batch.each_with_index do |document, index|
          values = {
            content: document[:content],
            content_hash: document[:content_hash],
            embedding_model: embedded.model,
            embedding_tokens: nil,
            embedding: stored_vector(embedded.vectors[index]),
            unit_type: document[:unit_type],
            unit_key: document[:unit_key],
            position: document[:position],
            metadata_json: JSON.generate(document[:metadata]),
            updated_at: now
          }
          dataset = @db[:semantic_documents].where(
            workspace_id: workspace_id,
            source_type: "interaction",
            source_id: document[:source_id],
            unit_type: document[:unit_type],
            unit_key: document[:unit_key]
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

      desired_keys = documents.to_h { |document| [document_key(document), true] }
      obsolete_ids = existing.filter_map { |key, row| row[:id] unless desired_keys[key] }
      removed_records = obsolete_ids.empty? ? 0 : @db[:semantic_documents].where(id: obsolete_ids).delete

      {
        indexed_records: documents.length,
        indexed_interactions: documents.map { |document| document[:source_id] }.uniq.length,
        overview_records: documents.count { |document| document[:unit_type] == "overview" },
        burst_records: documents.count { |document| document[:unit_type] == "burst" },
        refreshed_records: stale.length,
        removed_records: removed_records,
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

      interactions.flat_map do |interaction|
        person = people[interaction[:person_id]]
        organization = person && organizations[person[:organization_id]]
        overview = overview_document(interaction: interaction, person: person, organization: organization)
        [overview] + burst_documents(interaction: interaction, person: person, organization: organization)
      end
    end

    def overview_document(interaction:, person:, organization:)
      content = [
        "Interaction type: #{interaction[:interaction_type]}",
        "Person: #{person&.fetch(:display_name, 'Unknown person')}",
        organization && "Organization: #{organization[:name]}",
        "Summary: #{interaction[:summary]}"
      ].compact.join("\n")
      document(
        interaction: interaction,
        unit_type: "overview",
        unit_key: "overview",
        position: 0,
        content: content,
        metadata: {"excerpt" => interaction[:summary], "signal_kind" => "overview"}
      )
    end

    def burst_documents(interaction:, person:, organization:)
      summary = interaction[:summary].to_s.strip
      return [] if summary.length < BURST_MINIMUM_SOURCE_LENGTH

      burst_segments(summary).each_with_index.filter_map do |segment, index|
        signal_kind = burst_signal_kind(segment)
        next unless high_signal_burst?(segment, signal_kind)

        content = [
          "Unit: high-signal interaction burst",
          "Topic: #{interaction[:interaction_type]} with #{person&.fetch(:display_name, 'Unknown person')}",
          organization && "Organization: #{organization[:name]}",
          "Signal: #{signal_kind}",
          "Passage: #{segment}"
        ].compact.join("\n")
        document(
          interaction: interaction,
          unit_type: "burst",
          unit_key: format("burst-%03d", index + 1),
          position: index + 1,
          content: content,
          metadata: {"excerpt" => segment, "signal_kind" => signal_kind}
        )
      end
    end

    def burst_segments(summary)
      SemanticBurstRules.segments(summary)
    end

    def high_signal_burst?(segment, signal_kind)
      SemanticBurstRules.high_signal?(segment, signal_kind)
    end

    def burst_signal_kind(segment)
      SemanticBurstRules.signal_kind(segment)
    end

    def document(interaction:, unit_type:, unit_key:, position:, content:, metadata:)
      {
        source_id: interaction[:id],
        unit_type: unit_type,
        unit_key: unit_key,
        position: position,
        content: content,
        content_hash: Digest::SHA256.hexdigest(content),
        metadata: metadata
      }
    end

    def document_key(document)
      [document[:source_id], document[:unit_type] || "overview", document[:unit_key] || "overview"]
    end

    def workspace_id
      @workspace.fetch(:id)
    end

    def embedding_batch_size
      configured = Integer(
        ENV.fetch("SEMANTIC_EMBEDDING_BATCH_SIZE", DEFAULT_EMBEDDING_BATCH_SIZE.to_s),
        exception: false
      )
      configured && configured.positive? ? configured : DEFAULT_EMBEDDING_BATCH_SIZE
    end

    def vector_literal(vector)
      "[#{vector.map { |value| format('%.9f', value) }.join(',')}]"
    end

    def balanced_ranked_documents(person_ids:, exclude_request_id:, per_person_limit:, vector:, raw_vector:, model:, minimum_similarity:, include_bursts:)
      return [] unless per_person_limit.positive?

      ranked_by_person = Array(person_ids).uniq.filter_map do |person_id|
        interactions = @db[:interactions]
          .where(workspace_id: workspace_id, person_id: person_id)
        if exclude_request_id
          interactions = interactions.where(
            Sequel.|({scheduling_request_id: nil}, Sequel.~(scheduling_request_id: exclude_request_id))
          )
        end
        source_ids = interactions.select_map(:id)
        next if source_ids.empty?

        collapse_by_source(
          ranked_documents(
            vector: vector,
            raw_vector: raw_vector,
            model: model,
            limit: [per_person_limit * 6, source_ids.length * 4].min,
            source_ids: source_ids,
            include_bursts: include_bursts
          ).select { |row| row[:similarity].to_f >= minimum_similarity }
        ).first(per_person_limit)
      end

      Array.new(per_person_limit) do |index|
        ranked_by_person.filter_map { |rows| rows[index] }
      end.flatten.uniq { |row| row[:source_id] }
    end

    def ranked_documents(vector:, raw_vector:, model:, limit:, source_ids: nil, include_bursts: true)
      dataset = semantic_dataset(model: model, source_ids: source_ids, include_bursts: include_bursts)
      if pgvector?
        distance = Sequel.lit("embedding <=> ?::vector", vector)
        similarity = Sequel.lit("1.0 - (embedding <=> ?::vector)", vector)
        dataset
          .select_all(:semantic_documents)
          .select_append(Sequel.as(similarity, :similarity))
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

    def lexical_ranked_documents(query:, model:, limit:, source_ids: nil)
      lexical_query = lexical_query_for(query)
      return [] if lexical_query.empty?

      rank = Sequel.lit("ts_rank_cd(search_vector, websearch_to_tsquery('english', ?))", lexical_query)
      match = Sequel.lit("search_vector @@ websearch_to_tsquery('english', ?)", lexical_query)
      semantic_dataset(model: model, source_ids: source_ids, include_bursts: true)
        .where(match)
        .select_all(:semantic_documents)
        .select_append(Sequel.as(rank, :lexical_score))
        .reverse_order(rank)
        .limit(limit)
        .all
    end

    def lexical_query_for(query)
      stopwords = %w[
        about after again against all also and are because been before being between both but can could
        did does doing down during each few for from further had has have having here how into its may more
        most not now our out over own same should some such than that the their them then there these they
        this those through too under until very was were what when where which while who why will with would
        your meeting discuss discussion request requested purpose availability
      ]
      identifiers = query.to_s.scan(/\b(?:[A-Z]{2,}(?:-[A-Z0-9]+)+|[A-Z]{2,}\s*\d{2,}|[A-Za-z]+[._-]v?\d+)\b/)
        .map { |value| value.downcase.tr("_-", " ").squeeze(" ") }
        .uniq
        .first(6)
      names = query.to_s.scan(/\b[A-Z][a-z]+(?:\s+[A-Z][a-z]+){1,2}\b/)
        .map(&:downcase)
        .reject { |value| value.start_with?("community resilience", "mayor park") }
        .uniq
        .first(4)
      tokens = query.to_s.downcase.scan(/[a-z0-9]{3,}/)
        .reject { |token| stopwords.include?(token) }
        .uniq
      rare_tokens = tokens
        .map { |token| [token, lexical_document_frequency(token)] }
        .sort_by { |token, frequency| [frequency, token] }
        .first(10)
        .map(&:first)
      phrases = (identifiers + names).map { |phrase| %Q{"#{phrase}"} }
      (phrases + rare_tokens).uniq.join(" OR ")
    end

    def lexical_document_frequency(token)
      match = Sequel.lit("search_vector @@ plainto_tsquery('english', ?)", token)
      @db[:semantic_documents]
        .where(workspace_id: workspace_id, source_type: "interaction")
        .where(match)
        .count
    end

    def semantic_dataset(model:, source_ids: nil, include_bursts: true)
      dataset = @db[:semantic_documents]
        .where(workspace_id: workspace_id, source_type: "interaction", embedding_model: model)
      dataset = dataset.where(unit_type: "overview") unless include_bursts
      source_ids ? dataset.where(source_id: source_ids) : dataset
    end

    def collapse_by_source(rows)
      rows.each_with_object([]) do |row, collapsed|
        existing_index = collapsed.index { |candidate| candidate[:source_id] == row[:source_id] }
        unless existing_index
          collapsed << row.merge(matched_bursts: burst_spans(row))
          next
        end

        ranked_parent = collapsed[existing_index]
        combined_bursts = (Array(ranked_parent[:matched_bursts]) + burst_spans(row))
          .uniq { |span| span["unit_key"] }
          .first(3)
        if ranked_parent[:unit_type] != "burst" && row[:unit_type] == "burst"
          ranked_parent = ranked_parent.merge(
            unit_type: row[:unit_type],
            unit_key: row[:unit_key],
            position: row[:position],
            content: row[:content],
            metadata_json: row[:metadata_json]
          )
        end
        collapsed[existing_index] = ranked_parent.merge(matched_bursts: combined_bursts)
      end
    end

    def burst_spans(row)
      return [] unless row[:unit_type] == "burst"

      metadata = parsed_metadata(row[:metadata_json])
      [{
        "unit_key" => row[:unit_key],
        "kind" => metadata["signal_kind"],
        "text" => metadata["excerpt"]
      }.compact]
    end

    def recency_ranked_documents(source_ids)
      return [] if source_ids.empty?

      @db[:interactions]
        .where(workspace_id: workspace_id, id: source_ids)
        .reverse_order(:occurred_at, :id)
        .select(:id, :occurred_at)
        .all
        .map { |interaction| {source_id: interaction[:id], occurred_at: interaction[:occurred_at]} }
    end

    def reciprocal_rank_fusion(rankings)
      fused = {}
      rankings.each do |ranker, rows|
        rows.each_with_index do |row, index|
          source_id = row[:source_id]
          candidate = fused[source_id] ||= {
            source_id: source_id,
            rrf_score: 0.0,
            retrieval_signals: [],
            evidence_spans: [],
            best_row: nil
          }
          candidate[:rrf_score] += 1.0 / (RRF_K + index + 1)
          candidate[:retrieval_signals] << {
            "ranker" => ranker.to_s,
            "rank" => index + 1,
            "similarity" => row[:similarity]&.round(6),
            "lexical_score" => row[:lexical_score]&.to_f&.round(6),
            "occurred_at" => row[:occurred_at]&.iso8601
          }.compact
          candidate[:evidence_spans] = (candidate[:evidence_spans] + Array(row[:matched_bursts]))
            .uniq { |span| span["unit_key"] }
            .first(3)
          candidate[:best_row] = preferred_match(candidate[:best_row], row)
        end
      end

      fused.values.sort_by { |candidate| -candidate[:rrf_score] }.map do |candidate|
        (candidate[:best_row] || {}).merge(
          source_id: candidate[:source_id],
          rrf_score: candidate[:rrf_score],
          matched_bursts: candidate[:evidence_spans],
          retrieval_signals: candidate[:retrieval_signals]
        )
      end
    end

    def preferred_match(current, candidate)
      return candidate unless current
      return candidate if candidate[:unit_type] == "burst" && current[:unit_type] != "burst"
      return current if current[:unit_type] == "burst" && candidate[:unit_type] != "burst"

      candidate_score = candidate[:similarity].to_f + candidate[:lexical_score].to_f
      current_score = current[:similarity].to_f + current[:lexical_score].to_f
      candidate_score > current_score ? candidate : current
    end

    def parsed_metadata(value)
      JSON.parse(value.to_s)
    rescue JSON::ParserError
      {}
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
