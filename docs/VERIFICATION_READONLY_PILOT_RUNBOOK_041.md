# Runbook del piloto de verificación de solo lectura — contrato `041`

**Estado:** documentación. Este documento no ejecuta el piloto.
**Fecha:** 2026-10-15
**Base:** `origin/main` `5ed38a93f712069e8be45bd8573d6a5762b57b6a`.
**Sustituye como procedimiento:** `docs/VERIFICATION_REVIEWER_PILOT_SMOKE_STAGE4B4.md`. Ese archivo conserva el handoff de Stage 4B.4. No se ejecuta.
**Fuente de firmas, permisos y estados:** el SQL de las migraciones `036`–`041`. Los documentos de etapa anteriores no prevalecen sobre ese SQL.
**Remoto, según el registro autorizado de `docs/VERIFICATION_NEXT_TRAIN_STAGE0.md` y sin nueva consulta en este tren:** el proyecto `efkauegdlmfkonzwyyiv` tiene la migración `041` integrada y desplegada. Este tren no vuelve a leer ese proyecto y no afirma conteos actuales de cohortes, grants o auditorías.
**PR #62:** no se modifica.
**Bugbot:** manual. Autofix permanece apagado.

Este runbook describe un preflight de solo lectura y, por separado, operaciones futuras que siguen sin autorización. Ningún bloque de SQL de este archivo se ejecuta en este tren. No es el recorrido local `docs/PILOT_RUNBOOK.md`.

## Placeholders

Los ángulos forman parte del nombre. No se sustituyen en Git. No son UUID, correos, códigos de cohorte ni contraseñas. Un valor real solo puede aparecer en la sesión privada del operador y en su cuaderno privado, nunca en el repositorio, en la PR, en un log de CI ni en el chat.

| Placeholder | Qué es, cuando una autorización posterior lo sustituya |
| --- | --- |
| `<address-of-A-typed-in-this-session>` | Dirección de acceso de la persona A, tecleada en esa sesión. |
| `<address-of-B-typed-in-this-session>` | Dirección de acceso de la persona B, tecleada en esa sesión. |
| `<person-id-of-A>` | `persons.id` de A leído en el cuaderno privado. |
| `<person-id-of-B>` | `persons.id` de B leído en el cuaderno privado. |
| `<account-id-of-A>` | `user_accounts.id` de A leído en el cuaderno privado. |
| `<account-id-of-B>` | `user_accounts.id` de B leído en el cuaderno privado. |
| `<cohort-code>` | Código elegido en el momento de la operación. La función lo normaliza con `upper(btrim(...))` y solo acepta `^[A-Z0-9][A-Z0-9-]{0,63}$`. Este documento no elige un código. |
| `<identity-case-id>` | Id del expediente de identidad que el preflight haya identificado. |
| `<ownership-claim-id>` | Id de la reclamación de propiedad identificada. |
| `<management-claim-id>` | Id de la reclamación de responsabilidad identificada. |
| `<grant-id>` | UUID devuelto por el bootstrap futuro. No se inventa antes de esa llamada. |
| `<outside-case-type>` | `IDENTITY`, `OWNERSHIP` o `MANAGEMENT` de un expediente abierto `ES` que ya exista y no sea uno de los tres. |
| `<outside-case-id>` | Id de ese expediente, solo si el preflight demuestra que ya existe. |

`user_accounts.person_id` y `user_accounts.auth_user_id` son únicos (`003_persons_accounts.sql`). El preflight no se fía de esa unicidad: cuenta filas.

## Contrato vigente que este procedimiento usa

Ejecución de cohorte y de grant: `security invoker`. `verification_grant_technical_principal()` exige `current_user` igual a `postgres`. `supabase_admin` no es operador. `service_role`, `authenticated`, `anon` y `public` tienen `EXECUTE` revocado en estas funciones. No son una API de Expo.

| Función | Contrato en `041`, salvo que se indique `039` |
| --- | --- |
| `create_verification_review_cohort(text)` | Inserta una cohorte `ES` en `OPEN` y un evento `CREATED`. Un código duplicado o inválido responde `42501`. |
| `add_verification_review_cohort_case(text, text, uuid)` | Solo con la composición `OPEN`. El expediente tiene que existir, ser `ES` y estar en `SUBMITTED`, `IN_REVIEW` o `RESUBMITTED`. El tipo tiene que ser `IDENTITY`, `OWNERSHIP` o `MANAGEMENT` y coincidir con la tabla. La clave primaria `(case_type, case_id)` es global: el mismo expediente no puede entrar en otra cohorte. Un segundo alta responde `42501`. |
| `close_verification_review_cohort_composition(text)` | Pasa de `OPEN` a `CLOSED`, escribe `closed_at` y un evento `COMPOSITION_CLOSED`. No reabre. |
| `bootstrap_verification_review_grant(uuid, text)` | Sustituye a `bootstrap_verification_review_grant(uuid)`, que `041` elimina. Inserta un grant `ACTIVE`, `MARKET`, `ES`, con `cohort_code` ya enlazado a una cohorte `ES` `CLOSED`. Exige persona `ACTIVE` y cuenta `ACTIVE`. Si esa persona ya tiene un grant `MARKET` / `ES` en `ACTIVE` o `SUSPENDED`, responde `42501`. Devuelve el id del grant. El evento es `GRANTED`, estado anterior nulo, estado nuevo `ACTIVE`, actor `TECHNICAL`, motivo `PILOT_BOOTSTRAP`. |
| `suspend_verification_review_grant(uuid)` | Definida en `039`. Solo de `ACTIVE` a `SUSPENDED`. `valid_until` sigue nulo. Evento `SUSPENDED`, motivo `PILOT_SUSPEND`. No reactiva. |
| `close_verification_review_grant(uuid)` | Definida en `039`. De `ACTIVE` o `SUSPENDED` a `ENDED`, y escribe `valid_until`. El evento es `CLOSED`, motivo `PILOT_CLOSE`, y guarda el estado anterior. `ENDED` no cambia. |

