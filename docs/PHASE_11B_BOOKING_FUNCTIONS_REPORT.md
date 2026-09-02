# Phase 11B — Booking functions

**Project:** app-caballos-ok
**Phase:** 11B — Booking functions
**Migration:** `supabase/migrations/022_booking_functions.sql`
**Date:** 2026-09-02
**Architecture:** Data Architecture 2.1
**Baseline:** `refactor/phase-11a-bookings` `cdfd76808813d6b4a23e38472873e08b68c19554`
**Branch:** `refactor/phase-11b-booking-functions`

This PR targets the 021 branch. Do not merge. Do not deploy `022`.
Product Owner closed the 019–022 conflicts on docs PR #19
(comment `5516860208`). This agent will not merge or deploy.

## Design selected

- P0 RPCs only: `check_booking_eligibility`, `create_booking_request`,
  `confirm_booking`.
- No new tables. Migrations `001`–`021` are not edited.
- `CREATE OR REPLACE` of `enforce_equine_calendar_block_manage_authority`
  and `enforce_booking_request_authority` so `confirm_booking` can set
  `CONFIRMED` and insert BOOKING occupancy when transaction-local
  `app.confirming_booking = '1'`. ACTIVE/COMPLETED still cannot be forced.
  Ordinary calendar inserts still require `MANAGE_AVAILABILITY`.
- Eligibility callers: participant account, current VERIFIED guardian, or
  effective `MANAGE_BOOKINGS` for that equine+Center.
- Return shape: overall frozen eligibility token on every row plus
  explainable unmet-requirement rows.
- Staff callers do not use `has_accepted_required_policy(auth.uid())`.
  Policy acceptances are evaluated for the participant or booker/guardian.
- `create_booking_request` is booked-by the caller account. Never confirms.
  Classification:
  - `ELIGIBLE` / `ELIGIBLE_WITH_SUPERVISION` → `APPROVED`
  - `REQUIRES_CENTER_ASSESSMENT` / `REQUIRES_ZERO_SESSION` /
    `REQUIRES_OWNER_APPROVAL` → `PENDING_APPROVAL`
  - `REQUIRES_GUARDIAN_CONSENT` / `QUALIFICATION_NOT_VERIFIED` /
    `NOT_ELIGIBLE` → `PENDING_REQUIREMENTS`
- `confirm_booking` requires effective `MANAGE_BOOKINGS`. Booker-alone is
  not enough. Accepts only `APPROVED`.
- Satisfaction:
  - `ZERO_SESSION_REQUIRED` → currently effective `ZERO_SESSION`
    authorization. A Zero Session result alone is not enough.
  - `OWNER_APPROVAL_REQUIRED` → currently effective `OWNER_APPROVAL`.
  - `CENTER_ASSESSMENT_REQUIRED` → current `VALID` assessment at that
    Center (`valid_until` in the past is not currently effective).
  - Guardian `EQUESTRIAN_ACTIVITY` consent and required current policy
    acceptances are independent. No waiver.
- Confirm is atomic: revalidate, write requirement rows, insert a
  `BOOKING` calendar block (`block_type BOOKING`, `source_type BOOKING`,
  `source_id = booking.id`), snapshot policies, set `CONFIRMED` +
  `confirmed_at`. Any failure rolls back.
- Concurrent conflicting confirms cannot both succeed. Sequential
  revalidation sees occupancy; the 020 gist exclusion remains the
  concurrency barrier.
- `MIN_QUALIFICATION` / `MIN_EXPERIENCE` emit
  `QUALIFICATION_NOT_VERIFIED`. No Galope engine is invented.
- Missing `date_of_birth` does not invent adulthood.
- No `approve_zero_session`. No `sessions` table. No client CRUD.

## Access

Existing table RLS stays on, no client policies, `REVOKE ALL` from
`anon`/`authenticated`. The three RPCs: `REVOKE ALL` then
`GRANT EXECUTE` to `authenticated` only. Internal helpers stay revoked.

## Frontend

No booking UI. No confirm screen. No eligibility client.

## Next

Stop after this PR is Ready, CI-green and Bugbot-clean (or a documented
spend-limit after CI-green). Do not merge. Do not retarget. Do not
deploy. Do not start 023.
