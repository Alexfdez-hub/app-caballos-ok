# Equine creation and equine-media proposal

Issue #35 Stage 3. Documentation only. This is a recommendation for the
next train. It is not an accepted Product Owner decision, and it is not
implemented.

`avatars` and `equine-media` stay private deny-by-default buckets with
no client Storage policies, as frozen by
`docs/ARCHITECTURE_CONFLICT_027_STORAGE_VISIBILITY.md` and migration
`027_storage_policies.sql`. `equines.visibility_status = PUBLIC` remains
stored publication intent only. It does not grant SELECT, a public URL,
or an upload right.

Do not merge this proposal into an implementation. Do not deploy. Do not
open the buckets. Do not add equine-create or equine-media RPCs until
the Product Owner accepts a single option below.

## What is already frozen

- PERSON ≠ ACCOUNT. Paths and policies must not use `auth.uid()` as a
  domain identity.
- OWNERSHIP ≠ MANAGEMENT. An owner is not automatically a manager, and
  a manager is not automatically an owner. The create transaction below
  writes both rows on purpose; it does not collapse the two concepts.
- CENTER MEMBERSHIP ≠ EQUINE PERMISSION. `ADMIN` / `MANAGER` /
  `INSTRUCTOR` / `ASSESSOR` do not create an equine or a media object.
- A minor may have no account. A verified guardian relationship is not
  equine authority.
- `equines` has no `owner_id`, `manager_id`, or `center_id`.
- Ownership and management are PERSON or CENTER, never both on one row.
- At most one stored `ACTIVE` `PRIMARY_MANAGER` per equine.
- `equine_media.storage_path` is unique metadata. It is not proof that a
  Storage object exists, and it is not a public URL.
- `equine_media.media_type` is `PHOTO` only. Video is not in this
  proposal.
- RLS stays enabled. Clients do not receive table grants.
- `now()` is not used in a table CHECK.
- Audit uses existing `audit_events` (`actor_account_id`,
  `actor_person_id`, `event_type`, `entity_type`, `entity_id`,
  `metadata`, `occurred_at`). No second audit log.

## Unresolved choice

Architecture 2.1 does not name who may create an equine, who the first
owner and `PRIMARY_MANAGER` are, or whether equine-media is a public
URL, a client Storage policy, or a server-issued signed URL. Phase 3F
left provisioning outside Expo for that reason. Phase 14A kept
`equine-media` private for the same reason.

The options below are the decision. Until one is accepted, the next
train must not implement any of them.

## Options

### A. Adult self-create, private signed URLs (recommended)

An authenticated adult whose PERSON resolves may create one equine for
themselves. The same transaction inserts PERSON ownership at 100 percent
and a PERSON `PRIMARY_MANAGER` for that same PERSON. Media stays in the
private bucket. The server issues a short-lived signed URL for one exact
object path. There is no client Storage policy and no public object.

### B. Center staff create

A Center `ADMIN` or `MANAGER` may create a CENTER-owned equine and a
CENTER `PRIMARY_MANAGER` for a center where they have an active
membership. This treats membership as equine authority. That contradicts
CENTER MEMBERSHIP ≠ EQUINE PERMISSION unless the Product Owner explicitly
adds a new equine-create permission. Not recommended.

### C. Guardian creates for a minor

A verified guardian may create an equine whose owner PERSON is the
minor. The minor may have no account. This invents guardian equine
authority from a relationship that today only supports consent and
booking. Not recommended for the first slice.

### D. Public equine-media for `visibility_status = PUBLIC`

Published photos become public URLs. Architecture 2.1 allows published
media to be public by design, but 011 says `PUBLIC` is intent only and
does not grant Storage read. A public bucket also exposes every object
whose path can be guessed, including photos uploaded before publication.
Not recommended until a separate publication decision names which rows
are publishable and how an unpublished object is removed from public
read.

### E. Client Storage RLS on `equine-media/{equine_id}/...`

Authenticated clients insert and select objects directly. Policies must
re-check effective `PRIMARY_MANAGER` and reject prefix substitution.
Upsert needs SELECT and UPDATE as well as INSERT. This is the pattern
027 used for the frozen document buckets, but equine-media write
authority is not frozen, and a mistaken policy is a direct object leak.
Signed URLs keep the secret and the authority check on the server.

## Recommendation

Accept option A only. Keep B, C, and D out of the first implementation.
Keep the bucket private even after acceptance. Record the acceptance in
the decision log before any migration.

Security tradeoff: signed URLs require a server-held signing secret and
a short TTL. They avoid a client policy that could be wider than the
RPC. They do not make the object public. A leaked URL expires. The
metadata row remains the authority record; the URL is not a grant that
outlives the manager assignment if the server refuses to sign again
after the assignment ends.

## Recommended rules, if A is accepted

