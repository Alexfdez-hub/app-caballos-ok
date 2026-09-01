# Phase 3C — Rider profile and Passport foundations

**Project:** app-caballos-ok
**Phase:** 3C — Rider profile / Passport foundations
**Migration:** `supabase/migrations/008_rider_profiles.sql`
**Date:** 2026-09-01
**Architecture:** Data Architecture 2.1
**Baseline:** `main` `2ade001` (Phase 3B merged, PR #5)
**Branch:** `refactor/phase-3c-rider-profile-passport`

## Design selected

- PERSON remains distinct from ACCOUNT. `rider_profiles.person_id` is the
  domain identity and is never an Auth UUID.
- A person has zero or one rider profile. Other capabilities (guardian,
  future owner/center member) are unchanged by creating a profile.
- Access follows 006/007: RLS enabled, deny-by-default, no client table
  policies, `REVOKE ALL` from `anon`/`authenticated`, SECURITY DEFINER RPCs
  with `search_path = pg_catalog, public`.
- Actor identity is derived from `auth.uid()` → `user_accounts` → `persons`.
  RPCs do not accept `person_id`.
- Self-service for the authenticated caller only. Guardian-managed create or
  edit of a minor’s profile is deferred: Architecture 2.1 does not define the
  required relationship state, Rider Policy behavior for the minor, or whether
  guardian consent is required for profile creation versus later activity.
  A minor `persons` row can still structurally own a `rider_profiles` row.
- `profile_visibility` is not enumerated in Architecture 2.1. This phase
  stores `PRIVATE` (default) or `PUBLIC`. PUBLIC is stored intent only; there
  is no public SELECT/list RPC.
- Creating a profile does not check or write `RIDER_POLICY` acceptance. No
  activation status machine was added. Future sensitive Rider actions must
  call `has_accepted_required_policy('RIDER_POLICY', market)` when a current
  document exists: bookings/eligibility, assessments, Session Zero, and
  rider-equine authorization.
- Product Owner authorized this phase before Centers. Migration number `008`
  is used for rider profiles; planned Centers becomes `009_centers.sql`.

## Migration contents

`008_rider_profiles.sql` creates:

### Table

- `rider_profiles`
  - `person_id uuid pk/fk` → `persons`
  - `bio text` (null or ≤ 2000 chars)
  - `experience_start_year smallint` (null or 1900–2100)
  - `profile_visibility text not null default 'PRIVATE'`
    (`PRIVATE` | `PUBLIC`)
  - `created_at` / `updated_at`

The upsert RPC also rejects an experience year after the current UTC calendar
year. There is no Galope, qualification, assessment, center, or riding-level
column.

### RLS and privileges

- RLS enabled, no client policies.
- `REVOKE ALL` on `rider_profiles` from `anon` and `authenticated`.
- Functions: `REVOKE ALL` from `PUBLIC`/`anon`/`authenticated`, then
  `GRANT EXECUTE` to `authenticated` only.

### RPCs

- `get_my_rider_profile()` — zero or one row for the caller’s person.
- `upsert_my_rider_profile(p_bio, p_experience_start_year, p_profile_visibility)`
  — insert or update only that person; no impersonation parameter.

## Rider Policy boundary

Profile create/update does not create, delete, or require policy acceptance.
`has_accepted_required_policy` remains the helper for later sensitive Rider
actions. Historical acceptances are untouched.

## Minors / guardian boundary

No guardian RPC can create or edit a rider profile. Direct table writes remain
unavailable to clients. Structural fixture rows may exist for a minor person
without an Auth account. A rider profile does not create guardian consent.

## Frontend

Passport tab (`EquestrianPassportScreen` + `EditRiderProfileScreen`):

- loads the caller’s real profile via RPC;
- create/edit bio, experience start year, visibility;
- loading, empty, error and saved (return after save) states;
- deferred sections remain coming-soon with truthful copy;
- no fabricated qualifications, Galopes, assessments, authorizations or
  activity;
- no policy, guardian or authorization decisions in the screen.

## Tests and checks

| Command | Result |
|---|---|
| `npx supabase db reset --local` | PASS — replayed `001–008` |
| `npm run test:riders` | PASS — SQL/RLS/P0 |
| `npm run test:identity` | PASS |
| `npm run test:guardians` | PASS — SQL/RLS/P0 plus two-session concurrency |
| `npm run typecheck` | PASS |
| `npm run test:auth` | PASS — 24 tests |
| `npx expo-doctor` | PASS — 18/18 |
| `git diff --check` | PASS |
| Migrations `001–007` diff | PASS — empty |

`npm run test:riders` failed once on integer→smallint overload and once on an ambiguous `ON CONFLICT (person_id)` inside the RETURNS TABLE function. Both were fixed in this phase before publication.

## Deferred

- Public rider directory / public SELECT
- Guardian-managed minor profile create/edit
- Minority gating of self-service (requires a collected market)
- `RIDER_POLICY` acceptance UX and activation of sensitive Rider actions
- Disciplines, qualifications, assessments, centers, equines, Session Zero,
  authorizations, bookings

## Architecture conflicts

None. Occupying `008` for rider profiles is an explicit Product Owner
roadmap override of the historical `008_centers` filename, documented in
`docs/MIGRATION_PLAN.md`. Architecture 2.1 table shape is unchanged.

## Known issues

- An authenticated minor who already has an Auth account can currently
  upsert their own profile because minority evaluation needs a market that
  the person record does not yet store. Guardian-managed editing remains
  unavailable.
- PUBLIC visibility is not shown to other users.

## Bugbot

Cursor Bugbot (Manual Only, Autofix OFF) found two valid hydration issues:

1. The edit form re-synced from a focus refetch and could wipe unsaved input.
2. A failed first fetch still locked hydration, so a later successful load
   could leave a blank form that might overwrite an existing profile.

Hydration now waits for a successful load and runs once. The editor stays
closed until that happens. GitHub Bugbot still needs to be run on the pull
request after it is opened.
