-- Caller-scoped list_my_activity. One transaction, then ROLLBACK.
-- Direct SQL provisions the server-side world. Client steps use RPCs.

begin;

create function pg_temp.activity_jwt(p_auth uuid)
returns void
language plpgsql
as $$
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_auth::text, ''), true);
  if p_auth is null then
    perform set_config('request.jwt.claims', '{}', true);
  else
    perform set_config(
      'request.jwt.claims',
      json_build_object('sub', p_auth::text, 'role', 'authenticated')::text,
      true
    );
  end if;
end;
$$;

create function pg_temp.activity_rebind(
  p_auth uuid,
  p_person uuid,
  p_account uuid,
  p_first text,
  p_last text,
  p_dob date
)
returns void
language plpgsql
as $$
declare
  old_person uuid;
begin
  select account.person_id
    into old_person
    from public.user_accounts as account
   where account.auth_user_id = p_auth;

  delete from public.user_accounts where auth_user_id = p_auth;
  delete from public.persons where id = old_person;

  insert into public.persons (id, first_name, last_name, date_of_birth)
  values (p_person, p_first, p_last, p_dob);

  insert into public.user_accounts (id, auth_user_id, person_id)
  values (p_account, p_auth, p_person);
end;
$$;

insert into auth.users (id) values
  ('03010000-0000-4000-8000-000000000001'),
  ('03010000-0000-4000-8000-000000000002'),
  ('03010000-0000-4000-8000-000000000003'),
  ('03010000-0000-4000-8000-000000000004');

do $$
begin
  perform pg_temp.activity_rebind(
    '03010000-0000-4000-8000-000000000001',
    '03010000-0000-4000-8000-000000000011',
    '03010000-0000-4000-8000-000000000021',
    'Avery', 'Rider', date '1990-04-12'
  );
  perform pg_temp.activity_rebind(
    '03010000-0000-4000-8000-000000000002',
    '03010000-0000-4000-8000-000000000012',
    '03010000-0000-4000-8000-000000000022',
    'Quinn', 'Guardian', date '1982-02-02'
  );
  perform pg_temp.activity_rebind(
    '03010000-0000-4000-8000-000000000003',
    '03010000-0000-4000-8000-000000000013',
    '03010000-0000-4000-8000-000000000023',
    'Morgan', 'Manager', date '1984-08-08'
  );
  perform pg_temp.activity_rebind(
    '03010000-0000-4000-8000-000000000004',
    '03010000-0000-4000-8000-000000000014',
    '03010000-0000-4000-8000-000000000024',
    'Skyler', 'Intruder', date '1993-03-03'
  );

  insert into public.persons (id, first_name, last_name, date_of_birth)
  values (
    '03010000-0000-4000-8000-000000000015',
    'Rowan', 'Minor', date '2014-03-03'
  );

  insert into public.markets (country_code, status) values ('QY', 'ACTIVE');
  insert into public.market_age_rules (
    country_code, legal_adult_age, guardian_consent_required, effective_from
  ) values ('QY', 18, true, date '2000-01-01');

  insert into public.equestrian_centers (id, name, slug, country_code, status)
  values (
    '03010000-0000-4000-8000-000000000031',
    'Activity Read Center',
    'activity-read-center',
    'QY',
    'ACTIVE'
  );

  insert into public.equines (id, name, equine_type, visibility_status)
  values (
    '03010000-0000-4000-8000-000000000032',
    'Activity Horse',
    'HORSE',
    'PRIVATE'
  );

  insert into public.center_memberships (center_id, person_id, role_code)
  values (
    '03010000-0000-4000-8000-000000000031',
    '03010000-0000-4000-8000-000000000013',
    'MANAGER'
  );

  insert into public.equine_center_permissions (
    equine_id, center_id, granted_by_person_id, permission_code
  ) values
    ('03010000-0000-4000-8000-000000000032', '03010000-0000-4000-8000-000000000031', '03010000-0000-4000-8000-000000000013', 'MANAGE_BOOKINGS'),
    ('03010000-0000-4000-8000-000000000032', '03010000-0000-4000-8000-000000000031', '03010000-0000-4000-8000-000000000013', 'MANAGE_AVAILABILITY'),
    ('03010000-0000-4000-8000-000000000032', '03010000-0000-4000-8000-000000000031', '03010000-0000-4000-8000-000000000013', 'MANAGE_REQUIREMENTS');

  insert into public.center_services (id, center_id, service_type, name)
  values (
    '03010000-0000-4000-8000-000000000034',
    '03010000-0000-4000-8000-000000000031',
    'EQUINE_SESSION',
    'Activity read session'
  );

  insert into public.service_equines (service_id, equine_id, enabled, status)
  values (
    '03010000-0000-4000-8000-000000000034',
    '03010000-0000-4000-8000-000000000032',
    true,
    'ACTIVE'
  );

  insert into public.equine_availability_rules (
    equine_id, center_id, starts_at, ends_at, created_by_account_id
  ) values (
    '03010000-0000-4000-8000-000000000032',
    '03010000-0000-4000-8000-000000000031',
    timestamptz '2026-12-01 00:00:00+00',
    timestamptz '2026-12-04 00:00:00+00',
    '03010000-0000-4000-8000-000000000023'
  );

  insert into public.guardian_relationships (
    guardian_person_id, minor_person_id, relationship_type,
    verification_status, verified_at
  ) values (
    '03010000-0000-4000-8000-000000000012',
    '03010000-0000-4000-8000-000000000015',
    'PARENT',
    'VERIFIED',
    timestamptz '2026-09-01 00:00:00+00'
  );
