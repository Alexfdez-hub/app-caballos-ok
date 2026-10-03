# MIGRATION STATUS

**Live note (2026-10-03, issue #47 branch):** repository `main` is
`399189d8580c64f1b4dc164a289e7306e15d8c09` and contains migrations
`001`–`032`. This branch adds unreleased `035_identity_market_capture.sql`
for explicit country capture and the Spain pilot baseline. Nothing in
this change is deployed. Existing null countries are not assigned `ES`.
Do not start migration `036`. The Phase 14B record below is historical.

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

1. Issue #47 adds unreleased migration `035_identity_market_capture.sql`:
   explicit country selection, selectable-market validation and the
   Spain pilot baseline. It is not deployed.
2. Approve the remaining manual MVP0 identity and equine-verification
   workflow in `docs/IDENTITY_AND_EQUINE_VERIFICATION_PLAN.md`.
3. Do not allocate migration `036` for KYC, evidence or publication.
4. Keep private declared-equine and private-photo functionality working;
   block public listing, service enablement, real booking and payment
   until backend verification gates are satisfied.