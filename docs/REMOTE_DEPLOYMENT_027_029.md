# Remote deployment record — migrations 027–029

**Project:** app-caballos-ok  
**Supabase project:** `efkauegdlmfkonzwyyiv`  
**Deployment date:** 2026-09-04  
**Merged baseline:** `de90f90fa5d71f43b0fd4aba660bd7f522479ad3`  
**Vault:** not used  
**Migration 030:** does not exist

## Deployed migrations

The following migrations were applied sequentially:

1. `027_storage_policies.sql`
2. `028_zero_session_approval.sql`
3. `029_critical_audit.sql`

The connector initially recorded timestamp-style migration identifiers.
After deployment, history was normalized with guarded updates to the
repository's exact versions `027`, `028` and `029`. The final remote
history is continuous and exact through `029`.

## Preflight and dry-run

Before deployment:

- remote health and PostgreSQL 17 availability were confirmed;
- remote migration history was exact through `026`;
- required dependencies were present, including Storage tables,
  `zero_sessions`, `audit_events` and `resolve_session_caller`;
- the five target Storage buckets did not yet exist;
- migrations 027–029 were concatenated and executed inside a remote
  transaction ending in `ROLLBACK`;
- the transactional dry-run completed successfully.

## Corrections accepted before deployment

Manual Codex review and the Quality Gates identified and resolved these
critical points:

- Storage identity helpers now reject a suspended account or person.
- Zero Session approval determines minority and guardian consent at the
  scheduled activity time rather than at approval time.
- The security regression requires SQLSTATE `42501` when an assessor
  attempts to inspect a foreign minor's consent.
- Current policy acceptance is asserted on its own failed requirement,
  independently from other eligibility failures.

## Post-deployment verification

Verified on the remote project:

- migration history is exact and continuous through `029`;
- five target buckets exist and are private:
  - `avatars`
  - `equine-media`
  - `qualification-documents`
  - `session-evidence`
  - `assessment-documents`
- six intended Storage policies exist;
- no Storage UPDATE or DELETE policies were introduced;
- RLS is enabled on `storage.objects`;
- six critical audit triggers are installed;
- `anon` cannot execute `approve_zero_session`;
- `authenticated` may execute the approval RPC, whose internal
  authorization still fail-closes unauthorized callers;
- `approve_zero_session` is `SECURITY DEFINER` with a fixed
  `search_path`;
- its deployed definition evaluates consent at the scheduled activity
  time;
- Storage identity helpers require ACTIVE account and person status.

## Security advisors

Security advisors were inspected before and after deployment.

- RLS-without-policy notices on intentionally inaccessible tables are
  deny-by-default and expected.
- Warnings for reviewed authenticated `SECURITY DEFINER` RPC endpoints
  describe the deliberate public RPC surface; authorization remains
  enforced inside the functions and direct table privileges remain
  revoked.
- Leaked-password protection being disabled is a pre-existing Supabase
  Auth configuration warning. It was not changed by this database train.

## Quality evidence

Final App and PostgreSQL Quality Gates passed for all four integrated PRs:

- PR #30 — migration 027
- PR #31 — migration 028
- PR #33 — migration 029
- PR #34 — Phase 14B consolidated P0 security tests; no migration 030

Manual review additionally covered RLS, table privileges, fixed
`SECURITY DEFINER` search paths, guardian/minor consent, policy
versions, eligibility, immutable audit records, snapshots and
concurrency protections.
