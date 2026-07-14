# Holocron Implementation Plan

## Purpose

Holocron is a domain-informed principal-operations prototype with two goals:

1. Understand the users, workflows, data, and product decisions behind software
   for executive and government leadership offices.
2. Learn agentic-system architecture by building context, orchestration, tools,
   approval controls, observability, and evaluation one feature at a time.

This is not intended to reproduce Chief AI's private product, branding, user
interface, or internal architecture. Public product descriptions inform the
domain, while every implementation decision in this repository is our own.

## Working Method

Each step is a complete vertical slice. It should include the database change,
backend behavior, frontend workflow, tests, documentation, and a code walkthrough.

Do not begin the next step until the current step can be traced from browser
interaction to database state and explained without relying on hidden framework
behavior.

After every step, produce:

- A diagram tracing one representative request through the system.
- A file-by-file walkthrough of the new code.
- An architecture decision record for the most important tradeoff.
- A list of failure cases and the tests covering them.
- A focused source-control commit for that step.

## Technical Direction

### Frontend

- React and TypeScript
- Vinext and Vite runtime
- Lucide icons
- Operational, compact interface designed for repeated office use

### Backend

- Ruby
- Roda for HTTP routing
- Sequel for migrations and database access
- Rack with WEBrick for local development

### Data

- SQLite during early local development
- Logical schema documented with PostgreSQL-oriented types
- UUID identifiers
- Explicit foreign keys, constraints, and append-only audit history

### Agent Architecture

- Explicit workflow orchestration before adopting an agent framework
- Deterministic application code for permissions, state transitions, and writes
- Structured model outputs validated before entering the domain layer
- Human approval before consequential writes or external actions
- Inspectable context, tool calls, retries, and outcomes

## Step 1: Project Foundation

**Status: Complete**

Establish the frontend, Ruby API, local database, test harness, fictional office,
and architectural documentation. Authentication is intentionally excluded.

Implemented:

- Email-only fake entry flow with no password, cookie, or persistent session.
- Cedar Grove Mayor's Office workspace.
- One principal, Elena Park, represented by a principal workspace member and a
  one-to-one principal domain profile.
- Workspace members for the principal's office, including Neel as workspace owner.
- `workspaces`, `workspace_members`, `principals`, and `audit_events` tables.
- Append-only audit history for meaningful foundation events.
- Foundation dashboard showing the principal, members, timezone, retention, and
  audit activity.
- Backend request tests and frontend rendering/build checks.

Architectural lesson:

Understand the complete path from browser state to HTTP request, backend route,
database query, JSON response, and rendered interface before adding domain
complexity or AI.

Completion gate:

- Both services start with `npm run dev:all`.
- A valid email opens the seeded workspace.
- A seeded email resolves to its workspace-member persona.
- Database constraints represent one principal per workspace.
- Backend tests, frontend lint, and frontend build pass.

## Step 2: Scheduling Request Intake

**Status: Complete**

Build request creation, inbox, request detail, editing, and field validation.

Implemented data:

- `scheduling_requests`
- `request_participants`
- `request_candidate_windows`
- Requester name, email, and organization
- Meeting purpose and requested duration
- Candidate dates or availability notes
- Source channel and original request text
- Assigned scheduler
- Created and updated timestamps

The workflow is deterministic and contains no AI. Staff can create, inspect,
and edit a complete scheduling request manually. A development-only
`X-Holocron-Actor-Email` header resolves each write to an active workspace
member; request and audit-event writes occur together in one transaction.

Architectural lesson:

Separate transport schemas, domain validation, persistence, and frontend form
state. Learn where business rules belong and which malformed inputs must be
rejected at each boundary.

Completion gate met:

- Requests can be created, listed, viewed, and edited from the workspace inbox.
- Invalid requests return field-specific validation errors without partial writes.
- Every request belongs to the workspace principal.
- Request creation and edits synchronously create audit events.
- API request tests cover creation, listing, detail, editing, validation, and actor-header enforcement.

## Step 3: Review and Decision Workflow

**Status: Complete**

Add an explicit scheduling-request state machine.

