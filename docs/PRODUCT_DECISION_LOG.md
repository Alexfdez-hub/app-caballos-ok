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

## 2026-10-05 — Verification status screen, Stage 4A

Authorizes only the Verificación screen: read `list_my_verification_status()`
and `list_my_identity_cases()`, and submit `submit_my_identity_case('ES')`.
A case state is not identity verification. The screen stores no documents
and does not call a KYC vendor. Ownership and management claims, evidence,
reviewer UI, and Stage 4B stay unauthorized. `GATE-PREDICATE` and the other
open items stay open.

## 2026-10-08 — Verification reviewer UI, Stage 4B inspection

Does not authorize a reviewer screen, grant management, or migration `039`.
The Stage 0 inventory in `docs/VERIFICATION_REVIEWER_UI_STAGE4B.md` finds
that an active `verification_review_grants` row is the only review
authority, that no grant is seeded, and that no RPC lists cases a caller
may review. `REVIEWER-GRANT-AUTHORITY` stays open. `GATE-PREDICATE` and
the other open items stay open.

## 2026-10-08 — Stage 4B Codex review, documentation only

Does not authorize a reviewer screen, a grant row, an Edge Function, or
migration `039`. The inventory now separates a pseudonymous queue, an
authorized opening, private evidence access, and the decision. The
recommended Spain-pilot direction is a `MARKET` grant for `ES`, held by a
PERSON already designated, and changed only by a future server-side
administrative operation. Center affiliation is not that authority. The
bootstrap of that operator, and the operator's concrete identity, remain
a separate security review. The KYC provider, the legal evidence catalog,
retention, and conflict resolution stay open.

## 2026-10-08 — Reviewer bootstrap design, Stage 4B.1

Does not authorize a grant row, a script, an Edge Function, or migration
`039`. See `docs/VERIFICATION_REVIEWER_BOOTSTRAP_STAGE4B1.md`. The
technical pilot, when a later train may create a grant, uses fictional
data and one dedicated reviewer account, with scope `MARKET` / `ES` only.
The exceptional bootstrap is a database-owner action outside Expo. It is
blocked until a reviewed change can audit that action without a
client-supplied actor, because `audit_events` requires `auth.uid()`.
Ordinary grant administration stays a later authenticated server
operation, separate from the reviewer. Real users still wait for the KYC
provider, an operating procedure, and legal and privacy review.

## 2026-10-08 — Verification grant lifecycle, Stage 4B.2

Authorizes only migration `039` on this branch: the grant projection
may be `ACTIVE`, `SUSPENDED`, or `ENDED`, and an append-only event
records a technical PostgreSQL principal without inventing a PERSON.
The bootstrap function is not an Expo or `service_role` API, and it has
not been executed. No real grant exists. Remote version stays `038`.
Queue, evidence, reviewer UI, ordinary authenticated administration,
and real users stay unauthorized. See
`docs/VERIFICATION_GRANT_LIFECYCLE_STAGE4B2.md`.

## 2026-10-09 — Grant lifecycle review, still migration 039

The Codex review of Draft PR #58 stays inside unreleased migration `039`.
The only technical operator is `current_user` `postgres`. `supabase_admin`
is not an operator; its remaining superuser bypass is a provider trust
boundary. A suspended `MARKET` / `ES` grant can be closed, and that
`CLOSED` event records `SUSPENDED` as the previous status. `SUSPENDED`
does not return to `ACTIVE`, and `ENDED` does not change. A future
`PRODUCT` actor must reference one `user_accounts` row through
`(id, person_id)`. No remote bootstrap, real grant, or migration `040`.

## 2026-10-09 — Migration 039 deployed, still no grant

Remote project `efkauegdlmfkonzwyyiv` is normalized at exact version
`039`. The grant table and the grant-event table are empty. The
technical bootstrap has not been executed, and no reviewer account
exists. That deployment does not authorize a queue, a decision, or
migration `040`.

## 2026-10-09 — Read-only reviewer queue, Stage 4B.3

Authorizes only unreleased migration `040` and a read-only Spain pilot
screen. An authenticated caller with a current `MARKET` / `ES` grant may
read their capability, a pseudonymous queue, and one re-authorized case.
Opening that case writes `audit_events` without names, paths, or
documents. The screen does not call `review_*` and does not show a
decision. Evidence signing, remote bootstrap, a real grant, and migration
`041` stay unauthorized. See
`docs/VERIFICATION_REVIEWER_READ_UI_STAGE4B3.md`.

## 2026-10-10 — Pilot reviewer smoke runbook, Stage 4B.4

