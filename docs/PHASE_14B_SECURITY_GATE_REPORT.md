# Phase 14B — Consolidated P0 security gate

**Project:** app-caballos-ok
**Phase:** 14B — P0 security / RLS regression
**Migration:** none. `030_security_hardening.sql` was not created.
**Date:** 2026-09-04
**Architecture:** Data Architecture 2.1
**Base:** accepted Phase 13C / migration 029 HEAD
`43b6ec63f620d97ea90b122474e0f2347142ee2f` from PR #33
**Branch:** `cursor/phase-030-security-gate-d219`

Stacked Draft PR. Do not merge. Do not deploy. Do not start 031.

## Scope

Cross-cutting security regression covering migrations `001`–`029`:

- catalog: every `public` base table has RLS enabled; anon/authenticated/PUBLIC
  have no table DML; every non-extension `SECURITY DEFINER` function in
  `public` has `search_path = pg_catalog, public` and is not executable by
  PUBLIC or anon; audit writers stay revoked from clients
- occupancy/session/review uniqueness that fail-closes concurrent races
- private Storage buckets; avatars/equine-media deny-by-default; no
  signed-URL or `service_role` helper
- cross-person/cross-account table and RPC denials
- assessor self-assessment rejected
- guardian/minor consent: foreign grant, minor self-grant, missing and
  revoked consent, assessor cannot substitute
- expired TERMS v1 acceptance does not satisfy current v2
- forced CONFIRMED insert/update rejected
- unconfirmed booking cannot start a session
- Zero Session approval denied to anon and unrelated callers
- audit insert/select/update/delete and `record_audit_event` denied to clients;
  append-only rewrite/delete denied even as postgres
- overlapping ACTIVE calendar blocks rejected by the 020 gist exclusion

Per-phase concurrency suites (007, 022, 023, 024, 025, 026, 028, 029)
remain in `npm run test:sql`. This gate does not re-orchestrate those
two-session races.

## Migration 030

**Not created.** Issue #32 allows `030_security_hardening.sql` only when a
failing regression reproduces a concrete schema/security defect. No such
defect was reproduced in this revision. Inherited migrations `001`–`029`
are unchanged.

FORCE RLS is intentionally not required: table-owner `SECURITY DEFINER`
routines must write. Client roles are not owners; ENABLE RLS plus revoked
table grants is the client boundary.

## Advisors

This cloud environment has no Docker and no Supabase advisor connector.
Security/performance advisors were not inspected. Do not claim advisor
clean. Do not deploy or mutate remote project `efkauegdlmfkonzwyyiv`.

## Verification

`npm run test:security` → `supabase/tests/030_security_regression_test.sql`
via `scripts/run-security-sql-tests.cjs`, appended to `npm run test:sql`.

Complete Quality Gate (App + PostgreSQL) is required before Ready.

## Excluded

- No merge, retarget, remote deploy, Vault, or `service_role` client path
- No phase 031 or UI work
- No empty/speculative migration
