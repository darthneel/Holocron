# frozen_string_literal: true

require "sequel"
require "uri"

Sequel.default_timezone = :utc

module Holocron
  module Database
    ROOT = File.expand_path("../..", __dir__)
    DEFAULT_DATABASE_URL = "postgres://localhost:5432/holocron_development"
    DEFAULT_CONNECTION_VALIDATION_TIMEOUT = 30
    MIGRATIONS_PATH = File.join(ROOT, "db", "migrations")
    DB_MUTEX = Mutex.new

    module_function

    def db
      return @db if @db

      DB_MUTEX.synchronize do
        @db ||= connect
      end
    end

    def create!
      uri = URI.parse(database_url)
      database_name = uri.path.delete_prefix("/")
      raise "DATABASE_URL must include a database name." if database_name.empty?

      uri.path = "/postgres"
      admin = Sequel.connect(uri.to_s, max_connections: 1)
      return false if admin[:pg_database].where(datname: database_name).any?

      admin.run("CREATE DATABASE #{admin.literal(Sequel.identifier(database_name))}")
      true
    ensure
      admin&.disconnect
    end

    def migrate!
      Sequel.extension :migration
      Sequel::Migrator.run(db, MIGRATIONS_PATH)
    end

    def disconnect!
      DB_MUTEX.synchronize do
        @db&.disconnect
        @db = nil
      end
    end

    def database_url
      ENV.fetch("DATABASE_URL", DEFAULT_DATABASE_URL)
    end

    def connect
      database = Sequel.connect(
        database_url,
        max_connections: positive_integer_env("DATABASE_POOL_SIZE", 5),
        pool_timeout: positive_integer_env("DATABASE_POOL_TIMEOUT", 5)
      )
      database.extension(:connection_validator)
      database.pool.connection_validation_timeout = non_negative_integer_env(
        "DATABASE_CONNECTION_VALIDATION_TIMEOUT",
        DEFAULT_CONNECTION_VALIDATION_TIMEOUT
      )
      database.extension(:transaction_connection_validator)
      database
    rescue StandardError
      database&.disconnect
      raise
    end

    def positive_integer_env(name, default)
      value = Integer(ENV.fetch(name, default.to_s), exception: false)
      return value if value&.positive?

      raise ArgumentError, "#{name} must be a positive integer."
    end

    def non_negative_integer_env(name, default)
      value = Integer(ENV.fetch(name, default.to_s), exception: false)
      return value if value&.>= 0

      raise ArgumentError, "#{name} must be a non-negative integer."
    end
  end
end
