# Step 4 Walkthrough

Step 4 turns request intake into reusable relationship context.

1. Staff create or edit a scheduling request.
2. The request transaction resolves requester and participant emails to
   canonical people.
3. Organization names resolve through a normalized-name key.
4. A new person receives that organization, and an existing person receives it
   only when their current organization is empty.
5. A conflicting organization on an exact-email match rejects and rolls back
   the request so staff can resolve the person explicitly.
6. Explicit link rows record each person's role on the request. Organization
   context is derived through the linked people.
7. The inbound request becomes a sourced interaction authored by the staff
   member who recorded it.
8. Request details load prior interactions for every linked person, while the
   Relationships workspace supports manual additions and organization assignment.

The relationship write APIs require the development actor header. People,
organizations, interactions, request links, and audit events commit
synchronously through SQLite transactions.