El trigger de composición impide borrar la cohorte, reabrirla, cambiar su código o su mercado, y modificar o borrar membresías. También impide insertar una membresía mientras un grant enlazado a esa cohorte está `ACTIVE` o `SUSPENDED`. Cerrar el grant no reabre la composición. `cohort_code` del grant es inmutable.

Lectura, `security definer`, `EXECUTE` para `authenticated`:

- `get_my_review_capabilities()` no se vuelve a crear en `041`. Sigue llamando a `verification_lock_spain_review_grant(uuid)`, y `041` sí sustituye ese candado. Devuelve una fila `MARKET` / `ES`, o ninguna. El candado exige grant `ACTIVE`, `valid_from <= now()`, alcance `MARKET` / `ES`, `cohort_code` no nulo y cohorte `ES` `CLOSED`. Un grant nulo, legado, suspendido o cerrado no devuelve fila.
- `list_my_review_queue()` devuelve como máximo 50 filas de esa cohorte: `case_id`, `case_type`, `market_country_code`, `state`, `updated_at`, `evidence_categories`. No devuelve nombres. Excluye al sujeto, al remitente y, en propiedad o responsabilidad, a quien `verification_person_acts_for_center` reconozca por una membresía `ACTIVE` del centro nombrado en el expediente.
- `get_my_review_case(text, uuid)` reautoriza un expediente de esa cohorte. Fuera de la cohorte, o con el grant ausente, responde `42501` antes de auditar la apertura. Si la apertura sigue, `record_audit_event` escribe `verification_review_opened` con `case_type`, `market_country_code` y `state`. El detalle incluye el nombre mínimo y, en equino, el nombre del equino. La evidencia del detalle es `{category, document_country_code}`. No devuelve ruta, bucket ni URL.

`verification_cohort_authorizes(uuid, text, uuid)` es verdadero solo con ese grant activo y con el par `(tipo, id)` dentro de su cohorte. `enforce_verification_decision_cohort` deja un `UPDATE` a `ACCEPTED` o `REJECTED` solo cuando esa función es verdadera para `auth.uid()`. Si no, `42501`. El trigger no consulta `verification_case_evidence_is_sufficient`. `review_identity_case`, `review_equine_ownership_claim` y `review_equine_management_claim` siguen siendo las de `037`. Este procedimiento no las llama.

Cerrar un grant aísla a ese revisor. No publica los expedientes a otro grant. Otro grant solo los vería si su propia cohorte cerrada los contiene. La membresía no se mueve al cerrar el grant.

La transición de estado del grant, en `039`, permite `ACTIVE` → `SUSPENDED`, `ACTIVE` → `ENDED` y `SUSPENDED` → `ENDED`. No hay vuelta a `ACTIVE`. El comentario de `039` distingue otra cosa: un grant posterior a `ENDED` sería una fila nueva, no una reactivación de la fila cerrada. Este procedimiento no inserta esa fila.

## A. Preflight de solo lectura

Todavía no autorizado. Cuando lo esté, se ejecuta entero antes de cualquier mutación y como `current_user` `postgres`. Si un resultado obliga a abortar, no se crea la cohorte para completar la información que falte.

Los bloques A.1 a A.7 son una sola transacción. Empieza en `begin` y termina en `rollback`. No usa `commit`. Un `set_config` con el tercer argumento `true` dura solo esa transacción; si cada bloque se confirma por separado, la dirección y los id se pierden antes de la consulta siguiente. `rollback` no borra filas que este preflight no ha escrito.

Las consultas de este apartado solo leen. Los resultados que salgan de la sesión privada se reducen a booleanos y conteos. Los identificadores se quedan en el cuaderno privado.

### A.1. Principal y versión

```sql
begin;

select current_user = 'postgres' as technical_principal;

select max(version) as schema_version
  from supabase_migrations.schema_migrations;

select version
  from supabase_migrations.schema_migrations
 where version = '042';

select pg_get_function_identity_arguments(p.oid) as args
  from pg_proc as p
  join pg_namespace as n
    on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname = 'bootstrap_verification_review_grant';
```

Abortar si el principal no es `postgres`, si `schema_version` no es exactamente `041`, si aparece la versión `042`, o si la firma no es una sola fila `uuid, text`.

### A.2. Estado remoto antes de mutar

```sql
select
  (select count(*) from public.verification_review_cohorts) as cohorts,
  (select count(*) from public.verification_review_cohort_cases) as cohort_cases,
  (select count(*) from public.verification_review_cohort_events) as cohort_events,
  (select count(*) from public.verification_review_grants) as grants,
  (select count(*) from public.verification_review_grant_events) as grant_events,
  (select count(*)
     from public.audit_events
    where event_type = 'verification_review_opened') as opened_audits;
```

Abortar el arranque limpio, con `OPERATOR_ESCALATION_REQUIRED`, si `cohorts`, `cohort_cases`, `cohort_events`, `grants` o `grant_events` no son cero. Este runbook no adopta una cohorte ni un grant ya existentes. El conteo de `opened_audits` se anota y no se usa como prueba de cero: el registro histórico de la versión `040` no es una lectura de este tren, y esta consulta no selecciona metadatos.

### A.3. A y B son dos personas y dos cuentas distintas y activas

