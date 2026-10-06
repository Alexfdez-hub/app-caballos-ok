# Verification foundation — Stage 0 inventory

**Status:** scope matrix only. No schema, RPC, Edge Function, or client change.
**Date:** 2026-10-04
**Main:** `365225c419e44f1ed8a1776f2a7a9838aeb35273` (merge of PR #50)
**Remote:** `efkauegdlmfkonzwyyiv`, exact version `035`. This stage does not deploy.

## Architecture check

No `ARCHITECTURE_CONFLICT`.

The foundation follows Architecture 2.1 and
`docs/MANUAL_VERIFICATION_MVP0_DESIGN.md`:

- PERSON stays distinct from ACCOUNT.
- `equine_ownerships` and `equine_management_assignments` stay the effective
  relationship tables.
- Center membership does not grant equine authority or review authority.
- `equine_availability_rules` and `equine_calendar_blocks` stay the calendar.
  This train does not change owner-release or center-reduction behavior.
- Insurance stays independent of private equine creation.
- `audit_events` stays the only cross-cutting audit log.
- Evidence stays private. Raw KYC images, liveness captures, and biometric
  templates are not application columns.

## Exact scope

| Slice | In this train now | Holds |
| --- | --- | --- |
| Stage 0 | This document | Inventory and the boundary of migration `036` |
| Stage 1, migration `036` | Next Draft PR, after this stage is green | Cases, claims, append-only decisions, referenced evidence, review-grant rows, expiry columns, rejection and revocation outcomes, RLS deny-by-default |
| Stage 2 | This branch, unreleased | Submit, read, and review RPCs in migration `037`. Submitter and reviewer stay separate |
| Stage 3 | This branch, unreleased | Read-only identity, ownership and management predicates in migration `038`. Center corroboration is deferred. Not wired to publication, services or bookings |
| Stage 4 | Stage 4A only, this branch | Verificación screen for Spain identity status and a manual request. Evidence, equine claims, reviewer UI, and Stage 4B are not started |
| Stage 5 | Not started | Broader SQL, concurrency, TypeScript, and runbook coverage |
| Migration `037` | This branch, unreleased | Review RPCs only. No grant management, vendor, or effective-relationship writes |

Stage 1 may include one SQL test that the new tables reject client reads,
reject decision updates, and reject biometric or document-byte columns. That
test does not replace Stage 5.

## Stage 1 table boundary

Use the candidate names in the design:

- `identity_verification_cases`
- `identity_verification_decisions`
- `equine_ownership_claims`
- `equine_management_authority_claims`
- `equine_relationship_decisions`
- `verification_evidence`
- `verification_review_grants`

`market_country_code` is the operating market of the case. It is not
nationality, not residence, and not the KYC document country.
`document_country_code` may differ and is stored only when an evidence row
explicitly has it. Activity jurisdiction is not inferred from either column.

Identity evidence stores an opaque `provider_reference`, outcome metadata,
and timestamps. It does not store a vendor name, document bytes, or
biometrics. No vendor is selected.

Center corroboration is an evidence category. A row of that category does
not update `equine_ownerships` and does not transfer rights.

`expires_at` may be null. This slice sets no retention interval and no
deletion job.

Review grants have no seed and no client insert path.
`REVIEWER-GRANT-AUTHORITY` stays open.

Decision rows are append-only. Emitting `audit_events` stays with the Stage 2
RPC that resolves the caller from `auth.uid()`. Stage 1 does not invent an
actor for a session that has no user.

## Still not decided

- KYC vendor, processor terms, lawful basis, DPIA, retention, deletion, and
  exception handling.
- Which documents are legally sufficient.
- Who may create a review grant.
- Whether the claimant sees the reviewer.
- Whether a guardian may submit for a minor.
- Who resolves conflicting claims.
- The exact publication, service, and booking predicate.
- Fiscal identity and payments.
- Public access.
- `LEGAL_AND_INSURANCE_REVIEW_REQUIRED`.

## Stop

Do not enable public listing, services, real bookings, or payments. Do not
change private equine creation or private photos. Do not deploy.
