# MIGRATION STATUS

PHASE: 5A — Disciplines foundation
STATUS: IMPLEMENTADO — stacked PR against `refactor/phase-4b-equine-center-relations`; 014 NOT deployed
DATE: 2026-09-02

Phase 5A is stacked on Ready PR #13 (`013_equine_center_relations.sql`).
Do not merge this PR before #13 (and #12, #11). Do not deploy 014. Product
Owner will retarget later. This agent will not retarget or merge.

Parent HEAD at branch creation: `d056c3ca5af8cda6e3c098733ce24629164a21d1`.
Baseline `main`: `9ac317295a5a983c6b74284af17f7e9fb305a8c7`.

## Files created

- `supabase/migrations/014_disciplines.sql`
- `supabase/tests/014_disciplines_test.sql`
- `scripts/run-disciplines-sql-tests.cjs`
- `docs/PHASE_5A_DISCIPLINES_REPORT.md`

## Files modified

- `package.json` (`test:disciplines` appended to `test:sql`)
- `supabase/tests/008_rider_profiles_test.sql` (allow `disciplines`; still forbid qualifications/assessments)
- `supabase/tests/012_equine_ownership_management_test.sql` (allow 014 tables; still forbid qualifications/bookings)
- `supabase/tests/013_equine_center_relations_test.sql` (same)
- `docs/MIGRATION_STATUS.md`
- `docs/CURRENT_ARCHITECTURE_REPORT.md`
- `docs/MIGRATION_PLAN.md`

Inherited migrations present on the parent branch, including `013`, are
unchanged.

## Security

RLS on all three tables, no client policies, no catalog/list/assign RPC.
No seed. `experience_level` is optional free text, not a Galope token set.

## Next phase

`015_qualifications`. Do not start 015. Do not merge. Do not deploy.
