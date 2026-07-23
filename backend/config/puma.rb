# frozen_string_literal: true

min_threads = Integer(ENV.fetch("PUMA_MIN_THREADS", "1"))
max_threads = Integer(ENV.fetch("PUMA_MAX_THREADS", "5"))

threads min_threads, max_threads
port ENV.fetch("PORT", "9292")
environment ENV.fetch("RACK_ENV", "development")

workers Integer(ENV.fetch("WEB_CONCURRENCY", "0"))
preload_app! if Integer(ENV.fetch("WEB_CONCURRENCY", "0")).positive?

briefing_worker = nil
after_booted do
  next if ENV.fetch("BRIEFING_GENERATION_MODE", "async") == "disabled"

  require_relative "../lib/holocron/briefings"
  briefing_worker = Thread.new do
    Thread.current.name = "briefing-generation-worker"
    Holocron::BriefingGenerationJobs.run_forever
  end
end

after_stopped do
  briefing_worker&.kill
  briefing_worker&.join
end

plugin :tmp_restart
