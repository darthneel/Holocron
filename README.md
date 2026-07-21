# Holocron

## Current Architecture

- React and TypeScript frontend under `app/`
- Roda JSON API under `backend/`
- Sequel migrations and queries
- PostgreSQL for development, tests, and deployment
- Fictional Cedar Grove Mayor's Office seed data

The frontend and API are separate processes. The frontend never reads the
database directly.

```text
Browser -> React UI -> Roda API -> Sequel -> PostgreSQL
```

## Run Locally

Install frontend dependencies:

```bash
npm install
```

Add development and test PostgreSQL URLs to the ignored `.env.local` file:

```bash
DATABASE_URL=postgres://USER:PASSWORD@localhost:5432/holocron_development
TEST_DATABASE_URL=postgres://USER:PASSWORD@localhost:5432/holocron_test
```

Install Ruby dependencies, create both databases, and initialize the development
database:

```bash
cd backend
bundle install
set -a
. ../.env.local
set +a
bundle exec rake db:setup
```

`backend/bin/test` creates the configured `_test` database when needed and
resets only its `public` schema before running the suite.

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

The browser calls the API directly; there is no frontend proxy. Locally, API
CORS accepts localhost and 127.0.0.1 origins on any port when no allowlist is
configured. In production, configure an explicit comma-separated allowlist:

```bash
FRONTEND_ORIGINS=https://holocron.example.com
NEXT_PUBLIC_API_URL=https://api.holocron.example.com
```

The Rack API runs on Puma. `PUMA_MIN_THREADS`, `PUMA_MAX_THREADS`, and
`WEB_CONCURRENCY` can be adjusted for the Render service; the defaults are
`1`, `5`, and `0` respectively.

Request extraction and briefing generation use deterministic fake providers by
default. To use a real provider, export the configuration for each task before
starting the API:

```bash
# Recommended: Vercel AI Gateway
export AI_REQUEST_EXTRACTION_PROVIDER=vercel
export AI_REQUEST_EXTRACTION_MODEL=openai/gpt-5.6-luna
export AI_BRIEFING_GENERATION_PROVIDER=vercel
export AI_BRIEFING_GENERATION_MODEL=openai/gpt-5.6-terra
export AI_EMBEDDING_PROVIDER=vercel
export AI_EMBEDDING_MODEL=openai/text-embedding-3-small
export AI_GATEWAY_API_KEY=...

# Direct OpenAI alternative
export AI_REQUEST_EXTRACTION_PROVIDER=openai
export AI_REQUEST_EXTRACTION_MODEL=gpt-5.6-luna
export AI_BRIEFING_GENERATION_PROVIDER=openai
export AI_BRIEFING_GENERATION_MODEL=gpt-5.6-terra
export AI_EMBEDDING_PROVIDER=openai
export AI_EMBEDDING_MODEL=text-embedding-3-small
export OPENAI_API_KEY=...

# OpenRouter alternative
export AI_REQUEST_EXTRACTION_PROVIDER=openrouter
export AI_REQUEST_EXTRACTION_MODEL=openai/gpt-5.6-luna
export AI_BRIEFING_GENERATION_PROVIDER=openrouter
export AI_BRIEFING_GENERATION_MODEL=openai/gpt-5.6-terra
export OPENROUTER_API_KEY=...
```

See `.env.example` for the non-secret defaults. The local server and live eval
runner load the ignored `.env.local` file automatically.

For one local briefing-generation run with Kimi K3, start the API with:

```sh
cd backend
bin/server --briefing-model kimi-k3
```

This uses the existing Vercel AI Gateway credential and `moonshotai/kimi-k3` for
briefing generation only. It allows Kimi up to 180 seconds and makes one provider
attempt per click, so a slow response does not trigger a duplicate billed request.
It does not change `.env.local`, request extraction, or semantic embeddings. Stop
the server after the test and start it normally to return to the configured briefing
model.

Briefings support four retrieval strategies. `linked_recency` follows explicit
request-person relationships and recent interaction limits. `semantic` preserves
the same essential linked facts, then ranks prior interactions inside the current
workspace by embedding similarity. `hybrid` reserves relevant prior history across
the meeting attendees, fills the remaining interaction budget with the strongest
workspace-wide semantic matches, and gives each generated section its own evidence
boundary. `fused` combines vector, PostgreSQL full-text, attendee-scoped, and
candidate-recency rankings with reciprocal-rank fusion. Long, information-dense
interactions also receive deterministic high-signal child documents for decisions,
commitments, concerns, and requests. Child matches collapse back to one
authoritative interaction before context limits are applied, so verbose records do
not consume multiple evidence slots. The model receives up to three relevant spans
from a matched parent. A separate decision-grade fact pass protects a globally bounded
set of exact owners, identifiers, dates, thresholds, commitments, and blockers from
being lost when the matched spans are compacted; facts already present in matched spans
are deduplicated. Source excerpts stay available for citation audits but are omitted
from the model payload because their structured facts contain the same text. Retrieval
diagnostics likewise remain in version audits rather than consuming generation tokens;
the compact section-to-source boundary map remains model-visible so generated citations
can pass the same grounding rules enforced by the application. Fused selection preserves attendee coverage and
chooses a diverse 10–12 total interactions instead of always filling the 15-record
ceiling. Lexical candidates emphasize identifiers, names, and rare corpus terms.
Open questions reserve three to four compact slots and prioritize uncovered agenda
decisions and missing decision authority before secondary opportunities from history.
Neon creates a pgvector HNSW index; local
PostgreSQL installations without pgvector use an array-backed development
fallback with the same workspace filter and deterministic fake embeddings.
Generated versions retain retrieval metadata and model usage so reviewers can
compare useful cited claims per 1,000 input tokens for the same briefing. The UI
compares the latest generated version from each strategy.

