# Identity market capture

**Status:** merged, deployed, and verified
**Date:** 2026-10-03
**Migration:** `035_identity_market_capture.sql`, exact remote version `035`
**Issue:** #47, closed
**Main:** `fb599bba25f994bb0bd54ce6e872324523f56e92` (merge of PR #49)

## What changed

Identity completion and profile maintenance ask for an explicit country.
The selectable list is `list_identity_markets`: an `ACTIVE` market with
exactly one age rule effective today. `complete_my_identity` normalizes
the code and resolves the PERSON from `auth.uid()`. A missing, inactive,
unknown or ambiguous market is refused with a stable error, and the
client shows a generic Spanish message.

`is_complete` is false while `persons.country_code` is null or no longer
selectable. Existing null countries are not updated to `ES`. A stored
country that is still selectable is kept until that person changes it.

Spain is inserted only when absent: `ES`, `EUR`, `es-ES`,
`Europe/Madrid`, adult age 18, guardian consent required, reference
`BOE-A-1978-31229` article 12, effective from 1978-12-29. A matching
current Spanish rule is left in place. A contradictory Spanish market or
rule raises `23514` and does not delete history.

## Out of scope

KYC, biometrics, external identity providers, equine-ownership evidence,
public listing, real bookings, payments and migration `036`.

## Deployment

Applied to `efkauegdlmfkonzwyyiv` and registered as exact version `035`.
Android smoke passed: authentication, selecting and persisting Spain,
profile edit, navigation, and creation of a fictional equine. Do not run
a second manual Spain seed on top of the matching baseline. Migration
`036` does not exist and is not authorized.