Teclear las dos direcciones en la sesión. No guardarlas.

```sql
select set_config(
  'app.pilot_address_a',
  '<address-of-A-typed-in-this-session>',
  true
);

select set_config(
  'app.pilot_address_b',
  '<address-of-B-typed-in-this-session>',
  true
);

with typed as (
  select 'A' as party, current_setting('app.pilot_address_a', false) as address
  union all
  select 'B', current_setting('app.pilot_address_b', false)
),
resolved as (
  select
    typed.party,
    person.id as person_id,
    person.status as person_status,
    account.id as account_id,
    account.status as account_status,
    auth_user.id as auth_user_id
  from typed
  left join auth.users as auth_user
    on auth_user.email = typed.address
  left join public.user_accounts as account
    on account.auth_user_id = auth_user.id
  left join public.persons as person
    on person.id = account.person_id
)
select
  count(*) filter (where party = 'A') as a_rows,
  count(*) filter (where party = 'B') as b_rows,
  count(*) filter (where party = 'A' and person_id is not null) as a_resolved,
  count(*) filter (where party = 'B' and person_id is not null) as b_resolved,
  count(distinct person_id) filter (where person_id is not null) as distinct_persons,
  count(distinct account_id) filter (where account_id is not null) as distinct_accounts,
  count(distinct auth_user_id) filter (where auth_user_id is not null) as distinct_auth_users,
  bool_and(person_status = 'ACTIVE') filter (where person_id is not null) as persons_active,
  bool_and(account_status = 'ACTIVE') filter (where account_id is not null) as accounts_active
from resolved;
```

Abortar salvo que todas estas condiciones sean ciertas: una fila A, una fila B, las dos resueltas, dos personas distintas, dos cuentas distintas, dos usuarios de Auth distintos, personas `ACTIVE` y cuentas `ACTIVE`.

La lectura que copia `<person-id-of-A>`, `<person-id-of-B>`, `<account-id-of-A>` y `<account-id-of-B>` al cuaderno privado usa las mismas dos direcciones y no se pega fuera de ese cuaderno. El bootstrap futuro necesita `<person-id-of-B>`. No necesita la dirección.

### A.4. Expedientes abiertos `ES` que pertenecen a A

Pertenecer a A, en este preflight, significa lo que las columnas del expediente ya guardan:

- Identidad: `subject_person_id` es `<person-id-of-A>`, `submitted_by_account_id` es `<account-id-of-A>`, `market_country_code` es `ES`, y `state` está en `SUBMITTED`, `IN_REVIEW` o `RESUBMITTED`.
- Propiedad: `owner_type` es `PERSON`, `owner_person_id` es A, `owner_center_id` es nulo, el remitente es la cuenta de A, mercado `ES`, y el mismo conjunto de estados.
- Responsabilidad: `manager_type` es `PERSON`, `manager_person_id` es A, `manager_center_id` es nulo, el remitente es la cuenta de A, mercado `ES`, y el mismo conjunto de estados.

Esos tres estados son los únicos que `add_verification_review_cohort_case` acepta. Un estado terminal no es compatible con el alta.

```sql
select set_config('app.pilot_person_a', '<person-id-of-A>', true);
select set_config('app.pilot_account_a', '<account-id-of-A>', true);

with bounds as (
  select
    current_setting('app.pilot_person_a', false)::uuid as person_a,
    current_setting('app.pilot_account_a', false)::uuid as account_a
),
identity_cases as (
  select identity_case.id
    from bounds
    join public.identity_verification_cases as identity_case
      on identity_case.subject_person_id = bounds.person_a
     and identity_case.submitted_by_account_id = bounds.account_a
   where identity_case.market_country_code = 'ES'
     and identity_case.state in ('SUBMITTED', 'IN_REVIEW', 'RESUBMITTED')
),
ownership_claims as (
  select claim.id
    from bounds
    join public.equine_ownership_claims as claim
      on claim.owner_person_id = bounds.person_a
     and claim.submitted_by_account_id = bounds.account_a
   where claim.owner_type = 'PERSON'
     and claim.owner_center_id is null
     and claim.market_country_code = 'ES'
     and claim.state in ('SUBMITTED', 'IN_REVIEW', 'RESUBMITTED')
),
management_claims as (
  select claim.id
    from bounds
    join public.equine_management_authority_claims as claim
      on claim.manager_person_id = bounds.person_a
     and claim.submitted_by_account_id = bounds.account_a
   where claim.manager_type = 'PERSON'
     and claim.manager_center_id is null
     and claim.market_country_code = 'ES'
     and claim.state in ('SUBMITTED', 'IN_REVIEW', 'RESUBMITTED')
)
select
  (select count(*) from identity_cases) as identity_cases,
  (select count(*) from ownership_claims) as ownership_claims,
  (select count(*) from management_claims) as management_claims;
```

El conjunto futuro de este runbook es exactamente uno, uno y uno. Cualquier otro conteo aborta con `DECISION_REQUIRED`. No se crea el expediente que falte y no se elige uno entre varios. Los tres id se copian solo al cuaderno privado, como `<identity-case-id>`, `<ownership-claim-id>` y `<management-claim-id>`.

`DECISION_REQUIRED` — identidad ausente. `docs/VERIFICATION_NEXT_TRAIN_STAGE0.md` dice que, si falta la identidad, A podría enviarla después con `submit_my_identity_case`. Esta secuencia futura no incluye esa llamada.

- Alternativa 1: abortar hasta que una autorización distinta haya enviado esa solicitud.
- Alternativa 2: un tren posterior añade el envío antes de crear la cohorte.
- Consecuencia de la 1: los pasos de la sección B no empiezan.
- Consecuencia de la 2: se crea un expediente remoto. Este tren no la autoriza.
- Este documento no elige.

