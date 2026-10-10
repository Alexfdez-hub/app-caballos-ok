# Pilot reviewer smoke runbook — Stage 4B.4

**Status:** documentation only. This pull request does not create accounts, execute the bootstrap, insert grants, cases, or evidence, run remote SQL, or change Supabase.
**Date:** 2026-10-10
**Base:** `origin/main` `0df9baddc9eb8bf72938a584f5f2bfeab723aca4` (merge of PR #59).
**Remote starting state, recorded for this stage and not re-queried here:** project `efkauegdlmfkonzwyyiv` is healthy and normalized at exact version `040`. There are 0 reviewer grants, 0 grant events, and 0 `verification_review_opened` audit rows. No pilot reviewer account exists. Bugbot and Autofix stay off.

This runbook is the procedure for a later Android smoke of the read-only Spain review flow. It uses fictional data only. It does not authorize that smoke. Every remote or destructive step below is marked **AUTHORIZATION REQUIRED** and stays unexecuted until a later, explicit approval names that step.

The boundaries in `docs/VERIFICATION_REVIEWER_UI_STAGE4B.md`, `docs/VERIFICATION_REVIEWER_BOOTSTRAP_STAGE4B1.md`, `docs/VERIFICATION_GRANT_LIFECYCLE_STAGE4B2.md`, and `docs/VERIFICATION_REVIEWER_READ_UI_STAGE4B3.md` stay in force. Scope is `MARKET` / `ES` only. The mobile app has no superadministrator and never receives `service_role`. Migration `041` is not authorized. The screen does not call `review_*` and does not open a document.

## Fictional pilot

Two Auth users. Two PERSON rows. Signup already creates a distinct PERSON and ACCOUNT for each user, and `user_accounts.person_id` is unique, so the reviewer cannot be the applicant.

| Role | What it is | What it is not |
| --- | --- | --- |
| Reviewer | One dedicated fictional account. Display name example: `Revisor` / `Ficticio`. Adult date of birth, invented, such as `1990-06-15`. Country `ES`. | The applicant. A center member. The Product Owner's personal account. A stored email, UUID, password, or token. |
| Applicant | A second fictional account. Display name example: `Solicitante` / `Ficticio`. A different invented adult date, such as `1992-03-20`. Country `ES`. | The reviewer. A center member. A real rider or owner. |

One fictional equine, created by the applicant through the existing private create flow. Name example: `Caballo Ficticio 4B4`. No photograph.

Three open Spain cases, all submitted by the applicant and none by the reviewer:

| Case | How it can be created later | Subject seen by the reviewer |
| --- | --- | --- |
| Identity | Existing Android action on `Verificación`, which calls `submit_my_identity_case('ES')`. | The applicant's minimum name. |
| Ownership | No screen. A later authorized call, in the applicant session, of `submit_my_equine_ownership_claim` with owner type `PERSON`, market `ES`, the fictional equine, percentage `100`, and null center and effective-ownership ids. The function forces the owner PERSON to the caller. | The applicant and the fictional equine. |
| Management | No screen. A later authorized call, in the applicant session, of `submit_my_equine_management_claim` with manager type `PERSON`, market `ES`, role `PRIMARY_MANAGER`, the same equine, a `valid_from` not after `valid_until` when an end is set, and null center and effective-assignment ids. The function forces the manager PERSON to the caller. | The applicant and the fictional equine. |

A direct table insert is not the load path. It would skip `auth.uid()` and could make the reviewer the submitter. Forging `auth.uid()` in the SQL editor is refused by this runbook.

Evidence is referential and fictional. It is not a document, a photograph, a biometric sample, or a KYC result.

| Parent | Categories that make `evidence_sufficient` true | Shape required by `036` |
| --- | --- | --- |
| Identity case | `IDENTITY_PROVIDER_REFERENCE` | Opaque `provider_reference`, 1–200 characters. `storage_bucket`, `storage_path`, and `note_text` null. Example token: `FICTIONAL-PROVIDER-REF-4B4`. |
| Ownership claim | `EQUINE_IDENTIFIER_REFERENCE` and `OWNERSHIP_ARTIFACT` | `provider_reference` null. `note_text` null. The check requires a bucket and a path even though no object exists. |
| Management claim | `EQUINE_IDENTIFIER_REFERENCE` and `MANAGEMENT_DELEGATION_ARTIFACT` | Same file-shaped check. No object is uploaded. |

The file-shaped categories must not use a real bucket. The private buckets already created are `avatars`, `equine-media`, `qualification-documents`, `session-evidence`, and `assessment-documents`. A later fixture uses a bucket id that is not one of those, for example `pilot-fixture-not-a-bucket`, and a path that is only a label, for example `fictional/4b4/not-an-object`. No row is inserted into `storage.objects`. `document_country_code`, when set, is `ES`. Do not add `REVIEWER_NOTE`, `CENTER_CORROBORATION`, or `INSURANCE_REFERENCE` for this smoke. There is no client RPC that inserts `verification_evidence`. That insert is a later postgres write, not an app action.

Forbidden in the fixture and in Git: a real national identity number, passport, photograph, biometric template, personal email, personal UUID, password, token, vendor reference, or storage URL.

Addresses for the two accounts are chosen at operation time, written only in a private operator notebook, and never committed. They are not the Product Owner's personal address. This document stores no example address.

## Procedure

Stop at any step whose result does not match the checklist. Do not continue into the next **AUTHORIZATION REQUIRED** step to "fix" a mismatch.

### 1. Create the fictional accounts

**AUTHORIZATION REQUIRED.** Not done in this pull request.

Use the normal Auth signup in the Android app, twice. Confirm the email through the product's existing confirmation flow. Do not create the users in the Supabase Dashboard, and do not insert `auth.users`.

Expected: two distinct sessions. Neither profile shows `Revisión piloto`.

### 2. Complete Spain onboarding

**AUTHORIZATION REQUIRED** only because it writes the new accounts. The screen already exists.

On `Completa tu perfil`, for each account, save a fictional given name, a fictional family name, an invented past adult date of birth, and country `ES` chosen from the list. Do not leave the country empty and do not type a country that is not offered.

Expected: both PERSON and ACCOUNT rows can later be read as `ACTIVE`. The identity screen accepts the explicit country. Neither account is a center member.

### 3. Identify the reviewer PERSON

**AUTHORIZATION REQUIRED.** Read-only. Run only as a database read after the accounts exist. Type the reviewer address in the session. Do not paste it into Git, a pull request, or a workflow log.

```sql
select person.id as reviewer_person_id,
       person.status as person_status,
       account.id as account_id,
       account.status as account_status
  from auth.users as auth_user
  join public.user_accounts as account
    on account.auth_user_id = auth_user.id
  join public.persons as person
    on person.id = account.person_id
 where auth_user.email = '<reviewer-address-typed-at-runtime>';
```

Repeat the same shape for the applicant. Expected: two different `reviewer_person_id` values, both persons `ACTIVE`, both accounts `ACTIVE`, and the fictional names already saved. If either row is missing or not `ACTIVE`, stop. `bootstrap_verification_review_grant` returns `42501` for that target.

Copy the reviewer person id into the private notebook. The bootstrap argument is that id and nothing else. The function has no scope argument. It writes `MARKET` / `ES` itself.

### 4. Bootstrap once

**AUTHORIZATION REQUIRED.** Remote write. One execution.

Run outside Expo, as `current_user` `postgres`. `supabase_admin` is not an operator. `service_role` is not an operator. Do not call this from the app.

```sql
select public.bootstrap_verification_review_grant(
  '<reviewer-person-id-from-step-3>'::uuid
);
```

Expected: one uuid, the grant id. Store it in the private notebook. A second call for the same person, while that grant is `ACTIVE` or `SUSPENDED`, raises `42501` with `Verification grant operation is not available`. That refusal is the proof the bootstrap is not a retry.

### 5. Verify `GRANTED`

**AUTHORIZATION REQUIRED.** Read-only, immediately after step 4.

```sql
select count(*) as grant_rows
  from public.verification_review_grants;

select id, reviewer_person_id, scope_type, market_country_code,
       status, valid_until
  from public.verification_review_grants;

select event_type, reviewer_person_id, scope_type, market_country_code,
       previous_status, new_status, actor_kind, technical_principal,
       reason_code
  from public.verification_review_grant_events;
```

Expected: exactly one grant, `ACTIVE`, `MARKET`, `ES`, `valid_until` null, reviewer person equal to the id from step 3. Exactly one event, `GRANTED`, previous status null, new status `ACTIVE`, actor kind `TECHNICAL`, reason `PILOT_BOOTSTRAP`, technical principal `postgres`, account and person actor columns null. No `PLATFORM_IDENTITY` or `PLATFORM_EQUINE` row.

### 6. Load the fictional cases

**AUTHORIZATION REQUIRED.** Three different write paths.

1. As the applicant on Android, open `Verificación` and submit the Spain identity request. Expected local notice: the request was sent and the identity is not verified. The case state is `SUBMITTED`.
2. As the applicant, create the fictional equine and do not add a photo. Then, still as the applicant session, call `submit_my_equine_ownership_claim` and `submit_my_equine_management_claim` with the arguments in the table above. There is no screen for those two calls. A postgres insert into the claim tables is not a substitute.
3. Evidence, only if the smoke must show the sufficient indicator: one later postgres insert per required category, using the fictional tokens above, parented to the case the applicant just created. Do not upload an object. Do not use a real bucket. The queue and the detail still work with no evidence; the indicator then stays false and the copy is `La evidencia todavía no es suficiente para continuar.`

Expected after the three cases exist: the applicant's own verification screen shows the identity request as pending. It does not show the reviewer.

### 7. Android read-only smoke

**AUTHORIZATION REQUIRED.** No decision and no document.

Sign in as the reviewer on Android. Profile shows `Revisión piloto` only when capabilities are exactly one `MARKET` / `ES` row. Open it.

| Check | Expected |
| --- | --- |
| Header | `Revisión piloto`. Subtitle says the reading is authorized for Spain and does not decide or open documents. |
| Queue | Up to the three fictional rows. Labels `Identidad`, `Propiedad`, `Gestión`. State `Enviada`. Market `España`. No applicant email, no document, no path. |
| Detail | Minimum fictional name, and for the equine claims the fictional equine name. Evidence categories only, with country `ES` when it was stored. |
| Evidence copy | Incomplete copy when a required category is absent. When the minimum categories are present: `Hay evidencia de las categorías mínimas, pero la decisión sigue bloqueada.` |
| Decision | `La decisión queda bloqueada. Esta lectura no autoriza una aceptación ni un rechazo. Esa acción llegará solo cuando una revisión posterior compruebe la evidencia.` No `Aceptar` and no `Rechazar`. |
| Other account | The applicant does not see `Revisión piloto`. After switching accounts without killing the process, the reviewer queue and detail are gone before the applicant's own empty or unauthorized state. |

Opening writes `audit_events`. Confirm with a read-only count, not by selecting metadata that is not needed:

```sql
select entity_type, count(*)
  from public.audit_events
 where event_type = 'verification_review_opened'
 group by entity_type;
```

Expected entity types, one per opened case: `identity_verification_case`, `equine_ownership_claim`, `equine_management_authority_claim`. Metadata on those rows is only `case_type`, `market_country_code`, and `state`. A denied open raises `42501` and adds no row.

### 8. Suspend and confirm revocation

**AUTHORIZATION REQUIRED.** Remote write, then Android.

```sql
select public.suspend_verification_review_grant(
  '<grant-id-from-step-4>'::uuid
);
```

Expected: the grant is `SUSPENDED`, `valid_until` still null. A new event `SUSPENDED`, previous `ACTIVE`, new `SUSPENDED`, reason `PILOT_SUSPEND`, actor `TECHNICAL`. The previous `GRANTED` row is still there.

On the reviewer's next focus, capabilities return no row, so `Revisión piloto` disappears. If the screen was already open with access, it shows `Acceso cerrado` and drops the queue and detail. Queue and detail calls raise `42501`. The opened-audit count does not grow. `SUSPENDED` does not return to `ACTIVE`. Do not try to reactivate it.

### 9. Close the grant

**AUTHORIZATION REQUIRED.** Remote write.

```sql
select public.close_verification_review_grant(
  '<grant-id-from-step-4>'::uuid
);
```

Expected: status `ENDED`, `valid_until` set. A new event `CLOSED`, previous `SUSPENDED`, new `ENDED`, reason `PILOT_CLOSE`. Three events remain: `GRANTED`, `SUSPENDED`, `CLOSED`. A later close or suspend of this same id raises `42501`. A later grant would be a new bootstrap and a new row. This runbook does not do that second bootstrap.

### 10. Isolate the fixture

Default policy: leave the fictional rows in place and keep them unreachable.

- The closed grant no longer matches, so the reviewer queue and detail stay denied.
- Do not `DELETE` or `UPDATE` `audit_events`.
- Do not `DELETE` or `UPDATE` `verification_review_grant_events`.
- Do not `DELETE` `verification_review_grants`. Closure is the hide path. Deleting the row would hide the history the event table points at.
- Do not delete the fictional Auth users, PERSON rows, or ACCOUNT rows in this procedure. `audit_events.actor_person_id` has no foreign key, so a later delete would not erase the audit, but it is still a separate destructive operation.
- Do not delete Storage objects. This procedure creates none.
- The private notebook keeps the two addresses, the two person ids, the equine id, the three case ids, and the grant id. Git does not.

A later cleanup that removes the fictional cases, the fictional evidence rows, or the Auth users needs its own authorization. It still may not delete or rewrite audit rows or grant events. Case deletion is not required for the smoke to be over.

## Rollback

| Mistake | Recovery | Do not |
| --- | --- | --- |
| Bootstrap targeted the wrong ACTIVE person | Suspend that grant, then close it. Confirm the three events. Tell the wrong account's user. | Delete the grant or the `GRANTED` event. |
| Second bootstrap attempted | Expect `42501` while the first grant is `ACTIVE` or `SUSPENDED`. | Insert a grant by hand. |
| Evidence used a real bucket or a real path | Stop. Do not sign a URL. A later authorized correction may insert nothing further. Do not put the path in Git or in the pull request. | Upload a file to make the path "valid". |
| Reviewer can see their own case | The accounts were not distinct, or the reviewer submitted the case. Close the grant. Discard the smoke. | Call `review_*` to close the case. |
| Open audit row looks wrong | Leave it. A refusal does not write a compensating delete. | Update metadata or delete the event. |

There is no down migration. `039` and `040` stay applied.

## Checklist

| Step | Result | Read that proves it |
| --- | --- | --- |
| Before any write | Remote version `040`. Grants 0. Grant events 0. Opened audits 0. | `schema_migrations` max version. Counts below. |
| Accounts | Two ACTIVE persons, two ACTIVE accounts, different ids, country `ES`. | Step 3 select, run twice. |
| Bootstrap | One `ACTIVE` `MARKET` / `ES` grant. | Step 5 selects. |
| `GRANTED` | One event, `PILOT_BOOTSTRAP`, actor `TECHNICAL`. | Step 5 event select. |
| Cases | Identity from the app. Ownership and management only through the applicant RPCs. | Applicant session returns the new ids. Reviewer queue lists them after the grant exists. |
| Evidence | Fictional tokens only, or no evidence rows. | Detail shows categories, never a path or a provider reference. |
| Smoke | Queue and detail match the Android table. No decision control. | Screen. Opened-audit group by `entity_type`. |
| Suspend | `SUSPENDED`. Menu hidden. Open count unchanged. | Grant select. Event `PILOT_SUSPEND`. Audit count. |
| Close | `ENDED`. Previous status on the event is `SUSPENDED`. | Event `PILOT_CLOSE`. |
| Isolation | History still has the grant, three events, and every open audit. | Same counts, not zero. |

Starting and ending counts:

```sql
select max(version) as schema_version
  from supabase_migrations.schema_migrations;

select
  (select count(*) from public.verification_review_grants) as grants,
  (select count(*) from public.verification_review_grant_events) as grant_events,
  (select count(*)
     from public.audit_events
    where event_type = 'verification_review_opened') as opened_audits;
```

Before the smoke, the three counts are 0. After a completed smoke that opened all three cases and then closed the grant, the counts are 1 grant, 3 grant events, and 3 opened audits. They do not return to 0.

## Operations that still need a later authorization

This document does not approve any of them.

| Operation | Where | Why it is separate |
| --- | --- | --- |
| Two Auth signups | Android Auth | Creates remote users. |
| Spain onboarding for those users | Android identity screen | Writes PERSON fields. |
| Read that resolves person id from an address | Remote SQL, `postgres` or a reviewed read role | Touches `auth.users`. The address must not be logged. |
| `bootstrap_verification_review_grant` once | Remote SQL as `postgres` | Creates the only pilot grant. |
| `submit_my_equine_ownership_claim` and `submit_my_equine_management_claim` | Applicant session | No screen. Must not be a table insert or a forged `auth.uid()`. |
| `verification_evidence` inserts | Remote SQL as `postgres` | No client RPC. Must not create a Storage object. |
| Android smoke as the reviewer | Device | Reads private fictional detail and writes open audits. |
| `suspend_verification_review_grant` | Remote SQL as `postgres` | Stops the grant. |
| `close_verification_review_grant` | Remote SQL as `postgres` | Ends the grant. |
| Any delete of users, persons, cases, evidence, grants, grant events, or audit | Remote | Out of this runbook. Audit and grant events are append-only. |

Not authorized here: migration `041`, a decision button, `review_*` from the client, a signed evidence URL, an Edge Function, ordinary grant administration, KYC, a real document, remote bootstrap, and any change to migrations `036`–`040`.
