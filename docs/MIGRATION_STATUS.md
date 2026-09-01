# MIGRATION STATUS

PHASE: 3B — Guardians & Minors
STATUS: IMPLEMENTADO — pending Product Owner review / merge
DATE: 2026-09-01

Phase 3A Identity Integration + authenticated shell is merged on `main`
(`ce61313`, PR #4). Migration 007 adds guardians/minors foundations.
Migrations `001–006` were not modified.

## Approved starting state

- Remote `main` includes Phase 3A.
- Migrations 001–006 deployed and aligned.
- `006_identity_integration.sql` is immutable.
- Next migration reserved as `007_guardians.sql`.

## Files created

- `supabase/migrations/007_guardians.sql`
- `supabase/tests/007_guardians_test.sql`
- `scripts/run-guardians-sql-tests.cjs`
- `src/features/guardians/`
- `src/screens/GuardianRelationshipsScreen.tsx`
- `docs/PHASE_3B_GUARDIANS_MINORS_REPORT.md`
- `docs/16_AI_DOCUMENT_MAP_AND_USAGE.md` (Product Owner file; included unchanged)

## Files modified

- `package.json`
- `src/app/navigation/types.ts`
- `src/app/navigation/AuthenticatedTabs.tsx`
- `src/screens/ProfileScreen.tsx`
- `docs/MIGRATION_STATUS.md`
- `docs/CURRENT_ARCHITECTURE_REPORT.md`
- `docs/MIGRATION_PLAN.md`

## Migration created

`007_guardians.sql`:

- `market_age_rules` (Architecture 2.1 table missing from 002; no legal seed);
- `guardian_relationships`;
- `guardian_consents` without premature booking/equine/center FKs;
- `evaluate_person_minority`, `has_accepted_required_policy`,
  `grant_guardian_consent`, `revoke_guardian_consent`,
  `check_guardian_consent`, list RPCs.

No `is_minor`, no identity-level `guardian_id`, no verification RPC.

## Application state

- Profile → Tutor y menores lists real relationships/consents via RPC.
- Empty/pending/verified/rejected/revoked/expired states are truthful.
- Revoke is available for an active consent on a verified relationship.
- Grant is not offered in UI: no market is collected on the person, and
  the client must not invent one. The grant RPC exists for server use/tests.
- Verification cannot be performed in the app.

## Checks

- `npx supabase migration up --local` — PASS (`007_guardians.sql` applied)
- `npx supabase db reset` — NOT RUN (local wipe blocked by environment policy)
- `npm run test:guardians` — PASS
- `npm run test:identity` — PASS
- `npm run typecheck` — PASS
- `npm run test:auth` — PASS (18 tests)
- `npx expo-doctor` — PASS (18/18)
- `git diff --check` — PASS
- Migrations `001–006` — unmodified

Cursor Bugbot found two valid medium findings on grant expiry handling.
Both were corrected and `npm run test:guardians` was re-run (PASS).

## Next phase

Centers / memberships as frozen `008_centers.sql` after 007 is reviewed.
Do not start that phase until this one is merged.
