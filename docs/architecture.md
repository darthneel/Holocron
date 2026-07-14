# Holocron Architecture

## Boundaries

The frontend owns presentation and temporary fake-session state. The Ruby API
owns validation, workspace queries, serialization, and database access. Sequel
owns migrations and SQL construction.

```mermaid
flowchart LR
    Browser[React browser UI]
    Session[POST /api/fake-session]
    Foundation[GET /api/foundation]
    Roda[Roda routing and validation]
    Sequel[Sequel datasets]
    SQLite[(SQLite)]

    Browser --> Session
    Browser --> Foundation
    Session --> Roda
    Foundation --> Roda
    Roda --> Sequel
    Sequel --> SQLite
```

## Email Entry Lifecycle

1. The browser submits an email to `POST /api/fake-session`.
2. Roda validates its shape without authenticating it.
3. The API looks for a case-insensitive workspace-member match.
4. A known member receives their seeded name and role; an unknown valid email
   receives a temporary viewer persona.
5. The browser requests `GET /api/foundation` and renders the workspace.

No identity or session record is stored. This is deliberate: authentication is
outside the learning goal for Step 1.

## Framework Decision

Roda was selected over Sinatra because both are small Rack applications, while
Roda's routing tree keeps endpoint matching explicit as the API grows. Sequel is
maintained by the same author and keeps migrations and queries close to SQL.

## Local Database Decision

SQLite keeps the project runnable without a database service. UUID, enum,
case-insensitive email, and JSON values are represented as constrained text.
The logical PostgreSQL types remain documented in the ERD so a future migration
does not need to rediscover the intended model.

## Step 2 Scheduling Request Lifecycle

```mermaid
sequenceDiagram
    participant Browser
    participant API as Roda API
    participant Domain as SchedulingRequests
    participant DB as SQLite

    Browser->>API: POST /api/scheduling-requests + actor header
    API->>API: Parse JSON and resolve active actor
    API->>Domain: Validate and normalize intake payload
    Domain->>DB: Begin transaction
    Domain->>DB: Insert request, participants, and candidate windows
    Domain->>DB: Insert audit event
    Domain->>DB: Commit transaction
    Domain-->>API: Serialized request detail
    API-->>Browser: 201 Created
```

Reads are workspace-scoped. Writes require the development-only
`X-Holocron-Actor-Email` header, which resolves to an active workspace member.
The route owns HTTP parsing and error responses; `SchedulingRequests` owns the
domain validation, child-record replacement, and transaction boundary.

## Step 3 Workflow Transition Lifecycle

```mermaid
sequenceDiagram
    participant Browser
    participant API as Roda API
    participant Workflow as SchedulingRequestWorkflow
    participant DB as SQLite

    Browser->>API: POST transition + actor + expected lock version
    API->>Workflow: Resolve actor and pass command
    Workflow->>DB: Load request in workspace
    Workflow->>Workflow: Check version, transition, and reason
    Workflow->>DB: Conditional status and lock-version update
    Workflow->>DB: Insert immutable transition
    opt Approval or decline
        Workflow->>DB: Insert decision
    end
    Workflow->>DB: Insert audit event and commit
    Workflow-->>Browser: Updated detail and timeline
```

`scheduling_requests.status` is a read-optimized projection. It can change only
through `SchedulingRequestWorkflow`; the transition table is its immutable
explanation. `lock_version` increments on request edits and transitions. A
conditional update affecting zero rows produces `409 Conflict`, and the
transaction writes no transition, decision, or audit event.

## Step 4 Relationship Context Lifecycle

```mermaid
sequenceDiagram
    participant Browser
    participant API as Roda API
    participant Requests as SchedulingRequests
    participant Relations as Relationships
    participant DB as SQLite

    Browser->>API: Create or edit scheduling request
    API->>Requests: Validated request command and actor
    Requests->>DB: Begin transaction and persist intake
    Requests->>Relations: Synchronize request context
    Relations->>DB: Match person by exact email
    Relations->>DB: Match organization by normalized name
    Relations->>DB: Assign organization when the person has none
    Relations->>DB: Link request to people
    Relations->>DB: Insert or update sourced intake interaction
    Relations->>DB: Append relationship audit events
    Requests->>DB: Append request audit event and commit
    Requests-->>Browser: Request with relationship context
```

