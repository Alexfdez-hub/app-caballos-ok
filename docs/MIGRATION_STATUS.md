# MIGRATION STATUS

PHASE: 8B — Center services foundation
STATUS: IMPLEMENTADO — stacked PR against `refactor/phase-8a-equine-requirements`; 018 NOT deployed
DATE: 2026-09-02

Parent is Ready PR #17 HEAD `7165b7c1eaae1eadaee4a8358195abaab5096980`.
Do not merge this PR before #17 (and #16, #15). Do not deploy 018.

## Files created

- `supabase/migrations/018_center_services.sql`
- `supabase/tests/018_center_services_test.sql`
- `scripts/run-center-services-sql-tests.cjs`
- `docs/PHASE_8B_CENTER_SERVICES_REPORT.md`

## Files modified

- `package.json`
- `supabase/tests/009_centers_test.sql`
- `supabase/tests/010_center_memberships_test.sql`
- `supabase/tests/011_equines_test.sql`
- `supabase/tests/015_qualifications_test.sql`
- `supabase/tests/016_rider_assessments_test.sql`
- `supabase/tests/017_equine_requirements_test.sql`
- `docs/MIGRATION_STATUS.md`
- `docs/CURRENT_ARCHITECTURE_REPORT.md`
- `docs/MIGRATION_PLAN.md`

Inherited migrations including `017` are unchanged versus parent HEAD.

Product Owner (2026-09-02) approved `ACTIVE|INACTIVE` for
`center_services.status` and `service_equines.status`. Those CHECKs are
in `018` only. 015/017 already used the same catalog pair. Do not
rewrite 001–017.

## Next phase

Do not start 019. Do not merge. Do not deploy.
