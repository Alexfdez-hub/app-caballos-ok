# Phase 5A — Disciplines foundation

**Project:** app-caballos-ok
**Phase:** 5A — Disciplines
**Migration:** `supabase/migrations/014_disciplines.sql`
**Date:** 2026-09-02
**Architecture:** Data Architecture 2.1
**Parent:** Ready PR #13 `refactor/phase-4b-equine-center-relations`
**Branch:** `refactor/phase-5a-disciplines`

This PR is stacked on Phase 4B. It must not merge before PR #13 (and #12,
#11). Product Owner will retarget after the parents merge. This agent will
not retarget or merge. Migration `014` is local only and is not deployed.

## Design selected

- Tables: `disciplines`, `discipline_translations`, `equine_disciplines`.
- Lifecycle `ACTIVE | INACTIVE`. Not ARCHIVED, not a qualification state.
- Unique `disciplines.code`. Unique translation locale per discipline.
- Unique active association is equine+discipline (one row per pair).
- No seed. Architecture forbids hardcoded Galopes and automatic
  international equivalences. There is no Product Owner-approved catalog
  in this repository (`supabase/seed.sql` is empty by design).
- `experience_level` is optional free text. It is not constrained to
  invented tokens and is not a qualification.
- No qualification_systems / levels / rider_qualifications / assessments.
- No client list, create, or assign RPC. No Expo selector and no fake
  catalog data in the app.

## Migration contents

### `disciplines`

`id`, unique `code`, `status`, `sort_order`, `created_at`.

### `discipline_translations`

`discipline_id`, BCP 47 `locale` (same pattern as `center_languages`),
trimmed `name`, optional `description`.

### `equine_disciplines`

`equine_id`, `discipline_id`, optional `experience_level`, optional `notes`.
Index on `discipline_id`. Unique `(equine_id, discipline_id)`.

### Access

RLS on, no client policies, `REVOKE ALL` from `anon`/`authenticated`.

## Frontend

None in this phase. Passport and Explore do not gain a discipline picker.

## Tests

`npm run test:disciplines` is appended to `npm run test:sql`. Inherited
migrations at the parent SHA must remain unchanged; 014 is a new file.
008/012/013 SQL tests allow 014 tables and still forbid qualifications
and bookings.

## Next phase

`015_qualifications.sql`. Do not start 015. Do not merge. Do not deploy.
