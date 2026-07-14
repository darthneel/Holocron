# frozen_string_literal: true

require "date"

Sequel.migration do
  up do
    alter_table(:people) do
      add_foreign_key :organization_id, :organizations, type: String, on_delete: :set_null
      add_column :job_title, String
      add_index :organization_id
    end

    today = Date.today
    self[:people].each do |person|
      affiliations = self[:affiliations].where(person_id: person[:id]).all
      selected = affiliations.min_by do |affiliation|
        active = (!affiliation[:starts_on] || affiliation[:starts_on] <= today) &&
          (!affiliation[:ends_on] || affiliation[:ends_on] >= today)
        start_rank = affiliation[:starts_on] ? -affiliation[:starts_on].jd : 0
        [active ? 0 : 1, affiliation[:is_primary] ? 0 : 1, start_rank, affiliation[:created_at]]
      end
      next unless selected

      self[:people].where(id: person[:id]).update(
        organization_id: selected[:organization_id],
        job_title: selected[:title]
      )
    end

    if self[:interactions].where(person_id: nil).any?
      raise Sequel::Error, "Cannot simplify organization-only interactions without selecting a person."
    end

    create_table(:interactions_v5) do
      String :id, primary_key: true
      foreign_key :workspace_id, :workspaces, type: String, null: false, on_delete: :restrict
      foreign_key :person_id, :people, type: String, null: false, on_delete: :cascade
      foreign_key :scheduling_request_id, :scheduling_requests, type: String, on_delete: :set_null
      foreign_key :authored_by_workspace_member_id, :workspace_members, type: String, null: false, on_delete: :restrict
      String :interaction_type, null: false
      String :summary, text: true, null: false
      String :source_type, null: false
      String :source_id
      DateTime :occurred_at, null: false
      DateTime :created_at, null: false
      DateTime :updated_at, null: false

      check(interaction_type: %w[call email meeting note event other])
      check(source_type: %w[manual scheduling_request import])
      index %i[workspace_id occurred_at]
      index %i[person_id occurred_at]
      index :scheduling_request_id
      index %i[source_type source_id]
    end

    self[:interactions].each do |interaction|
      self[:interactions_v5].insert(
        id: interaction[:id],
        workspace_id: interaction[:workspace_id],
        person_id: interaction[:person_id],
        scheduling_request_id: interaction[:scheduling_request_id],
        authored_by_workspace_member_id: interaction[:authored_by_workspace_member_id],
        interaction_type: interaction[:interaction_type],
        summary: interaction[:summary],
        source_type: interaction[:source_type],
        source_id: interaction[:source_id],
        occurred_at: interaction[:occurred_at],
        created_at: interaction[:created_at],
        updated_at: interaction[:updated_at]
      )
    end

    drop_table(:interactions)
    rename_table(:interactions_v5, :interactions)
    drop_table(:scheduling_request_organizations)
    drop_table(:affiliations)
  end

  down do
    raise Sequel::Error, "Relationship simplification is intentionally irreversible."
  end
end
