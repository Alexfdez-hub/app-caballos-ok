# Manual MVP0 verification design

**Status:** design proposal updated with Product Owner decisions from 2026-10-04. Not approved for implementation.
**Date:** 2026-10-03
**Repository `main`:** `fb599bba25f994bb0bd54ce6e872324523f56e92`
**Remote project:** `efkauegdlmfkonzwyyiv`, exact migration version `035`
**Does not authorize:** migration `036`, SQL, Edge Functions, a KYC vendor, public access, or payments

This document completes the manual-review design named in
`docs/IDENTITY_AND_EQUINE_VERIFICATION_PLAN.md`. It does not amend
Architecture 2.1. Where a product, legal, or privacy choice is still open,
the section is marked `DECISION_REQUIRED`.

## 1. Live facts

- PR #49 is merged. Issue #47 is closed.
- `035_identity_market_capture` is on `main`, deployed, and registered
  remotely as exact version `035`.
- Android smoke passed: authentication, selecting and persisting Spain,
  profile edit, navigation, and creation of a fictional equine.
- Migration `036` does not exist and is not authorized.
- Private declared equines and private equine photos remain the current
  product behavior.

Level 1–3 handoff files named in `docs/16_AI_DOCUMENT_MAP_AND_USAGE.md`
(`08_DATA_ARCHITECTURE_2_1_FULL.md`, `07_DECISION_LOG.md`,
`03_SECURITY_AND_BUSINESS_RULES.md`, `10_AI_INSTRUCTIONS_FULL.md`,
`13_POLICY_AND_CONSENT_MODEL_RECONSTRUCTED.md`,
`04_IMPLEMENTATION_STATUS.md`, `06_NEXT_PHASES.md`) are not in this
repository. This design uses the live in-repo sources: `docs/DATA_ARCHITECTURE.md`,
`AI_INSTRUCTIONS.md`, `docs/IDENTITY_AND_EQUINE_VERIFICATION_PLAN.md`,
`docs/EQUINE_CREATE_AND_MEDIA_PROPOSAL.md`, the migration status documents,
and the phase reports for guardians, ownership, audit, storage, and
identity market capture.

## 2. Trust levels

These levels are derived facts. A client cannot set them, and one level
does not imply the next.

| Level | Derived when | Stays separate from |
| --- | --- | --- |
| `ACCOUNT_AUTHENTICATED` | Supabase Auth has a session for `auth.uid()`, and that id resolves to one `user_accounts` row | Civil identity, market, ownership, management, fiscal status |
| `MARKET_CONFIRMED` | The PERSON `country_code` is an `ACTIVE` market with exactly one age rule effective today | Residency, civil identity, equine rights |
| `IDENTITY_VERIFIED` | That PERSON has one current accepted identity decision that has not expired or been revoked | Equine ownership, management authority, guardian status, fiscal status |
| `EQUINE_OWNERSHIP_DECLARED` | `equine_ownerships` has an effective PERSON or CENTER row for that equine | Legal ownership and management authority |
| `EQUINE_OWNERSHIP_VERIFIED` | A review accepted a claim that corroborates that same effective ownership row, and the decision is still current | Management authority, center membership, a different ownership percentage |
| `MANAGEMENT_AUTHORITY_VERIFIED` | A review accepted a claim that corroborates that same effective management assignment, inside its role and dates | Legal ownership |
| `FISCAL_IDENTITY_VERIFIED` | A future fiscal gate, required only when a payment or fiscal rule applies, has a current accepted decision | General riding eligibility, ownership, management |

`MARKET_CONFIRMED` is already implemented by migration `035`. The other
verification levels are not implemented.

A minor can be a PERSON with no ACCOUNT. Guardian relationship
verification (`guardian_relationships.verification_status`) and guardian
consent remain separate from `IDENTITY_VERIFIED`. Policy acceptance remains
separate from both. Center membership remains separate from equine
ownership and from equine management. Rider qualification
`verification_status` remains a qualification fact.

## 3. What continues unchanged

- Adult self-create still inserts a private equine, an effective ownership
  row, and one current `PRIMARY_MANAGER`. That result is
  `EQUINE_OWNERSHIP_DECLARED` plus a declared management assignment.
- The current manager can still complete the private equine profile and
  private photos through the existing photo functions.
