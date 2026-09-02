# MIGRATION STATUS

PHASE: 11B — Booking functions
STATUS: IMPLEMENTADO — Draft PR targeting the 021 branch. 022 NOT deployed.
DATE: 2026-09-02

021 branch HEAD is `69bceac9cff865e7e10fc533ad1cec956a2a7f9d`
(PR #22 Ready). This branch implements 022 only.

Do not merge. Do not deploy. Do not start 023.

## Files created

- `supabase/migrations/022_booking_functions.sql`
- `supabase/tests/022_booking_functions_test.sql`
- `scripts/run-booking-functions-sql-tests.cjs`
- `docs/PHASE_11B_BOOKING_FUNCTIONS_REPORT.md`

Inherited migrations `001`–`021` are unchanged versus the 021 branch.
Inherited tests `016`–`021` now allow the three 022 RPCs and still
forbid `approve_zero_session` and `sessions`.

## Next phase

`023` is out of scope. Stop after Ready + CI-green + Bugbot-clean
(or a documented spend-limit after CI-green).
