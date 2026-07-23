# Step 3 Walkthrough

Migration `020` simplifies scheduling requests to two states: `proposed` and
`scheduled`. It maps every existing non-scheduled request to `proposed` and
removes the transition and decision tables.

Creating an intake produces a proposed meeting. The request detail exposes the
time picker immediately. Confirming a time conditionally updates the request to
`scheduled` and creates the meeting, briefing, initial version, preparation
task, and audit events in one transaction.

The API uses `POST /api/scheduling-requests/:id/meeting` as the single scheduling
command. It requires `expected_request_lock_version`; stale callers receive
`409 Conflict` without partial writes. The browser labels proposed records
“Awaiting scheduling” and uses ordinary audit events for the activity list.

Tests cover proposal creation, atomic scheduling, stale scheduling and edits,
actor enforcement, duplicate scheduling, and rollback of every scheduling side
effect after a rejected command.
