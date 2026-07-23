# frozen_string_literal: true

require "date"
require "json"
require "securerandom"
require "time"
require_relative "../lib/holocron/calendar"
require_relative "../lib/holocron/database"
require_relative "../lib/holocron/relationships"
require_relative "../lib/holocron/scheduling_requests"
require_relative "../lib/holocron/scheduling_request_workflow"

module Holocron
  module DemoCalendarSeed
    WORKSPACE_SLUG = "cedar-grove-mayor"
    ACTOR_EMAIL = "neelp22@gmail.com"
    OFFICE_UTC_OFFSET = "-06:00"
    PROPOSED_STATUSES = %w[submitted under_review approved].freeze

    module_function

    def run(start_date: default_start_date, output: $stdout)
      db = Database.db
      workspace = db[:workspaces].where(slug: WORKSPACE_SLUG).first
      raise "Seed the Cedar Grove workspace before adding demo calendar data." unless workspace

      actor = db[:workspace_members].where(workspace_id: workspace[:id], email: ACTOR_EMAIL, status: "active").first
      principal = db[:principals].where(workspace_id: workspace[:id], status: "active").first
      scheduling_team = db[:workspace_members]
        .where(workspace_id: workspace[:id], status: "active", role: %w[owner chief_of_staff scheduler])
        .all
      scheduler = scheduling_team.min_by { |member| %w[scheduler chief_of_staff owner].index(member[:role]) || 3 }
      raise "The demo seed requires an active owner and principal." unless actor && principal
      raise "The demo seed requires an active scheduling team member." unless scheduler

      start_on = Date.iso8601(start_date.to_s)
      end_on = start_on + 14
      definitions = demo_definitions
      organization_rows = upsert_organizations(definitions, workspace: workspace, actor: actor)
      people_rows = upsert_people(definitions, organization_rows: organization_rows, workspace: workspace, actor: actor)
      seed_prior_interactions(
        definitions,
        people_rows: people_rows,
        workspace: workspace,
        actor: actor,
        start_on: start_on
      )

      requests = definitions.map do |definition|
        upsert_request(
          definition,
          start_on: start_on,
          workspace: workspace,
          principal: principal,
          actor: actor,
          scheduler: scheduler
        )
      end.compact

      request_ids = requests.map { |request| request[:id] }
      window_count = request_ids.empty? ? 0 : db[:request_candidate_windows].where(scheduling_request_id: request_ids).count
      calendar = Calendar.list(workspace: workspace, start_date: start_on.iso8601, end_date: end_on.iso8601)
      proposed_count = calendar.fetch(:entries).count { |entry| entry[:kind] == "proposed" }

      output.puts "Seeded demo calendar for #{start_on.iso8601} through #{end_on.iso8601}."
      output.puts "#{organization_rows.length} organizations, #{people_rows.length} people, #{requests.length} proposed meetings, #{window_count} candidate windows."
      output.puts "Calendar API exposes #{proposed_count} proposed entries in the demo range."

      {
        start_date: start_on,
        end_date: end_on,
        organization_count: organization_rows.length,
        people_count: people_rows.length,
        request_count: requests.length,
        candidate_window_count: window_count,
        proposed_entry_count: proposed_count
      }
    end

    def default_start_date
      Date.iso8601(ENV.fetch("DEMO_START_DATE", Date.today.iso8601))
    rescue ArgumentError
      raise "DEMO_START_DATE must be an ISO 8601 date."
    end

    def upsert_organizations(definitions, workspace:, actor:)
      organizations = definitions.map { |definition| definition.fetch(:organization) }.uniq { |organization| organization.fetch(:name) }
      organizations.to_h do |organization|
        normalized_name = Relationships.normalize_organization_name(organization.fetch(:name))
        row = Database.db[:organizations].where(workspace_id: workspace[:id], normalized_name: normalized_name).first
        unless row
          created = Relationships.create_organization(
            attributes: {
              "name" => organization.fetch(:name),
              "website_url" => organization.fetch(:website_url),
              "notes" => organization.fetch(:notes)
            },
            workspace: workspace,
            actor: actor
          )
          row = Database.db[:organizations].where(id: created.fetch(:id)).first
        end
        [organization.fetch(:name), row]
      end
    end

    def upsert_people(definitions, organization_rows:, workspace:, actor:)
      contacts = definitions.flat_map { |definition| definition.fetch(:contacts) }.uniq { |contact| contact.fetch(:email) }
      contacts.to_h do |contact|
        organization = organization_rows.fetch(contact.fetch(:organization))
        person = Database.db[:people].where(workspace_id: workspace[:id], primary_email: contact.fetch(:email)).first
        if person
          Database.db[:people].where(id: person[:id]).update(
            organization_id: organization[:id],
            display_name: contact.fetch(:name),
            primary_phone: contact.fetch(:phone),
            job_title: contact.fetch(:job_title),
            notes: contact.fetch(:notes),
            updated_at: Time.now.utc
          )
        else
          created = Relationships.create_person(
            attributes: {
              "display_name" => contact.fetch(:name),
              "primary_email" => contact.fetch(:email),
              "primary_phone" => contact.fetch(:phone),
              "organization_id" => organization[:id],
              "job_title" => contact.fetch(:job_title),
              "notes" => contact.fetch(:notes)
            },
            workspace: workspace,
            actor: actor
          )
          person = Database.db[:people].where(id: created.fetch(:id)).first
        end
        person = Database.db[:people].where(id: person[:id]).first
        [contact.fetch(:email), person]
      end
    end

    def seed_prior_interactions(definitions, people_rows:, workspace:, actor:, start_on:)
      definitions.each_with_index do |definition, index|
        requester = definition.fetch(:contacts).fetch(0)
        source_id = "seed:demo-calendar:#{definition.fetch(:key)}:history"
        next if Database.db[:interactions].where(source_type: "import", source_id: source_id).any?

        occurred_on = start_on - (35 + index * 7)
        occurred_at = local_time(occurred_on, 10 + (index % 5), index.even? ? 0 : 30)
        interaction_id = SecureRandom.uuid
        now = Time.now.utc
        correlation_id = SecureRandom.uuid
        Database.db.transaction do
          Database.db[:interactions].insert(
            id: interaction_id,
            workspace_id: workspace[:id],
            person_id: people_rows.fetch(requester.fetch(:email))[:id],
            scheduling_request_id: nil,
            authored_by_workspace_member_id: actor[:id],
            interaction_type: definition.fetch(:history_type),
            summary: definition.fetch(:history),
            source_type: "import",
            source_id: source_id,
            occurred_at: occurred_at,
            created_at: now,
            updated_at: now
          )
          Database.db[:audit_events].insert(
            id: SecureRandom.uuid,
            workspace_id: workspace[:id],
            actor_workspace_member_id: actor[:id],
            event_type: "interaction.created",
            subject_type: "interaction",
            subject_id: interaction_id,
            payload: JSON.generate(source_type: "import", source_id: source_id),
            correlation_id: correlation_id,
            occurred_at: now
          )
        end
      end
    end

    def upsert_request(definition, start_on:, workspace:, principal:, actor:, scheduler:)
      requester = definition.fetch(:contacts).fetch(0)
      organization = definition.fetch(:organization).fetch(:name)
      attributes = {
        "requester_name" => requester.fetch(:name),
        "requester_email" => requester.fetch(:email),
        "requester_organization" => organization,
        "purpose" => definition.fetch(:purpose),
        "requested_duration_minutes" => definition.fetch(:duration_minutes),
        "availability_notes" => definition.fetch(:availability_notes),
        "source_channel" => definition.fetch(:source_channel),
        "original_request_text" => definition.fetch(:original_request_text),
        "assigned_scheduler_member_id" => scheduler[:id],
        "participants" => definition.fetch(:contacts).drop(1).map do |contact|
          {
            "name" => contact.fetch(:name),
            "email" => contact.fetch(:email),
            "organization" => contact.fetch(:organization),
            "role" => "required"
          }
        end,
        "candidate_windows" => definition.fetch(:windows).map do |window|
          date = start_on + window.fetch(:day_offset)
          starts_at = local_time(date, window.fetch(:hour), window.fetch(:minute, 0))
          ends_at = starts_at + definition.fetch(:duration_minutes) * 60
          {
            "candidate_date" => date.iso8601,
            "starts_at" => starts_at.iso8601,
            "ends_at" => ends_at.iso8601,
            "notes" => window.fetch(:notes)
          }
        end,
        "briefing_context" => definition.fetch(:briefing_context)
      }

      db = Database.db
      request = db[:scheduling_requests].where(
        workspace_id: workspace[:id],
        requester_email: requester.fetch(:email),
        purpose: definition.fetch(:purpose)
      ).first

      if request && PROPOSED_STATUSES.include?(request[:status])
        attributes["expected_lock_version"] = request[:lock_version]
        SchedulingRequests.update(id: request[:id], attributes: attributes, workspace: workspace, actor: actor)
      elsif request
        return request
      else
        created = SchedulingRequests.create(
          attributes: attributes,
          workspace: workspace,
          principal: principal,
          actor: actor
        )
        request = db[:scheduling_requests].where(id: created.fetch(:id)).first
      end

      request = db[:scheduling_requests].where(id: request[:id]).first
      advance_status(request, definition.fetch(:status), workspace: workspace, actor: actor)
      db[:scheduling_requests].where(id: request[:id]).first
    end

    def advance_status(request, target_status, workspace:, actor:)
      transitions = {
        "submitted" => ["under_review", "review_started", "Scheduling team confirmed the request is complete."],
        "under_review" => ["approved", "community_value", "Approved as a high-value community meeting; time remains unconfirmed."]
      }
      target_rank = PROPOSED_STATUSES.index(target_status)
      current = request
      while (current_rank = PROPOSED_STATUSES.index(current[:status])) && current_rank < target_rank
        to_status, reason_code, notes = transitions.fetch(current[:status])
        SchedulingRequestWorkflow.transition(
          id: current[:id],
          attributes: {
            "to_status" => to_status,
            "reason_code" => reason_code,
            "notes" => notes,
            "expected_lock_version" => current[:lock_version]
          },
          workspace: workspace,
          actor: actor
        )
        current = Database.db[:scheduling_requests].where(id: current[:id]).first
      end
    end

    def local_time(date, hour, minute)
      Time.new(date.year, date.month, date.day, hour, minute, 0, OFFICE_UTC_OFFSET).utc
    end

    def contact(name:, email:, phone:, job_title:, organization:, notes:)
      {name: name, email: email, phone: phone, job_title: job_title, organization: organization, notes: notes}
    end

    def agenda(topic:, ask:, outcome:, owner:)
      {
        "agenda_items" => [{
          "topic" => topic,
          "ask" => ask,
          "decision_needed" => "Confirm the Mayor's office position and next owner.",
          "desired_outcome" => outcome,
          "owner" => owner,
          "decision_maker" => "Mayor Elena Park",
          "deadline" => "Within five business days after the meeting",
          "readiness_standard" => "Participants arrive with a concise data summary and a specific next step.",
          "evidence_excerpt" => nil,
          "dependencies" => []
        }],
        "constraints" => ["Keep the working session focused to the requested duration.", "Do not imply a funding commitment before staff review."],
        "promised_deliverables" => [{
          "deliverable" => "Send a written recap with decisions, owners, and due dates.",
          "owner" => owner,
          "deadline" => "Two business days after the meeting",
          "status" => "Planned"
        }],
        "unresolved_questions" => ["Which proposed time works for every required attendee?"]
      }
    end

    def demo_definitions
      [
        {
          key: "housing-roundtable",
          organization: {name: "Summit Housing Collaborative", website_url: "https://summithousingcollaborative.org", notes: "Regional nonprofit coordinating affordable-housing production, preservation, and tenant stability."},
          contacts: [
            contact(name: "Nadia Flores", email: "nadia.flores@summithousingcollaborative.org", phone: "+1 970-555-0142", job_title: "Executive Director", organization: "Summit Housing Collaborative", notes: "Primary city liaison; pragmatic and highly prepared on housing pipeline data."),
            contact(name: "Ethan Cole", email: "ethan.cole@summithousingcollaborative.org", phone: "+1 970-555-0177", job_title: "Policy Director", organization: "Summit Housing Collaborative", notes: "Leads zoning, permitting, and state funding analysis.")
          ],
          purpose: "Housing production barriers roundtable",
          duration_minutes: 60,
          availability_notes: "Nadia is traveling Friday. Both attendees can meet at City Hall or by video.",
          source_channel: "email",
          original_request_text: "Mayor Park, could we hold a focused working session on the projects currently stalled by financing gaps, utility review, and entitlement sequencing? Ethan will bring a one-page pipeline summary. We can make either of the proposed windows work.",
          windows: [
            {day_offset: 1, hour: 10, minute: 0, notes: "Preferred; City Hall conference room requested."},
            {day_offset: 5, hour: 14, minute: 30, notes: "Backup option; video works if the Mayor is off-site."}
          ],
          status: "under_review",
          history_type: "meeting",
          history: "Nadia briefed city staff on a 186-home affordable housing pipeline and identified utility review and gap financing as the two most time-sensitive constraints.",
          briefing_context: agenda(topic: "Near-term housing pipeline", ask: "Identify two city process changes that could unblock projects this quarter.", outcome: "A short action list with named city and partner owners.", owner: "Maya Chen")
        },
        {
          key: "youth-mental-health",
          organization: {name: "North County Health Alliance", website_url: "https://northcountyhealthalliance.org", notes: "Coalition of clinics, schools, and behavioral-health providers serving families across North County."},
          contacts: [
            contact(name: "Dr. Leila Brooks", email: "leila.brooks@northcountyhealthalliance.org", phone: "+1 970-555-0116", job_title: "Chief Medical Officer", organization: "North County Health Alliance", notes: "Pediatrician and coalition spokesperson; focuses on access and crisis response."),
            contact(name: "Tessa Nguyen", email: "tessa.nguyen@northcountyhealthalliance.org", phone: "+1 970-555-0184", job_title: "Director of Community Partnerships", organization: "North County Health Alliance", notes: "Coordinates school district and nonprofit implementation partners.")
          ],
          purpose: "Youth mental health response partnership",
          duration_minutes: 45,
          availability_notes: "The clinical team has held the morning and needs confirmation by noon tomorrow.",
          source_channel: "phone",
          original_request_text: "Leila asked for 45 minutes with the Mayor to align the city's summer youth programming with the Alliance's mobile crisis and referral teams before the school year begins.",
          windows: [{day_offset: 2, hour: 9, minute: 30, notes: "Only shared opening for the clinical and school partners."}],
          status: "approved",
          history_type: "call",
          history: "Dr. Brooks shared that youth crisis referrals increased this spring and proposed a common referral card for recreation staff, school counselors, and library teams.",
          briefing_context: agenda(topic: "Coordinated youth response", ask: "Authorize staff participation in a ninety-day referral pilot.", outcome: "Agreement on pilot scope, launch date, and public messaging.", owner: "Sam Rivera")
        },
        {
          key: "flood-resilience",
          organization: {name: "Blue River Watershed Council", website_url: "https://blueriverwatershed.org", notes: "Watershed partnership focused on flood resilience, habitat restoration, and community preparedness."},
          contacts: [
            contact(name: "Jonah Kim", email: "jonah.kim@blueriverwatershed.org", phone: "+1 970-555-0139", job_title: "Executive Director", organization: "Blue River Watershed Council", notes: "Longtime regional convener with strong relationships across public works agencies."),
            contact(name: "Ana Torres", email: "ana.torres@blueriverwatershed.org", phone: "+1 970-555-0163", job_title: "Floodplain Program Manager", organization: "Blue River Watershed Council", notes: "Technical lead for river modeling, grants, and neighborhood preparedness.")
          ],
          purpose: "Riverfront flood resilience site review",
          duration_minutes: 75,
          availability_notes: "Outdoor walkthrough. Avoid the noon heat; closed-toe shoes recommended.",
          source_channel: "web",
          original_request_text: "We would like to walk the Mayor through the east riverfront reach before the grant concept is finalized. Ana can show the overtopping points, proposed trail detour, and two options for the restored flood bench.",
          windows: [
            {day_offset: 6, hour: 8, minute: 30, notes: "Preferred field window; meet at the East River trailhead."},
            {day_offset: 7, hour: 13, minute: 0, notes: "Indoor briefing at City Hall if field conditions are poor."},
            {day_offset: 8, hour: 10, minute: 0, notes: "Alternate field window with engineering consultant available."}
          ],
          status: "submitted",
          history_type: "meeting",
          history: "Jonah and Ana presented updated flood modeling showing two low riverfront segments where a restored flood bench could reduce neighborhood risk and protect the trail connection.",
          briefing_context: agenda(topic: "East riverfront flood mitigation", ask: "Select a preferred concept for grant development.", outcome: "Direction on the concept, community engagement, and matching-fund strategy.", owner: "Jordan Lee")
        },
        {
          key: "night-market",
          organization: {name: "Cedar Grove Downtown Partnership", website_url: "https://cedargrovedowntown.org", notes: "Business-led downtown management organization supporting events, storefront vitality, and district operations."},
          contacts: [
            contact(name: "Sofia Ramirez", email: "sofia.ramirez@cedargrovedowntown.org", phone: "+1 970-555-0128", job_title: "President", organization: "Cedar Grove Downtown Partnership", notes: "Primary contact for district strategy and merchant coordination."),
            contact(name: "Owen Price", email: "owen.price@cedargrovedowntown.org", phone: "+1 970-555-0196", job_title: "Director of Events", organization: "Cedar Grove Downtown Partnership", notes: "Owns permitting, vendor operations, and event-day logistics.")
          ],
          purpose: "Downtown night market operations",
          duration_minutes: 45,
          availability_notes: "The Partnership needs direction before vendor confirmations go out next week.",
          source_channel: "email",
          original_request_text: "Could we get a short decision meeting on the night market pilot? The open items are the street closure footprint, sanitation support, amplified sound cutoff, and whether the Mayor can open the first market.",
          windows: [
            {day_offset: 2, hour: 15, minute: 0, notes: "In person; operations map will be available."},
            {day_offset: 5, hour: 11, minute: 0, notes: "Video backup before vendor call at 1:00 PM."}
          ],
          status: "under_review",
          history_type: "event",
          history: "Sofia reported that the spring evening market drew roughly 2,400 visitors with no major safety issues; merchants requested clearer loading zones and an earlier sanitation sweep.",
          briefing_context: agenda(topic: "Night market operating plan", ask: "Resolve the remaining city service and street closure decisions.", outcome: "A go-forward plan that allows vendor confirmations to proceed.", owner: "Maya Chen")
        },
        {
          key: "manufacturing-workforce",
          organization: {name: "Front Range Manufacturing Council", website_url: "https://frmanufacturing.org", notes: "Employer council representing advanced manufacturing, clean technology, and industrial suppliers."},
          contacts: [
            contact(name: "Malcolm Reed", email: "malcolm.reed@frmanufacturing.org", phone: "+1 970-555-0107", job_title: "President", organization: "Front Range Manufacturing Council", notes: "Senior employer voice on workforce, infrastructure, and regional competitiveness."),
            contact(name: "Kelsey Grant", email: "kelsey.grant@frmanufacturing.org", phone: "+1 970-555-0155", job_title: "Vice President, Workforce Partnerships", organization: "Front Range Manufacturing Council", notes: "Runs apprenticeship partnerships with employers and community colleges.")
          ],
          purpose: "Advanced manufacturing workforce compact",
          duration_minutes: 60,
          availability_notes: "The community college president may join the Friday option by video.",
          source_channel: "email",
          original_request_text: "We are ready to share a draft employer compact covering paid internships, equipment donations, and a fall hiring cohort. We would value the Mayor's feedback before presenting it to the full council.",
          windows: [
            {day_offset: 8, hour: 16, minute: 0, notes: "Council office; employer co-chairs available."},
            {day_offset: 9, hour: 10, minute: 30, notes: "City Hall; community college president can join remotely."}
          ],
          status: "approved",
          history_type: "meeting",
          history: "Malcolm and Kelsey outlined a workforce compact that could create sixty paid student placements and a shared training-equipment fund for three local manufacturers.",
          briefing_context: agenda(topic: "Employer workforce compact", ask: "Confirm the city's role and identify a public launch window.", outcome: "A refined compact with clear city commitments and a launch owner.", owner: "Sam Rivera")
        },
        {
          key: "safe-routes",
          organization: {name: "Families for Safe Streets Cedar Grove", website_url: "https://safestreetscedargrove.org", notes: "Parent and neighborhood coalition advocating for safer walking and biking routes near schools."},
          contacts: [
            contact(name: "Amina Yusuf", email: "amina.yusuf@safestreetscedargrove.org", phone: "+1 970-555-0131", job_title: "Coalition Director", organization: "Families for Safe Streets Cedar Grove", notes: "Trusted neighborhood organizer and frequent public meeting facilitator."),
            contact(name: "Ben Caldwell", email: "ben.caldwell@safestreetscedargrove.org", phone: "+1 970-555-0171", job_title: "School Programs Lead", organization: "Families for Safe Streets Cedar Grove", notes: "Coordinates parent walk audits and school arrival observations.")
          ],
          purpose: "Eastside safe routes walkthrough",
          duration_minutes: 60,
          availability_notes: "Walk begins at Eastside Elementary. Morning option best reflects arrival conditions.",
          source_channel: "phone",
          original_request_text: "Amina invited the Mayor to join a one-hour route audit around Eastside Elementary. Families want to show the two crossings with the most near misses and discuss quick-build treatments before school starts.",
          windows: [
            {day_offset: 12, hour: 8, minute: 0, notes: "Preferred; observes actual summer program arrival traffic."},
            {day_offset: 13, hour: 16, minute: 0, notes: "Alternate; meet at the Eastside Elementary main entrance."}
          ],
          status: "submitted",
          history_type: "call",
          history: "Amina shared results from a parent walk audit documenting poor sight lines, long crossing distances, and frequent speeding near Eastside Elementary's north entrance.",
          briefing_context: agenda(topic: "Eastside school route safety", ask: "Prioritize quick-build changes for installation before the first day of school.", outcome: "Agreement on two immediate treatments and a resident communication plan.", owner: "Jordan Lee")
        },
        {
          key: "digital-access",
          organization: {name: "Cedar Grove Library Foundation", website_url: "https://cglibraryfoundation.org", notes: "Independent foundation supporting library innovation, literacy, and equitable digital access."},
          contacts: [
            contact(name: "Theo Martin", email: "theo.martin@cglibraryfoundation.org", phone: "+1 970-555-0104", job_title: "Foundation President", organization: "Cedar Grove Library Foundation", notes: "Civic fundraiser focused on measurable community access outcomes."),
            contact(name: "Rhea Das", email: "rhea.das@cglibraryfoundation.org", phone: "+1 970-555-0188", job_title: "Digital Inclusion Manager", organization: "Cedar Grove Library Foundation", notes: "Program lead for device lending, digital navigators, and public Wi-Fi access.")
          ],
          purpose: "Library digital access partnership",
          duration_minutes: 45,
          availability_notes: "Foundation board materials close at the end of the week.",
          source_channel: "web",
          original_request_text: "The Foundation would like to brief the Mayor on a matching campaign for 300 loaner hotspots and expanded digital navigator hours. We need to confirm whether the city can support outreach and identify eligible neighborhoods.",
          windows: [{day_offset: 7, hour: 15, minute: 30, notes: "Library innovation lab; device-lending demo included."}],
          status: "under_review",
          history_type: "meeting",
          history: "Rhea demonstrated the library's digital navigator pilot, which completed 420 one-on-one support sessions and maintained a waitlist for loaner hotspots.",
          briefing_context: agenda(topic: "Digital access expansion", ask: "Confirm city outreach support for the Foundation's matching campaign.", outcome: "A target neighborhood list and shared outreach plan.", owner: "Sam Rivera")
        },
        {
          key: "latino-business-listening",
          organization: {name: "West Mesa Latino Business Network", website_url: "https://westmesabusiness.org", notes: "Peer network supporting Latino-owned small businesses through technical assistance and civic advocacy."},
          contacts: [
            contact(name: "Camila Ortega", email: "camila.ortega@westmesabusiness.org", phone: "+1 970-555-0168", job_title: "Executive Director", organization: "West Mesa Latino Business Network", notes: "Bilingual small-business advocate with deep relationships among West Mesa merchants."),
            contact(name: "Luis Moreno", email: "luis.moreno@westmesabusiness.org", phone: "+1 970-555-0121", job_title: "Board Chair", organization: "West Mesa Latino Business Network", notes: "Restaurant owner and volunteer lead for the Network's permit clinics.")
          ],
          purpose: "Latino small business listening session",
          duration_minutes: 45,
          availability_notes: "Interpretation is not required; both attendees are bilingual. West Mesa location preferred.",
          source_channel: "email",
          original_request_text: "Camila requested a focused listening session on licensing, storefront improvements, and access to city procurement. The Network will bring a short summary from its recent bilingual permit clinic.",
          windows: [
            {day_offset: 12, hour: 13, minute: 30, notes: "West Mesa Community Center; preferred neighborhood location."},
            {day_offset: 13, hour: 9, minute: 0, notes: "City Hall backup option."},
            {day_offset: 14, hour: 13, minute: 30, notes: "Network office; board chair available."}
          ],
          status: "submitted",
          history_type: "event",
          history: "Camila and Luis hosted a bilingual permit clinic attended by thirty-one business owners; recurring questions concerned inspection sequencing, signage permits, and city vendor registration.",
          briefing_context: agenda(topic: "West Mesa small-business barriers", ask: "Select two near-term improvements for permits and procurement access.", outcome: "A practical follow-up plan with bilingual owner communications.", owner: "Maya Chen")
        }
      ]
    end
  end
end

Holocron::DemoCalendarSeed.run if $PROGRAM_NAME == __FILE__
