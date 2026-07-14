# Step 2 Walkthrough

The browser signs in through the existing fake-session endpoint, then loads the
foundation data and scheduling-request inbox. A known workspace member can open
the request composer, which sends the same email in the development actor
header for every create or edit.

`backend/app.rb` owns the HTTP routes and actor-header boundary.
`backend/lib/holocron/scheduling_requests.rb` validates the complete intake
payload, replaces child participant/window rows on edits, and creates the audit
event in the same transaction. Migration `002` adds the three intake tables and
their foreign keys, role/source checks, duration constraint, and candidate-time
constraint.

`app/page.tsx` contains the inbox, detail panel, and request composer. It keeps
form state local, sends only JSON to the API, and renders field errors returned
by the backend. `app/globals.css` adds the compact operational layout and its
responsive behavior.

Covered failure cases include a missing or unknown actor, malformed JSON,
missing required fields, invalid duration, invalid scheduler, invalid candidate
windows, unknown request IDs, and failed validation without a partial request
or audit event.
