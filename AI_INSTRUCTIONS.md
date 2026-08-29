# AI_INSTRUCTIONS.md

Permanent implementation rules for Cursor / AI coding agents.

## Source of truth

Before structural work read:
1. `docs/DATA_ARCHITECTURE.md`
2. `docs/MIGRATION_PLAN.md`
3. `docs/CURRENT_ARCHITECTURE_REPORT.md`
4. `docs/MIGRATION_STATUS.md` if present

`DATA_ARCHITECTURE.md` is frozen architecture. Do not reinterpret it silently.

## Approved stack

- Expo
- React Native
- TypeScript
- React Navigation
- Supabase Auth
- Supabase PostgreSQL
- Supabase Storage

Do not replace Expo/Supabase/PostgreSQL or add a separate backend without explicit approval.

## Layering

`Screen → Hook/Use Case → Domain Service → Supabase/RPC`.

Do not place critical business rules in screens. Critical state transitions are server-authoritative.

## Frozen distinctions

Never merge these concepts:
- person ≠ user_account
- participant ≠ booked_by account
- ownership ≠ management authority
- ownership ≠ center assignment
- assessment ≠ Zero Session
- policy acceptance ≠ guardian consent
- availability rules ≠ calendar occupancy

## Minors — P0

A minor must never bypass required guardian consent. Enforce server-side. A center, owner, assessor, qualification or Zero Session never substitutes guardian consent. This applies to bookings and any relevant equestrian activity.

## Roles

Do not reintroduce a single mutually-exclusive `users.role`. Roles derive from domain relationships and a person may have several simultaneously.

## Equines

Use `equine`. HORSE/PONY are types. Do not hardcode universal age/horse/pony access rules.

## Eligibility

Evaluate full context:
`PERSON + EQUINE + SERVICE + CENTER + TIME + OWNER POLICY + CENTER POLICY + MARKET POLICY`.

Eligibility may return multiple missing requirements and must be explainable.

## Database

All DB changes through versioned SQL in `supabase/migrations/`.

Prefer: CREATE → MIGRATE → VERIFY → REMOVE LEGACY LATER.

Never make undocumented dashboard-only schema changes.

## PostgreSQL authority

Server/DB controls:
- guardian consent
- eligibility
- booking confirmation
- booking/session critical transitions
- calendar conflicts
- policy checks
- session start/end

The mobile app requests; it does not decide.

## Double booking

Never rely on SELECT-then-INSERT only. Use PostgreSQL constraints/transactions/locking as defined. `equine_calendar_blocks` is canonical occupancy.

## Booking status

Do not allow client CRUD to force `CONFIRMED`, `ACTIVE`, `COMPLETED`, etc. Use approved RPC/server functions.

## Policies

Role-sensitive actions require the correct current policy acceptance. Historical acceptances are audit evidence and are not deleted when a role deactivates.

## RLS

RLS mandatory. Deny by default. Never disable RLS to make a feature work.

Every new business table must include RLS review/policies.

## Secrets

Expo may contain public Supabase URL + anon/publishable client key via env config.

Never place in Expo or commit:
- service_role
- DB password
- private API secrets
- admin credentials

Never echo secret values in reports.

## Storage

Published equine media may be public by design. Qualification docs, assessment docs, session evidence and private guardian/identity evidence are private.

## Offline

Allowed narrowly for previously confirmed session flows using a valid permit and later sync. Do not allow fully-offline booking creation, consent, authorization or approval.

## Migration style

Refactor gradually. Preserve working screens while replacing underlying architecture. New app code TypeScript. Do not redesign UI during infrastructure/database phases unless requested.

## Legacy model

The original `public.users` / `horses` / `bookings` prototype and its custom
Auth trigger are retired by migration 005 under the approved clean-break
decision. Do not reintroduce them or use Auth ids as domain owner/rider ids.
`docs/REMOTE_DATABASE_INVENTORY.md` is historical evidence only.

## Internationalization

Architecture international, Spain first. Do not hardcode Galopes, Spanish legal assumptions, euro-specific logic or translated status strings into DB internals.

## Legal/tax/insurance

Do not invent legal, tax or insurance rules. Market-specific rules must be configurable and legally validated before production.

## Testing

Run relevant checks after each change. Security/business tests must cover minors, permissions, self-assessment prevention, booking state protection, double booking and evidence privacy.

Never claim a test passed unless executed.

## Scope discipline

Before editing, inspect relevant code. Modify only files needed for the current phase. Avoid unrelated cleanup, major version upgrades and giant refactors.

## Dependencies

Do not add packages automatically. Justify necessity and ensure compatibility with current Expo SDK.

## Documentation

After each phase update `docs/MIGRATION_STATUS.md` with files, migrations, checks, issues, manual steps and next phase.

## Stop rule

Every task is phase-scoped. When requested phase is complete: STOP and report. Never continue automatically.

## Architecture conflict protocol

If frozen architecture cannot be implemented as written, report:

```text
ARCHITECTURE_CONFLICT
Current frozen rule:
Implementation problem:
Why it cannot be implemented as written:
Options:
Recommended option:
```

Do not silently alter architecture.

## Deferred MVP0 features

Do not implement unless explicitly authorized:
- Stripe/payments/payouts/deposits
- DAC7/fiscal automation
- advanced international qualification equivalence
- advanced veterinary engine
- AI recommendations
- microservices/event sourcing
- advanced generic RBAC
- full center SaaS

## Product trust chain

`IDENTITY + POLICY ACCEPTANCE + QUALIFICATION + CENTER ASSESSMENT + EQUINE REQUIREMENTS + ZERO SESSION WHEN REQUIRED + AUTHORIZATION + GUARDIAN CONSENT WHEN REQUIRED + AVAILABILITY + CALENDAR → ELIGIBILITY → CONFIRMED BOOKING → VERIFIABLE SESSION → HISTORY → REPUTATION`

Implement this incrementally without removing domain distinctions for convenience.
