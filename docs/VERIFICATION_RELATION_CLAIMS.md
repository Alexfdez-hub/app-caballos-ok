# Relation claims on the equine screen

**Status:** Expo only. No migration, no remote SQL, no cohort, no grant, no dossier.
**Base:** `origin/main` `d0fe2095bd56250303712db0859c3c78cb2c121d`.

Migration `041` is already deployed. This screen calls the existing authenticated RPCs. It does not read protected tables and it does not use `service_role`.

## RPCs

- `list_my_equine_ownerships`
- `list_my_equine_management_assignments`
- `list_my_equine_ownership_claims`
- `list_my_equine_management_claims`
- `list_my_verification_status`
- `submit_my_equine_ownership_claim`
- `submit_my_equine_management_claim`

The ownership payload copies `ownership_percentage` and `ownership_id` from the single current `PERSON` row. The management payload copies `management_role`, `valid_from`, `valid_until`, and `assignment_id` from the single current assignment. `valid_from` is never `now()`. A row that is not currently effective is not offered. Spain (`ES`) is the only market. The owner and manager type sent for these rows is `PERSON`, and the center id is null. The signed-in account comes from the Auth session inside each RPC.

Request labels reuse the existing copy: `Solicitud pendiente`, `En revisión`, `Aceptada`, `No aceptada`, and `No disponible`. Trust stays `Verificada` or `No verificada`. An accepted claim is not shown as verified trust.

The claim lists do not return the effective row id. An open claim for that equine and market blocks another submit. A finished claim is shown only when its percentage or role matches the current row. If that match is ambiguous, the action stays `No disponible`.

## Smoke for the requester

Use the existing requester account that already has a profile and equines. Do not use the reviewer account. Do not create a cohort, a grant, or a dossier by hand.

1. Sign in as the requester and open one equine that already has a current ownership and, if it exists, a current management assignment.
2. In **Verificación de relación**, confirm the screen does not ask for an id, a percentage, a role, or a date.
3. Present the ownership claim once. The request should show `Solicitud pendiente`, and the notice should say the relation is not verified.
4. If a current assignment is offered, present the management claim once and expect the same pending state.
5. A second press must not create another open request.
6. Sign out, sign in as the reviewer, and confirm that equine and those requests are not on the reviewer’s screens. Do not grant the reviewer and do not accept or reject.
