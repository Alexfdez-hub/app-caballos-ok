# Verification cohort migration 041

**Status:** local migration and tests. No remote SQL, no grant, no pilot dossier, no claim screen.
**Base:** `origin/main` `5e9b313adcd48da1699831e20add8b687907d6e8`.

`041` is the server boundary described in `docs/VERIFICATION_PILOT_SUBMIT_STAGE0.md`.

- A `MARKET` / `ES` grant authorizes only dossiers in its closed cohort.
- `get_my_review_capabilities`, `list_my_review_queue`, `get_my_review_case`, and accept/reject for identity, ownership, and management all require that grant and that membership. A known UUID outside the cohort fails with `42501`.
- Cohort create, add, and composition close are postgres functions. Application roles cannot mutate the tables. History is append-only and stores `session_user`.
- Composition does not reopen. A closed cohort does not take new dossiers. Membership is not updated or deleted, including while a linked grant is `ACTIVE` or `SUSPENDED`.
- `bootstrap_verification_review_grant(person, cohort)` inserts the grant already linked to a `CLOSED` cohort. A null or legacy grant authorizes nothing.
- Suspending or closing the grant cuts capabilities, queue, detail, and decisions immediately and leaves the cohort history in place.
- One open identity case per person and market. One open ownership or management claim per submitter, equine, and market. An effective row must be current; a management window must match that row.

Claim screens stay disabled until this migration is reviewed and deployed. This pull request does not deploy it.

Local proof is `npm run test:verification-cohort` after `supabase db reset`. Existing verification suites cover the previous contracts against this schema. `supabase db reset` replays `041` from an empty local database.