- `equines.visibility_status = PUBLIC` stays stored intent. It does not
  grant a public read, a public URL, or an upload right.
- `equine_ownerships` and `equine_management_assignments` stay the
  effective relationship tables.
- `audit_events` stays the only audit log, and it stays append-only.
- `service_role` stays out of Expo.
- No migration number is assigned by this document.

## 4. Identity verification states

A case belongs to one subject PERSON and one market. The submitter ACCOUNT
is resolved from `auth.uid()`. The subject may be the caller PERSON or,
when a later decision allows it, a minor PERSON linked by a verified
guardian relationship. See `DECISION_REQUIRED` `MINOR-IDENTITY-SUBMISSION`.

| State | Meaning |
| --- | --- |
| `DRAFT` | The caller has started a case and has not submitted it |
| `SUBMITTED` | The caller has submitted the case for review |
| `IN_REVIEW` | A reviewer has taken the case |
| `ACCEPTED` | A reviewer recorded an acceptance |
| `REJECTED` | A reviewer recorded a rejection |
| `RESUBMITTED` | The caller submitted a new cycle after rejection |
| `EXPIRED` | A previously accepted decision passed its server `expires_at` |
| `REVOKED` | A reviewer withdrew a previously accepted decision |
| `SUPERSEDED` | A newer accepted decision replaced an older one for the same subject and purpose |

`IDENTITY_VERIFIED` is true only when the latest decision for that PERSON
and market purpose is `ACCEPTED`, `expires_at` is null or still in the
future, and no revocation has been recorded. Expiry is evaluated by the
server at read and at each gate. A scheduled job is not required for the
gate to fail closed.

The caller cannot move a case to `ACCEPTED`, `REJECTED`, `EXPIRED`,
`REVOKED`, or `SUPERSEDED`.

## 5. Ownership-claim states

A claim points at one equine and one existing effective `equine_ownerships`
row, or it states that no effective row matches the assertion. It stores
`owner_type` `PERSON` or `CENTER`, exactly one owner reference, and the
claimed percentage. It does not insert or update `equine_ownerships`.

| State | Meaning |
| --- | --- |
| `DECLARED` | The effective ownership row exists from self-create or an earlier effective write. No review has accepted it |
| `SUBMITTED` | A claimant asked for review of that effective row, or filed a conflicting assertion |
| `IN_REVIEW` | A reviewer has taken the claim |
| `ACCEPTED` | Review corroborated the referenced effective row |
| `REJECTED` | Review refused the claim |
| `CONFLICT` | The assertion disagrees with the effective row or with another open claim |
| `RESUBMITTED` | The claimant submitted a new cycle after rejection |
| `EXPIRED` | An accepted corroboration passed its server `expires_at` |
| `REVOKED` | A reviewer withdrew an accepted corroboration |
| `WITHDRAWN` | The claimant withdrew an open claim before acceptance |

`EQUINE_OWNERSHIP_VERIFIED` follows the same current-decision rule as
identity. When the decision expires or is revoked, the effective ownership
row remains. The trust level returns to declared. Historical ownership
rows are not deleted.

## 6. Management-authority states

A management claim uses the same state set as an ownership claim, except
`DECLARED` refers to an effective `equine_management_assignments` row and
the claim stores `management_role` plus the assignment validity window.

`MANAGEMENT_AUTHORITY_VERIFIED` applies only to that assignment, that role,
and that window. It does not create ownership, a center membership, or an
`equine_center_permissions` row.

Accepting `PRIMARY_MANAGER` corroboration does not verify `CO_MANAGER` or
`AUTHORIZED_MANAGER`. Each assignment needs its own claim.

## 7. Who may review

Review authority is a separate grant. It is not `users.role`, not a center
membership, and not an equine ownership or management row.

A review function accepts the case or claim id only. It resolves the
reviewer PERSON from `auth.uid()`. A client-supplied reviewer id is
rejected.

The function refuses the transition when the reviewer PERSON is:

- the subject of an identity case;
- the claimant person, or a person acting for the claimant center;
- the owner or manager named by the claim;
- the submitter account's PERSON;
- outside an active review grant for that market and scope.

Center roles `ADMIN`, `MANAGER`, `INSTRUCTOR`, and `ASSESSOR` do not grant
this review. A center may later submit corroboration evidence. That
evidence is an attestation, not a decision.