end;
$$;

select pg_temp.activity_jwt('03010000-0000-4000-8000-000000000001');
set local role authenticated;

do $$
declare
  confirmed_id uuid;
  completed_id uuid;
  open_id uuid;
begin
  confirmed_id := public.create_booking_request(
    '03010000-0000-4000-8000-000000000011',
    '03010000-0000-4000-8000-000000000032',
    '03010000-0000-4000-8000-000000000031',
    '03010000-0000-4000-8000-000000000034',
    timestamptz '2026-12-01 10:00:00+00',
    timestamptz '2026-12-01 11:00:00+00'
  );
  completed_id := public.create_booking_request(
    '03010000-0000-4000-8000-000000000011',
    '03010000-0000-4000-8000-000000000032',
    '03010000-0000-4000-8000-000000000031',
    '03010000-0000-4000-8000-000000000034',
    timestamptz '2026-12-01 12:00:00+00',
    timestamptz '2026-12-01 13:00:00+00'
  );
  open_id := public.create_booking_request(
    '03010000-0000-4000-8000-000000000011',
    '03010000-0000-4000-8000-000000000032',
    '03010000-0000-4000-8000-000000000031',
    '03010000-0000-4000-8000-000000000034',
    timestamptz '2026-12-02 10:00:00+00',
    timestamptz '2026-12-02 11:00:00+00'
  );
  perform set_config('activity.confirmed_id', confirmed_id::text, true);
  perform set_config('activity.completed_id', completed_id::text, true);
  perform set_config('activity.open_id', open_id::text, true);
end;
$$;

reset role;

select pg_temp.activity_jwt('03010000-0000-4000-8000-000000000003');
set local role authenticated;

do $$
begin
  perform public.confirm_booking(current_setting('activity.confirmed_id')::uuid);
  perform public.confirm_booking(current_setting('activity.completed_id')::uuid);
end;
$$;

reset role;

select pg_temp.activity_jwt('03010000-0000-4000-8000-000000000001');
set local role authenticated;

do $$
declare
  session_id uuid;
begin
  session_id := public.start_session(
    current_setting('activity.completed_id')::uuid,
    false,
    null::uuid,
    null::double precision,
    null::double precision,
    null::text,
    null::timestamptz
  );
  perform public.end_session(
    session_id,
    false,
    null::double precision,
    null::double precision,
    null::text,
    null::timestamptz
  );
end;
$$;

reset role;

select pg_temp.activity_jwt('03010000-0000-4000-8000-000000000002');
set local role authenticated;

do $$
declare
  minor_id uuid;
begin
  minor_id := public.create_booking_request(
    '03010000-0000-4000-8000-000000000015',
    '03010000-0000-4000-8000-000000000032',
    '03010000-0000-4000-8000-000000000031',
    '03010000-0000-4000-8000-000000000034',
    timestamptz '2026-12-02 14:00:00+00',
    timestamptz '2026-12-02 15:00:00+00'
  );
  perform set_config('activity.minor_id', minor_id::text, true);
