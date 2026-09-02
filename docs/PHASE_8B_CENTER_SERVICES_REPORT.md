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

Architecture 2.1 names `status` on both tables and
`authorization_policy` on `service_equines` without enumerating tokens.
This foundation does **not** invent `DRAFT` / `ARCHIVED` / `REVOKED` or
policy enums. Default `status = 'ACTIVE'` is a stored string only.

Architecture 2.1 also does not name who may create or mutate
`center_services`. This phase does **not** invent ADMIN/MANAGER create
authority. Client writes stay denied. Server-side inserts used by tests
and controlled provisioning are unconstrained by a new trigger.

Do not treat these omissions as approval to add tokens or a create RPC
later without Product Owner decision.

## Frontend

None. No fabricated services catalog in Expo. No Zero Session records.

## Tests

`npm run test:center-services` is appended to `npm run test:sql`.

## Next phase

`019` is **not** started. After this PR is Ready and Bugbot-clean, post
the multi-phase handoff on the latest PR. Do not merge. Do not deploy.
