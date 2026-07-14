# frozen_string_literal: true

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

      def initialize(provider: nil)
        @provider = provider || configured_provider
      end

      def request_extraction(prompt:, schema:)
        started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        attempts = 0

        begin
          attempts += 1
          response = @provider.generate(prompt: prompt, schema: schema)
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

      private

      def configured_provider
        provider_name = ENV.fetch("AI_REQUEST_EXTRACTION_PROVIDER", "fake").downcase
        case provider_name
        when "fake"
          Providers::Fake.new(model: ENV.fetch("AI_REQUEST_EXTRACTION_MODEL", "fake-request-extractor-v1"))
        when "openai"
          Providers::Responses.new(
            name: "openai",
            endpoint: "https://api.openai.com/v1/responses",
            api_key: ENV["OPENAI_API_KEY"],
            model: ENV.fetch("AI_REQUEST_EXTRACTION_MODEL", "gpt-5.6-luna")
          )
        when "vercel"
          Providers::Responses.new(
            name: "vercel",
            endpoint: "https://ai-gateway.vercel.sh/v1/responses",
            api_key: ENV["AI_GATEWAY_API_KEY"],
            model: ENV.fetch("AI_REQUEST_EXTRACTION_MODEL", "openai/gpt-5.6-luna")
          )
        when "openrouter"
          Providers::Responses.new(
            name: "openrouter",
            endpoint: "https://openrouter.ai/api/v1/responses",
            api_key: ENV["OPENROUTER_API_KEY"],
            model: ENV.fetch("AI_REQUEST_EXTRACTION_MODEL", "openai/gpt-5.6-luna"),
            extra_headers: {"X-Title" => "Holocron"}
          )
        else
          raise ConfigurationError, "Unsupported request extraction provider: #{provider_name}."
        end
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
