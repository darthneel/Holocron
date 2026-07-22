# Ask Holocron MVP

## Objective

Prove that a workspace member can ask one question and receive a trustworthy,
source-backed answer from Holocron's existing relationship history.

The MVP is a single-turn, read-only question-and-answer surface over existing
`interactions`. It deliberately does not attempt to reproduce Chief AI's broader
analytics, priority alignment, proactive insights, or agent behavior.

## Product contract

A workspace member can ask questions such as:

- What do we know about the Chamber of Commerce?
- Summarize our history with Avery Morgan.
- What have we discussed about storefront permitting?

Holocron returns:

- One concise answer.
- Zero or more factual claims, each linked to at least one retrieved source.
- An inline source catalog containing the person, organization, interaction type,
  occurrence date, and bounded excerpt.
- Explicit limitations when the available interaction history is insufficient or
  a named entity is ambiguous.

The endpoint is `POST /api/ask` with this request shape:

```json
{
  "question": "What do we know about the Chamber of Commerce?"
}
```

The successful response shape is:

```json
{
  "question": "What do we know about the Chamber of Commerce?",
  "answer": "The office has discussed...",
  "claims": [
    {
      "text": "The Chamber requested a workforce roundtable.",
      "source_refs": ["interaction:abc123"]
    }
  ],
  "sources": [
    {
      "source_ref": "interaction:abc123",
      "source_type": "interaction",
      "source_id": "abc123",
      "person_name": "Avery Morgan",
      "organization_name": "Cedar Grove Chamber",
      "interaction_type": "email",
      "occurred_at": "2026-06-12T18:00:00Z",
      "excerpt": "Requested a workforce roundtable..."
    }
  ],
  "limitations": []
}
```

Insufficient evidence is a successful response with no claims or sources and an
explicit limitation. Validation failures return `422`. Provider and configuration
failures follow the API's existing error conventions.

## Strict scope

### Included

- One Ask Holocron navigation item and question input.
- One answer at a time; a later question replaces the earlier result.
- Exact person and organization matching where possible.
- Existing fused semantic and lexical retrieval over `interactions`.
- Claim-level citations validated against the retrieved source manifest.
- Inline, inspectable interaction source cards.
- Existing workspace and actor boundaries.

### Excluded

- Conversation history, follow-up memory, or new persistence tables.
- Priorities, time-allocation analytics, and charts.
- Briefing, scheduling-request, task, file, email, calendar, news, or web sources.
- Streaming responses, proactive suggestions, tools, actions, or record mutations.
- Durable agent execution and new semantic-document types.
- Deep links to individual relationship records.

## Implementation phases

Each phase has a hard completion gate. Do not start the next phase until the
current gate passes.

### Phase 1: Executable evaluation contract

**Status: Implemented**

Create a synthetic interaction corpus and query fixtures covering:

- A direct person-name question.
- An organization-name question.
- A topic question without a named entity.
- An unknown subject.
- Two people with the same first name.
- Prompt injection embedded in interaction content.
- A cross-workspace access attempt.

The fixture records expected behavior, allowed and required citations, forbidden
citations, required facts, limitations, and ambiguity candidates. A deterministic
contract test validates the fixture shape and enforces the MVP boundary.

Gate:

- All required cases exist exactly once.
- Every referenced citation resolves to the synthetic corpus.
- Answer citations remain inside the current workspace.
- The corpus contains interactions only.
- No expectation depends on deferred product capabilities.

Run the Phase 1 contract with:

```sh
ruby -Ibackend/eval backend/eval/ask_ai_fixture_contract_test.rb
```

### Phase 2: Ask AI model task

**Status: Implemented**

Extend `Holocron::AI::ModelRouter` with `ask_ai(prompt:, schema:)` and task-specific
provider configuration. Add a strict output schema containing only `answer`,
`claims`, `source_refs`, and `limitations`. Extend the fake provider so all behavior
is testable without a network call.

The implementation lives in `backend/lib/holocron/ask_ai_generation.rb`. It owns
the prompt, bounded model-source shape, strict output schema, claim-level citation
validation, and normalized provider outcome. `AI_ASK_PROVIDER` and `AI_ASK_MODEL`
select the provider independently from extraction and briefing generation. The
deterministic fake provider covers success, no evidence, refusal, malformed output,
tool-call output, arbitrary UI fields, and transient failures. A deterministic
failing-provider test covers terminal provider errors.

Gate:

- Fake-provider schema tests pass.
- Existing extraction and briefing-generation behavior is unchanged.
- The model cannot return tool calls or arbitrary UI structures.

Verified with:

```sh
backend/bin/test
```

### Phase 3: Grounded retrieval service

Add `backend/lib/holocron/ask_ai.rb`. Validate a 3-1,000 character question,
resolve exact entity names, retrieve at most six fused interaction matches, build
a bounded source manifest, call the model, and validate every generated source
reference. Return a deterministic insufficient-evidence result without calling the
model when retrieval finds no qualifying interaction.

Do not modify `SemanticIndex`, add semantic source types, or let the model create
SQL.

Gate:

- Every factual claim has a valid retrieved source.
- Invalid or missing citations fail closed.
- Retrieval never crosses the active workspace boundary.

### Phase 4: Read-only API

Add `POST /api/ask`. The route resolves the current workspace and actor, parses a
JSON object, delegates to `AskAI`, and serializes the validated result. It creates
no records and changes no domain state.

Gate:

- Invalid JSON, validation, provider failure, and success responses follow the
  documented contract.
- Database row counts do not change after a query.

### Phase 5: Ask Holocron interface

Add an `ask` workspace view and a separate `app/ask-holocron.tsx` component. The
component owns the question, loading, error, no-evidence, and success states and
renders cited source cards. Do not add browser persistence or thread history.

Gate:

- Keyboard submission works.
- Generated claims and source material are visually distinct.
- A second question replaces the first answer.
- Existing workspace views do not regress.

### Phase 6: End-to-end verification

Run the complete backend and frontend suites, then manually verify known,
unknown, ambiguous, injection, and cross-workspace questions.

Gate:

- Every factual claim is cited.
- Unknown questions do not invent an answer.
- Queries cannot mutate application data.
- Cross-workspace leakage remains zero.
- No migrations or new tables were introduced.

## Definition of done

The MVP is complete when one workspace member can submit one question and receive
one grounded answer over existing interactions, inspect every cited source, and
receive a clear limitation instead of an invented answer when evidence is missing.
Anything outside that boundary is a later increment.
