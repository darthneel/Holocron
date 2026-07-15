# Step 6 Walkthrough

Step 6 introduces request extraction as a narrow, human-reviewed AI capability.

## Representative Flow

1. Staff choose `Extract email` and paste the original request text.
2. `POST /api/request-extractions` resolves the development actor and calls
   `RequestExtractions`.
3. `ModelRouter` selects the configured fake, Vercel, OpenAI, or OpenRouter provider.
4. The provider receives a versioned prompt and strict request-extraction schema.
5. Deterministic code validates the response and converts missing or ambiguous
   facts into review warnings.
6. The attempt and its audit event are stored together, even for failure or
   refusal outcomes.
7. A successful proposal fills the normal request form. Staff review and edit
   every field before submitting it.
8. `SchedulingRequests.create` verifies the extraction is successful and unused,
   then creates the request, relationships, workflow history, extraction link,
   and audit events in one transaction.

## Files

- `backend/db/migrations/008_create_request_extractions.rb` adds durable attempts
  and the optional unique scheduling-request link.
- `backend/lib/holocron/ai/model_router.rb` selects one provider and owns retry
  classification.
- `backend/lib/holocron/ai/providers/fake.rb` supplies deterministic local and test
  extraction.
- `backend/lib/holocron/ai/providers/responses.rb` implements Vercel AI Gateway,
  direct OpenAI, and OpenRouter Responses API calls.
- `backend/lib/holocron/request_extractions.rb` owns prompting, validation,
  persistence, serialization, and extraction audits.
- `backend/lib/holocron/scheduling_requests.rb` accepts one reviewed extraction
  through the existing domain transaction.
- `backend/app.rb` exposes extraction create and detail endpoints.
- `app/page.tsx` and `app/globals.css` add the paste and review workflow.
- `backend/test/app_test.rb` traces success, ambiguity, malformed output, refusal,
  retry, adversarial input, acceptance, replay, and real-provider parsing.
- `backend/eval/fixtures/request_extractions.json` contains synthetic live-model
  cases and deterministic field-level expectations.
- `backend/eval/request_extraction_eval_test.rb` runs those cases through the
  production prompt, schema, router, and normalizer without database writes.

## Live Evals

Live evals are intentionally separate from the deterministic test suite because
they use the network, consume credits, and can vary between model runs. Run the
full corpus with explicit billing confirmation:

```bash
RUN_LIVE_EVALS=1 backend/bin/eval-request-extraction
```

The Minitest report includes case and assertion pass rates, tokens, latency, and
estimated cost. Complete inputs, outputs, failures, provider identifiers, and
usage metrics are saved under the ignored `backend/tmp/eval-results/` directory.
The eval path does not create extraction, scheduling-request, relationship, or
audit records.

## Failure Cases

- Blank or oversized text returns `422` without a model attempt.
- A missing or inactive development actor cannot start an extraction.
- Provider configuration, transport, and server failures create failed attempts.
- A transient failure is retried once, then stored if it still fails.
- A refusal is stored distinctly from a malformed or transport failure.
- Structurally invalid model output is retained for diagnosis and cannot become a
  reviewable proposal.
- Missing domain-required facts remain warnings and must be fixed in review.
- A failed, refused, cross-workspace, or already accepted extraction cannot create
  a request.
- Any acceptance failure rolls back request, relationships, workflow, link, and
  audit writes together.
