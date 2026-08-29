# Current architecture report

**Project:** app-caballos-ok
**Baseline:** Phase 2C — Clean baseline / legacy retirement
**Date:** 2026-08-29

## Summary

The repository is an Expo/React Native client backed by Supabase. Phase 2C
retires the original horse-rental prototype so future work can implement frozen
Data Architecture 2.1 directly.

The application is now a minimal TypeScript shell. It initializes the Supabase
client, restores any persisted Auth session, and displays baseline status. It
does not implement registration, login, identity onboarding, profiles, equines,
or bookings.

## Retained application infrastructure

- Expo SDK 54 and React Native
- TypeScript strict checking with gradual JavaScript support
- React Navigation native stack
- `AuthProvider`, persisted session restoration, and Auth state subscription
- Supabase client using public Expo environment variables
- `App.tsx` and `index.js` entry infrastructure

## Active runtime

```text
index.js
  -> App.tsx
     -> AuthProvider
        -> RootNavigator
           -> BaselineScreen
```

`AuthProvider` remains generic infrastructure. It reads the persisted Supabase
Auth session and listens for Auth changes. `BaselineScreen` only reports
whether a session was restored and permits sign-out when one exists.

No registration or identity provisioning is implemented in Phase 2C.

## Database target present before Phase 2C

Deployed migrations 001–004 introduced:

- `public.markets`
- `public.persons`
- `public.user_accounts`
- `public.policy_documents`
- `public.policy_acceptances`

These remain intact, constrained, and protected by RLS.

## Legacy retirement

Migration `005_legacy_retirement.sql` removes the confirmed prototype chain:

```text
auth.users.on_auth_user_created
  -> public.handle_new_user()
  -> public.users
     <- public.horses
        <- public.bookings
```

The migration removes the trigger, function, and the three public legacy
tables in dependency-safe order without `CASCADE`. It does not drop or alter
`auth.users`.

The previous horse catalog, horse CRUD, booking, legacy profile, and legacy
registration screens have been removed. Their routes and table calls no longer
exist in production application code.

## Supabase client and Auth

The client remains in `src/services/supabase/client.ts` and uses:

- `EXPO_PUBLIC_SUPABASE_URL`
- `EXPO_PUBLIC_SUPABASE_ANON_KEY`
- AsyncStorage session persistence
- token refresh
- Auth state change subscription

No `service_role` credential is present in the application.

## Current limitations by design

- No login or registration UI
- No `persons` / `user_accounts` provisioning
- No profile UI
- No domain role selection
- No equine, center, guardian, assessment, service, calendar, or booking UI
- No replacement business tables beyond migrations 001–004

These are deliberate stop conditions, not runtime regressions. Phase 3A will
build identity integration on `persons` and `user_accounts`.

## Historical records

`docs/REMOTE_DATABASE_INVENTORY.md` remains the authoritative historical
inventory of the retired legacy schema. Git history preserves the deleted
prototype application.

The repository may still contain legacy terms in historical reports, the
remote schema dump, migration comments, and the retirement migration. Those
references are documentation or migration evidence, not production runtime
dependencies.
