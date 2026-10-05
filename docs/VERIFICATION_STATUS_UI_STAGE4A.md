# Verification status UI — Stage 4A

Stage 4A is a mobile screen only. It does not add migration `039`, tables, columns, RPCs, RLS policies, or Edge Functions. It does not change migrations `036`, `037`, or `038`.

Repository `main` at the start of this branch is `435118b4e9ab5be3b4c511735f53f2b37ba5c35f`. Remote project `efkauegdlmfkonzwyyiv` is normalized at exact version `038`. This branch is not deployed.

## What the screen does

Perfil opens **Verificación**. The screen reads the signed-in person through:

- `list_my_verification_status()`
- `list_my_identity_cases()`
- `submit_my_identity_case('ES')`

Identity for Spain is `VERIFIED` only when that predicate returns `VERIFIED`. An accepted case by itself stays `No verificada`. Open states `SUBMITTED`, `IN_REVIEW`, and `RESUBMITTED` show `Solicitud pendiente`. A later finished rejection, with no current verification, shows `No aceptada`. An unknown code or a malformed payload fails closed. Labels stay in the presentation layer.

Ownership and management rows are read-only. A name comes from the existing ownership or management list. Otherwise the row says `Equino` and does not show the identifier. There is no claim button, no reviewer UI, and no center corroboration.

Creating a request does not verify identity, does not start KYC, does not ask for documents, and does not open publication, bookings, or payments.

## Still out of scope

Stage 4 is not complete. Evidence upload, ownership and management claims, reviewer UI, a KYC vendor, and Stage 4B are not in this slice. `GATE-PREDICATE` and the other open legal items stay open.

## Android smoke

1. Start Expo Go against the local or remote project that already has `038`. Do not apply a new migration.
2. Sign in with a test account that has a completed identity and market `ES`.
3. Open Perfil → Verificación. Confirm identity, property, and management sections, including the empty states.
4. When the status is `No verificada` or `No aceptada`, tap `Solicitar verificación` once. Confirm the button shows a spinner and does not send twice.
5. After the request, confirm the neutral notice and the status `Solicitud pendiente`.
6. Pull back to Perfil, open Mis equinos and Actividad, then return. Confirm those screens still load.
7. Sign out and sign in again. Open Verificación and confirm the same account's status returns.
8. Confirm the screen never asks for a document, photo, or identity number, and never says the person passed KYC.
