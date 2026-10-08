# Verification reviewer UI — Stage 4B inventory

**Status:** stopped after Stage 0. No screen, no hook, no migration `039`, no grant seed, no Edge Function, no deploy.
**Date:** 2026-10-08
**Base:** `origin/main` `901a320cdef648c5fdebb28945c2001a8b2041c1` (Stage 4A, PR #55).
**Remote:** project `efkauegdlmfkonzwyyiv` remains at exact version `038`. This document does not change that.

Codex review on PR #56 requires this inventory to separate four future operations and to record a Spain-pilot grant direction. Neither is implemented here. This pull request does not authorize migration `039`.

Stage 4A lets the signed-in person read Spain identity status and submit their own identity case. It does not let anyone else read or decide that case.

## Can Stage 4B ship on the existing RPCs?

No. Migrations `036`–`038` define how a grant would match a case, and `037` can record a decision when the caller already knows the case or claim id. They do not identify an operational reviewer, and they do not return a queue, an authorized detail, or a private evidence reference.

## Authority found in `036`–`038`

There is no global administrator role and no center role that reviews.

| Question | What `036`–`038` actually do |
| --- | --- |
| Who is the caller? | `verification_resolve_caller()` reads `auth.uid()`. `user_accounts.auth_user_id` is unique and references `auth.users`. `user_accounts.person_id` is unique. Both the account and the person must be `ACTIVE`. A missing or suspended caller fails with `42501`. |
| What would make that person a reviewer? | One `ACTIVE` row in `verification_review_grants` for that `reviewer_person_id`, with `valid_from <= now()`. An active row must have `valid_until` null. |
| What scope would that row have? | `PLATFORM_IDENTITY` with a null market matches every identity case. `PLATFORM_EQUINE` with a null market matches every equine claim. `MARKET` requires one `market_country_code` and matches both identity cases and equine claims in that country. |
| Which rows could they decide today? | `review_identity_case`, `review_equine_ownership_claim`, and `review_equine_management_claim` accept only `SUBMITTED`, `IN_REVIEW`, or `RESUBMITTED`, and only when `verification_review_grant_matches` is true. |
| Who is refused even with a grant? | The subject person, the submitter account, the named owner or manager, and a person with an active membership at the claimant center. Center membership blocks that review. It never grants it. |

No grant is seeded. `authenticated` has no privilege on `verification_review_grants`. No RPC creates, suspends, ends, or lists a grant. Expo cannot create, change, or close one. `users.role`, JWT `user_metadata`, ownership, and management are not review authority.

`review_*` requires `p_outcome` of `ACCEPTED` or `REJECTED` and a trimmed `p_reason_code` of 1–80 characters for both outcomes. The current functions do not check that the required evidence exists before `ACCEPTED`. `expires_at` stays null. Acceptance does not write `equine_ownerships` or `equine_management_assignments`.

There is no reviewer queue, no authorized detail read, and no evidence read. RLS is enabled on every verification table, and `public`, `anon`, and `authenticated` are revoked. A client cannot discover a case id by selecting. Helpers `verification_resolve_caller` and `verification_review_grant_matches` are revoked from `authenticated`.

`list_my_verification_status`, `list_my_identity_cases`, `list_my_equine_ownership_claims`, and `list_my_equine_management_claims` return the caller's own rows. They are not a reviewer inbox. They omit reviewer identity.

Decision rows are append-only. The insert trigger rejects the subject, the claimant person, or the submitter account. Two decisions on the same open case or claim serialize with a transaction advisory lock. A lost race, a closed case, a missing grant, and a self-review all fail with `42501` and the text `Verification request is not available`. Audit metadata on those RPCs stores outcome and reason code. It does not store storage paths or artifact contents.

`EXPIRED`, `REVOKED`, `WITHDRAWN`, `CONFLICT`, `SUPERSEDED`, `DECLARED`, and `DRAFT` are not decidable through these RPCs.

## Four operations, kept separate

A future reviewer flow is four checks, not one payload. Each one resolves the actor again from `auth.uid()`. None of them is implemented in this train. No SQL signature is fixed here: the evidence set still depends on the KYC provider, the legal evidence catalog, and the retention policy.

### 1. Pseudonymous queue

The queue identifies work. It does not verify a person, a horse, or a document.

It may return only:

- an opaque case or claim id;
- the kind of case or claim;
- the market;
- the state;
- a timestamp already stored on that row;
- the evidence categories present.

It does not return a full name, a private path, a document, a biometric value, `storage_bucket`, `storage_path`, `provider_reference`, or a signed URL.

A reviewer who can see the queue still cannot accept it. Acceptance requires the later checks.

### 2. Opening one case

Opening is a new authorization, not a reuse of the queue response.

The server:

- resolves the actor again from `auth.uid()`;
- checks that a grant is still current;
- checks the Spain-pilot scope `MARKET` with `market_country_code = 'ES'`;
- checks self-review and the same conflict-of-interest refusals already used by `review_*`;
- checks that the case or claim is still open.

Only after those checks may the response include the minimum identity and the minimum facts required to review that one case. That detail is for the authorized reviewer of that case. It is not returned to other users. While `REVIEWER-VISIBILITY` stays open, the claimant does not see the reviewer person.

Each opening is an audited event. The audit record does not contain document numbers, storage paths, or artifact contents.

### 3. Private evidence access

Expo never receives `storage_bucket` or `storage_path`.

A future Edge Function, not this train:

- authorizes the reviewer again, with the same actor, grant, scope, conflict, and open-case checks;
- uses server-side credentials, never the `service_role` key inside Expo;
- returns a short-lived signed URL for one named artifact;
- does not return secrets or a persistent URL;
- writes an audit event for that access.

A URL already issued can keep working until its TTL ends. After a grant is suspended or closed, that TTL is the longest remaining exposure of an artifact that was already signed. The function must not mint a new URL once the grant is no longer current.

This access is not a Storage policy for `authenticated`, and it is not a public bucket.

### 4. Decision

The existing `review_*` functions already resolve the actor from `auth.uid()`, refuse self-review and center affiliation, refuse a case that is no longer open, serialize two reviewers, and append a decision that cannot be updated or deleted.

A future decision path must check those conditions again at decision time. It must also refuse `ACCEPTED` when the evidence required for that case type is absent. The current RPCs do not perform that evidence check, so they are not a sufficient accept path.

For identity, ordinary manual acceptance is not available before a KYC provider result exists. Manual identity review is a future exception. It cannot accept a current request that lacks sufficient KYC evidence.

Reason codes stay stable values. Audit metadata stores the outcome and the reason code, not free-text secrets, document numbers, or storage paths.

## Identity minimization

The queue stays pseudonymous.

An authorized reviewer may see, in the opened case only, the minimum identity needed to perform that review. Other users do not receive that detail. The claimant does not see the reviewer person while `REVIEWER-VISIBILITY` stays open.

Opening a case and reading an artifact are audited. Minimization is not a ban on the reviewer's seeing the subject of the case they are authorized to decide.

## Recommended Spain-pilot grant direction

This is a direction for a later train. It creates no row.

- Scope `MARKET`.
- `market_country_code = 'ES'`.
- The reviewer is a PERSON already identified and designated.
- No hípica affiliation or center role grants review.
- `users.role`, JWT metadata, ownership, and management are not authority.
- Grants are not created automatically.
- A migration seeds no reviewers.
- A person cannot register themselves as a reviewer or grant review to themselves.
- Expo cannot create, change, or close a grant.

`PLATFORM_IDENTITY` and `PLATFORM_EQUINE` are not the pilot default. They match one domain in every market.

A current `MARKET` / `ES` grant matches both identity cases and equine claims in Spain. That is what `verification_review_grant_matches` does today. The evidence rule above still blocks acceptance when the required evidence is missing, including ordinary manual acceptance of an identity case that has no KYC result.

## Administrative grant operation, not implemented

A later server-side operation may:

- grant review;
- suspend a grant;
- close a grant;
- read the grant history.

The acting administrator is resolved from Auth. The client does not send that actor's id. Each transition is audited. The history is append-only: closing or suspending a grant records the transition and does not delete the row. Expo does not call this operation. The mobile app does not use `service_role`.

This document does not invent an in-app superadministrator. The bootstrap of that administrative operator, and the concrete identity of the operator, still need a separate security review.

The person who designates reviewers governs permission. That designation is not itself the proof of identity, ownership, or management.

## Permission is not the proof

- Civil identity will use, as the primary method, an external KYC provider with a document, a liveness check, and a facial comparison. The application stores an opaque provider reference and outcome metadata, not raw biometrics.
- Manual identity review is a future exception. It cannot accept current requests that lack sufficient KYC evidence.
- Ownership and management will be checked against traceable documents.
- A future center corroboration may confirm custody, presence, or a physical check. It does not, by itself, transfer or prove ownership.
- The platform is not the sole material source of verification.

Provider selection, the legal evidence catalog, retention, and conflict resolution stay open. This inventory does not choose them.

## Future migration `039` is not authorized

PR #56 does not authorize `039`. It does not edit `036`–`038`.

A separate later proposal, reviewed before any SQL is written, must cover at least:

- an audited administrative operation for grants;
- a pseudonymous queue;
- an authorized case detail;
- authorization of one private evidence artifact;
- an audit event for each opening and each evidence access;
- a refusal of `ACCEPTED` when the required evidence is missing;
- grant suspension, closure, and a fresh grant check on every operation;
- concurrency between two reviewers;
- RLS and privileges, with no client table access and no `service_role` in Expo;
- negative tests and two-session tests;
- a manual security review before implementation.

That proposal must not freeze SQL contracts that depend on the KYC provider, the legal evidence catalog, or the retention policy. Those three items stay open. The proposal is `SECURITY_REVIEW_REQUIRED` before implementation.

## Still open, unchanged

`REVIEWER-VISIBILITY`, `MINOR-IDENTITY-SUBMISSION`, `LEGAL-EVIDENCE-CATALOG`, `RETENTION-AND-EXPIRY`, `CONFLICT-RESOLUTION-AUTHORITY`, `GATE-PREDICATE`, `KYC-PROVIDER`, `FISCAL-GATE`, `PUBLIC-ACCESS`, and `LEGAL_AND_INSURANCE_REVIEW_REQUIRED`.

The bootstrap and the concrete identity of the administrative grant operator are also open, as a separate security review.

This train does not start KYC, facial recognition, document upload, biometric storage, fiscal identity, retention, center corroboration, a reviewer screen, or Stage 5.
