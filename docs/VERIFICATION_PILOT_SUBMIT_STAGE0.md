# Pilot submission from Expo — Stage 0

**Status:** design only. No screen change, no migration, no grant, no case, no remote SQL, no deploy.
**Date:** 2026-10-12
**Revision:** cohort covers capabilities, queue, detail, and accept/reject; composition is postgres-only, validated, append-only, and frozen while a grant is `ACTIVE` or `SUSPENDED`; bootstrap links a composition-closed cohort in one transaction; claim screens wait until `041` is deployed.
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
| Ownership claim for one equine the requester already holds | `submit_my_equine_ownership_claim(equine, market, owner type, center, percentage, effective ownership id)`. A `PERSON` owner is the caller. The claim does not write `equine_ownerships`. | No call in `src/`. Propiedad de equinos only lists relations. | Server rules in `041` first. The screen is enabled only after that migration is deployed. |
| Management claim when the requester is the current manager | `submit_my_equine_management_claim(...)`. `p_valid_from` is `not null`. A null value becomes `42501`. `p_valid_until` may be null only when it is not earlier than `p_valid_from`. | No call in `src/`. | Same as ownership. The date must be copied from the current assignment, not invented in the client. |
| Valid effective date | Ownership has no date column on the claim. Currency is `equine_ownerships.status = 'ACTIVE'`, `ended_at` null, and `started_at <= now()`. Management currency is `status = 'ACTIVE'`, `valid_until` null, and `valid_from <= now()` (`031`). Trust later requires the accepted claim to point at that row and match its percentage or its `valid_from` / `valid_until` (`038`). | The list RPC used by Verificación returns every ownership and assignment for the person, including rows that are not currently effective. | The server does not enforce a current row yet. A later UI filter is presentation only. `041` must reject the stale row before that screen is enabled. |
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

Add an explicit cohort allow-list and make every reviewer operation honor it. Do not add `exp://**`, a client-supplied reviewer id, or a screen that grants review.

A reduced scope string alone, without a case allow-list, still means “all of Spain” under another name. Knowing a UUID is not membership. An empty queue is an extra observation, not the proof.

Proposed migration `041`, not written in this stage. `039` and `040` stay as they landed. `041` replaces the read, decision, submit, and bootstrap functions in a new file. It does not edit `036`–`040`.

### What the cohort authorizes

The cohort is the allow-list for capabilities, queue, detail, and every direct decision. These functions require an `ACTIVE` `MARKET` / `ES` grant whose `cohort_code` points at a cohort closed for composition:

- `get_my_review_capabilities`
- `list_my_review_queue`
- `get_my_review_case`
- `review_identity_case` for both `ACCEPTED` and `REJECTED`
- `review_equine_ownership_claim` for both `ACCEPTED` and `REJECTED`
- `review_equine_management_claim` for both `ACCEPTED` and `REJECTED`

Each decision function locks that grant again and checks the pair `(case_type, case_id)` against the same cohort before it reads or writes the dossier. `IDENTITY` uses the identity case id. `OWNERSHIP` and `MANAGEMENT` use the claim id.

A dossier outside the cohort cannot be listed, opened, accepted, or rejected. A direct call that already knows the UUID fails as not authorized (`42501`), the same as an unknown id, and is not audited as an open. Self-review stays denied inside the cohort: the reviewer cannot decide a case they submitted, own, manage, or cover through an active center affiliation.

A grant with a null cohort, or any legacy `MARKET` / `ES` row that has no cohort, matches nothing. It grants zero capabilities, zero queue rows, zero detail, and zero decisions. `verification_lock_spain_review_grant` returns null for that row.

`SUSPENDED` and `ENDED` already stop matching in `039`. `041` keeps that. Suspending or closing the grant cuts capabilities, queue, detail, and decisions immediately. It does not delete the cohort or its history.

### How a cohort is composed

Application roles, including `authenticated` and `service_role`, get no `INSERT`, `UPDATE`, or `DELETE` on the cohort tables. The app never chooses the cohort. Case ids stay in the private operator notebook, not in Git.

Only `postgres` functions may create a cohort, add a dossier, or close composition. Adding a dossier validates, in the same statement, that the id exists, the market is `ES`, the state is incorporable (`SUBMITTED`, `IN_REVIEW`, or `RESUBMITTED`), and `case_type` matches the table that holds that id. A missing UUID or a wrong `case_type` is rejected. There is no unvalidated polymorphic pointer.

