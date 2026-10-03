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

## Android smoke for equine creation and private photos

This section is a manual check. It is not run by `npm run pilot:journey`
and it does not deploy migrations `031` or `032` or the equine-photo
Edge Functions. Do not run it against remote `efkauegdlmfkonzwyyiv`
until those artifacts have been deployed by a later, separate decision.
`equine-media` stays private. Do not open the bucket and do not put a
`service_role` key in the app.

Use two adult accounts in the same market, plus one center manager and
one verified guardian who are not the primary manager of the equine.

1. Adult A opens Mis equinos. The list is empty or shows only equines
   that adult already owns or manages. No sample card is invented.
2. Adult A creates a horse or pony. The detail shows 100 percent
   ownership and primary management, and the equine stays private.
3. Adult A adds a JPEG, PNG or WebP photo of at most 8 MB. The app
   prepares, uploads to the signed URL and finalizes. The photo renders
   from a signed read URL.
4. Adult A waits for the read URL to expire, or forces a load error, and
   confirms the image refreshes. Retire the photo and confirm it leaves
   the list.
5. Adult B, the center manager and the guardian open the same equine.
   They cannot see it in their list, cannot open its detail, and cannot
   upload, read or retire its photo. A membership or a guardianship does
   not create ownership.

## Identity market capture

Not part of `npm run pilot:journey`. Migration
`035_identity_market_capture.sql` is deployed to `efkauegdlmfkonzwyyiv`
as exact version `035`. Android smoke passed for authentication, Spain
selection and persistence, profile edit, navigation, and fictional equine
creation.

1. A new account, or an existing account whose `persons.country_code` is
   null, stays on Completa tu perfil until the person chooses a country.
   Spain is not assigned automatically.
2. The country list comes from `list_identity_markets`. Choose España
   only by tapping it. Do not treat the phone language, locale, time
   zone or location as the market.
3. Saving stores `ES` for that choice. The profile screen can change it
   to another selectable market later.
4. An inactive, unknown or rule-less country is refused with the generic
   save message. The previous person row is left unchanged.
5. After a valid adult market is stored, private equine creation can use
   that market. The Android smoke already exercised that path once.
