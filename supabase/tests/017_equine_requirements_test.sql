-- Phase 8A local equine-requirements foundation tests.
-- Assumes migrations 001-017. Zero Session / bookings remain deferred.
-- Runnable without psql meta-commands.

begin;

do $$
declare
  fixture_auth uuid[] := array[
    '94000000-0000-0000-0000-000000000001'::uuid
  ];
  linked_person_ids uuid[];
  fixture_equine_ids uuid[];
  fixture_system_ids uuid[];
  fixture_level_ids uuid[];
  fixture_discipline_ids uuid[];
begin
  select coalesce(array_agg(id), '{}') into fixture_equine_ids
    from public.equines where name like 'phase8a-%';
  select coalesce(array_agg(id), '{}') into fixture_system_ids
    from public.qualification_systems where code like 'phase8a-%';
  select coalesce(array_agg(id), '{}') into fixture_level_ids
    from public.qualification_levels
   where qualification_system_id = any(fixture_system_ids);
  select coalesce(array_agg(id), '{}') into fixture_discipline_ids
    from public.disciplines where code like 'phase8a-%';

  delete from public.equine_requirements
   where equine_id = any(fixture_equine_ids);
  delete from public.rider_qualifications
   where qualification_level_id = any(fixture_level_ids);
  delete from public.qualification_levels
   where id = any(fixture_level_ids);
  delete from public.qualification_systems
   where id = any(fixture_system_ids);
  delete from public.equine_disciplines
   where discipline_id = any(fixture_discipline_ids);
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
   where user_account_id in (
     select id from public.user_accounts where auth_user_id = any(fixture_auth)
   );
  select coalesce(array_agg(person_id), '{}') into linked_person_ids
    from public.user_accounts where auth_user_id = any(fixture_auth);
  delete from public.user_accounts where auth_user_id = any(fixture_auth);
  delete from public.persons where id = any(linked_person_ids);
  delete from public.market_age_rules where country_code = 'ZK';
  delete from public.markets where country_code = 'ZK';
  delete from auth.users where id = any(fixture_auth);
end;
$$;

insert into public.markets (country_code, status) values ('ZK', 'ACTIVE');
insert into auth.users (id) values ('94000000-0000-0000-0000-000000000001');

do $$
declare
  owner_person_id uuid;
  fixture_equine_id uuid;
  fixture_discipline_id uuid;
  fixture_system_id uuid;
  fixture_level_id uuid;
  kept_requirement_id uuid;
