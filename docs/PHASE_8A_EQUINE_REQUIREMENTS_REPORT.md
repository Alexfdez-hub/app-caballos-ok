# Phase 8A — Equine requirements foundation

**Project:** app-caballos-ok
**Phase:** 8A — Equine requirements
**Migration:** `supabase/migrations/017_equine_requirements.sql`
**Date:** 2026-09-02
**Architecture:** Data Architecture 2.1
**Parent:** Ready PR #16 `refactor/phase-6a-rider-assessments` HEAD `08e51cf6807b7828b4092c1d870969e1c16be691`
**Branch:** `refactor/phase-8a-equine-requirements`

This PR is stacked on Phase 6A. It must not merge before PR #16 (and #15).
This agent will not retarget or merge. Migration `017` is not deployed.

## Design selected

- Table: `equine_requirements` attached to `equines`.
- Types exactly: `MIN_AGE | MAX_AGE | MIN_QUALIFICATION | CENTER_ASSESSMENT_REQUIRED | ZERO_SESSION_REQUIRED | OWNER_APPROVAL_REQUIRED | SUPERVISION_REQUIRED | MIN_EXPERIENCE`.
- Sources exactly: `OWNER | CENTER | MARKET`. Source is provenance, not mutation authority.
- Architecture 2.1 already names `numeric_value`, `boolean_value`,
  `text_value`, `discipline_id` and `qualification_level_id`. This phase
  maps each type onto the matching columns. That is not a new
  polymorphic model.
- `MIN_AGE` / `MAX_AGE` / `MIN_EXPERIENCE` → non-negative `numeric_value`.
  Not stored rider age. Not Spanish adulthood.
- `MIN_QUALIFICATION` → `qualification_level_id` required.
- `*_REQUIRED` boolean types → `boolean_value` required.
- `discipline_id` optional for all types.
- `source_id` is an opaque uuid without a polymorphic FK.
- Status reuses catalog `ACTIVE | INACTIVE`.
- No client CRUD. Ownership, membership and `MANAGE_REQUIREMENTS` do not
  open a client write path in this phase.
- No eligibility evaluation. No Zero Session / authorization / booking.

## Architecture conflicts

None for typed values. Frozen columns were sufficient.

## Frontend

None. No fabricated requirements in Expo.

## Tests

`npm run test:equine-requirements` is appended to `npm run test:sql`.

## Next phase

`018_center_services.sql` on `refactor/phase-8b-center-services`, stacked
on this branch after CI + Bugbot. Do not merge. Do not deploy. Do not
start 019.
