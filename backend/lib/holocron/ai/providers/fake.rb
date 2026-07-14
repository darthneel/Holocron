# frozen_string_literal: true

require "date"

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

        def generate(prompt:, schema:)
          @calls += 1
          input = prompt.fetch(:input)
          raise RefusalError, "Deterministic fake refusal." if input.include?("[fake:refusal]")
          if input.include?("[fake:transient-once]") && @calls == 1
            raise TransientError, "Deterministic fake transient failure."
          end
          return {output: {"requester" => "malformed"}, model: model} if input.include?("[fake:malformed]")

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
      end
    end
  end
end
