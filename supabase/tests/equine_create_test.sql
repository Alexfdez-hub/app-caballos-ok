-- Issue #41 stage 031. One transaction, then ROLLBACK.
-- Direct SQL provisions people and markets. Client steps call RPCs.
-- Table reads run as the table owner. authenticated has no table grants.

begin;

create function pg_temp.equine_jwt(p_auth uuid)
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

create function pg_temp.equine_rebind(
  p_auth uuid,
  p_person uuid,
  p_account uuid,
  p_first text,
  p_last text,
  p_dob date,
  p_market text
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

  insert into public.persons (
    id, first_name, last_name, date_of_birth, country_code
  ) values (p_person, p_first, p_last, p_dob, p_market);

  insert into public.user_accounts (id, auth_user_id, person_id)
  values (p_account, p_auth, p_person);
end;
$$;

insert into auth.users (id) values
  ('03110000-0000-4000-8000-000000000001'),
  ('03110000-0000-4000-8000-000000000002'),
  ('03110000-0000-4000-8000-000000000003'),
  ('03110000-0000-4000-8000-000000000004'),
  ('03110000-0000-4000-8000-000000000005'),
  ('03110000-0000-4000-8000-000000000006');

insert into public.markets (country_code, status) values ('QZ', 'ACTIVE');
insert into public.market_age_rules (
  country_code, legal_adult_age, guardian_consent_required, effective_from
) values ('QZ', 18, true, date '2000-01-01');

do $$
begin
  perform pg_temp.equine_rebind(
    '03110000-0000-4000-8000-000000000001',
    '03110000-0000-4000-8000-000000000011',
    '03110000-0000-4000-8000-000000000021',
    'Avery', 'Adult', date '1990-04-12', 'QZ'
  );
  perform pg_temp.equine_rebind(
    '03110000-0000-4000-8000-000000000002',
    '03110000-0000-4000-8000-000000000012',
    '03110000-0000-4000-8000-000000000022',
    'Blair', 'Adult', date '1988-01-02', 'QZ'
  );
  perform pg_temp.equine_rebind(
    '03110000-0000-4000-8000-000000000003',
    '03110000-0000-4000-8000-000000000013',
    '03110000-0000-4000-8000-000000000023',
    'Quinn', 'Guardian', date '1982-02-02', 'QZ'
  );
  perform pg_temp.equine_rebind(
    '03110000-0000-4000-8000-000000000004',
    '03110000-0000-4000-8000-000000000014',
    '03110000-0000-4000-8000-000000000024',
    'Morgan', 'Center', date '1984-08-08', 'QZ'
  );
  perform pg_temp.equine_rebind(
    '03110000-0000-4000-8000-000000000005',
    '03110000-0000-4000-8000-000000000015',
    '03110000-0000-4000-8000-000000000025',
    'Noel', 'Nomarket', date '1991-05-05', null
  );

  insert into public.persons (id, first_name, last_name, date_of_birth, country_code)
  values (
    '03110000-0000-4000-8000-000000000016',
    'Rowan', 'Minor', date '2014-03-03', 'QZ'
  );

  insert into public.guardian_relationships (
    id, guardian_person_id, minor_person_id, relationship_type,
    verification_status, verified_at
  ) values (
    '03110000-0000-4000-8000-000000000041',
    '03110000-0000-4000-8000-000000000013',
    '03110000-0000-4000-8000-000000000016',
    'PARENT', 'VERIFIED', clock_timestamp()
  );

  insert into public.equestrian_centers (id, name, slug, country_code, status)
  values (
    '03110000-0000-4000-8000-000000000031',
    'Pilot center',
    'pilot-center-qz',
    'QZ',
    'ACTIVE'
  );

  insert into public.center_memberships (center_id, person_id, role_code, status)
  values (
    '03110000-0000-4000-8000-000000000031',
    '03110000-0000-4000-8000-000000000014',
    'MANAGER',
    'ACTIVE'
  );

  declare
    generated_person uuid;
  begin
    select account.person_id
      into generated_person
      from public.user_accounts as account
     where account.auth_user_id = '03110000-0000-4000-8000-000000000006';

    delete from public.user_accounts
     where auth_user_id = '03110000-0000-4000-8000-000000000006';
    delete from public.persons
     where id = generated_person;
  end;
end;
$$;

select pg_temp.equine_jwt('03110000-0000-4000-8000-000000000001');
set local role authenticated;

do $$
declare
  first_id uuid;
  second_id uuid;
  listed integer;
  detail_name text;
begin
  first_id := public.create_my_equine('  Nube  ', 'HORSE', null, null, null, null, null, null);
  second_id := public.create_my_equine('Bruma', 'PONY');

  if first_id is null or second_id is null or first_id = second_id then
    raise exception 'Two creates did not return distinct equine ids';
  end if;

  select count(*) into listed from public.list_my_equines();
  if listed <> 2 then
    raise exception 'Creator list should contain two equines, got %', listed;
  end if;

  select detail.equine_name
    into detail_name
    from public.get_my_equine(first_id) as detail;
  if detail_name is distinct from 'Nube' then
    raise exception 'Detail name was not trimmed, got %', detail_name;
  end if;

  begin
    perform public.create_my_equine('Futuro', 'HORSE', current_date + 1);
    raise exception 'Future birth date was accepted';
  exception
    when check_violation then null;
  end;

  perform set_config('equine.first_id', first_id::text, true);
  perform set_config('equine.second_id', second_id::text, true);
end;
$$;

reset role;

do $$
declare
  first_id uuid := current_setting('equine.first_id')::uuid;
  second_id uuid := current_setting('equine.second_id')::uuid;
  equine_count integer;
  ownership_count integer;
  manager_count integer;
  audit_count integer;
begin
  select count(*) into equine_count
    from public.equines as equine
   where equine.id in (first_id, second_id)
     and equine.status = 'ACTIVE'
     and equine.visibility_status = 'PRIVATE'
     and equine.name in ('Nube', 'Bruma');
  if equine_count <> 2 then
    raise exception 'Expected two private active equines, got %', equine_count;
  end if;

  select count(*) into ownership_count
    from public.equine_ownerships as ownership
   where ownership.equine_id in (first_id, second_id)
     and ownership.owner_type = 'PERSON'
     and ownership.owner_person_id = '03110000-0000-4000-8000-000000000011'
     and ownership.owner_center_id is null
     and ownership.ownership_percentage = 100
     and ownership.status = 'ACTIVE'
     and ownership.ended_at is null;
  if ownership_count <> 2 then
    raise exception 'Expected two 100 percent ownerships, got %', ownership_count;
  end if;

  select count(*) into manager_count
    from public.equine_management_assignments as assignment
   where assignment.equine_id in (first_id, second_id)
     and assignment.manager_type = 'PERSON'
     and assignment.manager_person_id = '03110000-0000-4000-8000-000000000011'
     and assignment.management_role = 'PRIMARY_MANAGER'
     and assignment.status = 'ACTIVE'
     and assignment.valid_until is null
     and assignment.granted_by_person_id = '03110000-0000-4000-8000-000000000011';
  if manager_count <> 2 then
    raise exception 'Expected two primary managers, got %', manager_count;
  end if;

  select count(*) into audit_count
    from public.audit_events as audit_event
   where audit_event.event_type = 'equine_created'
     and audit_event.entity_type = 'equines'
     and audit_event.entity_id in (first_id, second_id)
     and audit_event.actor_person_id = '03110000-0000-4000-8000-000000000011'
     and audit_event.metadata = jsonb_build_object(
       'equine_type', case when audit_event.entity_id = first_id then 'HORSE' else 'PONY' end,
       'visibility_status', 'PRIVATE'
     );
  if audit_count <> 2 then
    raise exception 'Expected two equine_created audits, got %', audit_count;
  end if;

  if exists (select 1 from public.equines as equine where equine.name = 'Futuro') then
    raise exception 'Failed create left an equine row';
  end if;
end;
$$;

select pg_temp.equine_jwt('03110000-0000-4000-8000-000000000002');
set local role authenticated;

do $$
declare
  foreign_count integer;
  created_id uuid;
begin
  select count(*)
    into foreign_count
    from public.list_my_equines() as equine
   where equine.equine_id = current_setting('equine.first_id')::uuid;
  if foreign_count <> 0 then
    raise exception 'Second adult listed a foreign equine';
  end if;

  begin
    perform public.get_my_equine(current_setting('equine.first_id')::uuid);
    raise exception 'Second adult read a foreign equine';
  exception
    when insufficient_privilege then null;
  end;

  created_id := public.create_my_equine('Otro', 'HORSE');
  perform set_config('equine.blair_id', created_id::text, true);
end;
$$;

reset role;

do $$
begin
  if not exists (
    select 1
      from public.equine_ownerships as ownership
     where ownership.equine_id = current_setting('equine.blair_id')::uuid
       and ownership.owner_type = 'PERSON'
       and ownership.owner_person_id = '03110000-0000-4000-8000-000000000012'
       and ownership.ownership_percentage = 100
  ) then
    raise exception 'Second adult did not receive their own ownership';
  end if;
end;
$$;

select pg_temp.equine_jwt('03110000-0000-4000-8000-000000000003');
set local role authenticated;

do $$
declare
  created_id uuid;
begin
  created_id := public.create_my_equine('Tutor', 'PONY');
  perform set_config('equine.guardian_id', created_id::text, true);
end;
$$;

reset role;

do $$
declare
  owner_id uuid;
begin
  select ownership.owner_person_id
    into owner_id
    from public.equine_ownerships as ownership
   where ownership.equine_id = current_setting('equine.guardian_id')::uuid;
  if owner_id is distinct from '03110000-0000-4000-8000-000000000013' then
    raise exception 'Guardian create did not stay on the guardian person';
  end if;

  if exists (
    select 1
      from public.equine_ownerships as ownership
     where ownership.owner_person_id = '03110000-0000-4000-8000-000000000016'
  ) then
    raise exception 'Guardian create wrote the minor as owner';
  end if;
end;
$$;

select pg_temp.equine_jwt('03110000-0000-4000-8000-000000000004');
set local role authenticated;

do $$
declare
  created_id uuid;
begin
  created_id := public.create_my_equine('Centro', 'HORSE');
  perform set_config('equine.center_id', created_id::text, true);

  begin
    perform public.get_my_equine(current_setting('equine.first_id')::uuid);
    raise exception 'Center member read a foreign equine';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

reset role;

do $$
declare
  created_id uuid := current_setting('equine.center_id')::uuid;
begin
  if exists (
    select 1
      from public.equine_ownerships as ownership
     where ownership.equine_id = created_id
       and ownership.owner_type = 'CENTER'
  ) or exists (
    select 1
      from public.equine_management_assignments as assignment
     where assignment.equine_id = created_id
       and assignment.manager_type = 'CENTER'
  ) then
    raise exception 'Center membership created center equine authority';
  end if;

  if not exists (
    select 1
      from public.equine_ownerships as ownership
     where ownership.equine_id = created_id
       and ownership.owner_type = 'PERSON'
       and ownership.owner_person_id = '03110000-0000-4000-8000-000000000014'
  ) then
    raise exception 'Center member create did not stay on that person';
  end if;
end;
$$;

select pg_temp.equine_jwt('03110000-0000-4000-8000-000000000005');
set local role authenticated;

do $$
begin
  begin
    perform public.create_my_equine('Sin mercado', 'HORSE');
    raise exception using
      errcode = 'P0002',
      message = 'Missing market was accepted';
  exception
    when sqlstate 'P0001' then
      if sqlerrm is distinct from 'Equine creation is not available' then
        raise;
      end if;
  end;
end;
$$;

reset role;

do $$
begin
  if exists (select 1 from public.equines as equine where equine.name = 'Sin mercado') then
    raise exception 'Missing-market create wrote rows';
  end if;

  update public.persons
     set date_of_birth = date '2015-01-01'
   where id = '03110000-0000-4000-8000-000000000011';
end;
$$;

select pg_temp.equine_jwt('03110000-0000-4000-8000-000000000001');
set local role authenticated;

do $$
begin
  begin
    perform public.create_my_equine('Menor', 'HORSE');
    raise exception using
      errcode = 'P0002',
      message = 'Minor was accepted';
  exception
    when sqlstate 'P0001' then
      if sqlerrm is distinct from 'Equine creation is not available' then
        raise;
      end if;
  end;

  begin
    insert into public.equines (name, equine_type)
    values ('Directo', 'HORSE');
    raise exception 'Authenticated inserted equines directly';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

reset role;

do $$
begin
  if exists (
    select 1 from public.equines as equine
     where equine.name in ('Menor', 'Directo')
  ) then
    raise exception 'Rejected create wrote an equine row';
  end if;
end;
$$;

select pg_temp.equine_jwt('03110000-0000-4000-8000-000000000006');
set local role authenticated;

do $$
begin
  begin
    perform public.create_my_equine('Sin identidad', 'HORSE');
    raise exception using
      errcode = 'P0002',
      message = 'Missing identity was accepted';
  exception
    when sqlstate 'P0001' then
      if sqlerrm is distinct from 'Identity could not be resolved' then
        raise;
      end if;
  end;
end;
$$;

reset role;

do $$
begin
  if exists (select 1 from public.equines as equine where equine.name = 'Sin identidad') then
    raise exception 'Missing-identity create wrote rows';
  end if;

  if has_function_privilege(
    'anon',
    'public.create_my_equine(text, text, date, text, text, numeric, text, text)',
    'EXECUTE'
  ) or has_function_privilege(
    'public',
    'public.create_my_equine(text, text, date, text, text, numeric, text, text)',
    'EXECUTE'
  ) or has_function_privilege(
    'anon',
    'public.list_my_equines()',
    'EXECUTE'
  ) or has_function_privilege(
    'anon',
    'public.get_my_equine(uuid)',
    'EXECUTE'
  ) or has_function_privilege(
    'public',
    'public.list_my_equines()',
    'EXECUTE'
  ) or has_function_privilege(
    'public',
    'public.get_my_equine(uuid)',
    'EXECUTE'
  ) then
    raise exception 'anon or PUBLIC can execute equine create reads';
  end if;

  if has_table_privilege('authenticated', 'public.equines', 'SELECT')
     or has_table_privilege('authenticated', 'public.equines', 'INSERT')
     or has_table_privilege('anon', 'public.equines', 'SELECT') then
    raise exception 'authenticated or anon can read or insert equines directly';
  end if;

  if exists (
    select 1
      from pg_catalog.pg_policy as policy
     where policy.polrelid = 'storage.objects'::regclass
       and (
         policy.polname ilike '%equine-media%'
         or pg_catalog.pg_get_expr(policy.polqual, policy.polrelid) ilike '%equine-media%'
         or pg_catalog.pg_get_expr(policy.polwithcheck, policy.polrelid) ilike '%equine-media%'
       )
  ) then
    raise exception 'equine-media must stay deny-by-default';
  end if;
end;
$$;

rollback;
