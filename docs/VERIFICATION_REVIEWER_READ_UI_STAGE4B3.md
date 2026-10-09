# Verification reviewer read UI — Stage 4B.3

**Status:** migration `040` exists only on this branch. It is not deployed. No remote bootstrap has been executed. No reviewer account and no grant exist.
**Date:** 2026-10-09
**Base:** `origin/main` `eeb6d9c121a3aec2406bec215b3c297d95dfe4e5`.
**Remote:** project `efkauegdlmfkonzwyyiv` is normalized at exact version `039`. That deployment has 0 grants and 0 grant events. This stage does not change the remote project.

## Stage 0

No `ARCHITECTURE_CONFLICT`. Opening a case is an authenticated reviewer action. `record_audit_event` already resolves the ACCOUNT and PERSON from `auth.uid()` and overwrites the actor. The reviewer session has that identity, so the existing audit table can record the opening. Metadata is only `case_type`, `market_country_code`, and `state`. A refusal still raises `42501` and rolls back, which is the same behavior as `review_*`. This stage does not invent a PERSON and does not add a parallel audit table.

`039` is deployed. Its technical bootstrap has not been run. Version `040` was free. Migrations `036`–`039` are not edited.

## Read contract

All three functions are `SECURITY DEFINER` with `search_path = pg_catalog, public`. Execute is granted only to `authenticated`. `PUBLIC`, `anon`, and `service_role` are revoked. They read `auth.uid()` through `verification_resolve_caller()`. They do not accept an account, a person, a scope, or a market.

| Function | Arguments | Result |
| --- | --- | --- |
| `get_my_review_capabilities()` | none | One row `scope_type = MARKET`, `market_country_code = ES` when that grant is `ACTIVE` and current. No row when it is absent, suspended, or closed. No case data and no private identifiers. |
| `list_my_review_queue()` | none | At most 50 open `ES` rows in `SUBMITTED`, `IN_REVIEW`, or `RESUBMITTED`, ordered by `updated_at` descending, then case type, then id. Columns: `case_id`, `case_type` (`IDENTITY`, `OWNERSHIP`, `MANAGEMENT`), `market_country_code`, `state`, `updated_at`, `evidence_categories`. Missing grant is `42501`. |
| `get_my_review_case(text, uuid)` | case type and opaque id | One re-authorized row, or the same `42501` for an unknown id, a wrong type, a closed case, another market, a missing grant, and a conflict. |

The queue and the detail use the same exclusions as `review_*`: the caller is not the subject, the submitter, the named owner or manager, or an active member of the claimant center. A platform grant is not a Spain-pilot capability. A center role does not grant review.

The detail adds the minimum subject name, and for equine claims the equine id, equine name, relation type, and relation role. Evidence is only `category` and `document_country_code`. `evidence_sufficient` follows the Spain-first categories already named in the design: an identity provider reference, or an equine identifier reference plus the ownership or management artifact. That flag does not accept the case.

A current grant is locked with the same advisory lock `392` used by suspend and close. If suspension wins the lock, the read fails closed and writes no audit row.

## What this stage does not do

The screen has no accept or reject action and does not call `review_*`. It does not write evidence, mint a signed URL, or show a storage path, a provider reference, a note, or a document. The decision remains blocked even when the evidence indicator is true.

Ordinary grant administration, evidence access, and migration `041` stay unauthorized.
