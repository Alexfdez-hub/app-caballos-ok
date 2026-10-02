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
