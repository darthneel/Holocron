# frozen_string_literal: true

require_relative "../lib/holocron/semantic_index_jobs"

trap("TERM") { exit }
trap("INT") { exit }

Holocron::SemanticIndexJobs.run_forever
