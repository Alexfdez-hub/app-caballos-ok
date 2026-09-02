# MIGRATION STATUS

PHASE: 4A — Equine ownership and management
STATUS: IMPLEMENTADO — stacked PR against `refactor/phase-3f-equines-foundation`; 012 NOT deployed
DATE: 2026-09-02

Phase 4A is stacked on Ready PR #11 (`011_equines.sql`). Do not merge this
PR before #11. Do not deploy 012. Product Owner will retarget later.

Parent HEAD at branch creation: `8262306bad8252713691fdcde8fff5be1dfbc8e1`.
Baseline `main`: `9ac317295a5a983c6b74284af17f7e9fb305a8c7`.

## Files created

- `supabase/migrations/012_equine_ownership_management.sql`
- `supabase/tests/012_equine_ownership_management_test.sql`
- `scripts/run-ownership-sql-tests.cjs`
- `docs/PHASE_4A_EQUINE_OWNERSHIP_MANAGEMENT_REPORT.md`
- `src/features/equines/*`
- `src/screens/MyEquinesScreen.tsx`
- `src/screens/MyManagedEquinesScreen.tsx`

## Files modified

- `package.json` (`test:ownership` appended to `test:sql`)
- `src/screens/ProfileScreen.tsx`
- `src/app/navigation/types.ts`
- `src/app/navigation/AuthenticatedTabs.tsx`
- `supabase/tests/009_centers_test.sql` (allow 012 tables; still forbid 013+)
- `supabase/tests/010_center_memberships_test.sql` (same)
- `supabase/tests/011_equines_test.sql` (same)
- `docs/MIGRATION_STATUS.md`
- `docs/CURRENT_ARCHITECTURE_REPORT.md`
- `docs/MIGRATION_PLAN.md`

Inherited migrations present on the parent branch, including `011`, are
unchanged.

## Provisional lifecycle

`ACTIVE | ENDED` on ownership and management is a provisional convention
awaiting Product Owner acceptance. Not frozen like 010.

## Security

RLS on both tables, no client policies, no mutation RPC, no
`person_id` argument on list RPCs, no PUBLIC execute on the internal helper.

## Next phase

`013_equine_center_relations`. Do not start 015. Do not merge. Do not deploy.
