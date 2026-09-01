# MIGRATION STATUS

PHASE: 3D — Centers foundation
STATUS: IMPLEMENTADO — merged on `main` (PR #7); migration 009 deployed
to linked development project `efkauegdlmfkonzwyyiv`
DATE: 2026-09-01

Phase 3D Centers foundation is merged on `main` (`cddf3c0`, PR #7).
Migration `009_centers.sql` is deployed on the linked development project.
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

## Product Owner decision — Center lifecycle

Approved 2026-09-01. No repository decision-log file exists; this is the
current-status record (full text in
`docs/PHASE_3D_CENTERS_FOUNDATION_REPORT.md`).

- `status`: `DRAFT` | `ACTIVE` | `INACTIVE` | `ARCHIVED` (default `DRAFT`)
- `verification_status`: `UNVERIFIED` | `PENDING` | `VERIFIED` | `REJECTED`
  (default `UNVERIFIED`)
- The two columns are independent.
- `ACTIVE` is not public discovery. `VERIFIED` is not membership, authority,
  policy, services, assessments or listing.
- `ARCHIVED` retains history. 009 does not enforce transitions.
- Ordinary clients cannot change either column.
- Later tokens (`SUSPENDED`, `EXPIRED`, `REVOKED`, …) need a new forward
  migration. Do not rewrite `009_centers.sql` after deployment.

## Application state

- Explore → Hípicas remains coming-soon with truthful copy: domain exists,
  onboarding/verification/directory are not in the app.
- Profile → Mis centros remains coming-soon: memberships are deferred.

## Remote

Linked development project: `efkauegdlmfkonzwyyiv`.

- `npx supabase db push --linked` applied `009_centers.sql` after a dry run
  that contained only that file (no 010, no seeds, no roles).
- Local and remote migration histories align through `009`.
- `equestrian_centers` and `center_languages` exist remotely.
- RLS is enabled on both tables.
- `anon` and `authenticated` have no table SELECT/INSERT/UPDATE/DELETE.
- No client RLS policies.
- No Center mutation RPCs.
- Migration 010 has not been started.

## Next phase

Center memberships as `010_center_memberships.sql` after Product Owner
authorizes that phase. Do not start 010 in this documentation update.
