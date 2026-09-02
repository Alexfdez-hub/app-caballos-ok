# MIGRATION STATUS

PHASE: 4B — Equine–Center relations
STATUS: IMPLEMENTADO — stacked PR against `refactor/phase-4a-equine-ownership-management`; 013 NOT deployed
DATE: 2026-09-02

Phase 4B is stacked on Ready PR #12 (`012_equine_ownership_management.sql`).
Do not merge this PR before #12 (and #11). Do not deploy 013. Product Owner
will retarget later. This agent will not retarget or merge.

Parent HEAD at branch creation: `71955494db243063889b56e4e1f4bc31c57f359d`.
Baseline `main`: `9ac317295a5a983c6b74284af17f7e9fb305a8c7`.

## Files created

- `supabase/migrations/013_equine_center_relations.sql`
- `supabase/tests/013_equine_center_relations_test.sql`
- `scripts/run-center-relations-sql-tests.cjs`
- `docs/PHASE_4B_EQUINE_CENTER_RELATIONS_REPORT.md`

## Files modified

- `package.json` (`test:center-relations` appended to `test:sql`)
- `supabase/tests/009_centers_test.sql` (allow 013 tables; still forbid later domains)
- `supabase/tests/010_center_memberships_test.sql` (same)
- `supabase/tests/011_equines_test.sql` (same)
- `supabase/tests/012_equine_ownership_management_test.sql` (allow 013 tables; still forbid `disciplines`/`bookings`)
- `docs/MIGRATION_STATUS.md`
- `docs/CURRENT_ARCHITECTURE_REPORT.md`
- `docs/MIGRATION_PLAN.md`

Inherited migrations present on the parent branch, including `012`, are
unchanged.

## Security

RLS on both tables, no client policies, no grant/revoke/assign RPC, no
caller-scoped list RPC (the relation is equine+center, not the caller's
person). `has_active_equine_center_permission` execute is revoked from
PUBLIC/anon/authenticated. Assignment, membership and ownership do not
create a permission.

## Next phase

`014_disciplines`. Do not start 015. Do not merge. Do not deploy.
