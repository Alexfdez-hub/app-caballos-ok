# MIGRATION STATUS

**Live note (2026-10-08, Stage 4B.1 design):** repository `main` is
`1b42764446ea7cdae223172ceed6a3aa7151e233`. Migrations `036`, `037`, and
`038` are on `main`. Remote project `efkauegdlmfkonzwyyiv` is normalized at
exact version `038`. Stage 4B is merged. This branch publishes the reviewer
bootstrap design only. It does not add migration `039` and does not open
publication, services, bookings, or payments.
Existing null countries are not assigned `ES`. The Phase 14B record below
is historical.

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
2. Migrations `036`, `037`, and `038` are on `main`. Remote is at exact
   version `038`. Stage 4B is merged. Stage 4B.1 publishes
   `docs/VERIFICATION_REVIEWER_BOOTSTRAP_STAGE4B1.md` and does not create
   a grant. No migration `039`, grant-management RPC, KYC vendor, or
   calendar change.
3. Open `DECISION_REQUIRED` items still block publication, services, real
   bookings, payments, and provider integration.
4. Keep private declared-equine and private-photo functionality working.
   Public listing, service enablement, real booking, and payment stay
   blocked until a later authorized train adds backend gates.