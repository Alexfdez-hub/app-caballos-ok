# Phase 14A — Storage security foundation

**Project:** app-caballos-ok
**Phase:** 14A — Storage security
**Migration:** `supabase/migrations/027_storage_policies.sql`
**Date:** 2026-09-03
**Architecture:** Data Architecture 2.1
**Baseline:** live `main` `9d58d3605a931fd930520238276215cf17a51a38`
**Branch:** `cursor/phase-14a-storage-security-b935`

This PR targets live `main` after PRs #25–#28 (migrations `023`–`026`)
merged. Do not merge. Do not deploy `027`. Do not start 028 until this
Quality Gate is green.

## Inventory

- Local `supabase/config.toml`: Storage enabled, no named buckets.
- Migrations `001`–`026`: path metadata only; no buckets or
  `storage.objects` policies.
- Remote dump (`docs/REMOTE_DATABASE_INVENTORY.md`): no Storage objects
  or policies. Retired client used `horse-images`. 027 does not delete,
  rename or rewrite that bucket or any existing object.
- Product Owner states remote `efkauegdlmfkonzwyyiv` is aligned through
  exact version `026`. This agent does not inspect or mutate remote.

## Design selected

- Five Architecture 2.1 buckets created private (`public = false`).
  Existing target-bucket rows are only forced private; objects are not
  rewritten. MIME/size limits are not invented.
- Current Supabase rule: mutation through the Storage API; RLS on
  `storage.objects`. No UPDATE/DELETE policies (upsert/move/delete are
  not frozen).
- Frozen-private buckets:
  - `session-evidence/{session_id}/{object}` — participant PERSON,
    booked_by ACCOUNT, or Center ADMIN/MANAGER + `MANAGE_BOOKINGS`
    (same as `attach_session_evidence`).
  - `qualification-documents/{rider_person_id}/{qualification_id}/{object}`
    — rider PERSON or current VERIFIED guardian.
  - `assessment-documents/{rider_person_id}/{assessment_id}/{object}` —
    write: current ASSESSOR who owns the assessment row; read: that
    assessor, the rider PERSON, or a current VERIFIED guardian.
- Paths use exact UUID segments. Prefix substitution, metadata,
  `user_metadata`, `owner` and `auth.uid()` as a domain id are ignored.
- `avatars` and `equine-media`: private, no client policies. See
  `docs/ARCHITECTURE_CONFLICT_027_STORAGE_VISIBILITY.md`.
- No signed-URL creator, no global listing RPC, no `service_role`
  client path, no SQL grant that bypasses Storage RLS.
- Helpers that clients can execute are boolean allow-checks only.
  Identity comes from `auth.uid()` → `user_accounts`. SECURITY DEFINER
  helpers set `search_path = pg_catalog, public`. PUBLIC/anon EXECUTE
  is revoked.

## Access

`storage.objects` RLS: INSERT/SELECT on the three private document
buckets only, `TO authenticated`, each bound to a domain helper.
Avatars/equine-media have no policies. Anon has no Storage policy.

## Frontend

No Storage client, signed URL helper or upload UI.

## Tests

`npm run test:storage` → `supabase/tests/027_storage_policies_test.sql`.

Covers authorized rider/staff/guardian/assessor paths, unrelated
authenticated user, anon, wrong bucket/path, prefix substitution,
private avatar/equine-media reads, metadata spoofing, overwrite/upsert
and delete denial, and revoked membership/permission.

`011_equines_test.sql` now allows a later private `equine-media` bucket
and still forbids objects and client policies for it.

## Advisors

Local Supabase/Docker is not available in this cloud environment.
Security/performance advisors were not run here. Do not claim advisor
clean. Record after CI or a local stack is available.

## Next

Make Ready only when the complete Quality Gate is green. Then start
028 on this HEAD. Do not merge. Do not deploy. Bugbot is optional;
do not claim Bugbot-clean unless a real review ran.
