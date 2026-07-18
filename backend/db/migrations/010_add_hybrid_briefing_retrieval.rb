# frozen_string_literal: true

Sequel.migration do
  up do
    alter_table(:briefing_versions) do
      drop_constraint :valid_retrieval_strategy
      add_constraint(
        :valid_retrieval_strategy,
        "retrieval_strategy IS NULL OR retrieval_strategy IN ('linked_recency', 'semantic', 'hybrid')"
      )
    end
  end

  down do
    alter_table(:briefing_versions) do
      drop_constraint :valid_retrieval_strategy
      add_constraint(
        :valid_retrieval_strategy,
        "retrieval_strategy IS NULL OR retrieval_strategy IN ('linked_recency', 'semantic')"
      )
    end
  end
end
