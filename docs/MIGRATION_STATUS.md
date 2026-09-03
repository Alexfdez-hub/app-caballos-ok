# MIGRATION STATUS

PHASE: 10A — Equine availability and calendar occupancy
STATUS: IMPLEMENTADO — Draft PR targeting the 019 branch. 020 NOT deployed.
DATE: 2026-09-02

019 branch HEAD is `0eda4503118e86d9424a4688e48d31a45dead43d`
(PR #20 Ready). Product Owner 2026-09-02 closed the 019–022 conflicts
on docs PR #19. This branch implements 020 only.

Do not merge. Do not deploy. Do not start 021 until this PR is Ready,
CI-green and Bugbot-clean (or a documented spend-limit after CI-green).

## Files created

- `supabase/migrations/020_calendar.sql`
- `supabase/tests/020_calendar_test.sql`
- `scripts/run-calendar-sql-tests.cjs`
- `docs/PHASE_10A_CALENDAR_REPORT.md`

## Files modified

- `package.json`
- inherited SQL tests 011–019 (allow 020 tables; still forbid bookings)
- `docs/MIGRATION_STATUS.md`
- `docs/CURRENT_ARCHITECTURE_REPORT.md`
- `docs/MIGRATION_PLAN.md`

Inherited migrations `001`–`019` are unchanged versus the 019 branch.

## Next phase

`021_bookings.sql` on `refactor/phase-11a-bookings`, stacked on this
branch after CI + Bugbot. Do not merge. Do not deploy.
