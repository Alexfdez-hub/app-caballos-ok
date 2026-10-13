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

An open request shows `Solicitud pendiente` or `En revisión`. `No disponible` means the screen cannot tell which open request applies. Trust stays `Verificada` or `No verificada`. `Aceptada` appears only when the current effective id is `VERIFIED`. A finished claim, including `No aceptada`, is not shown as the decision of the current row. The lists do not identify which effective row a finished claim used, so that history is not attached here.

Any open claim from this account for the same equine and Spain blocks another submit, whether its owner or manager type is `PERSON` or `CENTER`. The server uniqueness rule is the account, the equine, and the market. A finished `CENTER` claim does not block a new `PERSON` claim.

Leaving the equine screen settles the in-flight request in the session even though the result is not painted until the screen is focused again. The mutation RPC is confirmed before the following snapshot read. Once that RPC succeeds, or its response cannot be read, that claim kind stays blocked even if the snapshot read fails. Only a failure before confirmation can be retried. A successful submit keeps that post-submit snapshot with the account, the equine, and the request token. Returning applies it before another action, and the submit function rejects the same kind until a refresh shows the server no longer accepts it. A failed refresh keeps that confirmed snapshot. Refresh uses its own counter, so returning does not retire that request or leave the button and the session disagreeing.

## Smoke for the requester

Use the existing requester account that already has a profile and equines. Do not use the reviewer account. Do not create a cohort, a grant, or a dossier by hand.

1. Sign in as the requester and open one equine that already has a current ownership and, if it exists, a current management assignment.
2. In **Verificación de relación**, confirm the screen does not ask for an id, a percentage, a role, or a date.
3. Present the ownership claim once. The request should show `Solicitud pendiente`, and the notice should say the relation is not verified.
4. If a current assignment is offered, present the management claim once and expect the same pending state.
5. A second press must not create another open request.
6. Sign out, sign in as the reviewer, and confirm that equine and those requests are not on the reviewer’s screens. Do not grant the reviewer and do not accept or reject.
