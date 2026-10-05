# Product Decision Log

**Purpose:** append-only index of Product Owner decisions and material
clarifications. Agents must read this file together with
`docs/DATA_ARCHITECTURE.md`, `docs/IDENTITY_AND_EQUINE_VERIFICATION_PLAN.md`
and the relevant phase design. This log does not authorize code, migration,
merge or deployment.

Do not rewrite old entries when a decision changes. Add a new dated entry that
supersedes the earlier one and links the affected design.

## 2026-10-04 — Identity, equine evidence, insurance and availability

**Status:** approved product direction; executable implementation remains
unauthorized.

### Civil identity

- Primary method: external KYC provider.
- Evidence method: DNI/NIE or passport, liveness and 1:1 facial comparison.
- Application retention: opaque provider reference, outcome, assurance level
  and timestamps; do not copy raw biometrics into normal application storage.
- Pending: vendor, processor terms, lawful basis, DPIA, retention/deletion and
  exception handling.

### Equine identity and relationships

- Equine identity: passport/DIE, UELN, microchip and issuer.
- Spain ownership: identity set plus one principal ownership artifact.
- Management: identity set plus one current authorization or contract.
- Center corroboration may prove custody/presence or a physical identity check;
  it does not independently prove or transfer ownership.
- France, Germany, Italy, Belgium, the Netherlands and Austria use the common
  EU intake plus country-aware evidence review. First-market activities remain
  in the Spanish center/service context.

### Insurance

- Insurance is not required to create or keep a private equine.
- Coverage is evaluated per activity/reservation and does not prove ownership.
- Center-organized activity uses the center's applicable operational/professional
  cover as primary operational evidence.
- Federation licence/accident cover is separate from third-party liability and
  must not be described as equivalent without policy confirmation.
- Exterior rides require explicit off-premises coverage.
- `LEGAL_AND_INSURANCE_REVIEW_REQUIRED` remains open before real paid bookings:
  Spanish counsel and an insurance broker must validate terms, limits, scopes,
  exclusions and blocking rules.

### Owner-center calendar

This clarifies, and does not replace, the frozen Architecture 2.1 calendar.

- The owner or expressly delegated manager defines the maximum release window,
  center, services, welfare/rest limits and exterior-use permission.
- The center may schedule only inside that release and may reduce it according
  to opening hours, facilities, staff and service rules.
- The rider sees only derived bookable slots, never private owner/center
  calendar inputs or reasons.
- Existing welfare, veterinary, owner-use and confirmed-booking blocks prevail.
- Exterior activity may occur outside normal opening hours, but pickup and
  return require authorized handover windows. The entire preparation-to-recovery
  interval blocks the equine.
- Confirmed bookings require an explicit audited cancellation flow; reducing a
  later availability window does not silently erase them.

### Architecture effect

No architecture conflict. PERSON remains distinct from ACCOUNT; ownership from
management; center membership from equine permission; insurance from ownership;
and availability input from derived rider-visible bookable slots. No migration
number is allocated by this decision.

## 2026-10-04 — Verification foundation slice

Supersedes only the implementation hold in the entry above, and only for the
Stage 0 inventory plus migration `036` schema. See
`docs/VERIFICATION_FOUNDATION_STAGE0.md`.

Pending vendor, processor terms, lawful basis, DPIA, retention, deletion,
exception handling, admissible documents, reviewer-grant authority, fiscal
scope, and `LEGAL_AND_INSURANCE_REVIEW_REQUIRED` stay open. Calendar rules
stay as clarified above. Migration `037`, review RPCs, Edge Functions, public
access, and payments are not authorized by this entry.

## 2026-10-04 — Verification review RPC slice

Authorizes only migration `037`: submit, read, and review RPCs for identity
cases and equine claims. ACCOUNT and PERSON resolve from `auth.uid()`.
Review grants are read, not created. Acceptance does not write effective
ownership or management. The pending items in the entry above stay open.

## 2026-10-04 — Verification predicate slice

Authorizes only migration `038`: read-only predicates for current identity,
ownership and management. Center corroboration stays deferred: `036` does
not identify the attesting center or an authorized attester, so an evidence
label is not a trust fact. The predicates do not write effective rows and
are not called by publication, services, bookings or payments.
`GATE-PREDICATE` and the other open items stay open.
