# frozen_string_literal: true

require "securerandom"
require "time"
require_relative "database"
require_relative "semantic_index"

module Holocron
  module SemanticIndexJobs
    DEFAULT_POLL_INTERVAL_SECONDS = 2.0
    MAX_RETRY_DELAY_SECONDS = 300

    module_function

    def enqueue!(workspace_id:, interaction_id:, db: Database.db, now: Time.now.utc)
      values = {
        id: SecureRandom.uuid,
        workspace_id: workspace_id,
        interaction_id: interaction_id,
        status: "pending",
        revision: 1,
        attempts: 0,
        available_at: now,
        locked_at: nil,
        locked_by: nil,
        last_error: nil,
        last_indexed_at: nil,
        created_at: now,
        updated_at: now
      }
      db[:semantic_index_jobs]
        .insert_conflict(
          target: :interaction_id,
          update: {
            status: "pending",
            revision: Sequel[:semantic_index_jobs][:revision] + 1,
            available_at: now,
            locked_at: nil,
            locked_by: nil,
            last_error: nil,
            updated_at: now
          }
        )
        .insert(values)
    end

    def inline?
      ENV.fetch("SEMANTIC_INDEX_MODE", "inline") == "inline"
    end

    def process_inline!(workspace:, interaction_id:)
      return unless inline?

      run_once(worker_id: "inline-#{Process.pid}", interaction_id: interaction_id)
    end

    def run_once(worker_id: worker_identity, interaction_id: nil)
      job = claim!(worker_id: worker_id, interaction_id: interaction_id)
      return false unless job

      workspace = Database.db[:workspaces].where(id: job[:workspace_id]).first
      unless workspace
        complete!(job: job, worker_id: worker_id)
        return true
      end

      SemanticIndex.new(workspace: workspace).refresh_interaction!(interaction_id: job[:interaction_id])
      complete!(job: job, worker_id: worker_id)
      true
    rescue StandardError => error
      fail!(job: job, worker_id: worker_id, error: error) if job
      warn "Semantic index job failed: #{error.class}: #{error.message}"
      false
    end

    def run_forever(poll_interval: DEFAULT_POLL_INTERVAL_SECONDS, worker_id: worker_identity)
      loop do
        processed = run_once(worker_id: worker_id)
        sleep(poll_interval) unless processed
      end
    end

    def worker_identity
      "semantic-index-#{Process.pid}-#{SecureRandom.hex(4)}"
    end

    def claim!(worker_id:, interaction_id: nil)
      db = Database.db
      now = Time.now.utc
      db.transaction do
        jobs = db[:semantic_index_jobs]
          .where(status: "pending")
          .where { available_at <= now }
          .order(:available_at, :created_at)
        jobs = jobs.where(interaction_id: interaction_id) if interaction_id
        job = jobs.for_update.skip_locked.first
        next unless job

        claimed = db[:semantic_index_jobs]
          .where(id: job[:id], status: "pending", revision: job[:revision])
          .update(status: "running", locked_at: now, locked_by: worker_id, updated_at: now)
        next unless claimed == 1

        job.merge(status: "running", locked_at: now, locked_by: worker_id)
      end
    end

    def complete!(job:, worker_id:)
      now = Time.now.utc
      Database.db[:semantic_index_jobs]
        .where(id: job[:id], status: "running", locked_by: worker_id, revision: job[:revision])
        .update(
          status: "completed",
          locked_at: nil,
          locked_by: nil,
          last_error: nil,
          last_indexed_at: now,
          updated_at: now
        )
    end

    def fail!(job:, worker_id:, error:)
      attempts = job[:attempts].to_i + 1
      now = Time.now.utc
      Database.db[:semantic_index_jobs]
        .where(id: job[:id], status: "running", locked_by: worker_id, revision: job[:revision])
        .update(
          status: "pending",
          attempts: attempts,
          available_at: now + retry_delay(attempts),
          locked_at: nil,
          locked_by: nil,
          last_error: "#{error.class}: #{error.message}".slice(0, 4_000),
          updated_at: now
        )
    end

    def retry_delay(attempts)
      [2**[attempts, 8].min, MAX_RETRY_DELAY_SECONDS].min
    end
    private_class_method :claim!, :complete!, :fail!, :retry_delay
  end
end
