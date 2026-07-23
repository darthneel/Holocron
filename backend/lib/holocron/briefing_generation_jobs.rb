# frozen_string_literal: true

require "securerandom"
require "time"
require_relative "database"

module Holocron
  module BriefingGenerationJobs
    DEFAULT_POLL_INTERVAL_SECONDS = 0.5
    MAX_ATTEMPTS = 3
    MAX_RETRY_DELAY_SECONDS = 60
    STALE_LOCK_SECONDS = 300

    module_function

    def enqueue!(workspace_id:, briefing_id:, db: Database.db, now: Time.now.utc)
      values = {
        id: SecureRandom.uuid,
        workspace_id: workspace_id,
        briefing_id: briefing_id,
        status: "pending",
        revision: 1,
        attempts: 0,
        available_at: now,
        locked_at: nil,
        locked_by: nil,
        last_error: nil,
        completed_at: nil,
        created_at: now,
        updated_at: now
      }
      db[:briefing_generation_jobs]
        .insert_conflict(
          target: :briefing_id,
          update: {
            status: "pending",
            revision: Sequel[:briefing_generation_jobs][:revision] + 1,
            attempts: 0,
            available_at: now,
            locked_at: nil,
            locked_by: nil,
            last_error: nil,
            completed_at: nil,
            updated_at: now
          }
        )
        .insert(values)
      db[:briefings].where(id: briefing_id).update(generation_status: "pending", updated_at: now)
    end

    def run_once(worker_id: worker_identity, briefing_id: nil, router: nil)
      job = claim!(worker_id: worker_id, briefing_id: briefing_id)
      return false unless job

      db = Database.db
      workspace = db[:workspaces].where(id: job[:workspace_id]).first
      briefing = db[:briefings].where(id: job[:briefing_id], workspace_id: job[:workspace_id]).first
      unless workspace && briefing
        complete!(job: job, worker_id: worker_id)
        return true
      end

      if briefing[:generation_status] == "ready"
        complete!(job: job, worker_id: worker_id)
        return true
      end

      actor = db[:workspace_members].where(
        id: briefing[:created_by_workspace_member_id],
        workspace_id: workspace[:id],
        status: "active"
      ).first
      raise "Briefing creator is no longer an active workspace member." unless actor

      Briefings.generate_version(
        id: briefing[:id],
        attributes: {
          "expected_lock_version" => briefing[:lock_version],
          "retrieval_strategy" => "linked_recency"
        },
        workspace: workspace,
        actor: actor,
        router: router
      )
      complete!(job: job, worker_id: worker_id)
      true
    rescue StandardError => error
      fail!(job: job, worker_id: worker_id, error: error) if job
      warn "Briefing generation job failed: #{error.class}: #{error.message}"
      false
    end

    def run_forever(poll_interval: DEFAULT_POLL_INTERVAL_SECONDS, worker_id: worker_identity)
      loop do
        processed = run_once(worker_id: worker_id)
        sleep(poll_interval) unless processed
      end
    end

    def worker_identity
      "briefing-generation-#{Process.pid}-#{SecureRandom.hex(4)}"
    end

    def claim!(worker_id:, briefing_id: nil)
      db = Database.db
      now = Time.now.utc
      db.transaction do
        db[:briefing_generation_jobs]
          .where(status: "running")
          .where { locked_at < now - STALE_LOCK_SECONDS }
          .update(
            status: "pending",
            locked_at: nil,
            locked_by: nil,
            available_at: now,
            updated_at: now
          )
        jobs = db[:briefing_generation_jobs]
          .where(status: "pending")
          .where { available_at <= now }
          .order(:available_at, :created_at)
        jobs = jobs.where(briefing_id: briefing_id) if briefing_id
        job = jobs.for_update.skip_locked.first
        next unless job

        claimed = db[:briefing_generation_jobs]
          .where(id: job[:id], status: "pending", revision: job[:revision])
          .update(status: "running", locked_at: now, locked_by: worker_id, updated_at: now)
        next unless claimed == 1

        db[:briefings]
          .where(id: job[:briefing_id])
          .exclude(generation_status: "ready")
          .update(generation_status: "running", updated_at: now)
        job.merge(status: "running", locked_at: now, locked_by: worker_id)
      end
    end

    def complete!(job:, worker_id:)
      now = Time.now.utc
      Database.db.transaction do
        completed = Database.db[:briefing_generation_jobs]
          .where(id: job[:id], status: "running", locked_by: worker_id, revision: job[:revision])
          .update(
            status: "completed",
            locked_at: nil,
            locked_by: nil,
            last_error: nil,
            completed_at: now,
            updated_at: now
          )
        next if completed.zero?

        Database.db[:briefings]
          .where(id: job[:briefing_id])
          .update(generation_status: "ready", updated_at: now)
      end
    end

    def fail!(job:, worker_id:, error:)
      attempts = job[:attempts].to_i + 1
      now = Time.now.utc
      terminal = attempts >= MAX_ATTEMPTS
      Database.db.transaction do
        failed = Database.db[:briefing_generation_jobs]
          .where(id: job[:id], status: "running", locked_by: worker_id, revision: job[:revision])
          .update(
            status: terminal ? "failed" : "pending",
            attempts: attempts,
            available_at: terminal ? now : now + retry_delay(attempts),
            locked_at: nil,
            locked_by: nil,
            last_error: "#{error.class}: #{error.message}".slice(0, 4_000),
            updated_at: now
          )
        next if failed.zero?

        Database.db[:briefings]
          .where(id: job[:briefing_id])
          .update(generation_status: terminal ? "failed" : "pending", updated_at: now)
      end
    end

    def retry_delay(attempts)
      [2**[attempts, 6].min, MAX_RETRY_DELAY_SECONDS].min
    end
    private_class_method :claim!, :complete!, :fail!, :retry_delay
  end
end
