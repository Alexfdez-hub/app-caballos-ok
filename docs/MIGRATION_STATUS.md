# MIGRATION STATUS

PHASE: 12A — Verified sessions
STATUS: IMPLEMENTADO — stacked PR against live `main`; 023 NOT deployed
DATE: 2026-09-03

Parent is live `main` HEAD `188ed3f356c0da67126dd5da715e2765be7cf4a5`
(PRs #19–#23 merged; remote aligned through exact version `022`).
Do not merge this PR. Do not deploy 023. Do not start 024 until the
complete Quality Gate is green.

## Files created

- `supabase/migrations/023_sessions.sql`
- `supabase/tests/023_sessions_test.sql`
- `supabase/tests/023_sessions_concurrency_setup.sql`
- `supabase/tests/023_sessions_concurrency_session_a.sql`
- `supabase/tests/023_sessions_concurrency_session_b.sql`
- `supabase/tests/023_sessions_concurrency_assert.sql`
- `supabase/tests/023_sessions_concurrency_cleanup.sql`
- `scripts/run-sessions-sql-tests.cjs`
- `scripts/run-sessions-concurrency-test.cjs`
- `docs/PHASE_12A_VERIFIED_SESSIONS_REPORT.md`

## Files modified

- `package.json`
- `supabase/tests/008_rider_profiles_test.sql`
- `supabase/tests/009_centers_test.sql`
- `supabase/tests/010_center_memberships_test.sql`
- `supabase/tests/011_equines_test.sql`
- `supabase/tests/012_equine_ownership_management_test.sql`
- `supabase/tests/013_equine_center_relations_test.sql`
- `supabase/tests/014_disciplines_test.sql`
- `supabase/tests/015_qualifications_test.sql`
- `supabase/tests/016_rider_assessments_test.sql`
- `supabase/tests/017_equine_requirements_test.sql`
- `supabase/tests/018_center_services_test.sql`
- `supabase/tests/019_zero_sessions_authorizations_test.sql`
- `supabase/tests/020_calendar_test.sql`
- `supabase/tests/021_bookings_test.sql`
- `supabase/tests/022_booking_functions_test.sql`
- `docs/MIGRATION_STATUS.md`
- `docs/CURRENT_ARCHITECTURE_REPORT.md`
- `docs/MIGRATION_PLAN.md`

Inherited migrations `001`–`022` are unchanged versus live `main`.
Inherited tests `008`–`022` now allow `sessions` and still forbid
`equine_activities`, `reviews`, `incidents` and `audit_events`.

## Next phase

`024` is out of scope until this Quality Gate is green. Stop after
Ready + CI-green. Do not merge. Do not deploy.
