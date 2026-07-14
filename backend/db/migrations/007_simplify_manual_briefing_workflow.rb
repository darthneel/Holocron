# frozen_string_literal: true

require "json"

Sequel.migration do
  up do
    briefing_statuses = %w[draft in_review approved changes_requested]

    create_table(:briefing_versions_v7) do
      String :id, primary_key: true
      foreign_key :briefing_id, :briefings, type: String, null: false, on_delete: :cascade
      foreign_key :created_by_workspace_member_id, :workspace_members, type: String, null: false, on_delete: :restrict
      Integer :version_number, null: false
      String :status, null: false, default: "draft"
      String :change_summary
      String :review_decision
      String :review_notes, text: true
      foreign_key :reviewed_by_workspace_member_id, :workspace_members, type: String, on_delete: :restrict
      DateTime :reviewed_at
      DateTime :created_at, null: false

      check(status: briefing_statuses)
      constraint(:valid_review_decision, "review_decision IS NULL OR review_decision IN ('approved', 'changes_requested')")
      constraint(
        :complete_review_metadata,
        "(review_decision IS NULL AND reviewed_by_workspace_member_id IS NULL AND reviewed_at IS NULL) OR " \
          "(review_decision IS NOT NULL AND reviewed_by_workspace_member_id IS NOT NULL AND reviewed_at IS NOT NULL)"
      )
      constraint(:positive_version_number) { version_number > 0 }
      index %i[briefing_id version_number], unique: true
      index %i[briefing_id created_at]
    end

    self[:briefing_versions].each do |version|
      review = self[:briefing_reviews].where(briefing_version_id: version[:id]).first
      self[:briefing_versions_v7].insert(
        id: version[:id],
        briefing_id: version[:briefing_id],
        created_by_workspace_member_id: version[:created_by_workspace_member_id],
        version_number: version[:version_number],
        status: version[:status],
        change_summary: version[:change_summary],
        review_decision: review && review[:decision],
        review_notes: review && review[:notes],
        reviewed_by_workspace_member_id: review && review[:reviewed_by_workspace_member_id],
        reviewed_at: review && review[:reviewed_at],
        created_at: version[:created_at]
      )
    end

    create_table(:briefing_sections_v7) do
      String :id, primary_key: true
      foreign_key :briefing_version_id, :briefing_versions_v7, type: String, null: false, on_delete: :cascade
      String :section_type, null: false
      String :title, null: false
      String :body, text: true, null: false, default: ""
      Integer :position, null: false
      String :sources_json, text: true, null: false, default: "[]"
      DateTime :created_at, null: false

      check(section_type: %w[overview attendees relationship_context prior_history objectives logistics notes])
      index %i[briefing_version_id position], unique: true
    end

    self[:briefing_sections].each do |section|
      sources = self[:briefing_sources]
        .where(briefing_section_id: section[:id])
        .order(:created_at, :id)
        .all
        .map do |source|
          {
            source_type: source[:source_type],
            source_id: source[:source_id],
            source_label: source[:source_label],
            source_excerpt: source[:source_excerpt]
          }
        end

      self[:briefing_sections_v7].insert(
        id: section[:id],
        briefing_version_id: section[:briefing_version_id],
        section_type: section[:section_type],
        title: section[:title],
        body: section[:body],
        position: section[:position],
        sources_json: JSON.generate(sources),
        created_at: section[:created_at]
      )
    end

    drop_table(:briefing_reviews)
    drop_table(:briefing_sources)
    drop_table(:briefing_sections)
    drop_table(:briefing_versions)
    rename_table(:briefing_versions_v7, :briefing_versions)
    rename_table(:briefing_sections_v7, :briefing_sections)
  end

  down do
    raise Sequel::Error, "Briefing workflow simplification is intentionally irreversible."
  end
end
