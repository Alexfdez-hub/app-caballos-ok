# MIGRATION STATUS

**Live note (2026-10-03 after train 031–034):** repository `main` is
`72287679f87a56941f10fd468903b3fa7b4b4bf6` and contains migrations
`001`–`032`. Logical migrations `031_equine_self_create` and
`032_equine_photo_authorization` are deployed to
`efkauegdlmfkonzwyyiv`; the remote history uses connector-generated
timestamp versions. The four equine-photo Edge Functions are deployed
and active with JWT verification. `equine-media` remains private and
deny-by-default. Android smoke testing passed. Issue #41 is closed and
issue #47 remains open for country/market capture. No migration `035`
exists. The Phase 14B record below is historical.

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

1. Implement issue #47: explicit country/market capture, validation
   against active markets and remediation for existing accounts.
2. Approve the detailed manual MVP0 identity and equine-verification
   workflow in `docs/IDENTITY_AND_EQUINE_VERIFICATION_PLAN.md`.
3. Only then allocate migration `035` if the approved schema requires
   it. Do not infer a KYC provider or legal evidence rule.
4. Keep private declared-equine and private-photo functionality working;
   block public listing, service enablement, real booking and payment
   until backend verification gates are satisfied.