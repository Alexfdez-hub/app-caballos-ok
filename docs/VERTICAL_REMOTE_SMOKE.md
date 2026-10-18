# Recorrido vertical remoto

Procedimiento de solo lectura y, aparte, operaciones PostgreSQL ya existentes que este repositorio no ejecuta. No abre un piloto, no crea reservas y no inserta `booking_request_keys`. No usa `vertical_fixture_install`: esa función es local-only.

El Product Owner confirmó el 18-oct-2026 que `efkauegdlmfkonzwyyiv` está normalizado en las versiones exactas `042` y `043`. Este archivo no reconsulta ese proyecto. El preflight, cuando lo ejecute el operador, se detiene si el máximo no es `043`.

Bugbot y Autofix permanecen apagados. No hay migración `044`.

## Parámetros del operador

Definirlos en el shell, no en Git. No hace falta anotar correos ni UUID en el repositorio.

- `REQUESTER_EMAIL`: cuenta solicitante ya existente.
- `STAFF_EMAIL`: cuenta responsable ya existente. Distinta de la anterior.
- `SLOT_START` y `SLOT_END`: instante UTC de la franja, con zona explícita.

El código de piloto, solo para la sección que no se ejecuta aquí, lo elige el operador. Debe cumplir `^[A-Z0-9][A-Z0-9_-]{0,63}$` y llevar el prefijo `TEST_ONLY`. No hay un código escrito en este archivo.

## Preflight

Conectar como `postgres` al proyecto remoto. La transacción es `READ ONLY` y termina en `ROLLBACK`. Una fila `STOP` no se corrige desde aquí: no se rellenan país, permisos, reglas ni elegibilidad.

