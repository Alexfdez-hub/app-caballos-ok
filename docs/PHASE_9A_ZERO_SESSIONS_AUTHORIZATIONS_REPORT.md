# Phase 9A — Zero Sessions and rider-equine authorizations

**Project:** app-caballos-ok
**Phase:** 9A — Zero Sessions / authorizations
**Migration:** `supabase/migrations/019_zero_sessions_authorizations.sql`
**Date:** 2026-09-02
**Architecture:** Data Architecture 2.1
**Baseline:** `origin/main` `40e1f1e7b201796c632ec480bfba07d43564d439` (merge of PR #18)
**Branch:** `refactor/phase-9a-zero-sessions-authorizations`

This PR targets `main`. Do not merge. Do not deploy `019`. Product Owner
closed the 019–022 conflicts on docs PR #19
(comment `5516860208`, HEAD `6127941e4b89baf17d4a5fea36e4b73bf4d22d5d`).
This agent will not merge or deploy.

SQL aliases avoid reserved keywords (`authorization`, `session`).

## Design selected

- Tables: `zero_sessions`, `rider_equine_authorizations`.
- PERSON for rider, evaluator, issuer. ACCOUNT only for
  `requested_by_account_id`.
- Zero Session `result` exactly
  `PENDING | APPROVED | APPROVED_WITH_RESTRICTIONS | REJECTED | CANCELLED`.
- Authorization types exactly
  `OWNER_APPROVAL | ZERO_SESSION | CENTER_DELEGATED_APPROVAL`.
- Authorization status exactly `ACTIVE | REVOKED`. No stored `EXPIRED`.
  `revoked_at` required iff `REVOKED`. Current effectiveness is a helper:
  ACTIVE, `valid_from <= now()`, null or future `valid_until`.
- `now()` is not in a table CHECK.
- A Zero Session result never auto-creates an authorization.
- Assessment remains a different table. Qualification remains a
  different table.
- No client CRUD. No `approve_zero_session()`, eligibility, calendar or
  booking RPC.

## Authority (Product Owner 2026-09-02)

- Evaluator ≠ rider. When `evaluator_person_id` is set: active `ASSESSOR`
  at `center_id` **and** effective `ASSESS_RIDERS` for that equine+Center.
  `ASSESSOR` alone is not enough. `INSTRUCTOR` is not enough.
- `ZERO_SESSION` authorization requires `source_zero_session_id` for the
  same rider+equine with result `APPROVED` or
  `APPROVED_WITH_RESTRICTIONS`. Issuer is that session's evaluator.
  Rejected Zero Session does not authorize.
- `CENTER_DELEGATED_APPROVAL` requires `center_id` and effective
  `APPROVE_RIDERS` for that equine+Center. Issuer ≠ rider. The existing
  `has_active_equine_center_permission` primitive is Center-over-equine
  (not a person grant), matching 013/018.
- `OWNER_APPROVAL` with null `center_id`: issuer is an effective PERSON
  owner. Owner-as-rider is allowed.
- `OWNER_APPROVAL` with `center_id`: that Center must effectively own
  the equine and hold `APPROVE_RIDERS`. Issuer is an active `ADMIN` or
  `MANAGER` at that owning Center. Issuer ≠ rider, checked before role
  so an ADMIN/MANAGER rider still cannot self-approve. `INSTRUCTOR` /
  `ASSESSOR` do not represent the owning Center.
- Membership, assignment and management alone never substitute.
- UPDATE cannot retarget historical identity columns. Evaluator cannot
  change once set. Historical Zero Session remains after membership end;
  further mutation then fails authority.
- Authorization revoke-only UPDATE (`ACTIVE` → `REVOKED`, `revoked_at`
  set, no other business columns changed) does not re-check issuer
  authority, so a prior grant can be withdrawn after the issuer loses
  role, ownership or `APPROVE_RIDERS`. Other authorization mutations
  still require current issuance authority.

## Access

RLS on, no client policies, `REVOKE ALL` from `anon`/`authenticated`.

Server-internal helpers, execute revoked from PUBLIC/anon/authenticated:

- `has_effective_equine_person_ownership`
- `has_effective_equine_center_ownership`
- `has_effective_rider_equine_authorization`

## Frontend

None. No fabricated Zero Session or authorization UI.

## Tests

`npm run test:zero-sessions` is appended to `npm run test:sql`.
Inherited migrations `001`–`018` are unchanged versus `main`. Earlier
SQL tests allow 019 tables and still forbid calendar/bookings.

## Next phase

`020_calendar.sql` on `refactor/phase-10a-calendar`, stacked on this
branch after CI + Bugbot. Do not merge. Do not deploy.
