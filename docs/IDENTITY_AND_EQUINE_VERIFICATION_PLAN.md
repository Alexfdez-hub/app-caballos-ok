# Identity and Equine Verification Plan

**Status:** planning clarification approved. Manual flow proposed in
`docs/MANUAL_VERIFICATION_MVP0_DESIGN.md`. Implementation is not authorized.
**Date:** 2026-10-03
**Scope:** MVP0 trust gates before public marketplace operations
**Out of scope:** selecting the KYC vendor, final legal/insurance certification, payments, migration 036

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
- Civil identity uses an external KYC provider with DNI/NIE or passport, liveness and 1:1 facial comparison. Vendor, lawful basis, DPIA, retention, deletion and exception handling remain pending.
- Equine ownership and management start with auditable evidence review; automation follows evidence from use.

## 4. Evidence and review

For Spain, equine identity uses passport/DIE, UELN, microchip and issuing body. Ownership adds one principal ownership artifact; management adds one current authorization or contract. The admissible document list remains a legal review. Center corroboration may attest custody, presence or a physical identity check. It does not prove or transfer ownership. France, Germany, Italy, Belgium, the Netherlands and Austria may later use country-aware review of equivalent evidence. Possession of a passport alone is not ownership.

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

1. Issue #47: explicit country/market capture and existing-account
   remediation. Done in merged PR #49. Migration `035` is deployed as exact
   version `035`. Android smoke passed.
2. Docs/design PR: states, reviewer roles, evidence categories, retention and
   publication gates. Proposed in `docs/MANUAL_VERIFICATION_MVP0_DESIGN.md`.
   Open `DECISION_REQUIRED` items remain. This step does not implement the
   flow and does not allocate migration `036`.
3. External identity-provider adapter and auditable exception path, after vendor/privacy approval.
4. Manual equine ownership/management verification slice with tests.
5. Integrate gates into publication and service enablement.
6. Only then expose real discovery/booking flows.
7. Before real paid bookings: complete legal and insurance review for activity coverage and terms.
8. Before payments: complete fiscal/KYC requirements.

Migration `035_identity_market_capture.sql` is allocated only to issue #47.
It does not add KYC, evidence storage or publication gates.

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

Do not create migration `036`, select a provider, enable public supply, process
payments or encode further market-specific legal evidence rules until the
corresponding design and legal/product decisions are approved.
