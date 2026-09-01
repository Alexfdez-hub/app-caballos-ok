# MIGRATION STATUS

PHASE: 3E — Center memberships
STATUS: IMPLEMENTADO localmente — pending review / remote deployment approval
DATE: 2026-09-02

Phase 3E Center memberships is implemented on
`refactor/phase-3e-center-memberships`. Migration `010_center_memberships.sql`
is local only. Migrations `001–009` were not modified.

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

- Local and remote histories currently align through `009`.
- Migration `010` is **not** deployed.
- Do not `db push` until Product Owner approves this phase.

## Next phase

Do not start equines, disciplines, assessments, services or bookings until
Product Owner authorizes the next phase. Remote deployment of 010 is a
separate approval.
