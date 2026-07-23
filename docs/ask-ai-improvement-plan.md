# Ask AI results improvement plan

## Purpose

Improve the usefulness, completeness, and reliability of Ask Holocron answers
without weakening its existing workspace isolation, read-only behavior, or
claim-level evidence requirements.

This document covers the current interaction-history-only Ask surface. It does
not expand the product to files, calendars, email, web search, tool use, or
multi-turn memory.

## Current contract to preserve

Ask Holocron currently:

- accepts one question from an active workspace member;
- searches only the active workspace's interaction history;
- returns a concise answer, claims, cited interaction sources, and limitations;
- returns a deterministic no-evidence or disambiguation result rather than
  inventing history;
- makes no domain writes during an Ask request; and
- treats questions and retrieved source fields as untrusted data.

The following must remain release blockers for every improvement:

1. No cross-workspace source may appear in retrieval, a citation, or output.
2. Every displayed factual statement must have source evidence.
3. The Ask request itself must not create, update, or delete domain records.
4. Prompt-injection text in an interaction must be treated as evidence, never
   as an instruction.

## Investigation findings

### 1. Index freshness is now covered for normal writes

`AskAI.answer` still searches with `refresh: false`. That remains the correct
read-only, low-latency behavior. Commit `c8667d6` closes the prior write-path
gap by adding a durable, unique-per-interaction `semantic_index_jobs` queue:

- manual interactions enqueue inside the interaction transaction;
- scheduling-request interactions enqueue on create and update;
- local development processes the job inline, making a successful write
  immediately searchable; and
- production configures a dedicated worker to drain the queue asynchronously.

The indexer refreshes only the affected interaction, rather than rebuilding the
whole workspace. Tests now cover inline manual indexing, worker draining, and
reindexing after a scheduling-request edit. The previously failing
provider-configuration test indexes its fixture before asserting that Ask calls
the provider.

This solves the original freshness issue for interactions written through these
normal API paths once migration `018` and the production worker are live. It
does not by itself provide recovery for a job left `running` after a worker
crash, index pre-existing interactions, or cover imports that bypass those API
write paths.

### 2. The final source budget is applied before qualification is complete

Ask requests six results from the fused index, then applies its workspace,
entity, and topic qualification filter. If some of those six candidates are
discarded, lower-ranked but qualifying candidates are never considered. This
can produce a no-evidence result even when relevant indexed evidence exists.

The topic check is intentionally simple: it accepts an interaction if any
normalized topic token matches or shares a six-character prefix. It is useful
as a safety guard, but it is not a semantic relevance decision and does not
handle synonyms, aliases, negation, or intent.

### 3. Entity matching is narrow

Person and organization resolution relies on exact normalized names plus a
shared-first-name ambiguity check. Common user phrasing such as an organization
abbreviation, a nickname, a misspelling, or an alternate legal name can miss
the intended history.

### 4. Citation validity does not prove textual support

The generation validator ensures that claims cite one of the supplied source
references. It does not verify that a cited source entails the claim. The
top-level answer is also free-form rather than composed from the cited claims,
so an unsupported sentence could appear even when every claim reference is
syntactically valid.

### 5. Quality is not yet evaluated end to end

The Ask fixture test checks fixture structure and scope boundaries. It does not
run retrieval, call a model, or score answer completeness and factual support.
The local fake Ask provider echoes the first source, which is useful for
deterministic contract tests but cannot assess multi-source synthesis quality.

### 6. Operations and UX provide little recovery information

The Ask response hides retrieval coverage and index freshness. A user who
receives no evidence cannot distinguish an actually empty history from an
indexing delay or a poorly phrased query. The UI has no feedback path to turn
bad results into evaluation examples.

## Target outcomes and measurement

Create a baseline before setting release thresholds. The scorecard must include
both automated and human-reviewed measurements.

| Dimension | Measure | Initial release gate |
| --- | --- | --- |
| Retrieval | Recall@6 and Recall@20 for required source interactions | Improve from baseline; no regression on named people or organizations |
| Grounding | Percentage of displayed claims entailed by at least one cited source | 100% on security and deterministic cases; at least 95% in reviewed production-like cases |
| Completeness | Required evidence-backed facts represented in the answer | Improve from baseline for multi-source questions |
| Abstention | Correct no-answer and ambiguity behavior | No regression; zero cross-workspace leakage |
| Freshness | Time from interaction write to searchable state | Publish p50/p95; define an operational SLO after baseline |
| Experience | User helpfulness rating and corrected-answer rate | Track by question intent and release version |
| Performance | p50/p95 latency, provider failure rate, and verifier rejection rate | No material regression against the current service |

## Recommended implementation sequence

### Phase 0 — Establish a real evaluation harness

Build a versioned Ask evaluation corpus with anonymized, representative
interactions and question cases. Include:

- direct person and organization history;
- multi-source summaries and timelines;
- topic questions without a named entity;
- aliases, abbreviations, and alternate names;
- dates, decisions, commitments, conflicts, and negative/no-evidence cases;
- ambiguous names, prompt injection, and cross-workspace attempts; and
- recently created and recently updated interactions.

