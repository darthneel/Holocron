# ADR 005: Human-Reviewed Request Extraction

## Status

Accepted for Step 6.

## Decision

AI request extraction is a proposal-producing boundary, not a domain-write path.
Every call creates a durable `request_extractions` record containing the original
input, provider, model, prompt version, outcome, validated output, warnings,
attempt count, and operational metadata. Successful, failed, and refused calls
write synchronous audit events.

A small task router selects a deterministic fake, Vercel AI Gateway, direct
OpenAI, or optional OpenRouter provider. Vercel is the recommended hosted path
because it preserves Responses API and Structured Outputs compatibility while
centralizing model access and billing. The router does not fall back across
providers. Real providers use strict Structured Outputs and low reasoning effort.
Only transient failures receive one retry.

Staff must review and may edit every successful proposal in the normal request
form. Acceptance calls `SchedulingRequests.create`; the model never calls domain
services. The request, canonical relationship context, initial workflow state,
extraction link, and audit events commit in one transaction. The service forces
the request source to email and restores the retained extraction input regardless
of client payload. One extraction can be accepted at most once.

## Consequences

- Probabilistic output cannot independently create people, organizations,
  requests, workflow history, or external actions.
- Incomplete valid output remains useful because unknown facts become review
  warnings rather than fabricated defaults.
- Provider failures and refusals are observable without polluting domain tables.
- Provider selection remains simple and evaluation-friendly.
- Synchronous model calls may become a latency concern; Step 8 can move them to
  durable background execution without changing the acceptance boundary.
- Retaining original email text requires future privacy, retention, and access
  controls before production use.
