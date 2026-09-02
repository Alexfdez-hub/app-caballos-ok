# Current architecture report

**Project:** app-caballos-ok
**Baseline:** Phase 3F — Equines foundation
**Date:** 2026-09-02

## Summary

The repository is an Expo/React Native client backed by Supabase. Phase 3A
adds Auth → account → person identity. Phase 3B adds guardian relationships.
Phase 3C adds person-owned rider profiles and Passport. Phase 3D adds the
Center organization foundation. Phase 3E adds Center-scoped memberships
without client grant/revoke or first-admin bootstrap. Phase 3F adds equine
identity and media metadata without ownership, management, client mutation
or public directory. The application shell remains a single authenticated
app without role selectors.

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

Explore → Caballos y ponis and Profile → Mis equinos / Equinos que gestiono
remain truthful coming-soon copy. The equine domain exists; public
discovery, ownership, management, center assignment, availability, booking
and media upload are not in the app. There is no equine create/edit/upload
UI and no fabricated catalog.

## Database target

Migrations 001–010 cover identity, policies, guardians, rider profiles,
Centers and Center memberships. Migration `011_equines.sql` adds:

- `public.equines`
- `public.equine_media`

An equine row is a domain identity with type `HORSE` or `PONY`. Lifecycle is
`ACTIVE|INACTIVE|ARCHIVED|DECEASED` (Product Owner confirmed). It is not
ownership, management, center assignment, availability or booking rights.
`birth_date` is optional and cannot be after record creation; age is not
stored. Clients have no table privileges. There is no client RPC. PUBLIC
visibility is stored intent only and does not grant SELECT. `equine_media`
stores unique `storage_path` metadata only; 011 does not create a Storage
bucket. Provisioning remains controlled outside the app.

`has_active_center_role(person_id, center_id, role_code)` remains
server-internal and is not executable by `anon` or `authenticated`. Center
membership does not grant equine authority.

No `service_role` credential is present in the application. Clients do not
receive table `INSERT`/`UPDATE`/`DELETE`/`SELECT` on identity, guardian,
rider-profile, center, membership or equine tables.

Usual development: `npm run start:local`. Remote: `npm run start:remote`.

## Current limitations by design

- No RiderApp / OwnerApp / CenterApp split and no role selector
- No public Center directory or map
- No Center self-service onboarding, self-verification or invitations
- No client membership grant/revoke or first-admin bootstrap
- No public equine directory, ownership listing, management UI, media upload,
  availability or booking UI
- No booking, assessment, payment, or review UI
- No single `users.role` model

The next planned SQL migration after Product Owner authorization is
`012_equine_ownership_management.sql`. Migration 011 is not deployed on the
linked development project. Phase 012 has not been started.

## Historical records

`docs/REMOTE_DATABASE_INVENTORY.md` remains the authoritative historical
inventory of the retired legacy schema. Phase 3A–3E reports remain
historical. Git history preserves the deleted prototype application.
