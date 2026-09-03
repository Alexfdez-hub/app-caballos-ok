# Phase 12B — Equine activity

**Project:** app-caballos-ok
**Phase:** 12B — Equine activity
**Migration:** `supabase/migrations/024_equine_activity.sql`
**Date:** 2026-09-03
**Architecture:** Data Architecture 2.1
**Baseline:** accepted 023 HEAD `d037b62c83db44ee339688b35c2e8e0fe5f56a27`
**Branch:** `refactor/phase-12b-equine-activity`

This PR stacks on 023 (PR #25). Do not merge. Do not deploy `024`.
Do not start 025 until this Quality Gate is green.

## Design selected

- Table: `equine_activities`. One row per session (`session_id UNIQUE`).
  Equine, center and booking are copied from the canonical session.
  Optional caller-supplied booking/equine/center ids are accepted only
  when they match that session.
- `activity_type`, `status` and `source` are stored without invented
  CHECK catalogs. Architecture 2.1 names the columns and does not freeze
  those vocabularies.
- Official `starts_at` / `ends_at` are copied from the session. No
  diagnoses, billing, scores, public visibility, Storage, reviews,
  incidents or audit.
- `record_equine_activity` is the only write path. Replay is idempotent.
  A started session may be recorded with `ends_at` null; a later record
  after `end_session` copies official `ended_at`. Completed activity
  (`ends_at` present) cannot be rewritten.
- Caller authority is the frozen 023 session operator path
  (`caller_can_operate_session`). INSTRUCTOR, VIEW_ACTIVITY and an
  unrelated authenticated user are not enough.
- READY and INVALIDATED sessions cannot be recorded.
- Concurrent records serialize on the session row. Unique `session_id`
  remains the duplicate-activity barrier.
- Internal `app.activity_transition` is cleared before the RPC returns.

## Access

RLS on, no client policies, `REVOKE ALL` from `anon`/`authenticated`.
Public RPC: `REVOKE ALL` then `GRANT EXECUTE` to `authenticated` only.
Internal helpers stay revoked.

## Frontend

No activity UI.

## Next

Stop after this PR is Ready and the complete Quality Gate is green.
Do not merge. Do not retarget. Do not deploy. Do not start 025 until
then. Bugbot is optional/manual; do not claim Bugbot-clean unless a
real review ran.
