# Phase 13B — Audit

**Project:** app-caballos-ok
**Phase:** 13B — Audit
**Migration:** `supabase/migrations/026_audit.sql`
**Date:** 2026-09-03
**Architecture:** Data Architecture 2.1
**Baseline:** accepted 025 HEAD `ccbfdffdc73bc5b58e4ec0e38b8e818a2fd85842`
**Branch:** `refactor/phase-13b-audit`

This PR stacks on 025 (PR #27). Do not merge. Do not deploy `026`.
Do not start 027. Stop after the final handoff on this PR.

## Design selected

- Table: `audit_events` with Architecture 2.1 columns: actor account/
  person, event_type, entity_type, entity_id, metadata, occurred_at.
- Append-only. No client policies or SELECT. No public list/write RPC.
- Actor and `occurred_at` are overwritten from `auth.uid()` and
  `clock_timestamp()`. Callers cannot spoof them.
- Metadata is a small JSON object. Secret/JWT/policy/evidence keys and
  JWT-shaped values are rejected. Review comments and incident
  descriptions are not stored.
- `event_type` / `entity_type` have no invented CHECK catalogs.
- Integration is trigger-based so migrations `001`–`025` stay unchanged.
  Only 023–025 critical transitions are audited: session started/
  completed, equine activity recorded, review submitted, incident
  reported. Replay no-ops do not write a second event. Failed RPCs roll
  back the audit row. `confirm_booking` and earlier phases are not
  retrofitted.

## Access

RLS on, no client policies, `REVOKE ALL` from `anon`/`authenticated`.
Internal helpers stay revoked. Clients cannot enumerate global audit.

## Frontend

No audit UI.

## Next

Stop after this PR is Ready and the complete Quality Gate is green.
Post the train handoff on this PR. Do not merge. Do not retarget. Do
not deploy. Do not start 027. Bugbot on PRs #25–#26 was quota
unavailable; do not claim Bugbot-clean unless a real review ran.