### A.5. La propiedad y la responsabilidad siguen siendo las de A

El alta a la cohorte no vuelve a leer la fila efectiva. La aceptación de `037` sí la exige, y este piloto no acepta. Aun así, el preflight tiene que comprobar que la fila apuntada sigue siendo de A. No se selecciona el nombre del equino en el resultado compartido.

```sql
select set_config('app.pilot_person_a', '<person-id-of-A>', true);
select set_config('app.pilot_ownership_claim', '<ownership-claim-id>', true);
select set_config('app.pilot_management_claim', '<management-claim-id>', true);

with ids as (
  select
    current_setting('app.pilot_person_a', false)::uuid as person_a,
    current_setting('app.pilot_ownership_claim', false)::uuid as ownership_claim_id,
    current_setting('app.pilot_management_claim', false)::uuid as management_claim_id
)
select
  ownership_claim.effective_ownership_id is not null as ownership_effective_present,
  (
    ownership_claim.effective_ownership_id is not null
    and ownership.id is not null
    and ownership.status = 'ACTIVE'
    and ownership.ended_at is null
    and ownership.started_at <= pg_catalog.now()
    and ownership.equine_id = ownership_claim.equine_id
    and ownership.owner_type = 'PERSON'
    and ownership.owner_person_id = ids.person_a
    and ownership.owner_center_id is null
    and ownership.ownership_percentage is not distinct from ownership_claim.ownership_percentage
  ) as ownership_effective_still_matches,
  management_claim.effective_assignment_id is not null as management_effective_present,
  management_claim.valid_until is null as management_claim_valid_until_is_null,
  (
    management_claim.effective_assignment_id is not null
    and assignment.id is not null
    and assignment.status = 'ACTIVE'
    and assignment.valid_from <= pg_catalog.now()
    and (
      assignment.valid_until is null
      or assignment.valid_until >= pg_catalog.now()
    )
    and assignment.equine_id = management_claim.equine_id
    and assignment.manager_type = 'PERSON'
    and assignment.manager_person_id = ids.person_a
    and assignment.manager_center_id is null
    and assignment.management_role = management_claim.management_role
    and assignment.valid_from is not distinct from management_claim.valid_from
    and assignment.valid_until is not distinct from management_claim.valid_until
  ) as management_effective_still_matches
from ids
join public.equine_ownership_claims as ownership_claim
  on ownership_claim.id = ids.ownership_claim_id
join public.equine_management_authority_claims as management_claim
  on management_claim.id = ids.management_claim_id
left join public.equine_ownerships as ownership
  on ownership.id = ownership_claim.effective_ownership_id
left join public.equine_management_assignments as assignment
  on assignment.id = management_claim.effective_assignment_id;
```

La consulta tiene que devolver una fila. Si no devuelve ninguna, abortar: algún id del cuaderno no está en su tabla. Abortar también si `ownership_effective_still_matches` o `management_effective_still_matches` es falso y el id efectivo correspondiente no es nulo: la fila ya no coincide con el expediente.

`DECISION_REQUIRED` — id efectivo nulo. `add_verification_review_cohort_case` no lo exige. `review_equine_ownership_claim` y `review_equine_management_claim` rechazan `ACCEPTED` si el id efectivo es nulo. La lectura no lo necesita.

- Alternativa 1: abortar el piloto de lectura hasta que el expediente apunte a la fila vigente.
- Alternativa 2: continuar, porque la cohorte y la cola no leen ese id.
- Consecuencia de la 1: no hay piloto aunque la lectura fuera posible.
- Consecuencia de la 2: entra en la cohorte un expediente que `037` no podría aceptar. Este piloto no acepta, pero el expediente quedaría fijado en la cohorte.
- Este documento no elige. Con el id nulo, la sección B no empieza.

### A.6. B no es sujeto, remitente, propietario, gestor ni parte en conflicto

El conflicto que aplican la cola y el detalle es exactamente este: persona sujeto, propietaria o gestora del expediente; cuenta remitente; o `verification_person_acts_for_center` sobre el centro del expediente. Esa función es verdadera cuando hay una membresía `ACTIVE` de B en ese centro. No consulta `equine_ownerships` ni `equine_management_assignments` del revisor. Este preflight no añade un conflicto que el SQL de la cola no tenga.

```sql
select set_config('app.pilot_person_b', '<person-id-of-B>', true);
select set_config('app.pilot_account_b', '<account-id-of-B>', true);
select set_config('app.pilot_identity_case', '<identity-case-id>', true);
select set_config('app.pilot_ownership_claim', '<ownership-claim-id>', true);
select set_config('app.pilot_management_claim', '<management-claim-id>', true);

with ids as (
  select
    current_setting('app.pilot_person_b', false)::uuid as person_b,
    current_setting('app.pilot_account_b', false)::uuid as account_b,
    current_setting('app.pilot_identity_case', false)::uuid as identity_case_id,
    current_setting('app.pilot_ownership_claim', false)::uuid as ownership_claim_id,
    current_setting('app.pilot_management_claim', false)::uuid as management_claim_id
)
select
  (
    identity_case.subject_person_id is not distinct from ids.person_b
    or identity_case.submitted_by_account_id = ids.account_b
    or ownership_claim.owner_person_id is not distinct from ids.person_b
    or ownership_claim.submitted_by_account_id = ids.account_b
    or public.verification_person_acts_for_center(ids.person_b, ownership_claim.owner_center_id)
    or management_claim.manager_person_id is not distinct from ids.person_b
    or management_claim.submitted_by_account_id = ids.account_b
    or public.verification_person_acts_for_center(ids.person_b, management_claim.manager_center_id)
  ) as b_has_conflict
from ids
join public.identity_verification_cases as identity_case
  on identity_case.id = ids.identity_case_id
join public.equine_ownership_claims as ownership_claim
  on ownership_claim.id = ids.ownership_claim_id
join public.equine_management_authority_claims as management_claim
  on management_claim.id = ids.management_claim_id;
```

