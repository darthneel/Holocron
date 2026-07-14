# ADR 003: Conservative Relationship Resolution

## Status

Accepted for Step 4.

## Decision

People are resolved automatically only by an exact case-insensitive email match
inside one workspace. A display-name match is never sufficient to merge people.
Organizations are resolved by a normalized name that removes punctuation,
collapses whitespace, and compares case-insensitively.

Scheduling-request writes synchronize explicit links to canonical people in the
same transaction as the request. A person stores zero or one current
organization directly. Intake may fill that value when it is empty, but a
different organization for an exact-email match is rejected rather than
silently replacing it. Existing canonical records are not renamed by later
intake text. Interactions retain provenance rather than treating inferred
context as user-authored data.

## Consequences

- Repeat requesters with the same email converge on one person record.
- Two people with the same name remain separate without a stable identifier.
- Staff may see intentional duplicates that need later manual resolution.
- Organization aliases and manual merge tooling remain future work.
- Organization and role history are intentionally not represented in this exercise.
- Conflicting organization data must be resolved explicitly before intake succeeds.
