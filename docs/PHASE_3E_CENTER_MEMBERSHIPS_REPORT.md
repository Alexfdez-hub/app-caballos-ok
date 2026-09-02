# Phase 3E — Center memberships

**Project:** app-caballos-ok
**Phase:** 3E — Center memberships
**Migration:** `supabase/migrations/010_center_memberships.sql`
**Date:** 2026-09-02
**Architecture:** Data Architecture 2.1
**Baseline:** `main` `1b67ade` (Phase 3D merged, PR #7 + docs PR #8)
**Branch:** `refactor/phase-3e-center-memberships`

## Design selected

- Membership is a domain relationship between PERSON and CENTER.
- A Center row does not grant authority. A membership row does not own the
  Center, accept Center Policy, authorize equines, or validate assessments.
- Roles are Center-scoped codes, not a global `users.role`.
- One person may hold multiple roles at one Center and belong to multiple
  Centers. Duplicate simultaneously active Center/person/role rows are
  rejected. Ended rows are retained.
- Creation, grant, revoke and first-ADMIN bootstrap are not defined for
  ordinary clients. There is no mutation RPC.

## Membership lifecycle values

**Architecture 2.1:** names `status`, `joined_at` and `ended_at` without
enumerating status values.

**Product Owner decision:** approved and frozen 2026-09-02 for migration 010.
Do not add `INVITED`, `PENDING`, `SUSPENDED` or other lifecycle states.
Invitation and onboarding workflows remain deferred. Any future lifecycle
extension must use a new forward migration. Do not rewrite 010 after
deployment.

**Frozen foundation set:**

| Value | Meaning |
|---|---|
| `ACTIVE` | Currently in force. Default. `ended_at` must be null. |
| `ENDED` | Historical. `ended_at` required and `>= joined_at`. |

Intended transitions (not enforced by trigger; no client workflow):

- Controlled provisioning creates `ACTIVE`.
- An authorized future workflow may set `ENDED` and `ended_at`.
- Physical DELETE is not the ordinary end path.
- A later `ACTIVE` row for the same Center/person/role may exist after an
  `ENDED` row because uniqueness applies only to active rows.

Not included (frozen out of 010 by Product Owner):

- `INVITED` / `PENDING` — no invitation workflow in this phase.
- `SUSPENDED` / `REVOKED` — no management workflow in this phase.

## Roles

Frozen MVP0 codes: `ADMIN`, `MANAGER`, `INSTRUCTOR`, `ASSESSOR`.

- ADMIN does not own the Center.
- MANAGER does not own equines.
- INSTRUCTOR does not automatically assess.
- ASSESSOR does not create Assessor Policy acceptance or assessment
  authority.

## Migration contents

`010_center_memberships.sql` creates:

### `center_memberships`

- `id uuid pk`
- `center_id` FK → `equestrian_centers` (no `ON DELETE CASCADE`)
- `person_id` FK → `persons` (no Auth UUID)
- `role_code` `ADMIN|MANAGER|INSTRUCTOR|ASSESSOR`
- `status` default `ACTIVE` (`ACTIVE|ENDED`)
- `joined_at`, `ended_at`, `created_at`, `updated_at`
- unique index on `(center_id, person_id, role_code)` where `status = 'ACTIVE'`
- indexes on `center_id`, `person_id`, and active role lookup
  `(person_id, center_id, role_code)`

### RLS and privileges

- RLS enabled, no client policies
- `REVOKE ALL` from `anon` and `authenticated`
- no table SELECT for the Center member roster

### Helpers / RPCs

- `list_my_center_memberships()` — `SECURITY DEFINER`, identity from
  `auth.uid()` only, execute for `authenticated`, returns the caller’s rows
  plus Center name. No other members. No `person_id` argument.
- `has_active_center_role(person_id, center_id, role_code)` — server-internal,
  execute revoked from `anon` and `authenticated`. True only for `ACTIVE`
  membership with `ended_at` null. Center A never grants Center B.

No grant, revoke, bootstrap or self-assignment RPC.

## Authority boundary

Documentation does not define who provisions the first ADMIN, whether an
ADMIN may grant another ADMIN, or whether Center Policy / verification is
required before a role is usable for later sensitive actions.

Therefore:

- Initial provisioning stays outside Expo.
- Ordinary clients cannot INSERT/UPDATE/DELETE memberships.
- The app does not simulate a working staff-management UI.

Missing workflow (deferred, not invented):

- first-ADMIN bootstrap
- grant/revoke of ADMIN/MANAGER/INSTRUCTOR/ASSESSOR
- whether the last ADMIN may be ended
- invitation flow
- Center Policy / Assessor Policy activation as a membership side effect

## Center Policy and Assessor boundaries

Membership creation does not insert `policy_documents` or
`policy_acceptances`. ASSESSOR membership does not create assessments or
satisfy Assessor Policy. Future sensitive actions must still check
membership + role + applicable current policy + Center lifecycle as
required by that operation.

## Frontend

Profile → Mis centros loads `list_my_center_memberships()`.

- Shows Center name, UI labels for role codes, and active/ended state.
- Loading, empty, error and retry states.
- Empty copy: onboarding and role assignment are not in the app.
- No join, create, invite, assign, revoke, verify or directory UI.

Explore → Hípicas remains coming-soon.

## Deferred

- invitations and email invites
- first-admin onboarding
- staff management UI
- Center creation/verification
- Center Policy / Assessor Policy activation UX
- disciplines, qualifications, assessments, equines, services, bookings

## Architecture conflicts

None. Enumerating membership status as `ACTIVE|ENDED` is a documented
foundation constraint because Architecture 2.1 left the enumeration
unspecified. Invitation and suspension states were not invented.

## Tests and checks

| Command | Result |
|---|---|
| `npx supabase db reset --local` | PASS — replayed `001–010` |
| `npm run test:memberships` | PASS — SQL/RLS/P0 |
| `npm run test:centers` | PASS |
| `npm run test:riders` | PASS |
| `npm run test:identity` | PASS |
| `npm run test:guardians` | PASS — SQL/RLS plus concurrency |
| `npm run test:auth` | PASS — 38/38 |
| `npm run typecheck` | PASS |
| `npx expo-doctor` | PASS — 18/18 |
| `git diff --check` | PASS |
| Migrations `001–009` diff | PASS — empty |
| Working tree | PASS — clean |
| Authenticated Expo Go smoke (remote) | PASS — Profile → Mis centros; empty state truthful; no PGRST202 or generic load failure; no create/join/invite/assign-role/membership-edit UI |

Final Phase 3E HEAD verification above is recorded as already passed on
`84e3da1c7184abf4b9ebe5ec2f02257d7dbe15e2`. Not re-run in this
documentation update.

## Remote

Linked development project: `efkauegdlmfkonzwyyiv`.

Phase 3E PR #9 was merged into `main` at
`84e3da1c7184abf4b9ebe5ec2f02257d7dbe15e2`. Product Owner approved the
linked push. `010_center_memberships.sql` was applied.

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
