# Verification reviewer UI — Stage 4B inventory

**Status:** stopped after Stage 0. No screen, no hook, no migration `039`, no grant seed, no deploy.
**Date:** 2026-10-08
**Base:** `origin/main` `901a320cdef648c5fdebb28945c2001a8b2041c1` (Stage 4A, PR #55).
**Remote:** project `efkauegdlmfkonzwyyiv` remains at exact version `038`. This document does not change that.

Stage 4A lets the signed-in person read Spain identity status and submit their own identity case. It does not let anyone else read or decide that case.

## Can Stage 4B ship on the existing RPCs?

No. Migrations `036`–`038` define how a grant would match a case, and `037` can record a decision when the caller already knows the case or claim id. They do not identify an operational reviewer, and they do not return the queue, the detail, or the evidence references that a reviewer screen needs.

## Authority found

There is no global administrator role and no center role that reviews.

| Question | What `036`–`038` actually do |
| --- | --- |
| Who is the caller? | `verification_resolve_caller()` reads `auth.uid()`. `user_accounts.auth_user_id` is unique and references `auth.users`. `user_accounts.person_id` is unique. Both the account and the person must be `ACTIVE`. A missing or suspended caller fails with `42501`. |
| What would make that person a reviewer? | One `ACTIVE` row in `verification_review_grants` for that `reviewer_person_id`, with `valid_from <= now()`. An active row must have `valid_until` null. |
| What scope would that row have? | `PLATFORM_IDENTITY` with a null market matches every identity case. `PLATFORM_EQUINE` with a null market matches every equine claim. `MARKET` requires one `market_country_code` and matches both identity cases and equine claims in that country. |
| Which rows could they decide? | `review_identity_case`, `review_equine_ownership_claim`, and `review_equine_management_claim` accept only `SUBMITTED`, `IN_REVIEW`, or `RESUBMITTED`, and only when `verification_review_grant_matches` is true. |
| Who is refused even with a grant? | The subject person, the submitter account, the named owner or manager, and a person with an active membership at the claimant center. Center membership blocks that review. It never grants it. |

No grant is seeded. `authenticated` has no privilege on `verification_review_grants`. No RPC creates, ends, or lists a grant. `REVIEWER-GRANT-AUTHORITY` in `docs/MANUAL_VERIFICATION_MVP0_DESIGN.md` is still open. The 2026-10-04 review-RPC decision says grants are read, not created. The 2026-10-05 Stage 4A decision leaves the reviewer UI unauthorized.

`users.role` is not a review grant. Center roles `ADMIN`, `MANAGER`, `INSTRUCTOR`, and `ASSESSOR` are not a review grant. Ownership and management rows are not a review grant.

## RPCs an Expo client may call

Granted to `authenticated` only:

| RPC | Actor it serves | What it returns |
| --- | --- | --- |
| `list_my_verification_status()` | The caller's own person | Own trust codes. No other person's cases. |
| `list_my_identity_cases()` | Submitter account or subject person | Own case state, reason code, and timestamps. No reviewer identity. |
| `list_my_equine_ownership_claims()` | Submitter account | Own claims. No evidence fields. |
| `list_my_equine_management_claims()` | Submitter account | Own claims. No evidence fields. |
| `submit_my_identity_case(text)` | The caller's own person | Creates that person's case. |
| `submit_my_equine_ownership_claim(...)` | Caller, or an active center member for a center claim | Creates a claim. Affiliation is not review authority. |
| `submit_my_equine_management_claim(...)` | Same split as ownership | Creates a claim. Affiliation is not review authority. |
| `review_identity_case(uuid, text, text)` | A granted person who is not the subject or submitter | Writes one decision. Returns the decision echo, not the case. |
| `review_equine_ownership_claim(uuid, text, text)` | A granted person who is not the claimant | Same, for one ownership claim. |
| `review_equine_management_claim(uuid, text, text)` | A granted person who is not the claimant | Same, for one management claim. |

`review_*` requires `p_outcome` of `ACCEPTED` or `REJECTED` and a trimmed `p_reason_code` of 1–80 characters for both outcomes. `expires_at` stays null. Acceptance does not write `equine_ownerships` or `equine_management_assignments`.

There is no `list_cases_i_may_review`, no `get_review_case`, and no evidence read. RLS is enabled on every verification table, and `public`, `anon`, and `authenticated` are revoked. A client cannot discover a case id by selecting. Helpers `verification_resolve_caller`, `verification_review_grant_matches`, and the predicate internals are revoked from `authenticated`.

`list_my_verification_status` is not a reviewer inbox. It reports the caller's own identity, ownership, and management.

## Security already enforced on a decision

These checks exist inside `037`. They do not create a queue.

- The reviewer account and person come from `auth.uid()`, then from `user_accounts`. The client cannot pass either id.
- `search_path` on the review functions is `pg_catalog, public`. They are `SECURITY DEFINER`.
- Direct table reads and writes by `authenticated` are revoked.
- Decision triggers reject update and delete. Insert rejects the subject, the claimant person, or the submitter account. Center affiliation is enforced in the review functions, not in the trigger.
- Two decisions on the same case or claim serialize with a transaction advisory lock. The state update matches only an open state. A lost race fails with the same `42501` text, `Verification request is not available`.
- A second current acceptance of the same person and market, or of the same effective ownership or assignment, fails closed. `expires_at` null means the acceptance is still current.
- `EXPIRED`, `REVOKED`, `WITHDRAWN`, `CONFLICT`, `SUPERSEDED`, and `DECLARED` or `DRAFT` are not decidable through these RPCs. There is no cancel or expiry RPC in this slice.
- Audit metadata stores outcome and reason code. It does not store storage paths or artifact contents.
- Evidence columns `provider_reference`, `storage_bucket`, and `storage_path` are not returned by any client RPC. There is no signed URL and no Storage policy for a reviewer.

## Why migration `039` is not proposed

A reviewer inbox needs two capabilities that do not exist: a grant the server can prove, and a caller-scoped read of the cases that grant allows. The read is necessary, but it is not fully backed while `REVIEWER-GRANT-AUTHORITY` is open. A list RPC written now would still have nobody it is allowed to serve, or it would treat `PLATFORM_IDENTITY` as a global reviewer. This train does not add `039`, does not edit `036`–`038`, and does not use `service_role` from Expo.

## DECISION_REQUIRED

### REVIEWER-GRANT-AUTHORITY

Pending decision: which operational authority may create, suspend, and end a `verification_review_grants` row, and which existing scope that row uses.

Why this train stops: the schema can store a reviewer, a scope, and a market, but no approved operation inserts a row. Without that row, the server cannot say which person may review which cases. Guessing a center role, `users.role`, or a platform-wide default would grant review authority the product has not named.

Safe options:

1. Keep grants writable only by a later controlled server operation. Name the operator outside Expo, outside `service_role` in the app, and outside center membership. Choose one existing scope for the first grant: `MARKET` plus `ES`, which matches both identity and equine rows in Spain, or a platform scope, which matches one domain in every market. Seed nothing in a migration. Start the reviewer screen only after that grant path exists and a later reviewed migration adds the read RPCs below.
2. Postpone the reviewer screen until that operator and scope are named. Leave `review_*` as server functions that a client cannot usefully call, because the client cannot learn a case id.
3. Do not add a client screen that asks a person to paste a case id into `review_identity_case`. That skips the missing queue and still does not authorize the caller.

Reversible recommendation: option 1, with no grant row created in this train. Do not choose `PLATFORM_IDENTITY` or `PLATFORM_EQUINE` as a silent default.

### REVIEWER-QUEUE-READ

Pending decision, only after the grant authority above is named: the minimum read a reviewer may see.

Why it is separate: even a person who already had a grant could not open a queue. `review_*` returns the decision echo only when the client already has the id.

A later contract, not this train, would need at least:

- actor resolution only through `verification_resolve_caller()`;
- rows limited by `verification_review_grant_matches` and by the same self-review and center-affiliation refusals as `review_*`;
- a list of open identity cases and, only if the grant scope includes them, open equine claims;
- a detail of state, market, claim type, and evidence category plus document country;
- no `storage_path`, `storage_bucket`, `provider_reference`, `note_text`, signed URL, biometric value, or another person's name;
- `SECURITY DEFINER`, `search_path = pg_catalog, public`, execute granted only to `authenticated`, helpers revoked;
- the same generic `42501` for an unknown id, a closed case, a lost race, and a missing grant.

That later migration is `SECURITY_REVIEW_REQUIRED` before implementation. It is not migration `039` in this train.

## Still open, unchanged

`REVIEWER-VISIBILITY`, `MINOR-IDENTITY-SUBMISSION`, `LEGAL-EVIDENCE-CATALOG`, `RETENTION-AND-EXPIRY`, `CONFLICT-RESOLUTION-AUTHORITY`, `GATE-PREDICATE`, `KYC-PROVIDER`, `FISCAL-GATE`, `PUBLIC-ACCESS`, and `LEGAL_AND_INSURANCE_REVIEW_REQUIRED`.

This train does not start KYC, facial recognition, document upload, biometric storage, fiscal identity, retention, or center corroboration. It does not start Stage 5.
