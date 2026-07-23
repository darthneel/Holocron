# Step 7 Data Model

The project foundation models one leadership office per workspace. Each workspace
has exactly one principal, represented both as a workspace member and as a
principal domain profile. Scheduling requests are owned by the workspace,
directed to that principal, and retain their structured candidate windows. Each
request is either a `proposed` or `scheduled` meeting, with ordinary audit events
preserving creation and scheduling provenance. Canonical people and organizations
surround those requests. Each person may point to one current organization,
explicit person links preserve each request's context, and interactions retain
source and authorship. Scheduling a proposed request creates one meeting and
briefing in the same transaction. Briefing content is stored in immutable numbered
versions with ordered sections, source snapshots, and per-version review
decisions. Request extraction attempts sit outside the domain-write path until a
staff member accepts one into at most one scheduling request. Grounded generation
reuses the briefing-version model and introduces no mutable generated-content
table: an accepted model response is another immutable draft version.

```mermaid
erDiagram
    WORKSPACES {
        uuid id PK
        citext slug UK
        text name
        text timezone
        integer retention_days
        timestamptz created_at
        timestamptz updated_at
    }

    WORKSPACE_MEMBERS {
        uuid id PK
        uuid workspace_id FK
        text display_name
        citext email "nullable"
        text job_title "nullable"
        member_role role
        member_status status
        timestamptz created_at
        timestamptz updated_at
    }

    PRINCIPALS {
        uuid id PK
        uuid workspace_id FK,UK
        uuid workspace_member_id FK,UK
        text title
        principal_status status
        timestamptz created_at
        timestamptz updated_at
    }

    AUDIT_EVENTS {
        uuid id PK
        uuid workspace_id FK
        uuid actor_workspace_member_id FK "nullable"
        text event_type
        text subject_type
        uuid subject_id "nullable"
        jsonb payload
        uuid correlation_id
        timestamptz occurred_at
    }

    SCHEDULING_REQUESTS {
        uuid id PK
        uuid workspace_id FK
        uuid principal_id FK
        uuid assigned_scheduler_member_id FK
        uuid created_by_workspace_member_id FK
        text requester_name
        citext requester_email "nullable"
        text requester_organization "nullable"
        text purpose
        integer requested_duration_minutes
        text preferred_location "nullable"
        text availability_notes "nullable"
        source_channel source_channel
        text original_request_text "nullable"
        jsonb briefing_context
        request_status status
        integer lock_version
        timestamptz created_at
        timestamptz updated_at
    }

    REQUEST_EXTRACTIONS {
        uuid id PK
        uuid workspace_id FK
        uuid requested_by_workspace_member_id FK
        uuid scheduling_request_id FK,UK "nullable"
        extraction_status status
        text provider
        text model
        text prompt_version
        text input_text
        jsonb output "nullable"
        jsonb validation_errors
        jsonb warnings
        integer attempt_count
        text failure_reason "nullable"
        text provider_request_id "nullable"
        integer input_tokens "nullable"
        integer output_tokens "nullable"
        integer duration_ms "nullable"
        timestamptz created_at
        timestamptz completed_at
        timestamptz accepted_at "nullable"
    }

    REQUEST_PARTICIPANTS {
        uuid id PK
        uuid scheduling_request_id FK
        text name
        citext email "nullable"
        text organization "nullable"
        participant_role role
        timestamptz created_at
        timestamptz updated_at
    }

    REQUEST_CANDIDATE_WINDOWS {
        uuid id PK
        uuid scheduling_request_id FK
        date candidate_date
        timestamptz starts_at "nullable"
        timestamptz ends_at "nullable"
        text notes "nullable"
        integer position
        timestamptz created_at
        timestamptz updated_at
    }

    REQUEST_STATE_TRANSITIONS {
        uuid id PK
        uuid scheduling_request_id FK
        uuid actor_workspace_member_id FK "nullable for system"
        request_status from_status "nullable for initial state"
        request_status to_status
        text reason_code
        text notes "nullable"
        uuid correlation_id
        timestamptz occurred_at
    }

    REQUEST_DECISIONS {
        uuid id PK
        uuid scheduling_request_id FK
        uuid request_state_transition_id FK,UK
        uuid decided_by_workspace_member_id FK
        decision_type decision
        text reason_code
        text notes "nullable"
        timestamptz decided_at
    }

    PEOPLE {
        uuid id PK
        uuid workspace_id FK
        uuid created_by_workspace_member_id FK
        uuid organization_id FK "nullable"
        text display_name
        citext primary_email "nullable, unique per workspace"
        text primary_phone "nullable"
        text job_title "nullable"
        text notes "nullable"
        timestamptz created_at
        timestamptz updated_at
    }

    ORGANIZATIONS {
        uuid id PK
        uuid workspace_id FK
        uuid created_by_workspace_member_id FK
        text name
        text normalized_name "unique per workspace"
        text website_url "nullable"
        text notes "nullable"
        timestamptz created_at
        timestamptz updated_at
    }

    INTERACTIONS {
        uuid id PK
        uuid workspace_id FK
        uuid person_id FK
        uuid scheduling_request_id FK "nullable"
        uuid authored_by_workspace_member_id FK
        interaction_type interaction_type
        text summary
        text source_type
        uuid source_id "nullable"
        timestamptz occurred_at
        timestamptz created_at
        timestamptz updated_at
    }

    SEMANTIC_DOCUMENTS {
        uuid id PK
        uuid workspace_id FK
        text source_type
        uuid source_id "interaction ID"
        text unit_type "overview or burst"
        text unit_key
        integer position "nullable"
        text content
        text metadata_json "serialized JSON"
        text content_hash
        text embedding_model
        vector embedding
        tsvector search_vector
        timestamptz created_at
        timestamptz updated_at
    }

    SCHEDULING_REQUEST_PEOPLE {
        uuid scheduling_request_id PK,FK
        uuid person_id PK,FK
        text role PK
        text source_type
        timestamptz linked_at
    }

    MEETINGS {
        uuid id PK
        uuid workspace_id FK
        uuid scheduling_request_id FK,UK
        uuid created_by_workspace_member_id FK
        text title
        timestamptz starts_at
        timestamptz ends_at
        text location "nullable"
        timestamptz created_at
        timestamptz updated_at
    }

    BRIEFINGS {
        uuid id PK
        uuid workspace_id FK
        uuid meeting_id FK,UK
        uuid created_by_workspace_member_id FK
        briefing_status status
        integer current_version_number
        integer lock_version
        timestamptz created_at
        timestamptz updated_at
    }

    BRIEFING_VERSIONS {
        uuid id PK
        uuid briefing_id FK
        uuid created_by_workspace_member_id FK
        integer version_number
        briefing_status status
        text change_summary "nullable"
        review_decision review_decision "nullable"
        text review_notes "nullable"
        uuid reviewed_by_workspace_member_id FK "nullable"
        timestamptz reviewed_at "nullable"
        text retrieval_strategy "nullable"
        text retrieval_json "serialized JSON, nullable"
        text generation_provider "nullable"
        text generation_model "nullable"
        integer input_tokens "nullable"
        integer output_tokens "nullable"
        timestamptz created_at
    }

    BRIEFING_SECTIONS {
        uuid id PK
        uuid briefing_version_id FK
        section_type section_type
        text title
        text body
        integer position
        jsonb sources
        timestamptz created_at
    }

    WORKSPACES ||--o{ WORKSPACE_MEMBERS : contains
    WORKSPACES ||--|| PRINCIPALS : manages
    WORKSPACE_MEMBERS ||--o| PRINCIPALS : has_profile
    WORKSPACES ||--o{ AUDIT_EVENTS : records
    WORKSPACE_MEMBERS o|--o{ AUDIT_EVENTS : performs
    WORKSPACES ||--o{ SCHEDULING_REQUESTS : owns
    PRINCIPALS ||--o{ SCHEDULING_REQUESTS : receives
    WORKSPACE_MEMBERS ||--o{ SCHEDULING_REQUESTS : assigned
    WORKSPACE_MEMBERS ||--o{ SCHEDULING_REQUESTS : creates
    WORKSPACES ||--o{ REQUEST_EXTRACTIONS : owns
    WORKSPACE_MEMBERS ||--o{ REQUEST_EXTRACTIONS : requests
    REQUEST_EXTRACTIONS o|--o| SCHEDULING_REQUESTS : may_create
    SCHEDULING_REQUESTS ||--o{ REQUEST_PARTICIPANTS : includes
    SCHEDULING_REQUESTS ||--o{ REQUEST_CANDIDATE_WINDOWS : offers
    SCHEDULING_REQUESTS ||--o{ REQUEST_STATE_TRANSITIONS : has_history
    REQUEST_STATE_TRANSITIONS ||--o| REQUEST_DECISIONS : may_create
    WORKSPACE_MEMBERS o|--o{ REQUEST_STATE_TRANSITIONS : performs
    WORKSPACE_MEMBERS ||--o{ REQUEST_DECISIONS : decides
    WORKSPACES ||--o{ PEOPLE : owns
    WORKSPACES ||--o{ ORGANIZATIONS : owns
    ORGANIZATIONS o|--o{ PEOPLE : groups
    PEOPLE ||--o{ INTERACTIONS : concerns
    INTERACTIONS ||--o{ SEMANTIC_DOCUMENTS : indexed_as
    WORKSPACES ||--o{ SEMANTIC_DOCUMENTS : scopes
    WORKSPACE_MEMBERS ||--o{ INTERACTIONS : authors
    SCHEDULING_REQUESTS o|--o{ INTERACTIONS : sources
    SCHEDULING_REQUESTS ||--o{ SCHEDULING_REQUEST_PEOPLE : links
    PEOPLE ||--o{ SCHEDULING_REQUEST_PEOPLE : appears_in
    WORKSPACES ||--o{ MEETINGS : owns
    SCHEDULING_REQUESTS ||--o| MEETINGS : produces
    WORKSPACE_MEMBERS ||--o{ MEETINGS : creates
    WORKSPACES ||--o{ BRIEFINGS : owns
    MEETINGS ||--|| BRIEFINGS : prepares
    WORKSPACE_MEMBERS ||--o{ BRIEFINGS : creates
    BRIEFINGS ||--o{ BRIEFING_VERSIONS : preserves
    WORKSPACE_MEMBERS ||--o{ BRIEFING_VERSIONS : authors
    WORKSPACE_MEMBERS o|--o{ BRIEFING_VERSIONS : reviews
    BRIEFING_VERSIONS ||--o{ BRIEFING_SECTIONS : contains
```