### Who may create an equine

`create_my_equine` is executable by `authenticated` only.

The caller ACCOUNT must resolve to a PERSON. If it does not, the RPC
raises the existing identity error and writes nothing.

The caller PERSON must be an adult in the market used for the equine's
recorded country. MVP0 has no country on `equines`. Do not invent one.
The adult check uses the caller's own account market only if a single
market is already stored for that person. If no market is stored, the
RPC refuses creation rather than assuming age 18. That refusal is
intentional: a missing market is not a license to guess.

The creator is the only client who may establish the first rows:

- `equines`: `status = ACTIVE`, `visibility_status = PRIVATE`,
  `equine_type` `HORSE` or `PONY`, trimmed non-empty `name`, and the
  optional columns that 011 already allows.
- `equine_ownerships`: `owner_type = PERSON`, `owner_person_id` = caller
  PERSON, `ownership_percentage = 100`, `status = ACTIVE`, `ended_at`
  null, `started_at` set inside the function to the same timestamp as
  the management row. Not a table CHECK on `now()`.
- `equine_management_assignments`: `manager_type = PERSON`,
  `manager_person_id` = caller PERSON, `management_role =
  PRIMARY_MANAGER`, `status = ACTIVE`, `valid_until` null,
  `granted_by_person_id` = caller PERSON, `valid_from` equal to
  `started_at`.

No center assignment, center permission, availability rule, or media row
is created. Additional owners, co-managers, and percentage splits are a
later train. Shares are not forced to sum to 100, matching 012.

### Atomic ownership and PRIMARY_MANAGER

One SECURITY DEFINER function, `search_path = pg_catalog, public`,
revoked from PUBLIC and `anon`, granted to `authenticated` only. It does
not accept a person id, account id, center id, or manager id.

Order inside the function:

1. Resolve caller account and person from `auth.uid()`.
2. Refuse when the adult-market check cannot be made.
3. Insert the equine.
4. Insert the ownership row.
5. Insert the `PRIMARY_MANAGER` row.
6. Insert one `audit_events` row: `event_type = equine_created`,
   `entity_type = equines`, `entity_id` = equine id, actor account and
   person set, metadata limited to equine type and visibility
   `PRIVATE`. No name of another person.
7. Return the equine id.

Any failure rolls the whole function back. There must be no path that
leaves an equine without its initial PERSON owner and PERSON
`PRIMARY_MANAGER`. Direct INSERT by `authenticated` stays revoked.

### Adult, minor, and center-managed cases

| Case | First slice under option A |
|---|---|
| Adult with an account and a resolvable market | May call `create_my_equine`. Becomes PERSON owner and PERSON `PRIMARY_MANAGER`. |
| Adult with no market on record | Refused. No row. |
| Minor with no account | Cannot call the RPC. A guardian does not call it for them. |
| Verified guardian | May not create or upload for the minor. Consent is not equine authority. |
| Center membership | Does not create. CENTER ownership and CENTER `PRIMARY_MANAGER` stay server-side provisioning, as they are today. |
| Existing server-provisioned equine | Unchanged. No backfill that guesses an owner. |

If the product later needs a center-owned school horse or a minor-owned
horse, that is a new Product Owner decision (option B or C), not a
branch of this RPC.

### Who may upload, read, or delete media

Only the caller PERSON who is the currently effective PERSON
`PRIMARY_MANAGER` (`status = ACTIVE`, `valid_until` null, `valid_from`
at or before the function timestamp, `manager_type = PERSON`).

Not enough: ownership alone, `CO_MANAGER`, `AUTHORIZED_MANAGER`, a
CENTER manager row, center membership, `VIEW_ACTIVITY`, a verified
guardian, or `visibility_status = PUBLIC`.

Read, upload, replace, and retire use that same subject. There is no
broader read for "any authenticated user" and no public read.

### Private object path

Bucket: `equine-media` (existing, `public = false`).

Object name:

```text
{equine_id}/{media_id}
```

Both segments are the domain UUIDs from `equines.id` and
`equine_media.id`. No `auth.uid()`, no person id, no original filename,
no extra prefix. `storage_object_name_is_safe` must accept the name.
`equine_media.storage_path` stores that exact name and nothing else.

The server inserts the `equine_media` row first, with `media_type =
PHOTO`, `is_primary` chosen by the caller only when no other primary
exists, then signs the URL for that path. A client-supplied path is
rejected.

### Signed URLs, not client policies

Do not add INSERT, SELECT, UPDATE, or DELETE policies on
`storage.objects` for `equine-media`. Do not set the bucket `public`.

Proposed RPCs, all `SECURITY DEFINER`, fixed `search_path`, execute
granted to `authenticated` only, no person-id argument:

| RPC | Effect |
|---|---|
| `create_my_equine(...)` | Equine + 100 percent PERSON ownership + PERSON `PRIMARY_MANAGER` + audit. Returns equine id. |
| `prepare_my_equine_photo(equine_id, is_primary)` | Checks effective PERSON `PRIMARY_MANAGER`. Inserts `equine_media`. Returns `media_id` and a short-lived signed upload URL for `{equine_id}/{media_id}` only. |
| `finalize_my_equine_photo(media_id)` | Same manager check. Server confirms the object exists at that path. If it does not, the metadata row is removed in the same transaction and the audit records `equine_photo_abandoned`. |
| `list_my_equine_photos(equine_id)` | Same manager check. Returns metadata for that equine only: id, storage path, sort order, is_primary, created_at. No signed URL in the list. |
| `sign_my_equine_photo_read(media_id)` | Same manager check. Returns one short-lived signed read URL. Refuses when the manager assignment is no longer effective. |
| `retire_my_equine_photo(media_id)` | Same manager check. See lifecycle. |

Signing uses the server Storage secret. Expo does not receive
`service_role`. The TTL is a Product Owner parameter. This proposal does
not pick a number. MIME type and byte size are also Product Owner
parameters. This proposal does not invent them. Until they are named,
`prepare_my_equine_photo` should not be implemented.

`list_my_equine_ownerships` and `list_my_equine_management_assignments`
stay as they are. They do not grow media columns.

### Lifecycle, replacement, deletion, audit, orphans

`equine_media` has no status column. Do not overload `is_primary` as a
delete flag.

Proposed column, only if option A is accepted: `retired_at timestamptz`
null while the photo is current. `now()` is not used in a CHECK.
`retired_at` set means the row is historical. A partial unique primary
index must ignore retired rows so a new primary can exist. That index
change is part of the same migration as the column.

Replacement: call `prepare_my_equine_photo` again. The previous row stays
with `is_primary = false` until `retire_my_equine_photo`. Two current
photos are allowed. One primary is still the maximum.

`retire_my_equine_photo`:

1. Manager check.
2. Set `retired_at` and clear `is_primary`.
3. Audit `equine_photo_retired` with equine id and media id. No bytes
   and no URL.
4. Delete the Storage object from the server.
5. If the object delete fails, keep the retired metadata and audit
   `equine_photo_delete_pending`. A server-only retry deletes the object
   later. The client cannot call that retry.

Orphans:

- An object in `equine-media` with no `equine_media` row is a server
  reconciliation finding. Clients cannot list the bucket.
- A current metadata row whose object is missing is returned by
  `list_my_equine_photos` with no signed URL, and `finalize` is the only
  client repair. `sign_my_equine_photo_read` fails closed when the object
  is absent.
- Retiring an equine (`ARCHIVED` or `DECEASED`) does not by itself delete
  photos. A later train can retire them. This slice does not cascade.

### Tests the next train should add

SQL, one transaction, then ROLLBACK:

- Adult creator receives one equine, one 100 percent PERSON ownership,
  and one PERSON `PRIMARY_MANAGER`, and one `equine_created` audit row.
- A second adult, a center manager, and a verified guardian of a minor
  cannot create for someone else and cannot prepare a photo.
- A minor person id cannot be passed in. The RPC has no such argument.
- `authenticated` still cannot `SELECT` `equines` or `equine_media`.
- `anon` and PUBLIC cannot execute the new functions.
- `storage.buckets.public` is false for `equine-media`.
- No `storage.objects` policy names `equine-media`.
- A path containing `auth.uid()`, `..`, or an extra segment is rejected.
- After `retire`, a new signed read is refused.
- Direct INSERT of `equines` by `authenticated` still fails.

App, TypeScript, no network:

- Parser fails closed on an unexpected photo row.
- User-facing errors do not echo database text.
- Empty, loading, and error states do not fabricate an equine card.

### UI flow, only after acceptance

Screen → hook → domain service → `supabase.rpc`. No role selector. No
direct table read. No Storage client upload that bypasses the signed URL.

Proposed screens, not built here:

1. Profile → Mis equinos keeps the current ownership list.
2. A create action calls `create_my_equine` and returns to that list.
3. Equine detail for a row the caller manages shows photos from
   `list_my_equine_photos`, with refresh, empty, and error states.
4. Add photo calls `prepare_my_equine_photo`, uploads bytes only to the
   returned URL, then calls `finalize_my_equine_photo`.
5. Remove calls `retire_my_equine_photo`.

Android behavior of the current tabs stays as it is until that UI is
accepted. This document does not change `ActivityScreen` or the equine
list screens.

## What this document does not do

- No migration `031`.
- No RPC, RLS policy, Storage policy, or UI.
- No change to bucket privacy.
- No public directory.
- No guardian or center create path.
- No merge and no remote deploy.