Membership is unique on `(case_type, case_id)`, so one dossier belongs to one cohort. A concurrent add of the same dossier to two cohorts leaves exactly one membership.

Every create, add, and composition close is an append-only history row: event, `session_user`, timestamp, cohort code, and the real case type and case id when the event names a dossier. History rows are not updated or deleted. Suspending or closing a grant does not remove them.

Composition has two states, `OPEN` and `CLOSED`. Adds are allowed only while composition is `OPEN` and no grant for that cohort is `ACTIVE` or `SUSPENDED`. Closing composition is explicit and audited. After it is `CLOSED`, the set cannot grow.

While any grant linked to the cohort is `ACTIVE` or `SUSPENDED`, the set cannot grow or shrink. There is no silent add and no silent remove. Changing the set means ending that grant (`ENDED`), leaving that cohort closed, and creating a new audited cohort. A suspended grant is not reactivated, which matches `039`.

### Bootstrap

`bootstrap_verification_review_grant` must not insert a grant with `cohort_code` null and fill it in later. The revised function receives the reviewer person and a cohort whose composition is already `CLOSED`, checks `MARKET` / `ES`, and inserts the linked grant in that same transaction. `EXECUTE` stays revoked from `authenticated`. This stage does not call it.

### Submit constraints, enforced in PostgreSQL first

Client checks on currency and dates are presentation. They are not the security boundary. Before any claim screen is enabled, `041` must already enforce:

- one open case per caller, equine, market, and claim kind, including two concurrent submits, so exactly one `SUBMITTED` row remains;
- the same exclusion for a second open identity case for the same person and market (`037` does not guarantee it today);
- when `effective_ownership_id` or `effective_assignment_id` is set, the row is that caller’s, on that equine, and currently effective;
- for management, `p_valid_from` and `p_valid_until` equal that assignment’s window;
- a historical or future row is rejected.

The client copies the current row’s window. It does not choose `now()`.

## Architecture

```text
Requester Expo session (auth.uid)
  -> submit_my_identity_case('ES')                    already shipped
  -> submit_my_equine_ownership_claim(current row)    screen only after 041 is deployed
  -> submit_my_equine_management_claim(current row)   screen only after 041 is deployed
        |
        v
  open case rows, still invisible to the reviewer
        |
        v
postgres adds each validated dossier to an OPEN cohort
  and appends an audit row
        |
        v
postgres closes composition; the set can no longer change
        |
        v
bootstrap inserts one MARKET / ES grant linked to that closed cohort
  in the same transaction
        |
        v
capabilities, queue, detail, accept, and reject
  all require that grant and that cohort membership
```

The reviewer UI (`Revisión piloto`) stays read-only in the pilot smoke. It appears only when `get_my_review_capabilities` returns the single linked `MARKET` / `ES` row. A grant without a cohort leaves that entry hidden. Until the grant exists, the entry stays hidden, which matches the observation that the reviewer has no grant.

Claim screens live on Verificación, not on the reviewer stack. They are not enabled until `041` is integrated and deployed. They list only currently effective `PERSON` rows for the signed-in requester, default the market to Spain, send percentage and role from that row, and send the effective id. Management sends the row’s `valid_from` and `valid_until`. There is one primary action per row, behind the same synchronous in-flight gate identity already uses. That gate is UX. The unique open-case rule in PostgreSQL is what makes two concurrent submits one case.

Status after submit: the relation shows `Solicitud pendiente` while that caller has an open claim for that effective row, and still `No verificada` as the trust result. The notice says the claim was recorded and does not verify the equine, transfer it, or enable publication, bookings, or payments.

Errors stay generic unless a later migration returns a stable code. Suggested codes, mapped in the client without showing SQL: `not_current_relation`, `invalid_effective_window`, `duplicate_open_claim`, `market_not_selectable`. Until those codes exist, every claim failure uses the current generic verification sentence.

Account switch: `useReviewPilot` already clears queue and detail when the auth user id changes. `useVerification` sequences requests and drops a result after blur, but it does not clear the snapshot at the moment the user id changes. The claim-screen phase clears that snapshot synchronously, keys the sequence by user id, and ignores a late response from the previous account. The product owner’s switch did not show the requester’s equines on the reviewer; that phase keeps that true on Verificación as well.

