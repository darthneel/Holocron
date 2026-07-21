# frozen_string_literal: true

require "json"
require "securerandom"
require "time"
require "uri"
require_relative "database"

module Holocron
  module Relationships
    INTERACTION_TYPES = %w[call email meeting note event other].freeze
    EMAIL_PATTERN = URI::MailTo::EMAIL_REGEXP

    class ValidationError < StandardError
      attr_reader :fields

      def initialize(fields)
        super("Validation failed.")
        @fields = fields
      end
    end

    module_function

    def overview(workspace:)
      db = Database.db
      people_rows = db[:people]
        .where(workspace_id: workspace[:id])
        .order(Sequel.function(:lower, :display_name))
        .all
      organization_rows = db[:organizations]
        .where(workspace_id: workspace[:id])
        .order(Sequel.function(:lower, :name))
        .all
      people_by_id = people_rows.to_h { |person| [person[:id], person] }
      organizations_by_id = organization_rows.to_h { |organization| [organization[:id], organization] }
      person_ids = people_by_id.keys
      organization_ids = organizations_by_id.keys

      request_counts_by_person = grouped_count(
        db[:scheduling_request_people].where(person_id: person_ids),
        :person_id,
        distinct: :scheduling_request_id
      )
      interaction_counts_by_person = grouped_count(
        db[:interactions].where(workspace_id: workspace[:id], person_id: person_ids),
        :person_id
      )
      people_counts_by_organization = grouped_count(
        db[:people].where(workspace_id: workspace[:id], organization_id: organization_ids),
        :organization_id
      )
      request_counts_by_organization = grouped_count(
        db[:scheduling_request_people]
          .join(:people, id: :person_id)
          .where(Sequel[:people][:workspace_id] => workspace[:id], Sequel[:people][:organization_id] => organization_ids),
        Sequel[:people][:organization_id],
        result_key: :organization_id,
        distinct: Sequel[:scheduling_request_people][:scheduling_request_id]
      )
      interaction_counts_by_organization = grouped_count(
        db[:interactions]
          .join(:people, id: :person_id)
          .where(Sequel[:people][:workspace_id] => workspace[:id], Sequel[:people][:organization_id] => organization_ids),
        Sequel[:people][:organization_id],
        result_key: :organization_id
      )

      people = people_rows.map do |person|
        organization = person[:organization_id] && organizations_by_id[person[:organization_id]]
        serialize_person_overview(
          person,
          organization: organization,
          request_count: request_counts_by_person.fetch(person[:id], 0),
          interaction_count: interaction_counts_by_person.fetch(person[:id], 0)
        )
      end
      organizations = organization_rows.map do |organization|
        serialize_organization_overview(
          organization,
          people_count: people_counts_by_organization.fetch(organization[:id], 0),
          request_count: request_counts_by_organization.fetch(organization[:id], 0),
          interaction_count: interaction_counts_by_organization.fetch(organization[:id], 0)
        )
      end
      interactions = db[:interactions]
        .left_join(:people, id: Sequel[:interactions][:person_id])
        .left_join(:workspace_members, id: Sequel[:interactions][:authored_by_workspace_member_id])
        .where(Sequel[:interactions][:workspace_id] => workspace[:id])
        .select_all(:interactions)
        .select_append(
          Sequel[:people][:display_name].as(:person_name),
          Sequel[:workspace_members][:display_name].as(:author_name)
        )
        .reverse_order(Sequel[:interactions][:occurred_at])
        .limit(50)
        .all
        .map { |interaction| serialize_interaction_overview(interaction) }

      {
        people: people,
        organizations: organizations,
        interactions: interactions,
        counts: {
          people: people.length,
          organizations: organizations.length,
          linked_people: people.count { |person| person[:organization] },
          interactions: interaction_counts_by_person.values.sum
        }
      }
    end

    def create_person(attributes:, workspace:, actor:)
      errors = {}
      display_name = required_text(attributes, "display_name", "Name", errors, limit: 160)
      primary_email = optional_email(attributes, "primary_email", errors)
      primary_phone = optional_text(attributes, "primary_phone", limit: 80)
      organization = optional_workspace_record(:organizations, attributes["organization_id"], workspace, "organization_id", errors)
      job_title = optional_text(attributes, "job_title", limit: 160)
      notes = optional_text(attributes, "notes", limit: 4_000)

      if primary_email && Database.db[:people].where(workspace_id: workspace[:id], primary_email: primary_email).any?
        errors["primary_email"] = "A person with this email already exists."
      end
      raise ValidationError, errors unless errors.empty?

      now = Time.now.utc
      id = SecureRandom.uuid
      correlation_id = SecureRandom.uuid
      Database.db.transaction do
        Database.db[:people].insert(
          id: id,
          workspace_id: workspace[:id],
          organization_id: organization&.fetch(:id),
          created_by_workspace_member_id: actor[:id],
          display_name: display_name,
          primary_email: primary_email,
          primary_phone: primary_phone,
          job_title: job_title,
          notes: notes,
          created_at: now,
          updated_at: now
        )
        write_audit_event(
          workspace: workspace,
          actor: actor,
          event_type: "person.created",
          subject_type: "person",
          subject_id: id,
          payload: {
            display_name: display_name,
            primary_email: primary_email,
            organization_id: organization&.fetch(:id),
            source_type: "manual"
          },
          correlation_id: correlation_id,
          occurred_at: now
        )
      end
      serialize_person(Database.db[:people].where(id: id).first)
    end

    def update_person(id:, attributes:, workspace:, actor:)
      person = Database.db[:people].where(id: id, workspace_id: workspace[:id]).first
      return nil unless person

      errors = {}
      organization = optional_workspace_record(:organizations, attributes["organization_id"], workspace, "organization_id", errors)
      job_title = optional_text(attributes, "job_title", limit: 160)
      raise ValidationError, errors unless errors.empty?

      now = Time.now.utc
      correlation_id = SecureRandom.uuid
      Database.db.transaction do
        Database.db[:people].where(id: id).update(
          organization_id: organization&.fetch(:id),
          job_title: job_title,
          updated_at: now
        )
        write_audit_event(
          workspace: workspace,
          actor: actor,
          event_type: "person.updated",
          subject_type: "person",
          subject_id: id,
          payload: {organization_id: organization&.fetch(:id), job_title: job_title},
          correlation_id: correlation_id,
          occurred_at: now
        )
      end
      serialize_person(Database.db[:people].where(id: id).first)
    end

    def create_organization(attributes:, workspace:, actor:)
      errors = {}
      name = required_text(attributes, "name", "Organization name", errors, limit: 250)
      normalized_name = normalize_organization_name(name)
      website_url = optional_url(attributes, "website_url", errors)
      notes = optional_text(attributes, "notes", limit: 4_000)

      if !normalized_name.empty? && Database.db[:organizations].where(workspace_id: workspace[:id], normalized_name: normalized_name).any?
        errors["name"] = "An organization with this name already exists."
      end
      raise ValidationError, errors unless errors.empty?

      now = Time.now.utc
      id = SecureRandom.uuid
      correlation_id = SecureRandom.uuid
      Database.db.transaction do
        Database.db[:organizations].insert(
          id: id,
          workspace_id: workspace[:id],
          created_by_workspace_member_id: actor[:id],
          name: name,
          normalized_name: normalized_name,
          website_url: website_url,
          notes: notes,
          created_at: now,
          updated_at: now
        )
        write_audit_event(
          workspace: workspace,
          actor: actor,
          event_type: "organization.created",
          subject_type: "organization",
          subject_id: id,
          payload: {name: name, source_type: "manual"},
          correlation_id: correlation_id,
          occurred_at: now
        )
      end
      serialize_organization(Database.db[:organizations].where(id: id).first)
    end

    def create_interaction(attributes:, workspace:, actor:)
      errors = {}
      person = workspace_record(:people, attributes["person_id"], workspace, "person_id", errors)
      request = optional_workspace_record(:scheduling_requests, attributes["scheduling_request_id"], workspace, "scheduling_request_id", errors)
      interaction_type = optional_text(attributes, "interaction_type", limit: 40)
      errors["interaction_type"] = "Select a valid interaction type." unless INTERACTION_TYPES.include?(interaction_type)
      summary = required_text(attributes, "summary", "Summary", errors, limit: 4_000)
      occurred_at = required_time(attributes, "occurred_at", errors)
      raise ValidationError, errors unless errors.empty?

      now = Time.now.utc
      id = SecureRandom.uuid
      correlation_id = SecureRandom.uuid
      Database.db.transaction do
        Database.db[:interactions].insert(
          id: id,
          workspace_id: workspace[:id],
          person_id: person[:id],
          scheduling_request_id: request&.fetch(:id),
          authored_by_workspace_member_id: actor[:id],
          interaction_type: interaction_type,
          summary: summary,
          source_type: "manual",
          source_id: nil,
          occurred_at: occurred_at,
          created_at: now,
          updated_at: now
        )
        write_audit_event(
          workspace: workspace,
          actor: actor,
          event_type: "interaction.created",
          subject_type: "interaction",
          subject_id: id,
          payload: {
            person_id: person[:id],
            interaction_type: interaction_type,
            occurred_at: occurred_at.iso8601
          },
          correlation_id: correlation_id,
          occurred_at: now
        )
      end
      serialize_interaction(Database.db[:interactions].where(id: id).first)
    end

    def sync_request_context(request_id:, normalized:, workspace:, actor:, occurred_at:, correlation_id:)
      db = Database.db
      existing_no_email = db[:scheduling_request_people]
        .join(:people, id: :person_id)
        .where(Sequel[:scheduling_request_people][:scheduling_request_id] => request_id)
        .select(
          Sequel[:scheduling_request_people][:role],
          Sequel[:people][:id].as(:person_id),
          Sequel[:people][:display_name],
          Sequel[:people][:primary_email]
        )
        .all
        .select { |row| row[:primary_email].nil? }
        .to_h { |row| [[row[:role], row[:display_name].downcase], row[:person_id]] }

      db[:scheduling_request_people].where(scheduling_request_id: request_id).delete

      request_data = normalized.fetch(:request)
      subjects = [{
        name: request_data.fetch(:requester_name),
        email: request_data[:requester_email],
        organization: request_data[:requester_organization],
        organization_field: "requester_organization",
        role: "requester"
      }]
      subjects.concat(normalized.fetch(:participants).each_with_index.map do |participant, index|
        {
          name: participant.fetch(:name),
          email: participant[:email],
          organization: participant[:organization],
          organization_field: "participants.#{index}.organization",
          role: participant.fetch(:role)
        }
      end)

      requester_person_id = nil
      subjects.each do |subject|
        organization_id = resolve_organization(
          workspace: workspace,
          actor: actor,
          name: subject[:organization],
          source_id: request_id,
          occurred_at: occurred_at,
          correlation_id: correlation_id
        )
        person_id = resolve_person(
          workspace: workspace,
          actor: actor,
          display_name: subject.fetch(:name),
          email: subject[:email],
          organization_id: organization_id,
          organization_field: subject.fetch(:organization_field),
          existing_person_id: existing_no_email[[subject.fetch(:role), subject.fetch(:name).downcase]],
          source_id: request_id,
          occurred_at: occurred_at,
          correlation_id: correlation_id
        )

        db[:scheduling_request_people].insert_conflict.insert(
          scheduling_request_id: request_id,
          person_id: person_id,
          role: subject.fetch(:role),
          source_type: "scheduling_request",
          linked_at: occurred_at
        )
        requester_person_id = person_id if subject[:role] == "requester"
      end

      interaction = db[:interactions]
        .where(source_type: "scheduling_request", source_id: request_id)
        .first
      interaction_values = {
        person_id: requester_person_id,
        scheduling_request_id: request_id,
        summary: request_data.fetch(:purpose),
        updated_at: occurred_at
      }
      if interaction
        db[:interactions].where(id: interaction[:id]).update(interaction_values)
      else
        db[:interactions].insert(
          id: SecureRandom.uuid,
          workspace_id: workspace[:id],
          authored_by_workspace_member_id: actor[:id],
          interaction_type: request_interaction_type(request_data.fetch(:source_channel)),
          source_type: "scheduling_request",
          source_id: request_id,
          occurred_at: occurred_at,
          created_at: occurred_at,
          **interaction_values
        )
      end
    end

    def context_for_request(request_id:, workspace:)
      db = Database.db
      request = db[:scheduling_requests].where(id: request_id, workspace_id: workspace[:id]).first
      return {people: [], organizations: [], interactions: []} unless request

      person_rows = db[:scheduling_request_people]
        .join(:people, id: :person_id)
        .where(Sequel[:scheduling_request_people][:scheduling_request_id] => request_id)
        .select_all(:people)
        .select_append(Sequel[:scheduling_request_people][:role].as(:request_role))
        .order(Sequel[:scheduling_request_people][:role], Sequel[:people][:display_name])
        .all
      person_ids = person_rows.map { |person| person[:id] }.uniq
      organization_ids = person_rows.filter_map { |person| person[:organization_id] }.uniq
      organizations_by_id = db[:organizations]
        .where(workspace_id: workspace[:id], id: organization_ids)
        .all
        .to_h { |organization| [organization[:id], organization] }
      request_counts_by_person = grouped_count(
        db[:scheduling_request_people].where(person_id: person_ids),
        :person_id,
        distinct: :scheduling_request_id
      )
      interaction_counts_by_person = grouped_count(
        db[:interactions].where(workspace_id: workspace[:id], person_id: person_ids),
        :person_id
      )
      people_counts_by_organization = grouped_count(
        db[:people].where(workspace_id: workspace[:id], organization_id: organization_ids),
        :organization_id
      )
      request_counts_by_organization = grouped_count(
        db[:scheduling_request_people]
          .join(:people, id: :person_id)
          .where(Sequel[:people][:workspace_id] => workspace[:id], Sequel[:people][:organization_id] => organization_ids),
        Sequel[:people][:organization_id],
        result_key: :organization_id,
        distinct: Sequel[:scheduling_request_people][:scheduling_request_id]
      )
      interaction_counts_by_organization = grouped_count(
        db[:interactions]
          .join(:people, id: :person_id)
          .where(Sequel[:people][:workspace_id] => workspace[:id], Sequel[:people][:organization_id] => organization_ids),
        Sequel[:people][:organization_id],
        result_key: :organization_id
      )
      people = person_rows.group_by { |person| person[:id] }.map do |_id, rows|
        person = rows.first
        serialize_person_overview(
          person,
          organization: person[:organization_id] && organizations_by_id[person[:organization_id]],
          request_count: request_counts_by_person.fetch(person[:id], 0),
          interaction_count: interaction_counts_by_person.fetch(person[:id], 0)
        ).merge(request_role: rows.map { |row| row[:request_role] }.uniq.join(" / "))
      end
      organizations = organization_ids.filter_map do |organization_id|
        organization = organizations_by_id[organization_id]
        next unless organization

        serialize_organization_overview(
          organization,
          people_count: people_counts_by_organization.fetch(organization_id, 0),
          request_count: request_counts_by_organization.fetch(organization_id, 0),
          interaction_count: interaction_counts_by_organization.fetch(organization_id, 0)
        )
      end

      interactions = if person_ids.empty?
        []
      else
        db[:interactions]
          .left_join(:people, id: Sequel[:interactions][:person_id])
          .left_join(:workspace_members, id: Sequel[:interactions][:authored_by_workspace_member_id])
          .where(Sequel[:interactions][:workspace_id] => workspace[:id], Sequel[:interactions][:person_id] => person_ids)
          .select_all(:interactions)
          .select_append(
            Sequel[:people][:display_name].as(:person_name),
            Sequel[:workspace_members][:display_name].as(:author_name)
          )
          .reverse_order(Sequel[:interactions][:occurred_at])
          .limit(20)
          .all
          .map { |interaction| serialize_interaction_overview(interaction).merge(current_request: interaction[:scheduling_request_id] == request_id) }
      end

      {people: people, organizations: organizations, interactions: interactions}
    end

    def serialize_person(person)
      db = Database.db
      organization = person[:organization_id] && db[:organizations].where(id: person[:organization_id]).first
      {
        id: person[:id],
        display_name: person[:display_name],
        primary_email: person[:primary_email],
        primary_phone: person[:primary_phone],
        job_title: person[:job_title],
        notes: person[:notes],
        organization: organization && {id: organization[:id], name: organization[:name]},
        request_count: db[:scheduling_request_people].where(person_id: person[:id]).select(:scheduling_request_id).distinct.count,
        interaction_count: db[:interactions].where(person_id: person[:id]).count,
        created_at: iso8601(person[:created_at]),
        updated_at: iso8601(person[:updated_at])
      }
    end

    def serialize_person_overview(person, organization:, request_count:, interaction_count:)
      {
        id: person[:id],
        display_name: person[:display_name],
        primary_email: person[:primary_email],
        primary_phone: person[:primary_phone],
        job_title: person[:job_title],
        notes: person[:notes],
        organization: organization && {id: organization[:id], name: organization[:name]},
        request_count: request_count,
        interaction_count: interaction_count,
        created_at: iso8601(person[:created_at]),
        updated_at: iso8601(person[:updated_at])
      }
    end

    def serialize_organization(organization)
      db = Database.db
      {
        id: organization[:id],
        name: organization[:name],
        website_url: organization[:website_url],
        notes: organization[:notes],
        people_count: db[:people].where(organization_id: organization[:id]).count,
        request_count: db[:scheduling_request_people]
          .join(:people, id: :person_id)
          .where(Sequel[:people][:organization_id] => organization[:id])
          .select(Sequel[:scheduling_request_people][:scheduling_request_id])
          .distinct
          .count,
        interaction_count: db[:interactions]
          .join(:people, id: :person_id)
          .where(Sequel[:people][:organization_id] => organization[:id])
          .count,
        created_at: iso8601(organization[:created_at]),
        updated_at: iso8601(organization[:updated_at])
      }
    end

    def serialize_organization_overview(organization, people_count:, request_count:, interaction_count:)
      {
        id: organization[:id],
        name: organization[:name],
        website_url: organization[:website_url],
        notes: organization[:notes],
        people_count: people_count,
        request_count: request_count,
        interaction_count: interaction_count,
        created_at: iso8601(organization[:created_at]),
        updated_at: iso8601(organization[:updated_at])
      }
    end

    def serialize_interaction(interaction)
      db = Database.db
      person = db[:people].where(id: interaction[:person_id]).first
      author = db[:workspace_members].where(id: interaction[:authored_by_workspace_member_id]).first
      {
        id: interaction[:id],
        interaction_type: interaction[:interaction_type],
        summary: interaction[:summary],
        person: person && {id: person[:id], display_name: person[:display_name]},
        scheduling_request_id: interaction[:scheduling_request_id],
        author: author && {id: author[:id], display_name: author[:display_name]},
        source_type: interaction[:source_type],
        source_id: interaction[:source_id],
        occurred_at: iso8601(interaction[:occurred_at])
      }
    end

    def serialize_interaction_overview(interaction)
      {
        id: interaction[:id],
        interaction_type: interaction[:interaction_type],
        summary: interaction[:summary],
        person: interaction[:person_id] && {
          id: interaction[:person_id],
          display_name: interaction[:person_name]
        },
        scheduling_request_id: interaction[:scheduling_request_id],
        author: interaction[:authored_by_workspace_member_id] && {
          id: interaction[:authored_by_workspace_member_id],
          display_name: interaction[:author_name]
        },
        source_type: interaction[:source_type],
        source_id: interaction[:source_id],
        occurred_at: iso8601(interaction[:occurred_at])
      }
    end

    def grouped_count(dataset, group_expression, result_key: group_expression, distinct: nil)
      count_expression = if distinct
        Sequel.function(:count, distinct).distinct
      else
        Sequel.function(:count, Sequel.lit("*"))
      end
      selected_group = group_expression.is_a?(Symbol) ? Sequel[group_expression] : group_expression
      dataset
        .group(group_expression)
        .select(selected_group.as(result_key), count_expression.as(:count))
        .to_hash(result_key, :count)
    end

    def resolve_person(workspace:, actor:, display_name:, email:, organization_id:, organization_field:, existing_person_id:, source_id:, occurred_at:, correlation_id:)
      db = Database.db
      normalized_email = email.to_s.strip.downcase
      person = if normalized_email.empty?
        existing_person_id && db[:people].where(id: existing_person_id, workspace_id: workspace[:id]).first
      else
        db[:people].where(workspace_id: workspace[:id], primary_email: normalized_email).first
      end

      if person
        reconcile_person_organization(
          person: person,
          organization_id: organization_id,
          organization_field: organization_field,
          workspace: workspace,
          actor: actor,
          source_id: source_id,
          occurred_at: occurred_at,
          correlation_id: correlation_id
        )
        return person[:id]
      end

      id = SecureRandom.uuid
      db[:people].insert(
        id: id,
        workspace_id: workspace[:id],
        organization_id: organization_id,
        created_by_workspace_member_id: actor[:id],
        display_name: display_name,
        primary_email: normalized_email.empty? ? nil : normalized_email,
        primary_phone: nil,
        job_title: nil,
        notes: nil,
        created_at: occurred_at,
        updated_at: occurred_at
      )
      write_audit_event(
        workspace: workspace,
        actor: actor,
        event_type: "person.created",
        subject_type: "person",
        subject_id: id,
        payload: {
          display_name: display_name,
          primary_email: normalized_email.empty? ? nil : normalized_email,
          organization_id: organization_id,
          source_type: "scheduling_request",
          source_id: source_id
        },
        correlation_id: correlation_id,
        occurred_at: occurred_at
      )
      id
    end

    def reconcile_person_organization(person:, organization_id:, organization_field:, workspace:, actor:, source_id:, occurred_at:, correlation_id:)
      return unless organization_id
      return if person[:organization_id] == organization_id

      if person[:organization_id]
        existing = Database.db[:organizations].where(id: person[:organization_id]).first
        raise ValidationError, {
          organization_field => "#{person[:display_name]} is already linked to #{existing[:name]}. Review the person before changing organizations."
        }
      end

      Database.db[:people].where(id: person[:id]).update(organization_id: organization_id, updated_at: occurred_at)
      write_audit_event(
        workspace: workspace,
        actor: actor,
        event_type: "person.updated",
        subject_type: "person",
        subject_id: person[:id],
        payload: {organization_id: organization_id, source_type: "scheduling_request", source_id: source_id},
        correlation_id: correlation_id,
        occurred_at: occurred_at
      )
    end

    def resolve_organization(workspace:, actor:, name:, source_id:, occurred_at:, correlation_id:)
      normalized_name = normalize_organization_name(name)
      return nil if normalized_name.empty?

      db = Database.db
      organization = db[:organizations].where(workspace_id: workspace[:id], normalized_name: normalized_name).first
      return organization[:id] if organization

      id = SecureRandom.uuid
      db[:organizations].insert(
        id: id,
        workspace_id: workspace[:id],
        created_by_workspace_member_id: actor[:id],
        name: name.to_s.strip,
        normalized_name: normalized_name,
        website_url: nil,
        notes: nil,
        created_at: occurred_at,
        updated_at: occurred_at
      )
      write_audit_event(
        workspace: workspace,
        actor: actor,
        event_type: "organization.created",
        subject_type: "organization",
        subject_id: id,
        payload: {name: name.to_s.strip, source_type: "scheduling_request", source_id: source_id},
        correlation_id: correlation_id,
        occurred_at: occurred_at
      )
      id
    end

    def normalize_organization_name(name)
      name.to_s.downcase.gsub(/[^a-z0-9]+/, " ").strip
    end

    def request_interaction_type(source_channel)
      return "call" if source_channel == "phone"
      return "email" if source_channel == "email"

      "other"
    end

    def required_text(attributes, key, label, errors, limit:)
      value = optional_text(attributes, key, limit: limit)
      errors[key] = "#{label} is required." if value.nil?
      value
    end

    def optional_text(attributes, key, limit:)
      value = attributes[key]
      return nil unless value.is_a?(String)

      normalized = value.strip
      return nil if normalized.empty?

      normalized[0, limit]
    end

    def optional_email(attributes, key, errors)
      value = optional_text(attributes, key, limit: 254)
      return nil unless value

      unless value.match?(EMAIL_PATTERN)
        errors[key] = "Enter a valid email address."
        return nil
      end
      value.downcase
    end

    def optional_url(attributes, key, errors)
      value = optional_text(attributes, key, limit: 500)
      return nil unless value

      uri = URI.parse(value)
      return value if uri.is_a?(URI::HTTP) && uri.host

      errors[key] = "Enter a valid http or https URL."
      nil
    rescue URI::InvalidURIError
      errors[key] = "Enter a valid http or https URL."
      nil
    end

    def required_time(attributes, key, errors)
      value = optional_text(attributes, key, limit: 40)
      unless value
        errors[key] = "Date and time are required."
        return nil
      end
      Time.iso8601(value).utc
    rescue ArgumentError
      errors[key] = "Enter a valid ISO 8601 date and time."
      nil
    end

    def workspace_record(table, id, workspace, field, errors)
      record = optional_workspace_record(table, id, workspace, field, errors)
      errors[field] ||= "Select a valid #{field.delete_suffix("_id").tr("_", " ")}." unless record
      record
    end

    def optional_workspace_record(table, id, workspace, field, errors)
      return nil if id.nil? || id.to_s.strip.empty?

      record = Database.db[table].where(id: id.to_s, workspace_id: workspace[:id]).first
      errors[field] = "The selected record is not in this workspace." unless record
      record
    end

    def write_audit_event(workspace:, actor:, event_type:, subject_type:, subject_id:, payload:, correlation_id:, occurred_at:)
      Database.db[:audit_events].insert(
        id: SecureRandom.uuid,
        workspace_id: workspace[:id],
        actor_workspace_member_id: actor[:id],
        event_type: event_type,
        subject_type: subject_type,
        subject_id: subject_id,
        payload: JSON.generate(payload),
        correlation_id: correlation_id,
        occurred_at: occurred_at
      )
    end

    def iso8601(value)
      value&.iso8601
    end
  end
end