Abortar si `b_has_conflict` es verdadero, si B es A, o si alguna fila no aparece. No se llama a `review_*` para quitar el conflicto.

### A.7. Evidencia, sin abrirla

```sql
select
  (select count(*)
     from public.verification_evidence as evidence
    where evidence.identity_case_id = '<identity-case-id>'::uuid
       or evidence.ownership_claim_id = '<ownership-claim-id>'::uuid
       or evidence.management_claim_id = '<management-claim-id>'::uuid
  ) as evidence_rows;

rollback;
```

No seleccionar `storage_path`, bucket, referencia de proveedor ni cuerpo. El conteo solo prepara la copia que la pantalla ya tiene: cero filas acompañan a `La evidencia todavía no es suficiente para continuar.`; una fila o más acompañan a `Hay evidencia de las categorías mínimas, pero la decisión sigue bloqueada.` Ninguna de las dos frases es un botón. `verification_case_evidence_is_sufficient` no acepta el expediente. Para la identidad exige `IDENTITY_PROVIDER_REFERENCE`. Para la propiedad exige `EQUINE_IDENTIFIER_REFERENCE` y `OWNERSHIP_ARTIFACT`. Para la responsabilidad exige `EQUINE_IDENTIFIER_REFERENCE` y `MANAGEMENT_DELEGATION_ARTIFACT`.

### A.8. Resultados que obligan a abortar

| Resultado | Marca | Qué no se hace |
| --- | --- | --- |
| Principal distinto de `postgres`, versión distinta de `041`, versión `042`, o firma distinta de `uuid, text` | Abortar | No crear cohorte ni grant. |
| Ya existe cohorte, membresía, evento de cohorte, grant o evento de grant | `OPERATOR_ESCALATION_REQUIRED` | No adoptar esa fila y no crear otra. |
| A o B no resueltos, no activos, o no distintos | Abortar | No crear cuentas. |
| El conjunto de A no es un expediente de cada tipo | `DECISION_REQUIRED` | No enviar identidad ni elegir un expediente. |
| Id efectivo nulo | `DECISION_REQUIRED` | No decidir si entra en la cohorte. |
| La fila efectiva ya no coincide con A | Abortar | No reparar la fila. |
| B tiene conflicto | Abortar | No llamar a `review_*`. |
| `valid_until` de la responsabilidad no es nulo | `ARCHITECTURE_CONFLICT` | No añadir el expediente y no empezar la sección B. |

## ARCHITECTURE_CONFLICT

`041` y la pantalla de reclamación tratan como vigente una asignación `ACTIVE` cuyo `valid_until` es nulo o futuro. `submit_my_equine_management_claim` copia esa ventana. `review_equine_management_claim`, de `037` y no sustituida por `041`, rechaza `ACCEPTED` si `valid_until` no es nulo. `verification_management_is_verified`, de `038`, también exige `valid_until` nulo. Una aceptación de una ventana con fin futuro, si llegara a escribirse, no produciría `MANAGEMENT_AUTHORITY_VERIFIED`.

`create_my_equine` inserta `PRIMARY_MANAGER` con `valid_until` nulo. Esa fila concreta no choca con `037` ni con `038`. El choque aparece en cualquier asignación con fin futuro que la UI ya permite reclamar.

Este runbook no elige si esa reclamación entra en la cohorte, si se excluye, ni si se cambia `037` o `038`. Si el preflight encuentra `management_claim_valid_until_is_null` falso, se detiene antes de la sección B.

No es una aceptación permitida sin evidencia mínima. El SQL actual de `036`–`041` tampoco exige evidencia suficiente para `ACCEPTED` ni para `REJECTED`. La evidencia mínima y el futuro resultado KYC autorizado son el límite descrito para una migración `042` que este tren no inicia. `REJECTED` no queda condicionado a evidencia suficiente: la falta, la insuficiencia, la invalidez o la contradicción pueden ser un motivo de rechazo. La UI, el catálogo de `reason_code` y el procedimiento de rechazo siguen sin autorización. La frase de la pantalla, `Esa acción llegará solo cuando una revisión posterior compruebe la evidencia.`, no convierte esa comprobación en una regla de `REJECTED`.

## B. Operaciones futuras todavía no autorizadas

No ejecutarlas en este tren. No ejecutarlas tampoco si el preflight aborta. El orden es el de la lista. Cada llamada de cohorte o de grant es una escritura remota de `postgres` cuando una autorización distinta la permita. Expo no las llama.

1. Crear la cohorte `ES` en `OPEN`.

```sql
select public.create_verification_review_cohort('<cohort-code>');
```

El resultado tiene que ser el código ya normalizado. Anotarlo en el cuaderno. Si responde `42501`, abortar. No probar otro código dentro del mismo intento.

2. Añadir exclusivamente los tres expedientes identificados de A.

```sql
select public.add_verification_review_cohort_case(
  '<cohort-code>',
  'IDENTITY',
  '<identity-case-id>'::uuid
);

select public.add_verification_review_cohort_case(
  '<cohort-code>',
  'OWNERSHIP',
  '<ownership-claim-id>'::uuid
);

select public.add_verification_review_cohort_case(
  '<cohort-code>',
  'MANAGEMENT',
  '<management-claim-id>'::uuid
);
```