`DECISION_REQUIRED` `REVIEWER-GRANT-AUTHORITY` decides who may create or
end a review grant. Until that decision, no client-callable grant function
is in scope.

## 8. Evidence categories

Categories name the kind of artifact. Acceptance records corroboration of an
existing effective relationship; it does not itself transfer ownership or
management.

| Category | Applies to |
| --- | --- |
| `IDENTITY_PROVIDER_REFERENCE` | Opaque result from the external identity provider |
| `EQUINE_IDENTIFIER_REFERENCE` | Passport/DIE, UELN, microchip and issuing body |
| `OWNERSHIP_ARTIFACT` | One principal ownership artifact. The admissible document list remains open |
| `MANAGEMENT_DELEGATION_ARTIFACT` | One current authorization or contract naming scope and validity |
| `CENTER_CORROBORATION` | Custody, presence, or a physical identity check. It does not prove or transfer ownership |
| `INSURANCE_REFERENCE` | Policy/receipt metadata linked to an activity, not to ownership |
| `REVIEWER_NOTE` | A reviewer note stored with the decision |

### Spain-first minimum evidence rule

The initial operating market is Spain. Equine identity requires passport/DIE,
UELN, microchip and issuing country/body. An ownership claim requires that
identity set plus one principal ownership artifact. A management claim requires
the identity set plus one current authorization or contract naming its scope and
validity.

A center may corroborate custody, presence, or a physical check that the
passport and the equine match. That attestation does not, by itself, prove or
transfer ownership, and it does not change an effective ownership row. It also
does not create management authority.

For France, Germany, Italy, Belgium, the Netherlands and Austria, the same EU
passport/UELN/microchip intake is used. Country adapters may accept an official
registry or issuing-body extract as strong evidence, but the system must not
assume that possession of an equine passport proves ownership. Activities in
the first market remain governed by the Spanish center/service context even
when the rider, owner or passport is foreign.

Evidence files stay private. PostgreSQL stores only minimum metadata and object
references. Identity verification uses an external provider reference; raw
identity-document images, liveness captures and biometric templates must not
be copied into the application database. Provider selection, processor terms,
lawful basis, DPIA, retention and fallback handling remain pending privacy/legal
work.

## 9. Evidence, decision, and effective relationship

| Record | Holds | Must not hold |
| --- | --- | --- |
| Evidence | Private artifact metadata for one case or claim | The review outcome, or a change to ownership or management |
| Decision | Append-only outcome, reason code, reviewer PERSON and ACCOUNT resolved on the server, timestamps, optional `expires_at` | A client-chosen reviewer, or a direct edit of the effective row |
| Effective relationship | Current `equine_ownerships` or `equine_management_assignments` row | Verification state, evidence paths, or reviewer identity |

Acceptance of a corroborating claim writes a decision and an `audit_events`
row in the same transaction. It leaves the effective row's percentage,
owner, role, and dates unchanged.

A conflicting claim writes `CONFLICT` and an audit row. It does not update
the effective row and does not transfer a percentage.

Withdrawal and rejection likewise leave the effective row unchanged.

## 10. Rejection, resubmission, expiry, and revocation

- Rejection stores a stable reason code and a reviewer decision. The
  claimant may open a resubmission cycle. The rejected decision remains.
- Resubmission creates a new submitted cycle linked to the same case or
  claim. It does not delete the rejected decision or its evidence.
- Expiry is a server comparison of `expires_at` with the current
  timestamp. The duration is `DECISION_REQUIRED` `RETENTION-AND-EXPIRY`.
  The column may exist later; this design sets no interval.
- Revocation appends a new decision. It does not update the accepted
  decision in place. Gates read the latest decision.
- After expiry or revocation, private equine profile edits and private
  photos continue for the current effective manager. Publication, service
  enablement, and real booking gates fail closed.
- Evidence objects are not deleted by rejection, expiry, or revocation.
  Deletion or retention length is `DECISION_REQUIRED` `RETENTION-AND-EXPIRY`.

## 11. Conflicts between claims

A claim conflicts when any of these is true:

- the claimed owner or percentage differs from the effective ownership row;
- the claimed manager, role, or window differs from the referenced
  assignment;
- another claim for the same equine and same relationship is `SUBMITTED`,
  `IN_REVIEW`, `RESUBMITTED`, or `CONFLICT`;
- two accepted corroborations would be current for the same effective row.