Names alone are not person identifiers. A person is reused automatically only
when an exact case-insensitive email matches within the workspace. Name-only
requesters remain separate unless staff explicitly reconcile them later.
Organizations use a normalized name because their names are less ambiguous in
this initial domain boundary.

A person has zero or one current organization and an optional job title. Intake
may fill an empty organization, but a different organization on an exact-email
match is a validation conflict: the entire request transaction rolls back and
staff must resolve the person explicitly. Interactions retain an author, source
type, and occurrence time.

## Step 5 Manual Briefing Lifecycle

```mermaid
sequenceDiagram
    participant Browser
    participant API as Roda API
    participant Briefings as Briefings service
    participant Relations as Relationship context
    participant DB as SQLite

    Browser->>API: Create meeting for scheduled request
    API->>Briefings: Actor, request, confirmed time, and location
    Briefings->>DB: Begin transaction and verify request is scheduled
    Briefings->>Relations: Load linked people, organizations, and interactions
    Briefings->>DB: Insert meeting and briefing projection
    Briefings->>DB: Insert version 1, sections, and source snapshots
    Briefings->>DB: Insert meeting and briefing audit events and commit
    Briefings-->>Browser: Draft briefing detail
    Browser->>API: Save edited sections and expected lock version
    API->>Briefings: Create version command
    Briefings->>DB: Conditional lock update and append immutable version
    Briefings-->>Browser: New current version
    Browser->>API: Submit current version for review
    Briefings->>DB: Mark projection and current version in review
    Browser->>API: Approve or request changes
    Briefings->>DB: Insert decision for exact version and audit event
    Briefings-->>Browser: Reviewed briefing with recoverable history
```

The `briefings` row is the current read projection. Its status, current version
number, and `lock_version` change through domain commands. Section content is
never updated in place: an edit appends a `briefing_versions` row with a complete
new section set. Review status may change on the current version, but its content
and source snapshots remain fixed. Creating a revision after approval moves the
briefing projection back to `draft` while the earlier approved version and
review metadata remain intact. Review fields live directly on the immutable
version, and each section embeds its validated source snapshots as JSON.

Meeting and briefing creation, version writes, review decisions, source
snapshots, and audit events are synchronous transactions. Invalid sources,
invalid workflow states, and stale lock versions roll back every write.

## Step 6 Request Extraction Lifecycle

```mermaid
sequenceDiagram
    participant Staff as Staff browser
    participant API as Roda API
    participant Extract as RequestExtractions
    participant Router as ModelRouter
    participant Model as Fake or hosted Responses gateway
    participant Requests as SchedulingRequests
    participant DB as SQLite

    Staff->>API: POST pasted email + development actor
    API->>Extract: Extract untrusted input
    Extract->>Router: Versioned prompt + strict schema
    Router->>Model: Synchronous structured-output call
    Model-->>Router: Proposal, refusal, or failure
    Router-->>Extract: Normalized provider result
    Extract->>Extract: Deterministic validation and warnings
    Extract->>DB: Store attempt and synchronous audit
    Extract-->>Staff: Reviewable draft and provenance
    Staff->>API: POST edited request + extraction ID
    API->>Requests: Normal request creation command
    Requests->>DB: Begin acceptance transaction
    Requests->>DB: Lock unaccepted extraction
    Requests->>DB: Insert request, context, workflow, and audits
    Requests->>DB: Link extraction exactly once and commit
    Requests-->>Staff: Created scheduling request
```

The pasted text is data, not an instruction channel. The prompt tells the model
to use null instead of guessing, and deterministic code validates structure,
email, dates, times, limits, and participant roles. Missing facts become review
warnings. Malformed output, refusals, provider errors, and exhausted retries are
stored as extraction attempts but never enter scheduling or relationship tables.

`ModelRouter` selects one provider for the request-extraction task. Local and test
runs default to the deterministic fake provider. The recommended hosted path is
Vercel AI Gateway; direct OpenAI and OpenRouter remain alternatives. All three
use the same Responses API adapter. There is no cross-provider fallback: changing
models after a failure would make behavior and evaluation harder to explain at
this stage.

Human acceptance reuses `SchedulingRequests.create`, the sole request-write path.
The service ignores client changes to source provenance and forces `email` plus
the extraction's retained original text. It atomically links the extraction,
creates canonical relationship context, initializes workflow history, and writes
synchronous audit events. A unique link and conditional update prevent replay.
