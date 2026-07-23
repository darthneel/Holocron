# frozen_string_literal: true

# Creates an idempotent, fictional end-to-end briefing scenario with enough
# participant history and workspace distractors to exercise semantic retrieval.

require "json"
require "securerandom"
require "time"
require_relative "../lib/holocron/briefings"
require_relative "../lib/holocron/database"
require_relative "../lib/holocron/scheduling_requests"

module Holocron
  class ResilienceE2ESeed
    REQUESTER_EMAIL = "leila.okafor@cedargroveresilience.org"
    REQUEST_PURPOSE = "Community resilience and cooling access roundtable"

    def initialize(output: $stdout)
      @db = Database.db
      @output = output
    end

    def run
      workspace = @db[:workspaces].where(slug: "cedar-grove-mayor").first
      raise "Cedar Grove workspace is missing." unless workspace

      actor = @db[:workspace_members].where(workspace_id: workspace[:id], email: "neelp22@gmail.com").first
      principal = @db[:principals].where(workspace_id: workspace[:id], status: "active").first
      raise "Seed owner is missing." unless actor
      raise "Workspace principal is missing." unless principal

      people = ensure_people(workspace: workspace, actor: actor)
      inserted = seed_history(workspace: workspace, actor: actor, people: people)
      briefing = ensure_request_and_briefing(workspace: workspace, actor: actor, principal: principal)

      @output.puts "Seeded #{inserted} resilience-evaluation interactions."
      @output.puts "Request: #{REQUEST_PURPOSE}"
      @output.puts "Briefing ID: #{briefing.fetch(:id)}"
      briefing
    ensure
      Database.disconnect!
    end

    private

    def ensure_people(workspace:, actor:)
      resilience_org = ensure_organization(workspace: workspace, actor: actor, name: "Cedar Grove Resilience Collaborative")
      health_org = ensure_organization(workspace: workspace, actor: actor, name: "Front Range Public Health")
      schools_org = ensure_organization(workspace: workspace, actor: actor, name: "Cedar Grove Public Schools")
      mayor_org = ensure_organization(workspace: workspace, actor: actor, name: "Mayor Office")
      chamber_org = ensure_organization(workspace: workspace, actor: actor, name: "Cedar Grove Chamber of Commerce")
      arts_org = ensure_organization(workspace: workspace, actor: actor, name: "North River Arts Council")
      mobility_org = ensure_organization(workspace: workspace, actor: actor, name: "Front Range Mobility Coalition")

      {
        leila: ensure_person(
          workspace: workspace, actor: actor, organization: resilience_org,
          name: "Leila Okafor", email: REQUESTER_EMAIL, title: "Executive Director"
        ),
        nadia: ensure_person(
          workspace: workspace, actor: actor, organization: health_org,
          name: "Dr. Nadia Ibrahim", email: "nadia.ibrahim@frpublichealth.org", title: "Director of Climate Health"
        ),
        marcus: ensure_person(workspace: workspace, actor: actor, organization: schools_org, name: "Marcus Bell", email: "marcus.bell@cedargroveps.org", title: "Superintendent"),
        sam: ensure_person(workspace: workspace, actor: actor, organization: mayor_org, name: "Sam Rivera", email: "sam.rivera@cedargrove.gov", title: "Senior Advisor"),
        darius: ensure_person(workspace: workspace, actor: actor, organization: chamber_org, name: "Darius Holt", email: "dholt@cedargrovechamber.org", title: "President"),
        rina: ensure_person(workspace: workspace, actor: actor, organization: chamber_org, name: "Rina Patel", email: "rpatel@cedargrovechamber.org", title: "Policy Director"),
        avery: ensure_person(workspace: workspace, actor: actor, organization: arts_org, name: "Avery Morgan", email: "avery@northriverarts.org", title: "Executive Director"),
        priya: ensure_person(workspace: workspace, actor: actor, organization: mobility_org, name: "Priya Shah", email: "priya.demo@example.org", title: "Regional Policy Lead")
      }.tap do |records|
        missing = records.select { |_key, value| value.nil? }.keys
        raise "Seed people are missing: #{missing.join(', ')}" unless missing.empty?
      end
    end

    def ensure_organization(workspace:, actor:, name:)
      normalized_name = name.downcase.gsub(/[^a-z0-9]+/, " ").strip
      @db[:organizations].where(workspace_id: workspace[:id], normalized_name: normalized_name).first || begin
        now = Time.now.utc
        id = SecureRandom.uuid
        @db[:organizations].insert(
          id: id,
          workspace_id: workspace[:id],
          created_by_workspace_member_id: actor[:id],
          name: name,
          normalized_name: normalized_name,
          website_url: nil,
          notes: "Fictional retrieval-evaluation seed organization.",
          created_at: now,
          updated_at: now
        )
        @db[:organizations].where(id: id).first
      end
    end

    def ensure_person(workspace:, actor:, organization:, name:, email:, title:)
      @db[:people].where(workspace_id: workspace[:id], primary_email: email).first || begin
        now = Time.now.utc
        id = SecureRandom.uuid
        @db[:people].insert(
          id: id,
          workspace_id: workspace[:id],
          created_by_workspace_member_id: actor[:id],
          organization_id: organization[:id],
          display_name: name,
          primary_email: email,
          primary_phone: nil,
          job_title: title,
          notes: "Fictional retrieval-evaluation seed contact.",
          created_at: now,
          updated_at: now
        )
        @db[:people].where(id: id).first
      end
    end

    def seed_history(workspace:, actor:, people:)
      entries = [
        # Leila: high-value older commitments mixed with recent event noise.
        [:leila, "leila-heat-needs-2024", "meeting", "Leila presented a neighborhood heat-needs assessment showing that older adults and outdoor workers lack reliable cooling access during multi-day heat events.", "2024-05-21T10:00:00-06:00"],
        [:leila, "leila-cooling-center-commitment-2024", "call", "Mayor Park committed to identify library, recreation, and faith-based sites that could serve as coordinated cooling centers before the following summer.", "2024-08-14T15:30:00-06:00"],
        [:leila, "leila-resilience-hubs-2024", "note", "The Resilience Collaborative proposed neighborhood resilience hubs with backup power, clean-air rooms, water distribution, and multilingual heat alerts.", "2024-11-06T09:15:00-07:00"],
        [:leila, "leila-smoke-response-2025", "meeting", "Leila asked the city to align wildfire-smoke messaging with public-health guidance and maintain a public list of clean-air spaces.", "2025-02-19T13:00:00-07:00"],
        [:leila, "leila-cooling-map-2025", "call", "Leila shared a draft cooling-access map and requested that transit stops, hours, accessibility, and pet policies be included before summer outreach.", "2025-04-30T11:30:00-06:00"],
        [:leila, "leila-summer-heat-activation-2025", "meeting", "During the July heat emergency, Leila reported that cooling sites needed extended evening hours, transportation support, and clearer activation triggers.", "2025-07-10T16:00:00-06:00"],
        [:leila, "leila-utility-bill-relief-2025", "email", "Leila requested coordination with utilities on emergency bill-relief communications for households using medical cooling equipment.", "2025-09-03T08:45:00-06:00"],
        [:leila, "leila-community-grant-2025", "note", "The Collaborative received a planning grant to train neighborhood ambassadors on heat safety, smoke preparedness, and resilience-hub operations.", "2025-11-17T14:00:00-07:00"],
        [:leila, "leila-heat-action-plan-2026", "meeting", "Leila asked the Mayor's office to publish a heat-action plan with activation thresholds, cooling-center operations, outreach responsibilities, and post-event review.", "2026-01-29T10:30:00-07:00"],
        [:leila, "leila-cooling-sites-inspection-2026", "call", "Leila said several proposed cooling sites need accessibility checks, backup-power plans, and agreements on staffing before being listed publicly.", "2026-03-12T15:00:00-06:00"],
        [:leila, "leila-earth-day-2026", "event", "Leila invited Mayor Park to Earth Day volunteer activities and requested brief opening remarks.", "2026-04-22T09:00:00-06:00"],
        [:leila, "leila-heat-tabletop-2026", "meeting", "Leila proposed a pre-summer tabletop exercise involving public health, schools, transit, libraries, and neighborhood organizations.", "2026-05-19T13:30:00-06:00"],
        [:leila, "leila-sponsor-breakfast-2026", "email", "The Collaborative asked the Mayor to attend a sponsor breakfast recognizing local donors.", "2026-06-08T08:00:00-06:00"],
        [:leila, "leila-resilience-roundtable-agenda-2026", "note", "For a resilience roundtable, Leila requested decisions on cooling-center activation, school access, clean-air rooms, transit support, and a public heat-alert protocol.", "2026-07-09T11:00:00-06:00"],
        [:leila, "leila-harborlight-working-session-2026", "meeting", "The Project Harborlight working session reviewed neighborhood cooling access, public communications, and site readiness across the west side. Leila objected to publishing the current map because three listed facilities still lack accessible entrances and backup-power agreements. She asked the city to keep the sites internal until facilities staff complete checklist HL-27. Leila committed to deliver translated outreach copy and an updated partner roster by August 12. The group agreed that Sam Rivera will own the final go-live decision after Public Health confirms the activation threshold.", "2026-07-15T13:00:00-06:00"],

        # Nadia: required attendee with public-health history.
        [:nadia, "nadia-heat-health-data-2024", "meeting", "Dr. Ibrahim reported heat-related emergency visits rising during overnight heat and recommended neighborhood-level outreach rather than citywide messaging alone.", "2024-07-02T14:30:00-06:00"],
        [:nadia, "nadia-smoke-clean-air-2024", "call", "Public Health recommended a standing clean-air room protocol for wildfire smoke days, with portable filtration and clear public hours.", "2024-10-15T10:00:00-06:00"],
        [:nadia, "nadia-heat-alert-thresholds-2025", "note", "Nadia proposed shared heat-alert thresholds that trigger cooling-center activation, wellness checks, and multilingual outreach before emergency-department demand spikes.", "2025-03-27T09:00:00-06:00"],
        [:nadia, "nadia-mobile-clinics-2025", "meeting", "Nadia asked whether mobile clinics could visit high-risk apartment complexes during heat emergencies and coordinate with the city's outreach teams.", "2025-06-26T15:00:00-06:00"],
        [:nadia, "nadia-cooling-center-staffing-2025", "call", "Public Health said cooling-center staffing plans need trained volunteers, medication storage guidance, and referral pathways for people without housing.", "2025-08-21T11:15:00-06:00"],
        [:nadia, "nadia-summer-review-2025", "meeting", "After the summer response, Nadia recommended extending evening hours, adding transportation vouchers, and publishing a single source of heat-health information.", "2025-10-08T13:00:00-06:00"],
        [:nadia, "nadia-vaccine-clinic-2026", "event", "Nadia invited the Mayor to a seasonal vaccine clinic and asked for a short public-health video message.", "2026-02-05T09:30:00-07:00"],
        [:nadia, "nadia-heat-plan-review-2026", "note", "Nadia's draft heat-action plan calls for activation thresholds, clean-air operations, school coordination, transit access, and a public after-action report.", "2026-06-18T10:30:00-06:00"],
        [:nadia, "nadia-threshold-revision-2026", "email", "Public Health completed its review of the proposed heat-response thresholds. Nadia recommended replacing the old 105-degree trigger with Protocol CG-HEAT-4, which activates outreach when overnight temperatures remain above 75 degrees for two consecutive nights. She warned that the January guidance is now stale and should not be cited for operational decisions. Nadia will send the signed protocol and neighborhood risk table by August 14. The remaining question is whether Transit can guarantee no-fare service within thirty minutes of activation.", "2026-07-16T09:15:00-06:00"],

        # Existing meeting participants with relevant historical material.
        [:marcus, "marcus-school-cooling-2024", "meeting", "Marcus said schools can serve as daytime cooling locations only if HVAC capacity, custodial staffing, security, and summer-program schedules are confirmed early.", "2024-06-13T11:00:00-06:00"],
        [:marcus, "marcus-school-air-quality-2025", "call", "Marcus requested a consistent decision process for outdoor activities and clean-air spaces during wildfire-smoke events.", "2025-05-15T14:00:00-06:00"],
        [:marcus, "marcus-summer-meals-cooling-2025", "note", "Summer meal sites could pair with cooling access and heat-safety outreach if transportation and staffing gaps are addressed.", "2025-07-24T09:30:00-06:00"],
        [:marcus, "marcus-hvac-capital-plan-2026", "meeting", "Marcus briefed the Mayor on HVAC upgrades and backup-power constraints at schools considered for resilience-hub use.", "2026-03-05T13:30:00-07:00"],
        [:marcus, "marcus-back-to-school-2026", "email", "Marcus invited the Mayor to the back-to-school supply drive kickoff.", "2026-07-01T08:30:00-06:00"],
        [:sam, "sam-heat-response-operations-2024", "note", "Staff mapped city responsibilities for heat emergencies: public alerts, cooling-site activation, transit coordination, outreach, and after-action review.", "2024-08-02T16:00:00-06:00"],
        [:sam, "sam-resilience-hub-operations-2025", "meeting", "Sam outlined operating agreements for resilience hubs, including backup power, city liaisons, liability, supplies, and multilingual communications.", "2025-01-16T11:00:00-07:00"],
        [:sam, "sam-cooling-transit-plan-2025", "call", "Transit staff could provide no-fare rides to designated cooling sites during declared heat emergencies if activation is communicated early.", "2025-06-03T15:30:00-06:00"],
        [:sam, "sam-smoke-and-heat-2025", "meeting", "The Mayor's office asked staff to combine heat and smoke response planning because residents need clean-air cooling spaces during compound events.", "2025-09-25T10:00:00-06:00"],
        [:sam, "sam-heat-grant-2026", "note", "Staff identified a state resilience grant that could fund cooling-site accessibility upgrades, portable filtration, and neighborhood outreach.", "2026-04-16T14:30:00-06:00"],
        [:sam, "sam-resilience-roundtable-prep-2026", "meeting", "For the resilience roundtable, staff recommended decisions on activation thresholds, school-site readiness, transit access, clean-air rooms, and the grant application owner.", "2026-07-11T09:45:00-06:00"],
        [:sam, "sam-harborlight-operations-2026", "note", "Staff reviewed the Project Harborlight operating plan and the unresolved dependencies for a public launch. Facilities confirmed that East Library can open immediately, while Mesa Recreation Center requires a generator inspection and an accessible-door repair. Sam decided that East Library may appear on the public map but Mesa Recreation Center must remain unpublished. The state grant application is due August 19, and Sam assigned Priya Shah to compile the accessibility estimates before August 15. A separate Oak Street shade-pilot discussion was informational and did not change the Harborlight launch plan.", "2026-07-17T16:30:00-06:00"],

        # Workspace distractors and near-misses.
        [:darius, "darius-summer-business-hours-2026", "call", "Darius asked the city to promote adjusted downtown business hours during a hot summer festival weekend.", "2026-06-26T12:30:00-06:00"],
        [:rina, "rina-shaded-sidewalks-2026", "note", "Rina suggested more shade and water stations for downtown shoppers during outdoor events, but did not request emergency cooling operations.", "2026-05-28T10:00:00-06:00"],
        [:avery, "avery-arts-heat-festival-2026", "event", "Avery discussed shade tents and water refill stations for the outdoor arts festival.", "2026-06-15T14:00:00-06:00"],
        [:priya, "priya-bus-stop-shade-2026", "meeting", "Priya Shah proposed shaded bus stops and real-time arrival displays to improve rider comfort during summer heat.", "2026-05-06T11:00:00-06:00"],
        [:priya, "priya-transit-reliability-2026", "call", "Priya requested a meeting about regional transit reliability and commuter pass coordination.", "2026-07-07T15:00:00-06:00"]
      ]

      entries.count do |person_key, suffix, interaction_type, summary, occurred_at|
        source_id = "seed:resilience:#{suffix}"
        next false if @db[:interactions].where(source_type: "import", source_id: source_id).any?

        now = Time.now.utc
        @db.transaction do
          @db[:interactions].insert(
            id: SecureRandom.uuid,
            workspace_id: workspace[:id],
            person_id: people.fetch(person_key).fetch(:id),
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
          @db[:audit_events].insert(
            id: SecureRandom.uuid,
            workspace_id: workspace[:id],
            actor_workspace_member_id: actor[:id],
            event_type: "interaction.created",
            subject_type: "interaction",
            subject_id: source_id,
            payload: JSON.generate({source_type: "import", source_id: source_id}),
            correlation_id: SecureRandom.uuid,
            occurred_at: now
          )
        end
        true
      end
    end

    def ensure_request_and_briefing(workspace:, actor:, principal:)
      request = @db[:scheduling_requests].where(
        workspace_id: workspace[:id], requester_email: REQUESTER_EMAIL, purpose: REQUEST_PURPOSE
      ).first

      unless request
        request = SchedulingRequests.create(
          attributes: {
            "requester_name" => "Leila Okafor",
            "requester_email" => REQUESTER_EMAIL,
            "requester_organization" => "Cedar Grove Resilience Collaborative",
            "purpose" => REQUEST_PURPOSE,
            "requested_duration_minutes" => 60,
            "availability_notes" => "Leila asks for decisions before peak heat season: activation thresholds, cooling-site readiness, clean-air rooms, transit access, and ownership of the state resilience-grant application.",
            "source_channel" => "email",
            "original_request_text" => "Mayor Park, the Resilience Collaborative would welcome a 60-minute roundtable with Dr. Nadia Ibrahim, Superintendent Marcus Bell, and Sam Rivera. We need to align cooling centers, school access, clean-air rooms, transit support, and the resilience grant before the next heat event.",
            "assigned_scheduler_member_id" => actor[:id],
            "participants" => [
              {"name" => "Dr. Nadia Ibrahim", "email" => "nadia.ibrahim@frpublichealth.org", "organization" => "Front Range Public Health", "role" => "required"},
              {"name" => "Marcus Bell", "email" => "marcus.bell@cedargroveps.org", "organization" => "Cedar Grove Public Schools", "role" => "optional"},
              {"name" => "Sam Rivera", "email" => "sam.rivera@cedargrove.gov", "organization" => "Mayor Office", "role" => "staff"}
            ],
            "candidate_windows" => [
              {"candidate_date" => "2026-09-22", "starts_at" => "2026-09-22T10:00:00-06:00", "ends_at" => "2026-09-22T11:00:00-06:00", "notes" => "City Hall, with virtual access for Public Health."}
            ]
          },
          workspace: workspace,
          principal: principal,
          actor: actor
        )
        request = @db[:scheduling_requests].where(id: request.fetch(:id)).first
      end

      meeting = @db[:meetings].where(scheduling_request_id: request[:id]).first
      unless meeting
        Briefings.create_for_request(
          request_id: request[:id],
          attributes: {
            "title" => REQUEST_PURPOSE,
            "starts_at" => "2026-09-22T10:00:00-06:00",
            "ends_at" => "2026-09-22T11:00:00-06:00",
            "location" => "Cedar Grove City Hall - Resilience Operations Room",
            "expected_request_lock_version" => request[:lock_version]
          },
          workspace: workspace,
          actor: actor
        )
      end

      briefing = @db[:briefings].join(:meetings, id: :meeting_id)
        .where(Sequel[:meetings][:scheduling_request_id] => request[:id])
        .select_all(:briefings)
        .first
      raise "Scenario briefing was not created." unless briefing

      briefing
    end
  end
end

Holocron::ResilienceE2ESeed.new.run if $PROGRAM_NAME == __FILE__
