# MIGRATION STATUS

PHASE: 3E — Center memberships
STATUS: IMPLEMENTADO — merged on `main` (PR #9); migration 010 deployed
to linked development project `efkauegdlmfkonzwyyiv`
DATE: 2026-09-02

Phase 3E Center memberships is merged on `main`
(`84e3da1c7184abf4b9ebe5ec2f02257d7dbe15e2`, PR #9).
Migration `010_center_memberships.sql` is deployed on the linked development
project. Migrations `001–009` were not modified.

## Approved starting state

- `main` includes Phase 3D (`1b67ade`, PR #8 documentation after PR #7).
- Migrations 001–009 exist locally and on the linked development project
  `efkauegdlmfkonzwyyiv`.
- Next unused migration number was `010`.
- Roadmap assigns `010_center_memberships.sql` to memberships.

## Files created

- `supabase/migrations/010_center_memberships.sql`
- `supabase/tests/010_center_memberships_test.sql`
- `scripts/run-memberships-sql-tests.cjs`
- `src/features/centers/*`
- `src/screens/MyCentersScreen.tsx`
- `docs/PHASE_3E_CENTER_MEMBERSHIPS_REPORT.md`

## Files modified

- `package.json`
- `src/screens/ProfileScreen.tsx`
- `src/app/navigation/AuthenticatedTabs.tsx`
- `src/app/navigation/types.ts`
- `supabase/tests/009_centers_test.sql` (regression compatibility only;
  migration `009_centers.sql` is unchanged)
- `docs/MIGRATION_STATUS.md`
- `docs/CURRENT_ARCHITECTURE_REPORT.md`
- `docs/MIGRATION_PLAN.md`

## Migration created

`010_center_memberships.sql`:

- `center_memberships` as PERSON + CENTER domain relationships;
- MVP0 roles `ADMIN | MANAGER | INSTRUCTOR | ASSESSOR`;
- lifecycle `ACTIVE | ENDED`;
- unique active `(center_id, person_id, role_code)`;
- RLS deny-by-default, no client table policies or grants;
- `list_my_center_memberships()` caller-context read;
- `has_active_center_role(person, center, role)` server-internal helper;
- no grant/revoke/bootstrap RPCs, no invitations, no Center Policy
  activation.

## Membership lifecycle decision

**Product Owner, 2026-09-02.** Architecture 2.1 names
`center_memberships.status` without enumerating values. The frozen 010
tokens are:

- `ACTIVE` (default): currently in force; `ended_at` must be null.
- `ENDED`: historical; `ended_at` required and `>= joined_at`.

Do not add `INVITED`, `PENDING`, `SUSPENDED` or other lifecycle states.
Invitation and onboarding workflows remain deferred. Later tokens need a
new forward migration. 010 does not enforce transition triggers. Ordinary
clients cannot change status. Historical rows are retained; ending is not
a physical DELETE.

## Application state

- Profile → Mis centros lists the authenticated person’s real memberships
  (Center name, role label, active/ended). Empty state is truthful: onboarding
  and role assignment are not in the app.
- Explore → Hípicas remains coming-soon (no public directory).
- No join/create/invite/assign/verify UI.

## Remote

Linked development project: `efkauegdlmfkonzwyyiv`.

Product Owner approved the linked push. `010_center_memberships.sql` was applied.

- Strict dry-run: `npx supabase db push --linked --dry-run --skip-vault`
  showed ONLY `010_center_memberships.sql`.
- Deployment: `npx supabase db push --linked --yes --skip-vault`.
- Vault, seeds and custom roles were not included.
- Local and remote histories align through `010`.
- `public.center_memberships` exists remotely.
- RLS is enabled. No RLS policies (intentional deny-by-default).
- `anon` has no SELECT/INSERT/UPDATE/DELETE.
- `authenticated` has no SELECT/INSERT/UPDATE/DELETE.
- `list_my_center_memberships()` is executable by `authenticated`, not by
  `anon`; no `person_id` argument; identity from `auth.uid()`;
  `SECURITY DEFINER`; `STABLE`; `search_path = pg_catalog, public`.
- `has_active_center_role(uuid, uuid, text)` is not executable by `anon` or
  `authenticated`; `SECURITY DEFINER`; `STABLE`; fixed `search_path`.
- Unique active-membership index exists.
- Migration `011` was not created or deployed.

## Security Advisor (record only — do not fix)

1. `rls_enabled_no_policy` on `center_memberships` is intentional (RLS on,
   privileges revoked, no client policies, reads via caller-context RPC).
   Do not add permissive policies.
2. Authenticated `SECURITY DEFINER` on `list_my_center_memberships()` is
   intentional (caller-context read API, no `person_id`, `auth.uid()`,
   table access denied). Do not switch to `SECURITY INVOKER` or revoke
   authenticated execute.
3. Separate future task: Security Advisor "Leaked Password Protection
   Disabled". Not a Phase 3E defect and not caused by 010. Do not change
   Auth config.

## Local / app verification (final Phase 3E HEAD)

The complete local runtime gate was executed successfully on pre-merge
Phase 3E HEAD `0973a609176c77f87d2682644a6b8e57fe4794d4`. Merge commit
`84e3da1c7184abf4b9ebe5ec2f02257d7dbe15e2` contains the identical source
tree (GitHub comparison: zero changed files). The tests were not re-run
after merge.

- clean local replay `001–010`
- `test:memberships`, `test:centers`, `test:riders`, `test:identity`
- `test:guardians` including real two-session concurrency
- `test:auth` 38/38
- TypeScript typecheck
- Expo Doctor 18/18
- `git diff --check`
- `001–009` immutability
- clean working tree
- Authenticated Expo Go smoke: Profile → Mis centros against remote;
  caller without memberships sees truthful empty state; no PGRST202 or
  generic load failure; no create/join/invite/assign-role/membership-edit UI

## Next phase

Do not start equines, disciplines, assessments, services or bookings until
Product Owner authorizes the next phase. Phase 011 has not been started.
