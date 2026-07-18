# Step 7 Walkthrough

Step 7 turns an existing meeting briefing into a grounded, model-generated draft
without allowing the model to search the database or write domain records.

## Representative Flow

1. Staff schedule a meeting from a scheduling request.
2. Meeting creation commits the meeting, briefing, deterministic version 1, and
   synchronous audits in one transaction.
3. After that command succeeds, the browser automatically sends
   `POST /api/briefings/:id/generate` with the returned briefing ID and lock.
4. The generation command resolves the development actor and validates the
   expected briefing lock.
5. `BriefingContextAssembler` loads the briefing, meeting, and scheduling request
   through the current workspace.
6. The assembler follows `scheduling_request_people`, role orders the linked
   people, loads only their scoped organizations, and selects current plus recent
   interactions with per-person and global limits.
7. Request, meeting, person, organization, and interaction records become a
   bounded manifest with stable `SRC-nnn` handles and visible limitations.
8. `BriefingGeneration` sends the versioned instructions, manifest, and strict
   output schema for five generated sections through `ModelRouter`.
9. Deterministic validation requires overview, attendees, prior history,
   objectives, and logistics; it rejects unknown or irrelevant citations and
   requires citations for every non-empty material section. The application then
   derives `relationship_context` from the manifest's people, organizations, and
   prior interactions.
10. The service reloads the briefing and rechecks `lock_version` after the model
   call.
11. One short transaction advances the projection, appends the generated version
   and section source snapshots, writes the audit event, and commits.
12. Staff can regenerate, edit, submit, and approve the draft through the existing
    manual briefing lifecycle.

## Retrieval Limits

- 12 linked people, ordered requester, required, optional, then staff
- 2 current-request interactions per person
- 5 prior interactions per person
- 15 interactions across the complete meeting
- 25 citations per generated section
- 60,000 characters for selected source context

Interaction selection is round-robin across linked people after current-request
records are prioritized. A person with extensive history therefore cannot crowd
every other attendee out of the model context.

## Trust Boundaries

- Every workspace-owned table query includes the current `workspace_id`.
- The model sees only the assembled manifest, never credentials or database
  access.
- Manifest strings are explicitly treated as untrusted data.
- The response may cite only supplied `SRC-nnn` handles.
- The model does not generate `relationship_context`; application code derives
  that section from the selected manifest records and attaches its citations.
- Prior history may cite only interactions marked `current_request: false`.
- Application code, not the model, resolves citations to stored source snapshots.
- The model call cannot mutate a briefing. Persistence occurs only after output
  validation and a second optimistic-lock check.

## Failure Cases

- A missing or inactive actor cannot start generation.
- A stale lock returns `409` before the model call.
- A briefing under review cannot be regenerated.
- Provider configuration, transport, refusal, exhausted retry, malformed schema,
  unknown citation, irrelevant citation, or uncited material content creates no
  briefing version.
- Failure of the automatic generation request does not reverse the committed
  meeting or deterministic version 1. The workbench remains usable and offers
  `Generate draft` for retry.
- Rate limits, server errors, network failures, and successful responses without
  structured output are retried once before failure is recorded.
- Provider or output-validation failure writes a synchronous
  `briefing.generation_failed` audit with non-sensitive diagnostics.
- A lock conflict after the model call discards the output rather than replacing a
  newer human version.

## Files

- `backend/lib/holocron/briefing_context_assembler.rb` owns scoped traversal,
  ordering, limits, source snapshots, and the context manifest.
- `backend/lib/holocron/briefing_generation.rb` owns prompting, schema, citation
  validation, and conversion into briefing sections.
- `backend/lib/holocron/ai/model_router.rb` selects the task-specific provider and
  model.
- `backend/lib/holocron/briefings.rb` owns lock checks, immutable persistence, and
  success/failure audits.
- `backend/app.rb` exposes the generation command.
- `app/page.tsx` automatically requests first generation after meeting creation
  and exposes later generation in the Briefings tab of the consolidated Meetings
  workbench. Sources are available through per-section disclosures; empty
  deterministic relationship-context sections are hidden from the reading view.
- `backend/test/app_test.rb` covers generation, citations, retrieval limits,
  persistence, and failure audits.
- `backend/eval/fixtures/briefing_generations.json` and
  `backend/eval/briefing_generation_eval_test.rb` provide the separate billed
  faithfulness and citation eval suite.

## Live Evals

Run the three synthetic cases through the configured hosted model with explicit
billing confirmation:

```bash
RUN_LIVE_EVALS=1 backend/bin/eval-briefing-generation
```

The suite checks required facts, section-level source types, visible limitations,
forbidden unsupported claims, and citation coverage. Results are written under
the ignored `backend/tmp/eval-results/` directory.
