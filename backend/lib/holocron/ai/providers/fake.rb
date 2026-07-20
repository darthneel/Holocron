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
          prior_interactions = sources.select do |source|
            source["source_type"] == "interaction" && !source.dig("facts", "current_request")
          end
          allowed_refs = lambda do |_section_type, sources_to_cite|
            Array(sources_to_cite).filter_map { |source| source && source["source_ref"] }
              .uniq.first(3)
          end

          purpose = request&.dig("facts", "purpose")
          request_refs = allowed_refs.call("meeting_ask", [request])
          action_evidence = prior_interactions.first(3)
          context_items = prior_interactions.first(4).map do |interaction|
            fake_item(
              interaction.dig("facts", "person_name").to_s,
              interaction_text(interaction),
              allowed_refs.call("decision_context", [interaction])
            )
          end
          risk_evidence = prior_interactions.find do |interaction|
            interaction_text(interaction).match?(/risk|constraint|concern|delay|requires|blocked|shortage|gap/i)
          end
          sections = [
            fake_section("meeting_ask", "Why this meeting", [
              fake_item("The ask", purpose || "Clarify the purpose of the meeting.", request_refs)
            ]),
            fake_section("desired_outcomes", "Desired outcomes", [
              fake_item("Decision", "Reach a clear decision about #{purpose}.", allowed_refs.call("desired_outcomes", [request] + action_evidence)),
              fake_item("Next steps", "Assign owners and dates for agreed next steps.", allowed_refs.call("desired_outcomes", [request] + action_evidence))
            ]),
            fake_section("decision_context", "Decision-relevant context", context_items),
            fake_section("talking_points", "Recommended talking points", [
              fake_item("Open", "Confirm the most important outcome for #{purpose}.", allowed_refs.call("talking_points", [request] + action_evidence)),
              fake_item("Close", "Summarize decisions, owners, and deadlines before ending.", allowed_refs.call("talking_points", [request] + action_evidence))
            ]),
            fake_section("risks", "Risks and sensitivities", risk_evidence ? [
              fake_item("Constraint", interaction_text(risk_evidence), allowed_refs.call("risks", [risk_evidence]))
            ] : []),
            fake_section("open_questions", "Open questions", [
              fake_item("Ownership", "Who will own each follow-up after the meeting?", [])
            ])
          ]

          {
            output: {"sections" => sections, "limitations" => manifest.fetch("limitations", [])},
            model: model,
            provider_request_id: "fake-#{@calls}",
            input_tokens: input.split.length,
            output_tokens: sections.sum { |section| section.fetch("items").sum { |item| item.fetch("text").split.length } }
          }
        end

        def interaction_text(interaction)
          spans = Array(interaction.dig("facts", "evidence_spans"))
          return spans.filter_map { |span| span["text"] }.join(" ") if spans.any?

          interaction.dig("facts", "summary").to_s
        end

        def fake_section(type, title, items)
          {
            "section_type" => type,
            "title" => title,
            "items" => items
          }
        end

        def fake_item(label, text, refs)
          {"label" => label, "text" => text.to_s, "source_refs" => Array(refs).compact.uniq.first(3)}
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
