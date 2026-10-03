# Pilot journey runbook

Local and CI only. The journey provisions a fictitious market `QX`,
runs the existing RPCs, asserts the critical path and negatives, then
`ROLLBACK`s. It does not write the remote project
`efkauegdlmfkonzwyyiv`.

## Command

```text
npm run pilot:journey
```

`npm run test:pilot` is the same command. Quality Gate runs it as part
of `npm run test:sql`.

The runner refuses a Supabase URL or database URL whose host is not
local, and it refuses any environment value that contains `supabase.co`
or `service_role`. It never prints connection strings.

## What you need

A local Supabase database already started the same way the other SQL
suites expect (`npx supabase start`, then the scripts find the DB
container or `supabase status`). This repository does not install OS
packages and does not start remote services.

If Docker or the local stack is absent, record that and use the
GitHub Quality Gate. Do not point this command at production.

## What the transaction covers

Fictitious people and deterministic ids in
`03100000-0000-4000-8000-*`:

- adult rider account
- minor rider with no account, verified guardian and valid consent
- a second minor with a verified guardian and no consent
- a third minor whose consent is granted and then revoked through RPCs
- an unrelated intruder account
- one center with manager, instructor and assessor
- one horse and one pony
- person ownership and `PRIMARY_MANAGER`, center `SCHOOL` assignment,
  and explicit center permissions
- discipline `PILOT-RIDE` and qualification system `PILOT-QS` (not a
  Galope catalog and not an international equivalence)
- a center assessment, equine requirements and an `EQUINE_SESSION` service
- versioned `QX` policies, with an obsolete version and one current
  version, plus acceptances
- availability rules distinct from the booking occupancy block
- adult booking request, eligibility, manager confirmation
- Zero Session approval, then a separate `ZERO_SESSION` authorization
- session permit, start, equine activity, incident, completion, review
- audit rows for those committed transitions
- negatives: intruder and instructor access, self-confirm, missing
  consent, revoked consent, overlapping confirm

Market `QX` uses adult age `18` only as fixture data. It is not a
Spanish legal rule and not a production market setting.

`approve_zero_session` does not create an authorization. The fixture
inserts that row only after the approved result, as server-side
provisioning. There is still no client authorization RPC.

## Rollback

The SQL file is one transaction and its final statement is `ROLLBACK`.
The runner rejects any `COMMIT;` and rejects a file whose last SQL
statement is not `ROLLBACK;`. Availability, booking, and session times
are offsets from one UTC day boundary 30 days ahead of
`clock_timestamp()`, and the fixture asserts that anchor is in the
future. Dates of birth and policy-version labels stay fixed. Availability
rules and calendar blocks cannot be deleted by clients; do not try to
clean this fixture by deleting those rows in a committed database. Reset
the local database if a transaction is ever committed by hand.

## Not in this command

- Expo UI and the Activity screen
- remote deployment
- equine creation
- `equine-media` upload or read
- deployment of migrations `031` and `032`
- deployment of the equine-photo Edge Functions

## Android equine and photo smoke

This section is manual. `npm run pilot:journey` does not run it. Stage
034 does not deploy migrations or Edge Functions, so this smoke is not
claimed as passed here. Record it as not run until a later authorized
deploy of migrations `031` and `032` and of these undeployed functions:
`prepare-my-equine-photo`, `finalize-my-equine-photo`,
`sign-my-equine-photo-read`, and `retire-my-equine-photo`.

Do not point the smoke at production before that deploy. Do not open
`equine-media`. Do not add a client Storage policy. Do not use
`service_role` in the app. The bucket stays private. Signed read URLs
last 300 seconds. Upload URLs use Storage platform validity.

Use two adult accounts that already have identity and a resolvable
market, plus one center member and one guardian who are not the adult
primary manager. No role selector is part of the app.

1. Adult A signs in and opens Mis equinos. The list comes from
   `list_my_equines`. An empty account shows the empty state, not a
   fabricated equine.
2. Adult A creates one fictitious equine with a name and type horse or
   pony. The app calls `create_my_equine` only. There is no center,
   guardian, or minor create path.
3. The new equine appears for Adult A. Open its detail. Detail comes
   from `get_my_equine`. Photos come from `list_my_equine_photos`.
4. Choose a JPEG, PNG, or WebP of at most 8 MiB. The app calls
   `prepare-my-equine-photo`, uploads the bytes only to the returned
   signed URL, then calls `finalize-my-equine-photo`. A GIF or a file
   over 8 MiB is refused before prepare.
5. The photo renders from `sign-my-equine-photo-read`. It is not a
   public object URL. After 300 seconds, or when the image fails to
   load, the app asks for a new signed read.
6. Adult A retires the photo with `retire-my-equine-photo`. The photo
   leaves the list. If finalize or retire answers `retry`, the app
   repeats that call once and does not upload a second time.
7. Adult B cannot list, upload, read, or retire Adult A's photo.
8. A center member who is not the person primary manager cannot create
   the equine for Adult A and cannot prepare, read, or retire the photo.
9. A guardian cannot create an equine for a minor and cannot manage
   Adult A's photo. Guardianship is not management.

Errors shown in the app stay in Spanish and do not include database or
SQL text. A failed list does not invent an equine or a photo card.
