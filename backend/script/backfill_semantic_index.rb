# frozen_string_literal: true

require_relative "../lib/holocron/database"
require_relative "../lib/holocron/semantic_index"

module Holocron
  class SemanticBackfill
    def initialize(output: $stdout)
      @db = Database.db
      @output = output
    end

    def run(workspace_slug: ENV["WORKSPACE_SLUG"])
      ensure_schema!
      provider = AI::Embeddings.configured_provider
      ensure_provider_allowed!(provider)

      workspaces = @db[:workspaces].order(:slug)
      workspaces = workspaces.where(slug: workspace_slug) if workspace_slug && !workspace_slug.empty?
      rows = workspaces.all
      raise "No workspace matched #{workspace_slug.inspect}." if rows.empty?

      totals = {workspaces: 0, indexed: 0, refreshed: 0, tokens: 0}
      @output.puts "Semantic backfill using #{provider.name}/#{provider.model}"

      rows.each do |workspace|
        result = SemanticIndex.new(workspace: workspace, embedding_provider: provider).refresh_interactions!
        totals[:workspaces] += 1
        totals[:indexed] += result.fetch(:indexed_records)
        totals[:refreshed] += result.fetch(:refreshed_records)
        totals[:tokens] += result.fetch(:embedding_tokens)
        @output.puts format(
          "%-30s indexed=%d refreshed=%d embedding_tokens=%d",
          workspace.fetch(:slug),
          result.fetch(:indexed_records),
          result.fetch(:refreshed_records),
          result.fetch(:embedding_tokens)
        )
      end

      @output.puts format(
        "Complete: workspaces=%d indexed=%d refreshed=%d embedding_tokens=%d",
        totals.fetch(:workspaces), totals.fetch(:indexed), totals.fetch(:refreshed), totals.fetch(:tokens)
      )
      totals
    ensure
      Database.disconnect!
    end

    private

    def ensure_schema!
      return if @db.table_exists?(:semantic_documents)

      raise "semantic_documents does not exist. Run `bundle exec rake db:migrate` first."
    end

    def ensure_provider_allowed!(provider)
      return unless provider.name == "fake"
      return if ENV["ALLOW_FAKE_EMBEDDING_BACKFILL"] == "1"

      raise <<~MESSAGE.strip
        Refusing to backfill deterministic fake embeddings. Configure AI_EMBEDDING_PROVIDER and its API key, or set ALLOW_FAKE_EMBEDDING_BACKFILL=1 for local demonstration data.
      MESSAGE
    end
  end
end

Holocron::SemanticBackfill.new.run if $PROGRAM_NAME == __FILE__
