# MIGRATION STATUS

PHASE: 6A — Rider assessments foundation
STATUS: IMPLEMENTADO — stacked PR against `refactor/phase-5b-qualifications`; 016 NOT deployed
DATE: 2026-09-02

Parent is Ready PR #15 (`015_qualifications.sql`) HEAD
`aa67729e22ceb9f8cd6594177448f7852cb24be7`. Do not merge this PR before
#15. Do not deploy 016. This agent will not retarget or merge.

## Current baseline (verified 2026-09-02)

PRs #11–#14 are merged into `main` at
`6f916e7abb6834349cffef173bf307e51131123c`. Remote
`efkauegdlmfkonzwyyiv` is aligned through `014` (Product Owner).
Remote schema/RLS verification passed. Android/Expo Go smoke PASS.
PR #15 (015) is Ready; CI run 33664243044 green; Bugbot check
`100363454997` success — no issues found. Autofix OFF.

Historical Phase 5A text that described `011`–`014` as stacked/not
deployed was true at that branch time.

## Files created

- `supabase/migrations/016_rider_assessments.sql`
- `supabase/tests/016_rider_assessments_test.sql`
- `scripts/run-assessments-sql-tests.cjs`
- `docs/PHASE_6A_RIDER_ASSESSMENTS_REPORT.md`

## Files modified

- `package.json` (`test:assessments` appended to `test:sql`)
- `supabase/tests/008_rider_profiles_test.sql`
- `supabase/tests/009_centers_test.sql`
- `supabase/tests/010_center_memberships_test.sql`
- `supabase/tests/012_equine_ownership_management_test.sql`
- `supabase/tests/013_equine_center_relations_test.sql`
- `supabase/tests/014_disciplines_test.sql`
- `supabase/tests/015_qualifications_test.sql`
- `docs/MIGRATION_STATUS.md`
- `docs/CURRENT_ARCHITECTURE_REPORT.md`
- `docs/MIGRATION_PLAN.md`

Inherited migrations present on the parent branch, including `015`, are
unchanged versus parent HEAD `aa67729`.

## Security

RLS on all three tables, no client policies, no create/validate RPC.
Assessor authority is a SECURITY DEFINER trigger using active `ASSESSOR`
membership only. A rider cannot be their own assessor. Historical rows
remain after membership end.

## Next phase

`017_equine_requirements` on `refactor/phase-8a-equine-requirements`,
stacked on this branch. Do not merge. Do not deploy. Do not start 019.
