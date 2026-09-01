# Phase 3D — Centers foundation

**Project:** app-caballos-ok
**Phase:** 3D — Centers foundation
**Migration:** `supabase/migrations/009_centers.sql`
**Date:** 2026-09-01
**Architecture:** Data Architecture 2.1
**Baseline:** `main` `1d94807` (Phase 3C merged, PR #6)
**Branch:** `refactor/phase-3d-centers-foundation`

## Design selected

- A Center is an organization, not an Auth user and not a person.
- Architecture §5 lists `equestrian_centers` and `center_languages` together;
  `center_memberships` is the next migration (`010`). Languages are included
  in 009.
- Architecture 2.1 names `verification_status` and `status` without
  enumerating Center values. This phase constrains them so invalid strings
  are rejected. The values do not authorize verification or publication.
- Creation, verification and management authority are not defined for
  ordinary clients. There is no self-service RPC and no owner/manager column.
- Public discovery is deferred. Tables have no SELECT for `anon` or
  `authenticated`. ACTIVE/VERIFIED does not open a directory.
- Center Policy activation requires membership, which is deferred.

## Product Owner decision — Center lifecycle values

**Date:** 2026-09-01  
**Authority:** Product Owner, explicit approval after Phase 3D implementation.  
**Architecture 2.1:** names `status` and `verification_status` on
`equestrian_centers` without enumerating values. The lists below are the
approved Center foundation enumerations. They are not a copy of qualification
or guardian enums.

### `equestrian_centers.status`

`DRAFT` | `ACTIVE` | `INACTIVE` | `ARCHIVED`  
Default: `DRAFT`.

### `equestrian_centers.verification_status`

`UNVERIFIED` | `PENDING` | `VERIFIED` | `REJECTED`  
Default: `UNVERIFIED`.

### Approved semantics

1. `status` and `verification_status` are independent.
2. `ACTIVE` does not mean publicly discoverable.
3. `VERIFIED` does not create membership, management authority, Center Policy
   acceptance, services, assessments or public listing.
4. `ARCHIVED` preserves historical records.
5. Migration 009 does not enforce transition paths because no authorized
   Center onboarding/verification workflow exists yet.
6. Ordinary clients cannot perform state transitions.
7. Future tokens such as `SUSPENDED`, `EXPIRED` or `REVOKED` must be
   introduced only through a new forward migration if later product
   requirements need them.
8. Never rewrite migration 009 after deployment.

There is no `docs/07_DECISION_LOG.md` (or other current decision-log file) in
this repository. This section and `docs/MIGRATION_STATUS.md` are the
authoritative record of the decision.

## Migration contents

`009_centers.sql` creates:

### `equestrian_centers`

- `id uuid pk`
- `name`, unique normalized `slug`
- `description`
- `country_code` FK → `markets`
- `region`, `city`, `postal_code`, `address_line`
- `latitude` / `longitude` (both null or both in range)
- `timezone`, `default_currency` (optional; currency `AAA` form if present)
- `verification_status` default `UNVERIFIED`
  (`UNVERIFIED|PENDING|VERIFIED|REJECTED`)
- `status` default `DRAFT` (`DRAFT|ACTIVE|INACTIVE|ARCHIVED`)
- timestamps

### `center_languages`

- composite PK `(center_id, locale)`
- locale `xx` or `xx-YY`
- no `ON DELETE CASCADE` (center delete is restricted)

### RLS and privileges

- RLS enabled, no client policies
- `REVOKE ALL` from `anon` and `authenticated` on both tables
- no functions/RPCs

## Authority boundary

- Creation: controlled process outside the app. Clients cannot INSERT.
- Verification: clients cannot UPDATE, including `VERIFIED`.
- Management: no membership, no self-assignment.
- Reads: no public or authenticated table SELECT in this phase.

## Frontend

Explore → Hípicas and Profile → Mis centros stay coming-soon with copy that
the domain exists but onboarding, verification, memberships and directory
are not in the app. No fabricated Center list.

## Deferred

- `center_memberships` and staff roles
- Center Policy activation
- self-service onboarding and verification UI
- assessments, equines, services, bookings
- search/map discovery

## Architecture conflicts

None. Enumerating Center status values is a documented foundation constraint
because Architecture 2.1 left the enumerations unspecified. Product Owner
later approved those exact values and semantics (see the decision section
above).

## Tests and checks

| Command | Result |
|---|---|
| `npx supabase db reset --local` | PASS — replayed `001–009` |
| `npm run test:centers` | PASS — SQL/RLS/P0 |
| `npm run test:identity` | PASS |
| `npm run test:guardians` | PASS — SQL/RLS plus concurrency |
| `npm run test:riders` | PASS |
| `npm run typecheck` | PASS |
| `npm run test:auth` | PASS — 24 tests |
| `npx expo-doctor` | PASS — 18/18 |
| `git diff --check` | PASS |
| Migrations `001–008` diff | PASS — empty |

## Remote

Do not deploy 009 until Product Owner approval. Linked remote is aligned
through 008.
