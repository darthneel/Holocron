# frozen_string_literal: true

require "date"
require "fileutils"
require "json"
require "minitest/autorun"
require_relative "../lib/holocron/request_extractions"

unless ENV["RUN_LIVE_EVALS"] == "1"
  abort "Set RUN_LIVE_EVALS=1 to confirm that this suite may make billed model requests."
end

module RequestExtractionEval
  FIXTURE_PATH = File.expand_path("fixtures/request_extractions.json", __dir__)
  CASES = JSON.parse(File.read(FIXTURE_PATH))
  MATCHERS = %w[equals includes is_null length contains_object].freeze
  MISSING = Object.new.freeze
  DEFAULT_PRICING = {
    "openai/gpt-5.6-luna" => {input: 1.0, output: 6.0}
  }.freeze

  @records = []
  @started_at = Time.now.utc

  module_function

  def input_for(fixture)
    input = fixture.fetch("input")
    input.is_a?(Array) ? input.join("\n") : input.to_s
  end

  def evaluate(output, assertion)
    path = assertion.fetch("path")
    matcher = assertion.keys & MATCHERS
    raise ArgumentError, "#{path} must define exactly one matcher" unless matcher.length == 1

    actual = value_at(output, path)
    return "#{path} is missing" if actual.equal?(MISSING)

    key = matcher.first
    expected = assertion[key]
    passed = case key
    when "equals"
      actual == expected
    when "includes"
      includes?(actual, expected)
    when "is_null"
      expected == true && actual.nil?
    when "length"
      actual.respond_to?(:length) && actual.length == expected
    when "contains_object"
      contains_object?(actual, expected)
    end
    return if passed

    "#{path} expected #{key}=#{expected.inspect}, got #{actual.inspect}"
  end

  def value_at(output, path)
    path.split(".").reduce(output) do |value, key|
      return MISSING unless value.is_a?(Hash) && value.key?(key)
      value[key]
    end
  end

  def includes?(actual, expected)
    case actual
    when String
      actual.downcase.include?(expected.to_s.downcase)
    when Array
      actual.include?(expected)
    else
      false
    end
  end

  def contains_object?(actual, expected)
    actual.is_a?(Array) && expected.is_a?(Hash) && actual.any? do |entry|
      entry.is_a?(Hash) && expected.all? { |key, value| entry[key] == value }
    end
  end

  def estimated_cost(model, input_tokens, output_tokens)
    pricing = configured_pricing || DEFAULT_PRICING[model]
    return unless pricing && input_tokens && output_tokens

    ((input_tokens * pricing.fetch(:input)) + (output_tokens * pricing.fetch(:output))) / 1_000_000.0
  end

  def configured_pricing
    input = Float(ENV["EVAL_INPUT_USD_PER_MILLION"], exception: false)
    output = Float(ENV["EVAL_OUTPUT_USD_PER_MILLION"], exception: false)
    input && output && {input: input, output: output}
  end

  def record(entry)
    @records << entry
  end

  def report
    completed_at = Time.now.utc
    passed = @records.count { |record| record.fetch(:failures).empty? }
    assertions = @records.sum { |record| record.fetch(:assertion_count) }
    assertion_failures = @records.sum { |record| record.fetch(:assertion_failures) }
    input_tokens = @records.sum { |record| record[:input_tokens].to_i }
    output_tokens = @records.sum { |record| record[:output_tokens].to_i }
    total_cost = @records.filter_map { |record| record[:estimated_cost_usd] }.sum

    puts "\nRequest extraction eval report"
    @records.sort_by { |record| record.fetch(:id) }.each do |record|
      status = record.fetch(:failures).empty? ? "PASS" : "FAIL"
      tokens = "#{record[:input_tokens] || "?"}+#{record[:output_tokens] || "?"} tokens"
      cost = record[:estimated_cost_usd] ? format("$%.6f", record[:estimated_cost_usd]) : "cost n/a"
      puts format("%-4s %-31s %s, %dms, %s", status, record.fetch(:id), tokens, record[:duration_ms].to_i, cost)
    end
    puts "#{passed}/#{@records.length} cases passed; #{assertions - assertion_failures}/#{assertions} fixture assertions passed"
    puts "Total usage: #{input_tokens} input + #{output_tokens} output tokens; estimated cost #{format("$%.6f", total_cost)}" if total_cost.positive?

    output_path = write_results(
      started_at: @started_at,
      completed_at: completed_at,
      passed_cases: passed,
      assertion_count: assertions,
      assertion_failures: assertion_failures,
      input_tokens: input_tokens,
      output_tokens: output_tokens,
      estimated_cost_usd: total_cost,
      records: @records
    )
    puts "Detailed results: #{output_path}"
  end

  def write_results(summary)
    directory = File.expand_path("../tmp/eval-results", __dir__)
    FileUtils.mkdir_p(directory)
    path = File.join(directory, "request-extraction-#{Time.now.utc.strftime("%Y%m%dT%H%M%SZ")}.json")
    payload = {
      suite: "request-extraction-v2",
      prompt_version: Holocron::RequestExtractions::PROMPT_VERSION,
      provider: ENV["AI_REQUEST_EXTRACTION_PROVIDER"],
      configured_model: ENV["AI_REQUEST_EXTRACTION_MODEL"],
      workspace_timezone: ENV.fetch("EVAL_WORKSPACE_TIMEZONE", "America/Los_Angeles"),
      evaluation_date: Date.today.iso8601
    }.merge(summary)
    File.write(path, JSON.pretty_generate(payload))
    path
  end
