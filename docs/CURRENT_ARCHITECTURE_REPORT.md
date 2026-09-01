# Current architecture report

**Project:** app-caballos-ok
**Baseline:** Phase 3D — Centers foundation
**Date:** 2026-09-01

## Summary

The repository is an Expo/React Native client backed by Supabase. Phase 3A
adds Auth → account → person identity. Phase 3B adds guardian relationships.
Phase 3C adds person-owned rider profiles and Passport. Phase 3D adds the
Center organization foundation without memberships or self-service
onboarding. The application shell remains a single authenticated app without
role selectors.

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

Passport reads and writes only the caller’s rider profile through
`get_my_rider_profile()` and `upsert_my_rider_profile()`.

Explore and Profile mention Centers only as truthful coming-soon copy.
There is no Center creation, verification, membership or directory UI.

## Database target

Migrations 001–008 cover identity, policies, guardians and rider profiles.
Migration `009_centers.sql` adds:

- `public.equestrian_centers`
- `public.center_languages`

A Center is an organization, not an Auth user and not a person. Row existence
does not create membership, Center Policy acceptance, equine rights,
assessments or bookings. Clients have no table privileges and no mutation
RPC. Verification status can be `VERIFIED` only through a future controlled
process; ordinary roles cannot set it.

`center_memberships` remains deferred to `010_center_memberships.sql`.

No `service_role` credential is present in the application. Clients do not
receive table `INSERT`/`UPDATE`/`DELETE`/`SELECT` on identity, guardian,
rider-profile or center tables.

Usual development: `npm run start:local`. Remote: `npm run start:remote`.

## Current limitations by design

- No RiderApp / OwnerApp / CenterApp split and no role selector
- No public Center directory or map
- No Center self-service onboarding or self-verification
- No Center memberships or staff roles
- No equine, booking, assessment, payment, or review UI
- No single `users.role` model

The next planned SQL migration is `010_center_memberships.sql`.

## Historical records

`docs/REMOTE_DATABASE_INVENTORY.md` remains the authoritative historical
inventory of the retired legacy schema. Phase 3A–3C reports remain
historical. Git history preserves the deleted prototype application.
