# Pilot submission from Expo — Stage 0

**Status:** design only. No screen change, no migration, no grant, no case, no remote SQL, no deploy.
**Date:** 2026-10-12
**Base:** `origin/main` `fb1b164d92c93ee0a6d1e316e9dc0cf8357628c3`.
**Issue:** #61. This note does not close it and does not authorize the reviewer grant.

PR #62 stays a separate draft. This stage does not depend on creating another Auth account.

The two pilot accounts below are roles, not identifiers. No address, name, or id is recorded here.

## What the pilot observation already shows

These facts come from the product owner’s use of the app. This stage did not query remote Supabase.

- The requester has a completed profile, existing equines, and verification still pending on the Verificación screen.
- The future reviewer has a completed profile, given name, family name, and country Spain.
- The reviewer has no equines, ownership, management, or equine responsibility, and has no review grant. This stage does not give one.
- After signing out of the requester and into the reviewer, the reviewer’s screens did not show the requester’s data or equines.

“Pending” here matches the current presentation: identity `No verificada` or `Solicitud pendiente`, and each listed relation `No verificada`. It is not evidence that a case row already exists. This stage does not create, accept, or reject a case.

## Inventory

Migrations `036`–`040` are already on this base. The client can read status and submit an identity case. It cannot submit an equine claim.

| Need | Server today | Expo today | Gap |
| --- | --- | --- | --- |
| Identity verification for Spain | `submit_my_identity_case(p_market_country_code)` inserts `SUBMITTED` for `auth.uid()`. `list_my_identity_cases` and `list_my_verification_status` read the caller only. | Verificación shows `Solicitar verificación` and the notice `Solicitud registrada. Tu identidad no queda verificada con este envío.` A second press is ignored while `inFlight` is set. | No new RPC. The requester can submit when that button is shown (`canRequest` for `No verificada` or `No aceptada`). An open case hides the button and shows `Solicitud pendiente`. |
| Ownership claim for one equine the requester already holds | `submit_my_equine_ownership_claim(equine, market, owner type, center, percentage, effective ownership id)`. A `PERSON` owner is the caller. The claim does not write `equine_ownerships`. | No call in `src/`. Propiedad de equinos only lists relations. | Frontend, plus the server rules in the proposed migration below. |
| Management claim when the requester is the current manager | `submit_my_equine_management_claim(...)`. `p_valid_from` is `not null`. A null value becomes `42501`. `p_valid_until` may be null only when it is not earlier than `p_valid_from`. | No call in `src/`. | Same as ownership. The date must be copied from the current assignment, not invented in the client. |
| Valid effective date | Ownership has no date column on the claim. Currency is `equine_ownerships.status = 'ACTIVE'`, `ended_at` null, and `started_at <= now()`. Management currency is `status = 'ACTIVE'`, `valid_until` null, and `valid_from <= now()` (`031`). Trust later requires the accepted claim to point at that row and match its percentage or its `valid_from` / `valid_until` (`038`). | The list RPC used by Verificación returns every ownership and assignment for the person, including rows that are not currently effective. | The submit UI may offer only a currently effective row. The server does not enforce that yet. |
| Understandable state and errors | Submit failures raise `42501` with `Verification request is not available`. There is no partial unique index against a second open claim. | `userFacingVerificationMessage` always returns `No se pudo completar la verificación. Inténtalo de nuevo.` It does not echo SQL. It also does not say whether the date, the relation, or a duplicate submit failed. Relation rows never show `Solicitud pendiente`; only identity cases do. | Frontend copy for claim state, and stable server codes if a later migration adds them. Until then, do not parse the SQL message. |

`create_my_equine` already attaches the creating person as 100% `PERSON` owner and `PRIMARY_MANAGER`. The pilot claim should corroborate that current row (`effective_ownership_id` or `effective_assignment_id` set). A claim with those ids null does not make `verification_ownership_is_verified` or `verification_management_is_verified` true, even if a later decision is `ACCEPTED`.

