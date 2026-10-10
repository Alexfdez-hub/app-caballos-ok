# MIGRATION STATUS

**Live note (2026-10-10, Stage 4B.4):** repository `main` is
`0df9baddc9eb8bf72938a584f5f2bfeab723aca4`. Migrations `036` through
`040` are on `main`. The recorded remote state for project
`efkauegdlmfkonzwyyiv` is exact version `040`, with 0 grants, 0 grant
events, and 0 `verification_review_opened` rows. The bootstrap has not
been executed and no reviewer account exists. This branch adds the
pilot smoke runbook only. It does not decide a case, open a document,
or open publication, services, bookings, or payments.
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
2. Migrations `036` through `040` are on `main`. The recorded remote
   history is exact version `040`, with 0 grants, 0 grant events, and
   no bootstrap. The next document is the fictional Android smoke
   runbook, `docs/VERIFICATION_REVIEWER_PILOT_SMOKE_STAGE4B4.md`. That
   runbook does not itself authorize the bootstrap, a grant, or
   migration `041`. No KYC vendor and no calendar change.
3. Open `DECISION_REQUIRED` items still block publication, services, real
   bookings, payments, and provider integration.
4. Keep private declared-equine and private-photo functionality working.
   Public listing, service enablement, real booking, and payment stay
   blocked until a later authorized train adds backend gates.