Implemented states:

- `submitted`
- `needs_information`
- `under_review`
- `approved`
- `declined`
- `scheduled`

Implemented data:

- Current status on `scheduling_requests`
- `request_state_transitions`
- `request_decisions`
- Actor, reason, timestamp, and optional notes for every transition
- Optimistic `lock_version` on each request

Status changes are accepted only through the transition command. The service
checks the expected lock version, validates the transition and reason, updates
the status projection, and appends transition, decision, and audit records in
one transaction. Existing requests were backfilled as `submitted` with a
system-authored initial transition.

Architectural lesson:

Model deterministic workflows and invariants explicitly. A request cannot move
between arbitrary states, and history must not be reconstructed from the current
row alone.

Completion gate met:

- Valid transitions succeed and create immutable history.
- Invalid transitions fail without partially updating data.
- Decisions identify the responsible workspace member.
- The request screen presents the current state and complete timeline.
- Stale edits and transitions return `409 Conflict` without partial writes.
- The inbox shows current status and detail views expose only valid actions.

## Step 4: Relationship Management

**Status: Complete**

Add the people and organizations surrounding the principal.

Proposed data:

- `people`
- `organizations`
- `interactions`
- Links between scheduling requests, people, and prior meetings

Relationship history should appear on scheduling requests so staff can understand
who is asking, how they are connected, and what happened previously.

Implemented:

- Canonical `people` and `organizations` scoped to a workspace
- One optional current organization and job title directly on each person
- Sourced, authored `interactions` for calls, emails, meetings, notes, and events
- Explicit request links for people, with organization context derived from them
- Exact-email person resolution and normalized-name organization resolution
- Conservative name-only handling that never merges people automatically
- Transactional rejection when intake conflicts with a person's current organization
- Automatic relationship linking during request create and edit transactions
- Relationship management views and prior-history context on request details
- Synchronous audit events for relationship writes

Scope decision:

- `organizations` remains a separate canonical table.
- `people.organization_id` and `people.job_title` represent the person's one
  optional current organization and role.
- Affiliation history and explicit scheduling-request-to-organization links are
  intentionally excluded from this exercise.
- Interactions are person-centered and therefore require a person. Organization
  context is reached through that person.
- Migration 5 collapsed existing affiliation data onto people while preserving
  existing request links and interaction history.

Architectural lesson:

Build the first useful portion of the context graph through ordinary relational
domain tables. Learn entity resolution and provenance while keeping organization
membership deliberately simple for this exercise.

Completion gate:

- People and organizations can be created and linked.
- One person can have zero or one current organization.
- Interactions identify their source and author.
- Request details surface relevant relationship history.
- Duplicate-person and conflicting-organization cases are tested.

Completion gate met:

- People and organizations can be created and directly linked.
- A person's current organization and job title can be assigned or cleared.
- Interactions retain source, author, timestamp, and optional request linkage.
- Request details show linked entities and prior interactions.
- Tests cover exact-email reuse, name-only non-merging, and organization conflicts.

## Step 5: Manual Briefing Workflow

**Status: Complete**

Build briefing assembly without AI before automating it.

Proposed data:

- `meetings`
- `briefings`
- `briefing_versions`
- `briefing_sections`
- Source snapshots stored as JSON on each immutable briefing section
- Optional review decision, notes, reviewer, and timestamp stored on the exact
  briefing version
- Briefing status, current version number, and optimistic `lock_version`

Staff should be able to assemble a briefing from relationship records, scheduling
details, office notes, and priorities. Every important statement should retain a
source link.

Step 4 implications:

- Briefing assembly follows `scheduling request -> linked people -> current
  organization -> person interactions`.
- A section's source snapshot array may reference scheduling requests, people,
  organizations, and interactions. Organization sources are selected from the
  organization on a linked person rather than from a request-organization join
  table.
- No temporal affiliation query is required when assembling relationship
  context. The person's current organization and job title are used.
- Organization-wide history without a named person is out of scope. Every
  interaction used in a briefing has a person as its subject.
