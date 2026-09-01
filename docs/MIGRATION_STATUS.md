# MIGRATION STATUS

PHASE: 3C — Rider profile / Passport foundations
STATUS: IMPLEMENTADO — pending Product Owner review / merge
DATE: 2026-09-01

Phase 3B Guardians/Minors is merged on `main` (`2ade001`, PR #5).
Migration `008_rider_profiles.sql` adds the rider-profile foundation.
Migrations `001–007` were not modified.

## Approved starting state

- Remote `main` includes Phase 3B.
- Migrations 001–007 exist; `007_guardians.sql` is immutable.
- Next unused local migration number was `008`.
- Product Owner authorized Rider profile / Passport foundations next,
  not Centers. Planned `008_centers` is shifted to `009_centers`.

## Files created

- `supabase/migrations/008_rider_profiles.sql`
- `supabase/tests/008_rider_profiles_test.sql`
- `scripts/run-riders-sql-tests.cjs`
- `src/features/riders/`
- `src/screens/EditRiderProfileScreen.tsx`
- `docs/PHASE_3C_RIDER_PROFILE_PASSPORT_REPORT.md`

## Files modified

- `package.json`
- `src/app/navigation/types.ts`
- `src/app/navigation/AuthenticatedTabs.tsx`
- `src/screens/EquestrianPassportScreen.tsx`
- `docs/MIGRATION_STATUS.md`
- `docs/CURRENT_ARCHITECTURE_REPORT.md`
- `docs/MIGRATION_PLAN.md`

## Migration created

`008_rider_profiles.sql`:

- `rider_profiles` 1:1 with `persons` (`person_id` PK/FK);
- `bio`, `experience_start_year`, `profile_visibility`, timestamps;
- visibility constrained to `PRIVATE` | `PUBLIC` (default PRIVATE);
- RPCs `get_my_rider_profile` and `upsert_my_rider_profile`.

No disciplines, qualifications, assessments, centers, equines, Session Zero,
authorizations, `users.role`, or account-level rider flag.

## Application state

- Passport loads the authenticated person's real rider profile via RPC.
- The person can create/edit their own bio, experience start year and
  visibility.
- PUBLIC visibility is stored intent only; there is no public directory.
- Deferred passport sections stay truthful empty/coming-soon copy.
- Guardian-managed minor profile editing is not offered.

## Checks

Recorded in `docs/PHASE_3C_RIDER_PROFILE_PASSPORT_REPORT.md`.

## Next phase

Centers / memberships as `009_centers.sql` after this phase is reviewed
and merged. Do not start disciplines, qualifications, or Centers until
then.
