# Verification grant lifecycle — Stage 4B.2

**Status:** migration `039` is on `main` and deployed. The bootstrap has not been executed. Remote grants and grant events are both zero.
**Date:** 2026-10-08
**Base:** `origin/main` `78e9a699559f6be4409a25c39c109cc12d8167f4`.
**Remote:** project `efkauegdlmfkonzwyyiv` is normalized at exact version `039`.

This stage prepares the technical lifecycle for one fictional `MARKET` / `ES` review grant. It does not add a reviewer queue, a case detail, evidence access, a signed URL, an Edge Function, a reviewer screen, a KYC provider, or an acceptance of identity. Ordinary authenticated administration stays deferred. Real users stay blocked.

## Stage 0 inventory

No `ARCHITECTURE_CONFLICT`. The approved design said a database-owner action cannot be written through `audit_events`, because that writer requires `auth.uid()` and stores a product PERSON. Migration `039` does not forge that claim. It adds a separate event table.

What `036`–`038` already do:

- `verification_review_grants` is the current projection. Status was only `ACTIVE` or `ENDED`. An active row requires `valid_until` null. `ENDED` requires `valid_until`. There is no actor and no history.
- `verification_review_grant_matches` is true only for `ACTIVE`, `valid_from <= now()`, and either a platform scope for that domain or `MARKET` for that country. This migration does not replace it. `SUSPENDED` does not match because it is not `ACTIVE`.
- There is no unique open grant. Clients cannot read or write the table. `service_role` was not revoked on that table.
- `review_*` still decides an open case when the caller has a matching grant and is not the subject, the submitter, the named owner or manager, or an active member of the claimant center. A refusal raises `42501` and rolls back, so it does not write `audit_events`.
- `record_audit_event` overwrites the actor from `resolve_session_caller()`. A null `auth.uid()` is `42501`. Update and delete of `audit_events` are refused.
- Signup creates a distinct PERSON and ACCOUNT. `person_id` is unique. A center role is not a review grant.
- Version `039` was free. `036`–`038` are not edited.

## Projection

`verification_review_grants` remains the current row.

| Status | Effect |
| --- | --- |
| `ACTIVE` | The only status `verification_review_grant_matches` accepts. `valid_until` stays null. |
| `SUSPENDED` | Review stops immediately. `valid_until` stays null. This is not a close. |
| `ENDED` | Final. `valid_until` is set. The row is not deleted and is not reactivated. |

A partial unique index allows one `ACTIVE` or `SUSPENDED` row for the same person, scope, and market. A later grant after `ENDED` is a new row.

The pilot functions accept only `MARKET` / `ES`. `PLATFORM_IDENTITY` and `PLATFORM_EQUINE` remain valid projection values for the existing review tests. The bootstrap function cannot create them: it has no scope argument and writes `MARKET` / `ES` itself.

Allowed changes are `ACTIVE` → `SUSPENDED`, `ACTIVE` → `ENDED`, and `SUSPENDED` → `ENDED`. A trigger refuses every other status change, including `SUSPENDED` → `ACTIVE` and any change out of `ENDED`. The `CLOSED` event stores the real previous status, `ACTIVE` or `SUSPENDED`. Two concurrent suspend and close calls can leave one `CLOSED` event from `ACTIVE`, or a `SUSPENDED` event followed by `CLOSED` from `SUSPENDED`. The row ends `ENDED` either way. Reactivation is not implemented.

## Events

`verification_review_grant_events` is append-only. Update and delete raise `42501`. `PUBLIC`, `anon`, `authenticated`, `service_role`, and `supabase_admin` have no explicit table privilege. RLS is on and there is no client policy. A superuser still bypasses both privilege checks and RLS; that is the same provider trust boundary as the function grants.

A row stores the event, grant, recipient person, scope, market, previous status, new status, a stable reason code, and `occurred_at`.

The actor is exclusive:

- `TECHNICAL`: `technical_principal` is the PostgreSQL `session_user`. Account and person are null. This does not claim that `postgres`, the Dashboard, the CLI, or `service_role` is a product PERSON.
- `PRODUCT`: account and person are set, and the technical principal is null. Migration `039` does not write this shape. It is reserved for a later authenticated administrator. `(actor_account_id, actor_person_id)` references `user_accounts (id, person_id)` with `MATCH FULL`, using the unique key from migration `036`. A partial index covers rows that have an account. Unrelated account and person identifiers cannot be stored.

Implemented events are `GRANTED`, `SUSPENDED`, and `CLOSED`. Reasons are fixed by the function: `PILOT_BOOTSTRAP`, `PILOT_SUSPEND`, `PILOT_CLOSE`.

`ATTEMPT_REJECTED` and `ACCESS_REJECTED_AFTER_SUSPENSION` are not implemented. The current functions raise, and an insert in that same transaction would roll back with the error. Recording a refusal needs a later path that commits a safe result instead of raising. The provider's own Dashboard or CLI log remains the human access trail. This table does not invent it.

## Functions

The lifecycle functions and both enforcement triggers are `SECURITY INVOKER` with `search_path = pg_catalog, public`. Execute is revoked from `public`, `anon`, `authenticated`, `service_role`, and `supabase_admin`. Table privileges on the projection and the event table are revoked from those same roles. RLS is enabled and there is no client policy. The body of `verification_grant_technical_principal()` allows only `current_user` `postgres`, then returns `session_user`.

`supabase_admin` is not a grant operator. In local Supabase it is a superuser, so PostgreSQL still reports an implicit execute privilege that a migration cannot revoke. The local `postgres` session cannot assume that role. The function body rejects it whenever it is `current_user`. That remaining bypass is a provider trust boundary, not application authorization. `service_role` is not given an operational endpoint. Expo does not call these functions.

| Function | Argument | Effect |
| --- | --- | --- |
| `verification_grant_technical_principal()` | none | Resolves the technical principal or refuses. |
| `bootstrap_verification_review_grant(uuid)` | reviewer person only | One `ACTIVE` `MARKET` / `ES` grant and one `GRANTED` event, or `42501`. |
| `suspend_verification_review_grant(uuid)` | grant id only | `ACTIVE` → `SUSPENDED` and one event, or `42501`. |
| `close_verification_review_grant(uuid)` | grant id only | `ACTIVE` or `SUSPENDED` → `ENDED`, one `CLOSED` event with that previous status, or `42501`. |

Bootstrap requires an `ACTIVE` person and an `ACTIVE` account for that person. It locks the person and market, and the unique index is the backstop. It does not grant any further administrative ability. It was not executed against the remote database.

## Still deferred

- Reviewer queue, case detail, evidence, signed URLs, and the reviewer screen.
- Authenticated grant administration, separate from the reviewer.
- Reactivation of `SUSPENDED` or `ENDED`.
- Denial events.
- KYC, legal evidence, retention, and real users.
- Migration `040`.
- Any real or remote grant. Pilot data, when a later operation uses this function, must be fictional.