The server moves the new claim to `CONFLICT` and leaves every effective
row unchanged. It does not pick a winner. Resolving a conflict requires a
later explicit decision, which is `DECISION_REQUIRED`
`CONFLICT-RESOLUTION-AUTHORITY`.

Historical bounds use the same half-open idea already used by age rules
and assignment windows: a decision is current when its acceptance time is
in the past and `expires_at` is null or still ahead. Overlapping current
acceptances for the same subject and purpose are rejected by the review
transaction.

## 12. Traceability and audit

Each submit, review, resubmit, expire evaluation that changes a derived
gate, revoke, and conflict writes one `audit_events` row:

- `actor_account_id` and `actor_person_id` come from `auth.uid()`;
- `event_type` names the transition;
- `entity_type` and `entity_id` name the case, claim, or decision;
- `metadata` may contain the resulting state and reason code;
- `metadata` must not contain document numbers, file bytes, or storage
  paths.

The domain decision row is append-only as well. A later migration, when
authorized, should reject update and delete of decision rows the same way
`audit_events` already does. Evidence metadata can gain a withdrawn or
removed marker. It is not rewritten into a different subject.

The claimant receives the outcome and the stable reason code.
`DECISION_REQUIRED` `REVIEWER-VISIBILITY` decides whether the claimant can
see the reviewer PERSON. The safe reversible option is to hide the
reviewer identity from the claimant and from other authenticated users.

## 13. Backend gates

Future server functions, not this PR, enforce the gates. The client cannot
pass a trust level. Each gate fails closed when a required level is
missing, expired, revoked, or ambiguous.

| Operation | Continues now | Future gate |
| --- | --- | --- |
| Private equine self-create for an adult with `MARKET_CONFIRMED` | Yes | Unchanged |
| Private profile edit and private photo prepare, upload, read, retire for the current authorized manager | Yes | Unchanged |
| Mark an equine as publishable, or serve it to a public reader | No | `PUBLICATION` |
| Enable a center service that offers the equine | No | `SERVICE_ENABLEMENT` |
| Create or confirm a real booking | No | `REAL_BOOKING` |
| Move money or store fiscal identity | No | Out of scope until `FISCAL-GATE` is decided |

`PUBLICATION`, `SERVICE_ENABLEMENT`, and `REAL_BOOKING` are names for
future predicates. The exact required trust combination is
`DECISION_REQUIRED` `GATE-PREDICATE`. The reversible technical proposal,
not a product approval, is:

- the acting ACCOUNT is authenticated and the PERSON is `MARKET_CONFIRMED`;
- the acting PERSON is `IDENTITY_VERIFIED` in that market;
- publication and service enablement also require a current
  `EQUINE_OWNERSHIP_VERIFIED` or `MANAGEMENT_AUTHORITY_VERIFIED` result
  whose scope covers the operation;
- a real booking also keeps today's eligibility, guardian consent, policy
  acceptance, authorization, and calendar checks;
- `FISCAL_IDENTITY_VERIFIED` is absent from these three gates.

Setting `visibility_status` does not satisfy `PUBLICATION`. A center
membership does not satisfy it. A declared ownership row does not satisfy
it.

## 13.1 Activity insurance and owner-center calendar invariants

These rules clarify existing Architecture 2.1 calendar authority. They do not
replace `equine_availability_rules`, `equine_calendar_blocks`,
`equine_center_permissions`, `service_equines`, or the booking snapshot.

### Insurance belongs to the activity

Insurance is not required to create or keep a private equine profile and does
not prove ownership or management authority. A future activity gate may report
applicable coverage as `VERIFIED`, `DECLARED`, or `NOT_VERIFIED`. Those labels
are not implemented.

For a center-organized activity, the center's professional/operational
liability cover is the primary operational evidence. A federation licence or
accident policy is recorded separately and must not be presented as complete
third-party liability cover unless the actual policy says so. Indoor or
on-premises activity and an exterior ride are different coverage scopes;
exterior activity requires explicit off-premises coverage. The terms may
allocate information, safety and cooperation duties. They must not say that
all liability rests exclusively on the owner, and they must not displace
statutory liability or the rights of an injured third party.

`LEGAL_AND_INSURANCE_REVIEW_REQUIRED`: before real paid bookings, Spanish
legal counsel and an insurance broker must validate wording, minimum cover,
territorial/activity scope, exclusions and whether each gate is warning-only
or blocking. That review may change insurance gates without changing ownership
or management relationships.

