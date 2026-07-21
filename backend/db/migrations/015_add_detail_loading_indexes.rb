# frozen_string_literal: true

Sequel.migration do
  up do
    alter_table(:scheduling_requests) do
      add_index %i[workspace_id updated_at], name: :scheduling_requests_workspace_updated_at
    end
    alter_table(:briefings) do
      add_index %i[workspace_id updated_at], name: :briefings_workspace_updated_at
    end
    alter_table(:audit_events) do
      add_index %i[subject_type subject_id occurred_at], name: :audit_events_subject_occurred_at
    end
    alter_table(:interactions) do
      add_index %i[workspace_id person_id occurred_at], name: :interactions_workspace_person_occurred_at
    end
  end

  down do
    alter_table(:interactions) do
      drop_index %i[workspace_id person_id occurred_at], name: :interactions_workspace_person_occurred_at
    end
    alter_table(:audit_events) do
      drop_index %i[subject_type subject_id occurred_at], name: :audit_events_subject_occurred_at
    end
    alter_table(:briefings) do
      drop_index %i[workspace_id updated_at], name: :briefings_workspace_updated_at
    end
    alter_table(:scheduling_requests) do
      drop_index %i[workspace_id updated_at], name: :scheduling_requests_workspace_updated_at
    end
  end
end
