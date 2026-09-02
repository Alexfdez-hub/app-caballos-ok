# Phase 5B — Qualifications foundation

**Project:** app-caballos-ok
**Phase:** 5B — Qualifications
**Migration:** `supabase/migrations/015_qualifications.sql`
**Date:** 2026-09-02
**Architecture:** Data Architecture 2.1
**Baseline:** `origin/main` `6f916e7abb6834349cffef173bf307e51131123c` (merge of PR #14)
**Branch:** `refactor/phase-5b-qualifications`

This PR targets `main`. Do not merge. Do not deploy `015`. Product Owner
will merge after review. This agent will not merge or deploy.

## Current baseline versus historical branch-time statements

Verified 2026-09-02 before this branch was created:

- PRs #11–#14 are **merged into `main`**.
- `origin/main` HEAD is `6f916e7abb6834349cffef173bf307e51131123c`.
- Migrations `001`–`014` exist on `main`. `015` did not exist and was not
  previously started.
- Product Owner states remote project `efkauegdlmfkonzwyyiv` is aligned
  through `014`. Remote schema/RLS verification passed.
  Android/Expo Go smoke PASS.
- This agent does **not** deploy and does **not** modify remote.

`docs/PHASE_5A_DISCIPLINES_REPORT.md` and earlier MIGRATION_STATUS/PLAN
text described `011`–`014` as stacked and not deployed. Those statements
were true at Phase 5A branch time. They are historical. They are not
rewritten here. Current state is the merge of #11–#14 plus remote
alignment through `014`.

## Design selected

- Tables: `qualification_systems`, `qualification_levels`,
  `rider_qualifications`.
- Systems are configurable. `country_code` is an optional FK to `markets`
  (market/country scoped when present; null means not bound to one market).
- System `code` is globally unique.
- A level belongs to exactly one system. Level `code` uniqueness is
  scoped to `(qualification_system_id, code)`.
- `level_order` is a non-negative ordering hint inside one system.
  Duplicates are allowed. It is not an international equivalence.
- `discipline_id` on a level is optional. Architecture 2.1 lists the
  column without requiring it.
- Rider qualification belongs to `rider_person_id` (PERSON), never to an
  account.
- Verification states exactly:
  `DECLARED | PENDING | VERIFIED | REJECTED | EXPIRED`.
- Frozen issuer/document/history fields preserved:
  `certificate_number`, `issued_at`, `expires_at`,
  `verified_by_person_id`, `document_path`, `created_at`.
- `expires_at` must not precede `issued_at` when both exist. `now()` is
  not used in a table CHECK. Stored `EXPIRED` is not computed from clock
  time.
- `verified_by_person_id` is a person identity. It is required when
  status is `VERIFIED`. It cannot equal `rider_person_id`. It does not
  imply Center membership, equine permission or assessment authority.
- System/level `status` reuses the Product Owner-approved catalog
  operational pair `ACTIVE | INACTIVE` (2026-09-02, disciplines). That
  is not a rider verification state.
- No equivalence tables. No seed. No assessment/authorization/eligibility.
- No client list/declare/verify RPC. Passport already has truthful
  coming-soon copy and does not require a caller-scoped read.
- Deny-by-default. A rider cannot mark their own qualification `VERIFIED`
  (CHECK plus no client writes).

## Migration contents

### `qualification_systems`

`id`, unique `code`, `name`, optional `country_code` → `markets`,
optional `issuing_organization`, `status`, `created_at`.

### `qualification_levels`

`id`, `qualification_system_id`, `code`, non-negative `level_order`,
`name`, optional `description`, optional `discipline_id` → `disciplines`,
`status`, `created_at`. Unique `(qualification_system_id, code)`.

### `rider_qualifications`

`id`, `rider_person_id` → `persons`, `qualification_level_id`,
optional `certificate_number`, `issued_at`, `expires_at`,
`verification_status` default `DECLARED`, optional
`verified_by_person_id` → `persons`, optional `document_path`,
`created_at`. Indexes on rider, level and verifier.

### Access

RLS on, no client policies, `REVOKE ALL` from `anon`/`authenticated`.
No functions.

## Frontend

None in this phase. Passport keeps existing truthful copy that a rider
profile does not accredit a qualification and that there are no
equivalences in the app. No selector and no fake catalog.

## Tests

`npm run test:qualifications` is appended to `npm run test:sql`.
Inherited migrations `001`–`014` are unchanged versus `main`.
008/012/013/014 SQL tests allow 015 tables and still forbid
assessments/bookings as applicable.

P0 coverage includes: invalid market/system/discipline/rider/level FKs;
duplicate global system code; duplicate scoped level code; same level
code allowed in another system; duplicate `level_order` allowed;
invalid dates; invalid verification status; `VERIFIED` without verifier;
self-verification rejected; direct client SELECT/INSERT/UPDATE/DELETE
denied; catalog unseeded; no Galope/equivalence tables; absence of
016+ domains.

## Next phase

`016_rider_assessments.sql` on branch `refactor/phase-6a-rider-assessments`,
stacked on this branch. Do not merge. Do not deploy. Do not start 019.