Review read is unchanged and is not a submit API: `get_my_review_capabilities`, `list_my_review_queue`, and `get_my_review_case` (`040`). The queue is every open Spain case in `SUBMITTED`, `IN_REVIEW`, or `RESUBMITTED`, at most 50, excluding self-review and an active center affiliation. The queue row has no name. Opening a case returns the minimum person name and, for an equine, the equine name.

`bootstrap_verification_review_grant` (`039`) writes `MARKET` / `ES` / `ACTIVE` and does not accept a case list. `EXECUTE` is revoked from `authenticated`. This stage does not call it.

## Why an empty queue is not the control

Issue #61 required a private count of zero open Spain cases before the first grant. That count is a point in time. It is not a constraint:

- another Spain case can be submitted after the count and before or during review;
- the grant still authorizes every open Spain case, not the three pilot dossiers;
- opening a case reveals a name and an equine name;
- a later empty screen only shows that the reviewer saw nothing then. It does not prove other dossiers were unreachable.

The reviewer’s current lack of equines is also not the control. It avoids self-review of an equine claim. It does not hide anyone else’s Spain case.

## Proposed isolation

Add an explicit cohort allow-list and make the existing Spain grant honor it. Do not add `exp://**`, a client-supplied reviewer id, or a screen that grants review.

Proposed migration `041`, not written in this stage:

1. `verification_review_cohorts (code text primary key)` and `verification_review_cohort_cases (cohort_code, case_type, case_id)` with `case_type in ('IDENTITY','OWNERSHIP','MANAGEMENT')` and a unique `(case_type, case_id)`.
2. Nullable `verification_review_grants.cohort_code`. For this pilot, an `ACTIVE` `MARKET` / `ES` grant must have a cohort. A grant without one must not match `verification_lock_spain_review_grant`.
3. `list_my_review_queue` and `get_my_review_case` keep today’s market, state, self-review, and center checks, and add membership in that grant’s cohort. A case outside the cohort fails like an unknown id (`42501`) and is not audited as an open.
4. Cohort rows are inserted only by `postgres`, after the requester has submitted, and only for those case ids. The app never chooses the cohort. Ids stay in the private operator notebook, not in Git.
5. One open claim per caller, equine, market, and claim kind, so a double press cannot create two `SUBMITTED` rows. Identity keeps its current “button hidden while a case is open” rule; a second open identity case for the same person and market should get the same exclusion if `037` does not already guarantee it.
6. When `effective_ownership_id` or `effective_assignment_id` is set, the row must be that caller’s, on that equine, and currently effective. For management, `p_valid_from` and `p_valid_until` must equal the assignment window. A historical or future row is rejected. The client copies those values; it does not choose `now()`.

A reduced scope string alone, without a case allow-list, still means “all of Spain” under another name. The allow-list is the verifiable mechanism. After `041`, a SQL test inserts one in-cohort case and one out-of-cohort case and asserts that only the in-cohort id is listed and openable. An empty queue is an extra observation, not the proof.

`039` and `040` stay as they landed. `041` replaces the read and submit functions in a new file. It does not edit `036`–`040`.

## Architecture

```text
Requester Expo session (auth.uid)
  -> submit_my_identity_case('ES')                    already shipped
  -> submit_my_equine_ownership_claim(current row)    new screen, existing RPC
  -> submit_my_equine_management_claim(current row)   new screen, existing RPC
        |
        v
  open case rows, still invisible to the reviewer
        |
        v
postgres inserts those ids into the pilot cohort     private, not Git
        |
        v
041 queue/detail require cohort membership
        |
        v
only then may a later train call the grant bootstrap for the reviewer
```

The reviewer UI (`Revisión piloto`) stays read-only. It appears only when `get_my_review_capabilities` returns the single `MARKET` / `ES` row. Until the grant exists, that entry stays hidden, which matches the observation that the reviewer has no grant.

Claim screens live on Verificación, not on the reviewer stack. They list only currently effective `PERSON` rows for the signed-in requester, default the market to Spain, send percentage and role from that row, and send the effective id. Management sends the row’s `valid_from` and `valid_until`. There is one primary action per row, behind the same synchronous in-flight gate identity already uses.

