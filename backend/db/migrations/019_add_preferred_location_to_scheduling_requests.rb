# frozen_string_literal: true

Sequel.migration do
  up do
    alter_table(:scheduling_requests) do
      add_column :preferred_location, String, text: true
    end
  end

  down do
    alter_table(:scheduling_requests) do
      drop_column :preferred_location
    end
  end
end