### Owner release, center use and rider visibility

The owner, or a manager with an express delegation, defines the maximum window
in which the equine is released to one center and the services for which it may
be used. Within that release, the center may only reduce availability according
to opening hours, facilities, resources and services. The center must not
expand beyond the owner release. Neither the owner release nor the center
reduction may ignore welfare, veterinary, rest, owner-use or confirmed-booking
blocks.

The rider sees only derived bookable slots. The rider must not see the owner's
private calendar, owner-use reasons, unused release windows, center internal
capacity, or the negotiation between owner and center.

Conceptually:

`BOOKABLE_SLOT = OWNER_RELEASE_WINDOW ∩ CENTER_SERVICE_WINDOW ∩ WELFARE_RULES
∩ NO_CALENDAR_CONFLICT`

Confirmed bookings are not silently removed when a later release window is
reduced. Cancellation requires an allowed workflow, reason, audit and
notification; emergency welfare/veterinary handling remains fail-closed.

For an exterior ride, riding time need not remain inside normal center opening
hours. Pickup and return must each fall in an authorized handover window unless
an explicit late-return, overnight or temporary-custody authorization exists.
The equine is unavailable for the whole interval from preparation/pickup
through travel, activity, return and recovery.

Duration and rest are not one global hard-coded number. The backend applies the
most restrictive current legal/market, veterinary/welfare, owner, center and
service rule, including consecutive duration, rest between activities and
daily/weekly accumulation.

The existing permission split stays authoritative:

- `MANAGE_AVAILABILITY` lets a center operate only inside delegated scope.
- `MANAGE_BOOKINGS` does not create owner release or remove owner blocks.
- center membership alone grants neither permission.
- owner and center may each reduce availability; neither can make a forbidden
  slot bookable.


## 14. Candidate tables

Not a migration. Names are proposals.

- `identity_verification_cases`
- `identity_verification_decisions`
- `equine_ownership_claims`
- `equine_management_authority_claims`
- `equine_relationship_decisions` for both claim types, so ownership and
  management do not share a status column on the effective tables
- `verification_evidence`
- `verification_review_grants`

`identity_verifications`, `equine_ownership_verifications`, and
`equine_verification_evidence` in Architecture 2.1 section 7.1 are the
same candidate family. This proposal splits claims from decisions so the
effective tables stay unchanged. That split follows section 7.1; it does
not replace `equine_ownerships` or `equine_management_assignments`.

Suggested closed columns, without SQL:

- cases and claims: id, market country, subject, state, submitter account,
  optional link to the effective row, timestamps;
- decisions: id, parent id, outcome, reason code, reviewer account,
  reviewer person, decided at, optional expires at;
- evidence: id, parent type, parent id, category, private bucket, object
  path, submitter account, created at;
- grants: reviewer person, scope, market, status, validity window.

No table stores a KYC vendor name, a price, a payment id, or a public
object URL.

## 15. Candidate operations

PostgreSQL functions, granted only to `authenticated`, `SECURITY DEFINER`
only where they must read private rows, with `search_path = pg_catalog, public`,
an `auth.uid()` check, and no client-supplied person, account, or reviewer
id:

- `submit_my_identity_verification`
- `submit_my_equine_ownership_claim`
- `submit_my_equine_management_claim`
- `withdraw_my_verification_request`
- `review_identity_verification`
- `review_equine_ownership_claim`
- `review_equine_management_claim`
- `revoke_identity_verification`
- `revoke_equine_relationship_verification`

A private evidence upload can follow the existing equine-photo shape: a
narrow prepare function returns a path, an Edge Function signs that path
with server-only credentials, and a finalize function records metadata
after the object exists. That Edge Function is a candidate named
`sign-verification-evidence`. It is not part of this PR. Expo still uses
only the anon key.

Internal helpers that decide whether a grant or a trust level is current
stay revoked from `anon`, `authenticated`, and `PUBLIC`.

`assert_operation_allowed(equine_id, operation)` is an internal helper for
the future publication, service, and booking functions. It is not a client
bypass.

## 16. Permission model

- Enable RLS and revoke table privileges from `anon` and `authenticated`
  on every new table.
- No client policy exposes evidence rows or storage objects to an
  unrelated user.
