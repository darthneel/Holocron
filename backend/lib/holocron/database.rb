# frozen_string_literal: true

require "fileutils"
require "sequel"

Sequel.default_timezone = :utc

module Holocron
  module Database
    ROOT = File.expand_path("../..", __dir__)
    DEFAULT_DATABASE_PATH = File.join(ROOT, "db", "holocron.sqlite3")
    MIGRATIONS_PATH = File.join(ROOT, "db", "migrations")

    module_function

    def db
      @db ||= begin
        FileUtils.mkdir_p(File.dirname(DEFAULT_DATABASE_PATH))
        Sequel.connect(ENV.fetch("DATABASE_URL", "sqlite://#{DEFAULT_DATABASE_PATH}"))
      end
    end

    def migrate!
      Sequel.extension :migration
      Sequel::Migrator.run(db, MIGRATIONS_PATH)
    end

    def disconnect!
      @db&.disconnect
      @db = nil
    end
  end
end
