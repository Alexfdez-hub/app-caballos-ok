# MIGRATION STATUS

PHASE: 11A — Booking foundation
STATUS: IMPLEMENTADO — Draft PR targeting the 020 branch. 021 NOT deployed.
DATE: 2026-09-02

020 branch HEAD is `cc3d7da8cd11a068b1b7638e6352054b480e998e`
(PR #21 Ready). This branch implements 021 only.

Do not merge. Do not deploy. Do not start 022 until this PR is Ready,
CI-green and Bugbot-clean (or a documented spend-limit after CI-green).

## Files created

- `supabase/migrations/021_bookings.sql`
- `supabase/tests/021_bookings_test.sql`
- `scripts/run-bookings-sql-tests.cjs`
- `docs/PHASE_11A_BOOKINGS_REPORT.md`

Inherited migrations `001`–`020` are unchanged versus the 020 branch.

## Next phase

`022_booking_functions.sql` on `refactor/phase-11b-booking-functions`.
