# Phase 3F — Equines foundation

**Project:** app-caballos-ok
**Phase:** 3F — Equines foundation
**Migration:** `supabase/migrations/011_equines.sql`
**Date:** 2026-09-02
**Architecture:** Data Architecture 2.1
**Baseline:** `main` `9ac317295a5a983c6b74284af17f7e9fb305a8c7` (docs PR #10; Phase 3E merged and documented)
**Branch:** `refactor/phase-3f-equines-foundation`

## Design selected

- `equine` is the generic entity. `HORSE` and `PONY` are types, not separate
  tables and not access rules.
- Ownership, management, center assignment and center permission are deferred
  to 012/013. They are not collapsed onto `equines`.
- PUBLIC `visibility_status` is stored publication intent only. It is not
  edit authority and does not open a public directory in this phase.
- Creation, edit, upload and “my equines” authority are not defined for
  ordinary clients. There is no client RPC.
- Provisioning remains a controlled process outside Expo.
- Center membership and rider profile do not grant equine authority.

## Phase 3F implementation decision — enumerations

**Architecture 2.1:** freezes `equine_type` as `HORSE | PONY`. It names
`status`, `visibility_status` and `media_type` without enumerating values.

**Authority of this list:** Phase 3F implementation decision, recorded here
and in `docs/MIGRATION_STATUS.md`. **Product Owner confirmation is required
before remote deployment.** There is no `docs/07_DECISION_LOG.md` in this
repository.

These values are not copied from another domain enum without justification.
They are CHECK-constrained. Later tokens need a new forward migration. Do
not rewrite 011 after deployment.

### `equines.status` — lifecycle

`ACTIVE` | `INACTIVE` | `ARCHIVED`  
Default: `ACTIVE`.

| Value | Meaning |
|---|---|
| `ACTIVE` | Operational catalog record currently in force. Default for a provisioned equine. |
| `INACTIVE` | Temporarily not operational. The row is retained. This is not calendar occupancy and not availability. |
| `ARCHIVED` | Retained historical record. Not operational. |

**Why this set, not Center `DRAFT\|ACTIVE\|INACTIVE\|ARCHIVED`:** Center
`DRAFT` models unpublished organization onboarding (default `DRAFT` in 009).
Architecture 2.1 does not name `DRAFT` for equines. Publication intent for
equines is `visibility_status`. “Equino publicable” in Architecture §7
depends on later ownership + `PRIMARY_MANAGER`, which 011 must not invent.
An equine row is a living catalog identity, provisioned outside the app;
the operational default is therefore `ACTIVE`, not an unpublished Center
draft.

Not included:

- `DRAFT` — Center onboarding semantics; not supported by equine architecture.
- `SUSPENDED` / `EXPIRED` / `REVOKED` — no management workflow in this phase.

Migration 011 does not enforce transition triggers. Ordinary clients cannot
change status. Historical rows are retained; archiving is not a physical
DELETE.

### `equines.visibility_status`

`PRIVATE` | `PUBLIC`  
Default: `PRIVATE`.

| Value | Meaning |
|---|---|
| `PRIVATE` | No stored publication intent. Default. |
| `PUBLIC` | Stored publication intent only. Does not grant `anon`/`authenticated` SELECT, directory listing or edit authority in 011. |

**Justification:** Architecture §22 says equine public read is only for
publishable rows. Publishability cannot be evaluated until ownership and
`PRIMARY_MANAGER` exist (012). The same stored-intent pattern was used for
`rider_profiles.profile_visibility` in 008 (`PRIVATE|PUBLIC`, public read
not implemented). That is a publication-intent pattern, not a Rider-domain
enum copied onto equines. `UNLISTED` / `DISCOVERABLE` were not invented.

### `equine_media.media_type`

`PHOTO`  
No default other than the column being `NOT NULL` (callers must supply it).

**Justification:** Architecture 2.1 names `media_type` without values.
Session evidence uses photo types. Architecture does not mention `VIDEO`
for `equine_media`. `VIDEO` is not added. Storage buckets and policies
remain a later phase.

## Migration contents

`011_equines.sql` creates:

### `equines`

- `id uuid pk`
- trimmed non-empty `name`
- `equine_type` `HORSE|PONY`
- optional `birth_date`, `sex`, `breed`, `height_cm`, `description`,
  `temperament_description`
- `height_cm` strictly positive when present
- `sex`, when present, must be trimmed and non-empty (not an enumerated
  sex vocabulary)
- `status` default `ACTIVE` (`ACTIVE|INACTIVE|ARCHIVED`)
- `visibility_status` default `PRIVATE` (`PRIVATE|PUBLIC`)
- `created_at`, `updated_at`
- indexes on `equine_type` and `status`
- no `owner_id`, `manager_id`, `center_id`, Auth UUID or person shortcut

### `equine_media`

- `id uuid pk`
- `equine_id` FK → `equines` (no `ON DELETE CASCADE`)
- trimmed non-empty `storage_path` (path string only)
- `media_type` `PHOTO`
- non-negative `sort_order` default 0
- `is_primary` default false; at most one primary row per equine
- `created_at`
- index on `equine_id`
- no upload workflow, bucket or storage policy

### RLS and privileges

- RLS enabled on both tables, no client policies
- `REVOKE ALL` from `anon` and `authenticated`
- no functions/RPCs
- no table SELECT for a public directory or “my equines”

## Authority boundary

Documentation does not define who may create or edit an equine until
ownership and management exist.

Therefore:

- Initial provisioning stays outside Expo.
- Ordinary clients cannot INSERT/UPDATE/DELETE equines or media.
- The app does not simulate a working equine catalog, owner or manager UI.
- Center membership is not equine authority.
- Rider profile existence is not equine authority.
- `PUBLIC` is not a SELECT grant.

Missing workflow (deferred, not invented):

- ownership percentages and owner type PERSON/CENTER
- `PRIMARY_MANAGER` / co-manager assignments
- owner-manager RPCs
- center assignments and equine-center permissions
- public directory / map
- Expo create/edit/upload
- Storage `equine-media` bucket and policies

A later forward migration can add a secure read path (publishable public
read and/or caller-owned list) once 012/013 exist. 011 preserves deny-by-default
so that path is not pre-empted by a broad policy.

## Frontend

Explore → Caballos y ponis and Profile → Mis equinos / Equinos que gestiono
stay coming-soon. Copy says the equine domain exists while public discovery,
ownership, management, center assignment, availability, booking and media
upload remain unavailable. No fabricated equine cards, directory, create/edit
or upload UI.

## Deferred

- 012 ownerships / management / percentages / `PRIMARY_MANAGER` / owner-manager RPCs
- 013 center assignments / permissions / boarding / school equine
- disciplines, qualifications, assessments, requirements, services
- Zero Session, rider-equine authorizations
- availability, calendar, bookings, sessions/evidence
- activities, incidents, reviews, audit
- public directory/map
- Expo create/edit
- media upload/delete
- storage buckets/policies
- policy activation UX

## Architecture conflicts

None. Enumerating equine lifecycle, visibility and media type is a documented
foundation constraint because Architecture 2.1 left those enumerations
unspecified. Center `DRAFT` was not copied. Ownership/management were not
collapsed onto `equines`. Architecture §22 public-read-if-publishable is not
implemented in 011 because publishability requires 012; deny-by-default
preserves a later secure read path.

Official Supabase RLS / Data API (CLI 2.116.0; docs and changelog 45329):
RLS with no policies denies rows; `REVOKE ALL` from `anon`/`authenticated`
also keeps tables off the Data API. Security was not weakened to expose
tables through PostgREST.

## Tests and checks

See the pull request and `docs/MIGRATION_STATUS.md` for commands actually
executed in this environment. Local PostgreSQL execution of SQL tests
requires Docker, which this cloud clone does not provide and must not
install.

## Remote

Linked development project: `efkauegdlmfkonzwyyiv`.

Migration `011_equines.sql` has **not** been deployed remotely. Product
Owner confirmation of the Phase 3F enumerations is required before any
linked push. Do not apply 011 without that confirmation.