Ningún otro par. Un `42501` detiene el orden. No se cierra la composición para compensar un alta fallida.

3. Verificar la composición, todavía en `OPEN`.

```sql
select
  cohort.market_country_code = 'ES' as market_es,
  cohort.composition_status = 'OPEN' as still_open,
  cohort.closed_at is null as closed_at_null
from public.verification_review_cohorts as cohort
where cohort.code = '<cohort-code>';

select case_type, count(*) as cases
  from public.verification_review_cohort_cases
 where cohort_code = '<cohort-code>'
 group by case_type
 order by case_type;

select
  count(*) = 3
  and bool_and(
    (case_type = 'IDENTITY' and case_id = '<identity-case-id>'::uuid)
    or (case_type = 'OWNERSHIP' and case_id = '<ownership-claim-id>'::uuid)
    or (case_type = 'MANAGEMENT' and case_id = '<management-claim-id>'::uuid)
  ) as composition_is_the_notebook
from public.verification_review_cohort_cases
where cohort_code = '<cohort-code>';

select event_type, count(*) as events
  from public.verification_review_cohort_events
 where cohort_code = '<cohort-code>'
 group by event_type
 order by event_type;
```

Tiene que haber una fila de cohorte `ES` `OPEN`, tres membresías (`IDENTITY`, `OWNERSHIP`, `MANAGEMENT`, una cada una), `composition_is_the_notebook` verdadero, y eventos `CREATED` más tres `CASE_ADDED`. Cero grants. Si el booleano no es verdadero, no seguir. Ese booleano no devuelve los id.

4. Cerrar la composición.

```sql
select public.close_verification_review_cohort_composition('<cohort-code>');
```

Después, la misma cohorte está `CLOSED`, `closed_at` no es nulo, y existe un evento `COMPOSITION_CLOSED`. Sigue sin grant. Una segunda llamada de cierre responde `42501`. No reabrir.

5. Bootstrap del grant de B, ya con la cohorte cerrada.

```sql
select public.bootstrap_verification_review_grant(
  '<person-id-of-B>'::uuid,
  '<cohort-code>'
);
```

Guardar el UUID devuelto como `<grant-id>` en el cuaderno privado. No llamar a la firma de un solo argumento: `041` la elimina. No llamar desde Expo ni como `service_role`.

6. Verificar el grant `MARKET` / `ES` ligado a esa cohorte.

```sql
select
  grant_row.scope_type = 'MARKET' as scope_market,
  grant_row.market_country_code = 'ES' as market_es,
  grant_row.status = 'ACTIVE' as active,
  grant_row.valid_until is null as valid_until_null,
  grant_row.cohort_code = '<cohort-code>' as linked_to_cohort,
  grant_row.reviewer_person_id = '<person-id-of-B>'::uuid as reviewer_is_b
from public.verification_review_grants as grant_row
where grant_row.id = '<grant-id>'::uuid;

select
  event_type,
  previous_status,
  new_status,
  actor_kind,
  reason_code,
  technical_principal = session_user as technical_principal_is_session_user,
  actor_account_id is null as no_account_actor,
  actor_person_id is null as no_person_actor
from public.verification_review_grant_events
where grant_id = '<grant-id>'::uuid
order by occurred_at;
```

Esperado: un grant `ACTIVE`, `MARKET`, `ES`, `valid_until` nulo, `cohort_code` igual al código cerrado, revisor B. Un evento `GRANTED`, estado anterior nulo, estado nuevo `ACTIVE`, actor `TECHNICAL`, motivo `PILOT_BOOTSTRAP`, `technical_principal` igual a `session_user` (la prueba de `039` compara contra `session_user`, no contra un nombre de persona), actores de cuenta y de persona nulos. El principal de esa sesión ya tuvo que ser `postgres` en el preflight. La cohorte sigue `CLOSED`. No hay fila `PLATFORM_IDENTITY` ni `PLATFORM_EQUINE`.

7. Probar la cola y el detalle desde Expo con B. Los pasos observables están en la sección C. No llamar a `review_*`.

8. Confirmar que un expediente fuera de la cohorte falla cerrado.

`get_my_review_case` resuelve al actor con `auth.uid()`. Llamarla como `postgres`, sin sesión de B, no prueba el fallo de cohorte: `verification_resolve_caller` responde `Authentication required`. Forjar `auth.uid()` está fuera de este runbook.

La pantalla no tiene un campo para un id arbitrario. `ReviewPilotScreen` solo abre una fila de la cola. La cola no contiene un expediente fuera de la cohorte, así que el toque no puede demostrar el `42501`.

`DECISION_REQUIRED` — canal del negativo.

- Alternativa 1: una autorización posterior llama a `get_my_review_case('<outside-case-type>', '<outside-case-id>')` con la sesión autenticada de B, sin forjar `auth.uid()` y sin copiar el id a Git.
- Alternativa 2: observar solo que la cola no lo muestra.
- Consecuencia de la 1: hace falta un canal que conserve el JWT de B.
- Consecuencia de la 2: no prueba que el detalle responda `42501` ni que no escriba `verification_review_opened`.
- Este documento no elige.

Si no existe ya un expediente abierto `ES` distinto de los tres, no se crea uno para fabricar el negativo. El id desconocido también responde `42501` y no distingue un expediente real fuera de la cohorte. No usar un UUID inventado.

Cuando ese canal exista, el resultado esperado es `42501` y el mismo conteo de `verification_review_opened` para `<outside-case-id>` que antes de la llamada. No seleccionar el metadato.

9. Suspender el grant.

