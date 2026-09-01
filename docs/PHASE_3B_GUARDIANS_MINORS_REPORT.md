# Phase 3B — Guardians and minors

**Project:** app-caballos-ok
**Phase:** 3B — Guardians & Minors
**Migration:** `supabase/migrations/007_guardians.sql`
**Date:** 2026-09-01
**Architecture:** Data Architecture 2.1
**Baseline:** `main` `ce61313` (Phase 3A merged, PR #4)
**Branch:** `refactor/phase-3b-guardians-minors`

## Design selected

- PERSON remains distinct from ACCOUNT. A minor can exist as a `persons` row
  without `user_accounts`.
- Age is never stored. `evaluate_person_minority` computes age from
  `persons.date_of_birth` + supplied reference date + the market rule effective
  on that date.
- `market_age_rules` is added in 007 because migration 002 created only
  `markets`. No legal adult-age values are seeded.
- `guardian_relationships` and `guardian_consents` are separate tables.
  Policy acceptance is reused through `has_accepted_required_policy`; it is not
  duplicated and does not create consent.
- No client verification RPC. `VERIFIED` cannot be set by `anon` or
  `authenticated`. Authority to verify is deferred.
- No `booking_id` / `equine_id` / `center_id` columns. Architecture 2.1 names
  those future scopes; this phase does not add relational-looking UUIDs without
  target tables.
- No `audit_events`. Grant/revoke evidence lives on the consent row.
- Frontend is a Profile stack screen: list + revoke only. Grant is not offered
  because the app has no associated market/country yet and must not invent one.

## Migration contents

`007_guardians.sql` creates:

### Tables

- `market_age_rules` — `country_code`, `legal_adult_age` (1–25 bound, not a
  universal legal constant), `guardian_consent_required`, effective period,
  overlap rejection trigger.
- `guardian_relationships` — guardian/minor FKs, distinct-person check,
  types `PARENT|LEGAL_GUARDIAN|OTHER`, statuses
  `PENDING|VERIFIED|REJECTED|REVOKED|EXPIRED`, lifecycle timestamps,
  unique active pair `(PENDING, VERIFIED)`.
- `guardian_consents` — relationship + person FKs, `granted_by_account_id`,
  type `EQUESTRIAN_ACTIVITY`, scope `GENERAL`, statuses
  `ACTIVE|REVOKED|EXPIRED`, unique one ACTIVE per relationship/type/scope,
  trigger forcing persons to match the relationship.

### RLS and privileges

- RLS enabled, no client policies (deny-by-default).
- `REVOKE ALL` on the three tables from `anon` and `authenticated`.
- Trigger functions not executable by clients.
- `evaluate_person_minority` not granted to clients.
- Consent/list/grant/revoke/check/policy helpers: `REVOKE` from
  `PUBLIC`/`anon`/`authenticated`, then `GRANT EXECUTE` to `authenticated`
  only where required.

### RPCs

- `grant_guardian_consent(...)` — identity from `auth.uid()` only; requires
  VERIFIED/active relationship of the caller; market-aware consent
  requirement; independent `GUARDIAN_POLICY` check when a current document
  exists; does not verify relationships or create policy acceptances.
- `revoke_guardian_consent(...)` — caller must be the guardian; idempotent;
  retains the row.
- `check_guardian_consent(...)` — reusable validity check; fails closed on
  missing/ambiguous market rules; does not confirm bookings.
- `list_my_guardian_relationships()` / `list_my_guardian_consents()` —
  caller’s own records only.
- `has_accepted_required_policy(...)` — not applicable when no current
  document exists; fails closed if current documents are ambiguous.

All security-definer functions use `search_path = pg_catalog, public`.

## Verification boundary

Authenticated and anonymous roles cannot INSERT/UPDATE relationships or set
`VERIFIED`. A trigger also rejects client verification. No
`verify_guardian_relationship` RPC exists. Rows may remain `PENDING` or be
provisioned as `VERIFIED` only through a controlled process outside normal
client access.

## Policy vs consent

`has_accepted_required_policy('GUARDIAN_POLICY', market)` is checked on grant
when a current document exists. Accepting policy does not create consent.
Granting consent does not create policy acceptance. UI copy distinguishes
the two; missing policy is mapped to a distinct user-facing message.

## Frontend

Profile → Tutor y menores (`GuardianRelationshipsScreen`):

- lists real relationships/consents via RPC;
- truthful empty, pending, verified, rejected, revoked, expired and error
  states;
- revoke for an ACTIVE consent on a VERIFIED relationship;
- no self-verification, no minor creation, no invented market for grant.

## Tests and checks

| Command | Result |
|---|---|
| `npx supabase migration up --local` | PASS — applied `007_guardians.sql` |
| `npx supabase db reset` | NOT RUN — local wipe was blocked by environment policy |
| `npm run test:guardians` | PASS |
| `npm run test:identity` | PASS |
| `npm run typecheck` | PASS |
| `npm run test:auth` | PASS — 18 tests |
| `npx expo-doctor` | PASS — 18/18 |
| `git diff --check` | PASS |
| Migrations `001–006` diff | PASS — empty |

## Deferred

- Verification authority
- Contextual consent FKs (`booking_id`, `equine_id`, `center_id`)
- Canonical `audit_events`
- Validated market/legal seed data
- Person `country_code` collection and in-app grant UX
- Booking/session/assessment integration

## Architecture conflicts

None. Premature contextual UUID columns from Architecture 2.1 §4 are deferred
on Product Owner instruction for this phase: do not add FKs without target
domains.

## Known issues

- Local `db reset` was not executed; 007 was applied with `migration up --local`
  onto the existing local database, then SQL tests ran against that schema.
- Grant RPC exists; UI does not call it because no market is collected on the
  person.
- Canonical audit coverage is not claimed.

## Bugbot

Cursor Bugbot (Manual Only, Autofix OFF) found two valid medium issues on the
first review. Both were corrected in `grant_guardian_consent`:

- time-expired `ACTIVE` consents are retired to `EXPIRED` before a new grant,
  so renewal is not blocked by the unique active index;
- `p_expires_at` in the past is rejected.

A second Bugbot pass found that `check_guardian_consent` compared expiry to
UTC midnight of the reference date, so a same-day expired consent could still
pass. Same-day checks now use `now()`; other dates fail closed at the end of
that UTC day. `npm run test:guardians` was re-run (PASS).

A third Cursor Bugbot pass found no remaining bugs. GitHub Bugbot still needs
to be run on the pull request (Manual Only, Autofix OFF) after the PR is opened.