Authorizes a document only: `docs/VERIFICATION_REVIEWER_PILOT_SMOKE_STAGE4B4.md`.
The recorded remote state is exact version `040` on
`efkauegdlmfkonzwyyiv`, with 0 grants, 0 grant events, 0
`verification_review_opened` rows, and no reviewer account. A later
smoke, if separately authorized, uses two fictional accounts, fictional
Spain cases, and referential evidence tokens. It does not use a real
document, a personal address, or a stored password. The bootstrap,
suspension, and closure remain later `postgres` operations. Cleanup
isolates the fixture and does not delete audit rows or grant events.
This entry does not execute that procedure and does not authorize
migration `041`, a decision, or a signed evidence URL.

## 2026-10-11 — Smoke fixtures stay open after the reviewer is closed

Corrects the isolation sentence in the 2026-10-10 Stage 4B.4 entry.
Closing the pilot grant isolates that reviewer. It does not make the
three fictional cases unreachable. They remain `SUBMITTED`, with no
evidence, and `list_my_review_queue()` will show them to any later
active `MARKET` / `ES` reviewer who has no conflict. Until a separately
reviewed retirement accounts for those case ids, another Spain reviewer
grant is forbidden. This correction invents no `DELETE`, `UPDATE`,
rejection, decision, or artificial case close. See
`docs/VERIFICATION_REVIEWER_PILOT_SMOKE_STAGE4B4.md`.

## 2026-10-15 — Read-only pilot runbook aligned with migration 041

Does not execute the pilot. Does not close a pending decision.

### Already approved

The entries above stay as written. They record the slices they name.
They do not become the live procedure. The 2026-10-10 and 2026-10-11
entries describe the Stage 4B.4 handoff: remote version `040`,
`bootstrap_verification_review_grant` with the person only, and cases
remaining visible to a later `MARKET` / `ES` reviewer after that grant
closes. That description is superseded for execution by this entry.
The old entries are not rewritten.

### Behavior that already exists

Migrations `036`–`041` are on `origin/main`
`5ed38a93f712069e8be45bd8573d6a5762b57b6a`. The last authorized remote
record, from `docs/VERIFICATION_NEXT_TRAIN_STAGE0.md` and not re-queried
here, is project `efkauegdlmfkonzwyyiv` with `041` deployed. This entry
does not state a current grant count or cohort count.

`041` drops `bootstrap_verification_review_grant(uuid)`. The current
function is `bootstrap_verification_review_grant(uuid, text)` and inserts
an `ACTIVE` `MARKET` / `ES` grant already linked to a `CLOSED` Spain
cohort. Queue, detail, and accept/reject authorization follow that
cohort. Closing a grant isolates that reviewer. It does not publish the
dossiers to a grant whose closed cohort does not contain them. Expo
already submits identity, ownership, and management claims, and
`ReviewPilotScreen` already reads capabilities, queue, and detail. It
does not render `Aceptar` or `Rechazar` and it does not call `review_*`.

### Operations still not authorized

`docs/VERIFICATION_READONLY_PILOT_RUNBOOK_041.md` describes, and does not
authorize, the later order: read-only preflight, create an `OPEN` `ES`
cohort, add only the identified dossiers, verify the composition, close
it, bootstrap B with the person id and the cohort code, read the queue
and detail in Expo, prove an outside dossier fails closed, suspend,
observe the revocation, close, and confirm that the closed row is not
reactivated. None of those steps is executed by this entry.

### Still open

`DECISION_REQUIRED`: the items named in
`docs/MANUAL_VERIFICATION_MVP0_DESIGN.md`, including `KYC-PROVIDER` and
`RETENTION-AND-EXPIRY`. Also the runbook's own open items: a missing
identity submission, a null effective ownership or assignment id, an
identified set that is not one open Spain dossier of each type, and the
authenticated channel for the outside-cohort read. This entry chooses
none of them.

`ARCHITECTURE_CONFLICT`: the contracts are not aligned. This entry does
not choose a resolution and does not start migration `042`.
`submit_my_equine_management_claim` in `041` can accept an `ACTIVE`
assignment whose `valid_until` is null or future, when called with a row
that meets its conditions. `list_my_equine_management_assignments` marks
`is_currently_effective` only when `valid_until` is null; that is the
read the app uses. `managementClaimPayload` builds the claim only when
that row arrives marked current, so the current UI does not allow
claiming an assignment with a future `valid_until`.
`review_equine_management_claim` refuses `ACCEPTED` when `valid_until`
is not null, and `verification_management_is_verified` also requires it
null. The runbook still stops before section B when
`management_claim_valid_until_is_null` is false.

`LEGAL_AND_INSURANCE_REVIEW_REQUIRED` remains open before real paid
bookings.

`ACCEPTED` is not evidence-gated by migrations `036`–`041`. A future
`042`, if separately authorized, is the limit described in the Stage 0
inventory: fail closed until minimum evidence exists and, for identity,
until the future authorized KYC result exists. `REJECTED` is not
conditioned on sufficient evidence. Rejection UI, a stable `reason_code`
catalog, and a rejection procedure stay unauthorized.