```sql
select public.suspend_verification_review_grant('<grant-id>'::uuid);
```

Esperado: `status` `SUSPENDED`, `valid_until` todavía nulo. Un evento nuevo `SUSPENDED`, anterior `ACTIVE`, nuevo `SUSPENDED`, motivo `PILOT_SUSPEND`, actor `TECHNICAL`. El evento `GRANTED` sigue. Una segunda suspensión responde `42501`. No hay función de reactivación.

10. Comprobar que desaparecen capacidades, cola y detalle. Sección C, después de la suspensión. `get_my_review_capabilities()` no devuelve fila. La cola y el detalle responden `42501`. El conteo de aperturas no crece por esos intentos fallidos. La cohorte y sus eventos siguen.

11. Cerrar el grant.

```sql
select public.close_verification_review_grant('<grant-id>'::uuid);
```

Esperado: `ENDED`, `valid_until` no nulo y mayor o igual que `valid_from`. Un evento `CLOSED`, anterior `SUSPENDED`, nuevo `ENDED`, motivo `PILOT_CLOSE`. Permanecen `GRANTED`, `SUSPENDED` y `CLOSED`.

12. Confirmar que esa fila no puede reactivarse y que el historial permanece.

```sql
select public.suspend_verification_review_grant('<grant-id>'::uuid);
```

```sql
select public.close_verification_review_grant('<grant-id>'::uuid);
```

Las dos tienen que responder `42501` y no añadir eventos. La fila sigue `ENDED`. Los tres eventos de grant y los eventos de cohorte siguen. No se borra el grant, no se reescribe `verification_review_grant_events`, no se reescribe `verification_review_cohort_events` y no se borra `audit_events`.

No volver a llamar a `bootstrap_verification_review_grant` en este procedimiento. `039` permite, como fila nueva y no como reactivación, otro grant cuando el anterior ya está `ENDED`. Insertarlo quedaría fuera de este orden y volvería a autorizar la misma cohorte. No se hace aquí.

## C. Smoke test Android futuro

No ejecutarlo en este tren. Empieza solo después del paso 6, y se repite la parte de B después de los pasos 9 y 11. No crea cuentas, no envía solicitudes, no añade fotos y no pulsa una decisión.

Las tres solicitudes de A se comprueban en las pantallas que ya existen:

1. Iniciar sesión como A hasta llegar a Perfil. La dirección visible en Perfil sirve para reconocer la cuenta en el dispositivo. No se copia a Git.
2. Perfil → Verificación. En `Verificación de identidad`, el estado de una solicitud abierta es `Solicitud pendiente` para `SUBMITTED`, `IN_REVIEW` y `RESUBMITTED`. No pulsar `Solicitar verificación`.
3. Abrir el equino de las dos reclamaciones identificadas. En `Verificación de relación`, la propiedad y la responsabilidad muestran su confianza y, si la solicitud está abierta, `Solicitud pendiente` o `En revisión`. La confianza esperada de un expediente aún no verificado es `No verificada`. No pulsar `Presentar reclamación de propiedad`, `Presentar reclamación de responsabilidad` ni `Añadir foto`.
4. En Perfil, la fila `Revisión piloto` no está. A no es el revisor.
5. Perfil → `Cerrar sesión`. La sesión de `supabase.auth.signOut()` desaparece y queda la pantalla con el botón `Iniciar sesión`. Perfil ya no está. No iniciar la sesión de B encima de una sesión que siga activa.
6. Iniciar sesión como B. Confirmar en Perfil que la cuenta no es la de A. Antes del paso 6 de la sección B, `Revisión piloto` no está.

Con el grant activo del paso 6:

- Perfil → Verificación muestra `Revisión piloto` solo cuando `get_my_review_capabilities()` devuelve exactamente una fila `MARKET` / `ES`. Esa es la condición de `pilotReviewIsVisible`.
- Abrir `Revisión piloto`. El título es `Revisión piloto`. El subtítulo es `Lectura autorizada para España. No decide ni abre documentos.`
- La bandeja no muestra nombres, direcciones, rutas, buckets ni documentos. Cada fila muestra el tipo (`Identidad`, `Propiedad` o `Gestión`), el estado (`Enviada`, `En revisión` o `Reenviada`), `España`, la fecha de actualización, y o `Sin categorías de evidencia` o los nombres de categoría. Como máximo hay 50 filas. Para este piloto tienen que ser las tres, y ninguna más.
- Abrir solo esas tres. El detalle muestra `Sujeto:` con el nombre mínimo, y en propiedad o responsabilidad `Equino:` con el nombre del equino y el tipo y el rol de la relación. La evidencia, si existe, es categoría y país del documento. No hay ruta, bucket, documento ni URL firmada.
- El detalle muestra la copia de evidencia incompleta o la de evidencia presente, según el conteo del preflight, y siempre `La decisión queda bloqueada. Esta lectura no autoriza una aceptación ni un rechazo. Esa acción llegará solo cuando una revisión posterior compruebe la evidencia.`
- No existen botones `Aceptar` ni `Rechazar`. No pulsar `Actualizar` como si decidiera. `Actualizar` solo vuelve a leer.

Después de la suspensión, y otra vez después del cierre, con B:

- Volver a Perfil. `Revisión piloto` no está.
- Si la pantalla de revisión seguía abierta y la carga anterior había tenido acceso, el estado es `Acceso cerrado`: `La autorización ya no está vigente. Los expedientes de esta sesión se han retirado.` No queda la bandeja ni el detalle.
- La pantalla no distingue `SUSPENDED` de `ENDED`. Esa diferencia se lee solo en el grant.
- No aparecen botones de decisión, rutas, buckets, documentos ni URLs firmadas, porque el detalle ya no está.

