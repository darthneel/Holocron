# frozen_string_literal: true

require "fileutils"
require "json"
require "minitest/autorun"
require "time"
require_relative "../lib/holocron/briefing_generation"

unless ENV["RUN_LIVE_EVALS"] == "1"
  abort "Set RUN_LIVE_EVALS=1 to confirm that this suite may make billed model requests."
end

module BriefingGenerationEval
  FIXTURES = JSON.parse(File.read(File.expand_path("fixtures/briefing_generations.json", __dir__)))
  @records = []
  @started_at = Time.now.utc

  module_function

  def evaluate(outcome, fixture)
    failures = []
    return ["provider returned #{outcome.status}: #{outcome.failure_reason}"] unless outcome.status == "succeeded"

    sections = outcome.sections.to_h { |section| [section.fetch(:section_type), section] }
    fixture.dig("assertions", "section_includes")&.each do |section_type, terms|
      body = sections.fetch(section_type, {}).fetch(:body, "").downcase
      terms.each do |term|
        failures << "#{section_type} does not include #{term.inspect}" unless body.include?(term.downcase)
      end
    end
    fixture.dig("assertions", "section_source_types")&.each do |section_type, expected_types|
      actual_types = sections.fetch(section_type, {}).fetch(:sources, []).map { |source| source.fetch(:source_type) }
      expected_types.each do |type|
        failures << "#{section_type} does not cite a #{type} source" unless actual_types.include?(type)
      end
    end
    Array(fixture.dig("assertions", "limitation_includes")).each do |term|
      limitations = sections.fetch("notes", {}).fetch(:body, "")
      failures << "limitations do not include #{term.inspect}" unless limitations.downcase.include?(term.downcase)
    end

    combined_body = outcome.sections.map { |section| section.fetch(:body) }.join("\n").downcase
    Array(fixture.dig("assertions", "forbidden_terms")).each do |term|
      failures << "generated body includes forbidden term #{term.inspect}" if combined_body.include?(term.downcase)
    end
    outcome.sections.each do |section|
      next if section[:section_type] == "notes" || section[:body].empty?

      failures << "#{section[:section_type]} has material content without sources" if section[:sources].empty?
    end
    failures
  end

  def record(entry)
    @records << entry
  end

  def report
    passed = @records.count { |record| record.fetch(:failures).empty? }
    puts "\nGrounded briefing eval report"
    @records.each do |record|
      status = record.fetch(:failures).empty? ? "PASS" : "FAIL"
      puts format(
        "%-4s %-29s %s+%s tokens, %dms",
        status,
        record.fetch(:id),
        record[:input_tokens] || "?",
        record[:output_tokens] || "?",
        record[:duration_ms].to_i
      )
    end
    puts "#{passed}/#{@records.length} cases passed"

    directory = File.expand_path("../tmp/eval-results", __dir__)
    FileUtils.mkdir_p(directory)
    path = File.join(directory, "briefing-generation-#{Time.now.utc.strftime('%Y%m%dT%H%M%SZ')}.json")
    File.write(path, JSON.pretty_generate(
      suite: "grounded-briefing-v1",
      prompt_version: Holocron::BriefingGeneration::PROMPT_VERSION,
      provider: ENV["AI_BRIEFING_GENERATION_PROVIDER"],
      configured_model: ENV["AI_BRIEFING_GENERATION_MODEL"],
      started_at: @started_at.iso8601,
      completed_at: Time.now.utc.iso8601,
      records: @records
    ))
    puts "Detailed results: #{path}"
  end
end

class BriefingGenerationEvalTest < Minitest::Test
  BriefingGenerationEval::FIXTURES.each do |fixture|
    define_method("test_#{fixture.fetch('id')}") do
      outcome = Holocron::BriefingGeneration.generate(manifest: fixture.fetch("manifest"))
      failures = BriefingGenerationEval.evaluate(outcome, fixture)
      BriefingGenerationEval.record(
        id: fixture.fetch("id"),
        description: fixture.fetch("description"),
        failures: failures,
        status: outcome.status,
        failure_reason: outcome.failure_reason,
        provider: outcome.provider,
        model: outcome.model,
        provider_request_id: outcome.provider_request_id,
        attempt_count: outcome.attempt_count,
        input_tokens: outcome.input_tokens,
        output_tokens: outcome.output_tokens,
        duration_ms: outcome.duration_ms,
        validation_errors: outcome.validation_errors,
        sections: outcome.sections
      )
      assert failures.empty?, "#{fixture.fetch('description')}\n#{failures.join("\n")}"
    end
  end
end

Minitest.after_run { BriefingGenerationEval.report }
