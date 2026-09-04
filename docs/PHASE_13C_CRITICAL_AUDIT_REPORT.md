# Phase 13C — Critical audit coverage

**Migration:** `supabase/migrations/029_critical_audit.sql`
**Branch:** `cursor/phase-029-critical-audit-d219`
**Base:** accepted Phase 9B / migration 028 HEAD `9e1331708eca6db62085f8374b6fe712115db4a6`
**Status:** implemented; stacked Draft PR; complete Quality Gate pending

## Scope

Phase 13C extends the append-only `audit_events` foundation from 026
for the remaining Architecture 2.1 critical committed transitions:

- `policy_accepted`
- `guardian_consent_granted` / `guardian_consent_revoked`
- `rider_assessment_validated`
- `equine_permission_granted` / `equine_permission_revoked`
- `zero_session_approved`
- `booking_confirmed` / `booking_cancelled`

Integration is trigger-based. Migrations `001`–`028` are unchanged.
Product RPCs are not rewritten. There is no client audit feed and no
direct client insert/update/delete/select.

## Security and correctness

- Audit fires only after a committed INSERT/UPDATE of the named
  transition. Failed RPCs and rolled-back subtransactions write no row.
- Exact idempotent replays that do not change status (revoke replay,
  Zero Session exact replay, already-VALID assessment, already-CANCELLED
  booking) create no duplicate event.
- Actor ACCOUNT/PERSON and `occurred_at` remain server-authoritative
  through `record_audit_event`.
- Unauthenticated fixture DML (`auth.uid()` null) is skipped so earlier
  phase fixtures keep working. Authenticated RPCs and JWT-backed server
  writes are audited.
- Metadata is allowlisted ids and public-safe tokens. Policy bodies,
  JWTs, notes, comments, snapshots and unrestricted row metadata are
  not stored. Policy-acceptance metadata uses `target_id` / `account_id`
  so keys do not match the 026 `policy`/`document` denylist.
- New helpers are `SECURITY DEFINER` with
  `search_path = pg_catalog, public`. `PUBLIC`, `anon` and
  `authenticated` execution are revoked.

## Verification

`supabase/tests/029_critical_audit_test.sql` proves spoof resistance,
rollback, failed-call silence, replay/no-op exact counts and metadata
privacy for every 029 event.

`029_critical_audit_concurrency_*` and
`scripts/run-audit-coverage-concurrency-test.cjs` race two
`grant_guardian_consent` callers and require exactly one ACTIVE consent
and exactly one `guardian_consent_granted` event.

The 026 suite no longer asserts that booking confirm is unaudited; that
deferral was 026-only.

## Excluded

- No merge, no deploy, no migration 030 until this Quality Gate is green.
- No client-readable global audit feed.
- No retrofit of unrelated historical migration files.