- A briefing version stores its assembled section content as a snapshot. Later
  edits to a person or organization do not rewrite an earlier version or an
  approved briefing.
- Source references remain inspectable even though the rendered briefing content
  is versioned independently.

Implemented:

- One meeting per scheduled request and one briefing per meeting
- Confirmed meeting title, start, end, and optional location
- Deterministic initial sections assembled without AI
- Complete immutable section snapshots for every numbered briefing version
- Source validation against workspace scheduling requests, people,
  organizations, and interactions
- Copied source labels and excerpts stored with their section as JSON so they
  remain readable with old versions
- Explicit `draft`, `in_review`, `approved`, and `changes_requested` states
- Review metadata stored directly on one exact briefing version and bound to a
  workspace member
- Optimistic concurrency for version, submission, and review commands
- Synchronous audit events for meeting creation, briefing creation, versions,
  submissions, approvals, and requested changes
- Briefing queue, source-backed editor, version browser, and review controls

Architectural lesson:

Understand the human workflow and document lifecycle before introducing generated
content. Establish versioning, approval, and provenance as domain behavior.

Completion gate:

- A scheduled request can produce a meeting and briefing.
- Briefings can be edited, versioned, reviewed, and approved.
- Source records remain inspectable.
- Relationship context can be assembled through linked people without an
  affiliation-history dependency.
- Earlier approved versions remain recoverable.

Completion gate met:

- Scheduled requests create a meeting, briefing, deterministic first version,
  source snapshots, and audit events in one transaction.
- Editing appends a complete new version and never mutates earlier section text.
- Staff can browse versions, submit the current draft, approve it, or request
  changes with notes.
- Source labels and excerpts remain inspectable on every saved version.
- Approved versions and their review metadata survive later draft revisions.
- Tests cover state restrictions, actor enforcement, source validation, stale
  writers, review notes, rollback behavior, and immutable approved history.

## Step 6: First AI Capability - Request Extraction

**Status: Complete**

Accept pasted email text and extract structured scheduling-request fields.

Implemented:

- Task-based provider-neutral model router
- Deterministic fake provider for local development and tests
- Recommended Vercel AI Gateway plus direct OpenAI and optional OpenRouter
  Responses API providers
- `gpt-5.6-luna` default real model with low reasoning effort
- Versioned extraction prompt that treats pasted text as untrusted data
- Strict structured-output schema with nullable unknown facts
- Deterministic validation and normalization before proposal persistence
- One retry for transient failures, with explicit refusal and failure records
- Durable provenance, token counts, timing, attempts, warnings, and audits
- Paste, extract, review, edit, and accept workflow in the request workbench
- Atomic one-time acceptance through the existing scheduling-request service

Architectural lesson:

Introduce probabilistic output at one narrow boundary. The model proposes
structured data; deterministic code validates it and a human accepts or edits it.

Completion gate:

- Extraction works through both the real and fake providers.
- Invalid or incomplete model output cannot enter domain tables.
- The original text and extraction provenance are retained.
- Tests cover complete, ambiguous, malformed, and adversarial requests.

Completion gate met:

- The fake provider runs end to end and the real Responses adapter is covered
  with transport-level request and response tests.
- Extraction never creates scheduling, relationship, or workflow records.
- Only a reviewed normal intake command can accept an extraction, and replay or
  cross-workspace acceptance rolls back.
- Original input, provider, model, prompt version, attempts, outcomes, and audit
  events remain inspectable.
- Tests cover complete, incomplete, malformed, refused, transient, replayed, and
  prompt-injection-shaped inputs.

## Step 7: Grounded Briefing Generation

**Status: Pending**

Generate a briefing draft from permitted workspace records.

Implement:

- Context assembler for the selected meeting
- Retrieval over people, organizations, interactions, priorities, and sources
- Prompt construction with explicit context boundaries
- Source citations for material generated claims
- Unsupported-claim detection
- Human editing and approval

Architectural lesson:

Learn retrieval-augmented generation, context selection, provenance, context-window
management, and the difference between retrieving similar text and traversing
meaningful domain relationships.

Completion gate:

