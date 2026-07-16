# frozen_string_literal: true

require "json"
require_relative "providers/fake"
require_relative "providers/responses"

module Holocron
  module AI
    Result = Struct.new(
      :status,
      :output,
      :provider,
      :model,
      :attempt_count,
      :failure_reason,
      :provider_request_id,
      :input_tokens,
      :output_tokens,
      :duration_ms,
      keyword_init: true
    )

    class TransientError < StandardError; end
    class ProviderError < StandardError; end
    class RefusalError < StandardError; end
    class ConfigurationError < StandardError; end

    class ModelRouter
      MAX_ATTEMPTS = 2

      def initialize(provider: nil, task: :request_extraction)
        @task = task.to_sym
        @provider = provider || configured_provider
      end

      def request_extraction(prompt:, schema:)
        request(prompt: prompt, schema: schema, schema_name: "request_extraction", reasoning_effort: "low")
      end

      def briefing_generation(prompt:, schema:)
        request(prompt: prompt, schema: schema, schema_name: "grounded_briefing", reasoning_effort: "medium")
      end

      private

      def request(prompt:, schema:, schema_name:, reasoning_effort:)
        started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        attempts = 0

        begin
          attempts += 1
          response = @provider.generate(
            prompt: prompt,
            schema: schema,
            schema_name: schema_name,
            reasoning_effort: reasoning_effort
          )
          Result.new(
            status: "succeeded",
            output: response.fetch(:output),
            provider: @provider.name,
            model: response[:model] || @provider.model,
            attempt_count: attempts,
            provider_request_id: response[:provider_request_id],
            input_tokens: response[:input_tokens],
            output_tokens: response[:output_tokens],
            duration_ms: elapsed_ms(started_at)
          )
        rescue TransientError => error
          retry if attempts < MAX_ATTEMPTS
          failure_result("failed", error, attempts, started_at)
        rescue RefusalError => error
          failure_result("refused", error, attempts, started_at)
        rescue ConfigurationError, ProviderError, JSON::ParserError, KeyError => error
          failure_result("failed", error, attempts, started_at)
        end
      end

      def configured_provider
        provider_name = ENV.fetch(provider_environment_key, "fake").downcase
        model = ENV.fetch(model_environment_key, default_model(provider_name))
        case provider_name
        when "fake"
          Providers::Fake.new(model: model)
        when "openai"
          Providers::Responses.new(
            name: "openai",
            endpoint: "https://api.openai.com/v1/responses",
            api_key: ENV["OPENAI_API_KEY"],
            model: model
          )
        when "vercel"
          Providers::Responses.new(
            name: "vercel",
            endpoint: "https://ai-gateway.vercel.sh/v1/responses",
            api_key: ENV["AI_GATEWAY_API_KEY"],
            model: model
          )
        when "openrouter"
          Providers::Responses.new(
            name: "openrouter",
            endpoint: "https://openrouter.ai/api/v1/responses",
            api_key: ENV["OPENROUTER_API_KEY"],
            model: model,
            extra_headers: {"X-Title" => "Holocron"}
          )
        else
          raise ConfigurationError, "Unsupported #{task_label} provider: #{provider_name}."
        end
      end

      def provider_environment_key
        @task == :briefing_generation ? "AI_BRIEFING_GENERATION_PROVIDER" : "AI_REQUEST_EXTRACTION_PROVIDER"
      end

      def model_environment_key
        @task == :briefing_generation ? "AI_BRIEFING_GENERATION_MODEL" : "AI_REQUEST_EXTRACTION_MODEL"
      end

      def default_model(provider_name)
        if @task == :briefing_generation
          return "fake-briefing-generator-v1" if provider_name == "fake"
          return "gpt-5.6-terra" if provider_name == "openai"

          "openai/gpt-5.6-terra"
        else
          return "fake-request-extractor-v1" if provider_name == "fake"
          return "gpt-5.6-luna" if provider_name == "openai"

          "openai/gpt-5.6-luna"
        end
      end

      def task_label
        @task.to_s.tr("_", " ")
      end

      def failure_result(status, error, attempts, started_at)
        Result.new(
          status: status,
          provider: @provider.respond_to?(:name) ? @provider.name : "configuration",
          model: @provider.respond_to?(:model) ? @provider.model : "unconfigured",
          attempt_count: [attempts, 1].max,
          failure_reason: error.message.to_s[0, 1_000],
          duration_ms: elapsed_ms(started_at)
        )
      end

      def elapsed_ms(started_at)
        ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1_000).round
      end
    end
  end
end