end

class RequestExtractionEvalTest < Minitest::Test
  RequestExtractionEval::CASES.each do |fixture|
    define_method("test_#{fixture.fetch("id")}") do
      run_fixture(fixture)
    end
  end

  private

  def run_fixture(fixture)
    input = RequestExtractionEval.input_for(fixture)
    workspace = {timezone: ENV.fetch("EVAL_WORKSPACE_TIMEZONE", "America/Los_Angeles")}
    result = Holocron::AI::ModelRouter.new.request_extraction(
      prompt: Holocron::RequestExtractions.prompt(input, workspace),
      schema: Holocron::RequestExtractions::OUTPUT_SCHEMA
    )

    failures = []
    normalized = nil
    validation_errors = {}
    warnings = []
    assertion_failures = []

    if result.status != "succeeded"
      failures << "provider returned #{result.status}: #{result.failure_reason}"
      assertion_failures = Array.new(fixture.fetch("assertions").length, "not evaluated")
    else
      normalized, validation_errors, warnings = Holocron::RequestExtractions.normalize_output(result.output)
      failures << "deterministic validation failed: #{validation_errors.inspect}" unless validation_errors.empty?
      assertion_failures = fixture.fetch("assertions").filter_map do |assertion|
        RequestExtractionEval.evaluate(normalized, assertion)
      end
      failures.concat(assertion_failures)
    end

    cost = RequestExtractionEval.estimated_cost(result.model, result.input_tokens, result.output_tokens)
    RequestExtractionEval.record(
      id: fixture.fetch("id"),
      description: fixture.fetch("description"),
      input: input,
      assertions: fixture.fetch("assertions"),
      assertion_count: fixture.fetch("assertions").length,
      assertion_failures: assertion_failures.length,
      failures: failures,
      status: result.status,
      failure_reason: result.failure_reason,
      provider: result.provider,
      model: result.model,
      provider_request_id: result.provider_request_id,
      attempt_count: result.attempt_count,
      input_tokens: result.input_tokens,
      output_tokens: result.output_tokens,
      duration_ms: result.duration_ms,
      estimated_cost_usd: cost,
      raw_output: result.output,
      normalized_output: normalized,
      validation_errors: validation_errors,
      warnings: warnings
    )

    assert failures.empty?, "#{fixture.fetch("description")}\n#{failures.join("\n")}"
  end
end

Minitest.after_run { RequestExtractionEval.report }
