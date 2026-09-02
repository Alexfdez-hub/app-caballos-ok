# MIGRATION STATUS

PHASE: 3F — Equines foundation
STATUS: IMPLEMENTADO — draft PR against `main`; migration 011 NOT deployed
DATE: 2026-09-02

Phase 3F Equines foundation is implemented on
`refactor/phase-3f-equines-foundation`. Migration `011_equines.sql` is local
only. Migrations `001–010` were not modified.

## Approved starting state

- `main` `9ac317295a5a983c6b74284af17f7e9fb305a8c7` (docs PR #10; Phase 3E
  merged and documented).
- Migrations 001–010 exist locally and on the linked development project
  `efkauegdlmfkonzwyyiv`.
- Next unused migration number was `011`.
- Roadmap assigns `011_equines.sql` to the Equines foundation.

## Files created

- `supabase/migrations/011_equines.sql`
- `supabase/tests/011_equines_test.sql`
- `scripts/run-equines-sql-tests.cjs`
- `docs/PHASE_3F_EQUINES_FOUNDATION_REPORT.md`

## Files modified

- `package.json`
- `src/screens/ExploreScreen.tsx`
- `src/screens/ProfileScreen.tsx`
- `supabase/tests/009_centers_test.sql` (regression compatibility only;
  migration `009_centers.sql` is unchanged)
- `supabase/tests/010_center_memberships_test.sql` (regression compatibility
  only; migration `010_center_memberships.sql` is unchanged)
- `docs/MIGRATION_STATUS.md`
- `docs/CURRENT_ARCHITECTURE_REPORT.md`
- `docs/MIGRATION_PLAN.md`

## Migration created

`011_equines.sql`:

- `equines` as UUID equine identity; `HORSE | PONY` types;
- lifecycle `ACTIVE | INACTIVE | ARCHIVED`;
- visibility `PRIVATE | PUBLIC` as stored intent only;
- `equine_media` metadata with `PHOTO` only;
- RLS deny-by-default, no client table policies or grants;
- no client RPC.

## Equine enumeration decision

**Phase 3F implementation decision, 2026-09-02.** Architecture 2.1 freezes
`HORSE|PONY` and names `status`, `visibility_status` and `media_type`
without enumerating values. Product Owner confirmation is required before
remote deployment.

- Lifecycle: `ACTIVE` (default), `INACTIVE`, `ARCHIVED`. Center `DRAFT` is
  not copied. Not occupancy or availability.
- Visibility: `PRIVATE` (default), `PUBLIC`. PUBLIC does not grant SELECT.
- Media: `PHOTO` only. Architecture does not mention VIDEO for equine_media.

Do not add ownership, management, center assignment or public-directory
tokens. Later tokens need a new forward migration. 011 does not enforce
transition triggers. Ordinary clients cannot change status. Historical rows
are retained.

## Application state

- Explore → Caballos y ponis remains coming-soon: domain exists; public
  discovery, availability, booking and media upload are not in the app.
- Profile → Mis equinos remains coming-soon: domain exists; ownership
  listing is not in the app.
- Profile → Equinos que gestiono remains coming-soon: domain exists;
  management, center assignment and booking are not in the app.
- No create/edit/upload/directory UI and no fabricated equine cards.

## Remote

Linked development project: `efkauegdlmfkonzwyyiv`.

Migration `011` was **not** created on the remote project and was **not**
deployed. Local and remote histories remain aligned through `010` until
Product Owner confirms enumerations and authorizes a linked push.

## Security Advisor (record only — do not fix)

When 011 is applied locally or remotely, `rls_enabled_no_policy` on
`equines` and `equine_media` is intentional (RLS on, privileges revoked, no
client policies, no client RPC). Do not add permissive policies to silence
the advisor. Do not grant Data API SELECT to make PostgREST see the tables.

Separate future task: Security Advisor "Leaked Password Protection
Disabled". Not a Phase 3F defect and not caused by 011. Do not change Auth
config.

## Local / app verification

See the draft PR test plan. This cloud clone has no Docker; SQL tests were
not executed against PostgreSQL here. Flag: `LOCAL_RUNTIME_GATE_PENDING`.

## Next phase

Do not start 012 equine ownership/management until Product Owner authorizes
it. Do not merge this draft. Do not deploy 011 remotely without Product
Owner confirmation of the enumerations.