The pilot still uses two different accounts. The requester must not receive the grant. The reviewer must not submit the pilot claims.

## Phases and dependencies

| Phase | Work | Depends on | Grant |
| --- | --- | --- | --- |
| 0 | This note. | None. | Not allowed. |
| 1 | Migration `041` and its SQL tests: cohort authorization of capabilities, queue, detail, and decisions; audited composition; atomic bootstrap; current-row, window, and one-open-case constraints. | This note reviewed. | Still not allowed. |
| 2 | Expo claim UI, pending claim state, account-switch clear, single-flight submit, tests. | `041` integrated and deployed on the target database. A stacked branch may be written earlier. It must not merge or ship before that deploy. | Still not allowed. |
| 3 | Private operator steps, outside Git: requester submits; `postgres` adds only those dossiers, closes composition, and the local tests prove an outside dossier cannot be read or decided. | Phases 1 and 2 on the target database. | Only a later train, and only through the atomic bootstrap of a composition-closed cohort. |
| 4 | Read-only reviewer smoke, then suspend and close. No accept and no reject in that smoke. | Phase 3. | The grant exists only for that smoke and is closed afterwards. History remains. |

The claim screens are not enabled before the server constraints in `041` are integrated and deployed. Creating the grant before that proof is still a NO-GO. A grant without a cohort is not a temporary step.

PR #62 is not a dependency. Its remaining check is a signup smoke after the mail limit lifts. This stage does not create an account.

## Tests required before a grant

App tests, without a remote project, and only after the claim screens exist:

- one press sends one ownership call and one management call; a second press does not;
- a rapid switch of auth user drops the previous snapshot and does not apply its late response;
- only a currently effective row is offered; an ended or future row is not;
- management submits the row’s `valid_from`, not the clock at tap time;
- identity `Solicitud pendiente` and a new claim `Solicitud pendiente` stay distinct from `Verificada`;
- the generic error does not contain SQL, a uuid, or a table name;
- the reviewer menu stays hidden when the capability call returns no row, including a grant whose cohort is null.

SQL tests for `041`, local only:

- an in-cohort open Spain case is listed and can be opened;
- an out-of-cohort open Spain case yields no capability for that dossier, is listed nowhere, and `get_my_review_case` returns `42501` even when the caller passes its UUID;
- `review_identity_case`, `review_equine_ownership_claim`, and `review_equine_management_claim` return `42501` for that outside UUID with `ACCEPTED` and again with `REJECTED`;
- the same three functions return `42501` for self-review of a dossier that is inside the cohort;
- a grant with a null cohort, and a legacy `MARKET` / `ES` grant with no cohort, return no capabilities, no queue row, no detail, and no decision;
- suspending the grant cuts capabilities, queue, detail, and both outcomes immediately, and the cohort history rows are still present;
- closing the grant does the same, and the cohort history rows are still present;
- a missing UUID or a `case_type` that does not match the row is rejected and writes no membership;
- two concurrent adds of the same dossier to two cohorts leave exactly one membership;
- two concurrent submits of the same identity, ownership, or management relation leave exactly one open case;
- a claim against an ended or future effective row is rejected;
- a management claim whose window differs from that row is rejected;
- while a linked grant is `ACTIVE` or `SUSPENDED`, adding or removing a dossier is rejected;
- `authenticated` and `service_role` cannot insert, update, or delete cohort or history rows, and cannot bootstrap a grant;
- bootstrap refuses a cohort that is still `OPEN`, and the successful bootstrap inserts the grant and its cohort link in one transaction.

No remote SQL, no real case, no real cohort, and no grant are part of those tests.

## Decision on migration 041

Yes. It is required before the reviewer grant and before the claim screens are enabled. The current `MARKET` / `ES` path authorizes every open Spain dossier for read and for `review_identity_case`, `review_equine_ownership_claim`, and `review_equine_management_claim`. It cannot express “only these pilot dossiers.” The submit path does not refuse a stale effective row, a mismatched management window, or a duplicate open claim. Frontend checks are not a substitute.

`041` is not authorized by this pull request. Do not add the file until a later train says so. Do not edit `036`–`040`.

## Out of scope

- Applying remote templates, creating accounts, granting review, or deciding a case.
- A one-time-code mail flow. That belongs to auth, not to this verification train.
- Evidence upload, KYC, publication, bookings, and payments.
- Changing PR #62.
