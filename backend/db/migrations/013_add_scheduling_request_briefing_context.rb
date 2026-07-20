# frozen_string_literal: true

Sequel.migration do
  up do
    alter_table(:scheduling_requests) do
      add_column :briefing_context_json, String, text: true, null: false, default: "{}"
    end
  end

  down do
    alter_table(:scheduling_requests) do
      drop_column :briefing_context_json
    end
  end
end
