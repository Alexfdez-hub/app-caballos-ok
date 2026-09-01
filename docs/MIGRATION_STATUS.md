# MIGRATION STATUS

PHASE: 3D — Centers foundation
STATUS: IMPLEMENTADO — pending Product Owner review / merge / remote 009
DATE: 2026-09-01

Phase 3C Rider Profile / Passport is merged on `main` (`1d94807`, PR #6).
Migration `009_centers.sql` adds the Center domain foundation.
Migrations `001–008` were not modified.

## Approved starting state

- Remote `main` includes Phase 3C.
- Migrations 001–008 exist locally and on the linked development project.
- Next unused migration number was `009`.
- Roadmap assigns `009_centers.sql` to Centers and `010_center_memberships`
  to memberships.

## Files created

- `supabase/migrations/009_centers.sql`
- `supabase/tests/009_centers_test.sql`
- `scripts/run-centers-sql-tests.cjs`
- `docs/PHASE_3D_CENTERS_FOUNDATION_REPORT.md`

## Files modified

- `package.json`
- `src/screens/ExploreScreen.tsx`
- `src/screens/ProfileScreen.tsx`
- `docs/MIGRATION_STATUS.md`
- `docs/CURRENT_ARCHITECTURE_REPORT.md`
- `docs/MIGRATION_PLAN.md`

## Migration created

`009_centers.sql`:

- `equestrian_centers` with Architecture 2.1 foundation fields;
- `center_languages` (`center_id`, `locale` composite PK);
- RLS deny-by-default, no client table policies or grants;
- no memberships, no creation/verification RPCs, no public directory.

## Application state

- Explore → Hípicas remains coming-soon with truthful copy: domain exists,
  onboarding/verification/directory are not in the app.
- Profile → Mis centros remains coming-soon: memberships are deferred.

## Remote

Do not push `009` until Product Owner approval. Linked remote is currently
aligned through `008`.

## Next phase

Center memberships as `010_center_memberships.sql` after this phase is
reviewed and merged.
