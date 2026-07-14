# frozen_string_literal: true

require "json"
require "securerandom"
require "time"
require "date"
require_relative "../lib/holocron/database"
require_relative "../lib/holocron/briefings"
require_relative "../lib/holocron/scheduling_request_workflow"

db = Holocron::Database.db

foundation_exists = db[:workspaces].where(slug: "cedar-grove-mayor").any?
if foundation_exists
  puts "Cedar Grove foundation data already exists."
else

now = Time.now.utc
workspace_id = SecureRandom.uuid
correlation_id = SecureRandom.uuid

members = [
  {
    id: SecureRandom.uuid,
    display_name: "Elena Park",
    email: "mayor@cedargrove.gov",
    job_title: "Mayor",
    role: "principal"
  },
  {
    id: SecureRandom.uuid,
    display_name: "Neel",
    email: "neelp22@gmail.com",
    job_title: "Workspace Owner",
    role: "owner"
  },
  {
    id: SecureRandom.uuid,
    display_name: "Maya Chen",
    email: "maya.chen@cedargrove.gov",
    job_title: "Chief of Staff",
    role: "chief_of_staff"
  },
  {
    id: SecureRandom.uuid,
    display_name: "Jordan Lee",
    email: "jordan.lee@cedargrove.gov",
    job_title: "Director of Scheduling",
    role: "scheduler"
  },
  {
    id: SecureRandom.uuid,
    display_name: "Sam Rivera",
    email: "sam.rivera@cedargrove.gov",
    job_title: "Senior Advisor",
    role: "advisor"
  }
]

principal_member = members.fetch(0)
principal_id = SecureRandom.uuid

db.transaction do
  db[:workspaces].insert(
    id: workspace_id,
    slug: "cedar-grove-mayor",
    name: "Cedar Grove Mayor's Office",
    timezone: "America/Denver",
    retention_days: 365,
    created_at: now,
    updated_at: now
  )

  members.each do |member|
    db[:workspace_members].insert(
      **member,
      workspace_id: workspace_id,
      status: "active",
      created_at: now,
      updated_at: now
    )
  end

  db[:principals].insert(
    id: principal_id,
    workspace_id: workspace_id,
    workspace_member_id: principal_member[:id],
    title: "Mayor",
    status: "active",
    created_at: now,
    updated_at: now
  )

  events = [
    ["workspace.created", "workspace", workspace_id, {name: "Cedar Grove Mayor's Office"}],
    ["principal.created", "principal", principal_id, {display_name: "Elena Park", title: "Mayor"}],
    ["workspace_members.seeded", "workspace", workspace_id, {count: members.length}]
  ]

  events.each_with_index do |(event_type, subject_type, subject_id, payload), index|
    db[:audit_events].insert(
      id: SecureRandom.uuid,
      workspace_id: workspace_id,
      actor_workspace_member_id: index.zero? ? nil : principal_member[:id],
      event_type: event_type,
      subject_type: subject_type,
      subject_id: subject_id,
      payload: JSON.generate(payload),
      correlation_id: correlation_id,
      occurred_at: now + index
    )
  end
end

puts "Seeded Cedar Grove Mayor's Office."
end

if db.table_exists?(:people)
  workspace = db[:workspaces].where(slug: "cedar-grove-mayor").first
  darius = workspace && db[:people].where(workspace_id: workspace[:id], primary_email: "dholt@cedargrovechamber.org").first
  actor = workspace && db[:workspace_members].where(workspace_id: workspace[:id], email: "neelp22@gmail.com").first
  chamber = darius && darius[:organization_id] && db[:organizations].where(id: darius[:organization_id]).first

  if workspace && darius && actor && chamber
    historical_interactions = [
      {
        source_id: "seed:darius-roundtable-2025",
        interaction_type: "meeting",
        summary: "Mayor Park joined the Chamber's fall small-business roundtable; follow-up focused on storefront permitting.",
        occurred_at: Time.iso8601("2025-11-14T17:00:00-07:00")
      },
      {
        source_id: "seed:darius-permitting-follow-up",
        interaction_type: "call",
        summary: "Darius shared positive feedback on the permitting liaison and asked to keep quarterly roundtables on the calendar.",
        occurred_at: Time.iso8601("2026-03-09T10:30:00-07:00")
      }
    ]

    historical_interactions.each do |history|
      next if db[:interactions].where(source_type: "import", source_id: history[:source_id]).any?

      now = Time.now.utc
      interaction_id = SecureRandom.uuid
      correlation_id = SecureRandom.uuid
      db.transaction do
        db[:interactions].insert(
          id: interaction_id,
          workspace_id: workspace[:id],
          person_id: darius[:id],
          scheduling_request_id: nil,
          authored_by_workspace_member_id: actor[:id],
          interaction_type: history[:interaction_type],
          summary: history[:summary],
          source_type: "import",
          source_id: history[:source_id],
          occurred_at: history[:occurred_at],
          created_at: now,
          updated_at: now
        )
        db[:audit_events].insert(
          id: SecureRandom.uuid,
          workspace_id: workspace[:id],
          actor_workspace_member_id: actor[:id],
          event_type: "interaction.created",
          subject_type: "interaction",
          subject_id: interaction_id,
          payload: JSON.generate({source_type: "import", source_id: history[:source_id]}),
          correlation_id: correlation_id,
          occurred_at: now
        )
      end
    end
  end
end

if db.table_exists?(:briefings)
  workspace = db[:workspaces].where(slug: "cedar-grove-mayor").first
  actor = workspace && db[:workspace_members].where(workspace_id: workspace[:id], email: "neelp22@gmail.com").first
  request = workspace && db[:scheduling_requests].where(
    workspace_id: workspace[:id],
    requester_email: "dholt@cedargrovechamber.org"
  ).first
  meeting = request && db[:meetings].where(scheduling_request_id: request[:id]).first
  window = request && db[:request_candidate_windows]
    .where(scheduling_request_id: request[:id])
    .order(:position)
    .first

  if workspace && actor && request && !meeting && window
    transitions = {
      "submitted" => ["under_review", "review_started"],
      "under_review" => ["approved", "ready_to_schedule"],
      "approved" => ["scheduled", "time_confirmed"]
    }
    while (transition = transitions[request[:status]])
      Holocron::SchedulingRequestWorkflow.transition(
        id: request[:id],
        attributes: {
          "to_status" => transition[0],
          "reason_code" => transition[1],
          "expected_lock_version" => request[:lock_version]
        },
        workspace: workspace,
        actor: actor
      )
      request = db[:scheduling_requests].where(id: request[:id]).first
    end

    candidate_date = Date.iso8601(window[:candidate_date])
    starts_at = window[:starts_at] || Time.new(candidate_date.year, candidate_date.month, candidate_date.day, 10, 0, 0, "-06:00")
    ends_at = window[:ends_at] || starts_at + (request[:requested_duration_minutes] * 60)

    if request[:status] == "scheduled"
      Holocron::Briefings.create_for_request(
        request_id: request[:id],
        attributes: {
          "title" => request[:purpose],
          "starts_at" => starts_at.iso8601,
          "ends_at" => ends_at.iso8601,
          "location" => "Cedar Grove City Hall - Conference Room A"
        },
        workspace: workspace,
        actor: actor
      )
      puts "Seeded Darius Holt briefing."
    end
  end
end