- The submitter reads their own case state through an RPC that returns
  state, reason code, and timestamps.
- The reviewer reads a case only through a review RPC that checks the
  grant and the self-approval rule.
- `anon` cannot execute any of these functions.
- Storage stays private. No public bucket policy is added.
- JWT `user_metadata` is not an authorization source.
- A suspended person or account fails the same way existing identity
  helpers already fail closed.

## 17. Tests the future train must include

Security and RLS:

- `anon` cannot execute submit, review, revoke, or evidence functions;
- authenticated users cannot select the new tables or the evidence bucket;
- a caller cannot submit a case for another PERSON;
- a caller cannot pass a reviewer id;
- a reviewer cannot accept or reject their own identity, ownership, or
  management claim;
- a center role cannot review without a review grant;
- evidence metadata and bytes are unreadable by an unrelated authenticated
  user;
- error text returned to the client does not include document numbers,
  storage paths, or SQL detail.

Privacy:

- audit metadata excludes artifact contents and storage paths;
- the claimant response excludes reviewer identity until
  `REVIEWER-VISIBILITY` says otherwise.

Concurrency:

- two reviewers cannot both accept the same open case;
- a second current acceptance for the same subject and purpose fails;
- a conflicting claim cannot commit an effective-row update;
- resubmission cannot erase the rejected decision.

Revocation and expiry:

- a revoked or expired acceptance fails the future publication, service,
  and booking gates;
- the same revocation leaves private equine edit and private photo
  operations available to the current manager;
- historical decisions remain readable to the server audit path.

Product distinctions:

- `ACCOUNT_AUTHENTICATED` without `IDENTITY_VERIFIED` fails a verification
  gate;
- a declared ownership row is not reported as verified;
- a verified manager is not reported as owner;
- an inactive or unknown market fails closed;
- an existing private equine and its existing private photos still load.

## 18. Future executable train

This order starts only after the blocking decisions in section 19 are
closed. It does not name a migration file and does not start the train.

1. External identity-provider adapter for the caller's own PERSON, only after
   the pending vendor, lawful-basis, DPIA, retention, deletion and exception
   items in `KYC-PROVIDER` are closed. Manual review is the exception path.
2. Spain-first equine identity, ownership and management evidence review,
   including conflict handling that does not write the effective tables.
   Automatic acceptance of particular documents waits for the pending legal
   catalog.
3. Internal gates for publication, service enablement, and real booking,
   still without opening public discovery or taking payment.
4. Real discovery and real booking only after those gates exist. Remunerated
   bookings also wait for `LEGAL_AND_INSURANCE_REVIEW_REQUIRED`.
5. Fiscal identity and payments only after `FISCAL-GATE`. This step does not
   choose a KYC vendor.

Slices 1 and 2 should be separate pull requests. Each one preserves
private equine creation and private photos.

## 19. DECISION_REQUIRED

### REVIEWER-GRANT-AUTHORITY

- Pending decision: which operational authority may create, suspend, and
  end a `verification_review_grants` row, and for which market scope.
- Why it blocks implementation: a review RPC cannot be shipped without a
  server-side way to know who a reviewer is. Guessing a center role would
  give a hípica authority over equines it does not have.
- Safe options: keep grants insertable only by a future controlled
  server operation with no client insert; or postpone review RPCs until
  the Product Owner names the grant authority.
- Reversible recommendation: add the grant table only in the first
  implementation slice, with no client insert path, and seed no reviewers
  in a migration.

### REVIEWER-VISIBILITY

- Pending decision: whether the claimant may see the reviewer PERSON.
- Why it blocks implementation: the submitter RPC must have a fixed
  response shape before the client is built.
- Safe options: return only outcome and reason code; or return reviewer
  identity to the claimant and to nobody else.
- Reversible recommendation: hide reviewer identity.

### MINOR-IDENTITY-SUBMISSION

- Pending decision: whether a verified guardian may submit identity
  evidence for a minor PERSON who has no account.
- Why it blocks implementation: the submit function must know which
  subject PERSON it may bind to the caller.
- Safe options: the first slice accepts only the caller's own PERSON; a
  later slice allows a verified guardian to submit for the linked minor
  without treating guardian verification as identity verification.
- Reversible recommendation: limit the first slice to the caller's own
  PERSON.

