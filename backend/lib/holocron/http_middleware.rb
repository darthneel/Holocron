# frozen_string_literal: true

require "json"
require "securerandom"
require "time"

module Holocron
  class ServerTimingMiddleware
    HEADER = "Server-Timing"

    def initialize(app)
      @app = app
    end

    def call(env)
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      status, headers, body = @app.call(env)
      duration_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1_000
      updated_headers = headers.dup
      updated_headers[HEADER] = format("app;dur=%.1f", duration_ms)
      [status, updated_headers, body]
    end
  end

  class RequestIdMiddleware
    HEADER = "X-Request-ID"
    ENV_KEY = "holocron.request_id"
    VALID_REQUEST_ID = /\A[a-zA-Z0-9._:-]{1,128}\z/

    def initialize(app)
      @app = app
    end

    def call(env)
      supplied = env["HTTP_X_REQUEST_ID"].to_s
      request_id = supplied.match?(VALID_REQUEST_ID) ? supplied : SecureRandom.uuid
      env[ENV_KEY] = request_id
      status, headers, body = @app.call(env)
      headers[HEADER] = request_id
      [status, headers, body]
    end
  end

  class CorsMiddleware
    LOCAL_ORIGIN = %r{\Ahttp://(?:localhost|127\.0\.0\.1)(?::\d+)?\z}
    ALLOW_HEADERS = "Content-Type, X-Holocron-Actor-Email, X-Request-ID"
    ALLOW_METHODS = "GET, POST, PATCH, OPTIONS"
    EXPOSE_HEADERS = "X-Request-ID, Server-Timing"

    def initialize(app)
      @app = app
      configured = ENV["FRONTEND_ORIGINS"] || ENV["FRONTEND_ORIGIN"]
      @allowed_origins = configured.to_s.split(",").map(&:strip).reject(&:empty?).freeze
    end

    def call(env)
      origin = env["HTTP_ORIGIN"].to_s
      allowed_origin = origin if origin_allowed?(origin)

      if env["REQUEST_METHOD"] == "OPTIONS"
        return [204, cors_headers({}, allowed_origin), []]
      end

      status, headers, body = @app.call(env)
      [status, cors_headers(headers, allowed_origin), body]
    end

    private

    def origin_allowed?(origin)
      return false if origin.empty?
      return @allowed_origins.include?(origin) unless @allowed_origins.empty?

      origin.match?(LOCAL_ORIGIN)
    end

    def cors_headers(headers, origin)
      updated = headers.dup
      updated["Vary"] = merge_vary(updated["Vary"], "Origin")
      return updated unless origin

      updated["Access-Control-Allow-Origin"] = origin
      updated["Access-Control-Allow-Headers"] = ALLOW_HEADERS
      updated["Access-Control-Allow-Methods"] = ALLOW_METHODS
      updated["Access-Control-Expose-Headers"] = EXPOSE_HEADERS
      updated
    end

    def merge_vary(current, value)
      values = current.to_s.split(",").map(&:strip).reject(&:empty?)
      values << value unless values.include?(value)
      values.join(", ")
    end
  end

  class JsonErrorMiddleware
    def initialize(app, logger: $stderr)
      @app = app
      @logger = logger
    end

    def call(env)
      @app.call(env)
    rescue Errno::ECONNRESET, Errno::EPIPE
      raise
    rescue StandardError => error
      request_id = env[RequestIdMiddleware::ENV_KEY] || SecureRandom.uuid
      @logger.puts JSON.generate(
        timestamp: Time.now.utc.iso8601,
        level: "error",
        request_id: request_id,
        method: env["REQUEST_METHOD"],
        path: env["PATH_INFO"],
        error_class: error.class.name,
        error: error.message
      )
      body = JSON.generate(error: "Internal server error.", request_id: request_id)
      [
        500,
        {"Content-Type" => "application/json", "Content-Length" => body.bytesize.to_s},
        [body]
      ]
    end
  end
end
