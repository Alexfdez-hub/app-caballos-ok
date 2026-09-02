# Current architecture report

**Project:** app-caballos-ok
**Baseline:** Phase 3E — Center memberships
**Date:** 2026-09-02

## Summary

The repository is an Expo/React Native client backed by Supabase. Phase 3A
adds Auth → account → person identity. Phase 3B adds guardian relationships.
Phase 3C adds person-owned rider profiles and Passport. Phase 3D adds the
Center organization foundation. Phase 3E adds Center-scoped memberships
without client grant/revoke or first-admin bootstrap. The application shell
remains a single authenticated app without role selectors.

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
                       -> MyCentersScreen
```

`AuthProvider` remains generic session infrastructure. It does not store
person or account domain state.

Passport reads and writes only the caller’s rider profile through
`get_my_rider_profile()` and `upsert_my_rider_profile()`.

Profile → Mis centros reads only the caller’s memberships through
`list_my_center_memberships()`. Explore → Hípicas remains truthful
coming-soon copy. There is no Center creation, verification, invitation or
directory UI.

## Database target

Migrations 001–009 cover identity, policies, guardians, rider profiles and
Centers. Migration `010_center_memberships.sql` adds:

- `public.center_memberships`

A membership is a PERSON + CENTER relationship, not a global account role.
Row existence does not create Center Policy acceptance, equine rights,
assessments or bookings. Clients have no table privileges. Grant, revoke and
first-ADMIN bootstrap remain controlled outside the app.

`has_active_center_role(person_id, center_id, role_code)` is server-internal
and is not executable by `anon` or `authenticated`.

No `service_role` credential is present in the application. Clients do not
receive table `INSERT`/`UPDATE`/`DELETE`/`SELECT` on identity, guardian,
rider-profile, center or membership tables.

Usual development: `npm run start:local`. Remote: `npm run start:remote`.

## Current limitations by design

- No RiderApp / OwnerApp / CenterApp split and no role selector
- No public Center directory or map
- No Center self-service onboarding, self-verification or invitations
- No client membership grant/revoke or first-admin bootstrap
- No equine, booking, assessment, payment, or review UI
- No single `users.role` model

The next planned SQL migration after Product Owner authorization is
`011_equines.sql`. Migration 010 is deployed on the linked development
project. Phase 011 has not been started.

## Historical records

`docs/REMOTE_DATABASE_INVENTORY.md` remains the authoritative historical
inventory of the retired legacy schema. Phase 3A–3D reports remain
historical. Git history preserves the deleted prototype application.
