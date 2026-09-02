# Phase 8B — Center services foundation

**Project:** app-caballos-ok
**Phase:** 8B — Center services
**Migration:** `supabase/migrations/018_center_services.sql`
**Date:** 2026-09-02
**Architecture:** Data Architecture 2.1
**Parent:** Ready PR #17 `refactor/phase-8a-equine-requirements` HEAD `7165b7c1eaae1eadaee4a8358195abaab5096980`
**Branch:** `refactor/phase-8b-center-services`

This PR is stacked on Phase 8A. It must not merge before PR #17 (and
#16, #15). This agent will not retarget or merge. Migration `018` is
not deployed.

## Design selected

- Tables: `center_services`, `service_equines`.
- Service types exactly: `EQUINE_SESSION | RIDER_ASSESSMENT | ZERO_SESSION`.
  `ZERO_SESSION` here is a service kind, not a `zero_sessions` row.
- A service belongs to one Center. Unique `(service_id, equine_id)`.
- Positive duration CHECKs: `default_duration_minutes` and
  `duration_limit_minutes` are null or `> 0`. `now()` is not in a CHECK.
- `enabled` default true. `supervision_required` default false.
  `requirements` must be a JSON object, default `{}`.
- `center_services.status` and `service_equines.status` are exactly
  `ACTIVE | INACTIVE`, default `ACTIVE`. Product Owner approved this
  catalog pair on 2026-09-02 for the 015–018 train (same tokens as
  `qualification_systems`, `qualification_levels` and
  `equine_requirements`). Not `DRAFT`, `ARCHIVED` or `REVOKED`.
- `authorization_policy` remains optional trimmed non-empty free text
  when present. No enum and no authorization engine in 018. Vocabulary
  belongs to the later authorization / Zero Session / booking train
  (Product Owner, 2026-09-02).
- `service_equines.service_id` is `ON DELETE CASCADE`.
- Linking authority is explicit: trigger
  `enforce_service_equine_manage_requirements()` requires
  `has_active_equine_center_permission(equine, service.center,
  'MANAGE_REQUIREMENTS')`. Membership, assignment, ownership and
  `ASSESS_RIDERS` are not sufficient. Cross-center permission is rejected.
- UPDATE cannot retarget `service_id` or `equine_id`.
- DELETE of a link is allowed if the parent service is already gone
  (CASCADE). DELETE while the service exists still requires effective
  `MANAGE_REQUIREMENTS`.
- Historical link remains after permission revoke. Further mutation then
  fails authority.
- RLS deny-by-default. No client create/link RPC. Current UI has no
  services catalog.

## Architecture conflicts

**Closed (status):** Product Owner decision 2026-09-02. Both 018 status
columns use `ACTIVE | INACTIVE`. The earlier unnamed-token conflict
does not remain.

**Open:** Architecture 2.1 does not name who may create or mutate
`center_services`. This phase does **not** invent ADMIN/MANAGER create
authority. Client writes stay denied. Server-side inserts used by tests
and controlled provisioning are unconstrained by a new trigger.

`authorization_policy` is intentionally not an enum. That is a deferred
vocabulary, not an unresolved status-lifecycle conflict.

## Frontend

None. No fabricated services catalog in Expo. No Zero Session records.

## Tests

`npm run test:center-services` is appended to `npm run test:sql`.
Coverage includes invalid status rejection and both approved values on
`center_services` and `service_equines`.

## Next phase

`019` is **not** started. Do not merge. Do not deploy.
