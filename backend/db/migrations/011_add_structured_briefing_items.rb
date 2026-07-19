# frozen_string_literal: true

Sequel.migration do
  up do
    run "ALTER TABLE briefing_sections DROP CONSTRAINT IF EXISTS briefing_sections_section_type_check"
    run "ALTER TABLE briefing_sections DROP CONSTRAINT IF EXISTS briefing_sections_v7_section_type_check"
    alter_table(:briefing_sections) do
      add_column :items_json, String, text: true, null: false, default: "[]"
      add_constraint(
        :valid_briefing_section_type,
        "section_type IN (" \
          "'overview', 'attendees', 'relationship_context', 'prior_history', 'objectives', 'logistics', 'notes', " \
          "'meeting_snapshot', 'meeting_ask', 'desired_outcomes', 'decision_context', 'talking_points', 'risks', 'open_questions')"
      )
    end
  end

  down do
    unsupported = self[:briefing_sections]
      .exclude(section_type: %w[overview attendees relationship_context prior_history objectives logistics notes])
      .count
    raise Sequel::Error, "Cannot roll back while action-oriented briefing sections exist." if unsupported.positive?

    alter_table(:briefing_sections) do
      drop_constraint :valid_briefing_section_type
      drop_column :items_json
      add_constraint(
        :briefing_sections_section_type_check,
        "section_type IN ('overview', 'attendees', 'relationship_context', 'prior_history', 'objectives', 'logistics', 'notes')"
      )
    end
  end
end