Each case should define the expected behavior, required and allowed source IDs,
forbidden source IDs, required facts, and expected limitations where applicable.
Run the full retrieval-and-generation path with a pinned model configuration,
then score retrieval independently from generation. Store the prompt version,
retrieval strategy, model, latency, and score for each run.

**Exit criteria:** a repeatable baseline exists; the fixture-contract test is
retained as a safety test rather than presented as an answer-quality evaluation.

### Phase 1 — Harden indexed-evidence freshness

**Status: delivered for normal API writes; production hardening remains.**

The durable job queue, write-path enqueueing, single-interaction refresh, inline
local mode, and Render worker are implemented in commit `c8667d6`. This means
Ask can remain read-only while newly created manual interactions and newly
created or edited scheduling-request interactions become searchable.

Complete the remaining operational work:

- reclaim jobs whose worker died after changing their status to `running`;
  `locked_at` should become a lease with a bounded expiry and safe retry;
- add queue-depth, oldest-pending-job age, retry count, failure count, and
  write-to-index latency metrics and alerts;
- perform and record an initial backfill after migration for interactions that
  existed before the queue was introduced; and
- make imports and maintenance scripts enqueue jobs or explicitly invoke a
  scoped backfill. Do not assume direct database writes become searchable.

Defer an exact-entity lexical fallback unless metrics show worker lag breaches
the freshness SLO. If introduced, it must preserve the same interaction-only and
workspace restrictions as semantic retrieval and make freshness limitations
explicit rather than silently mixing stale and fresh sources.

**Exit criteria:** migration `018` is applied, the production worker is healthy,
all existing interactions are backfilled, a worker restart cannot strand a job,
and write-to-searchable p50/p95 meet the published freshness SLO.

### Phase 2 — Improve retrieval before changing the model

Retrieve a larger candidate pool (for example 30–50 interactions), enforce
workspace and entity boundaries, apply qualification and reranking, then select
the final six sources. Do not discard candidates merely because an earlier six
contained weak matches.

Use a query-intent layer to select retrieval behavior:

- **person or organization history:** prioritize resolved entities, then balance
  across people and time;
- **topic question:** favor high-signal matched spans and lexical identifiers;
- **timeline or recent question:** explicitly rank by occurrence date after
  relevance; and
- **comparison or conflict question:** seek evidence on each named side and
  preserve disagreement rather than flattening it.

Add controlled aliases for people and organizations. Prefer stored normalized
aliases and reviewer-confirmed alternatives over unconstrained fuzzy matching.
Keep ambiguity responses when candidates cannot be distinguished safely.

Build source context from the best matching high-signal spans plus enough parent
interaction context to preserve meaning. Avoid taking the first 800 characters
of a long overview when the relevant decision or commitment appears later.

**Exit criteria:** retrieval recall and no-evidence behavior improve on the
evaluation corpus with no workspace-boundary regressions.

### Phase 3 — Make answer generation verifiable

Replace the free-form answer/claim split with citation-bound answer units. A
practical response shape is a short answer summary plus ordered factual bullets,
where every bullet carries one to three source references. The rendered summary
must be assembled from, or directly traceable to, those cited bullets.

Add a verification pass for every proposed claim:

1. Validate source IDs and output schema as today.
2. Check whether the claim is entailed by its cited excerpts using a constrained
   verifier model or deterministic rules for dates, names, and exact values.
3. Drop, revise, or regenerate claims that are unsupported.
4. State evidence conflicts and missing details in limitations rather than
   selecting a side without support.

Keep model and prompt changes behind the evaluation gate. Tune for concise
evidence synthesis only after retrieval quality is measurable.

**Exit criteria:** every displayed factual sentence is citation-linked and
passes entailment review; unsupported top-level answer text cannot bypass the
claim validator.

### Phase 4 — Close the learning loop

Record privacy-conscious operational events: Ask version, retrieval coverage,
index freshness, result type, latency, provider outcome, and verifier outcome.
Do not persist question or source content by default without an explicit data
retention decision.

Add optional user feedback to the result view: helpful/not helpful and an
optional explanation. Route sampled failures and user-reported misses into a
human review queue, redact as needed, and promote approved examples into the
versioned evaluation corpus.

Offer low-risk UI aids after backend quality is stable: intent-specific examples,
date/scope suggestions, source filters, and a one-click refine action for
no-evidence responses. Retain the current evidence-first source cards.

**Exit criteria:** each release reports the scorecard, feedback is reviewable,
and regressions block promotion.

## Non-goals for this plan

- Adding external sources, files, email, calendar, or web search.
- Granting the model database, network, or mutation tools.
- Adding multi-turn memory or durable chat history.
- Replacing human review for disputed or sensitive relationship information.
- Relaxing the existing workspace boundary to improve recall.

## Verification status at time of investigation

- The Ask fixture contract passes with the repository's configured Ruby runtime.
- Frontend lint passes.
- The backend suite passes: 92 runs, 822 assertions, zero failures and zero
  errors. This includes indexing a manual interaction inline, draining a queued
  worker job, reindexing a scheduling-request interaction after an edit, and the
  Ask provider-configuration path.
- The feature is ready to rely on the new index-freshness mechanism only after
  migration `018` and the `holocron-semantic-indexer` worker are deployed in the
  target environment.
