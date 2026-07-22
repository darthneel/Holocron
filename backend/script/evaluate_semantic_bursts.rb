# frozen_string_literal: true

require "fileutils"
require_relative "../lib/holocron/database"
require_relative "../lib/holocron/semantic_burst_labeling_evaluation"

module Holocron
  class SemanticBurstEvaluationScript
    def initialize(output: $stdout)
      @db = Database.db
      @output = output
    end

    def run(workspace_slug: ENV["WORKSPACE_SLUG"], report_path: ENV["SEMANTIC_LABELING_REPORT_PATH"])
      ensure_schema!
      workspaces = @db[:workspaces].order(:slug)
      workspaces = workspaces.where(slug: workspace_slug) if workspace_slug && !workspace_slug.empty?
      rows = workspaces.all
      raise "No workspace matched #{workspace_slug.inspect}." if rows.empty?

      rows.each do |workspace|
        result = SemanticBurstLabelingEvaluation.new(workspace: workspace).run
        path = report_path || File.expand_path("../tmp/semantic-labeling-review-#{result.fetch(:id)}.json", __dir__)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, JSON.pretty_generate(SemanticBurstLabelingEvaluation.export_review(run_id: result.fetch(:id))))
        summary = result.fetch(:summary)
        @output.puts format(
          "%s run=%s baseline_bursts=%d proposed_bursts=%d llm_calls=%d accepted=%d report=%s",
          workspace.fetch(:slug), result.fetch(:id), summary.fetch("baseline_burst_count"),
          summary.fetch("proposed_burst_count"), summary.fetch("classifier").fetch(:calls),
          summary.fetch("classifier").fetch(:accepted), path
        )
      end
    ensure
      Database.disconnect!
    end

    private

    def ensure_schema!
      return if @db.table_exists?(:semantic_labeling_runs)

      raise "semantic_labeling_runs does not exist. Run `bundle exec rake db:migrate` first."
    end
  end
end

Holocron::SemanticBurstEvaluationScript.new.run if $PROGRAM_NAME == __FILE__
