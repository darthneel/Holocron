# Step 5 Walkthrough

Step 5 implements meeting briefing assembly without AI.

## Representative Flow

1. AI extraction or manual intake creates a `proposed` meeting.
2. The proposed-meeting detail collects the confirmed meeting title, start, end, and
   location.
3. `Briefings.create_for_request` verifies the request lock, marks it
   `scheduled`, and creates one meeting, one briefing, and version 1 in a single
   transaction.
4. Version 1 is assembled deterministically from request details, linked people,
   their current organizations, and person-centered interactions.
5. Every section receives validated source snapshots where relevant.
6. Staff edit the full section set and save it as the next immutable version.
7. The current draft is submitted for review using the briefing lock version.
8. A workspace member approves that exact version or requests changes with
   notes.
9. A later revision becomes the current draft without changing the earlier
   approved version or its review metadata.

The workflow uses four briefing tables: `meetings`, `briefings`,
`briefing_versions`, and `briefing_sections`. Review metadata lives on the exact
version being reviewed, while source snapshots live as JSON on their immutable
section. Neither reviews nor sources need an independent lifecycle table.

## Files

- `backend/db/migrations/006_create_manual_briefing_workflow.rb` introduces the
  workflow, and `007_simplify_manual_briefing_workflow.rb` folds source snapshots
  and review metadata into sections and versions.
- `backend/lib/holocron/briefings.rb` owns validation, deterministic assembly,
  serialization, transactions, optimistic concurrency, and audit writes.
- `backend/app.rb` exposes meeting creation plus briefing list, detail, version,
  submission, and review endpoints.
- `backend/db/seeds.rb` creates a first briefing for the scheduled Darius Holt
  request when that fixture is available.
- `backend/test/app_test.rb` traces successful and failed commands through the
  HTTP and database boundaries.
- `app/page.tsx` provides the consolidated Meetings workspace: scheduling
  requests and briefings occupy internal tabs, the briefing list loads when its
  tab opens, and the workbench provides section editing, source disclosures,
  version browsing, and review decisions.
- `app/globals.css` lays out the responsive operational briefing workspace.

## Failure Cases

- A record that is not `proposed` cannot be scheduled.
- A request cannot create a second meeting or briefing.
- A stale proposed-meeting lock version creates no meeting or briefing.
- Invalid meeting times create no records.
- A missing or inactive development actor cannot write.
- An invalid or cross-workspace source rejects the complete version.
- A stale briefing `lock_version` returns `409 Conflict` without a version or
  audit event.
- A briefing under review cannot be edited.
- A review decision is rejected unless the current version is `in_review`.
- Changes requested requires review notes.
- A version that already has a review decision cannot be reviewed again.
