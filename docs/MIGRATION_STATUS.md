# MIGRATION STATUS

PHASE: 12B — Equine activity
STATUS: IMPLEMENTADO — stacked PR against accepted 023 HEAD; 024 NOT deployed
DATE: 2026-09-03

Parent is accepted 023 HEAD `d037b62c83db44ee339688b35c2e8e0fe5f56a27`
(PR #25 Quality Gate green). Live `main` remains
`188ed3f356c0da67126dd5da715e2765be7cf4a5` through `022`. Do not merge
this PR. Do not deploy 024. Do not start 025 until the complete Quality
Gate is green.

## Files created

- `supabase/migrations/024_equine_activity.sql`
- `supabase/tests/024_equine_activity_test.sql`
- `supabase/tests/024_equine_activity_concurrency_setup.sql`
- `supabase/tests/024_equine_activity_concurrency_session_a.sql`
- `supabase/tests/024_equine_activity_concurrency_session_b.sql`
- `supabase/tests/024_equine_activity_concurrency_assert.sql`
- `supabase/tests/024_equine_activity_concurrency_cleanup.sql`
- `scripts/run-activity-sql-tests.cjs`
- `scripts/run-activity-concurrency-test.cjs`
- `docs/PHASE_12B_EQUINE_ACTIVITY_REPORT.md`

## Files modified

- `package.json`
- inherited tests `008`–`023` (allow `equine_activities`; still forbid
  `reviews`, `incidents`, `audit_events`)
- `supabase/tests/023_sessions_concurrency_setup.sql`
- `supabase/tests/023_sessions_concurrency_cleanup.sql`
- `docs/MIGRATION_STATUS.md`
- `docs/CURRENT_ARCHITECTURE_REPORT.md`
- `docs/MIGRATION_PLAN.md`

Inherited migrations `001`–`023` are unchanged versus the 023 parent.
023 tests now allow `equine_activities` and still forbid `reviews`,
`incidents` and `audit_events`.

## Next phase

`025` is out of scope until this Quality Gate is green. Stop after
Ready + CI-green. Do not merge. Do not deploy.
