# Siguiente tren de verificación — inventario Stage 0

**Estado:** solo documentación. No crea la migración `042`, no escribe código ejecutable y no ejecuta SQL remoto.
**Base:** `origin/main` `8cea048ecd6fe6f031977bc2d65ef623ec7c6181` (merge de la PR #65).
**Remoto, según el estado autorizado de este turno y sin nueva consulta:** proyecto `efkauegdlmfkonzwyyiv`, migración `041` integrada y desplegada. El smoke Android de las reclamaciones de propiedad y de responsabilidad ya pasó. No hay autorización para crear cohortes, conceder grants, decidir expedientes ni ejecutar SQL remoto.
**PR #62:** permanece separada. Este inventario no la modifica.
**Bugbot:** manual. Autofix permanece apagado. Este Stage 0 no lo activa.
**Documento ausente:** `docs/RELATION_CLAIMS_UI.md` no existe. La pantalla fusionada está descrita en `docs/VERIFICATION_RELATION_CLAIMS.md`.

## Conclusión

No hace falta una migración `042` para acercar el MVP depurable al siguiente paso mínimo. Las migraciones `036`–`041` ya contienen la cohorte cerrada, el grant `MARKET` / `ES` enlazado a esa cohorte, la cola y el detalle aislados, y la suspensión y el cierre del grant. Expo ya envía las reclamaciones y ya muestra la revisión en solo lectura.

La migración `042` sí quedaría justificada antes de exponer `ACCEPTED` o `REJECTED` en Expo. Hoy `review_*` puede escribir esos estados sin evidencia suficiente. Esa UI no es el siguiente slice.

## ARCHITECTURE_CONFLICT

Hay dos contradicciones. Ninguna se resuelve en este turno.

### 1. El runbook de humo todavía describe el contrato anterior a `041`

`docs/VERIFICATION_REVIEWER_PILOT_SMOKE_STAGE4B4.md`, `docs/MIGRATION_STATUS.md` y las entradas del 2026-10-10 y 2026-10-11 de `docs/PRODUCT_DECISION_LOG.md` dicen que el remoto está en `040`, que `bootstrap_verification_review_grant` recibe solo la persona, y que cerrar el grant deja los expedientes visibles para cualquier revisor `MARKET` / `ES` posterior.

El SQL desplegable de `041` dice otra cosa:

- `bootstrap_verification_review_grant(uuid)` se elimina. La función vigente es `bootstrap_verification_review_grant(uuid, text)` y exige una cohorte `ES` ya `CLOSED`.
- `list_my_review_queue()` y `get_my_review_case(text, uuid)` solo alcanzan expedientes de esa cohorte. Un UUID conocido fuera de ella responde `42501` y no se audita como apertura.
- Cerrar el grant aísla a ese revisor. No publica los expedientes a otro grant que no tenga esos expedientes en su propia cohorte cerrada.

Seguir el runbook `4B4` al pie de la letra sería un procedimiento obsoleto, no el piloto controlado.

### 2. «Vigente» no significa lo mismo al reclamar que al aceptar o al confiar

`041` y la pantalla de reclamación tratan como vigente una asignación `ACTIVE` cuyo `valid_until` es nulo o futuro. El payload copia esa fecha.

`review_equine_management_claim` (`037`, no sustituida por `041`) rechaza `ACCEPTED` si `valid_until` no es nulo. `verification_management_is_verified` (`038`) también exige `valid_until` nulo. Una aceptación de una ventana con fin futuro, si llegara a escribirse, no produciría `MANAGEMENT_AUTHORITY_VERIFIED`.

El equino creado por `create_my_equine` inserta `PRIMARY_MANAGER` con `valid_until` nulo, así que esa fila concreta no choca con `037` ni con `038`. El choque aparece en cualquier asignación con fin futuro que la UI ya permite reclamar. No autoriza la migración `042` en este Stage 0. Sí impide tratar la UI de decisión como si el contrato de aceptación ya estuviera alineado.

## Firmas y permisos vigentes

Las funciones de lectura de `040` que `041` sustituye quedan reemplazadas. `get_my_review_capabilities()` no se vuelve a crear: sigue llamando a `verification_lock_spain_review_grant`, y `041` sí sustituye ese candado para exigir cohorte cerrada.

| Función | Argumentos | Devuelve | Ejecución |
| --- | --- | --- | --- |
| `get_my_review_capabilities()` | ninguno | `scope_type`, `market_country_code`. Una fila `MARKET` / `ES`, o ninguna. | `SECURITY DEFINER`. `EXECUTE` para `authenticated`. Revocado a `public`, `anon` y `service_role`. |
| `list_my_review_queue()` | ninguno | Como máximo 50 filas: `case_id`, `case_type`, `market_country_code`, `state`, `updated_at`, `evidence_categories`. Sin nombres. | Igual. `041` limita las filas a la cohorte del grant. |
| `get_my_review_case(text, uuid)` | tipo y id opaco | Una fila con estado, fechas, nombre mínimo, equino, tipo y rol de relación, evidencia `{category, document_country_code}` y `evidence_sufficient`. | Igual. Fuera de la cohorte, `42501` antes de auditar la apertura. |
| `review_identity_case(uuid, text, text)` | id, `ACCEPTED` o `REJECTED`, motivo de 1 a 80 caracteres | `case_id`, `state`, `outcome`, `reason_code`, `decided_at` | `SECURITY DEFINER`. `EXECUTE` para `authenticated`. Revocado a `public` y `anon` en `037`. `041` no la sustituye. |
| `review_equine_ownership_claim(uuid, text, text)` | igual, sobre la reclamación | `claim_id`, `state`, `outcome`, `reason_code`, `decided_at` | Igual. |
| `review_equine_management_claim(uuid, text, text)` | igual | igual | Igual. `ACCEPTED` exige `valid_until` nulo. |

`ACCEPTED` y `REJECTED` también pasan por el trigger `enforce_verification_decision_cohort`. Ese trigger solo deja el cambio si `verification_cohort_authorizes` es verdadero para el `auth.uid()` y el par `(tipo, id)`. Un grant sin cohorte, suspendido o cerrado no autoriza la decisión. El rechazo observable es `42501`.

Composición y bootstrap, solo `postgres`:

| Función | Contrato | Ejecución |
| --- | --- | --- |
| `create_verification_review_cohort(text)` | Crea una cohorte `ES` en `OPEN`. | `SECURITY INVOKER`. Exige el principal técnico de `039`. `EXECUTE` revocado a `public`, `anon`, `authenticated`, `service_role` y `supabase_admin`. |
| `add_verification_review_cohort_case(text, text, uuid)` | Añade un expediente abierto `ES` cuyo tipo coincide con la tabla. Un segundo alta del mismo par falla. | Igual. Solo mientras la composición está `OPEN`. |
| `close_verification_review_cohort_composition(text)` | Pasa a `CLOSED`. No reabre. | Igual. |
| `bootstrap_verification_review_grant(uuid, text)` | Inserta un grant `ACTIVE` `MARKET` / `ES` ya enlazado a una cohorte `CLOSED`. | Igual. No es una API de Expo ni de `service_role`. |
| `suspend_verification_review_grant(uuid)` | `ACTIVE` pasa a `SUSPENDED`. No reactiva. | Igual, definida en `039`. |
| `close_verification_review_grant(uuid)` | `ACTIVE` o `SUSPENDED` pasa a `ENDED`. El evento es `CLOSED`. | Igual. |

Las tablas de cohorte tienen RLS y `REVOKE ALL` para `public`, `anon`, `authenticated` y `service_role`. La app no elige la cohorte.

## Qué hay ya en Expo

- Solicitante: `submit_my_identity_case`, y desde la PR #65 `submit_my_equine_ownership_claim` y `submit_my_equine_management_claim`, copiando la fila vigente. `Aceptada` solo aparece si el predicado del id efectivo es `VERIFIED`. Un estado terminal suelto no se presenta como decisión de esa fila.
- Revisor: `ReviewPilotScreen` llama a capacidades, cola y detalle. El subtítulo dice que la lectura no decide ni abre documentos. No hay botón `Aceptar` ni `Rechazar`. El texto de decisión bloqueada permanece. No llama a `review_*`.
- La evidencia del detalle, cuando existe, muestra categoría y país del documento. No muestra ruta, bucket ni URL firmada.

## A. Qué falta para el piloto controlado

El piloto pedido es: usuario A solicitante, usuario B revisor, una cohorte cerrada solo con los expedientes de A, cola y detalle aislados, grant `MARKET` / `ES`, y después suspensión y cierre.

No falta esquema. Falta un procedimiento autorizado y alineado con `041`, y falta ejecutarlo. Este turno no lo ejecuta.

1. Confirmar, fuera de Git y sin publicar identificadores, qué expedientes abiertos `ES` pertenecen ya a A: identidad si se envió, más las reclamaciones de propiedad y responsabilidad del smoke. Si falta la identidad, A puede enviarla con la RPC que ya existe. No se crea aquí.
2. Sustituir el runbook `4B4` antes de cualquier operación. El orden real es: crear cohorte, añadir solo esos expedientes, cerrar la composición, y solo entonces `bootstrap_verification_review_grant(persona de B, código)`.
3. B tiene que ser otra persona `ACTIVE`, con cuenta `ACTIVE`, sin ser sujeto, remitente, titular o gestor de esos expedientes, y sin una membresía activa del centro reclamante. B no recibe las reclamaciones del piloto.
4. Con el grant enlazado, la pantalla ya implementada debe mostrar `Revisión piloto`, la cola solo con esos expedientes y el detalle reautorizado. Un UUID fuera de la cohorte debe fallar cerrado.
5. `suspend_verification_review_grant` y después `close_verification_review_grant` retiran capacidades, cola, detalle y decisión. La cohorte y su historial permanecen. No se borra el grant ni sus eventos.
6. En ese humo no se llama a `review_*`. La evidencia seguirá siendo insuficiente mientras no existan filas de evidencia, y la pantalla ya lo dice.

## B. Qué puede hacerse con `036`–`041` sin migración nueva

- Enviar identidad, propiedad y responsabilidad desde Expo, con las restricciones de fila vigente y de una sola reclamación abierta.
- Componer y congelar una cohorte, crear el grant enlazado, suspenderlo y cerrarlo, como operaciones `postgres` ya escritas.
- Leer capacidades, cola pseudónima y detalle reautorizado, aislados por esa cohorte.
- Mantener la pantalla de revisión sin decisión y sin documentos.
- Corregir el runbook para que describa ese contrato.

No hace falta otro RPC de lectura ni otro botón de envío para ese piloto.

## C. Qué carencia justificaría la migración `042`

No la justifica el piloto de solo lectura.

La justificaría el slice de decisión. `review_identity_case`, `review_equine_ownership_claim` y `review_equine_management_claim` no consultan `verification_case_evidence_is_sufficient`. Un revisor autenticado, con grant de cohorte y sin conflicto, puede dejar `ACCEPTED` con cero evidencia. Para la identidad, el predicado de `038` convertiría esa aceptación en `IDENTITY_VERIFIED`. El servidor dejaría de ser el límite que la pantalla ya anuncia.

El contrato mínimo de esa migración, si un tren posterior la autoriza, sería:

- `ACCEPTED` falla cerrado cuando la evidencia mínima no está completa. La regla de España ya está en `verification_case_evidence_is_sufficient`: referencia del proveedor para la identidad; referencia del equino más artefacto para propiedad y para responsabilidad.
- La misma función debe seguir exigiendo la cohorte antes de devolver una fila.
- Si el producto quiere aceptar asignaciones con `valid_until` futuro, `042` tiene que alinear la aceptación y `verification_management_is_verified` con la regla de vigencia de `041`. Hasta esa decisión, no se aceptan esas filas.

KYC, URLs firmadas y un catálogo legal de documentos no caben en ese arreglo mínimo. Siguen siendo trenes posteriores. `DECISION_REQUIRED` `KYC-PROVIDER` y `RETENTION-AND-EXPIRY` continúan abiertos en `docs/MANUAL_VERIFICATION_MVP0_DESIGN.md`.

## D. ¿Pueden exponerse `ACCEPTED` y `REJECTED` en Expo?

No, no en este tren.

- No hay evidencia válida en el flujo de reclamaciones fusionado. El smoke no inserta `verification_evidence`. `evidence_sufficient` permanece falso. La pantalla ya distingue «todavía no es suficiente» de «hay categorías mínimas y aun así la decisión sigue bloqueada».
- No hay proveedor KYC. La identidad verificada no puede presentarse como resultado de una aceptación manual sin cerrar esa decisión de producto.
- No hay URLs firmadas, y no deben añadirse. `get_my_review_case` no devuelve `storage_path`, bucket ni documento. La evidencia de identidad, además, exige `storage_path` nulo: solo una referencia de proveedor.
- La cola no devuelve nombres. El detalle autorizado sí devuelve el nombre mínimo y el nombre del equino. Eso ya es el contrato de lectura de `040`/`041`, no una decisión. Exponer botones de aceptación o rechazo no es necesario para ese dato y sí escribiría confianza sin evidencia.
- En el lado solicitante, `Aceptada` solo puede seguir el predicado `VERIFIED`. Mostrar `ACCEPTED` o `REJECTED` desde la fila histórica atribuiría una decisión a la relación vigente sin probar el id efectivo. La PR #65 ya retiró esa asociación.

`REJECTED` tampoco se expone. El texto actual bloquea las dos acciones hasta que una revisión posterior compruebe la evidencia. Un botón que llamara a la RPC existente saltaría ese límite.

## E. Siguiente slice

Recomendación: **1. Ejecución controlada del piloto de solo lectura.**

No recomiendo la UI de decisión, la evidencia privada ni la integración KYC como paso inmediato. Las dos primeras necesitan el límite de servidor del apartado C. KYC sigue sin proveedor, sin base jurídica cerrada y sin ser necesaria para comprobar que A y B quedan aislados.

El Stage siguiente, exacto, todavía no ejecuta el piloto:

**Stage 0.1 — runbook de solo lectura alineado con `041`.** Documental. Sustituye el procedimiento obsoleto de `4B4` por el orden cohorte abierta, alta solo de los expedientes de A, cierre de composición, bootstrap con persona y código, lectura en Expo, suspensión y cierre. No crea `042`. No añade botones. No ejecuta bootstrap ni SQL remoto. No toca la PR #62. Bugbot sigue manual y Autofix apagado.

Solo después de revisar ese runbook, y con una autorización distinta de este turno, el Stage 1 ejecuta la opción 1.
