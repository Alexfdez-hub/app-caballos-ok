# ARCHITECTURE_CONFLICT — 019–022 preflight

**Project:** app-caballos-ok
**Date:** 2026-09-02
**Architecture:** Data Architecture 2.1 Frozen
**Baseline:** `origin/main` `40e1f1e7b201796c632ec480bfba07d43564d439` (merge of PR #18)
**Branch:** `docs/architecture-conflict-019`
**Status:** CLOSED / RESOLVED
**Decision:** Product Owner closed these conflicts via PR #19 comment
`5516860208` (2026-09-02). Implementation of 019 is **authorized** on
a separate branch. This docs PR is a close-out record, **not** a STOP
and **not** migration 019. Do not add `019_*.sql` here.

This document is the durable conflict report. Historical phase reports
for 015–018 are not rewritten. They remain branch-time records.

## Live baseline (verified 2026-09-02)

- PRs #15–#18 merged sequentially into `main`.
- Migrations `001`–`018` exist on `main`. `019` does not exist.
- Product Owner states remote project `efkauegdlmfkonzwyyiv` is aligned
  through `018`; 9 new 015–018 tables present; RLS on all 9; no direct
  anon/authenticated table grants; new internal trigger functions not
  client-executable; Expo Go smoke PASS.
- This agent does not deploy and does not modify remote Supabase.

## Preflight method

Read: `docs/16_AI_DOCUMENT_MAP_AND_USAGE.md`, `AI_INSTRUCTIONS.md`,
`docs/DATA_ARCHITECTURE.md`, `docs/MIGRATION_PLAN.md`,
`docs/CURRENT_ARCHITECTURE_REPORT.md`, `docs/MIGRATION_STATUS.md`,
phase reports 015–018, migrations `001`–`018`, relevant SQL tests.

Compared required 019–022 schema, status vocabularies, permissions,
source types, state transitions and RPC authority against frozen
Architecture 2.1. Named tokens were treated as frozen. Unnamed,
ambiguous or contradictory rules were not inferred.

## What is already frozen (not in dispute)

- PERSON ≠ ACCOUNT; PARTICIPANT ≠ BOOKER; OWNERSHIP ≠ MANAGEMENT;
  CENTER MEMBERSHIP ≠ EQUINE PERMISSION; ASSESSMENT ≠ ZERO SESSION;
  QUALIFICATION ≠ ASSESSMENT ≠ AUTHORIZATION; POLICY ACCEPTANCE ≠
  GUARDIAN CONSENT; availability ≠ calendar occupancy.
- `zero_sessions.result`:
  `PENDING | APPROVED | APPROVED_WITH_RESTRICTIONS | REJECTED | CANCELLED`.
- `rider_equine_authorizations.authorization_type`:
  `OWNER_APPROVAL | ZERO_SESSION | CENTER_DELEGATED_APPROVAL`.
- Booking statuses:
  `DRAFT | REQUESTED | PENDING_REQUIREMENTS | PENDING_APPROVAL | APPROVED | CONFIRMED | ACTIVE | COMPLETED | REJECTED | CANCELLED | EXPIRED | DISPUTED`.
- `booking_requirements.status`:
  `PENDING | SATISFIED | WAIVED | FAILED | EXPIRED`.
- Eligibility result tokens:
  `ELIGIBLE | ELIGIBLE_WITH_SUPERVISION | REQUIRES_CENTER_ASSESSMENT | REQUIRES_ZERO_SESSION | REQUIRES_OWNER_APPROVAL | REQUIRES_GUARDIAN_CONSENT | QUALIFICATION_NOT_VERIFIED | NOT_ELIGIBLE`.
- Calendar `block_type`:
  `BOOKING | OWNER_USE | LESSON | COURSE | TRAIL_RIDE | VET | REST | MANUAL_BLOCK | OTHER`.
- Equine–center permission codes:
  `MANAGE_AVAILABILITY | MANAGE_BOOKINGS | ASSESS_RIDERS | APPROVE_RIDERS | MANAGE_REQUIREMENTS | VIEW_ACTIVITY`.
- Center membership roles: `ADMIN | MANAGER | INSTRUCTOR | ASSESSOR`.
- Existing server-internal primitives:
  `has_active_center_role`, `has_active_equine_center_permission`,
  `has_active_equine_management_role`, `check_guardian_consent`.
- No client table CRUD. RLS deny-by-default. No `now()` in table CHECKs.
- No `approve_zero_session()` until issuer/evaluator authority and
  transitions are frozen. No eligibility/calendar/booking in 019.
- `confirm_booking()` atomic: revalidate inside a transaction, create
  canonical calendar block, store snapshot, confirm only if every
  mandatory condition succeeds, rollback on failure.

## Existing primitive map (named, not a new mapping)

| Primitive | Frozen meaning |
|---|---|
| `has_active_center_role(person, center, role)` | Center membership `ADMIN\|MANAGER\|INSTRUCTOR\|ASSESSOR`. Not equine permission. |
| `has_active_equine_center_permission(equine, center, code)` | Explicit equine–center permission. Membership and assignment do not imply it. |
| `has_active_equine_management_role(person, equine, role)` | Management assignment. Not ownership. |
| `equine_ownerships` | PERSON or CENTER XOR. No current-owner helper exists. |
| Assessment create/validate | Active `ASSESSOR` membership at that Center. `ASSESS_RIDERS` is not sufficient. |
| Service–equine link | Effective `MANAGE_REQUIREMENTS` at the service Center. |

---

ARCHITECTURE_CONFLICT

Current frozen rule:
`rider_equine_authorizations` has `status`, `valid_from`, `valid_until`
and `revoked_at`. Architecture 2.1 does not enumerate `status` tokens.
Zero Session uses a separate named `result` vocabulary. Permission
lifecycle `ACTIVE|REVOKED` and catalog `ACTIVE|INACTIVE` are Product
Owner decisions for other tables, not for this one.

Missing or conflicting decision:
The exact stored lifecycle for `rider_equine_authorizations.status`.

Why implementation cannot safely infer it:
018 stopped until Product Owner named `ACTIVE|INACTIVE`. Reusing
permission `ACTIVE|REVOKED` because `revoked_at` exists, or catalog
`ACTIVE|INACTIVE`, or assessment `VALID|REVOKED|EXPIRED`, would invent
tokens. Unconstrained `text` would accept invalid strings.

Options:
1. `ACTIVE | REVOKED` with `revoked_at` required iff `REVOKED`, parallel
   to `equine_center_permissions`. Stored ACTIVE is currently effective
   only when `valid_from <= now()` and (`valid_until` is null or
   `valid_until >= now()`), without putting `now()` in a CHECK.
2. `ACTIVE | REVOKED | EXPIRED` — `EXPIRED` stored, not computed.
3. Another Product Owner-named set. Do not copy assessment or
   qualification tokens onto authorization.

Recommended option:
Option 1. Closest named pattern to a row that already has `revoked_at`.
Effective-at-time remains a helper, not a CHECK.

Affected migrations:
019 (blocks 020–022 consumers of authorization status).

---

ARCHITECTURE_CONFLICT

Current frozen rule:
Issuer and evaluator are PERSON. Authority must be enforced
server-side using existing Center/equine permission primitives.
OWNERSHIP ≠ MANAGEMENT. CENTER MEMBERSHIP ≠ EQUINE PERMISSION.
ASSESSMENT ≠ ZERO SESSION. `ASSESSOR` membership is the named
authority for `rider_assessments` only. `APPROVE_RIDERS` and
`ASSESS_RIDERS` exist as equine–center permission codes without a
named binding to Zero Session evaluation or to each authorization type.

Missing or conflicting decision:
Which primitive authorizes:
- `zero_sessions.evaluator_person_id`
- `OWNER_APPROVAL.issued_by_person_id`
- `ZERO_SESSION` authorization issuer
- `CENTER_DELEGATED_APPROVAL.issued_by_person_id`
including CENTER-owned equines, where ownership is a Center and the
issuer column is still PERSON.

Why implementation cannot safely infer it:
Binding Zero Session evaluation to `ASSESSOR` would collapse assessment
and Zero Session. Binding it to `ASSESS_RIDERS` or `APPROVE_RIDERS` is
an unstated mapping. Binding `OWNER_APPROVAL` to `PRIMARY_MANAGER`
would collapse ownership and management. There is no
`has_active_equine_owner` helper, and CENTER owners have no named
person issuer. Skipping the trigger would violate the 019 requirement
to enforce authority. Writing the trigger would invent authorization
semantics.

Options:
1. Name the primitive per type, for example:
   - `OWNER_APPROVAL`: effective PERSON owner of the equine; CENTER-owned
     equines cannot use this type until a Center-owner person issuer is
     named.
   - Zero Session evaluator: effective `APPROVE_RIDERS` at
     `(equine_id, center_id)` — not `ASSESSOR` membership.
   - `CENTER_DELEGATED_APPROVAL`: same `APPROVE_RIDERS` at that
     equine+center; `center_id` required.
   - `ZERO_SESSION` authorization issuer: the Zero Session
     `evaluator_person_id`, with `source_zero_session_id` required.
2. Name different primitives (`ASSESS_RIDERS`, `INSTRUCTOR`,
   `PRIMARY_MANAGER`, Center `ADMIN`/`MANAGER`).
3. Defer authority triggers and `approve_zero_session()` until the map
   is named; tables still cannot land without the status decision above.

Recommended option:
Option 1, with CENTER-owner issuer named separately if Product Owner
wants `OWNER_APPROVAL` on CENTER-owned equines. Do not treat membership
or assignment as sufficient.

Affected migrations:
019. `approve_zero_session()` stays out of 019 until this is named.

---

ARCHITECTURE_CONFLICT

Current frozen rule:
An assessor cannot assess themselves. A rider cannot mark their own
qualification `VERIFIED`. Product Owner P0 test: owner-as-rider must
work. 019 says reject self-approval only where architecture makes it
invalid. Architecture 2.1 does not say whether
`zero_sessions.evaluator_person_id` may equal `rider_person_id`, or
whether an owner-rider may issue `OWNER_APPROVAL` for themselves.

Missing or conflicting decision:
Self-approval / self-evaluation rules per record type.

Why implementation cannot safely infer it:
Copying the assessment CHECK onto Zero Session invents a rule.
Allowing all self-approval contradicts “reject where invalid”.
Forbidding owner-rider `OWNER_APPROVAL` would fight the owner-as-rider
P0 case.

Options:
1. Evaluator ≠ rider on `zero_sessions`. `CENTER_DELEGATED_APPROVAL`
   issuer ≠ rider. `OWNER_APPROVAL` issuer may equal rider when that
   person is an effective PERSON owner.
2. Forbid issuer/evaluator = rider on every 019 row.
3. Allow all combinations until a later RPC.

Recommended option:
Option 1.

Affected migrations:
019.

---

ARCHITECTURE_CONFLICT

Current frozen rule:
The three authorization types remain distinguishable. Zero Session
result is not the authorization row. Columns include `center_id` and
`source_zero_session_id`. Nullability and required-by-type CHECKs are
not named. `evaluator_person_id`, `scheduled_at` and `performed_at`
are listed without saying which `result` values require them.

Missing or conflicting decision:
- When `source_zero_session_id` is required or forbidden.
- When `center_id` is required on an authorization.
- Whether `APPROVED` / `APPROVED_WITH_RESTRICTIONS` require evaluator
  and `performed_at`.

Why implementation cannot safely infer it:
Requiring `source_zero_session_id` only for type `ZERO_SESSION` is
plausible and still unstated. Requiring `center_id` only for
`CENTER_DELEGATED_APPROVAL` is plausible and still unstated. A Zero
Session row always has `center_id` in the architecture list.

Options:
1. Type `ZERO_SESSION` requires `source_zero_session_id` pointing at a
   Zero Session for the same rider+equine; other types require it null.
   `CENTER_DELEGATED_APPROVAL` requires `center_id`. `OWNER_APPROVAL`
   `center_id` null. `APPROVED` / `APPROVED_WITH_RESTRICTIONS` require
   `evaluator_person_id` and `performed_at`.
2. All FKs optional; later RPC fills them.
3. Product Owner names a different CHECK matrix.

Recommended option:
Option 1. Do not auto-insert an authorization from a Zero Session
`result`.

Affected migrations:
019.

---

ARCHITECTURE_CONFLICT

Current frozen rule:
`equine_availability_rules.status` and `equine_calendar_blocks.status`
are unnamed. `equine_calendar_blocks.source_type` / `source_id` are
listed without a source vocabulary. `recurrence_rule` is a column
without recurrence semantics. PostgreSQL must prevent incompatible
overlaps for the same equine via `tstzrange` + `EXCLUDE USING gist`
or an equivalent transactional mechanism. P0: concurrent double
booking fails; a VET block prevents a new session.

Missing or conflicting decision:
Calendar status tokens; calendar `source_type` tokens; whether every
overlap is incompatible or only some `block_type` pairs; recurrence
behavior.

Why implementation cannot safely infer it:
019/018 precedent forbids inventing status or source tokens. Treating
all same-equine overlaps as incompatible implements canonical occupancy
but may over-constrain if REST/MANUAL_BLOCK were meant to stack. An
incompatibility matrix would be invented. Interpreting `recurrence_rule`
would invent recurrence.

Options:
1. Status `ACTIVE | INACTIVE` (catalog pair). No `source_type` CHECK in
   020; `source_id` opaque uuid. Store `recurrence_rule` as optional
   trimmed text without expanding occurrences. Exclude all overlapping
   `tstzrange`s for the same equine while status is `ACTIVE`.
2. Status `ACTIVE | CANCELLED` or `ACTIVE | ENDED`. Named source types
   such as `BOOKING | MANUAL | SYSTEM` — only if Product Owner names
   them. Named overlap matrix — only if Product Owner names it.
3. Defer 020 until those tokens and the overlap rule are named.

Recommended option:
Option 3 unless Product Owner adopts option 1 in writing. Do not invent
recurrence expansion.

Affected migrations:
020, and 022 `confirm_booking()` which must insert a canonical block.

---

ARCHITECTURE_CONFLICT

Current frozen rule:
`booking_requirements` has `requirement_type`, `source_type` and
`source_id`. Equine requirement types and `OWNER | CENTER | MARKET`
are frozen on `equine_requirements`, not on this table. `WAIVED` is a
named status. Waiver rules are not named. Client CRUD must not force
critical booking states. `confirm_booking()` is 022, not 021.

Missing or conflicting decision:
`booking_requirements.requirement_type` and `source_type` vocabularies.
Who may set `WAIVED`. Whether `bookings.eligibility_status` reuses the
section 15 tokens.

Options:
1. Reuse equine requirement types plus an explicit
   `GUARDIAN_CONSENT` type; reuse `OWNER | CENTER | MARKET` for
   `source_type`; store `WAIVED` but add no waive RPC in 021/022.
   Reuse section 15 tokens for `eligibility_status`.
2. Product Owner names a distinct booking-requirement catalog.
3. Defer 021 CHECKs on those two columns until named.

Recommended option:
Option 1 for snapshots only, with no waive RPC. If Product Owner
rejects reuse, option 3.

Affected migrations:
021, 022.

---

ARCHITECTURE_CONFLICT

Current frozen rule:
P0 RPCs include `check_booking_eligibility`, `create_booking_request`
and `confirm_booking`. The client requests; PostgreSQL decides.
Eligibility evaluates PERSON + EQUINE + SERVICE + CENTER + TIME +
owner/center/market policy and may return multiple unmet requirements.
`confirm_booking()` is atomic. Booking transition permissions and the
status graph (which prior status may become `CONFIRMED`, who may call
each RPC) are not named. Architecture does not say whether
`ZERO_SESSION_REQUIRED` is satisfied by an `APPROVED` Zero Session
row, by a `ZERO_SESSION` authorization, or both; nor whether
`OWNER_APPROVAL_REQUIRED` is satisfied only by `OWNER_APPROVAL` or
also by `CENTER_DELEGATED_APPROVAL`. Function return shape is unnamed.

Missing or conflicting decision:
Caller authority and allowed transitions for the three RPCs.
Satisfaction rules for Zero Session vs authorization vs owner approval.
Eligibility return shape. Waiver.

Why implementation cannot safely infer it:
Inventing “any authenticated user may request” or “center
`MANAGE_BOOKINGS` may confirm” would invent booking transition
permissions. Treating an `APPROVED` Zero Session as authorization would
collapse the two records. Implementing `WAIVED` as a confirm bypass
would invent waiver rules.

Options:
1. Name: caller of `create_booking_request` is the booked-by account
   (participant may be another PERSON, including a minor with consent).
   `confirm_booking` is server-internal after eligibility+availability
   succeed, callable by the booker, not a Center override. Satisfaction:
   `ZERO_SESSION_REQUIRED` needs a currently effective `ZERO_SESSION`
   authorization (rejected Zero Session is not enough);
   `OWNER_APPROVAL_REQUIRED` needs currently effective `OWNER_APPROVAL`;
   `CENTER_ASSESSMENT_REQUIRED` needs a currently effective `VALID`
   assessment at that Center. Return a table of unmet requirement rows
   plus an overall token. No waive path.
2. Center `MANAGE_BOOKINGS` confirms. Different satisfaction pairing.
3. Defer 022 until those rules are named. 021 may still store bookings
   without confirm RPC if 021 vocabularies are named.

Recommended option:
Option 3 for 022. Option 1 is the implementation recommendation if
Product Owner wants the three RPCs in this train.

Affected migrations:
022 (and 021 if confirm-side snapshots need the same tokens).

## Preflight STOP (historical — superseded)

The preflight on HEAD `ee0dc57` recorded the unnamed tokens below and
stopped before SQL. That STOP is closed by the Product Owner package.
This docs branch still contains **no** `019_*.sql`. Implementation
starts on `refactor/phase-9a-zero-sessions-authorizations` targeting
`main`. No merge, retarget, remote deploy, push to `main`, force-push,
`023`, payments, Sessions, Storage or Autofix.

## Next

Closed. See **Closed by Product Owner** above. Implementation of 019
is a separate PR on `refactor/phase-9a-zero-sessions-authorizations`.

## Closed by Product Owner (2026-09-02)

Comment https://github.com/Alexfdez-hub/app-caballos-ok/pull/19#issuecomment-5516860208

Ordinary implementation details may be derived from Architecture 2.1,
existing patterns and this decision. Escalate only a genuine product
contradiction, legal/economic risk, security-critical ambiguity with
materially different outcomes, or an irreversible action outside scope.

### 019

- `rider_equine_authorizations.status`: `ACTIVE | REVOKED`.
  `revoked_at` required iff `REVOKED`. No stored `EXPIRED`. Current
  effectiveness: ACTIVE, `valid_from <= now()`, null/future
  `valid_until`. No `now()` in a CHECK.
- Zero Session evaluator ≠ rider. Requires active Center `ASSESSOR` at
  `center_id` **and** effective `ASSESS_RIDERS` for that equine+Center.
  Assessment remains distinct from Zero Session.
- `ZERO_SESSION` authorization: `source_zero_session_id` required for
  the same rider+equine with result `APPROVED` or
  `APPROVED_WITH_RESTRICTIONS`; issuer is that session's evaluator.
- `CENTER_DELEGATED_APPROVAL`: `center_id` required; issuer has
  effective `APPROVE_RIDERS`; issuer ≠ rider.
- `OWNER_APPROVAL`: PERSON owner may equal rider. CENTER-owned equine:
  `center_id` is the owning Center; issuer has effective
  `APPROVE_RIDERS` there. PERSON `OWNER_APPROVAL` has null `center_id`.
- Membership, assignment and management alone never substitute.
- Only type `ZERO_SESSION` may have `source_zero_session_id`.
- `APPROVED` / `APPROVED_WITH_RESTRICTIONS` require evaluator and
  `performed_at`. A Zero Session result never auto-creates an
  authorization.
- Do **not** bind the Zero Session evaluator to `APPROVE_RIDERS`.
- `approve_zero_session()` remains omitted until caller identity and
  result transitions are named; 019 enforces the frozen authority on
  INSERT/UPDATE instead.

**CENTER-owner “represent the owning Center” (derived, not a new role):**
the issuer PERSON must have an active Center membership `ADMIN` or
`MANAGER` at the owning Center **and** effective explicit
`APPROVE_RIDERS` for that equine at that Center. `INSTRUCTOR` /
`ASSESSOR` membership, assignment and management do not substitute.

### 020

- Availability status `ACTIVE | INACTIVE`.
- Calendar block status `ACTIVE | CANCELLED`.
- `recurrence_rule` optional trimmed text; no expansion in 020.
- `source_type` `BOOKING | ACTIVITY | MANUAL | SYSTEM`; `source_id`
  opaque uuid.
- All ACTIVE same-equine overlapping blocks are incompatible.

### 021

- `bookings.eligibility_status` uses Architecture 2.1 eligibility tokens.
- Requirement types: frozen equine types plus `GUARDIAN_CONSENT` and
  `POLICY_ACCEPTANCE`.
- Requirement sources: `OWNER | CENTER | MARKET | EQUINE | SERVICE | GUARDIAN | POLICY`.
- `WAIVED` stored; no waiver RPC.
- Booker may request for own PERSON or a minor with a current VERIFIED
  guardian relationship.

### 022

- `check_booking_eligibility`: participant account, verified guardian
  for that minor, or effective `MANAGE_BOOKINGS`.
- `create_booking_request`: booked-by account; status `REQUESTED`; never
  confirms. Server may classify `PENDING_REQUIREMENTS`,
  `PENDING_APPROVAL`, or `APPROVED`.
- `confirm_booking`: only effective `MANAGE_BOOKINGS`; only an
  `APPROVED` booking; rider/booker cannot self-confirm.
- `ZERO_SESSION_REQUIRED` needs a currently effective `ZERO_SESSION`
  authorization. `OWNER_APPROVAL_REQUIRED` needs currently effective
  `OWNER_APPROVAL`. `CENTER_ASSESSMENT_REQUIRED` needs current `VALID`
  assessment at that Center.
- Atomic confirm + BOOKING calendar block + snapshots. Concurrent
  conflicting confirms cannot both succeed. No waiver path.
