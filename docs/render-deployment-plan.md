# Render Deployment Implementation Plan

## Objective

Deploy Holocron to Render as two always-on Starter web services while retaining the existing Neon PostgreSQL database as the single production datastore.

The target recurring Render compute cost is **$14 per month**:

| Service | Render type | Plan | Monthly cost |
| --- | --- | --- | ---: |
| Holocron web | Node web service | Starter | $7 |
| Holocron API | Ruby web service | Starter | $7 |
| Existing Neon database | External PostgreSQL | Current Neon plan | Unchanged |
| **Render total** |  |  | **$14** |

Render workspace-plan upgrades are not required. The cost comes from the two Starter compute instances. Do not create a Render Postgres resource.

## Target Architecture

```text
Browser
  |
  v
Holocron web (Render Starter, Node/vinext)
  |
  | HTTPS JSON API requests
  v
Holocron API (Render Starter, Ruby/Roda/Puma)
  |
  | TLS PostgreSQL connection
  v
Existing Neon database
```

The frontend never receives database credentials. Only the API connects to Neon.

## Deployment Decisions

The initial deployment decisions are confirmed:

| Decision | Selection |
| --- | --- |
| Frontend service name | `holocron-web` |
| API service name | `holocron-api` |
| Render region | `oregon`, matching the Neon US West location |
| Production Git branch | `production` |
| Request extraction | Vercel AI Gateway with `openai/gpt-5.6-luna` |
| Briefing generation | Vercel AI Gateway with `openai/gpt-5.6-terra` |
| Embeddings | Vercel AI Gateway with `openai/text-embedding-3-small` |
| Frontend public URL | `https://holocron-web.onrender.com` |
| API public URL | `https://holocron-api-fctr.onrender.com` |
| Custom domains | None planned |

Create the `production` branch from the verified release commit before connecting
the Blueprint. Both Render services should deploy only from this branch.

The production AI configuration intentionally matches the current local configuration. Render will receive the same provider and model names plus its own securely stored copy of `AI_GATEWAY_API_KEY`. No AI credential will be committed to the repository.

## Phase 1: Repository Preparation

### 1. Add a Render Blueprint

Add a root-level `render.yaml` defining exactly two services and no database resources.

The API service should use:

- Type: `web`
- Runtime: `ruby`
- Plan: `starter`
- Region: `oregon`
- Branch: `production`
- Root directory: `backend`
- Build command: `bundle install`
- Pre-deploy command: `DATABASE_URL="$MIGRATION_DATABASE_URL" bundle exec rake db:migrate`
- Start command: `bundle exec puma --config config/puma.rb config.ru`
- Health check: `/health`
- Auto-deploy trigger: `commit`

The frontend service should use:

- Type: `web`
- Runtime: `node`
- Plan: `starter`
- Region: `oregon`
- Branch: `production`
- Repository root as its root directory
- Build command: `npm ci && npm run build`
- Start command: `npm start`
- Health check: `/`
- Auto-deploy trigger: `commit`

The Blueprint should declare secret variables with `sync: false`. No secret values should be committed.

### 2. Pin Runtime Versions

- Pin Node to a tested Node 22 release using `NODE_VERSION` in the Blueprint or a `.node-version` file.
- Retain the Ruby version recorded in `backend/Gemfile.lock`, provided it is supported by Render at deployment time.
- Change the unbounded Node engine range in `package.json` to include an upper bound so a future Node major release cannot be selected automatically.

### 3. Configure Build Filters

Avoid unnecessary redeployments:

- API deploys should be triggered by changes under `backend/**` or `render.yaml`.
- Frontend deploys should be triggered by changes under `app/**`, `public/**`, `worker/**`, `build/**`, and root frontend configuration/package files.
- Render always processes changes to `render.yaml`, independent of build filters.

### 4. Update Deployment Documentation

Replace the current local-only deployment note in `README.md` with:

- Render service architecture
- Required environment variables
- Migration procedure
- Health endpoints
- Rollback procedure
- A warning not to run `db:setup` or `db:seed` against production Neon

