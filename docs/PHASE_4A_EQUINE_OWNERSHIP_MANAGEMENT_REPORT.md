# Phase 4A — Equine ownership and management foundation

**Project:** app-caballos-ok
**Phase:** 4A — Equine ownership and management
**Migration:** `supabase/migrations/012_equine_ownership_management.sql`
**Date:** 2026-09-02
**Architecture:** Data Architecture 2.1
**Parent:** Draft/Ready PR #11 `refactor/phase-3f-equines-foundation`
**Branch:** `refactor/phase-4a-equine-ownership-management`

This PR is stacked on Phase 3F. It must not merge before PR #11. Product
Owner will retarget after the parent merges. This agent will not retarget
or merge.

## Design selected

- OWNERSHIP ≠ MANAGEMENT ≠ CENTER ASSIGNMENT ≠ CENTER PERMISSION.
- PERSON | CENTER XOR owner/manager FKs. No generic party in MVP0.
- No `owner_id` / `manager_id` / `center_id` on `equines`.
- An owner may also be a manager.
- Center membership and rider profile do not grant equine authority.
- At most one active `PRIMARY_MANAGER` per equine.
- Ownership shares are `0 < percentage <= 100`. Architecture 2.1 names
  `0..100` as a column constraint, not an aggregate 100% rule. This
  foundation does not enforce that shares sum to 100 (not concurrency-safe
  as a table CHECK without a constraint trigger).
- Provisioning stays outside Expo. No mutation RPC. No self-assignment.

## Provisional lifecycle

Architecture 2.1 names `status` without values. This migration uses
`ACTIVE | ENDED` as a **provisional convention awaiting Product Owner
acceptance**, copied from the frozen 010 membership pattern.

| Value | Ownership | Management |
|---|---|---|
| `ACTIVE` | In force. `ended_at` null. | In force. `valid_until` null. |
| `ENDED` | Historical. `ended_at` required. | Historical. `valid_until` required. |

Not included: `INVITED`, `PENDING`, `SUSPENDED`, `VERIFIED`. No invitation
or verification workflow.

## Migration contents

`012_equine_ownership_management.sql` creates:

### `equine_ownerships`

PERSON/CENTER XOR, percentage, lifecycle, unique active person/center per
equine. Index on `equine_id`.

### `equine_management_assignments`

PERSON/CENTER XOR, roles `PRIMARY_MANAGER | CO_MANAGER | AUTHORIZED_MANAGER`,
`granted_by_person_id`, unique active PRIMARY_MANAGER, unique active
person/center+role per equine.

### Access

RLS on, no client policies, `REVOKE ALL` from `anon`/`authenticated`.

- `has_active_equine_management_role(...)` — server-internal DEFINER,
  `search_path` fixed, execute revoked from PUBLIC/anon/authenticated.
- `list_my_equine_ownerships()` / `list_my_equine_management_assignments()`
  — caller PERSON from `auth.uid()` via `user_accounts`. No `person_id`
  argument. Does not expose other owners/managers or CENTER-owned rows.
  Execute granted to `authenticated` only.

## Frontend

Smallest truthful Profile slice:

- Profile → Mis equinos loads the caller ownership RPC.
- Profile → Equinos que gestiono loads the caller management RPC.

No public directory. No create/edit. Empty states are truthful.

## Tests

`npm run test:ownership` is appended to `npm run test:sql`. Inherited
migrations at the parent SHA must remain unchanged; 012 is a new file.
009/010/011 SQL tests allow 012 tables and still forbid 013+.
