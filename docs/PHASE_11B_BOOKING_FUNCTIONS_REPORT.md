# Phase 11B — Booking functions

**Project:** app-caballos-ok
**Phase:** 11B — Booking functions
**Migration:** `supabase/migrations/022_booking_functions.sql`
**Date:** 2026-09-03
**Architecture:** Data Architecture 2.1
**Baseline:** `refactor/phase-11a-bookings` `69bceac9cff865e7e10fc533ad1cec956a2a7f9d`
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
  a Center ADMIN/MANAGER with effective `MANAGE_BOOKINGS` for that
  equine+Center. INSTRUCTOR/ASSESSOR and booker-alone are not enough.
- Return shape: overall frozen eligibility token on every row plus
  explainable unmet-requirement rows.
- Staff callers do not use `has_accepted_required_policy(auth.uid())`.
  Policy acceptance subject is always the participant PERSON. A guardian
  ACCOUNT may record that acceptance. Guardian-own and staff-own
  acceptances never substitute.
- `create_booking_request` is booked-by the caller account. Never confirms.
  Classification:
  - `ELIGIBLE` / `ELIGIBLE_WITH_SUPERVISION` → `APPROVED`
  - `REQUIRES_CENTER_ASSESSMENT` / `REQUIRES_ZERO_SESSION` /
    `REQUIRES_OWNER_APPROVAL` → `PENDING_APPROVAL`
  - `REQUIRES_GUARDIAN_CONSENT` / `QUALIFICATION_NOT_VERIFIED` /
    `NOT_ELIGIBLE` → `PENDING_REQUIREMENTS`
- `confirm_booking` requires a Center ADMIN/MANAGER with effective
  `MANAGE_BOOKINGS`. Rider/booker cannot self-confirm. Accepts only
  `APPROVED`. Identity cannot be retargeted.
- Satisfaction:
  - Named service requires a matching `service_equines` row that is
    ACTIVE and `enabled=true`. `supervision_required` applies.
    `duration_limit_minutes` is enforced against the requested interval.
  - `ZERO_SESSION_REQUIRED` → currently effective `ZERO_SESSION`
    authorization. A Zero Session result alone is not enough.
  - `OWNER_APPROVAL_REQUIRED` → currently effective `OWNER_APPROVAL`.
  - `CENTER_ASSESSMENT_REQUIRED` → current `VALID` assessment at that
    Center (`valid_until` in the past is not currently effective).
  - Guardian `EQUESTRIAN_ACTIVITY` / `GENERAL` consent is evaluated at
    `starts_at`, not only `now()`. Consent must belong to a VERIFIED
    guardian effective at that time.
  - `MIN_QUALIFICATION` evaluates a current VERIFIED rider qualification
    in the required system/level (`level_order` inside that system only),
    expiry and optional discipline scope. No international equivalences.
  - `MIN_EXPERIENCE` evaluates `rider_profiles.experience_start_year` at
    the activity date against the stored numeric requirement. No derived
    age/experience column is stored.
  - Multiple current locales of the same `policy_code`+version are
    translations, not conflicting policies. Simultaneous current versions
    of one `policy_code` fail closed. Obsolete documents do not satisfy.
  - Guardian `EQUESTRIAN_ACTIVITY` consent and required current policy
    acceptances are independent. No waiver.
- Confirm is atomic: revalidate, persist every applicable evaluated
  requirement (SATISFIED or unmet) with source identity, insert a
  `BOOKING` calendar block (`block_type BOOKING`, `source_type BOOKING`,
  `source_id = booking.id`), snapshot the exact documents/acceptances
  used (document id, policy code/type, locale, version) in deterministic
  JSON, set `CONFIRMED` + `confirmed_at`. Confirmed requirement rows and
  the policy snapshot are then immutable. Any failure rolls back.
- Concurrent conflicting confirms cannot both succeed. Sequential
  revalidation sees occupancy; the 020 gist exclusion remains the
  concurrency barrier.
- `MIN_QUALIFICATION` / `MIN_EXPERIENCE` are evaluated. Unmet rows still
  emit `QUALIFICATION_NOT_VERIFIED`. No Galope engine is invented.
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
