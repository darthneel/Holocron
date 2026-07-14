# frozen_string_literal: true

Sequel.migration do
  up do
    briefing_statuses = %w[draft in_review approved changes_requested]

    create_table(:meetings) do
      String :id, primary_key: true
      foreign_key :workspace_id, :workspaces, type: String, null: false, on_delete: :restrict
      foreign_key :scheduling_request_id, :scheduling_requests, type: String, null: false, unique: true, on_delete: :restrict
      foreign_key :created_by_workspace_member_id, :workspace_members, type: String, null: false, on_delete: :restrict
      String :title, null: false
      DateTime :starts_at, null: false
      DateTime :ends_at, null: false
      String :location
      DateTime :created_at, null: false
      DateTime :updated_at, null: false

      constraint(:meeting_ends_after_start, "ends_at > starts_at")
      index %i[workspace_id starts_at]
    end

    create_table(:briefings) do
      String :id, primary_key: true
      foreign_key :workspace_id, :workspaces, type: String, null: false, on_delete: :restrict
      foreign_key :meeting_id, :meetings, type: String, null: false, unique: true, on_delete: :cascade
      foreign_key :created_by_workspace_member_id, :workspace_members, type: String, null: false, on_delete: :restrict
      String :status, null: false, default: "draft"
      Integer :current_version_number, null: false, default: 1
      Integer :lock_version, null: false, default: 1
      DateTime :created_at, null: false
      DateTime :updated_at, null: false

      check(status: briefing_statuses)
      constraint(:positive_briefing_version_number) { current_version_number > 0 }
      constraint(:positive_briefing_lock_version) { lock_version > 0 }
      index %i[workspace_id status updated_at]
    end

    create_table(:briefing_versions) do
      String :id, primary_key: true
      foreign_key :briefing_id, :briefings, type: String, null: false, on_delete: :cascade
      foreign_key :created_by_workspace_member_id, :workspace_members, type: String, null: false, on_delete: :restrict
      Integer :version_number, null: false
      String :status, null: false, default: "draft"
      String :change_summary
      DateTime :created_at, null: false

      check(status: briefing_statuses)
      constraint(:positive_version_number) { version_number > 0 }
      index %i[briefing_id version_number], unique: true
      index %i[briefing_id created_at]
    end

    create_table(:briefing_sections) do
      String :id, primary_key: true
      foreign_key :briefing_version_id, :briefing_versions, type: String, null: false, on_delete: :cascade
      String :section_type, null: false
      String :title, null: false
      String :body, text: true, null: false, default: ""
      Integer :position, null: false
      DateTime :created_at, null: false

      check(section_type: %w[overview attendees relationship_context prior_history objectives logistics notes])
      index %i[briefing_version_id position], unique: true
    end

    create_table(:briefing_sources) do
      String :id, primary_key: true
      foreign_key :briefing_section_id, :briefing_sections, type: String, null: false, on_delete: :cascade
      foreign_key :added_by_workspace_member_id, :workspace_members, type: String, null: false, on_delete: :restrict
      String :source_type, null: false
      String :source_id, null: false
      String :source_label, null: false
      String :source_excerpt, text: true
      DateTime :created_at, null: false

      check(source_type: %w[scheduling_request person organization interaction])
      index %i[briefing_section_id source_type source_id], unique: true
      index %i[source_type source_id]
    end

    create_table(:briefing_reviews) do
      String :id, primary_key: true
      foreign_key :briefing_id, :briefings, type: String, null: false, on_delete: :cascade
      foreign_key :briefing_version_id, :briefing_versions, type: String, null: false, unique: true, on_delete: :cascade
      foreign_key :reviewed_by_workspace_member_id, :workspace_members, type: String, null: false, on_delete: :restrict
      String :decision, null: false
      String :notes, text: true
      DateTime :reviewed_at, null: false

      check(decision: %w[approved changes_requested])
      index %i[briefing_id reviewed_at]
    end
  end

  down do
    drop_table(:briefing_reviews)
    drop_table(:briefing_sources)
    drop_table(:briefing_sections)
    drop_table(:briefing_versions)
    drop_table(:briefings)
    drop_table(:meetings)
  end
end
