# Phase 13A — Reviews and incidents

**Project:** app-caballos-ok
**Phase:** 13A — Reviews and incidents
**Migration:** `supabase/migrations/025_reviews_incidents.sql`
**Date:** 2026-09-03
**Architecture:** Data Architecture 2.1
**Baseline:** accepted 024 HEAD `cb213e8031089b5f2dd90122d7cd4219d860fca3`
**Branch:** `refactor/phase-13a-reviews-incidents`

This PR stacks on 024 (PR #26). Do not merge. Do not deploy `025`.
Do not start 026 until this Quality Gate is green.

## Design selected

- Tables: `reviews`, `incidents`.
- Frozen rating CHECK `1..5`. `subject_type`, review `status`,
  `incident_type`, `severity` and incident `status` are stored without
  invented CHECK catalogs. No moderation, aggregation, compensation,
  penalties, insurance conclusions or legal classifications.
- A review requires a COMPLETED booking. `subject_id` must be that
  booking's center, equine or participant. Reviewer is the caller
  PERSON (participant or booked_by ACCOUNT). Center staff and
  INSTRUCTOR cannot submit a review of the booking they operate.
- Replay of the same reviewer + booking + subject is idempotent and
  does not rewrite rating or comment.
- An incident requires a started session. Session/booking/equine/center
  must match. Reporter is the caller PERSON. Authority is the frozen
  023 session operator path so Center ADMIN/MANAGER + `MANAGE_BOOKINGS`
  can report safety incidents. Multiple incidents per session are
  allowed. No resolve RPC.
- Review comment is public-classified content. Incident description is
  private. Neither is a Storage path. Clients have no table SELECT.
- Concurrent `submit_review` serializes on the booking row.

## Access

RLS on, no client policies, `REVOKE ALL` from `anon`/`authenticated`.
Public RPCs: `REVOKE ALL` then `GRANT EXECUTE` to `authenticated` only.
Internal helpers stay revoked.

Inherited tests `008`–`024` allow `reviews`/`incidents` to exist and
still forbid `audit_events`. 023/024 sequential and concurrency
cleanups delete those rows before sessions/bookings.

## Frontend

No review or incident UI.

## Next

Stop after this PR is Ready and the complete Quality Gate is green.
Do not merge. Do not retarget. Do not deploy. Do not start 026 until
then. Bugbot is optional/manual; do not claim Bugbot-clean unless a
real review ran. Bugbot on PR #25 was quota unavailable.
