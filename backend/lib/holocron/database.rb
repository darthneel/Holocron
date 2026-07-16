# frozen_string_literal: true

require "sequel"
require "uri"

Sequel.default_timezone = :utc

module Holocron
  module Database
    ROOT = File.expand_path("../..", __dir__)
    DEFAULT_DATABASE_URL = "postgres://localhost:5432/holocron_development"
    MIGRATIONS_PATH = File.join(ROOT, "db", "migrations")

    module_function

    def db
      @db ||= Sequel.connect(
        database_url,
        max_connections: Integer(ENV.fetch("DATABASE_POOL_SIZE", "5")),
        pool_timeout: Integer(ENV.fetch("DATABASE_POOL_TIMEOUT", "5"))
      )
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
      @db&.disconnect
      @db = nil
    end

    def database_url
      ENV.fetch("DATABASE_URL", DEFAULT_DATABASE_URL)
    end
  end
end
