# Phase 10A — Equine availability and calendar occupancy

**Project:** app-caballos-ok
**Phase:** 10A — Calendar
**Migration:** `supabase/migrations/020_calendar.sql`
**Date:** 2026-09-02
**Architecture:** Data Architecture 2.1
**Baseline:** `refactor/phase-9a-zero-sessions-authorizations` `0eda4503118e86d9424a4688e48d31a45dead43d`
**Branch:** `refactor/phase-10a-calendar`

This PR targets the 019 branch. Do not merge. Do not deploy `020`.
Product Owner closed the 019–022 conflicts on docs PR #19
(comment `5516860208`). This agent will not merge or deploy.

## Design selected

- Tables: `equine_availability_rules`, `equine_calendar_blocks`.
- Availability is potential. Calendar blocks are canonical occupancy.
- Availability status exactly `ACTIVE | INACTIVE`.
- Calendar block status exactly `ACTIVE | CANCELLED`.
  `cancelled_at` required iff `CANCELLED`.
- `ends_at > starts_at`. `now()` is not in a table CHECK.
- `recurrence_rule` is optional trimmed text. Occurrences are not expanded.
- Calendar `source_type` exactly `BOOKING | ACTIVITY | MANUAL | SYSTEM`.
  `source_id` is an opaque uuid, not a polymorphic FK.
- `block_type` uses Architecture 2.1 occupancy kinds.
- All ACTIVE same-equine overlapping `tstzrange`s are incompatible.
  Enforced with `EXCLUDE USING gist` on
  `(equine_id WITH =, tstzrange(starts_at, ends_at, '[)') WITH &&)`
  where `status = 'ACTIVE'`. Adjacent ranges may touch.
  `btree_gist` is created if missing so uuid equality can participate.
- Creating or mutating rows requires effective `MANAGE_AVAILABILITY`
  for that equine at that Center. Membership, assignment and ownership
  never substitute.
- Cancel-only calendar UPDATE and deactivate-only availability UPDATE
  do not re-check authority, so historical rows remain auditable after
  permission lapse. Identity cannot be retargeted. DELETE is rejected.
- No client CRUD. No `confirm_booking()`, bookings table or eligibility RPC.

## Access

RLS on, no client policies, `REVOKE ALL` from `anon`/`authenticated`.

Server-internal helpers, execute revoked from PUBLIC/anon/authenticated:

- `has_effective_equine_availability`
- `has_active_equine_calendar_overlap`

## Frontend

None. No fabricated availability or occupancy UI.

## Tests

`npm run test:calendar` is appended to `npm run test:sql`.
Inherited migrations `001`–`019` are unchanged versus the 019 branch.
Earlier SQL tests allow 020 tables and still forbid bookings/sessions.

## Next phase

`021_bookings.sql` on `refactor/phase-11a-bookings`, stacked on this
branch after CI + Bugbot. Do not merge. Do not deploy.
