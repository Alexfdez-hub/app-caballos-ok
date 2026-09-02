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

## Equine enumerations

**Architecture 2.1:** freezes `equine_type` as `HORSE | PONY`. It names
`status`, `visibility_status` and `media_type` without enumerating values.

There is no `docs/07_DECISION_LOG.md` in this repository. This section and
`docs/MIGRATION_STATUS.md` are the authoritative record. Later tokens need a
new forward migration. Do not rewrite 011 after deployment.

### `equines.status` — lifecycle (Product Owner confirmed)

**Product Owner, 2026-09-02.** Confirmed tokens:

`ACTIVE` | `INACTIVE` | `ARCHIVED` | `DECEASED`
Default: `ACTIVE`.

| Value | Meaning |
|---|---|
| `ACTIVE` | Operational catalog record currently in force. Default for a provisioned equine. |
| `INACTIVE` | Temporarily not operational. The row is retained. This is not calendar occupancy and not availability. |
| `ARCHIVED` | Retained historical record of a living equine withdrawn from operational use. Distinct from `DECEASED`. |
| `DECEASED` | The equine has died. Distinct from `ARCHIVED`. |

**Why this set, not Center `DRAFT\|ACTIVE\|INACTIVE\|ARCHIVED`:** Center
`DRAFT` models unpublished organization onboarding (default `DRAFT` in 009).
Architecture 2.1 does not name `DRAFT` for equines. Publication intent for
equines is `visibility_status`. An equine row is a catalog identity,
provisioned outside the app; the operational default is `ACTIVE`.

Not included:

- `DRAFT` — Center onboarding semantics; not supported by equine architecture.
- `RETIRED` — rejected. Not a Product Owner token.
- `SUSPENDED` / `EXPIRED` / `REVOKED` — no management workflow in this phase.

Migration 011 does not enforce transition triggers. Ordinary clients cannot
change status. Historical rows are retained; archiving or recording death is
not a physical DELETE.

### `equines.visibility_status`

`PRIVATE` | `PUBLIC`.
Default: `PRIVATE`.

| Value | Meaning |
|---|---|
| `PRIVATE` | No stored publication intent. Default. |
| `PUBLIC` | Stored publication intent only. Does not grant `anon`/`authenticated` SELECT, directory listing or edit authority in 011. |

**Justification:** Architecture §22 says equine public read is only for
publishable rows. Publishability cannot be evaluated until ownership and
`PRIMARY_MANAGER` exist (012). Codex review confirmed this pair stays.

### `equine_media.media_type`

`PHOTO`.
No default other than the column being `NOT NULL` (callers must supply it).

**Justification:** Architecture 2.1 names `media_type` without values.
Architecture does not mention `VIDEO` for `equine_media`. Codex review
confirmed `PHOTO` only. Storage buckets and policies remain a later phase.

## Migration contents

`011_equines.sql` creates:

### `equines`

- `id uuid pk`
- trimmed non-empty `name`
- `equine_type` `HORSE|PONY`
- optional `birth_date` (`NULL` or `<= (created_at AT TIME ZONE 'UTC')::date`;
  age is not stored and is not an access rule)
- optional `sex`, `breed`, `height_cm`, `description`,
  `temperament_description`
- `height_cm` strictly positive when present
- `sex`, when present, must be trimmed and non-empty (not an enumerated
  sex vocabulary)
- `status` default `ACTIVE` (`ACTIVE|INACTIVE|ARCHIVED|DECEASED`, Product
  Owner confirmed)
- `visibility_status` default `PRIVATE` (`PRIVATE|PUBLIC`)
- `created_at`, `updated_at`
- indexes on `equine_type` and `status`
- no `owner_id`, `manager_id`, `center_id`, Auth UUID or person shortcut

### `equine_media`

- `id uuid pk`
- `equine_id` FK → `equines` (no `ON DELETE CASCADE`)
- trimmed non-empty `storage_path` (path string only; UNIQUE via
  `equine_media_storage_path_key`)
- `media_type` `PHOTO`
- non-negative `sort_order` default 0
- `is_primary` default false; at most one primary row per equine
- `created_at`
- index on `equine_id`
- no upload workflow, bucket, Storage objects or storage policy

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
unspecified. Product Owner confirmed `ACTIVE|INACTIVE|ARCHIVED|DECEASED`
with `DECEASED ≠ ARCHIVED` and without `RETIRED`. Center `DRAFT` was not
copied. Ownership/management were not collapsed onto `equines`. Architecture
§22 public-read-if-publishable is not implemented in 011 because
publishability requires 012; deny-by-default preserves a later secure read
path. `birth_date` is optional and must not be after the UTC calendar date of
`created_at` (`(created_at AT TIME ZONE 'UTC')::date`); age is not stored.
Unique `storage_path` is metadata uniqueness only and does not create a
Storage bucket.

