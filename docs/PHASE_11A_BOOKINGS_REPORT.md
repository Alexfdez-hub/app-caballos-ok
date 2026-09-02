# Phase 11A — Booking foundation

**Project:** app-caballos-ok
**Phase:** 11A — Bookings
**Migration:** `supabase/migrations/021_bookings.sql`
**Date:** 2026-09-02
**Architecture:** Data Architecture 2.1
**Baseline:** `refactor/phase-10a-calendar` `cc3d7da8cd11a068b1b7638e6352054b480e998e`
**Branch:** `refactor/phase-11a-bookings`

This PR targets the 020 branch. Do not merge. Do not deploy `021`.

## Design selected

- Tables: `bookings`, `booking_requirements`.
- Participant is PERSON. Booker is ACCOUNT. Distinct roles.
- A booker may request only for their own PERSON or a minor covered by
  a current VERIFIED guardian relationship. Activity-specific consent
  may still be pending at request time.
- Booking statuses are the frozen Architecture 2.1 set.
  `CONFIRMED | ACTIVE | COMPLETED` cannot be inserted or transitioned
  to in 021.
- `eligibility_status` uses the frozen Architecture 2.1 tokens.
- Requirement types: equine types plus `GUARDIAN_CONSENT` and
  `POLICY_ACCEPTANCE`.
- Requirement source types: `OWNER | CENTER | MARKET | EQUINE |
  SERVICE | GUARDIAN | POLICY`.
- Requirement status includes `WAIVED` but there is no waive path.
- Confirmed history cannot be silently rewritten. `ends_at > starts_at`.
- Service must belong to the booking Center.
- No `check_booking_eligibility`, `create_booking_request` or
  `confirm_booking` in 021. No client CRUD.

## Access

RLS on, no client policies, `REVOKE ALL` from `anon`/`authenticated`.

## Next phase

`022_booking_functions.sql` on `refactor/phase-11b-booking-functions`
after CI + Bugbot. Do not merge. Do not deploy.
