# Reviewer bootstrap and grant administration — Stage 4B.1

**Status:** design only. No screen, no grant row, no migration, no Edge Function, no script, no deploy.
**Date:** 2026-10-08
**Base:** `origin/main` `1b42764446ea7cdae223172ceed6a3aa7151e233` (Stage 4B documentation, PR #56).
**Remote:** project `efkauegdlmfkonzwyyiv` stays at exact version `038`.

This document decides how the first reviewer permission could be created for a technical pilot, and how later administration must differ from that first step. It does not create the permission.

The boundary in `docs/VERIFICATION_REVIEWER_UI_STAGE4B.md` stays in force: a pseudonymous queue, a re-authorized opening, a short-lived signed evidence URL, and a re-authorized decision. The first review scope remains `MARKET` / `ES`. A hípica role is not review authority. The mobile app has no superadministrator. Migration `039` is not authorized.

## Pilot rules this design starts from

- The technical pilot uses fictional data only.
- One internal account is dedicated to review. It is not the applicant's normal account.
- The Product Owner may sign in to that dedicated account while debugging. That does not authorize review of a real person's identity or documents.
- The first grant, when a later train is allowed to create it, is only `scope_type = 'MARKET'` and `market_country_code = 'ES'`.
- The reviewer account must be an `ACTIVE` `user_accounts` row whose `persons` row is also `ACTIVE`.
- The normal account and the reviewer account are different Auth users. `user_accounts.auth_user_id` and `user_accounts.person_id` are each unique, so they are also different PERSON rows.
- A person cannot review their own request. `037` already refuses the subject, the submitter account, the named owner or manager, and an active member of the claimant center.
- No center role and no hípica affiliation grants review.
- This repository stores no email, personal UUID, password, token, or other concrete identifier of the Product Owner or of the test reviewer.
- Moving from fictional data to real users requires a KYC provider, an operating procedure, and a legal and privacy review.

## What exists today

Signup inserts `auth.users` and the existing integration creates a new PERSON and a new ACCOUNT. That is how a second test account can exist. It does not make that account a reviewer.

Review authority is only an `ACTIVE` row in `verification_review_grants`. `verification_review_grant_matches` accepts:

- `PLATFORM_IDENTITY` with a null market, every identity case;
- `PLATFORM_EQUINE` with a null market, every equine claim;
- `MARKET` plus one country, both identity cases and equine claims in that country.

An active row must have `valid_until` null. The only other status is `ENDED`, which requires `valid_until`. There is no suspend status, no request status, and no actor column. Nothing stops a second `ACTIVE` row for the same person and scope. The table has no append-only trigger. The database owner can insert, update, or delete a row. `authenticated` cannot.

`record_audit_event` is the product audit writer. Its trigger calls `resolve_session_caller()`, which reads `auth.uid()` and refuses a null session. The trigger overwrites `actor_account_id` and `actor_person_id` from that session. A successful `review_*` call writes an audit row because it runs as the signed-in reviewer. A refused review raises `42501` before that write, so a denial is not an `audit_events` row today.

There is no product administrator. Center first-admin bootstrap was left undefined on purpose in the membership work. `users.role`, JWT `user_metadata`, a center role, the Supabase Dashboard, and `service_role` are not a review grant and are not a grant administrator. `service_role` appears in the equine-photo server path. That path is not a pattern for grants, and Expo must not receive that key.

## The bootstrap paradox

A review grant needs an authority that may create it. No such authority exists inside the product. The reviewer account must not be able to create it for itself, or it becomes its own administrator. Expo must not be the place that breaks the circle. A hidden mobile superadministrator would be the same circle with a broader scope.

The authority that creates the first grant therefore has to sit outside the product permission graph. After that, ordinary changes need a different authority, so the break-glass path does not become the daily path.

## Alternatives

### A. Manual action by the database owner

The owner runs a controlled statement from the Supabase SQL editor or CLI and inserts the first grant.

Simplicity is high, and there is no public screen. The statement is not in Git. The values are typed at operation time.

Traceability inside the product is absent. The SQL session has no `auth.uid()`. `record_audit_event` rejects that session, and a hand-written `audit_events` insert is overwritten or refused by the same trigger. A Dashboard history, if the host keeps one, is not `audit_events`: it is not the product actor, and it is not protected by the append-only trigger. An in-place `UPDATE` to `ENDED` also leaves no product event and replaces the previous state.

Human error can select the wrong person, set `PLATFORM_IDENTITY`, or set a market other than `ES`. The step is not repeatable as a checked operation. Revocation is another manual update, with the same audit gap. This shape is acceptable only as a one-time break-glass, and only after the product can record it. It is not the habitual administration.

### B. Administrative script outside Expo

A local or CI script uses server credentials and receives the reviewer identifier.

Secret custody is the first problem. A `service_role` key on a laptop or in CI can change the database without an Auth session. Identification of the operator then depends on who holds the key, not on `auth.uid()`. The script can check that the PERSON and ACCOUNT are `ACTIVE`, and it can refuse to grant the caller's own person, but the person who can edit the script can remove those checks. Committed to this repository, or wired into CI, the script is a back door. It is not the pilot path. Expo must not call it.

### C. Authenticated server administration

A future Edge Function or RPC grants, suspends, and closes grants for an administrative authority that already exists.

The actor comes from `auth.uid()` through the existing account resolution, never from an id in the request. Suspension and closure append history. Rotation means a second designated administrator, not a self-service reset. Expo does not hold `service_role`.

This cannot create the first authority. Someone still has to designate the first grant administrator. Storing that designation in `verification_review_grants` would confuse a reviewer with the person who appoints reviewers. The two permissions stay separate. A review grant never implies grant administration.

This is the ordinary path later. It is not available to a normal user or to a hípica role. It is not implemented in this train.

### D. Wait for an external backoffice

Full administration can wait for a provider or backoffice. That is the right gate before real users. It is a poor fit for the fictional technical pilot: the pilot needs one designated test reviewer, not a vendor, and waiting would either block the fictional account or invite an unaudited manual insert.

## Recommendation

Use A only as the exceptional bootstrap, and C only as later ordinary administration. Do not use B. Use D as the gate before real users, not as a substitute for the fictional bootstrap.

The schema does not allow the exceptional bootstrap to be audited today. That blocks creating the grant. It does not block recording this direction.

### Blocker

A database-owner session cannot write a truthful `audit_events` row. `resolve_session_caller()` requires `auth.uid()`. Forging a JWT claim in the SQL editor would choose the actor by hand, which is the failure the audit trigger exists to prevent. Until a later reviewed change can record a database-owner action without a client-supplied actor, no one inserts a `verification_review_grants` row.

### Exceptional bootstrap, after that change and not before

- Run only by the technical owner of the database.
- Run outside Expo.
- Type the target account at operation time. Do not commit it.
- Target one fictional reviewer account, already `ACTIVE`, with an `ACTIVE` PERSON, and different from the applicant account.
- Force `MARKET` and `ES`. Refuse `PLATFORM_IDENTITY`, `PLATFORM_EQUINE`, and any other market.
- Append an audit event in the same transaction as the grant row.
- The event's actor is the database-owner session, not an ACCOUNT id passed into the statement.
- The reviewer account receives no ability to insert, alter, or close grants, including its own.

The same break-glass path is how that one test grant is later suspended or closed during the fictional pilot. The pilot does not gain an in-product grant administrator.

### Ordinary administration, later and not in this train

- An authenticated server operation.
- The grant administrator is a different permission from the reviewer, resolved from Auth.
- Grant, suspend, and close append immutable history.
- A normal user and a hípica role cannot call it.
- It is not built until a later security review. The reviewer created by the bootstrap cannot appoint that administrator.

## State model

These events are the minimum vocabulary. They are names for the design, not a frozen `event_type` catalog.

| Event | Meaning |
| --- | --- |
| Grant requested | Someone asked for review authority. The pilot does not accept self-service requests. |
| Grant granted | An authority outside the reviewer created one `MARKET` / `ES` grant for a designated PERSON. |
| Grant suspended | The grant stops matching immediately, and the history keeps the previous grant. This is not deletion. |
| Grant closed | The grant is finished. Closing is not a resume. A later grant is a new event. |
| Attempt rejected | A grant or self-grant request was refused. The refusal is itself an event. |
| Review access refused after suspension | A suspended or closed reviewer tried to list, open, read evidence, or decide. The refusal is an event. The current `review_*` functions do not write this; they raise `42501` and roll back. |

`verification_review_grants` can store only the current projection of "granted" (`ACTIVE`, `valid_until` null) or "closed" (`ENDED`, `valid_until` set). It cannot store a request, a suspension distinct from closure, a rejected attempt, a refused review, or who did it. An `UPDATE` replaces that projection. A future migration needs a separate append-only event history. The current row may be updated only in the same transaction as the new event, by that server path. This train does not add the table and does not alter `036`–`038`.

`verification_review_grant_matches` treats only a current `ACTIVE` row as authority. After a real suspension or closure, the next queue, open, evidence, and decision call must see no match. A signed URL already issued can still work until its TTL. That TTL is the longest remaining exposure. The evidence function, when it exists, must not sign a new URL after the grant ceases to match.

## Threat model

| Threat | How this design treats it |
| --- | --- |
| Self-registration as a reviewer | Signup creates an ACCOUNT and a PERSON only. No client insert exists on `verification_review_grants`. |
| Self-grant | The reviewer permission does not include grant administration. The bootstrap statement refuses a target that is the operator's own review account granting itself a wider scope. Expo cannot call the bootstrap. |
| Escalation from a hípica role | Center membership never matches `verification_review_grant_matches`. An active member of the claimant center is refused by `review_*`. |
| Misuse of `service_role` | The key stays off the device. Alternative B is not the pilot path. Photo-server use of `service_role` is not copied onto grants. |
| Leak of the reviewer email or UUID | Those values are typed at operation time and are not committed. Audit metadata stays within the existing safe-metadata rules: no secrets, no document bodies. |
| Compromised reviewer account | Close or suspend the grant by the break-glass path, and mark the ACCOUNT or PERSON inactive so `verification_resolve_caller()` fails closed. The reviewer still cannot appoint a replacement. |
| Grant still active after suspension | The match reads current `ACTIVE` rows. Suspension must remove that match in the same transaction as the event. A second hidden `ACTIVE` row must be refused. |
| Signed URL issued before suspension | It may survive until TTL. No new URL is signed afterwards. |
| Two administrators, one grant | The later ordinary path locks the grant, appends one event, and updates the projection only if the state is still the expected one. The loser fails closed. The pilot has no second in-product administrator. |
| Deleted or rewritten history | `audit_events` already refuses update and delete. Grant events need the same rule. The database owner must not `DELETE` the grant row as a way to hide it. |
| Fictional pilot pointed at real people | The bootstrap is refused as an operating rule unless the target is the dedicated fictional account and the data under review is fictional. A real submission waits for KYC, procedure, and legal and privacy review. |
| Same person as applicant and reviewer | The dedicated account is a different Auth user and, by the unique `person_id`, a different PERSON. `review_*` still refuses a case whose subject or submitter is that reviewer. |

## Fictional data

The signal is operational, not a bypass.

- The dedicated reviewer account is created as a normal second signup. Its address and identifiers stay out of Git.
- The only extra fact is the single `MARKET` / `ES` grant, created later by the audited break-glass path.
- Do not add a flag, role, or claim that skips RLS, self-review, the evidence check, or audit. Fictional data is not weaker security.
- The Product Owner's use of that login is a debugging convenience. It is not a product role and it is not written into the repository.
- The account is not eligible for real identity documents, real equine documents, or a real KYC case.
- The step to real users is a separate decision: KYC provider, operating procedure, and legal and privacy review.

## What is closed, pending, and refused

Closed as the technical-pilot direction:

- Fictional data only, with a dedicated reviewer account distinct from the applicant.
- First grant, later and only if the audit blocker is lifted: `MARKET` / `ES`, and no platform scope.
- Exceptional bootstrap by the database owner, outside Expo, values not stored in Git, reviewer cannot administer grants.
- Ordinary administration deferred to an authenticated server operation whose actor is not the reviewer.

Pending before any grant row, and before real users:

- A reviewed change that can audit a database-owner bootstrap without a supplied actor id. This document does not write that SQL.
- KYC provider, legal evidence catalog, retention, conflict handling, and `REVIEWER-VISIBILITY`.
- The concrete test account, chosen at operation time.
- Reviewer queue, opening, evidence signing, and the evidence check before `ACCEPTED`, as already described in Stage 4B.

A future `039` could need, and this pull request does not authorize:

- the append-only grant-event history;
- the database-owner bootstrap writer;
- the later authenticated grant-admin operation, separate from review;
- suspension distinct from closure;
- an audit row for a refused review after suspension;
- the queue, detail, evidence, and acceptance checks already required by Stage 4B;
- a manual security review before implementation.

Not authorized:

- implementing any of the above;
- migration `039`, or any edit to `036`–`038`;
- a seed of a reviewer or of a personal identifier;
- a script or CI job that holds `service_role` in order to grant review;
- `service_role` in Expo;
- an in-app superadministrator;
- a hípica role, `users.role`, or JWT metadata as grant authority;
- an unaudited Dashboard insert treated as if it were product audit;
- a fictional-data flag that disables a control.
