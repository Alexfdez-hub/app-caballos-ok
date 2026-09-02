# Current architecture report

**Project:** app-caballos-ok
**Baseline:** Phase 9A — Zero Sessions and authorizations (on `main` through 018)
**Date:** 2026-09-02

## Summary

The repository is an Expo/React Native client backed by Supabase. Phase 3A
adds Auth → account → person identity. Phase 3B adds guardian relationships.
Phase 3C adds person-owned rider profiles and Passport. Phase 3D adds the
Center organization foundation. Phase 3E adds Center-scoped memberships
without client grant/revoke or first-admin bootstrap. Phase 3F adds equine
identity and media metadata. Phase 4A adds ownership and management
relationships without collapsing them onto `equines` and without a public
directory. Phase 4B adds equine–center assignments and explicit center
permissions without treating membership, ownership or assignment as a
permission grant. Phase 5A adds a coded discipline catalog, translations
and equine–discipline associations without seeding codes, without Galope
equivalences. Phase 5B adds configurable qualification systems, levels
and rider qualifications without seeding, without equivalences, and
without assessments. Phase 6A adds Center-owned rider assessments with
discipline observations and restriction JSON, without Zero Session,
authorization or eligibility. The application shell remains a
single authenticated app without role selectors.

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
                       -> MyEquinesScreen
                       -> MyManagedEquinesScreen
