# MIGRATION STATUS

PHASE: 8A — Equine requirements foundation
STATUS: IMPLEMENTADO — stacked PR against `refactor/phase-6a-rider-assessments`; 017 NOT deployed
DATE: 2026-09-02

Parent is Ready PR #16 HEAD `08e51cf6807b7828b4092c1d870969e1c16be691`.
Do not merge this PR before #16 (and #15). Do not deploy 017.

## Files created

- `supabase/migrations/017_equine_requirements.sql`
- `supabase/tests/017_equine_requirements_test.sql`
- `scripts/run-equine-requirements-sql-tests.cjs`
- `docs/PHASE_8A_EQUINE_REQUIREMENTS_REPORT.md`

## Files modified

- `package.json`
- `supabase/tests/011_equines_test.sql`
- `supabase/tests/015_qualifications_test.sql`
- `supabase/tests/016_rider_assessments_test.sql`
- `docs/MIGRATION_STATUS.md`
- `docs/CURRENT_ARCHITECTURE_REPORT.md`
- `docs/MIGRATION_PLAN.md`

Inherited migrations including `016` are unchanged versus parent HEAD.

## Next phase

`018_center_services` on `refactor/phase-8b-center-services`.
Do not merge. Do not deploy. Do not start 019.
