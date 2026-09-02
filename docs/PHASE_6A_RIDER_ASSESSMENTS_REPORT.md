# Phase 6A — Rider assessments foundation

**Project:** app-caballos-ok
**Phase:** 6A — Rider assessments
**Migration:** `supabase/migrations/016_rider_assessments.sql`
**Date:** 2026-09-02
**Architecture:** Data Architecture 2.1
**Parent:** Ready PR #15 `refactor/phase-5b-qualifications` HEAD `aa67729e22ceb9f8cd6594177448f7852cb24be7`
**Branch:** `refactor/phase-6a-rider-assessments`

This PR is stacked on Phase 5B. It must not merge before PR #15. This
agent will not retarget or merge. Migration `016` is local only and is
not deployed.

## Design selected

- Tables: `rider_assessments`, `rider_assessment_disciplines`,
  `rider_assessment_restrictions`.
- Types exactly: `ACCESS_TEST | RIDING_LESSON | COURSE | PRACTICAL_TEST | OTHER`.
- States exactly: `DRAFT | PENDING | VALID | REJECTED | REVOKED | EXPIRED`.
- `rider_person_id` and `assessor_person_id` are PERSON. CHECK
  `rider_person_id <> assessor_person_id`.
- Historical authority belongs to the Center. Creating or validating
  requires an active `ASSESSOR` membership at `center_id`.
  `ADMIN` / `MANAGER` / `INSTRUCTOR` are not inferred.
  Equine `ASSESS_RIDERS` is not sufficient.
- Membership is not universal equine permission.
- Qualification does not replace assessment. Assessment does not create
  Zero Session or rider-equine authorization.
- `valid_until` must not precede `performed_at` when both exist.
  `now()` is not in a table CHECK. Stored `EXPIRED` is not computed.
- Restriction payload is `restriction_code` + JSON object `value_json`
  (Architecture 2.1). No invented restriction catalog.
- `observed_level` is optional free text, not a Galope.
- Discipline and restriction children `ON DELETE CASCADE`.
- No client create/validate RPC. Current UI has no assessments surface.
  Server-authoritative trigger on INSERT/UPDATE of `rider_assessments`.
- Historical row remains after the assessor membership ends. Further
  mutation of that row then fails authority.

## Migration contents

### `rider_assessments`

Indexes on `rider_person_id`, `center_id`, `assessor_person_id`.

### `rider_assessment_disciplines`

Unique `(assessment_id, discipline_id)`. Optional `observed_level`.
`supervision_required` default false.

### `rider_assessment_restrictions`

`restriction_code` trimmed non-empty. `value_json` must be a JSON object.

### Access

RLS on, no client policies, `REVOKE ALL` from `anon`/`authenticated`.

- `enforce_rider_assessment_assessor_authority()` — SECURITY DEFINER
  trigger function, fixed `search_path`, execute revoked from
  PUBLIC/anon/authenticated. Uses `has_active_center_role(..., 'ASSESSOR')`.
  Identity is the recorded `assessor_person_id`, not a caller-supplied actor.
  UPDATE cannot retarget `rider_person_id`, `center_id` or
  `assessor_person_id`.
- `enforce_rider_assessment_child_authority()` — same authority on
  discipline and restriction INSERT/UPDATE/DELETE.

## Frontend

None. Passport already has truthful copy that the profile is not a
center assessment. No fake Expo data.

## Tests

`npm run test:assessments` is appended to `npm run test:sql`.
Inherited migrations including `015` are unchanged versus the 015 branch.

P0 coverage includes: self-assessment rejected; missing/invalid assessor
authority; INSTRUCTOR insufficient; equine `ASSESS_RIDERS` insufficient;
cross-center authority rejected; invalid type/status; invalid temporal
range; invalid FKs; discipline/restriction cascade; unauthorized client
mutation denied; historical assessment preserved after membership end;
absence of Zero Session/authorization/booking tables.

## Next phase

`017_equine_requirements.sql` on `refactor/phase-8a-equine-requirements`,
stacked on this branch after CI + Bugbot. Do not merge. Do not deploy.
Do not start 019.