- Every material briefing claim links to one or more source records.
- Records outside the current workspace never enter model context.
- Missing context produces a visible limitation rather than an invented claim.
- Evaluation fixtures measure faithfulness and citation correctness.

## Step 8: Durable Agent Execution

**Status: Pending**

Move AI work into durable background execution.

Proposed data:

- `agent_runs`
- `model_calls`
- `context_items`
- `tool_calls`
- `agent_run_events`

Implement explicit states such as queued, running, waiting for approval, succeeded,
failed, cancelled, and exhausted. Add idempotency keys, retries, timeouts, and
cancellation.

Architectural lesson:

An agent is a durable workflow with observable state, not merely an LLM request.
Learn how execution resumes safely and how repeated delivery avoids duplicate
side effects.

Completion gate:

- Runs survive process interruption and can resume or retry.
- Duplicate submissions do not duplicate work.
- Inputs, context, model calls, outputs, duration, and status are inspectable.
- Failures surface actionable information without exposing sensitive context.

## Step 9: Follow-Up Agent and Tools

**Status: Pending**

After a meeting, suggest tasks and relationship updates.

Initial tools:

- `create_task`
- `record_interaction`
- `suggest_relationship_update`

The agent may prepare tool calls, but a workspace member must approve them before
execution. Tool handlers must validate arguments independently from the model.

Architectural lesson:

Learn tool contracts, side effects, authorization, approval gates, replay
protection, and the distinction between proposing an action and performing it.

Completion gate:

- Suggested actions are reviewable and editable.
- Rejected actions make no domain changes.
- Approved actions execute once and create audit records.
- Tool misuse, malformed arguments, and repeated approval are tested.

## Step 10: Priority Alignment

**Status: Pending**

Define strategic priorities and measure how the principal's scheduled time aligns
with them.

Proposed data:

- `priorities`
- Priority periods and status
- Meeting-to-priority associations
- Time-allocation snapshots

Calculate allocation deterministically. AI may explain anomalies or suggest
questions, but it must not invent the underlying metrics.

Architectural lesson:

Separate trusted computation from generated interpretation. Models are useful for
explanation and synthesis, while arithmetic and policy rules remain ordinary code.

Completion gate:

- The system calculates allocation from meeting durations and associations.
- Users can inspect the meetings behind every metric.
- Generated explanations cite the computed values and relevant records.
- Edge cases around overlapping meetings and unallocated time are tested.

## Step 11: Evaluation, Observability, and Hardening

**Status: Pending**

Create a system-level quality and safety layer.

Evaluation areas:

- Request-extraction accuracy
- Briefing faithfulness
- Citation correctness
- Missing or conflicting context
- Cross-workspace data leakage
- Invalid tool arguments
- Duplicate side effects
- Human edit and acceptance rates
- Latency, token usage, and model cost

Add trace inspection, prompt and model versioning, evaluation datasets, regression
tests, and a threat model. Document data-retention and deletion behavior for
source records, generated content, and agent traces.

Architectural lesson:

Evaluate the full compound system rather than grading isolated prompts. Reliability
depends on retrieval, policies, tool handlers, persistence, human review, and model
behavior together.

Completion gate:

- A repeatable evaluation command produces stable metrics.
- Known failure cases are represented in fixtures.
- Prompt or model changes can be compared against a baseline.
- Trace data is useful for debugging without becoming an uncontrolled copy of
  sensitive workspace information.

## Product Questions to Carry Forward

These should be revisited as the implementation reveals more of the domain:

- Which scheduling decisions require judgment rather than automation?
- What context is most valuable at the moment a request is reviewed?
- Which facts belong to people, organizations, interactions, or decisions?
- How should conflicting staff notes be represented and resolved?
- What information is too sensitive to place in model context?
- What constitutes a useful citation for a generated briefing claim?
- Which actions may be automated, and which always require approval?
- How should staff corrections improve future outputs without silently rewriting
  historical records?
- What metrics demonstrate that the system makes an office more strategic, not
  merely faster?
- At what point would a graph projection or graph database materially improve on
  relational queries?
