# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Holocron
  module AI
    module Providers
      class Responses
        attr_reader :name, :model

        def initialize(name:, endpoint:, api_key:, model:, extra_headers: {}, transport: nil)
          @name = name
          @endpoint = URI(endpoint)
          @api_key = api_key.to_s
          @model = model
          @extra_headers = extra_headers
          @transport = transport || method(:perform_request)
        end

        def generate(prompt:, schema:, schema_name: "structured_output", reasoning_effort: "low")
          raise ConfigurationError, "#{name} API key is not configured." if @api_key.empty?

          response = @transport.call(
            @endpoint,
            request_body(prompt, schema, schema_name: schema_name, reasoning_effort: reasoning_effort),
            request_headers
          )
          status = response.fetch(:status).to_i
          body = response.fetch(:body).to_s
          raise TransientError, provider_message(body, status) if status == 429 || status >= 500
          raise ProviderError, provider_message(body, status) unless status.between?(200, 299)

          payload = JSON.parse(body)
          content = payload.fetch("output", []).flat_map { |item| item.fetch("content", []) }
          refusal = content.find { |item| item["type"] == "refusal" }
          raise RefusalError, refusal.fetch("refusal", "The model refused this request.") if refusal

          output_text = content.find { |item| item["type"] == "output_text" }&.fetch("text", nil)
          raise TransientError, "#{name} returned no structured output." unless output_text

          usage = payload.fetch("usage", {})
          {
            output: JSON.parse(output_text),
            provider_request_id: payload["id"],
            model: payload["model"] || model,
            input_tokens: usage["input_tokens"],
            output_tokens: usage["output_tokens"]
          }
        end

        private

        def request_body(prompt, schema, schema_name:, reasoning_effort:)
          JSON.generate(
            model: model,
            input: [
              {
                role: "developer",
                content: [{type: "input_text", text: prompt.fetch(:instructions)}]
              },
              {
                role: "user",
                content: [{type: "input_text", text: prompt.fetch(:input)}]
              }
            ],
            reasoning: {effort: reasoning_effort},
            text: {
              format: {
                type: "json_schema",
                name: schema_name,
                strict: true,
                schema: schema
              }
            },
            store: false
          )
        end

        def request_headers
          {
            "Authorization" => "Bearer #{@api_key}",
            "Content-Type" => "application/json"
          }.merge(@extra_headers)
        end

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
          raise TransientError, "#{name} request failed: #{error.message}"
        end

        def provider_message(body, status)
          message = JSON.parse(body).dig("error", "message")
          "#{name} returned HTTP #{status}: #{message || 'request failed'}"
        rescue JSON::ParserError
          "#{name} returned HTTP #{status}."
        end
      end
    end
  end
end
