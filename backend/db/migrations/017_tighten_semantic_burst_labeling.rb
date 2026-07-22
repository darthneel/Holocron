# frozen_string_literal: true

Sequel.migration do
  up do
    alter_table(:semantic_labeling_candidates) do
      add_column :assertion_status, String
      add_column :materially_distinct, TrueClass
      add_constraint(
        :valid_semantic_labeling_candidate_assertion_status,
        "assertion_status IS NULL OR assertion_status IN ('settled', 'proposed', 'conditional', 'none')"
      )
    end

    alter_table(:semantic_labeling_burst_proposals) do
      add_column :assertion_status, String
      add_constraint(
        :valid_semantic_labeling_proposal_assertion_status,
        "assertion_status IS NULL OR assertion_status IN ('settled', 'proposed', 'conditional', 'none')"
      )
    end
  end

  down do
    alter_table(:semantic_labeling_burst_proposals) do
      drop_constraint :valid_semantic_labeling_proposal_assertion_status
      drop_column :assertion_status
    end
    alter_table(:semantic_labeling_candidates) do
      drop_constraint :valid_semantic_labeling_candidate_assertion_status
      drop_column :materially_distinct
      drop_column :assertion_status
    end
  end
end
