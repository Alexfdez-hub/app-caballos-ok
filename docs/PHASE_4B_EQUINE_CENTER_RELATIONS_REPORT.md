# Phase 4B — Equine–Center relations foundation

**Project:** app-caballos-ok
**Phase:** 4B — Equine–Center relations
**Migration:** `supabase/migrations/013_equine_center_relations.sql`
**Date:** 2026-09-02
**Architecture:** Data Architecture 2.1
**Parent:** Ready PR #12 `refactor/phase-4a-equine-ownership-management`
**Branch:** `refactor/phase-4b-equine-center-relations`

This PR is stacked on Phase 4A. It must not merge before PR #12 (and #11).
Product Owner will retarget after the parents merge. This agent will not
retarget or merge. Migration `013` is local only and is not deployed.

## Design selected

- ASSIGNMENT ≠ OWNERSHIP ≠ MANAGEMENT ≠ PUBLISH ≠ PERMISSION.
- An assignment, membership or ownership row does not create a permission.
- Permission is explicit. Helpers are not executable by PUBLIC/anon/authenticated.
- No `center_id` shortcut on `equines`.
- No Expo assign/grant/revoke UI. No client mutation RPC.
- No caller-scoped list RPC: the relation is equine+center, not the
  caller's person. Joining via membership would be a shortcut.

## Assignment types

`BOARDING | CENTER_OWNED | SCHOOL | TEMPORARY | OTHER`

Duplicate active exact (`equine_id`, `center_id`, `assignment_type`) is
rejected. The same equine may hold different types at the same center
(for example BOARDING and SCHOOL).

## Lifecycles

| Relation | Values | Meaning |
|---|---|---|
| Assignment | `ACTIVE \| ENDED` | ACTIVE requires `ended_at` null. ENDED requires `ended_at >= started_at`. Assignment end does not revoke permissions. |
| Permission | `ACTIVE \| REVOKED` | ACTIVE requires `revoked_at` null. REVOKED requires `revoked_at >= granted_at`. Distinct from assignment ENDED. |

Invitation, suspension and verification tokens are not invented here.

## Permission codes

`MANAGE_AVAILABILITY | MANAGE_BOOKINGS | ASSESS_RIDERS | APPROVE_RIDERS | MANAGE_REQUIREMENTS | VIEW_ACTIVITY`

`granted_by_person_id` is required. Unique active
(`equine_id`, `center_id`, `permission_code`).

## Migration contents

`013_equine_center_relations.sql` creates:

### `equine_center_assignments`

Equine located/used at a Center. Indexes on `equine_id` and `center_id`.
Partial unique index for active exact type.

### `equine_center_permissions`

Explicit Center permission over an equine. Indexes on `equine_id` and
`center_id`. Partial unique index for active code.

### Access

RLS on, no client policies, `REVOKE ALL` from `anon`/`authenticated`.

- `has_active_equine_center_permission(equine_id, center_id, code)` —
  server-internal DEFINER, `search_path` fixed, execute revoked from
  PUBLIC/anon/authenticated.

## Frontend

None in this phase. Public directory, availability, bookings and
assign/grant screens remain deferred. Profile equine lists stay the
Phase 4A caller-scoped RPCs.

## Tests

`npm run test:center-relations` is appended to `npm run test:sql`.
Inherited migrations at the parent SHA must remain unchanged; 013 is a
new file. 009/010/011/012 SQL tests allow 013 tables and still forbid
`disciplines`/`bookings` and later equine domains.

## Next phase

`014_disciplines.sql`. Do not start 015. Do not merge. Do not deploy.