end;
$$;

reset role;

select pg_temp.activity_jwt('03010000-0000-4000-8000-000000000001');
set local role authenticated;

do $$
declare
  visible integer;
  relation text;
  booking_status text;
  session_status text;
begin
  select count(*) into visible from public.list_my_activity();
  if visible <> 3 then
    raise exception 'Participant should see 3 personal rows, got %', visible;
  end if;

  if exists (
    select 1 from public.list_my_activity() as item
     where item.booking_id = current_setting('activity.minor_id')::uuid
  ) then
    raise exception 'Participant saw a booking made for someone else';
  end if;

  select item.caller_relation, item.booking_status
    into relation, booking_status
    from public.list_my_activity() as item
   where item.booking_id = current_setting('activity.confirmed_id')::uuid;
  if relation is distinct from 'PARTICIPANT' or booking_status is distinct from 'CONFIRMED' then
    raise exception 'Confirmed self-booking was not PARTICIPANT/CONFIRMED';
  end if;

  select item.booking_status, item.session_status
    into booking_status, session_status
    from public.list_my_activity() as item
   where item.booking_id = current_setting('activity.completed_id')::uuid;
  if booking_status is distinct from 'COMPLETED' or session_status is distinct from 'COMPLETED' then
    raise exception 'Completed session history was not returned';
  end if;

  select item.booking_status
    into booking_status
    from public.list_my_activity() as item
   where item.booking_id = current_setting('activity.open_id')::uuid;
  if booking_status is distinct from 'APPROVED' then
    raise exception 'Open request was not APPROVED, got %', booking_status;
  end if;
end;
$$;

reset role;

select pg_temp.activity_jwt('03010000-0000-4000-8000-000000000002');
set local role authenticated;

do $$
declare
  visible integer;
  relation text;
  booking_status text;
begin
  select count(*) into visible from public.list_my_activity();
  if visible <> 1 then
    raise exception 'Booker should see only the minor request, got %', visible;
  end if;

  select item.caller_relation, item.booking_status
    into relation, booking_status
    from public.list_my_activity() as item;
  if relation is distinct from 'BOOKER' or booking_status is distinct from 'PENDING_REQUIREMENTS' then
    raise exception 'Guardian booker row was %, %', relation, booking_status;
  end if;
end;
$$;

reset role;

select pg_temp.activity_jwt('03010000-0000-4000-8000-000000000003');
set local role authenticated;

do $$
declare
  visible integer;
begin
  select count(*) into visible from public.list_my_activity();
  if visible <> 0 then
    raise exception 'Manager inbox must not be enumerated, got %', visible;
  end if;
end;
$$;

reset role;

select pg_temp.activity_jwt('03010000-0000-4000-8000-000000000004');
set local role authenticated;

do $$
declare
  visible integer;
begin
  select count(*) into visible from public.list_my_activity();
  if visible <> 0 then
    raise exception 'Intruder saw activity rows';
  end if;

  begin
    perform 1 from public.bookings;
    raise exception 'Authenticated selected bookings directly';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

reset role;
select pg_temp.activity_jwt(null);

do $$
declare
  result_type text;
begin
  if has_function_privilege('anon', 'public.list_my_activity()', 'EXECUTE')
     or has_function_privilege('public', 'public.list_my_activity()', 'EXECUTE') then
    raise exception 'list_my_activity must not be executable by anon or PUBLIC';
  end if;

  if not has_function_privilege('authenticated', 'public.list_my_activity()', 'EXECUTE') then
    raise exception 'authenticated must be able to execute list_my_activity';
  end if;

  select pg_catalog.pg_get_function_result('public.list_my_activity()'::regprocedure)
    into result_type;

  if result_type ilike '%latitude%'
     or result_type ilike '%snapshot%'
     or result_type ilike '%evidence%'
     or result_type ilike '%person%'
     or result_type ilike '%name%' then
    raise exception 'Activity read result leaks a forbidden field: %', result_type;
  end if;
end;
$$;

rollback;
