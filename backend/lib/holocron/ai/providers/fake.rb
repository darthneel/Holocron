# frozen_string_literal: true

require "date"
require "json"

module Holocron
  module AI
    module Providers
      class Fake
        attr_reader :name, :model

        def initialize(model: "fake-request-extractor-v1")
          @name = "fake"
          @model = model
          @calls = 0
        end

        def generate(prompt:, schema:, **_options)
          @calls += 1
          input = prompt.fetch(:input)
          raise RefusalError, "Deterministic fake refusal." if input.include?("[fake:refusal]")
          if input.include?("[fake:transient-once]") && @calls == 1
            raise TransientError, "Deterministic fake transient failure."
          end
          return {output: {"requester" => "malformed"}, model: model} if input.include?("[fake:malformed]")
          return generate_briefing(input) if prompt[:task] == "briefing_generation"

          headers = parse_headers(input)
          requester = parse_identity(headers["from"])
          organization = clean(headers["organization"])
          purpose = clean(headers["subject"]) || first_body_line(input)
          duration = parse_duration(headers["duration"] || input)
          availability = clean(headers["availability"])
          participants = parse_participants(headers["participants"])
          candidate_windows = parse_candidates(input)
          warnings = []
          warnings << "Confirm the requester name." unless requester[:name]
          warnings << "Confirm the meeting purpose." unless purpose
          warnings << "Confirm the meeting duration." unless duration

          {
            output: {
              "requester" => {
                "name" => requester[:name],
                "email" => requester[:email],
                "organization" => organization
              },
              "purpose" => purpose,
              "requested_duration_minutes" => duration,
              "availability_notes" => availability,
              "participants" => participants,
              "candidate_windows" => candidate_windows,
              "warnings" => warnings
            },
            model: model,
            provider_request_id: "fake-#{@calls}",
            input_tokens: input.split.length,
            output_tokens: 0
          }
        end

        private

        def generate_briefing(input)
          manifest = JSON.parse(input)
          sources = manifest.fetch("sources")
          request = sources.find { |source| source["source_type"] == "scheduling_request" }
          meeting = sources.find { |source| source["source_type"] == "meeting" }
          people = sources.select { |source| source["source_type"] == "person" }
          organizations = sources.select { |source| source["source_type"] == "organization" }
          prior_interactions = sources.select do |source|
            source["source_type"] == "interaction" && !source.dig("facts", "current_request")
          end

          purpose = request&.dig("facts", "purpose")
          duration = request&.dig("facts", "requested_duration_minutes")
          overview_lines = []
          overview_lines << purpose if purpose
          overview_lines << "Requested duration: #{duration} minutes." if duration
          attendee_lines = people.map do |person|
            facts = person.fetch("facts")
            context = [facts["job_title"], facts["organization_name"]].compact.join(", ")
            roles = facts.fetch("request_roles", []).map { |role| humanize(role) }.join(" / ")
            suffix = context.empty? ? "" : " - #{context}"
            role_suffix = roles.empty? ? "" : " (#{roles})"
            "#{facts.fetch('display_name')}#{suffix}#{role_suffix}"
          end
          relationship_lines = people.filter_map do |person|
            facts = person.fetch("facts")
            details = [facts["job_title"], facts["organization_name"], facts["notes"]].compact
            next if details.empty?

            "#{facts.fetch('display_name')}: #{details.join('; ')}"
          end
          history_lines = prior_interactions.map do |interaction|
            facts = interaction.fetch("facts")
            "#{facts.fetch('occurred_at')[0, 10]} - #{facts.fetch('summary')}"
          end
          meeting_facts = meeting&.fetch("facts", {}) || {}
          logistics_lines = []
          logistics_lines << "Starts: #{meeting_facts['starts_at']}" if meeting_facts["starts_at"]
          logistics_lines << "Ends: #{meeting_facts['ends_at']}" if meeting_facts["ends_at"]
          logistics_lines << "Location: #{meeting_facts['location'] || 'Not specified'}" if meeting

          organization_refs = organizations.filter_map do |organization|
            person_organization_ids = people.filter_map { |person| person.dig("facts", "organization_id") }
            organization["source_ref"] if person_organization_ids.include?(organization["source_id"])
          end
          people_refs = people.map { |person| person.fetch("source_ref") }
          interaction_refs = prior_interactions.map { |interaction| interaction.fetch("source_ref") }
          sections = [
            fake_section("overview", "Meeting overview", overview_lines, request && [request.fetch("source_ref")]),
            fake_section("attendees", "Attendees", attendee_lines, people_refs + organization_refs),
            fake_section("relationship_context", "Relationship context", relationship_lines, people_refs + organization_refs),
            fake_section("prior_history", "Prior history", history_lines, interaction_refs),
            fake_section(
              "objectives",
              "Objectives and talking points",
              purpose ? ["Discuss #{purpose}", "Identify decisions, owners, and next steps."] : [],
              request && [request.fetch("source_ref")]
            ),
            fake_section("logistics", "Logistics", logistics_lines, meeting && [meeting.fetch("source_ref")])
          ]

          {
            output: {"sections" => sections, "limitations" => manifest.fetch("limitations", [])},
            model: model,
            provider_request_id: "fake-#{@calls}",
            input_tokens: input.split.length,
            output_tokens: sections.sum { |section| section.fetch("body").split.length }
          }
        end

        def fake_section(type, title, lines, refs)
          {
            "section_type" => type,
            "title" => title,
            "body" => Array(lines).compact.join("\n"),
            "source_refs" => Array(refs).compact.uniq.first(25)
          }
        end

        def parse_headers(input)
          input.each_line.each_with_object({}) do |line, result|
            match = line.match(/^([A-Za-z][A-Za-z ]{1,30}):\s*(.+)$/)
            result[match[1].strip.downcase] = match[2].strip if match
          end
        end

        def parse_identity(value)
          return {name: nil, email: nil} unless value

          match = value.match(/\A\s*(.*?)\s*<([^>]+)>\s*\z/)
          if match
            {name: clean(match[1].delete_prefix('"').delete_suffix('"')), email: clean(match[2])&.downcase}
          elsif value.include?("@")
            {name: nil, email: clean(value)&.downcase}
          else
            {name: clean(value), email: nil}
          end
        end

        def parse_duration(value)
          match = value.to_s.match(/\b(\d{1,3})\s*(?:minutes?|mins?|min)\b/i)
          match && Integer(match[1], exception: false)
        end

        def parse_participants(value)
          return [] unless value

          value.split(/\s*;\s*|\s*,\s*(?=[^,]*<)/).filter_map do |entry|
            identity = parse_identity(entry.sub(/\s*\((required|optional|staff)\)\s*\z/i, ""))
            next unless identity[:name] || identity[:email]

            role = entry[/\((required|optional|staff)\)\s*\z/i, 1]&.downcase
            {
              "name" => identity[:name],
              "email" => identity[:email],
              "organization" => nil,
              "role" => role
            }
          end
        end

        def parse_candidates(input)
          input.each_line.filter_map do |line|
            match = line.match(/^Candidate(?: window)?:\s*(\d{4}-\d{2}-\d{2})(?:\s*[,;-]\s*(.+))?$/i)
            next unless match

            {
              "candidate_date" => match[1],
              "starts_at" => nil,
              "ends_at" => nil,
              "notes" => clean(match[2])
            }
          end
        end

        def first_body_line(input)
          input.each_line.map(&:strip).find do |line|
            !line.empty? && !line.match?(/^([A-Za-z][A-Za-z ]{1,30}):\s*/) && !line.start_with?("[fake:")
          end&.then { |line| clean(line) }
        end

        def clean(value)
          text = value.to_s.strip
          text.empty? ? nil : text
        end

        def humanize(value)
          value.to_s.split("_").map(&:capitalize).join(" ")
        end
      end
    end
  end
end