## Phase 2: Neon Preparation

### Verification Status

Phase 2 was verified on July 21, 2026:

- The runtime connection uses the Neon pooled endpoint in US West.
- The migration connection uses the matching direct endpoint.
- Both connection strings require TLS and channel binding.
- Migration `015_add_detail_loading_indexes.rb` was applied through the direct
  endpoint, advancing `schema_info.version` from `14` to `15`.
- The four detail-loading indexes created by migration 15 are present.
- The pooled runtime connection succeeds with a five-connection application
  pool.
- Existing record counts were unchanged after migration: one workspace, five
  workspace members, five scheduling requests, three briefings, zero tasks, 82
  interactions, and 158 audit events.

The current Neon credential owns the database and can create databases and
roles. This is acceptable for the initial deployment under the exception below,
but it is broader than the desired long-term runtime scope. Schedule a dedicated
restricted application role as a production-hardening follow-up; until then,
keep the owner credential confined to Render secrets and never expose it to the
frontend.

### 1. Collect Both Connection Strings

From the existing Neon project, copy:

- The pooled application connection string, whose hostname contains `-pooler`
- The direct connection string for schema migrations

Both strings must require TLS. Store them only in Render secrets.

### 2. Configure Database Roles and Scope

Prefer a dedicated application role with access only to the Holocron database and required schema. If the existing Neon connection uses an owner role, deployment can proceed initially, but creating a restricted runtime role should be scheduled as a follow-up hardening task.

### 3. Verify the Existing Schema

Before the first Render deploy:

1. Run `bundle exec rake db:migrate` locally against the Neon direct connection string.
2. Confirm the migration completes without loading seed data.
3. Confirm the existing workspace and records remain present.
4. Record the latest applied migration number.

Do not run `db:create`, `db:setup`, or `db:seed` against Neon production.

### 4. Set Conservative Connection Limits

Start the API with:
```env
DATABASE_POOL_SIZE=5
DATABASE_POOL_TIMEOUT=5
DATABASE_CONNECTION_VALIDATION_TIMEOUT=30
PUMA_MIN_THREADS=1
PUMA_MAX_THREADS=5
WEB_CONCURRENCY=0
```

This keeps the Sequel pool aligned with one Puma process and five maximum threads. Revisit the pool only after measuring production concurrency.

## Phase 3: Render Environment Configuration

### API Variables

Configure these on `holocron-api`:

```env
RACK_ENV=production
DATABASE_URL=<Neon pooled connection string>
MIGRATION_DATABASE_URL=<Neon direct connection string>
DATABASE_POOL_SIZE=5
DATABASE_POOL_TIMEOUT=5
DATABASE_CONNECTION_VALIDATION_TIMEOUT=30
PUMA_MIN_THREADS=1
PUMA_MAX_THREADS=5
WEB_CONCURRENCY=0
FRONTEND_ORIGINS=https://holocron-web.onrender.com
```

Configure the current AI provider and models on Render:

```env
AI_REQUEST_EXTRACTION_PROVIDER=vercel
AI_REQUEST_EXTRACTION_MODEL=openai/gpt-5.6-luna
AI_BRIEFING_GENERATION_PROVIDER=vercel
AI_BRIEFING_GENERATION_MODEL=openai/gpt-5.6-terra
AI_EMBEDDING_PROVIDER=vercel
AI_EMBEDDING_MODEL=openai/text-embedding-3-small
AI_GATEWAY_API_KEY=<secret configured in Render>
```

Do not configure `TEST_DATABASE_URL` in production.

### Frontend Variables

Configure these on `holocron-web`:

```env
NODE_VERSION=22.22.0
NEXT_PUBLIC_API_URL=https://holocron-api-fctr.onrender.com
```

`NEXT_PUBLIC_API_URL` is embedded during the frontend build. Any change to it requires rebuilding the frontend service.

### Custom Domains

No custom domain is planned. The production deployment will use:

- `https://holocron-web.onrender.com`
- `https://holocron-api-fctr.onrender.com`