Después del cierre, iniciar sesión otra vez como A. Las tres solicitudes siguen en el mismo estado visible de antes. `Revisión piloto` sigue ausente. No enviar, no decidir y no fotografiar.

## D. Rollback y manejo de incidentes

No hay `DELETE`, ni reescritura de `audit_events`, ni reescritura de eventos de grant o de cohorte, ni `UPDATE` de una cohorte cerrada, ni reactivación de un grant `ENDED`. Si el esquema no ofrece una recuperación que deje la composición correcta y el revisor correcto, la marca es `OPERATOR_ESCALATION_REQUIRED`.

| Situación | Qué permite el esquema | Qué no se inventa |
| --- | --- | --- |
| Abortar antes de crear la cohorte | Ninguna escritura de este procedimiento. Anotar el check que falló. | No crear la cohorte para inspeccionar el fallo. |
| Cohorte `OPEN` incompleta, sin expedientes ajenos | Seguir en el paso 2: añadir solo los expedientes identificados que aún no estén, y repetir el paso 3 antes de cerrar. | No cerrar una composición incompleta. No borrar la cohorte. |
| Cohorte `OPEN` con un expediente que no es uno de los tres | Parar. La membresía no se actualiza ni se borra. Ese par `(case_type, case_id)` no puede pasar a otra cohorte. | `OPERATOR_ESCALATION_REQUIRED`. No cerrar y no hacer bootstrap. |
| Cohorte `CLOSED` sin grant, composición igual al cuaderno | Es el estado esperado entre los pasos 4 y 5. El paso 5 sigue disponible si la autorización de ese paso existe. | No reabrir. No añadir. |
| Cohorte `CLOSED` sin grant, composición distinta | Parar. Cerrar no se revierte. | `OPERATOR_ESCALATION_REQUIRED`. No hacer bootstrap sobre una composición incorrecta. |
| Grant creado para una persona que no es B | Si sigue `ACTIVE`, suspenderlo y después cerrarlo. Si ya está `SUSPENDED`, cerrarlo. Comprobar que los eventos permanecen. La cohorte sigue `CLOSED` y el `cohort_code` de esa fila no se vacía. | No borrar el grant. No hacer en el mismo incidente otro bootstrap, ni siquiera para B. Sustituir al revisor es `OPERATOR_ESCALATION_REQUIRED`. |
| Grant `ACTIVE` con composición incorrecta | La membresía no cambia mientras el grant está `ACTIVE` o `SUSPENDED`, y cerrar el grant no reabre la cohorte. Contención: suspender y cerrar, para que la cola deje de ver ese conjunto. Los expedientes permanecen en esa cohorte. | `OPERATOR_ESCALATION_REQUIRED`. No enlazar a otra persona a esa cohorte. |
| Suspensión | Es el paso 9 cuando el humo activo ya terminó. Si ocurre antes de terminar ese humo, el grant no vuelve a `ACTIVE`. Otro bootstrap de la misma persona, mientras exista un grant `SUSPENDED`, responde `42501`. | `OPERATOR_ESCALATION_REQUIRED` para recuperar el acceso. No cerrar como sustituto de una reactivación. |
| Cierre definitivo | La fila queda `ENDED`. Suspenderla o cerrarla otra vez responde `42501`. El historial de grant, el de cohorte y las auditorías de apertura permanecen. | No reactivar. No insertar la fila nueva que `039` distingue de una reactivación. No borrar expedientes. |

## Decisiones que este runbook no cierra

Siguen abiertas en sus fuentes. Este tren no las cierra.

- `DECISION_REQUIRED` ya registradas en `docs/MANUAL_VERIFICATION_MVP0_DESIGN.md` y en `docs/PRODUCT_DECISION_LOG.md`: `REVIEWER-GRANT-AUTHORITY`, `REVIEWER-VISIBILITY`, `MINOR-IDENTITY-SUBMISSION`, `LEGAL-EVIDENCE-CATALOG`, `RETENTION-AND-EXPIRY`, `CONFLICT-RESOLUTION-AUTHORITY`, `GATE-PREDICATE`, `KYC-PROVIDER`, `FISCAL-GATE`, `PUBLIC-ACCESS`.
- `LEGAL_AND_INSURANCE_REVIEW_REQUIRED`, antes de reservas remuneradas reales.
- `DECISION_REQUIRED` de este procedimiento: identidad ausente; id efectivo nulo; conjunto de expedientes distinto de uno por tipo; canal autenticado del negativo fuera de cohorte.
- `ARCHITECTURE_CONFLICT` de `valid_until`, sin solución elegida.
- `OPERATOR_ESCALATION_REQUIRED` en los incidentes de la sección D donde el esquema no recupera la composición o el revisor.

La migración `042` no forma parte de este runbook. No se inicia.

## Qué ya existe y qué no se autoriza

Ya existe en el repositorio y, según el registro del inventario Stage 0, en el remoto desplegado hasta `041`: las funciones de la tabla de contrato, la pantalla `ReviewPilotScreen` sin botones de decisión, y el envío de identidad y de reclamaciones de propiedad y de responsabilidad. Este documento no vuelve a desplegar nada de eso.

Siguen sin autorización: ejecutar este runbook, crear la cohorte, añadir expedientes, cerrar la composición, hacer bootstrap, suspender, cerrar el grant, crear cuentas o expedientes, llamar a `review_*`, implementar `Aceptar` o `Rechazar`, KYC, evidencia privada, Storage, URLs firmadas, la migración `042`, y cualquier cambio de las migraciones `036`–`041`.