```

`AuthProvider` remains generic session infrastructure. It does not store
person or account domain state.

Passport reads and writes only the caller’s rider profile through
`get_my_rider_profile()` and `upsert_my_rider_profile()`.

Profile → Mis centros reads only the caller’s memberships through
`list_my_center_memberships()`. Explore → Hípicas remains truthful
coming-soon copy. There is no Center creation, verification, invitation or
directory UI.

Explore → Caballos y ponis remains truthful coming-soon copy (no public
directory). Profile → Mis equinos / Equinos que gestiono load the
Phase 4A caller-scoped RPCs. There is no equine create/edit/upload UI,
no fabricated catalog, and no assign/grant/revoke UI for center relations.

## Database target

**Current baseline (verified 2026-09-02):** `origin/main` HEAD is
`40e1f1e7b201796c632ec480bfba07d43564d439` (merge of PR #18). PRs
#15–#18 are merged into `main`. Migrations `001`–`018` exist on `main`.
Product Owner states remote project `efkauegdlmfkonzwyyiv` is aligned
through `018`; remote schema/RLS verification passed; Android/Expo Go
smoke PASS. Historical reports that described `015`–`018` as stacked and
not deployed were true at those branch times; they are not rewritten.

Migrations 001–010 cover identity, policies, guardians, rider profiles,
Centers and Center memberships. Migration `011_equines.sql` adds:

- `public.equines`
- `public.equine_media`

An equine row is a domain identity with type `HORSE` or `PONY`. Lifecycle is
`ACTIVE|INACTIVE|ARCHIVED|DECEASED` (Product Owner confirmed). It is not
ownership, management, center assignment, availability or booking rights.
`birth_date` is optional and cannot be after the UTC calendar date of
record creation (`(created_at AT TIME ZONE 'UTC')::date`); age is not
stored. Clients have no table privileges. There is no client RPC. PUBLIC
visibility is stored intent only and does not grant SELECT. `equine_media`
stores unique `storage_path` metadata only; 011 does not create a Storage
bucket. Provisioning remains controlled outside the app.

Migration `012_equine_ownership_management.sql` (merged PR #12)
adds `equine_ownerships` and `equine_management_assignments` with PERSON|
CENTER XOR FKs, strictly positive percentage, Product Owner approved
`ACTIVE|ENDED`, and at most one active `PRIMARY_MANAGER`. Caller-scoped
`list_my_equine_ownerships()` / `list_my_equine_management_assignments()`
derive PERSON from `auth.uid()` and expose stored status plus
`is_currently_effective`. Profile → Mis equinos / Equinos que
gestiono load those RPCs. Center membership does not grant equine
authority. `has_active_equine_management_role` is server-internal and
requires `valid_from <= now()`.

Migration `013_equine_center_relations.sql` (merged PR #13)
adds `equine_center_assignments` and `equine_center_permissions`.
Assignment types are `BOARDING|CENTER_OWNED|SCHOOL|TEMPORARY|OTHER`
with lifecycle `ACTIVE|ENDED`. Permissions are explicit codes with
lifecycle `ACTIVE|REVOKED`. Duplicate active exact assignment type and
duplicate active permission code are rejected. Assignment, membership
and ownership do not create a permission. There is no client list or
mutation RPC. `has_active_equine_center_permission` is server-internal,
requires `granted_at <= now()`, and is not executable by `anon` or
`authenticated`.

Migration `014_disciplines.sql` (merged PR #14) adds
`disciplines`, `discipline_translations` and `equine_disciplines`.
Lifecycle is Product Owner approved `ACTIVE|INACTIVE`. Codes are unique
and unseeded. `sort_order` is a non-negative display hint (duplicates
allowed). Translations use BCP 47 locales. `experience_level` is optional
free text, not a qualification. There is no client catalog or assign RPC
and no Expo selector.

Migration `015_qualifications.sql` (merged PR #15) adds
`qualification_systems`, `qualification_levels` and
`rider_qualifications`. Systems may be market-scoped. Level codes are
unique per system. `level_order` is a non-negative hint, not an
international equivalence. Rider qualification belongs to PERSON.
Verification states are exactly
`DECLARED|PENDING|VERIFIED|REJECTED|EXPIRED`. A rider cannot mark their
own qualification `VERIFIED`. `verified_by_person_id` does not imply
Center authority. No seed, no equivalence tables, no client RPC.

Migration `016_rider_assessments.sql` (merged PR #16) adds
`rider_assessments`, `rider_assessment_disciplines` and
`rider_assessment_restrictions`. Types
`ACCESS_TEST|RIDING_LESSON|COURSE|PRACTICAL_TEST|OTHER`. States
`DRAFT|PENDING|VALID|REJECTED|REVOKED|EXPIRED`. Assessor cannot assess
themselves. Creating/validating requires active `ASSESSOR` membership at
that Center. Historical rows remain after membership end. No client RPC.

Migration `017_equine_requirements.sql` (merged PR #17) adds
`equine_requirements` attached to an equine. Types and sources follow
Architecture 2.1. Typed value columns are mapped per type. No client CRUD,
no eligibility evaluation, no stored rider age.

Migration `018_center_services.sql` (merged PR #18) adds
`center_services` and `service_equines`. Types are
`EQUINE_SESSION|RIDER_ASSESSMENT|ZERO_SESSION`. `ZERO_SESSION` is a
service kind, not a Zero Session record. Linking an equine requires
effective `MANAGE_REQUIREMENTS` at the service Center. Membership and
assignment are not sufficient. Product Owner (2026-09-02) approved
`center_services.status` and `service_equines.status` as
`ACTIVE|INACTIVE` (catalog pair reuse). `authorization_policy` stays
optional trimmed non-empty free text; no policy enum in 018. No client
create/link RPC.

`has_active_center_role(person_id, center_id, role_code)` remains
server-internal and is not executable by `anon` or `authenticated`. Center
membership does not grant equine authority.

No `service_role` credential is present in the application. Clients do not
receive table `INSERT`/`UPDATE`/`DELETE`/`SELECT` on identity, guardian,
rider-profile, center, membership or equine tables.

Usual development: `npm run start:local`. Remote: `npm run start:remote`.

GitHub Actions (`.github/workflows/quality-gate.yml`) is the permanent
automated quality gate for every pull request (including stacked PRs) plus
`workflow_dispatch`. App quality and local PostgreSQL/SQL suites run on
GitHub-hosted runners with `contents: read`, no project secrets, and no
linked/remote Supabase. The cloud clone does not replace that gate. First
proven-green run:
https://github.com/Alexfdez-hub/app-caballos-ok/actions/runs/33629791578
(head `93788a208b50c8e5f652b9c94ee3c1d230c840e7`; App quality PASS;
PostgreSQL quality PASS). A3/A5 workflow generalization (no target-branch
filter, inherited-migration check, `npm run test:sql`, no `supabase status`
in diagnostics) is recorded after the replacement run on this branch.

## Current limitations by design

- No RiderApp / OwnerApp / CenterApp split and no role selector
- No public Center directory or map
- No Center self-service onboarding, self-verification or invitations
- No client membership grant/revoke or first-admin bootstrap
- No public equine directory, media upload, availability, booking or
  equine–center assign/grant UI
- No discipline catalog UI, selector or seeded codes
- No qualification catalog UI, selector, seed or equivalences
- No booking, assessment mutation, payment, or review UI
- No services catalog or eligibility UI
- No single `users.role` model

Migration `019_zero_sessions_authorizations.sql` is on Ready PR #20.
This branch adds `020_calendar.sql`: `equine_availability_rules` and
`equine_calendar_blocks`. Availability is potential; calendar blocks
are canonical occupancy. ACTIVE same-equine overlapping ranges are
excluded. Authority is effective `MANAGE_AVAILABILITY`. No client CRUD.
No bookings table or `confirm_booking()`. Remote remains aligned
through `018`; this agent does not deploy. The next planned SQL
migration is `021` and is **not** started.

## Historical records

`docs/REMOTE_DATABASE_INVENTORY.md` remains the authoritative historical
inventory of the retired legacy schema. Phase 3A–3E reports remain
historical. Git history preserves the deleted prototype application.