### LEGAL-EVIDENCE-CATALOG

- Closed product direction: in Spain, equine identity is passport/DIE, UELN,
  microchip and issuing body. Ownership adds one principal ownership artifact.
  Management adds one current authorization or contract. Center corroboration
  may attest custody, presence or a physical identity check, and does not
  prove or transfer ownership. France, Germany, Italy, Belgium, the
  Netherlands and Austria may later use the same EU intake plus country-aware
  review. Possession of a passport alone is not ownership.
- Still pending: which documents are legally sufficient as that principal
  artifact, any additional legal rules, and any automatic sufficiency check.
- The catalog corroborates an existing relationship. It does not transfer or
  overwrite ownership. Country-specific activation waits for that legal
  validation.

### RETENTION-AND-EXPIRY

- Pending decision: how long evidence is kept, when an acceptance expires,
  and whether artifacts are deleted or only made unreachable.
- Why it blocks implementation: a default interval or a delete job would
  be an unapproved retention rule.
- Safe options: store `expires_at` only when a reviewer sets it under a
  later rule; keep artifacts until a retention decision exists; do not add
  a deletion job in the first slice.
- Reversible recommendation: no default expiry and no deletion job.

### CONFLICT-RESOLUTION-AUTHORITY

- Pending decision: who may resolve two conflicting claims, and whether
  resolution may change an effective ownership or management row.
- Why it blocks implementation: an automatic overwrite would rewrite
  ownership history and collapse review into the effective relationship.
- Safe options: leave the effective row unchanged until a separate
  authorized operation; or require a later Product Owner decision before
  any effective-row write exists.
- Reversible recommendation: conflict handling in the first equine slice
  only marks `CONFLICT` and writes audit. It does not change
  `equine_ownerships` or `equine_management_assignments`.

### GATE-PREDICATE

- Pending decision: the exact trust levels required for publication,
  service enablement, and real booking, per market and per risk.
- Why it blocks implementation: wiring a guessed predicate into booking
  or publication would change product access without approval.
- Safe options: keep the three operations unavailable; or implement the
  internal helper in fail-closed form and call it only after the predicate
  is approved.
- Reversible recommendation: do not call the helper from existing private
  equine or photo functions. Do not open public read.

### KYC-PROVIDER

- Product method decided: civil identity verification will use an external KYC
  provider with DNI/NIE or passport, liveness and 1:1 facial comparison.
- Still pending: provider/vendor selection, supported countries/documents,
  processor terms, lawful basis, DPIA, retention, deletion and an auditable
  exception/fallback path.
- The application stores an opaque provider reference, outcome, assurance
  level and timestamps. It must not treat raw document images or biometric
  templates as ordinary application evidence.
- Manual review is an exception path, not the primary identity method.

### FISCAL-GATE

- Pending decision: when `FISCAL_IDENTITY_VERIFIED` is required, which
  fiscal data is stored, and how it relates to payments.
- Why it blocks implementation: fiscal data and payments are out of scope
  and must not be implied by identity verification.
- Safe options: omit the level from all current gates; define it only in
  a later payment design.
- Reversible recommendation: omit it from publication, services, and
  bookings.

### PUBLIC-ACCESS

- Pending decision: which equine and media rows, if any, become readable
  without an authorized relationship.
- Why it blocks implementation: Architecture 2.1 allows public equine read
  only when the equine is publishable, while the accepted storage
  conflict record says `visibility_status = PUBLIC` is not itself a public
  read. Choosing the public audience now would decide both.
- Safe options: leave public read closed; define publishable as a future
  derived gate that is independent from the stored visibility token.
- Reversible recommendation: keep the current private media behavior.

## 20. ARCHITECTURE_CONFLICT

No `ARCHITECTURE_CONFLICT` is raised by this design.

The design keeps PERSON distinct from ACCOUNT, ownership distinct from
management, center membership distinct from equine authority, policy
acceptance distinct from guardian consent, and guardian verification
distinct from civil identity. It does not change `equine_ownerships`,
`equine_management_assignments`, public Storage access, or the rule that
a publishable equine is the only future candidate for public equine read.
It does not assign migration `036`.

## 21. Stop

Do not implement this design from this document. Do not add SQL, Edge
Functions, a provider, public discovery, bookings, or payments until the
blocking decisions for that slice are closed and a later train is
explicitly authorized.
