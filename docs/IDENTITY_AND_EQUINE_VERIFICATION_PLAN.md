# Identity and Equine Verification Plan

**Status:** approved planning clarification; implementation design pending
**Date:** 2026-10-03
**Scope:** MVP0 trust gates before public marketplace operations
**Out of scope:** selecting a KYC provider, legal certification, payments, migration 035

## 1. Why this exists

The frozen model already separates PERSON from ACCOUNT and ownership from
management. The completed 031 flow correctly creates a private equine with a
declared owner and current PRIMARY_MANAGER. What was missing was an explicit
workflow for proving human identity and proving or corroborating the ownership
or management relationship.

No completed migration must be rebuilt. This plan adds trust state and product
gates before public discovery, real bookings or payments.

## 2. Trust levels

| Level | Meaning | What it does not prove |
| --- | --- | --- |
| ACCOUNT_AUTHENTICATED | The caller controls an authenticated account | Civil identity |
| MARKET_CONFIRMED | Country/market was explicitly selected and validated | Identity or residency evidence |
| IDENTITY_VERIFIED | Civil identity passed an auditable verification | Equine ownership |
| EQUINE_OWNERSHIP_DECLARED | A person or center asserts ownership | Legal ownership |
| EQUINE_OWNERSHIP_VERIFIED | The ownership claim was reviewed and accepted | Management authority outside its scope |
| MANAGEMENT_AUTHORITY_VERIFIED | Authority to manage the equine was reviewed | Legal ownership |
| FISCAL_IDENTITY_VERIFIED | Required fiscal data passed the applicable gate | General equestrian eligibility |

## 3. MVP0 operating rule

- Adult self-create remains available for a private equine.
- Private profile completion and private photos remain available to the current
  authorized manager.
- Public visibility, service enablement, real bookings and money movement are
  blocked until the backend confirms the required trust levels.
- UI labels must say declared/pending/verified truthfully.
- The pilot starts with human review; automation follows evidence from use.

## 4. Evidence and review

Possible evidence sources include equine passport or UELN, microchip where
applicable, ownership or delegation documents, center corroboration and manual
review. No single source is assumed universally sufficient.

Evidence is private, least-privilege and retention-limited. Store only the
minimum metadata needed in PostgreSQL; use private Storage or an external
provider reference for artifacts. Every decision records method, reviewer,
timestamps, outcome and reason. Support rejection, expiry, revocation,
resubmission and conflicting claims.

Center corroboration records what a center can attest. It does not silently
become legal proof of ownership.

## 5. Candidate model — not yet a migration

- `identity_verifications`
- `equine_ownership_claims` or `equine_ownership_verifications`
- `equine_verification_evidence`
- optional review events or reuse of immutable `audit_events`

The design must preserve the existing `equine_ownerships` and
`equine_management_assignments` as the effective relationship tables.
Verification records trust in those relationships; they do not replace them.

## 6. Security requirements

- RLS and table privileges remain deny-by-default.
- Evidence is never public and never exposed through broad table reads.
- Client-supplied reviewer, owner or actor identifiers are not trusted.
- Sensitive transitions use narrowly granted server functions or Edge
  Functions; `service_role` never enters Expo.
- SECURITY DEFINER functions must use fixed `search_path`, explicit caller
  checks, restricted EXECUTE grants and audit events.
- User-editable JWT metadata is not authorization.
- Revocation and expiry must affect publication and future operations
  immediately at the backend gate.

## 7. Delivery sequence

1. Issue #47: explicit country/market capture and existing-account remediation.
2. Docs/design PR: states, reviewer roles, evidence categories, retention and
   exact publication gates.
3. Manual identity-verification slice with tests.
4. Manual equine ownership/management verification slice with tests.
5. Integrate gates into publication and service enablement.
6. Only then expose real discovery/booking flows.
7. Before payments: choose provider, complete privacy/legal review and add
   fiscal/KYC requirements.

## 8. Acceptance tests for the future train

- Authenticated but unverified account cannot cross a verification gate.
- Declared ownership cannot be presented as verified.
- A verified manager may act within granted scope without becoming owner.
- Foreign users cannot bypass an inactive or unsupported market.
- A reviewer cannot approve their own claim.
- Evidence cannot be read by unrelated authenticated users.
- Revoked/expired verification removes future publication/operation access.
- Conflicting active claims require review and do not auto-overwrite ownership.
- Existing private equines and photos continue working.

## 9. Stop conditions

Do not create migration 035, select a provider, enable public supply, process
payments or encode market-specific legal evidence rules until the corresponding
design and legal/product decisions are approved.
