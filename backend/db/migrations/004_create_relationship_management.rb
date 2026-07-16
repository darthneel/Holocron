# frozen_string_literal: true

require "securerandom"

Sequel.migration do
  up do
    create_table(:people) do
      String :id, primary_key: true
      foreign_key :workspace_id, :workspaces, type: String, null: false, on_delete: :restrict
      foreign_key :created_by_workspace_member_id, :workspace_members, type: String, null: false, on_delete: :restrict
      String :display_name, null: false
      column :primary_email, "citext"
      String :primary_phone
      String :notes, text: true
      DateTime :created_at, null: false
      DateTime :updated_at, null: false

      index %i[workspace_id primary_email], unique: true, where: Sequel.~(primary_email: nil)
      index %i[workspace_id display_name]
    end

    create_table(:organizations) do
      String :id, primary_key: true
      foreign_key :workspace_id, :workspaces, type: String, null: false, on_delete: :restrict
      foreign_key :created_by_workspace_member_id, :workspace_members, type: String, null: false, on_delete: :restrict
      String :name, null: false
      String :normalized_name, null: false
      String :website_url
      String :notes, text: true
      DateTime :created_at, null: false
      DateTime :updated_at, null: false

      index %i[workspace_id normalized_name], unique: true
      index %i[workspace_id name]
    end

    create_table(:affiliations) do
      String :id, primary_key: true
      foreign_key :workspace_id, :workspaces, type: String, null: false, on_delete: :restrict
      foreign_key :person_id, :people, type: String, null: false, on_delete: :cascade
      foreign_key :organization_id, :organizations, type: String, null: false, on_delete: :cascade
      foreign_key :created_by_workspace_member_id, :workspace_members, type: String, null: false, on_delete: :restrict
      String :title
      String :relationship_type, null: false
      Date :starts_on
      Date :ends_on
      TrueClass :is_primary, null: false, default: false
      String :source_type, null: false
      String :source_id
      DateTime :created_at, null: false
      DateTime :updated_at, null: false

      check(relationship_type: %w[employee member board_member elected_official volunteer other])
      check(source_type: %w[manual scheduling_request migration])
      constraint(:valid_affiliation_dates, "ends_on IS NULL OR starts_on IS NULL OR ends_on >= starts_on")
      index %i[person_id starts_on ends_on]
      index %i[organization_id starts_on ends_on]
      index %i[source_type source_id]
    end

    create_table(:interactions) do
      String :id, primary_key: true
      foreign_key :workspace_id, :workspaces, type: String, null: false, on_delete: :restrict
      foreign_key :person_id, :people, type: String, on_delete: :set_null
      foreign_key :organization_id, :organizations, type: String, on_delete: :set_null
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
      constraint(:interaction_has_subject, "person_id IS NOT NULL OR organization_id IS NOT NULL")
      index %i[workspace_id occurred_at]
      index %i[person_id occurred_at]
      index %i[organization_id occurred_at]
      index :scheduling_request_id
      index %i[source_type source_id]
    end

    create_table(:scheduling_request_people) do
      foreign_key :scheduling_request_id, :scheduling_requests, type: String, null: false, on_delete: :cascade
      foreign_key :person_id, :people, type: String, null: false, on_delete: :cascade
      String :role, null: false
      String :source_type, null: false
      DateTime :linked_at, null: false

      check(role: %w[requester required optional staff])
      check(source_type: %w[manual scheduling_request migration])
      primary_key %i[scheduling_request_id person_id role]
      index :person_id
    end

    create_table(:scheduling_request_organizations) do
      foreign_key :scheduling_request_id, :scheduling_requests, type: String, null: false, on_delete: :cascade
      foreign_key :organization_id, :organizations, type: String, null: false, on_delete: :cascade
      String :role, null: false
      String :source_type, null: false
      DateTime :linked_at, null: false

      check(role: %w[requester participant host related])
      check(source_type: %w[manual scheduling_request migration])
      primary_key %i[scheduling_request_id organization_id role]
      index :organization_id
    end

    normalize_organization = lambda do |name|
      name.to_s.downcase.gsub(/[^a-z0-9]+/, " ").strip
    end

    find_or_create_person = lambda do |workspace_id, name, email, created_by, occurred_at|
      normalized_email = email.to_s.strip.downcase
      person = if normalized_email.empty?
        nil
      else
        self[:people].where(workspace_id: workspace_id, primary_email: normalized_email).first
      end
      next person[:id] if person

      id = SecureRandom.uuid
      self[:people].insert(
        id: id,
        workspace_id: workspace_id,
        created_by_workspace_member_id: created_by,
        display_name: name,
        primary_email: normalized_email.empty? ? nil : normalized_email,
        primary_phone: nil,
        notes: nil,
        created_at: occurred_at,
        updated_at: occurred_at
      )
      id
    end

    find_or_create_organization = lambda do |workspace_id, name, created_by, occurred_at|
      normalized_name = normalize_organization.call(name)
      next nil if normalized_name.empty?

      organization = self[:organizations].where(workspace_id: workspace_id, normalized_name: normalized_name).first
      next organization[:id] if organization

      id = SecureRandom.uuid
      self[:organizations].insert(
        id: id,
        workspace_id: workspace_id,
        created_by_workspace_member_id: created_by,
        name: name.to_s.strip,
        normalized_name: normalized_name,
        website_url: nil,
        notes: nil,
        created_at: occurred_at,
        updated_at: occurred_at
      )
      id
    end

    link_affiliation = lambda do |request, person_id, organization_id|
      next unless person_id && organization_id

      existing = self[:affiliations].where(person_id: person_id, organization_id: organization_id, ends_on: nil).first
      next if existing

      self[:affiliations].insert(
        id: SecureRandom.uuid,
        workspace_id: request[:workspace_id],
        person_id: person_id,
        organization_id: organization_id,
        created_by_workspace_member_id: request[:created_by_workspace_member_id],
        title: nil,
        relationship_type: "member",
        starts_on: nil,
        ends_on: nil,
        is_primary: false,
        source_type: "migration",
        source_id: request[:id],
        created_at: request[:created_at],
        updated_at: request[:created_at]
      )
    end

    self[:scheduling_requests].all.each do |request|
      requester_person_id = find_or_create_person.call(
        request[:workspace_id], request[:requester_name], request[:requester_email],
        request[:created_by_workspace_member_id], request[:created_at]
      )
      requester_organization_id = find_or_create_organization.call(
        request[:workspace_id], request[:requester_organization],
        request[:created_by_workspace_member_id], request[:created_at]
      )

      self[:scheduling_request_people].insert(
        scheduling_request_id: request[:id], person_id: requester_person_id,
        role: "requester", source_type: "migration", linked_at: request[:created_at]
      )
      if requester_organization_id
        self[:scheduling_request_organizations].insert(
          scheduling_request_id: request[:id], organization_id: requester_organization_id,
          role: "requester", source_type: "migration", linked_at: request[:created_at]
        )
      end
      link_affiliation.call(request, requester_person_id, requester_organization_id)

      self[:request_participants].where(scheduling_request_id: request[:id]).each do |participant|
        person_id = find_or_create_person.call(
          request[:workspace_id], participant[:name], participant[:email],
          request[:created_by_workspace_member_id], participant[:created_at]
        )
        organization_id = find_or_create_organization.call(
          request[:workspace_id], participant[:organization],
          request[:created_by_workspace_member_id], participant[:created_at]
        )
        self[:scheduling_request_people].insert_conflict.insert(
          scheduling_request_id: request[:id], person_id: person_id,
          role: participant[:role], source_type: "migration", linked_at: participant[:created_at]
        )
        if organization_id
          self[:scheduling_request_organizations].insert_conflict.insert(
            scheduling_request_id: request[:id], organization_id: organization_id,
            role: "participant", source_type: "migration", linked_at: participant[:created_at]
          )
        end
        link_affiliation.call(request, person_id, organization_id)
      end

      self[:interactions].insert(
        id: SecureRandom.uuid,
        workspace_id: request[:workspace_id],
        person_id: requester_person_id,
        organization_id: requester_organization_id,
        scheduling_request_id: request[:id],
        authored_by_workspace_member_id: request[:created_by_workspace_member_id],
        interaction_type: %w[phone email].include?(request[:source_channel]) ? request[:source_channel].sub("phone", "call") : "other",
        summary: request[:purpose],
        source_type: "scheduling_request",
        source_id: request[:id],
        occurred_at: request[:created_at],
        created_at: request[:created_at],
        updated_at: request[:updated_at]
      )
    end
  end

  down do
    drop_table(:scheduling_request_organizations)
    drop_table(:scheduling_request_people)
    drop_table(:interactions)
    drop_table(:affiliations)
    drop_table(:organizations)
    drop_table(:people)
  end
end
