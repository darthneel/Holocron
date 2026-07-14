# Step 3 Walkthrough

Migration `003` adds request status, `lock_version`, immutable transitions, and
approval/decline decisions. It backfills every existing request to `submitted`
with a system-authored initial transition.

`SchedulingRequestWorkflow` owns the allowed transition graph, reason codes,
optimistic version check, conditional status update, transition insertion,
decision insertion, and audit event. All writes happen in one transaction.
Ordinary request edits use the same version check and increment the version
without changing status.

The API exposes `POST /api/scheduling-requests/:id/transitions`. The request
detail response includes the current status and version, valid next actions,
and serialized transition history. The browser shows status in the inbox,
reasoned workflow actions on request detail, and the newest-first timeline.

Tests cover the full submitted-to-scheduled path, approval decisions, illegal
state jumps, stale transitions, stale edits, actor enforcement, and rollback of
all workflow side effects after a rejected command.
