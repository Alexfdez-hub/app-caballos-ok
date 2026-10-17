# MIGRATION STATUS

**Live note (2026-10-17):** `042_bookable_offers.sql` is in the repository
and is not deployed. The last recorded remote schema remains the
previously authorized `041` deploy. `042` is not applied to that project
by this train. Payments, KYC, and insurance review stay open. The local
vertical procedure is `docs/VERTICAL_MVP_SMOKE.md`.

**Live note (2026-10-15, Stage 0.1):** the procedure base is `origin/main`
`5ed38a93f712069e8be45bd8573d6a5762b57b6a`. Migrations `036` through
`041` are on that `main`. The last authorized remote record, not
re-queried in this stage, is project `efkauegdlmfkonzwyyiv` with
migration `041` deployed. This stage does not assert a current grant,
cohort, or audit count. The live procedure is
`docs/VERIFICATION_READONLY_PILOT_RUNBOOK_041.md`. It does not execute
the pilot, decide a case, open a document, or open publication,
services, bookings, or payments. The version `040` counts in older
notes are historical. Existing null countries are not assigned `ES`.
The Phase 14B record below is historical.

PHASE: 14B — Consolidated P0 security gate
STATUS: MERGED AND DEPLOYED — migrations 027–029 deployed; no migration 030 on main
DATE: 2026-09-04

`main` HEAD is
`de90f90fa5d71f43b0fd4aba660bd7f522479ad3` (merge of PR #34).
PRs #30, #31, #33 and #34 were reviewed, corrected where required,
retargeted and merged sequentially.

Remote Supabase project `efkauegdlmfkonzwyyiv` is aligned through exact
migration version `029`:

- `027_storage_policies.sql`
- `028_zero_session_approval.sql`
- `029_critical_audit.sql`

No migration `030` exists. Phase 14B is a tests-and-documentation
security gate only. No Vault integration was introduced.

## Critical corrections included before merge

- Storage identity helpers reject suspended accounts and persons.
- Zero Session approval evaluates minor status and guardian consent at
  the scheduled activity time, not at approval time.
- Security regressions require a hard authorization denial when an
  assessor tries to inspect a foreign minor's consent state.
- Current policy acceptance is asserted independently from unrelated
  eligibility failures.

## Verification

- Final App and PostgreSQL Quality Gates passed on every merged HEAD.
- Manual review covered RLS, table privileges, SECURITY DEFINER
  functions, fixed search paths, Storage policies, guardian/minor
  consent, policy versions, eligibility, immutable audit records and
  concurrency protections.
- A remote transactional dry-run of 027–029 completed with rollback
  before deployment.
- Deployment was applied sequentially and migration history was
  normalized to exact versions 027, 028 and 029.
- Post-deploy checks confirmed five private buckets, six Storage
  policies, RLS on `storage.objects`, six audit triggers, and restricted
  execution of `approve_zero_session`.
- Supabase advisors were reviewed. Intentional deny-by-default RLS and
  reviewed RPC warnings remain documented. Leaked-password protection
  remains a pre-existing Auth configuration warning.

See `docs/REMOTE_DEPLOYMENT_027_029.md` for the deployment record.

## Next phase

1. Issue #47 and migration `035_identity_market_capture` are merged,
   deployed as exact version `035`, and covered by the approved Android
   smoke. See `docs/PHASE_IDENTITY_MARKET_CAPTURE_REPORT.md`.
2. Migrations `036` through `041` are on `main`. The live read-only
   pilot procedure is `docs/VERIFICATION_READONLY_PILOT_RUNBOOK_041.md`.
   It describes a later preflight and a later cohort, bootstrap,
   suspension, and close. It does not authorize executing them, and it
   does not start migration `042`. The Stage 4B.4 runbook is not the
   procedure. No KYC vendor and no calendar change.
3. Open `DECISION_REQUIRED` items still block publication, services, real
   bookings, payments, and provider integration.
4. Keep private declared-equine and private-photo functionality working.
   Public listing, service enablement, real booking, and payment stay
   blocked until a later authorized train adds backend gates.