To backfill embeddings for all existing interactions, configure a real embedding
provider in `.env.local`, apply migrations, and run:

```bash
cd backend
bundle exec rake db:migrate
bin/backfill-semantic-index
```

The command is idempotent: it embeds only missing records, changed content, or
records stored with a different embedding model, and removes obsolete child
documents after an interaction changes. Set `WORKSPACE_SLUG=slug` to
backfill one workspace. For local demonstration data only, set
`ALLOW_FAKE_EMBEDDING_BACKFILL=1`; production backfills refuse the fake provider
by default. Requests are sent in batches controlled by
`SEMANTIC_EMBEDDING_BATCH_SIZE` (default `100`).

## Retrieval Comparison Scenario

The deterministic resilience scenario contains attendee-heavy history,
workspace distractors, superseded guidance, exact identifiers, deadlines, and
long interactions with high-signal passages. Seed it after normal database setup:

```bash
cd backend
bundle exec rake db:migrate
bundle exec ruby script/seed_resilience_e2e_scenario.rb
bin/backfill-semantic-index
```

Open the printed briefing ID and generate `linked_recency`, `semantic`, and
`hybrid` versions as controls, followed by `fused`. The comparison keeps the
latest immutable version for each strategy and supports a useful-cited-claims
rating. Keep the briefing, generation model, and prompt version fixed while
comparing required evidence, distractors, stale evidence, attendee coverage,
input tokens, and citation usefulness.

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

Production is configured to run on Render in Oregon as two independently
deployed Starter web services. `holocron-web` serves the vinext frontend and
calls `holocron-api` over HTTPS. Only the API connects to the existing Neon US
West PostgreSQL database; the Blueprint does not create a Render Postgres
resource.

```text
Browser -> holocron-web -> holocron-api -> existing Neon database
```

Both services deploy from the `production` branch using the root-level
`render.yaml`. The frontend uses Node `22.22.0`; the API uses the Ruby version
recorded in `backend/Gemfile.lock`.

### Render environment variables

The Blueprint supplies the non-secret production settings. Enter these secrets
in the Render dashboard when creating the Blueprint:

| Service | Variable | Value |
| --- | --- | --- |
| `holocron-api` | `DATABASE_URL` | Neon pooled URL (hostname contains `-pooler`; TLS required) |
| `holocron-api` | `MIGRATION_DATABASE_URL` | Neon direct URL (TLS required) |
| `holocron-api` | `AI_GATEWAY_API_KEY` | Production Vercel AI Gateway credential |

The API runtime uses `DATABASE_URL`; the pre-deploy migration temporarily uses
`MIGRATION_DATABASE_URL`. The frontend receives the public
`NEXT_PUBLIC_API_URL=https://holocron-api.onrender.com` value at build time, and
the API allows `https://holocron-web.onrender.com` through `FRONTEND_ORIGINS`.
If either Render service name is unavailable, choose both final names and update
these two URL values before deploying.

Do not configure `TEST_DATABASE_URL` in production. Never run `db:create`,
`db:setup`, or `db:seed` against the production Neon database.

### Migrations and health checks

Every API deploy runs the following pre-deploy command before new application
instances start:

```bash
DATABASE_URL="$MIGRATION_DATABASE_URL" bundle exec rake db:migrate
```

Render checks the API at `GET /health` and the frontend at `GET /`. The API
health response should be HTTP 200 with `{"status":"ok","service":"holocron-api"}`.

### Rollback

For an application regression, roll back only the affected Render service to
its previous successful deploy. Do not automatically reverse a database
migration: first confirm that the old application remains compatible with the
current schema. Use Neon restore capabilities only for actual data corruption,
not for an ordinary application rollback.

See [the Render deployment plan](docs/render-deployment-plan.md) for the complete
provisioning sequence, smoke test, and operational checklist.

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
POST /api/briefings/:id/generate
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

Only scheduled requests can produce meetings and briefings. Meeting creation
commits an editable deterministic version 1; the browser then separately calls
the generation endpoint to append a grounded draft. Briefing edits append
immutable versions; generation, submission, and review commands use
`lock_version` and synchronously record audit events. Approval and
changes-requested decisions belong to the exact version reviewed.

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