begin
  if exists (
    select 1 from information_schema.tables
     where table_schema = 'public'
       and table_name in (
         'equine_activities',
         'reviews',
         'incidents',
         'audit_events'
       )
  ) then
    raise exception 'Later domains must remain deferred';
  end if;

  if exists (
    select 1
      from information_schema.columns
     where table_schema = 'public'
       and table_name in ('persons', 'rider_profiles')
       and column_name = 'age'
  ) then
    raise exception 'Rider age must not be stored as a column';
  end if;

  if exists (
    select 1 from pg_catalog.pg_proc as procedure
      join pg_catalog.pg_namespace as namespace
        on namespace.oid = procedure.pronamespace
     where namespace.nspname = 'public'
       and procedure.proname in (
         'create_equine_requirement',
         'upsert_equine_requirement',
         'approve_zero_session'
       )
  ) then
    raise exception 'Requirements mutation or eligibility RPC must not exist';
  end if;

  if not (
    select relrowsecurity
      from pg_catalog.pg_class
     where oid = 'public.equine_requirements'::regclass
  ) then
    raise exception '017 RLS is not enabled';
  end if;

  if exists (
    select 1 from pg_catalog.pg_policy
     where polrelid = 'public.equine_requirements'::regclass
  ) then
    raise exception '017 unexpectedly gained client RLS policies';
  end if;

  select person_id into owner_person_id
    from public.user_accounts
   where auth_user_id = '94000000-0000-0000-0000-000000000001';

  update public.persons
     set first_name = 'Owner', last_name = 'One', date_of_birth = date '1985-01-01'
   where id = owner_person_id;

  insert into public.equines (name, equine_type)
  values ('phase8a-horse', 'HORSE')
  returning id into fixture_equine_id;

  insert into public.equine_ownerships (
    equine_id, owner_type, owner_person_id, ownership_percentage, status
  ) values (
    fixture_equine_id, 'PERSON', owner_person_id, 100, 'ACTIVE'
  );

  insert into public.disciplines (code)
  values ('phase8a-fixture')
  returning id into fixture_discipline_id;

  insert into public.qualification_systems (code, name)
  values ('phase8a-system', 'Phase 8A system')
  returning id into fixture_system_id;

  insert into public.qualification_levels (
    qualification_system_id, code, name
  ) values (
    fixture_system_id, 'phase8a-l1', 'Level one'
  )
  returning id into fixture_level_id;

  begin
    insert into public.equine_requirements (
      equine_id, requirement_type, numeric_value, source_type
    ) values (
      fixture_equine_id, 'MIN_HEIGHT', 140, 'OWNER'
    );
    raise exception 'Invalid requirement type was allowed';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.equine_requirements (
      equine_id, requirement_type, numeric_value, source_type
    ) values (
      fixture_equine_id, 'MIN_AGE', 12, 'TRAINER'
    );
    raise exception 'Invalid source type was allowed';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.equine_requirements (
      equine_id, requirement_type, numeric_value, source_type
    ) values (
      '94000000-0000-0000-0000-000000000099'::uuid, 'MIN_AGE', 12, 'OWNER'
    );
    raise exception 'Requirement with invalid equine FK was allowed';
  exception
    when foreign_key_violation then null;
  end;

  begin
    insert into public.equine_requirements (
      equine_id, requirement_type, numeric_value, source_type, discipline_id
    ) values (
      fixture_equine_id, 'MIN_AGE', 12, 'OWNER',
      '94000000-0000-0000-0000-000000000098'::uuid
    );
    raise exception 'Requirement with invalid discipline FK was allowed';
  exception
    when foreign_key_violation then null;
  end;

  begin
    insert into public.equine_requirements (
      equine_id, requirement_type, qualification_level_id, source_type
    ) values (
      fixture_equine_id, 'MIN_QUALIFICATION',
      '94000000-0000-0000-0000-000000000097'::uuid, 'OWNER'
    );
    raise exception 'Requirement with invalid qualification FK was allowed';
  exception
    when foreign_key_violation then null;
  end;

  begin
    insert into public.equine_requirements (
      equine_id, requirement_type, numeric_value, boolean_value, source_type
    ) values (
      fixture_equine_id, 'MIN_AGE', 12, true, 'OWNER'
    );
    raise exception 'MIN_AGE with boolean_value was allowed';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.equine_requirements (
      equine_id, requirement_type, source_type
    ) values (
      fixture_equine_id, 'MIN_QUALIFICATION', 'OWNER'
    );
    raise exception 'MIN_QUALIFICATION without qualification_level_id was allowed';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.equine_requirements (
      equine_id, requirement_type, numeric_value, boolean_value, source_type
    ) values (
      fixture_equine_id, 'SUPERVISION_REQUIRED', 3, true, 'CENTER'
    );
    raise exception 'SUPERVISION_REQUIRED with numeric_value was allowed';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.equine_requirements (
      equine_id, requirement_type, numeric_value, source_type
    ) values (
      fixture_equine_id, 'MIN_AGE', -1, 'MARKET'
    );
    raise exception 'Negative MIN_AGE was allowed';
  exception
    when check_violation then null;
  end;

  insert into public.equine_requirements (
    equine_id, requirement_type, numeric_value, source_type, discipline_id
  ) values (
    fixture_equine_id, 'MIN_AGE', 12, 'MARKET', fixture_discipline_id
  )
  returning id into kept_requirement_id;

  insert into public.equine_requirements (
    equine_id, requirement_type, qualification_level_id, source_type
  ) values (
    fixture_equine_id, 'MIN_QUALIFICATION', fixture_level_id, 'OWNER'
  );

  insert into public.equine_requirements (
    equine_id, requirement_type, boolean_value, source_type
  ) values (
    fixture_equine_id, 'ZERO_SESSION_REQUIRED', true, 'CENTER'
  );

  perform set_config('app.equine_id', fixture_equine_id::text, true);
  perform set_config('app.requirement_id', kept_requirement_id::text, true);
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '94000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claims', '{"sub":"94000000-0000-0000-0000-000000000001"}', true);

do $$
begin
  begin
    perform * from public.equine_requirements;
    raise exception 'Authenticated role selected equine requirements';
  exception
    when insufficient_privilege then null;
  end;

  begin
    insert into public.equine_requirements (
      equine_id, requirement_type, numeric_value, source_type
    ) values (
      current_setting('app.equine_id', true)::uuid, 'MAX_AGE', 70, 'OWNER'
    );
    raise exception 'Owner client inserted an equine requirement';
  exception
    when insufficient_privilege then null;
  end;

  begin
    update public.equine_requirements
       set status = 'INACTIVE';
    raise exception 'Owner client updated equine requirements';
  exception
    when insufficient_privilege then null;
  end;

  begin
    delete from public.equine_requirements;
    raise exception 'Owner client deleted equine requirements';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

reset role;

do $$
begin
  if has_table_privilege('anon', 'public.equine_requirements', 'select')
     or has_table_privilege('authenticated', 'public.equine_requirements', 'insert')
     or has_table_privilege('authenticated', 'public.equine_requirements', 'update')
     or has_table_privilege('authenticated', 'public.equine_requirements', 'delete')
  then
    raise exception '017 privileges are not deny-by-default';
  end if;
end;
$$;

rollback;
