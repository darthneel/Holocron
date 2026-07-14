# Synchronous Scheduling-Request Audits

## Status

Accepted for Step 2.

## Context

Scheduling-request creation and editing are the first meaningful workspace
mutations. The development environment has no job queue or durable outbox, but
the audit history must reliably identify each completed change.

## Decision

The scheduling-request domain service writes the request, its participants,
candidate windows, and audit event synchronously in one SQLite transaction.
The development actor comes from `X-Holocron-Actor-Email` and is stored as the
audit event actor and the request creator.

## Consequences

The write path stays simple and the audit trail cannot lag behind a successful
request mutation. A failed audit insert rolls the entire mutation back. This
does not yet solve delivery of external side effects; a future integration that
needs retries should introduce an outbox rather than weakening this invariant.
