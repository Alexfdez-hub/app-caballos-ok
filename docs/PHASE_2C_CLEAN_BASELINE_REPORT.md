# Phase 2C clean baseline report

**Date:** 2026-08-29
**Branch:** `refactor/phase-2c-clean-baseline`
**Remote database modified:** no

## Product decision

The original prototype is no longer a compatibility or data-retention target.
Frozen Data Architecture 2.1 and the approved migration architecture now
control future implementation. Git history and
`docs/REMOTE_DATABASE_INVENTORY.md` retain the prototype record.

No legacy users, horses, bookings, roles, waivers, KYC, tax, Stripe, Galope, or
media values are copied into Architecture 2.1.

## Dependency analysis before retirement

The authoritative inventory and a reconstructed local catalog showed:

```text
auth.users.on_auth_user_created
  -> public.handle_new_user()

public.bookings.horse_id
  -> public.horses.id

public.bookings.rider_id
  -> public.users.id

public.horses.owner_id
  -> public.users.id
```

Catalog validation found zero foreign keys from `markets`, `persons`,
`user_accounts`, `policy_documents`, or `policy_acceptances` to any legacy
table.

Migration 005 therefore removes objects in this order:

1. `auth.users.on_auth_user_created`
2. `public.handle_new_user()`
3. `public.bookings`
4. `public.horses`
5. `public.users`

The migration does not use `CASCADE`. An unexpected external dependency will
abort deployment instead of being removed implicitly. `auth.users` is retained.

## Migration

Created `supabase/migrations/005_legacy_retirement.sql`.

It is safe in both supported starting conditions:

- the deployed remote legacy objects exist and are removed explicitly;
- a clean Architecture 2.1 database has no prototype objects, so `IF EXISTS`
  makes migration 005 a no-op for those objects.

Migrations 001–004 are unchanged.

## Frontend retirement

Removed the legacy routes and screens for:

- registration/login tied to the prototype flow;
- horse search and detail;
- legacy booking creation and listing;
- owner horse create/edit/delete;
- legacy profile and owner navigation.

Removed direct calls to `horses` and `bookings`, the `horse-images` upload
path, and the prototype global rider/owner concepts from production code.

Removed dependencies used only by those screens:

- `@react-native-community/datetimepicker`
- `@react-navigation/bottom-tabs`
- `expo-image-picker`

The obsolete datetime-picker Expo plugin was also removed.

## Reusable infrastructure retained

- Expo / React Native application and assets
- TypeScript and strict type checking
- React Navigation native stack
- Supabase environment configuration and client
- AsyncStorage-backed Supabase Auth session persistence
- `AuthProvider`, session restoration, and Auth state subscription
- Architecture and migration documentation
- Architecture 2.1 migrations and tables from 001–004

## Clean shell

`BaselineScreen.tsx` is the sole route. It states that product flows are not
implemented, reports whether a generic Supabase Auth session was restored, and
allows sign-out when a session exists.

It does not implement login, registration, identity provisioning, profile
onboarding, roles, or any future domain feature.

## Local database validation

Validation used disposable local
`public.ecr.aws/supabase/postgres:17.6.1.165` containers only.

Results:

- clean local chain 001→005: passed;
- clean local chain repeated in a second fresh container: passed;
- reconstructed legacy schema + verified Auth trigger + 001→005: passed;
- legacy trigger, function, and three tables absent after 005: passed;
- `auth.users` still present: passed;
- all five Architecture 2.1 tables from 001–004 still present: passed;
- their 16 constraints remain present: passed;
- RLS remains enabled on all five tables: passed;
- dependency catalog showed no Architecture 2.1 FK to legacy tables: passed.

The normal Supabase CLI stack remains affected by the pre-existing UTF-8 BOM
in the ignored root `.env`, so direct local Supabase PostgreSQL containers were
used as in Phase 2B. The secret file was not read or modified.

## Application validation

- `npm run typecheck`: passed.
- `npx expo-doctor`: passed 18/18 checks.
- `npx expo config --type public`: passed.
- Expo web development server reached ready state.
- Browser smoke test rendered the clean baseline shell.
- Production `src` search found no legacy table, role, trigger, or bucket
  references.
- `git diff --check`: passed after documentation whitespace correction.

## Remaining legacy references

Remaining terms are legitimate:

- `supabase_remote_schema.sql` — historical remote schema dump;
- `docs/REMOTE_DATABASE_INVENTORY.md` — historical inventory;
- `docs/PHASE_2B_IMPLEMENTATION_REPORT.md` and prior status text — migration
  history;
- migrations 001/003 comments — historical safety context;
- migration 005 — explicit retirement operations;
- `cursor_architecture_pack/` — archived architecture source pack;
- frozen architecture prose that explains prohibited single-role concepts.

No production application path depends on a retired object.

## Documentation cleanup

- Removed obsolete root `ESTRUCTURA.md`.
- Removed the stale duplicate root `CURRENT_ARCHITECTURE_REPORT.md`.
- Replaced `docs/CURRENT_ARCHITECTURE_REPORT.md` with the current clean
  baseline.
- Updated migration numbering: identity integration is 006 and guardians is
  007.

## Unresolved risks

- Migration 005 intentionally discards prototype data.
- The unverified Storage bucket `horse-images`, if it still exists remotely,
  is not removed by this public-schema migration. It has no remaining app path;
  Storage cleanup requires a separately authorized, verified operation.
- Remote deployment has not occurred, so the linked project still contains the
  legacy objects until migration 005 is separately reviewed and applied.
- npm reports the existing 16 audit findings (7 moderate, 9 high).
- The ignored root `.env` BOM still blocks normal `supabase start`.

## Expected state before Phase 3A

After migration 005 is reviewed and separately deployed:

- Supabase Auth remains available without the prototype trigger;
- Architecture 2.1 identity tables exist but have no provisioning flow;
- the app is a compiling shell with reusable Auth/session plumbing;
- Phase 3A can implement identity directly on `persons` and `user_accounts`.

Phase 3A was not started.