Official Supabase RLS / Data API (CLI 2.116.0; docs and changelog 45329):
RLS with no policies denies rows; `REVOKE ALL` from `anon`/`authenticated`
also keeps tables off the Data API. Security was not weakened to expose
tables through PostgREST.

## Tests and checks

GitHub Actions (`.github/workflows/quality-gate.yml`) is the permanent
automated quality gate. It triggers on every `pull_request` (no target-branch
filter, so stacked PRs run) plus `workflow_dispatch`. It uses `pull_request`
(never `pull_request_target`), `contents: read`, no project secrets, and
local Docker/Supabase only. Inherited migrations already present at the PR
base SHA must not be modified, deleted or renamed; new migration files are
allowed. PostgreSQL quality runs `npm run test:sql` after local
`db reset --local`. Failure diagnostics are Docker ps plus filtered
container logs; they do not print `supabase status`.

Proven green: Quality gate run
https://github.com/Alexfdez-hub/app-caballos-ok/actions/runs/33629791578
on `93788a208b50c8e5f652b9c94ee3c1d230c840e7`. Conclusion: success.

### Checks Grok ran in the cloud workspace

| Command | Result |
|---|---|
| `node --version` | PASS — `v22.14.0` |
| `npm ci` | PASS |
| `npm run test:auth` | PASS — 38/38 |
| `npm run typecheck` | PASS |
| `npx expo-doctor` | PASS — 18/18 |
| `git diff --check` | PASS |
| `001–010` vs `origin/main` | PASS — empty; only `011_equines.sql` added among migrations |

Docker is not installed in this cloud clone. SQL suites were not executed
here.

### Checks executed by GitHub Actions

Run `33629791578` on head `93788a208b50c8e5f652b9c94ee3c1d230c840e7`.
Workflow: Quality gate. Event: `pull_request`. Conclusion: **success**.

| Job | Result | URL |
|---|---|---|
| App quality | PASS (33s) | https://github.com/Alexfdez-hub/app-caballos-ok/actions/runs/33629791578/job/100246131581 |
| PostgreSQL quality | PASS (3m11s) | https://github.com/Alexfdez-hub/app-caballos-ok/actions/runs/33629791578/job/100246131894 |

App quality executed: `npm ci`, `npm run test:auth`, `npm run typecheck`,
`npx expo-doctor`, `git diff --check`, inherited migrations unchanged versus
PR base. PostgreSQL quality now runs `npm run test:sql` on later heads
(identity, guardians including two-session concurrency, riders, centers,
memberships, equines). Local Supabase is stopped in an `always()` step.
Failure diagnostics do not print `supabase status`.

Earlier failed run (superseded):
https://github.com/Alexfdez-hub/app-caballos-ok/actions/runs/33629287665
on `847583b993a31a69b38b249218c2ab230d926c2f` (trailing whitespace in this
report; static `FROM storage.policies` parse error). Fixed in `93788a2`.

### Checks not executed in the cloud workspace

| Command | Result |
|---|---|
| `npx supabase db reset --local` | NOT RUN here — `docker: command not found` |
| `npm run test:equines` | NOT EXECUTED here against PostgreSQL — executed by GitHub Actions |
| `npm run test:memberships` | NOT EXECUTED here against PostgreSQL — executed by GitHub Actions |
| `npm run test:centers` | NOT EXECUTED here against PostgreSQL — executed by GitHub Actions |
| `npm run test:riders` | NOT EXECUTED here against PostgreSQL — executed by GitHub Actions |
| `npm run test:identity` | NOT EXECUTED here against PostgreSQL — executed by GitHub Actions |
| `npm run test:guardians` | NOT EXECUTED here against PostgreSQL — executed by GitHub Actions |
| local advisors | NOT RUN here — no local Supabase |

Cloud clone: Docker was not installed. SQL/RLS P0 execution is the GitHub
Actions PostgreSQL quality job, which passed on run `33629791578`.

## Remote

Linked development project: `efkauegdlmfkonzwyyiv`.

Migration `011_equines.sql` has **not** been deployed remotely. Product
Owner confirmed the lifecycle tokens. Do not apply 011 from this correction
pass. A linked push still requires an explicit Product Owner deploy
authorization.