PostgreSQL stores case-insensitive slugs and emails as `citext`. During the
initial engine migration, UUIDs, enums, and JSON payloads remain application-
validated text even where this logical model shows their intended native
PostgreSQL types. Each briefing section stores an ordered JSON array of validated
source snapshots. Every snapshot contains a source type and ID plus the copied
label and excerpt, so the version remains understandable if the live record
later changes. A version's optional review decision, notes, reviewer, and
timestamp live on the version itself because only one decision is allowed for
each immutable version.

Step 7 expands the permitted source snapshot types to include `meeting` alongside
`scheduling_request`, `person`, `organization`, and `interaction`. Generated
section citations are resolved from temporary `SRC-nnn` manifest handles back to
these snapshots before persistence. Provider, model, prompt/context versions,
usage, retrieval counts, and success or failure are stored in synchronous audit
payloads. Durable model-call records remain a Step 8 concern.

`request_extractions.output` contains the deterministically validated proposal
when extraction succeeds and may retain malformed output for diagnosis when it
fails. Validation errors and warnings remain separate so incomplete but valid
proposals can be reviewed. `scheduling_request_id` and `accepted_at` are both null
until acceptance, then both are set in the scheduling-request transaction. The
unique request link ensures one extraction cannot create multiple requests.
`scheduling_requests.preferred_location` keeps the reviewed meeting location separate
from availability and candidate-window context. `scheduling_requests.briefing_context`
preserves the reviewed v2 intake structure:
agenda items and their evidence excerpts, explicit asks and decisions, owners and
decision-makers, deadlines, readiness standards, dependencies, constraints,
promised deliverables, and unresolved questions. It is stored as application-
validated JSON so existing requests can default to an empty context while the
contract evolves without flattening decision detail back into `purpose`.

Semantic documents are a derived, replaceable index rather than authoritative
domain records. Every interaction has one `overview` unit. Long interactions may
also have selected `burst` units containing independently retrievable decisions,
commitments, concerns, or requests. The composite source/unit key permits multiple
index rows per interaction. Retrieval ranks documents, then collapses them by
`interactions.id` before assigning briefing source references; citations therefore
continue to identify the authoritative interaction even when a child burst supplied
the matching excerpt.
