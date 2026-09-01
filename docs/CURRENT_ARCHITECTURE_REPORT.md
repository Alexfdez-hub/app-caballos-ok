# Current architecture report

**Project:** app-caballos-ok
**Baseline:** Phase 3C — Rider profile / Passport foundations
**Date:** 2026-09-01

## Summary

The repository is an Expo/React Native client backed by Supabase. Phase 3A
adds Auth → account → person identity. Phase 3B adds guardian relationships,
guardian consents, and market-aware minority evaluation. Phase 3C adds a
person-owned `rider_profiles` foundation and a truthful Passport surface.
The application shell remains a single authenticated app without role
selectors.

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
                       -> EditRiderProfileScreen
                    -> ProfileTab / ProfileScreen
                       -> EditIdentityScreen
                       -> GuardianRelationshipsScreen
```

`AuthProvider` remains generic session infrastructure. It does not store
person or account domain state.

`IdentityProvider` calls `ensure_my_identity()` for the current `auth.uid()`
and `complete_my_identity()` to update only that person’s basic fields.

Passport reads and writes only the caller’s rider profile through
`get_my_rider_profile()` and `upsert_my_rider_profile()`. Those RPCs derive
the person from `auth.uid()` via `user_accounts`. They do not accept a
`person_id`.

## Database target

Migrations 001–006 introduce identity, markets and policies. Migration
`007_guardians.sql` adds guardian/minor foundations. Migration
`008_rider_profiles.sql` adds:

- `public.rider_profiles` (`person_id` PK/FK → `persons`)
- `get_my_rider_profile()`
- `upsert_my_rider_profile(...)`

Identity objects retained from 001–007:

- `public.markets`
- `public.market_age_rules`
- `public.persons`
- `public.user_accounts`
- `public.policy_documents`
- `public.policy_acceptances`
- `public.guardian_relationships`
- `public.guardian_consents`
- Auth identity trigger and RPCs from `006_identity_integration.sql`
- Guardian consent RPCs from `007_guardians.sql`

Legacy prototype objects remain removed by `005_legacy_retirement.sql`.

Identity completeness is derived from `persons.first_name`, `last_name`, and
`date_of_birth`. Those columns remain nullable so incomplete accounts and
future persons without login credentials are not forced to invent values.

A rider profile belongs to a person, not an Auth user. A person may have at
most one rider profile. Profile existence does not prove Rider Policy
acceptance, guardian consent, qualification, assessment, Session Zero or
equine authorization.

`profile_visibility` is `PRIVATE` (default) or `PUBLIC`. PUBLIC is stored
intent only in this phase; there is no public SELECT or directory RPC.

## Supabase client and Auth

The client remains in `src/services/supabase/client.ts` and uses:

- `EXPO_PUBLIC_SUPABASE_URL`
- `EXPO_PUBLIC_SUPABASE_ANON_KEY`
- AsyncStorage session persistence
- token refresh
- Auth state change subscription

No `service_role` credential is present in the application. Clients do not
receive table `INSERT`/`UPDATE`/`DELETE`/`SELECT` privileges on `persons`,
`user_accounts`, guardian tables, or `rider_profiles`.

Usual development: `npm run start:local` (alias: `npm start`), which loads
the gitignored `.env.supabase.local`. Remote Supabase and physical Android:
`npm run start:remote`, which loads `.env.supabase.remote`. A physical
Android device cannot use `127.0.0.1` on the PC without extra network setup.
Tracked `*.example` files contain placeholders only.

## Current limitations by design

- Authenticated users with complete identity enter a single application shell
  (bottom tabs). There is no RiderApp / OwnerApp / CenterApp split and no
  role selector.
- Home, Explore and Activity remain empty-state discovery chrome.
- Passport shows a real rider-profile foundation and truthful placeholders
  for later domains.
- Guardian-managed creation or editing of a minor’s rider profile is deferred.
- Creating a rider profile does not check or create `RIDER_POLICY` acceptance.
- No public rider directory, even when visibility is PUBLIC.
- No equine, listing, search, map, booking, assessment, payment, or review UI
- No single `users.role` model

These are deliberate stop conditions. The next planned SQL migration is
`009_centers.sql`.

## Historical records

`docs/REMOTE_DATABASE_INVENTORY.md` remains the authoritative historical
inventory of the retired legacy schema. `docs/PHASE_2C_CLEAN_BASELINE_REPORT.md`
records the clean-break retirement. `docs/PHASE_3A_IDENTITY_INTEGRATION_REPORT.md`
and `docs/PHASE_3B_GUARDIANS_MINORS_REPORT.md` remain historical phase
reports. Git history preserves the deleted prototype application.

The repository may still contain legacy terms in historical reports, the
remote schema dump, migration comments, and the retirement migration. Those
references are documentation or migration evidence, not production runtime
dependencies.
