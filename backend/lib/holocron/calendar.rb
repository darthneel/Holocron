# frozen_string_literal: true

require "date"
require_relative "database"

module Holocron
  module Calendar
    PROPOSED_REQUEST_STATUSES = %w[proposed].freeze
    MAX_RANGE_DAYS = 31

    class ValidationError < StandardError; end

    module_function

    def list(workspace:, start_date:, end_date:)
      start_on, end_on = parse_range(start_date, end_date)
      db = Database.db
      principal_id = db[:principals]
        .where(workspace_id: workspace[:id], status: "active")
        .get(:id)
      return empty_payload(workspace, start_on, end_on) unless principal_id

      requests = db[:scheduling_requests]
        .where(workspace_id: workspace[:id], principal_id: principal_id)
        .all
        .to_h { |request| [request[:id], request] }
      return empty_payload(workspace, start_on, end_on) if requests.empty?

      request_ids = requests.keys
      meetings = db[:meetings]
        .where(workspace_id: workspace[:id], scheduling_request_id: request_ids)
        .where(overlaps_range_sql(start_on, end_on, workspace[:timezone]))
        .order(:starts_at, :id)
        .all
      briefings_by_meeting = db[:briefings]
        .where(workspace_id: workspace[:id], meeting_id: meetings.map { |meeting| meeting[:id] })
        .to_hash(:meeting_id)

      candidate_windows = db[:request_candidate_windows]
        .where(scheduling_request_id: request_ids, candidate_date: start_on.iso8601..end_on.iso8601)
        .order(:candidate_date, :position, :id)
        .all
        .select { |window| PROPOSED_REQUEST_STATUSES.include?(requests.fetch(window[:scheduling_request_id])[:status]) }
      candidate_counts = db[:request_candidate_windows]
        .where(scheduling_request_id: candidate_windows.map { |window| window[:scheduling_request_id] }.uniq)
        .group(:scheduling_request_id)
        .select(:scheduling_request_id, Sequel.function(:count, :id).as(:count))
        .to_hash(:scheduling_request_id, :count)

      {
        timezone: workspace[:timezone],
        range: {start_date: start_on.iso8601, end_date: end_on.iso8601},
        entries: meetings.map { |meeting| serialize_meeting(meeting, briefings_by_meeting[meeting[:id]]) } +
          candidate_windows.map { |window| serialize_candidate(window, requests.fetch(window[:scheduling_request_id]), candidate_counts.fetch(window[:scheduling_request_id], 1)) }
      }
    end

    def parse_range(start_date, end_date)
      start_on = Date.iso8601(start_date.to_s)
      end_on = Date.iso8601(end_date.to_s)
      raise ValidationError, "End date must be on or after start date." if end_on < start_on
      raise ValidationError, "Calendar ranges can be at most #{MAX_RANGE_DAYS} days." if (end_on - start_on).to_i + 1 > MAX_RANGE_DAYS

      [start_on, end_on]
    rescue ArgumentError
      raise ValidationError, "start_date and end_date must be valid ISO 8601 dates."
    end

    def empty_payload(workspace, start_on, end_on)
      {timezone: workspace[:timezone], range: {start_date: start_on.iso8601, end_date: end_on.iso8601}, entries: []}
    end

    def overlaps_range_sql(start_on, end_on, timezone)
      Sequel.lit(
        "meetings.starts_at < ((?::date + INTERVAL '1 day')::timestamp AT TIME ZONE ?) AND meetings.ends_at > (?::date::timestamp AT TIME ZONE ?)",
        end_on.iso8601,
        timezone,
        start_on.iso8601,
        timezone
      )
    end

    def serialize_meeting(meeting, briefing)
      {
        id: "meeting:#{meeting[:id]}",
        kind: "scheduled",
        meeting_id: meeting[:id],
        briefing_id: briefing && briefing[:id],
        scheduling_request_id: meeting[:scheduling_request_id],
        title: meeting[:title],
        starts_at: meeting[:starts_at].iso8601,
        ends_at: meeting[:ends_at].iso8601,
        location: meeting[:location]
      }
    end

    def serialize_candidate(window, request, count)
      {
        id: "candidate:#{window[:id]}",
        kind: "proposed",
        candidate_window_id: window[:id],
        scheduling_request_id: request[:id],
        request_status: request[:status],
        title: request[:purpose],
        candidate_date: window[:candidate_date].to_s,
        starts_at: window[:starts_at]&.iso8601,
        ends_at: window[:ends_at]&.iso8601,
        option_label: "Option #{window[:position] + 1} of #{count}",
        notes: window[:notes]
      }
    end
  end
end