Status after submit: the relation shows `Solicitud pendiente` while that caller has an open claim for that effective row, and still `No verificada` as the trust result. The notice says the claim was recorded and does not verify the equine, transfer it, or enable publication, bookings, or payments.

Errors stay generic unless a later migration returns a stable code. Suggested codes, mapped in the client without showing SQL: `not_current_relation`, `invalid_effective_window`, `duplicate_open_claim`, `market_not_selectable`. Until those codes exist, every claim failure uses the current generic verification sentence.

Account switch: `useReviewPilot` already clears queue and detail when the auth user id changes. `useVerification` sequences requests and drops a result after blur, but it does not clear the snapshot at the moment the user id changes. The next phase clears that snapshot synchronously, keys the sequence by user id, and ignores a late response from the previous account. The product owner’s switch did not show the requester’s equines on the reviewer; this phase keeps that true on Verificación as well.

Self-review stays in `040`: the reviewer cannot open a case they submitted, own, manage, or cover through an active center affiliation. The pilot still uses two different accounts. The requester must not receive the grant. The reviewer must not submit the pilot claims.

## Phases and dependencies

| Phase | Work | Depends on | Grant |
| --- | --- | --- | --- |
| 0 | This note. | None. | Not allowed. |
| 1 | Expo claim UI, pending claim state, account-switch clear, single-flight submit, tests. Calls the RPCs that already exist. | This note reviewed. | Still not allowed. A claim can be submitted, but the reviewer must not be granted yet. |
| 2 | Migration `041` and its SQL tests: cohort allow-list, current-row and date checks, one open claim. | Phase 1 is not required for the migration, but the grant waits for both. | Still not allowed. |
| 3 | Private operator steps, outside Git: requester submits from Expo; `postgres` inserts only those case ids into the cohort; the SQL test fixture proves an outside case stays hidden. | `041` applied on the target database. | Only a later train, after that proof. |
| 4 | Read-only reviewer smoke, then suspend and close. No accept and no reject in that smoke. | Phase 3. | The grant exists only for that smoke and is closed afterwards. |

Phase 1 does not isolate the queue. Shipping the screen before `041` is acceptable only while the grant remains absent. Creating the grant before `041` is still a NO-GO.

PR #62 is not a dependency. Its remaining check is a signup smoke after the mail limit lifts. This stage does not create an account.

## Tests required before a grant

App tests, without a remote project:

- one press sends one ownership call and one management call; a second press does not;
- a rapid switch of auth user drops the previous snapshot and does not apply its late response;
- only a currently effective row is offered; an ended or future row is not;
- management submits the row’s `valid_from`, not the clock at tap time;
- identity `Solicitud pendiente` and a new claim `Solicitud pendiente` stay distinct from `Verificada`;
- the generic error does not contain SQL, a uuid, or a table name;
- the reviewer menu stays hidden when the capability call returns no row.

SQL tests for `041`, local only:

- an in-cohort open Spain case is listed and can be opened;
- an out-of-cohort open Spain case is listed nowhere and opens as `42501`;
- the requester cannot open their own case even if it is in the cohort;
- a grant with a null cohort matches nothing;
- a claim against an ended or future effective row is rejected;
- a management claim whose window differs from that row is rejected;
- a second open claim for the same caller, equine, market, and kind is rejected;
- `authenticated` cannot insert cohort rows or bootstrap a grant.

No remote SQL, no real case, and no grant are part of those tests.

## Decision on migration 041

Yes. It is required before the reviewer grant. The current `MARKET` / `ES` read path cannot express “only these pilot dossiers,” and the submit path does not refuse a stale effective row, a mismatched management window, or a duplicate open claim. Frontend checks are not a substitute.

`041` is not authorized by this pull request. Do not add the file until a later train says so. Do not edit `036`–`040`.

## Out of scope

- Applying remote templates, creating accounts, granting review, or deciding a case.
- A one-time-code mail flow. That belongs to auth, not to this verification train.
- Evidence upload, KYC, publication, bookings, and payments.
- Changing PR #62.