```sql
begin transaction read only;

with params as (
  select
    :'requester_email' as requester_email,
    :'staff_email' as staff_email,
    :'slot_start'::timestamptz as slot_start,
    :'slot_end'::timestamptz as slot_end
),
schema_gate as (
  select
    (select max(version) from supabase_migrations.schema_migrations) = '043'
      and exists (
        select 1 from supabase_migrations.schema_migrations where version = '042'
      )
      and exists (
        select 1 from supabase_migrations.schema_migrations where version = '043'
      )
      and not exists (
        select 1
          from supabase_migrations.schema_migrations
         where version !~ '^[0-9]{3}$'
            or version > '043'
      ) as ok
),
requester as (
  select account.id as account_id, person.id as person_id, account.status as account_status,
         person.status as person_status, person.country_code
    from params
    join auth.users as auth_user on auth_user.email = params.requester_email
    join public.user_accounts as account on account.auth_user_id = auth_user.id
    join public.persons as person on person.id = account.person_id
),
staff as (
  select account.id as account_id, person.id as person_id, account.status as account_status,
         person.status as person_status
    from params
    join auth.users as auth_user on auth_user.email = params.staff_email
    join public.user_accounts as account on account.auth_user_id = auth_user.id
    join public.persons as person on person.id = account.person_id
),
account_gate as (
  select
    (select count(*) from requester) = 1
      and (select account_status from requester) = 'ACTIVE'
      and (select person_status from requester) = 'ACTIVE' as requester_ok,
    (select count(*) from staff) = 1
      and (select account_status from staff) = 'ACTIVE'
      and (select person_status from staff) = 'ACTIVE' as staff_ok,
    (select count(*) from requester) = 1
      and (select count(*) from staff) = 1
      and (select account_id from requester) is distinct from (select account_id from staff) as distinct_ok
),
market_gate as (
  select exists (
    select 1
      from requester
      join public.markets as market on market.country_code = requester.country_code
     where requester.country_code is not null
       and market.status = 'ACTIVE'
  ) as ok
),
candidates as (
  select
    center.id as center_id,
    center.name as center_name,
    equine.id as equine_id,
    equine.name as equine_name,
    service.id as service_id,
    service.name as service_name,
    slot.slot_start,
    slot.slot_end
  from params
  join public.equine_availability_rules as rule
    on rule.status = 'ACTIVE'
   and rule.recurrence_rule is null
   and rule.starts_at <= params.slot_start
   and rule.ends_at >= params.slot_end
  join public.equines as equine
    on equine.id = rule.equine_id
   and equine.status = 'ACTIVE'
   and equine.visibility_status = 'PUBLIC'
  join public.equestrian_centers as center
    on center.id = rule.center_id
   and center.status = 'ACTIVE'
  join public.center_services as service
    on service.center_id = center.id
   and service.status = 'ACTIVE'
  join public.service_equines as link
    on link.service_id = service.id
   and link.equine_id = equine.id
   and link.status = 'ACTIVE'
   and link.enabled is true
  join lateral (
    select series.slot_start,
           series.slot_start + make_interval(mins => service.default_duration_minutes) as slot_end
      from generate_series(
        rule.starts_at,
        rule.ends_at - make_interval(mins => service.default_duration_minutes),
        make_interval(mins => service.default_duration_minutes)
      ) as series (slot_start)
     where service.default_duration_minutes is not null
       and (
         link.duration_limit_minutes is null
         or service.default_duration_minutes <= link.duration_limit_minutes
       )
    union all
    select rule.starts_at, rule.ends_at
     where service.default_duration_minutes is null
       and (
         link.duration_limit_minutes is null
         or (extract(epoch from (rule.ends_at - rule.starts_at)) / 60.0)
            <= link.duration_limit_minutes
       )
  ) as slot on slot.slot_start = params.slot_start
            and slot.slot_end = params.slot_end
  where exists (
    select 1
      from public.equine_center_assignments as assignment
     where assignment.equine_id = equine.id
       and assignment.center_id = center.id
       and assignment.status = 'ACTIVE'
       and assignment.ended_at is null
       and assignment.started_at <= now()
  )
  and public.caller_has_booking_manage_authority(
    (select person_id from staff),
    equine.id,
    center.id
  )
  and not public.has_active_equine_calendar_overlap(
    equine.id,
    params.slot_start,
    params.slot_end
  )
),
chosen as (
  select *
    from candidates
   where (select count(*) from candidates) = 1
),
custody_gate as (
  select exists (
    select 1
      from chosen
      join public.equine_ownerships as ownership
        on ownership.equine_id = chosen.equine_id
       and ownership.status = 'ACTIVE'
       and ownership.ended_at is null
  ) or exists (
    select 1
      from chosen
      join public.equine_management_assignments as management
        on management.equine_id = chosen.equine_id
       and management.status = 'ACTIVE'
  ) as ok
),
pilot_gate as (
  select not exists (
    select 1
      from chosen
     where public.equine_center_is_in_open_bookable_pilot(chosen.center_id, chosen.equine_id)
  ) as ok
),
booking_gate as (
  select not exists (
    select 1
      from chosen
      join public.bookings as booking
        on booking.equine_id = chosen.equine_id
       and booking.starts_at < chosen.slot_end
       and booking.ends_at > chosen.slot_start
       and booking.status not in ('REJECTED', 'CANCELLED', 'EXPIRED', 'COMPLETED')
  ) as ok
),
key_gate as (
  select not exists (
    select 1
      from chosen
      join public.booking_request_keys as key
        on key.account_id = (select account_id from requester)
       and key.equine_id = chosen.equine_id
       and key.center_id = chosen.center_id
       and key.service_id = chosen.service_id
       and key.starts_at = chosen.slot_start
       and key.ends_at = chosen.slot_end
  ) as ok
),
eligibility_gate as (
  select public.booking_eligibility_overall(
    (select person_id from requester),
    (select equine_id from chosen),
    (select center_id from chosen),
    (select slot_start from chosen),
    (select slot_end from chosen),
    (select service_id from chosen),
    (select person_id from requester)
  ) as overall
  where (select count(*) from chosen) = 1
)
select
  case
    when not (select ok from schema_gate) then 'STOP'
    when not (select requester_ok and distinct_ok from account_gate) then 'STOP'
    when not (select staff_ok from account_gate) then 'STOP'
    when not (select ok from market_gate) then 'STOP'
    when (select slot_end <= slot_start or slot_start <= now() from params) then 'STOP'
    when (select count(*) from candidates) is distinct from 1 then 'STOP'
    when not (select ok from custody_gate) then 'STOP'
    when not (select ok from pilot_gate) then 'STOP'
    when not (select ok from booking_gate) then 'STOP'
    when not (select ok from key_gate) then 'STOP'
    when (select overall from eligibility_gate) is distinct from 'ELIGIBLE'
     and (select overall from eligibility_gate) is distinct from 'ELIGIBLE_WITH_SUPERVISION'
      then 'STOP'
    else 'PASS'
  end as verdict,
  case
    when not (select ok from schema_gate) then 'schema_not_043'
    when not (select requester_ok and distinct_ok from account_gate) then 'requester_account'
    when not (select staff_ok from account_gate) then 'staff_account'
    when not (select ok from market_gate) then 'requester_market'
    when (select slot_end <= slot_start or slot_start <= now() from params) then 'slot_range'
    when (select count(*) from candidates) is distinct from 1 then 'slot_count'
    when not (select ok from custody_gate) then 'custody'
    when not (select ok from pilot_gate) then 'open_pilot'
    when not (select ok from booking_gate) then 'incompatible_booking'
    when not (select ok from key_gate) then 'incompatible_key'
    when (select overall from eligibility_gate) is distinct from 'ELIGIBLE'
     and (select overall from eligibility_gate) is distinct from 'ELIGIBLE_WITH_SUPERVISION'
      then 'eligibility_' || coalesce((select overall from eligibility_gate), 'absent')
    else 'ready'
  end as reason,
  (select center_id from chosen) as center_id,
  (select equine_id from chosen) as equine_id,
  (select service_id from chosen) as service_id,
  (select center_name from chosen) as center_name,
  (select equine_name from chosen) as equine_name,
  (select service_name from chosen) as service_name;

rollback;
```

