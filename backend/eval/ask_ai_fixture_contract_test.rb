# frozen_string_literal: true

require "json"
require "minitest/autorun"
require "time"

class AskAIFixtureContractTest < Minitest::Test
  FIXTURE_PATH = File.expand_path("fixtures/ask_ai_queries.json", __dir__)
  FIXTURE = JSON.parse(File.read(FIXTURE_PATH))
  REQUIRED_CATEGORIES = %w[
    named_person
    named_organization
    topic_without_entity
    unknown_subject
    ambiguous_name
    prompt_injection
    cross_workspace
  ].freeze
  ALLOWED_BEHAVIORS = %w[answer insufficient_evidence disambiguation].freeze
  REQUIRED_SCOPE = {
    "source_types" => ["interaction"],
    "single_turn" => true,
    "read_only" => true,
    "external_sources" => false,
    "conversation_history" => false,
    "analytics" => false
  }.freeze

  def test_fixture_declares_the_strict_mvp_scope
    assert_equal "ask-holocron-mvp-v1", FIXTURE.fetch("version")
    assert_equal REQUIRED_SCOPE, FIXTURE.fetch("scope")
  end

  def test_source_corpus_contains_only_well_formed_unique_interactions
    sources = FIXTURE.fetch("sources")
    refs = sources.map { |source| source.fetch("source_ref") }

    refute_empty sources
    assert_equal refs.uniq, refs
    sources.each do |source|
      assert_equal "interaction", source.fetch("source_type")
      assert_equal "interaction:#{source.fetch('source_id')}", source.fetch("source_ref")
      refute_empty source.fetch("workspace_slug")
      refute_empty source.fetch("person_name")
      refute_empty source.fetch("organization_name")
      refute_empty source.fetch("interaction_type")
      refute_empty source.fetch("summary")
      Time.iso8601(source.fetch("occurred_at"))
    end
  end

  def test_required_case_categories_exist_exactly_once
    categories = FIXTURE.fetch("cases").map { |fixture| fixture.fetch("category") }

    assert_equal REQUIRED_CATEGORIES.sort, categories.sort
    assert_equal categories.uniq.sort, categories.sort
  end

  def test_case_ids_are_unique_and_questions_fit_the_api_contract
    cases = FIXTURE.fetch("cases")
    ids = cases.map { |fixture| fixture.fetch("id") }

    assert_equal ids.uniq, ids
    cases.each do |fixture|
      question = fixture.fetch("question")
      assert_operator question.length, :>=, 3
      assert_operator question.length, :<=, 1_000
      refute_empty fixture.fetch("description")
    end
  end

  def test_every_expected_source_reference_resolves_to_the_corpus
    known_refs = FIXTURE.fetch("sources").map { |source| source.fetch("source_ref") }

    FIXTURE.fetch("cases").each do |fixture|
      expected = fixture.fetch("expected")
      referenced = %w[allowed_source_refs required_source_refs forbidden_source_refs]
        .flat_map { |key| expected.fetch(key) }

      assert_empty referenced.uniq - known_refs, fixture.fetch("id")
      assert_empty expected.fetch("required_source_refs") - expected.fetch("allowed_source_refs"), fixture.fetch("id")
    end
  end

  def test_answer_sources_are_interactions_from_the_current_workspace
    source_by_ref = FIXTURE.fetch("sources").to_h { |source| [source.fetch("source_ref"), source] }
    workspace_slug = FIXTURE.fetch("workspace_slug")

    FIXTURE.fetch("cases").each do |fixture|
      fixture.dig("expected", "allowed_source_refs").each do |source_ref|
        source = source_by_ref.fetch(source_ref)
        assert_equal workspace_slug, source.fetch("workspace_slug"), fixture.fetch("id")
        assert_equal "interaction", source.fetch("source_type"), fixture.fetch("id")
      end
    end
  end

  def test_required_facts_are_grounded_in_allowed_source_text
    source_by_ref = FIXTURE.fetch("sources").to_h { |source| [source.fetch("source_ref"), source] }

    FIXTURE.fetch("cases").each do |fixture|
      expected = fixture.fetch("expected")
      evidence = expected.fetch("allowed_source_refs")
        .map { |source_ref| source_by_ref.fetch(source_ref).fetch("summary") }
        .join("\n")
        .downcase

      expected.fetch("required_facts").each do |fact|
        assert_includes evidence, fact.downcase, "#{fixture.fetch('id')}: #{fact}"
      end
    end
  end

  def test_every_case_forbids_all_foreign_workspace_sources
    workspace_slug = FIXTURE.fetch("workspace_slug")
    foreign_refs = FIXTURE.fetch("sources").filter_map do |source|
      source.fetch("source_ref") unless source.fetch("workspace_slug") == workspace_slug
    end

    refute_empty foreign_refs
    FIXTURE.fetch("cases").each do |fixture|
      forbidden = fixture.dig("expected", "forbidden_source_refs")
      assert_empty foreign_refs - forbidden, fixture.fetch("id")
    end
  end

  def test_behavior_specific_expectations_are_complete
    FIXTURE.fetch("cases").each do |fixture|
      expected = fixture.fetch("expected")
      behavior = expected.fetch("behavior")

      assert_includes ALLOWED_BEHAVIORS, behavior
      assert expected.key?("required_facts")
      assert expected.key?("forbidden_terms")

      case behavior
      when "answer"
        refute_empty expected.fetch("allowed_source_refs"), fixture.fetch("id")
        refute_empty expected.fetch("required_source_refs"), fixture.fetch("id")
        refute_empty expected.fetch("required_facts"), fixture.fetch("id")
      when "insufficient_evidence"
        assert_empty expected.fetch("allowed_source_refs"), fixture.fetch("id")
        assert_empty expected.fetch("required_source_refs"), fixture.fetch("id")
        refute_empty expected.fetch("required_limitations"), fixture.fetch("id")
      when "disambiguation"
        assert_empty expected.fetch("allowed_source_refs"), fixture.fetch("id")
        assert_empty expected.fetch("required_source_refs"), fixture.fetch("id")
        assert_operator expected.fetch("expected_entities").length, :>=, 2, fixture.fetch("id")
        refute_empty expected.fetch("required_limitations"), fixture.fetch("id")
      end
    end
  end
end
