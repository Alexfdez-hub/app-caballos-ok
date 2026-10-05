# Verification predicates — Stage 3

Inventory taken from `main` `a862fd52222ce5a436c72746372b47c13afe3526`, which contains migrations `036` and `037`. Remote project `efkauegdlmfkonzwyyiv` is normalized at exact version `037`. This branch adds unreleased `038` only. It does not deploy it.

## How a decision is current

The latest relevant decision is the one with the greatest `decided_at`, then `id`. It is current only when its outcome is `ACCEPTED` and `expires_at` is null or later than the queried instant. A later `REJECTED`, `REVOKED`, `EXPIRED` or `SUPERSEDED` outcome means the subject is not verified. No retention interval is chosen here.

Identity is keyed by subject PERSON plus `market_country_code`. Ownership is keyed by `equine_ownerships.id`. Management is keyed by `equine_management_assignments.id`. The effective row must still be `ACTIVE`, current at the queried instant, and equal to the accepted claim on equine, party, percentage or role, and validity window. The predicates do not update those rows.

## Center corroboration

Deferred. Migration `036` records only `submitted_by_account_id` on evidence. It does not identify the attesting center, an authorized representative, or an authority snapshot. A `CENTER_CORROBORATION` label is therefore not a trust fact in `038`. A later slice needs its own product decision before it can add that schema. This migration does not invent it.

## Who can read

Internal predicates accept a server-supplied subject id because a future gate may evaluate someone other than the caller. They are not executable by `PUBLIC`, `anon` or `authenticated`. `list_my_verification_status()` resolves PERSON from `auth.uid()` and returns only that caller's codes: `VERIFIED` or `NOT_VERIFIED`, for identity, ownership and management. It omits reviewer identity, notes, evidence paths and other people.

These predicates are not called by publication, services, bookings, payments or the calendar. `GATE-PREDICATE` stays open.

No `ARCHITECTURE_CONFLICT` was found. The frozen split between PERSON and ACCOUNT, ownership and management, and effective rows versus review decisions stays intact.