`PASS` significa que hay exactamente una franja derivada con la misma regla que `list_bookable_offers`, salvo que el sujeto del piloto todavía no está abierto. `valid_until` de la gestión no se interpreta: ese conflicto sigue abierto. Un `STOP` con `eligibility_` repite el token que ya devuelve `booking_eligibility_overall`. No se inventa un estado sin pago. `confirm_booking` solo acepta `APPROVED`, y eso solo sale de `ELIGIBLE` o `ELIGIBLE_WITH_SUPERVISION`.

## Operaciones que no se ejecutan

Solo después de un `PASS`, en otra sesión `postgres`, y fuera de este tren:

```sql
begin;
select public.open_bookable_pilot(:'pilot_code');
select public.add_bookable_pilot_subject(
  :'pilot_id'::uuid,
  :'center_id'::uuid,
  :'equine_id'::uuid
);
commit;
```

`open_bookable_pilot` no reabre un código `CLOSED`. `add_bookable_pilot_subject` admite solo el centro y el equino devueltos por el preflight. No insertar reservas, claves ni eventos a mano.

Al terminar el recorrido en Expo, conservar auditoría e historial:

```sql
begin;
select public.end_bookable_pilot_subject(
  :'pilot_id'::uuid,
  :'center_id'::uuid,
  :'equine_id'::uuid
);
select public.close_bookable_pilot(:'pilot_id'::uuid);
commit;
```

Eso no borra `audit_events` ni `bookable_pilot_events`. Cerrar el piloto no lo reabre.

## Expo

No cambiar credenciales ni crear una tercera cuenta. No usar `service_role`.

1. Iniciar sesión con la cuenta solicitante. En Explorar, mover el intervalo hasta que la franja del preflight caiga dentro de la ventana de 14 días. Abrir el detalle. Solicitar una vez. La segunda pulsación no envía otra clave.
2. Si la respuesta no llega, pulsar Reconciliar con el servidor. No volver a solicitar mientras el resultado sea ambiguo. Un `42501` queda cerrado.
3. Actividad muestra la solicitud en Solicitudes. No muestra reservas de la otra cuenta.
4. Cerrar sesión. Entrar con la cuenta responsable. Puedes confirmar muestra solo filas de `list_bookings_i_can_confirm`. Confirmar una vez.
5. Volver a la cuenta solicitante. Próximas muestra la reserva confirmada. Iniciar actividad y después Finalizar actividad. Historial muestra la sesión terminada. Esta pantalla no abre Storage.

Si el preflight devolvió `STOP`, no continuar.
