# Briefing Retrieval and Context Efficiency Changes

This note summarizes the recent changes to fused briefing retrieval and the context sent to the generation model. The goal was to retain the decision-grade specificity of the stronger briefings while reducing input tokens, latency, and irrelevant evidence.

## 1. Retrieval-query changes

### Four fused rankings

Fused retrieval combines four independently ranked candidate lists using reciprocal-rank fusion:

- Vector similarity for semantically related interactions.
- PostgreSQL full-text search for exact words and phrases.
- Attendee-scoped semantic retrieval to preserve coverage across linked meeting participants.
- Recency ranking over the candidates found by the other rankers.

When the same interaction appears in multiple rankings, reciprocal-rank fusion increases its combined score. The interaction is still included only once in the final context.

### Smaller candidate pools

The candidate queries were capped before fusion:

- Vector candidates: up to three times the requested interaction limit.
- Lexical candidates: up to two times the requested interaction limit.
- Attendee candidates: up to two relevant interactions per linked attendee, with a final maximum of three selected interactions per person.

In the resilience scenario, this reduced the vector candidate set from 73 to 38 and the lexical candidate set from 73 to 24 without changing the final attendee coverage.

### More selective lexical queries

The full-text query now emphasizes:

- Exact identifiers such as `CG-HEAT-4` and `HL-27`.
- Person names.
- Rare terms in the workspace corpus.
- Fewer generic meeting and scheduling words.

This makes lexical retrieval useful for facts that embeddings may understand broadly but fail to preserve exactly.

### Adaptive and diverse final selection

Fused retrieval now chooses a diverse total of 10–12 interactions instead of always filling the general 15-interaction ceiling. Selection:

- Preserves at least one relevant interaction for attendees with available history.
- Favors high fused relevance.
- Penalizes redundant interactions with heavily overlapping text.
- Keeps additional interactions when they add a new evidence type or attendee perspective.

## 2. Semantic burst changes

Long interactions retain one overview embedding and may receive child embeddings for high-signal passages. Child bursts are created only for passages that contain decisions, commitments, concerns, requests, identifiers, or other sufficiently dense evidence.

A burst match does not become another top-level interaction in the briefing context. All matching bursts collapse back into their authoritative parent interaction, with up to three matched passages retained. This provides passage-level retrieval without allowing one long email or meeting note to consume several interaction slots.

## 3. Model-context changes

### Separate audit and model manifests

The complete manifest is retained for audits and debugging, including retrieval scores, ranker signals, candidate counts, and section evidence counts. The model receives a compact manifest containing only:

- Context version and workspace timezone.
- Selected source records and their structured facts.
- The compact section-to-source citation boundary map.
- Known context limitations.

Retrieval diagnostics no longer consume generation tokens.

### Remove redundant source excerpts from model input

`source_excerpt` remains in the full manifest so saved citations have readable evidence. It is removed from the model payload because the same information already appears in each source's structured `facts`.

This avoids sending interaction passages, names, and scheduling information twice. The citation-boundary map remains model-visible because the application validates citations against it.

### Protected decision-grade facts

Matched semantic passages occasionally omitted exact facts that were present elsewhere in the same selected parent interaction. A bounded extraction pass now protects sentences containing:

- Owners and assignments.
- Dates and deadlines.
- Protocol or checklist identifiers.
- Numerical thresholds.
- Explicit commitments.
- Unresolved blockers and constraints.

The protection budget is deliberately small:

- At most 10 protected facts across the whole briefing.
- At most 2 protected facts per interaction.
- At most 1,800 protected-fact characters total.
- At most 320 characters per fact.

Facts already represented in the matched semantic passages are deduplicated. In v25, eight protected facts used 1,132 characters and restored details such as `CG-HEAT-4`, the 75-degree/two-night threshold, Priya Shah's assignment, and the August 15 and August 19 deadlines.

### Compact citation boundaries

An earlier compact payload omitted `section_source_refs` even though output validation still enforced those boundaries. That caused intermittent grounded-validation failures when the model cited a valid source in the wrong section.

The compact boundary map is now included in the model payload, and the prompt identifies it as the authoritative list of allowed citations for each section. Large retrieval diagnostics remain excluded.

### Agenda-aware open questions

Prompt version `action-briefing-v4` introduced three to four open questions and prioritized them in this order:

1. Explicitly requested decisions lacking a confirmed location, owner, readiness standard, or commitment.
2. Missing stakeholder attendance or decision authority.
3. Unresolved operational status or promised deliverables.
4. Secondary opportunities found in prior history.

The fourth slot should be used when an explicit agenda or authority gap remains uncovered. This is intended to recover questions about clean-air-room ownership/readiness and the presence of Transit or facilities decision-makers without expanding retrieval or the context manifest.

### Compact meeting ask and non-repetitive questions

Prompt version `action-briefing-v5` tightens the output contract without changing retrieval or model context:

- `meeting_ask` must contain exactly one compact item combining the meeting purpose and concrete ask. This prevents the model from spending separate items on two versions of the same setup.
- An open question may overlap a desired outcome only when it identifies a specific unresolved owner, decision authority, attendee, current status, deadline completion, location, readiness standard, approval path, or operating commitment.
- Before returning output, the model must compare `open_questions` with `desired_outcomes` and remove or rewrite questions that merely convert an outcome into question form.

The application enforces the one-item meeting-ask limit structurally. Open-question deduplication remains a prompt-level semantic rule: a lexical-overlap validator could incorrectly reject a legitimate pair in which an outcome names a decision and its corresponding question asks for the missing approval or authority. The expected result is less output repetition and a modest output-token reduction with no additional retrieval, embeddings, or source data.

## 4. Observed v23 to v25 result

| Metric | v23 | v25 | Change |
|---|---:|---:|---:|
| Input tokens | 4,620 | 4,949 | +7.1% |
| Output tokens | 933 | 1,098 | +17.7% |
| Total tokens | 5,553 | 6,047 | +8.9% |
| Latency | 8.61 seconds | 8.70 seconds | +1.0% |
| Compact context characters | 13,007 | 12,073 | -7.2% |
| Cited claims | 17 | 21 | +23.5% |
| Cited claims per 1,000 input tokens | 3.68 | 4.24 | +15.3% |
| Selected interactions | 12 | 12 | unchanged |
| Unique cited interactions | 9 | 9 | unchanged |

V25 used 7.1% more input tokens than v23 because it added protected facts and a compact citation-boundary map. It produced 23.5% more cited claims, retained the same number of selected and cited interactions, and had effectively unchanged latency. It also remained about 41% below v22's 8,405 input tokens.

## 5. Current design principle

The current approach does not retrieve more data merely to improve quality. It retrieves a smaller, diverse candidate set; uses child embeddings to locate the useful passages inside long interactions; collapses those passages to authoritative parent records; and spends a small, explicit context budget on exact decision-grade facts and citation constraints.

The result should be evaluated on useful cited claims per 1,000 input tokens, exact decision coverage, grounded-validation reliability, and human briefing quality—not token reduction alone.
