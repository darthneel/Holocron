# frozen_string_literal: true

require "set"
require "time"
require_relative "ask_ai_generation"
require_relative "database"
require_relative "semantic_index"

module Holocron
  module AskAI
    MIN_QUESTION_LENGTH = 3
    MAX_QUESTION_LENGTH = 1_000
    MAX_SOURCES = 6
    MAX_EXCERPT_LENGTH = 800
    TOPIC_STOPWORDS = %w[
      a about after all also an and are as associated at be been before being between by can
      could did discuss discussed discussion do does for from had has have having history how i
      ignore in into is it know me more most of on or our please restrictions say summarize tell
      than that the their them then there these they this those to us was we were what when where
      which who why will with workspace would you your
    ].to_set.freeze

    class ValidationError < StandardError
      attr_reader :fields

      def initialize(fields)
        super("Validation failed.")
        @fields = fields
      end
    end

    Result = Struct.new(
      :status, :question, :answer, :claims, :sources, :limitations,
      :provider, :model, :attempt_count, :failure_reason, :provider_request_id,
      :input_tokens, :output_tokens, :duration_ms, :validation_errors,
      keyword_init: true
    )

    module_function

    def answer(question:, workspace:, router: nil, semantic_index: nil)
      normalized_question = validate_question(question)
      resolution = resolve_entities(normalized_question, workspace: workspace)

      if resolution.fetch(:ambiguity_candidates).any?
        return disambiguation_result(normalized_question, resolution.fetch(:ambiguity_candidates))
      end
      if unknown_named_entity?(normalized_question, resolution)
        return insufficient_result(normalized_question, workspace_specific: false)
      end

      retrieval = (semantic_index || SemanticIndex.new(workspace: workspace)).search_interactions(
        query: normalized_question,
        limit: MAX_SOURCES,
        balanced_person_ids: resolution.fetch(:balanced_person_ids),
        per_person_limit: 2,
        max_per_person: resolution.fetch(:balanced_person_ids).any? ? 3 : nil,
        fused: true
      )
      interactions = qualifying_interactions(
        retrieval.fetch(:interactions),
        question: normalized_question,
        workspace: workspace,
        resolution: resolution
      )
      sources = build_sources(interactions, resolution: resolution)
      if sources.empty?
        return insufficient_result(
          normalized_question,
          workspace_specific: workspace_override_attempt?(normalized_question)
        )
      end

      generation = AskAIGeneration.generate(
        question: normalized_question,
        sources: sources,
        router: router
      )
      return generation_failure_result(normalized_question, generation) unless generation.status == "succeeded"

      cited_refs = generation.claims.flat_map { |claim| claim.fetch(:source_refs) }.to_set
      cited_sources = sources.select { |source| cited_refs.include?(source.fetch("source_ref")) }
      Result.new(
        status: "succeeded",
        question: normalized_question,
        answer: generation.answer,
        claims: generation.claims,
        sources: cited_sources,
        limitations: generation.limitations,
        provider: generation.provider,
        model: generation.model,
        attempt_count: generation.attempt_count,
        provider_request_id: generation.provider_request_id,
        input_tokens: generation.input_tokens,
        output_tokens: generation.output_tokens,
        duration_ms: generation.duration_ms,
        validation_errors: {}
      )
    rescue AI::ConfigurationError, AI::ProviderError, AI::TransientError => error
      Result.new(
        status: "failed",
        question: normalized_question || question.to_s.strip,
        claims: [],
        sources: [],
        limitations: [],
        failure_reason: error.message.to_s[0, 1_000],
        validation_errors: {}
      )
    end

    def validate_question(value)
      errors = {}
      question = value.is_a?(String) ? value.strip.gsub(/\s+/, " ") : nil
      if !question || question.length < MIN_QUESTION_LENGTH
        errors["question"] = "Question must be at least #{MIN_QUESTION_LENGTH} characters."
      elsif question.length > MAX_QUESTION_LENGTH
        errors["question"] = "Question must be no more than #{MAX_QUESTION_LENGTH} characters."
      end
      raise ValidationError, errors unless errors.empty?

      question
    end

    def resolve_entities(question, workspace:)
      db = Database.db
      people = db[:people].where(workspace_id: workspace.fetch(:id)).all
      organizations = db[:organizations].where(workspace_id: workspace.fetch(:id)).all
      normalized_question = normalized_words(question)
      exact_people = people.select do |person|
        phrase_present?(normalized_question, normalized_words(person.fetch(:display_name)))
      end
      exact_organizations = organizations.select do |organization|
        phrase_present?(normalized_question, normalized_words(organization.fetch(:name)))
      end

      ambiguity_candidates = []
      if exact_people.empty?
        question_tokens = normalized_question.split
        people.group_by { |person| normalized_words(person.fetch(:display_name)).split.first }
          .each do |first_name, candidates|
            next unless first_name && question_tokens.include?(first_name) && candidates.length > 1

            ambiguity_candidates.concat(candidates.map { |person| person.fetch(:display_name) })
          end
      end

      organization_ids = exact_organizations.map { |organization| organization.fetch(:id) }
      organization_people = people.select { |person| organization_ids.include?(person[:organization_id]) }
      balanced_person_ids = (exact_people + organization_people).map { |person| person.fetch(:id) }.uniq
      organizations_by_id = organizations.to_h { |organization| [organization.fetch(:id), organization] }
      people_by_id = people.to_h { |person| [person.fetch(:id), person] }

      {
        exact_people: exact_people,
        exact_organizations: exact_organizations,
        balanced_person_ids: balanced_person_ids,
        restricted_person_ids: balanced_person_ids.to_set,
        restrict_to_entities: exact_people.any? || exact_organizations.any?,
        ambiguity_candidates: ambiguity_candidates.uniq.sort,
        people_by_id: people_by_id,
        organizations_by_id: organizations_by_id,
        entity_tokens: (exact_people.map { |person| person.fetch(:display_name) } +
          exact_organizations.map { |organization| organization.fetch(:name) })
          .flat_map { |name| normalized_words(name).split }
          .to_set
      }
    end

    def qualifying_interactions(interactions, question:, workspace:, resolution:)
      topic_tokens = question_topic_tokens(question, resolution.fetch(:entity_tokens))
      Array(interactions).select do |interaction|
        next false unless interaction[:workspace_id] == workspace.fetch(:id)
        if resolution.fetch(:restrict_to_entities)
          next false unless resolution.fetch(:restricted_person_ids).include?(interaction[:person_id])
        end
        next true if topic_tokens.empty?

        interaction_tokens = normalized_words([
          interaction[:summary],
          interaction[:matched_excerpt],
          Array(interaction[:matched_evidence_spans]).filter_map { |span| span["text"] }
        ].flatten.compact.join(" ")).split.to_set
        topic_tokens.any? do |topic|
          interaction_tokens.any? { |token| related_token?(topic, token) }
        end
      end.first(MAX_SOURCES)
    end

    def build_sources(interactions, resolution:)
      interactions.first(MAX_SOURCES).map do |interaction|
        person = resolution.fetch(:people_by_id)[interaction[:person_id]]
        organization = person && resolution.fetch(:organizations_by_id)[person[:organization_id]]
        excerpt = interaction[:matched_excerpt].to_s.strip
        excerpt = interaction[:summary].to_s.strip if excerpt.empty?
        excerpt = excerpt.gsub(/\s+/, " ")[0, MAX_EXCERPT_LENGTH]
        {
          "source_ref" => "interaction:#{interaction.fetch(:id)}",
          "source_type" => "interaction",
          "source_id" => interaction.fetch(:id),
          "person_name" => person&.fetch(:display_name, nil) || interaction[:person_name],
          "organization_name" => organization&.fetch(:name, nil),
          "interaction_type" => interaction.fetch(:interaction_type),
          "occurred_at" => iso8601(interaction[:occurred_at]),
          "excerpt" => excerpt
        }
      end
    end

    def question_topic_tokens(question, entity_tokens)
      normalized_words(question).split
        .reject { |token| TOPIC_STOPWORDS.include?(token) || entity_tokens.include?(token) }
        .select { |token| token.length >= 3 }
        .to_set
    end

    def related_token?(left, right)
      return true if left == right

      prefix_length = [left.length, right.length, 6].min
      prefix_length >= 5 && left[0, prefix_length] == right[0, prefix_length]
    end

    def unknown_named_entity?(question, resolution)
      return false if resolution.fetch(:restrict_to_entities)

      question.match?(/\b(?:about|with)\s+(?:the\s+)?[A-Z][A-Za-z'’-]+(?:\s+[A-Z][A-Za-z'’-]+)+/)
    end

    def workspace_override_attempt?(question)
      question.match?(/\b(?:ignore|bypass|cross)[^.!?]{0,80}\bworkspace\b|\bworkspace restrictions?\b/i)
    end

    def disambiguation_result(question, candidates)
      names = candidates.join(" and ")
      Result.new(
        status: "succeeded",
        question: question,
        answer: "I found more than one matching person: #{names}.",
        claims: [],
        sources: [],
        limitations: ["Clarify which #{normalized_words(candidates.first).split.first.capitalize} you mean."],
        validation_errors: {}
      )
    end

    def insufficient_result(question, workspace_specific:)
      limitation = if workspace_specific
        "No relevant interactions were found in this workspace."
      else
        "No relevant interactions were found."
      end
      Result.new(
        status: "succeeded",
        question: question,
        answer: "I could not find enough interaction evidence to answer that question.",
        claims: [],
        sources: [],
        limitations: [limitation],
        validation_errors: {}
      )
    end

    def generation_failure_result(question, generation)
      Result.new(
        status: generation.status,
        question: question,
        claims: [],
        sources: [],
        limitations: [],
        provider: generation.provider,
        model: generation.model,
        attempt_count: generation.attempt_count,
        failure_reason: generation.failure_reason,
        provider_request_id: generation.provider_request_id,
        input_tokens: generation.input_tokens,
        output_tokens: generation.output_tokens,
        duration_ms: generation.duration_ms,
        validation_errors: generation.validation_errors
      )
    end

    def normalized_words(value)
      value.to_s.downcase.gsub(/[^a-z0-9]+/, " ").strip
    end

    def phrase_present?(haystack, needle)
      !needle.empty? && " #{haystack} ".include?(" #{needle} ")
    end

    def iso8601(value)
      value.respond_to?(:iso8601) ? value.iso8601 : value.to_s
    end
  end
end
