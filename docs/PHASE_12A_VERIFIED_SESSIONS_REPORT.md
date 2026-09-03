# Phase 12A — Verified sessions

**Project:** app-caballos-ok
**Phase:** 12A — Verified sessions
**Migration:** `supabase/migrations/023_sessions.sql`
**Date:** 2026-09-03
**Architecture:** Data Architecture 2.1
**Baseline:** live `main` `188ed3f356c0da67126dd5da715e2765be7cf4a5`
**Branch:** `refactor/phase-12a-verified-sessions`

This PR targets live `main` (migrations `001`–`022` merged). Do not merge.
Do not deploy `023`. Do not start 024 until this Quality Gate is green.

## Design selected

- Tables: `sessions`, `session_events`, `session_evidence`,
  `session_permits`.
- One session per booking (`booking_id UNIQUE`). Participant is PERSON.
  Equine and Center are copied from the CONFIRMED booking and cannot be
  retargeted.
- Frozen session statuses, event types and evidence types from
  Architecture 2.1. `sync_status` and evidence `status` are stored
  without invented CHECK catalogs.
- Official `started_at` / `ended_at` / `received_at_server` are
  `clock_timestamp()` (server wall clock). Table `DEFAULT now()` remains
  for `created_at`. Client/device time is stored on events only.
  Session RPCs clear transaction-local `app.session_transition` before
  returning so a later statement cannot reuse the GUC.
- `start_session` / `end_session` are the only start/end path.
  Replay of an ACTIVE start or COMPLETED end is idempotent and does not
  rewrite the official timestamp.
- Caller authority: participant ACCOUNT, booked_by ACCOUNT, or the
  frozen 022 Center ADMIN/MANAGER + `MANAGE_BOOKINGS` helper. INSTRUCTOR,
  ASSESSOR, VIEW_ACTIVITY, membership-alone and an unrelated verified
  guardian are not enough.
- Offline start requires a server-issued `session_permits` row bound to
  booking, participant, equine and the booking window. No client-signed
  token. Online start does not accept a permit.
- Evidence is private metadata only. No Storage bucket and no upload
  policy. Completed/invalidated evidence cannot be attached or rewritten.
- `CREATE OR REPLACE` of `enforce_booking_request_authority` so a
  session RPC may move CONFIRMED→ACTIVE and ACTIVE→COMPLETED when
  transaction-local `app.session_transition = '1'`. Identity, snapshot
  and confirmed timestamps stay immutable.
- Concurrent starts serialize on the booking row. Unique `booking_id`
  remains the duplicate-session barrier.
- No `equine_activities`, reviews, incidents, audit, or
  `approve_zero_session`. No client table CRUD.

## Access

RLS on, no client policies, `REVOKE ALL` from `anon`/`authenticated`.
Public RPCs: `REVOKE ALL` then `GRANT EXECUTE` to `authenticated` only.
Internal helpers stay revoked.

## Frontend

No session UI. No timer authority. No evidence upload client.

## Next

Stop after this PR is Ready and the complete Quality Gate is green.
Do not merge. Do not retarget. Do not deploy. Do not start 024 until
then. Bugbot is optional/manual; do not claim Bugbot-clean unless a
real review ran.
