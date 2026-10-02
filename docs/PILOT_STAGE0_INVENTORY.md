# Pilot Stage 0 inventory

Verified 2026-10-02 against live `origin/main` before the pilot journey
was added. GitHub live state wins over older phase prose.

## Baseline

| Fact | Value |
| --- | --- |
| Repository | `Alexfdez-hub/app-caballos-ok` |
| `origin/main` | `f9b77de45d39fd8cb6380358f9a192899f6cb1c9` |
| Implementation merge baseline | `de90f90fa5d71f43b0fd4aba660bd7f522479ad3` (PR #34) |
| Open pull requests | none |
| Quality Gate | `.github/workflows/quality-gate.yml` (`pull_request` and `workflow_dispatch`) |
| Remote project | `efkauegdlmfkonzwyyiv`, exact history through `029` |
| Migration `030` | does not exist |
| Issue #32 | closed |

Migrations present on `main`: `001` through `029`
(`001_extensions_and_core.sql` … `029_critical_audit.sql`).

## Documents read

Level 1–3 filenames in `docs/16_AI_DOCUMENT_MAP_AND_USAGE.md`
(`08_DATA_ARCHITECTURE_2_1_FULL.md`, `07_DECISION_LOG.md`,
`03_SECURITY_AND_BUSINESS_RULES.md`, `10_AI_INSTRUCTIONS_FULL.md`,
`13_POLICY_AND_CONSENT_MODEL_RECONSTRUCTED.md`,
`04_IMPLEMENTATION_STATUS.md`, `06_NEXT_PHASES.md`) are not in this
repository.

Live sources used:

- `docs/DATA_ARCHITECTURE.md`
- `docs/MIGRATION_STATUS.md`
- `docs/MIGRATION_PLAN.md` live-status sections
- `docs/REMOTE_DEPLOYMENT_027_029.md`
- `docs/16_AI_DOCUMENT_MAP_AND_USAGE.md`
- phase reports for bookings, sessions, activity, reviews, Zero Session
  approval, audit and storage (`PHASE_11B` through `PHASE_14B`)

Stale statements corrected in place, without rewriting historical phase
reports:

- `docs/MIGRATION_PLAN.md` still described an unmerged Phase 14B branch
  and remote alignment through `026`.
- `docs/16_AI_DOCUMENT_MAP_AND_USAGE.md` still said to stop after
  migration 030 and the issue #32 handoff.

## Architecture

No `ARCHITECTURE_CONFLICT` blocks the pilot fixture. Existing RPCs and
server-side provisioning cover the journey. `approve_zero_session` does
not create a rider-equine authorization; that separation is Architecture
2.1 (`ASSESSMENT != ZERO SESSION != AUTHORIZATION`), so the fixture
inserts the authorization only after an approved Zero Session result.

Equine creation and `equine-media` visibility stay unresolved and are
Stage 3 proposal territory. They do not block Stage 1. `avatars` and
`equine-media` remain private and deny-by-default.

## Caller-scoped RPCs already on `main`

Granted to `authenticated`. Internal helpers stay revoked.

Bookings:

- `check_booking_eligibility(uuid, uuid, uuid, timestamptz, timestamptz, uuid)`
- `create_booking_request(uuid, uuid, uuid, uuid, timestamptz, timestamptz)`
- `confirm_booking(uuid)`

Sessions:

- `issue_session_permit(uuid)`
- `start_session(uuid, boolean, uuid, double precision, double precision, text, timestamptz)`
- `end_session(uuid, boolean, double precision, double precision, text, timestamptz)`
- `attach_session_evidence(uuid, text, text, timestamptz, double precision, double precision)`

Activity, reviews, incidents:

- `record_equine_activity(uuid, uuid, uuid, uuid)`
- `submit_review(uuid, uuid, integer, text, text)`
- `report_incident(uuid, uuid, text, uuid, uuid)`

Zero Session:

- `approve_zero_session(uuid, text, text)`

Equines and centers (caller reads, not mutation):

- `list_my_equine_ownerships()`
- `list_my_equine_management_assignments()`
- `list_my_center_memberships()`

Related caller RPCs the journey also uses:

- `upsert_my_rider_profile(text, smallint, text)`
- `get_my_rider_profile()`
- `grant_guardian_consent(uuid, text, text, text, text, timestamptz)`
- `revoke_guardian_consent(uuid)`

Not present, and not invented here:

- no client equine-create RPC
- no equine-media upload/read RPC
- no caller-scoped list of bookings, sessions or activities
- no policy-acceptance RPC
- no client assessment, qualification or authorization RPC

`src/screens/ActivityScreen.tsx` still renders truthful empty states.

## Stage 1 files

- `supabase/tests/pilot_journey_test.sql`
- `scripts/run-pilot-journey.cjs`
- `docs/PILOT_RUNBOOK.md`
- `package.json` scripts `pilot:journey` and `test:pilot`

No migration. Direct SQL is limited to fixture provisioning inside the
rolled-back test transaction. Client steps call the RPCs above.

## Stage 2 and Stage 3 (not this change)

Stage 2, only after this journey is green: a stacked Draft PR for the
Activity screen. It can show data only through a caller-scoped read.
That read RPC does not exist. Add the narrowest migration only if
Architecture 2.1 already fixes who may see which booking, request and
session rows. Otherwise stop that subsection with `ARCHITECTURE_CONFLICT`.

Stage 3, documentation only: who may create an equine, how ownership and
`PRIMARY_MANAGER` are established atomically, and how private
`equine-media` would be uploaded, read, replaced and audited. Do not
implement that choice and do not open the buckets.
