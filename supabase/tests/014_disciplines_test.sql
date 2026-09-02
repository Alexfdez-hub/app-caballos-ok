-- Phase 5A local disciplines foundation tests.
-- Assumes migrations 001-014. Qualifications remain deferred.
-- Runnable without psql meta-commands.

begin;

do $$
declare
  fixture_auth uuid[] := array[
    '91000000-0000-0000-0000-000000000001'::uuid
  ];
  linked_person_ids uuid[];
  fixture_equine_ids uuid[];
  fixture_discipline_ids uuid[];
begin
  select coalesce(array_agg(id), '{}') into fixture_equine_ids
    from public.equines where name like 'phase5a-%';
  select coalesce(array_agg(id), '{}') into fixture_discipline_ids
    from public.disciplines where code like 'phase5a-%';

  delete from public.equine_disciplines
   where equine_id = any(fixture_equine_ids)
      or discipline_id = any(fixture_discipline_ids);
  delete from public.discipline_translations
   where discipline_id = any(fixture_discipline_ids);
  delete from public.disciplines
   where id = any(fixture_discipline_ids);
  delete from public.equine_center_permissions
   where equine_id = any(fixture_equine_ids);
  delete from public.equine_center_assignments
   where equine_id = any(fixture_equine_ids);
  delete from public.equine_management_assignments
   where equine_id = any(fixture_equine_ids);
  delete from public.equine_ownerships
   where equine_id = any(fixture_equine_ids);
  delete from public.equine_media where equine_id = any(fixture_equine_ids);
  delete from public.equines where id = any(fixture_equine_ids);
  delete from public.policy_acceptances
   where user_account_id in (select id from public.user_accounts where auth_user_id = any(fixture_auth));
  select coalesce(array_agg(person_id), '{}') into linked_person_ids
    from public.user_accounts where auth_user_id = any(fixture_auth);
  delete from public.user_accounts where auth_user_id = any(fixture_auth);
  delete from public.persons where id = any(linked_person_ids);
  delete from public.market_age_rules where country_code = 'ZH';
  delete from public.markets where country_code = 'ZH';
  delete from auth.users where id = any(fixture_auth);
end;
$$;

insert into public.markets (country_code, status) values ('ZH', 'ACTIVE');
insert into auth.users (id) values ('91000000-0000-0000-0000-000000000001');

do $$
declare
  caller_person_id uuid;
  fixture_equine_id uuid;
  fixture_discipline_id uuid;
  duplicate_sort_discipline_id uuid;
  catalog_count integer;
begin
  if exists (
    select 1 from information_schema.tables
     where table_schema = 'public'
       and table_name in (
         'rider_assessments',
         'bookings'
       )
  ) then
    raise exception 'Later domains must remain deferred';
  end if;

  if exists (
    select 1 from pg_catalog.pg_proc as procedure
      join pg_catalog.pg_namespace as namespace on namespace.oid = procedure.pronamespace
     where namespace.nspname = 'public'
       and procedure.proname in (
         'list_disciplines',
         'create_discipline',
         'assign_equine_discipline',
         'upsert_equine_discipline'
       )
  ) then
    raise exception 'Discipline mutation or catalog RPC must not exist';
  end if;

  if (
    select count(*) from pg_catalog.pg_class
     where oid in (
       'public.disciplines'::regclass,
       'public.discipline_translations'::regclass,
       'public.equine_disciplines'::regclass
     ) and relrowsecurity
  ) <> 3 then
    raise exception '014 RLS is not enabled';
  end if;

  if exists (
    select 1 from pg_catalog.pg_policy
     where polrelid in (
       'public.disciplines'::regclass,
       'public.discipline_translations'::regclass,
       'public.equine_disciplines'::regclass
     )
  ) then
    raise exception '014 tables unexpectedly gained client RLS policies';
  end if;

  select count(*) into catalog_count from public.disciplines;
  if catalog_count <> 0 then
    raise exception '014 must not seed a discipline catalog';
  end if;

  if exists (
    select 1 from information_schema.tables
     where table_schema = 'public'
       and table_name ~* 'galope|equivalence'
  ) then
    raise exception '014 must not create Galope or equivalence tables';
  end if;

  select person_id into caller_person_id
    from public.user_accounts
   where auth_user_id = '91000000-0000-0000-0000-000000000001';

  insert into public.equines (name, equine_type)
  values ('phase5a-horse', 'HORSE')
  returning id into fixture_equine_id;

  begin
    insert into public.disciplines (code, status)
    values ('phase5a-fixture', 'RETIRED');
    raise exception 'Invalid discipline status was allowed';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.disciplines (code)
    values ('');
    raise exception 'Empty discipline code was allowed';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.disciplines (code, sort_order)
    values ('phase5a-negative', -1);
    raise exception 'Negative sort_order was allowed';
  exception
    when check_violation then null;
  end;

  insert into public.disciplines (code, sort_order)
  values ('phase5a-fixture', 10)
  returning id into fixture_discipline_id;

  insert into public.disciplines (code, sort_order)
  values ('phase5a-duplicate-sort', 10)
  returning id into duplicate_sort_discipline_id;

  if duplicate_sort_discipline_id is null then
    raise exception 'Duplicate non-negative sort_order was rejected';
  end if;

  begin
    insert into public.disciplines (code)
    values ('phase5a-fixture');
    raise exception 'Duplicate discipline code was allowed';
  exception
    when unique_violation then null;
  end;

  begin
    insert into public.discipline_translations (
      discipline_id, locale, name
    ) values (fixture_discipline_id, 'ES', 'Nombre');
    raise exception 'Invalid translation locale was allowed';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.discipline_translations (
      discipline_id, locale, name
    ) values (fixture_discipline_id, 'es', '');
    raise exception 'Blank translation name was allowed';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.discipline_translations (
      discipline_id, locale, name
    ) values (fixture_discipline_id, 'es', '  ');
    raise exception 'Whitespace translation name was allowed';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.discipline_translations (
      discipline_id, locale, name
    ) values ('91000000-0000-0000-0000-000000000099'::uuid, 'es', 'Huérfano');
    raise exception 'Translation with invalid discipline FK was allowed';
  exception
    when foreign_key_violation then null;
  end;

  insert into public.discipline_translations (
    discipline_id, locale, name
  ) values (fixture_discipline_id, 'es', 'Nombre de prueba');

  begin
    insert into public.discipline_translations (
      discipline_id, locale, name
    ) values (fixture_discipline_id, 'es', 'Otro nombre');
    raise exception 'Duplicate translation locale was allowed';
  exception
    when unique_violation then null;
  end;

  begin
    insert into public.equine_disciplines (
      equine_id, discipline_id
    ) values (
      fixture_equine_id,
      '91000000-0000-0000-0000-000000000098'::uuid
    );
    raise exception 'Equine discipline with invalid discipline FK was allowed';
  exception
    when foreign_key_violation then null;
  end;

  begin
    insert into public.equine_disciplines (
      equine_id, discipline_id
    ) values (
      '91000000-0000-0000-0000-000000000097'::uuid,
      fixture_discipline_id
    );
    raise exception 'Equine discipline with invalid equine FK was allowed';
  exception
    when foreign_key_violation then null;
  end;

  begin
    insert into public.equine_disciplines (
      equine_id, discipline_id, experience_level
    ) values (fixture_equine_id, fixture_discipline_id, '  ');
    raise exception 'Blank experience_level was allowed';
  exception
    when check_violation then null;
  end;

  insert into public.equine_disciplines (
    equine_id, discipline_id, experience_level, notes
  ) values (fixture_equine_id, fixture_discipline_id, null, 'fixture note');

  begin
    insert into public.equine_disciplines (
      equine_id, discipline_id
    ) values (fixture_equine_id, fixture_discipline_id);
    raise exception 'Duplicate equine-discipline association was allowed';
  exception
    when unique_violation then null;
  end;

  perform set_config('app.equine_id', fixture_equine_id::text, true);
  perform set_config('app.discipline_id', fixture_discipline_id::text, true);
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '91000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claims', '{"sub":"91000000-0000-0000-0000-000000000001"}', true);

