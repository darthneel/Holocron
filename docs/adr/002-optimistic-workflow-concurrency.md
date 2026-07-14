# Optimistic Workflow Concurrency

## Status

Accepted for Step 3.

## Context

Multiple staff members may review or edit the same scheduling request. A
transaction makes one command atomic, but it does not reveal that the command
was prepared from stale request details.

## Decision

Every scheduling request has an integer `lock_version`. API responses expose
it, and edits and transitions must send it as `expected_lock_version`. The
service updates the request only where the stored version still matches, then
increments it in the same transaction as history and audit writes.

## Consequences

Competing commands cannot silently overwrite one another. The first valid
command succeeds; later stale commands receive `409 Conflict` and must reload.
This does not replace authentication, authorization, transactions, or future
idempotency keys.
