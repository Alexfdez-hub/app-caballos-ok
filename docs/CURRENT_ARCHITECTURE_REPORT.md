# Current architecture report

**Project:** app-caballos-ok
**Baseline:** Phase 3A — Identity integration + authenticated application shell
**Date:** 2026-09-01

## Summary

The repository is an Expo/React Native client backed by Supabase. Phase 2C
retired the original horse-rental prototype. Phase 3A adds the first
Architecture 2.1 identity flow on `auth.users`, `user_accounts`, and
`persons`.

The application authenticates with email/password, provisions a person/account
link without fabricating personal data, and gates navigation on whether the
authenticated person has completed first name, last name, and date of birth.
A completed identity enters a single authenticated application shell; it does
not select a role.

## Retained application infrastructure

- Expo SDK 54 and React Native
- TypeScript strict checking with gradual JavaScript support
- React Navigation native stack and bottom tabs
- `AuthProvider`, persisted session restoration, and Auth state subscription
- Supabase client using public Expo environment variables
- `App.tsx` and `index.js` entry infrastructure

## Active runtime

```text
index.js
  -> App.tsx
     -> SafeAreaProvider
        -> AuthProvider
           -> IdentityProvider
              -> RootNavigator
                 -> AuthScreen                         (no session)
                 -> IdentityOnboardingScreen           (session, incomplete)
                 -> IdentityErrorScreen                (session, identity load failure)
                 -> AuthenticatedTabs                  (session, complete identity)
                    -> HomeTab / HomeScreen
                    -> ExploreTab / ExploreScreen
                    -> ActivityTab / ActivityScreen
                    -> PassportTab / EquestrianPassportScreen
                    -> ProfileTab / ProfileScreen
                       -> EditIdentityScreen
```

`AuthProvider` remains generic session infrastructure. It does not store
person or account domain state.

`IdentityProvider` calls `ensure_my_identity()` for the current `auth.uid()`
and `complete_my_identity()` to update only that person’s basic fields.

## Database target

Migrations 001–006 introduce or integrate:

- `public.markets`
- `public.persons`
- `public.user_accounts`
- `public.policy_documents`
- `public.policy_acceptances`
- Auth identity trigger and RPCs from `006_identity_integration.sql`

Legacy prototype objects are removed by `005_legacy_retirement.sql`:

```text
auth.users.on_auth_user_created
  -> public.handle_new_user()
  -> public.users
     <- public.horses
        <- public.bookings
```

Identity completeness is derived from `persons.first_name`, `last_name`, and
`date_of_birth`. Those columns remain nullable so incomplete accounts and
future persons without login credentials are not forced to invent values.

## Supabase client and Auth

The client remains in `src/services/supabase/client.ts` and uses:

- `EXPO_PUBLIC_SUPABASE_URL`
- `EXPO_PUBLIC_SUPABASE_ANON_KEY`
- AsyncStorage session persistence
- token refresh
- Auth state change subscription

No `service_role` credential is present in the application. Clients do not
receive table `INSERT`/`UPDATE` privileges on `persons` or `user_accounts`.

Usual development: `npm run start:local` (alias: `npm start`), which loads
the gitignored `.env.supabase.local`. Remote Supabase and physical Android:
`npm run start:remote`, which loads `.env.supabase.remote`. A physical
Android device cannot use `127.0.0.1` on the PC without extra network setup.
Tracked `*.example` files contain placeholders only.

## Current limitations by design

- Authenticated users with complete identity enter a single application shell
  (bottom tabs). There is no RiderApp / OwnerApp / CenterApp split and no
  role selector.
- Home, Explore, Activity, Passport, and Profile are navigation and empty
  states only. They do not load bookings, equines, centers, or passport data.
- No rider, owner, center, or guardian business flows
- No equine, listing, search, map, booking, assessment, payment, or review UI
- No guardian consent
- No single `users.role` model

These are deliberate stop conditions. The next planned SQL migration remains
`007_guardians.sql`. The application shell is frontend-only.

## Historical records

`docs/REMOTE_DATABASE_INVENTORY.md` remains the authoritative historical
inventory of the retired legacy schema. `docs/PHASE_2C_CLEAN_BASELINE_REPORT.md`
records the clean-break retirement. Git history preserves the deleted
prototype application.

The repository may still contain legacy terms in historical reports, the
remote schema dump, migration comments, and the retirement migration. Those
references are documentation or migration evidence, not production runtime
dependencies.
