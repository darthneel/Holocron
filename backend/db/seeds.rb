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

# A deliberately varied history for retrieval evaluation. The Darius and Rina
# records contain older permitting and small-business commitments that should
# outrank newer, less relevant updates for a business-roundtable briefing.
# Other records provide realistic workspace-level distractors and adjacent
# topics, so semantic retrieval has to discriminate rather than simply match a
# person's newest notes.
if db.table_exists?(:people)
  workspace = db[:workspaces].where(slug: "cedar-grove-mayor").first
  actor = workspace && db[:workspace_members].where(workspace_id: workspace[:id], email: "neelp22@gmail.com").first

  if workspace && actor
    people = db[:people]
      .where(workspace_id: workspace[:id])
      .exclude(primary_email: nil)
      .all
      .to_h { |person| [person[:primary_email].downcase, person] }

    expanded_interactions = [
      # Darius: older high-value commitments, mixed with recent but weaker context.
      ["dholt@cedargrovechamber.org", "seed:darius-permit-turnaround-2024", "meeting", "Darius asked the Mayor to prioritize a predictable storefront permit turnaround; the Chamber offered to collect examples from downtown businesses.", "2024-06-18T09:30:00-06:00"],
      ["dholt@cedargrovechamber.org", "seed:darius-small-business-listening-2024", "note", "Small-business listening session identified permit timelines, inspection coordination, and construction communication as the top operational concerns.", "2024-09-26T14:15:00-06:00"],
      ["dholt@cedargrovechamber.org", "seed:darius-quarterly-roundtable-commitment-2024", "call", "Mayor Park committed to a quarterly small-business roundtable with the Chamber, beginning with a winter update on storefront permitting.", "2024-12-12T11:00:00-07:00"],
      ["dholt@cedargrovechamber.org", "seed:darius-permitting-dashboard-2025", "meeting", "Darius requested a simple public dashboard for commercial permit status and agreed the Chamber would test the first version with five downtown businesses.", "2025-02-20T10:00:00-07:00"],
      ["dholt@cedargrovechamber.org", "seed:darius-construction-communications-2025", "call", "The Chamber asked for earlier notice on downtown construction closures so merchants can plan deliveries and customer communications.", "2025-05-07T15:30:00-06:00"],
      ["dholt@cedargrovechamber.org", "seed:darius-inspection-pilot-2025", "meeting", "Mayor Park asked staff to explore a coordinated inspection pilot for small tenant improvements before the next Chamber roundtable.", "2025-08-28T13:00:00-06:00"],
      ["dholt@cedargrovechamber.org", "seed:darius-winter-luncheon-2026", "event", "Darius invited Mayor Park to the Chamber winter luncheon; no policy follow-up was requested.", "2026-01-16T12:00:00-07:00"],
      ["dholt@cedargrovechamber.org", "seed:darius-awards-sponsorship-2026", "email", "The Chamber requested sponsorship remarks for the annual business awards dinner and asked for a short congratulatory video.", "2026-02-11T09:45:00-07:00"],
      ["dholt@cedargrovechamber.org", "seed:darius-retail-pulse-2026", "call", "Darius reported stable downtown foot traffic but noted that merchants remain concerned about the timing of tenant-improvement permits.", "2026-04-22T16:00:00-06:00"],
      ["dholt@cedargrovechamber.org", "seed:darius-summer-festival-2026", "email", "Darius asked whether the Mayor could attend the summer street festival opening and introduce the local business honorees.", "2026-05-30T08:30:00-06:00"],
      ["dholt@cedargrovechamber.org", "seed:darius-roundtable-agenda-2026", "meeting", "Darius proposed that the next quarterly roundtable cover permit turnaround metrics, the inspection pilot, and construction-notice improvements.", "2026-06-24T10:30:00-06:00"],

      # Rina: adjacent Chamber context that semantic retrieval can discover even
      # when it is not attached directly to the Darius request.
      ["rpatel@cedargrovechamber.org", "seed:rina-permitting-workgroup-2025", "meeting", "Rina convened Chamber members to review recurring storefront permitting delays and proposed a monthly city-business escalation channel.", "2025-01-23T09:00:00-07:00"],
      ["rpatel@cedargrovechamber.org", "seed:rina-tenant-improvements-2025", "note", "Rina shared examples of small tenant improvements delayed by sequential inspections; the group requested clearer handoffs between departments.", "2025-04-14T14:00:00-06:00"],
      ["rpatel@cedargrovechamber.org", "seed:rina-roundtable-scorecard-2025", "call", "Rina suggested a roundtable scorecard tracking commercial permit turnaround, inspection coordination, and unresolved merchant cases.", "2025-09-18T11:15:00-06:00"],
      ["rpatel@cedargrovechamber.org", "seed:rina-holiday-parking-2025", "email", "Rina requested a holiday parking reminder for downtown shoppers and merchants.", "2025-11-20T13:30:00-07:00"],
      ["rpatel@cedargrovechamber.org", "seed:rina-permit-liaison-feedback-2026", "call", "Rina said the permitting liaison has improved response time but merchants still need clearer expectations for inspections and resubmittals.", "2026-03-17T10:00:00-06:00"],
      ["rpatel@cedargrovechamber.org", "seed:rina-business-awards-2026", "event", "Rina coordinated business awards logistics and asked the Mayor's office to confirm table assignments.", "2026-05-12T15:00:00-06:00"],
      ["rpatel@cedargrovechamber.org", "seed:rina-quarterly-roundtable-brief-2026", "note", "For the quarterly roundtable, Rina recommended reporting permit metrics, active inspection-pilot cases, and downtown construction communications.", "2026-06-30T09:20:00-06:00"],

      # Internal staff context, intentionally useful but not all attendee-linked.
      ["sam.rivera@cedargrove.gov", "seed:sam-permit-liaison-status-2025", "note", "Staff launched a permitting liaison office hour for small businesses; early cases show faster routing but inconsistent inspection scheduling.", "2025-03-04T16:30:00-07:00"],
      ["sam.rivera@cedargrove.gov", "seed:sam-inspection-pilot-design-2025", "meeting", "Sam outlined a coordinated inspection pilot for tenant improvements, with a target to reduce repeat site visits and publish a single point of contact.", "2025-07-16T14:00:00-06:00"],
      ["sam.rivera@cedargrove.gov", "seed:sam-downtown-construction-2025", "call", "Public works agreed to send a two-week construction notice to Chamber staff for distribution to affected merchants.", "2025-10-02T10:45:00-06:00"],
      ["sam.rivera@cedargrove.gov", "seed:sam-permit-metrics-2026", "note", "April dashboard: median small commercial permit review time improved, while resubmittal delays remain concentrated in fire and accessibility reviews.", "2026-04-08T08:45:00-06:00"],
      ["sam.rivera@cedargrove.gov", "seed:sam-roundtable-prep-2026", "meeting", "Staff recommended the Mayor arrive with current permit turnaround metrics, pilot results, and a response on construction-notice cadence.", "2026-07-02T11:00:00-06:00"],

      # Plausible but mostly irrelevant workspace history.
      ["marcus.bell@cedargroveps.org", "seed:marcus-school-modernization-2025", "meeting", "Marcus briefed the Mayor on school modernization bonds, classroom ventilation upgrades, and construction phasing for the middle school.", "2025-02-05T13:00:00-07:00"],
      ["marcus.bell@cedargroveps.org", "seed:marcus-school-bus-safety-2025", "call", "Marcus requested support for school bus safety messaging near the new elementary campus.", "2025-09-09T10:00:00-06:00"],
      ["marcus.bell@cedargroveps.org", "seed:marcus-graduation-2026", "email", "Marcus invited Mayor Park to deliver brief remarks at high-school graduation.", "2026-04-29T09:30:00-06:00"],
      ["priya.nanduri@cedargroveps.org", "seed:priya-stem-grant-2025", "meeting", "Priya discussed a regional STEM grant, teacher externships, and student transportation to the innovation campus.", "2025-06-11T15:00:00-06:00"],
      ["priya.nanduri@cedargroveps.org", "seed:priya-youth-mental-health-2026", "call", "Priya asked the Mayor's office to support a youth mental-health resource fair with school counselors and local providers.", "2026-03-25T14:30:00-06:00"],
      ["priya.nanduri@cedargroveps.org", "seed:priya-career-day-2026", "email", "Priya invited the Mayor to student career day and requested a short message about public service careers.", "2026-06-04T09:00:00-06:00"],
      ["avery@northriverarts.org", "seed:avery-public-art-2025", "meeting", "Avery presented a public-art corridor proposal, including artist stipends, storefront murals, and a fall gallery walk.", "2025-04-02T11:30:00-06:00"],
      ["avery@northriverarts.org", "seed:avery-arts-festival-2026", "event", "Avery requested the Mayor attend the River Arts festival opening and recognize student mural finalists.", "2026-05-18T17:00:00-06:00"],
      ["priya.demo@example.org", "seed:priya-mobility-corridor-2025", "meeting", "Priya Shah shared a mobility-corridor proposal focused on bus reliability, safer crossings, and employer commute benefits.", "2025-08-06T10:00:00-06:00"],
      ["priya.demo@example.org", "seed:priya-mobility-grant-2026", "call", "Priya asked for a letter of support for a regional mobility grant and a meeting with transit agency staff.", "2026-02-03T13:45:00-07:00"],
      ["rafael.demo@example.org", "seed:rafael-neighborhood-cleanup-2026", "email", "Rafael invited the Mayor to a neighborhood cleanup and requested waste-hauling support for the volunteer event.", "2026-06-12T08:00:00-06:00"]
    ]

    inserted = 0
    expanded_interactions.each do |email, source_id, interaction_type, summary, occurred_at|
      person = people[email]
      next unless person
      next if db[:interactions].where(source_type: "import", source_id: source_id).any?

      now = Time.now.utc
      interaction_id = SecureRandom.uuid
      correlation_id = SecureRandom.uuid
      db.transaction do
        db[:interactions].insert(
          id: interaction_id,
          workspace_id: workspace[:id],
          person_id: person[:id],
          scheduling_request_id: nil,
          authored_by_workspace_member_id: actor[:id],
          interaction_type: interaction_type,
          summary: summary,
          source_type: "import",
          source_id: source_id,
          occurred_at: Time.iso8601(occurred_at),
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
          payload: JSON.generate({source_type: "import", source_id: source_id}),
          correlation_id: correlation_id,
          occurred_at: now
        )
      end
      inserted += 1
    end
    puts "Seeded #{inserted} expanded retrieval-evaluation interactions." if inserted.positive?
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
