# frozen_string_literal: true

require "digest"
require "json"
require "net/http"
require "uri"
require_relative "model_router"

module Holocron
  module AI
    module Embeddings
      DIMENSIONS = 1536
      DEFAULT_MODEL = "text-embedding-3-small"

      Result = Struct.new(:vectors, :provider, :model, :input_tokens, :duration_ms, keyword_init: true)

      module_function

      def embed(texts, provider: nil)
        values = Array(texts).map(&:to_s)
        raise ConfigurationError, "Include at least one value to embed." if values.empty?

        selected = provider || configured_provider
        started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        response = selected.embed(values)
        vectors = response.fetch(:vectors)
        unless vectors.length == values.length && vectors.all? { |vector| vector.length == DIMENSIONS }
          raise ProviderError, "Embedding provider returned an unexpected vector shape."
        end

        Result.new(
          vectors: vectors,
          provider: selected.name,
          model: response[:model] || selected.model,
          input_tokens: response[:input_tokens],
          duration_ms: elapsed_ms(started_at)
        )
      end

      def configured_provider
        provider_name = ENV.fetch("AI_EMBEDDING_PROVIDER", "fake").downcase
        model = ENV.fetch("AI_EMBEDDING_MODEL", default_model(provider_name))
        case provider_name
        when "fake"
          FakeProvider.new(model: model)
        when "openai"
          HttpProvider.new(
            name: "openai",
            endpoint: "https://api.openai.com/v1/embeddings",
            api_key: ENV["OPENAI_API_KEY"],
            model: model
          )
        when "vercel"
          HttpProvider.new(
            name: "vercel",
            endpoint: "https://ai-gateway.vercel.sh/v1/embeddings",
            api_key: ENV["AI_GATEWAY_API_KEY"],
            model: model
          )
        else
          raise ConfigurationError, "Unsupported embedding provider: #{provider_name}."
        end
      end

      def default_model(provider_name)
        return "fake-semantic-embedding-v1" if provider_name == "fake"
        provider_name == "vercel" ? "openai/#{DEFAULT_MODEL}" : DEFAULT_MODEL
      end

      def elapsed_ms(started_at)
        ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1_000).round
      end

      class FakeProvider
        attr_reader :name, :model

        def initialize(model: "fake-semantic-embedding-v1")
          @name = "fake"
          @model = model
        end

        def embed(texts)
          {
            vectors: texts.map { |text| vector_for(text) },
            model: model,
            input_tokens: texts.sum { |text| text.split.length }
          }
        end

        private

        def vector_for(text)
          vector = Array.new(DIMENSIONS, 0.0)
          tokens = text.downcase.scan(/[a-z0-9]+/)
          tokens.each do |token|
            digest = Digest::SHA256.digest(token)
            index = digest.unpack1("L>") % DIMENSIONS
            sign = digest.getbyte(4).even? ? 1.0 : -1.0
            vector[index] += sign
          end
          magnitude = Math.sqrt(vector.sum { |value| value * value })
          return vector if magnitude.zero?

          vector.map { |value| value / magnitude }
        end
      end

      class HttpProvider
        attr_reader :name, :model

        def initialize(name:, endpoint:, api_key:, model:, transport: nil)
          @name = name
          @endpoint = URI(endpoint)
          @api_key = api_key.to_s
          @model = model
          @transport = transport || method(:perform_request)
        end

        def embed(texts)
          raise ConfigurationError, "#{name} API key is not configured." if @api_key.empty?

          response = @transport.call(
            @endpoint,
            JSON.generate(model: model, input: texts, dimensions: DIMENSIONS),
            {"Authorization" => "Bearer #{@api_key}", "Content-Type" => "application/json"}
          )
          status = response.fetch(:status).to_i
          body = response.fetch(:body).to_s
          raise TransientError, provider_message(body, status) if status == 429 || status >= 500
          raise ProviderError, provider_message(body, status) unless status.between?(200, 299)

          payload = JSON.parse(body)
          ordered = payload.fetch("data").sort_by { |item| item.fetch("index") }
          {
            vectors: ordered.map { |item| item.fetch("embedding") },
            model: payload["model"] || model,
            input_tokens: payload.dig("usage", "prompt_tokens") || payload.dig("usage", "input_tokens")
          }
        rescue JSON::ParserError, KeyError => error
          raise ProviderError, "#{name} returned an invalid embedding response: #{error.message}"
        end

        private

        def perform_request(uri, body, headers)
          request = Net::HTTP::Post.new(uri)
          headers.each { |key, value| request[key] = value }
          request.body = body
          response = Net::HTTP.start(
            uri.host,
            uri.port,
            use_ssl: uri.scheme == "https",
            open_timeout: 10,
            read_timeout: 60
          ) { |http| http.request(request) }
          {status: response.code.to_i, body: response.body}
        rescue Net::OpenTimeout, Net::ReadTimeout, IOError, SocketError => error
          raise TransientError, "#{name} embedding request failed: #{error.message}"
        end

        def provider_message(body, status)
          message = JSON.parse(body).dig("error", "message")
          "#{name} returned HTTP #{status}: #{message || 'embedding request failed'}"
        rescue JSON::ParserError
          "#{name} returned HTTP #{status} for embeddings."
        end
      end
    end
  end
end
