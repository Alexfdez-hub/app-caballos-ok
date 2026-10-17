# Preflight de solo lectura del piloto 041

**Estado:** documentación. Este archivo no ejecuta el preflight remoto.
**Base:** `origin/main` `d4a5ef4cf265764085dc92728b3ea8cd79acb353`.
**Autoridad:** `docs/VERIFICATION_READONLY_PILOT_RUNBOOK_041.md`. Este guion consolida los bloques A.1 a A.7 en una transacción. No sustituye la sección B y no la autoriza.
**SQL:** `docs/VERIFICATION_READONLY_PREFLIGHT_041.sql`.
**Bugbot:** manual. Autofix permanece apagado.
**PR #62:** no se modifica.

No se crea la migración `042`. No se modifican las migraciones `036`–`041`. No se llama a ninguna función que escriba cohorte, grant, expediente o decisión.

## Stage 0 — contraste

El runbook integrado en este `main` sigue coincidiendo con el SQL de `036`–`041` y con la pantalla. No hay un conflicto que obligue a adaptar código.

- Firmas: `create_verification_review_cohort(text)`, `add_verification_review_cohort_case(text, text, uuid)`, `close_verification_review_cohort_composition(text)`, `bootstrap_verification_review_grant(uuid, text)`, `suspend_verification_review_grant(uuid)`, `close_verification_review_grant(uuid)`. La firma de un solo `uuid` no existe después de `041`.
- Esas funciones son `security invoker`. `verification_grant_technical_principal()` exige `current_user` igual a `postgres`. `EXECUTE` está revocado a `public`, `anon`, `authenticated` y `service_role`.
- `get_my_review_capabilities()`, `list_my_review_queue()` y `get_my_review_case(text, uuid)` son `security definer` con `EXECUTE` para `authenticated`. Capacidades, cola, detalle y el trigger `enforce_verification_decision_cohort` usan la cohorte cerrada del grant.
- La cola admite `SUBMITTED`, `IN_REVIEW` y `RESUBMITTED`. El alta a la cohorte admite los mismos tres. Un estado terminal no entra.
- `verification_case_evidence_is_sufficient(text, uuid)` es el predicado del detalle. Identidad exige `IDENTITY_PROVIDER_REFERENCE`. Propiedad exige `EQUINE_IDENTIFIER_REFERENCE` y `OWNERSHIP_ARTIFACT`. Gestión exige `EQUINE_IDENTIFIER_REFERENCE` y `MANAGEMENT_DELEGATION_ARTIFACT`. El conteo de filas no elige la frase.
- `Revisión piloto` está en Perfil, sección `Verificación`, junto a la fila `Verificación`. `pilotReviewIsVisible` exige exactamente una capacidad `MARKET` / `ES`. La pantalla `Verificación de identidad` no contiene esa fila.
- `valid_until` sigue en `ARCHITECTURE_CONFLICT`. `submit_my_equine_management_claim` puede aceptar un fin nulo o futuro. `list_my_equine_management_assignments` marca `is_currently_effective` solo si `valid_until` es nulo. `managementClaimPayload` no construye la reclamación si esa marca es falsa. `review_equine_management_claim` rechaza `ACCEPTED` si `valid_until` no es nulo, y `verification_management_is_verified` también lo exige nulo. Este guion no elige solución.
- Los eventos de cohorte y de grant, y `audit_events`, siguen siendo de solo adición. El resultado no selecciona `storage_path`, bucket, URL, nombre, correo ni UUID.

Dos lecturas se añaden sin cambiar el SQL ni cerrar una decisión:

- El mercado de identidad es `persons.country_code`, elegido en el perfil. A.3 del runbook no lo leía. Este guion exige `ES` en A y en B. Un nulo no se rellena.
- `person_id` y `account_id` son UUID. El PostgreSQL que usa Supabase no tiene `max(uuid)`. La CTE `chosen` extrae cada valor con `(array_agg(...) filter (...))[1]` solo cuando `account_gate.ok` es verdadero. Esa puerta ya demostró una sola fila, así que el índice no elige entre duplicados. Si la unicidad falla, los seis valores quedan nulos y el preflight se detiene. `array_agg` no sustituye un país nulo por otro.
- En PostgreSQL 17, `pg_get_function_identity_arguments` incluye el nombre del parámetro. La puerta de firma compara los tipos resultantes con `uuid, text` y sigue exigiendo una sola función.
- `identity_verification_decisions` y `equine_relationship_decisions` se cuentan. El runbook no las usa como parada de arranque limpio. La parada sigue siendo cualquiera de los cinco conteos de cohorte o de grant distinto de cero. `opened_audits` se anota y tampoco es esa parada.

El conjunto que abre la sección B, si una autorización posterior existiera, sigue siendo un expediente abierto de cada tipo. Abierto significa `SUBMITTED`, `IN_REVIEW` o `RESUBMITTED`. El detalle `submitted=` solo informa cuántos de esos están en `SUBMITTED`. No se elige un expediente entre varios.

## Cómo se ejecuta, cuando haya autorización

Todavía no hay autorización para el proyecto remoto. Hasta entonces el archivo SQL no se ejecuta allí.

Cuando la haya, se ejecuta el archivo entero en una sesión `postgres`, como un solo guion. Empieza en `begin read only` y termina en `rollback`. No hay `commit`. Las dos primeras sentencias solo aceptan las direcciones en memoria de la transacción y devuelven un booleano, no la dirección. Si el cliente confirma cada sentencia por separado, la dirección se pierde y la consulta siguiente falla cerrada.

