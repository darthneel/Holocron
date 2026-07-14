# ADR 004: Immutable Briefing Content Versions

## Status

Accepted for Step 5.

## Decision

Every briefing edit appends a complete numbered version containing an ordered
set of sections and source snapshots. Existing section content is never updated
in place. The `briefings` row stores the current status, current version number,
and optimistic lock version as a read projection.

Submission and review change the status of the current version without changing
its content. An approval or changes-requested decision, notes, reviewer, and
timestamp are stored directly on that exact version. A separate review table is
unnecessary because one immutable version can receive at most one decision.
Creating a revision after either decision appends a new draft and leaves the
reviewed version intact.

Each section stores an ordered JSON array of source snapshots. Every snapshot
contains its validated record type and identifier plus a copied label and
excerpt. Sources have no independent lifecycle, so keeping them inside the
immutable section avoids relational overhead while preserving what staff saw
when that briefing version was assembled.

## Consequences

- Approved briefing content can always be recovered exactly.
- Concurrent editors receive `409 Conflict` before any partial version is written.
- Review responsibility and notes remain attached to the reviewed text.
- Storage grows with each save because a version contains a complete snapshot.
- Editing while a version is under review is rejected; staff must wait for a
  decision before creating another version.
- Live source records may evolve independently, but old section JSON retains
  readable source labels and excerpts.
