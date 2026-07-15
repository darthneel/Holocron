# Holocron

Holocron is a learning project for principal-operations software and agentic
architecture. Step 6 adds the first narrow AI boundary: staff can paste request
email text, inspect a validated structured draft, edit it, and explicitly create
the scheduling request without allowing model output to write domain records.

## Current Architecture

- React and TypeScript frontend under `app/`
- Roda JSON API under `backend/`
- Sequel migrations and queries
- SQLite for dependency-free local development
- Fictional Cedar Grove Mayor's Office seed data

The frontend and API are separate processes. The frontend never reads the
database directly.

```text
Browser -> React UI -> Roda API -> Sequel -> SQLite
```

## Run Locally

Install frontend dependencies:

```bash
npm install
```

Install Ruby dependencies and initialize the database:

```bash
cd backend
bundle install
bundle exec rake db:setup
```

Start the API and frontend together:

```bash
npm run dev:all
```

They can also be started separately:

```bash
npm run dev:api
npm run dev
```

Open `http://localhost:3000`. The API runs on `http://localhost:9292`.

Request extraction uses the deterministic fake provider by default. To use a
real provider, export one of these configurations before starting the API:

```bash
# Recommended: Vercel AI Gateway
export AI_REQUEST_EXTRACTION_PROVIDER=vercel
export AI_REQUEST_EXTRACTION_MODEL=openai/gpt-5.6-luna
export AI_GATEWAY_API_KEY=...

# Direct OpenAI alternative
export AI_REQUEST_EXTRACTION_PROVIDER=openai
export AI_REQUEST_EXTRACTION_MODEL=gpt-5.6-luna
export OPENAI_API_KEY=...

# OpenRouter alternative
export AI_REQUEST_EXTRACTION_PROVIDER=openrouter
export AI_REQUEST_EXTRACTION_MODEL=openai/gpt-5.6-luna
export OPENROUTER_API_KEY=...
```

See `.env.example` for the non-secret defaults. The local server and live eval
runner load the ignored `.env.local` file automatically.

## Live Request Extraction Evals

The opt-in eval suite runs synthetic scheduling emails through the configured
real model, shared prompt and schema, and deterministic normalizer without
writing request or audit records:

```bash
RUN_LIVE_EVALS=1 backend/bin/eval-request-extraction
```

The command makes billed network requests and writes a detailed report under
`backend/tmp/eval-results/`. Use Minitest's name filter to rerun one case:

```bash
RUN_LIVE_EVALS=1 backend/bin/eval-request-extraction -n /conflicting_duration/
```

Cost estimates use the configured Luna rates by default. Set
`EVAL_INPUT_USD_PER_MILLION` and `EVAL_OUTPUT_USD_PER_MILLION` when evaluating a
different model.

## Deployment

This milestone remains local-only. The frontend depends on the separate Ruby
API and its SQLite database, which are not part of the current Sites deployment
target. Publishing only the frontend would produce a workspace that cannot load
or persist records. Deployment should follow a later backend-hosting decision.

## Fake Entry Flow

`POST /api/fake-session` validates email syntax and returns a temporary persona.
It does not create a session, set a cookie, or write to the database. A seeded
office email resolves to its workspace member; any other valid email receives
the `viewer` persona.

The default seeded email is `neelp22@gmail.com`.

## API

```text
GET  /health
POST /api/fake-session
GET  /api/foundation
POST /api/request-extractions
GET  /api/request-extractions/:id
GET  /api/scheduling-requests
POST /api/scheduling-requests
GET  /api/scheduling-requests/:id
PATCH /api/scheduling-requests/:id
POST /api/scheduling-requests/:id/transitions
POST /api/scheduling-requests/:id/meeting
GET  /api/relationships
POST /api/relationships/people
PATCH /api/relationships/people/:id
POST /api/relationships/organizations
POST /api/relationships/interactions
GET  /api/briefings
GET  /api/briefings/:id
POST /api/briefings/:id/versions
POST /api/briefings/:id/submit-review
POST /api/briefings/:id/reviews
```

`POST` and `PATCH` require the development-only
`X-Holocron-Actor-Email` header. It must identify an active workspace member;
the API uses it for request attribution and append-only audit events. Request
edits and transitions also require the current `lock_version`; stale writes
return `409 Conflict` without changing workflow history.

Relationship writes use the same actor header and write audit events in the
same database transaction. Request intake links people by exact email and
organizations by normalized name. A person can have one current organization;
conflicting intake data returns `422` instead of silently changing it. Names
alone never merge people.

Only scheduled requests can produce meetings and briefings. Briefing edits
append immutable versions; submission and review commands use `lock_version`
and synchronously record audit events. Approval and changes-requested decisions
belong to the exact version reviewed.

Request extraction is synchronous and provider-neutral. The router supports a
deterministic fake, the recommended Vercel AI Gateway, direct OpenAI, and optional
OpenRouter through one Responses API adapter. Calls use a versioned prompt,
strict JSON schema, low reasoning, and
at most one retry for transient failures. Successful, failed, and refused attempts
are retained and audited. A successful extraction remains a proposal until staff
review it and submit the normal scheduling-request form. Acceptance links the
extraction, request, relationship updates, workflow initialization, and audit
events in one transaction; an extraction can be accepted only once.

## Verification

```bash
cd backend && bin/test
npm run build
npm test
```

See [docs/architecture.md](docs/architecture.md) for request lifecycles and
[docs/data-model.md](docs/data-model.md) for the current ERD. The complete
feature-by-feature roadmap is in
[docs/implementation-plan.md](docs/implementation-plan.md).