La prueba local `npm run test:verification-preflight` hace eso contra la base creada por las migraciones `001`–`041`. Sustituye solo los dos placeholders por direcciones ficticias del fixture, comprueba que la transacción es `READ ONLY`, que termina en `ROLLBACK` y que no queda ningún cambio. No usa el proyecto remoto. Cubre cuentas válidas, una cuenta ausente, país nulo, país distinto de `ES`, una cohorte previa, un grant previo, un expediente ausente y expedientes de más. `auth.users.email` sigue siendo único, así que el fixture no fabrica dos filas con la misma dirección.

Sustituir las direcciones solo en esa sesión. No guardarlas en Git, en la PR, en CI ni en el chat. El resultado publicado de la última consulta no incluye UUID, nombres ni correos.

## Tabla de veredictos

La última consulta devuelve `sort_order`, `check_name`, `verdict`, `runbook_mark` y `detail`.

`verdict` es solo `PASS`, `STOP` u `OPERATOR_ESCALATION_REQUIRED`. `runbook_mark` conserva `DECISION_REQUIRED` y `ARCHITECTURE_CONFLICT` cuando el runbook los usa. Esas marcas siguen abiertas: `STOP` no las cierra.

| `check_name` | `PASS` significa | Si no pasa |
| --- | --- | --- |
| `technical_principal` | `current_user` es `postgres`. | `STOP`. |
| `transaction_is_read_only` | La transacción es de solo lectura. | `STOP`. |
| `schema_exact_041` | La versión máxima es `041` y no existe `042`. | `STOP`. |
| `bootstrap_signature` | Hay una sola firma `uuid, text`. | `STOP`. |
| `bootstrap_not_client_executable` | `public`, `anon`, `authenticated` y `service_role` no tienen `EXECUTE` sobre esa firma. | `STOP`. |
| `clean_start_inventory` | Los cinco conteos de cohorte y de grant son cero. | `OPERATOR_ESCALATION_REQUIRED`. No adoptar ni crear. |
| `two_distinct_active_accounts` | Una fila A, una fila B, las dos resueltas, personas y cuentas distintas y `ACTIVE`. | `STOP`. No crear cuentas. |
| `both_identity_markets_es` | Las dos personas tienen `persons.country_code` igual a `ES`. | `STOP`. No asignar `ES`. |
| `applicant_open_case_set` | Un expediente abierto `ES` de cada tipo, perteneciente a A según el runbook. | `STOP` con `DECISION_REQUIRED`. No elegir ni crear. |
| `ownership_effective_row` | La fila efectiva de propiedad existe y sigue coincidiendo con A. | `STOP`. Si el id efectivo es nulo, la marca es `DECISION_REQUIRED`. |
| `management_effective_row` | La fila efectiva de gestión existe y sigue coincidiendo con A. | `STOP`. Si el id efectivo es nulo, la marca es `DECISION_REQUIRED`. |
| `management_valid_until_null` | `valid_until` de la reclamación de gestión es nulo. El detalle dice si el de la asignación también lo es, sin devolver la fecha. | `STOP` con `ARCHITECTURE_CONFLICT` si no es nulo. La sección B no empieza. |
| `reviewer_has_no_conflict` | B no es sujeto, remitente ni parte en el conflicto que ya aplica la cola. | `STOP`. No llamar a `review_*`. |
| `evidence_predicate_read` | Se pudo leer el predicado de los tres expedientes únicos. `PASS` no significa que la evidencia sea suficiente. | `STOP` con `DECISION_REQUIRED` si no hay un expediente único que evaluar. |
| `section_b_remains_unauthorized` | Esta fila no puede pasar. | `STOP` siempre. La sección B sigue sin autorización. |

Con la migración `042` en el repositorio, `schema_exact_041` devuelve `STOP`. El preflight de verificación no autoriza el recorrido de reservas.

`detail` de `clean_start_inventory` incluye `opened_audits`, `identity_decisions` y `relationship_decisions`. Esos tres números no cambian el veredicto. `detail` de `applicant_open_case_set` separa `open` y `submitted`. `detail` de `evidence_predicate_read` trae los tres booleanos y `rows`. `rows` no elige la frase de la pantalla. La frase de evidencia incompleta acompaña a un booleano falso. La de categorías mínimas acompaña a un booleano verdadero.

Una fila `PASS` en `evidence_predicate_read`, con marca `NOT_A_GATE` e `identity=false`, significa que el predicado se leyó y que la evidencia no es suficiente. No autoriza `ACCEPTED` ni `REJECTED`. La frase de la pantalla sigue ese booleano, no el conteo `rows`.

Cualquier `verdict` distinto de `PASS` detiene el intento. `section_b_remains_unauthorized` es `STOP` aunque las filas anteriores pasen: este guion no autoriza la sección B.

## Lo que el operador obtiene en privado

Solo después de una autorización expresa, y solo en la sesión y en el cuaderno privado:

- las dos direcciones que ya existan, tecleadas en la sesión;
- si más adelante hiciera falta, los id que el cuaderno copie con una lectura que no se pega fuera de ese cuaderno.

Este guion no devuelve esos id. No inventa cuentas, expedientes, evidencias ni cohortes.

## Sigue sin autorización

Ejecutar este guion en el remoto, crear una cohorte, añadir expedientes, cerrar la composición, hacer bootstrap, suspender, cerrar un grant, llamar a `review_*`, crear la migración `042`, elegir la solución de `valid_until`, cerrar un `DECISION_REQUIRED`, hacer merge o desplegar.