do $$
begin
  begin
    perform * from public.disciplines;
    raise exception 'Authenticated role selected disciplines';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform * from public.discipline_translations;
    raise exception 'Authenticated role selected translations';
  exception
    when insufficient_privilege then null;
  end;

  begin
    insert into public.equine_disciplines (
      equine_id, discipline_id
    ) values (
      current_setting('app.equine_id', true)::uuid,
      current_setting('app.discipline_id', true)::uuid
    );
    raise exception 'Authenticated role inserted an equine discipline';
  exception
    when insufficient_privilege then null;
  end;

  begin
    update public.disciplines
       set status = 'INACTIVE';
    raise exception 'Authenticated role updated disciplines';
  exception
    when insufficient_privilege then null;
  end;

  begin
    delete from public.disciplines;
    raise exception 'Authenticated role deleted disciplines';
  exception
    when insufficient_privilege then null;
  end;

  begin
    update public.discipline_translations
       set name = 'x';
    raise exception 'Authenticated role updated translations';
  exception
    when insufficient_privilege then null;
  end;

  begin
    delete from public.discipline_translations;
    raise exception 'Authenticated role deleted translations';
  exception
    when insufficient_privilege then null;
  end;

  begin
    update public.equine_disciplines
       set notes = 'x';
    raise exception 'Authenticated role updated equine disciplines';
  exception
    when insufficient_privilege then null;
  end;

  begin
    delete from public.equine_disciplines;
    raise exception 'Authenticated role deleted equine disciplines';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

set local role anon;
select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claims', '', true);

do $$
begin
  begin
    perform * from public.equine_disciplines;
    raise exception 'Anonymous role selected equine disciplines';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

reset role;

do $$
begin
  if has_table_privilege('anon', 'public.disciplines', 'select')
     or has_table_privilege('authenticated', 'public.disciplines', 'insert')
     or has_table_privilege('authenticated', 'public.disciplines', 'update')
     or has_table_privilege('authenticated', 'public.disciplines', 'delete')
     or has_table_privilege('anon', 'public.discipline_translations', 'select')
     or has_table_privilege('authenticated', 'public.discipline_translations', 'insert')
     or has_table_privilege('authenticated', 'public.discipline_translations', 'update')
     or has_table_privilege('authenticated', 'public.discipline_translations', 'delete')
     or has_table_privilege('anon', 'public.equine_disciplines', 'select')
     or has_table_privilege('authenticated', 'public.equine_disciplines', 'insert')
     or has_table_privilege('authenticated', 'public.equine_disciplines', 'update')
     or has_table_privilege('authenticated', 'public.equine_disciplines', 'delete')
  then
    raise exception '014 privileges are not deny-by-default';
  end if;
end;
$$;

rollback;