The API service is still named `holocron-api`. Render assigned the public slug
`holocron-api-fctr` because the shorter global hostname was unavailable. Keep
the assigned hostname in `NEXT_PUBLIC_API_URL`; the frontend URL remains the
allowed `FRONTEND_ORIGINS` value.

## Phase 4: First Deployment

1. Push the repository preparation changes to the production branch.
2. In Render, create a new Blueprint from the repository's `render.yaml`.
3. Review that the Blueprint creates two Starter web services and no Render database.
4. Enter every `sync: false` secret when prompted.
5. Confirm the expected cost is $7 per service, $14 per month total.
6. Start the Blueprint sync.
7. Confirm the API build succeeds.
8. Confirm the API pre-deploy migration succeeds against the Neon direct connection.
9. Confirm the API passes `GET /health`.
10. Confirm the frontend build receives `NEXT_PUBLIC_API_URL` and starts successfully.
11. Open the frontend's Render URL and confirm browser requests reach the API without CORS errors.

## Phase 5: Production Smoke Test

Perform these checks in order:

1. `GET https://holocron-api-fctr.onrender.com/health` returns HTTP 200.
2. The frontend email-entry page renders.
3. A known workspace member can open the workspace.
4. The request list loads and an existing request opens.
5. The briefing list loads and an existing briefing opens.
6. Briefing sources expand and collapse normally.
7. Browser developer tools show the API's `Server-Timing` response header.
8. Neon monitoring shows connections using the pooled endpoint.
9. Render logs contain no CORS, database-pool, migration, or missing-secret errors.
10. Existing Neon record counts remain consistent with the pre-deployment check.

Avoid creating permanent test records during the first smoke test because the application does not currently expose a delete workflow.

### Deployment result — July 21, 2026

- Blueprint commit: `3899545` on `production`.
- `holocron-api` is live on Starter in Oregon at
  `https://holocron-api-fctr.onrender.com`.
- `holocron-web` is live on Starter in Oregon at
  `https://holocron-web.onrender.com`.
- The Blueprint created no Render database; the API uses the existing Neon US
  West database with pooled runtime and direct migration connections.
- The final API pre-deploy migration and both final service deploys succeeded.
- Health, CORS, `Server-Timing`, workspace entry, request loading, briefing
  loading, briefing count, and Sources open/close smoke checks passed.
- Post-release logs contained no application errors or HTTP 5xx responses.
- Render compute is two $7 Starter services, totaling $14 per month.

## Phase 6: Operational Setup

### Monitoring

Create alerts or a review routine for:

- Render API health-check failures
- Render deploy failures
- Puma worker/thread saturation
- Neon connection and pooler usage
- Neon compute and storage consumption
- AI provider timeouts and errors

### Deployments

- Require frontend and backend tests to pass before merging to the production branch.
- Keep database migrations backward-compatible with the currently running API during zero-downtime deployments.
- Never combine destructive schema changes with the application change that first stops using the old schema.

### Rollback

For an application regression:

1. Roll back the affected Render service to the previous successful deploy.
2. Do not automatically reverse database migrations.
3. If a migration is implicated, assess data compatibility before running a down migration.
4. Use Neon's restore capabilities only for actual data corruption, not ordinary application rollback.

## Acceptance Criteria

Deployment is complete when:

- Two Render Starter services are running at a confirmed total of $14 per month.
- The frontend is publicly accessible over HTTPS.
- The API health check is passing.
- The browser can call the API without CORS failures.
- The API uses the existing Neon pooled connection for runtime traffic.
- Render migrations use the Neon direct connection.
- No Render Postgres resource exists.
- Existing requests, relationships, tasks, and briefings remain intact.
- A repeat visit does not incur Render free-tier cold starts.
- Repository documentation accurately describes production deployment and rollback.

## References

- [Render Blueprints](https://render.com/docs/infrastructure-as-code)
- [Render monorepo support](https://render.com/docs/monorepo-support)
- [Render web services](https://render.com/docs/web-services)
- [Render pricing](https://render.com/pricing)
- [Neon connection pooling](https://neon.com/docs/connect/connection-pooling)
