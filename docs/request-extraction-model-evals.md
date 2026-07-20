# Request Extraction Model Evaluations

This document tracks live-model evaluations for scheduling-request extraction.
It is intended to make model comparisons repeatable as the candidate set grows.

The production contract is now `request-extraction-v2`. It adds structured
briefing context for agenda decisions, ownership, authority, readiness,
dependencies, constraints, deliverables, and unresolved questions. The results
below are historical v1 measurements and should not be treated as v2 model
selection evidence. The v2 fixture suite contains an additional decision-rich
case and must be rerun before selecting a production model for the new contract.

## Current comparison

Runs in this table used the same six fixtures, 39 deterministic assertions,
`request-extraction-v1` prompt and schema, Vercel AI Gateway, and the
`America/Los_Angeles` workspace timezone. Calls were sequential. Prices are
estimates based on the configured per-token rates at evaluation time and may
differ from the gateway's final bill when provider routing changes.

| Evaluated (local date) | Model | Cases | Assertions | Input tokens | Output tokens | Estimated cost | Average latency | Median latency | Maximum latency | Total wall time |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 2026-07-16 | `openai/gpt-5.6-luna` | 5/6 | 38/39 | 2,491 | 1,038 | $0.008719 | 2.0s | 1.6s | 3.2s | 11.9s |
| 2026-07-16 | `moonshotai/kimi-k3` | 6/6 | 39/39 | 3,697 | 5,173 | $0.088686 | 49.5s | 23.0s | 110.9s | 296.8s |
| 2026-07-16 | `zai/glm-5.2` | 0/6 | 14/39 | 1,227 | 3,387 | $0.011327 | 12.8s | 10.4s | 22.6s | 76.5s |

These are single runs over a small corpus. Treat them as integration and
regression evidence, not statistically stable model rankings.

## Findings

### `openai/gpt-5.6-luna`

Luna remains the best production candidate from this group. It was the fastest
and least expensive successful integration.

Its only failed assertion was an exact timestamp-string comparison in the
`prompt_injection_is_data` case. Luna returned
`2026-09-30T16:00:00Z` instead of the expected
`2026-09-30T09:00:00-07:00`. Those values represent the same instant, so this
is a fixture-normalization issue rather than an extraction error. The assertion
should compare parsed instants while separately checking any requirement to
preserve the source offset.

### `moonshotai/kimi-k3`

Kimi was the only model to satisfy every current assertion, including the exact
timestamp representation. It was approximately 10.2 times as expensive and
24.9 times as slow end-to-end as Luna. It produced about five times as many
output tokens. The `fully_specified_request` and `prompt_injection_is_data`
cases each required a second attempt after the first response did not provide
usable structured output.

The small measured accuracy difference does not justify the cost and latency
penalties for this extraction workload.

### `zai/glm-5.2`

GLM understood many facts in the source messages but failed the integration
contract in all six cases. The gateway accepted the strict JSON Schema request,
but the responses used model-invented shapes such as `requester_name`,
`meeting_topic`, `duration_minutes`, and `candidate_dates`. Required nested
objects, arrays, field names, participant roles, and warnings were frequently
missing or incompatible with the schema.

Because production deterministically validates this contract, all six outputs
would be rejected. GLM was also approximately 1.3 times as expensive and 6.4
times as slow as Luna in this run. It should not be considered a drop-in model
for the current Vercel Responses API integration. A future GLM-specific prompt
or request format must be evaluated as a separate configuration rather than
compared as though it were the same integration.

## Evaluation protocol

Run the live suite with a Vercel AI Gateway key in `.env.local`. Load that file,
then apply the candidate override after it has loaded so its default model does
not replace the model under evaluation:

```sh
cd backend
set -a
. ../.env.local
set +a
export RUN_LIVE_EVALS=1
export AI_REQUEST_EXTRACTION_PROVIDER=vercel
export AI_REQUEST_EXTRACTION_MODEL=<gateway-model-id>
export EVAL_INPUT_USD_PER_MILLION=<input-rate>
export EVAL_OUTPUT_USD_PER_MILLION=<output-rate>
bundle exec ruby -Ieval eval/request_extraction_eval_test.rb
```

The runner writes detailed JSON, including raw and normalized outputs, under
`backend/tmp/eval-results/`. Before adding a result here:

1. Confirm the prompt version, fixture revision, workspace timezone, gateway,
   reasoning effort, and schema are unchanged.
2. Record the exact model identifier and the pricing rates used.
3. Report case and assertion scores separately. A case fails when any assertion
   or deterministic validation check fails.
4. Report input and output tokens, estimated cost, average/median/maximum
   request latency, total wall time, and retry count.
5. Inspect failures and classify them as extraction, schema compliance,
   provider/API, safety, or evaluator issues.
6. Preserve important caveats in the model's findings section rather than
   relying only on the aggregate score.

For a serious selection decision, run each model multiple times and report pass
rate and latency distributions across runs. The current corpus should also be
expanded before treating a one-assertion difference as meaningful.

## Run artifacts

The initial detailed reports are local, generated artifacts and are not tracked
by Git:

- Luna: `backend/tmp/eval-results/request-extraction-20260717T004253Z.json`
- Kimi K3: `backend/tmp/eval-results/request-extraction-20260717T004230Z.json`
- GLM 5.2: `backend/tmp/eval-results/request-extraction-20260717T032916Z.json`

## Adding another model

Append one row to the current comparison and add a short findings subsection
when a result has a caveat that is not apparent from the metrics. If the prompt,
fixtures, schema, reasoning effort, or evaluator changes, start a new comparison
table labeled with the new evaluation configuration rather than mixing results.
