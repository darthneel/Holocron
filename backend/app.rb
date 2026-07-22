# frozen_string_literal: true

require "json"
require "roda"
require "uri"
require_relative "lib/holocron/ask_ai"
require_relative "lib/holocron/http_middleware"
require_relative "lib/holocron/database"
require_relative "lib/holocron/briefings"
require_relative "lib/holocron/calendar"
require_relative "lib/holocron/relationships"
require_relative "lib/holocron/request_extractions"
require_relative "lib/holocron/scheduling_requests"
require_relative "lib/holocron/scheduling_request_workflow"
require_relative "lib/holocron/tasks"

module Holocron
  class App < Roda
    use RequestIdMiddleware
    use ServerTimingMiddleware
    use CorsMiddleware
    use JsonErrorMiddleware

    plugin :all_verbs
    plugin :json

    EMAIL_PATTERN = URI::MailTo::EMAIL_REGEXP

    route do |r|
      r.get "health" do
        {status: "ok", service: "holocron-api"}
      end

      r.on "api" do
        r.post "fake-session" do
          body = parse_json_body(r)
          email = body.fetch("email", "").strip.downcase

          unless valid_email?(email)
            response.status = 422
            next({error: "Enter a valid email address."})
          end

          member = Database.db[:workspace_members]
            .where(Sequel.function(:lower, :email) => email)
            .first

          {
            email: email,
            known_member: !member.nil?,
            display_name: member&.fetch(:display_name) || display_name_from(email),
            role: member&.fetch(:role) || "viewer"
          }
        rescue JSON::ParserError
          response.status = 400
          {error: "Request body must be valid JSON."}
        end

        r.post "ask" do
          begin
            workspace = current_workspace
            unless workspace
              response.status = 503
              next({error: "Foundation data has not been seeded."})
            end

            body = parse_json_body(r)
            unless body.is_a?(Hash)
              response.status = 400
              next({error: "Request body must be a JSON object."})
            end

            actor = actor_or_error(r, workspace)
            next actor if actor.key?(:error)

            result = AskAI.answer(question: body["question"], workspace: workspace)
            unless result.status == "succeeded"
              response.status = ask_failure_status(result)
              next({
                error: result.failure_reason || "Ask Holocron could not complete the request.",
                provider: result.provider,
                model: result.model,
                validation_errors: result.validation_errors
              }.compact)
            end

            serialize_ask_result(result)
          rescue JSON::ParserError
            response.status = 400
            {error: "Request body must be valid JSON."}
          rescue AskAI::ValidationError => error
            response.status = 422
            {error: error.message, fields: error.fields}
          end
        end

        r.get "foundation" do
          workspace_payload(include_audit: true)
        end

        r.get "bootstrap" do
          workspace_payload(include_audit: false)
        end

        r.get "audit-events" do
          workspace = current_workspace
          unless workspace
            response.status = 503
            next({error: "Foundation data has not been seeded."})
          end

          limit = Integer(r.params.fetch("limit", "25"), exception: false) || 25
          limit = [[limit, 1].max, 100].min
          events = Database.db[:audit_events]
            .where(workspace_id: workspace[:id])
            .reverse_order(:occurred_at, :id)
            .limit(limit)
            .all
            .map { |event| serialize_audit_event(event) }
          {audit_events: events}
        end

        r.get "tasks" do
          workspace = current_workspace
          unless workspace
            response.status = 503
            next({error: "Foundation data has not been seeded."})
          end

          {tasks: Tasks.list(workspace: workspace)}
        end

        r.get "calendar" do
          workspace = current_workspace
          unless workspace
            response.status = 503
            next({error: "Foundation data has not been seeded."})
          end

          Calendar.list(
            workspace: workspace,
            start_date: r.params["start_date"],
            end_date: r.params["end_date"]
          )
        rescue Calendar::ValidationError => error
          response.status = 422
          {error: error.message}
        end

        r.on "briefings" do
          workspace = current_workspace

          unless workspace
            response.status = 503
            next({error: "Foundation data has not been seeded."})
          end

          r.get true do
            {briefings: Briefings.list(workspace: workspace)}
          end

          r.on String do |id|
            r.post "generate" do
              briefing_command(r, workspace, :generate_version, identifier: id)
            end

            r.post "versions" do
              briefing_command(r, workspace, :create_version, identifier: id)
            end

            r.post "submit-review" do
              briefing_command(r, workspace, :submit_for_review, identifier: id)
            end

            r.post "reviews" do
              briefing_command(r, workspace, :review, identifier: id)
            end

            r.post "evaluate-generation" do
              briefing_command(r, workspace, :evaluate_version, identifier: id)
            end

            r.get true do
              lean_detail = r.params["view"] == "current"
              briefing = Briefings.fetch(
                id: id,
                workspace: workspace,
                include_history: !lean_detail,
                include_source_catalog: !lean_detail
              )
              unless briefing
                response.status = 404
                next({error: "Briefing not found."})
              end
              briefing
            end
          end
        end

        r.on "relationships" do
          workspace = current_workspace

          unless workspace
            response.status = 503
            next({error: "Foundation data has not been seeded."})
          end

          r.get true do
            Relationships.overview(workspace: workspace)
          end

          r.on "people" do
            r.post true do
              relationship_command(r, workspace, :create_person)
            end

            r.on String do |id|
              r.patch true do
                relationship_command(r, workspace, :update_person, id: id, success_status: 200)
              end
            end
          end

          r.post "organizations" do
            relationship_command(r, workspace, :create_organization)
          end

          r.post "interactions" do
            relationship_command(r, workspace, :create_interaction)
          end
        end

        r.on "request-extractions" do
          workspace = current_workspace

          unless workspace
            response.status = 503
            next({error: "Foundation data has not been seeded."})
          end

          r.post true do
            begin
              body = parse_json_body(r)
              unless body.is_a?(Hash)
                response.status = 400
                next({error: "Request body must be a JSON object."})
              end

              actor = actor_or_error(r, workspace)
              next actor if actor.key?(:error)

              response.status = 201
              RequestExtractions.extract(
                input_text: body["input_text"],
                workspace: workspace,
                actor: actor
              )
            rescue JSON::ParserError
              response.status = 400
              {error: "Request body must be valid JSON."}
            rescue RequestExtractions::ValidationError => error
              response.status = 422
              {error: error.message, fields: error.fields}
            end
          end

          r.on String do |id|
            r.get true do
              extraction = RequestExtractions.fetch(id: id, workspace: workspace)
              unless extraction
                response.status = 404
                next({error: "Request extraction not found."})
              end
              extraction
            end
          end
        end

        r.on "scheduling-requests" do
          workspace = current_workspace

          unless workspace
            response.status = 503
            next({error: "Foundation data has not been seeded."})
          end

          r.get true do
            {requests: SchedulingRequests.list(workspace: workspace)}
          end

          r.post true do
            begin
              body = parse_json_body(r)
              unless body.is_a?(Hash)
                response.status = 400
                next({error: "Request body must be a JSON object."})
              end

              actor = actor_or_error(r, workspace)
              next actor if actor.key?(:error)

              principal = active_principal(workspace)
              unless principal
                response.status = 503
                next({error: "Workspace principal has not been configured."})
              end

              response.status = 201
              SchedulingRequests.create(
                attributes: body,
                workspace: workspace,
                principal: principal,
                actor: actor
              )
            rescue JSON::ParserError
              response.status = 400
              {error: "Request body must be valid JSON."}
            rescue SchedulingRequests::ValidationError => error
              response.status = 422
              {error: error.message, fields: error.fields}
            rescue Relationships::ValidationError => error
              response.status = 422
              {error: error.message, fields: error.fields}
            end
          end

          r.on String do |id|
            r.post "meeting" do
              briefing_command(
                r,
                workspace,
                :create_for_request,
                identifier: id,
                identifier_key: :request_id,
                success_status: 201,
                not_found: "Scheduling request not found."
              )
            end

            r.post "transitions" do
              begin
                body = parse_json_body(r)
                unless body.is_a?(Hash)
                  response.status = 400
                  next({error: "Request body must be a JSON object."})
                end

                actor = actor_or_error(r, workspace)
                next actor if actor.key?(:error)

                result = SchedulingRequestWorkflow.transition(
                  id: id,
                  attributes: body,
                  workspace: workspace,
                  actor: actor
                )
                unless result
                  response.status = 404
                  next({error: "Scheduling request not found."})
                end

                SchedulingRequests.fetch(id: id, workspace: workspace)
              rescue JSON::ParserError
                response.status = 400
                {error: "Request body must be valid JSON."}
              rescue SchedulingRequestWorkflow::ValidationError => error
                response.status = 422
                {error: error.message, fields: error.fields}
              rescue SchedulingRequestWorkflow::InvalidTransitionError => error
                response.status = 409
                {
                  error: error.message,
                  current_status: error.current_status,
                  requested_status: error.requested_status
                }
              rescue SchedulingRequestWorkflow::ConflictError => error
                response.status = 409
                conflict_payload(error)
              end
            end

            r.get true do
              request = SchedulingRequests.fetch(id: id, workspace: workspace)
              unless request
                response.status = 404
                next({error: "Scheduling request not found."})
              end
              request
            end

            r.patch true do
              begin
                body = parse_json_body(r)
                unless body.is_a?(Hash)
                  response.status = 400
                  next({error: "Request body must be a JSON object."})
                end

                actor = actor_or_error(r, workspace)
                next actor if actor.key?(:error)

                request = SchedulingRequests.update(
                  id: id,
                  attributes: body,
                  workspace: workspace,
                  actor: actor
                )
                unless request
                  response.status = 404
                  next({error: "Scheduling request not found."})
                end
                request
              rescue JSON::ParserError
                response.status = 400
                {error: "Request body must be valid JSON."}
              rescue SchedulingRequests::ValidationError => error
                response.status = 422
                {error: error.message, fields: error.fields}
              rescue Relationships::ValidationError => error
                response.status = 422
                {error: error.message, fields: error.fields}
              rescue SchedulingRequestWorkflow::ConflictError => error
                response.status = 409
                conflict_payload(error)
              end
            end
          end
        end
      end

      response.status = 404
      {error: "Not found"}
    end

    private

    def parse_json_body(request)
      raw_body = request.body.read
      raw_body.empty? ? {} : JSON.parse(raw_body)
    end

    def valid_email?(email)
      !email.empty? && email.match?(EMAIL_PATTERN)
    end

    def display_name_from(email)
      email.split("@", 2).first
        .split(/[._+-]+/)
        .map(&:capitalize)
        .join(" ")
    end

    def workspace_payload(include_audit:)
      workspace = current_workspace

      unless workspace
        response.status = 503
        return {error: "Foundation data has not been seeded."}
      end

      principal = Database.db[:principals]
        .join(:workspace_members, id: :workspace_member_id)
        .where(Sequel[:principals][:workspace_id] => workspace[:id])
        .select(
          Sequel[:principals][:id],
          Sequel[:principals][:title],
          Sequel[:principals][:status],
          Sequel[:workspace_members][:display_name],
          Sequel[:workspace_members][:email]
        )
        .first

      members = Database.db[:workspace_members]
        .where(workspace_id: workspace[:id])
        .order(:display_name)
        .all
        .map { |member| serialize_member(member) }

      payload = {
        workspace: {
          id: workspace[:id],
          slug: workspace[:slug],
          name: workspace[:name],
          timezone: workspace[:timezone],
          retention_days: workspace[:retention_days]
        },
        principal: principal && {
          id: principal[:id],
          display_name: principal[:display_name],
          email: principal[:email],
          title: principal[:title],
          status: principal[:status]
        },
        members: members
      }
      if include_audit
        payload[:audit_events] = Database.db[:audit_events]
          .where(workspace_id: workspace[:id])
          .reverse_order(:occurred_at, :id)
          .limit(8)
          .all
          .map { |event| serialize_audit_event(event) }
      end
      payload
    end

    def current_workspace
      Database.db[:workspaces].first
    end

    def active_principal(workspace)
      Database.db[:principals]
        .where(workspace_id: workspace[:id], status: "active")
        .first
    end

    def actor_or_error(request, workspace)
      email = request.env["HTTP_X_HOLOCRON_ACTOR_EMAIL"].to_s.strip.downcase
      unless valid_email?(email)
        response.status = 401
        return {error: "Provide an active workspace member in X-Holocron-Actor-Email."}
      end

      member = Database.db[:workspace_members]
        .where(
          workspace_id: workspace[:id],
          status: "active",
          Sequel.function(:lower, :email) => email
        )
        .first
      return member if member

      response.status = 403
      {error: "The development actor must be an active workspace member."}
    end

    def serialize_member(member)
      {
        id: member[:id],
        display_name: member[:display_name],
        email: member[:email],
        job_title: member[:job_title],
        role: member[:role],
        status: member[:status]
      }
    end

    def serialize_audit_event(event)
      {
        id: event[:id],
        event_type: event[:event_type],
        subject_type: event[:subject_type],
        subject_id: event[:subject_id],
        payload: JSON.parse(event[:payload]),
        correlation_id: event[:correlation_id],
        occurred_at: event[:occurred_at].iso8601
      }
    end

    def conflict_payload(error)
      {
        error: error.message,
        current_lock_version: error.current_lock_version,
        current_status: error.current_status
      }
    end

    def serialize_ask_result(result)
      {
        question: result.question,
        answer: result.answer,
        claims: result.claims,
        sources: result.sources,
        limitations: result.limitations
      }
    end

    def ask_failure_status(result)
      configuration_failure = result.failure_reason.to_s.match?(
        /not configured|unconfigured|Unsupported ask ai provider/i
      )
      configuration_failure ? 503 : 502
    end

    def relationship_command(request, workspace, method_name, id: nil, success_status: 201)
      body = parse_json_body(request)
      unless body.is_a?(Hash)
        response.status = 400
        return {error: "Request body must be a JSON object."}
      end

      actor = actor_or_error(request, workspace)
      return actor if actor.key?(:error)

      arguments = {attributes: body, workspace: workspace, actor: actor}
      arguments[:id] = id if id
      result = Relationships.public_send(method_name, **arguments)
      unless result
        response.status = 404
        return {error: "Person not found."}
      end

      response.status = success_status
      result
    rescue JSON::ParserError
      response.status = 400
      {error: "Request body must be valid JSON."}
    rescue Relationships::ValidationError => error
      response.status = 422
      {error: error.message, fields: error.fields}
    end

    def briefing_command(request, workspace, method_name, identifier:, identifier_key: :id, success_status: 200, not_found: "Briefing not found.")
      body = parse_json_body(request)
      unless body.is_a?(Hash)
        response.status = 400
        return {error: "Request body must be a JSON object."}
      end

      actor = actor_or_error(request, workspace)
      return actor if actor.key?(:error)

      result = Briefings.public_send(
        method_name,
        identifier_key => identifier,
        attributes: body,
        workspace: workspace,
        actor: actor
      )
      unless result
        response.status = 404
        return {error: not_found}
      end

      response.status = success_status
      result
    rescue JSON::ParserError
      response.status = 400
      {error: "Request body must be valid JSON."}
    rescue Briefings::ValidationError => error
      response.status = 422
      {error: error.message, fields: error.fields}
    rescue Briefings::ConflictError => error
      response.status = 409
      {
        error: error.message,
        current_lock_version: error.current_lock_version,
        current_status: error.current_status,
        current_version_number: error.current_version_number
      }
    rescue Briefings::StateError => error
      response.status = 409
      {error: error.message, current_status: error.current_status}
    rescue Briefings::GenerationError => error
      response.status = 502
      {
        error: error.message,
        provider: error.provider,
        model: error.model,
        validation_errors: error.validation_errors
      }
    end
  end
end
