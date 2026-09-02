-- Phase 4A local equine ownership/management tests.
-- Assumes migrations 001-012 are applied and auth.uid() reads
-- request.jwt.claim.sub. Compatible with later 013 being absent.
-- Runnable without psql meta-commands.

begin;

do $$
declare
  fixture_auth uuid[] := array[
    '80000000-0000-0000-0000-000000000001'::uuid,
    '80000000-0000-0000-0000-000000000002'::uuid
  ];
  linked_person_ids uuid[];
  fixture_equine_ids uuid[];
  fixture_center_ids uuid[];
begin
  select coalesce(array_agg(id), '{}')
    into fixture_equine_ids
    from public.equines
   where name like 'phase4a-%';

  delete from public.equine_management_assignments
   where equine_id = any(fixture_equine_ids)
      or granted_by_person_id in (
        select person_id from public.user_accounts where auth_user_id = any(fixture_auth)
      );

  delete from public.equine_ownerships
   where equine_id = any(fixture_equine_ids)
      or owner_person_id in (
        select person_id from public.user_accounts where auth_user_id = any(fixture_auth)
      );

  delete from public.equine_media
   where equine_id = any(fixture_equine_ids);

  delete from public.equines
   where id = any(fixture_equine_ids);

  select coalesce(array_agg(id), '{}')
    into fixture_center_ids
    from public.equestrian_centers
   where slug like 'phase4a-%';

  delete from public.center_memberships
   where center_id = any(fixture_center_ids)
      or person_id in (
        select person_id from public.user_accounts where auth_user_id = any(fixture_auth)
      );

  delete from public.center_languages
   where center_id = any(fixture_center_ids);

  delete from public.equestrian_centers
   where id = any(fixture_center_ids);

  delete from public.policy_acceptances
   where user_account_id in (
     select id from public.user_accounts where auth_user_id = any(fixture_auth)
   );

  select coalesce(array_agg(person_id), '{}')
    into linked_person_ids
    from public.user_accounts
   where auth_user_id = any(fixture_auth);

  delete from public.user_accounts
   where auth_user_id = any(fixture_auth);

  delete from public.persons
   where id = any(linked_person_ids)
      or last_name in ('Phase4AUnlinked');

  delete from public.market_age_rules
   where country_code = 'ZF';

  delete from public.markets
   where country_code = 'ZF';

  delete from auth.users
   where id = any(fixture_auth);
end;
$$;

insert into public.markets (country_code, status)
values ('ZF', 'ACTIVE');

insert into auth.users (id)
values
  ('80000000-0000-0000-0000-000000000001'),
  ('80000000-0000-0000-0000-000000000002');

do $$
declare
  caller_person_id uuid;
  other_person_id uuid;
  unlinked_person_id uuid;
  equine_id uuid;
  second_equine_id uuid;
  future_equine_id uuid;
  ended_equine_id uuid;
  center_id uuid;
  ownership_id uuid;
begin
  if exists (
    select 1
      from information_schema.columns
     where table_schema = 'public'
       and table_name = 'equines'
       and column_name in (
         'owner_id',
         'manager_id',
         'center_id',
         'auth_user_id'
       )
  ) then
    raise exception 'Equines must not carry owner, manager or center shortcuts';
  end if;

  if exists (
    select 1
      from information_schema.tables
     where table_schema = 'public'
       and table_name in (
         'equine_center_assignments',
         'equine_center_permissions',
         'disciplines',
         'bookings'
       )
  ) then
    raise exception 'Later domains must remain deferred';
  end if;

  if exists (
    select 1
      from information_schema.parameters
     where specific_schema = 'public'
       and specific_name like 'list_my_equine_ownerships%'
       and parameter_name = 'p_person_id'
  ) then
    raise exception 'Ownership list must not accept a caller-supplied person_id';
  end if;

  if exists (
    select 1
      from pg_catalog.pg_proc as procedure
      join pg_catalog.pg_namespace as namespace
        on namespace.oid = procedure.pronamespace
     where namespace.nspname = 'public'
       and procedure.proname in (
         'assign_equine_owner',
         'grant_equine_management',
         'create_equine_ownership',
         'self_assign_equine_manager'
       )
  ) then
    raise exception 'Ownership or management mutation RPC must not exist';
  end if;

  if (
    select count(*)
      from pg_catalog.pg_class
     where oid in (
       'public.equine_ownerships'::regclass,
       'public.equine_management_assignments'::regclass
     )
       and relrowsecurity
  ) <> 2 then
    raise exception 'Ownership/management RLS is not enabled';
  end if;

  if exists (
    select 1
      from pg_catalog.pg_policy
     where polrelid in (
       'public.equine_ownerships'::regclass,
       'public.equine_management_assignments'::regclass
     )
  ) then
    raise exception 'Ownership tables unexpectedly gained client RLS policies';
  end if;

  select person_id into caller_person_id
    from public.user_accounts
   where auth_user_id = '80000000-0000-0000-0000-000000000001';

  select person_id into other_person_id
    from public.user_accounts
   where auth_user_id = '80000000-0000-0000-0000-000000000002';

  update public.persons
     set first_name = 'Owner', last_name = 'One', date_of_birth = date '1988-01-01'
   where id = caller_person_id;

  update public.persons
     set first_name = 'Owner', last_name = 'Two', date_of_birth = date '1989-01-01'
   where id = other_person_id;

  insert into public.persons (first_name, last_name, date_of_birth)
  values ('Unlinked', 'Phase4AUnlinked', date '1984-01-01')
  returning id into unlinked_person_id;

  insert into public.equestrian_centers (name, slug, country_code)
  values ('Phase4A Yard', 'phase4a-yard', 'ZF')
  returning id into center_id;

  insert into public.center_memberships (
    center_id, person_id, role_code
  ) values (
    center_id, caller_person_id, 'ADMIN'
  );

  insert into public.equines (name, equine_type)
  values ('phase4a-horse', 'HORSE')
  returning id into equine_id;

  insert into public.equines (name, equine_type)
  values ('phase4a-pony', 'PONY')
  returning id into second_equine_id;

  insert into public.equines (name, equine_type)
  values ('phase4a-future', 'HORSE')
  returning id into future_equine_id;

  insert into public.equines (name, equine_type)
  values ('phase4a-ended', 'PONY')
  returning id into ended_equine_id;

  if public.has_active_equine_management_role(
    caller_person_id, equine_id, 'PRIMARY_MANAGER'
  ) then
    raise exception 'Center membership created management authority';
  end if;

  begin
    insert into public.equine_ownerships (
      equine_id, owner_type, owner_person_id, owner_center_id, ownership_percentage
    ) values (
      equine_id, 'PERSON', caller_person_id, center_id, 50
    );
    raise exception 'Ownership with both FKs was allowed';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.equine_ownerships (
      equine_id, owner_type, ownership_percentage
    ) values (
      equine_id, 'PERSON', 50
    );
    raise exception 'Ownership with no owner FK was allowed';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.equine_ownerships (
      equine_id, owner_type, owner_center_id, ownership_percentage
    ) values (
      equine_id, 'PERSON', center_id, 50
    );
    raise exception 'Ownership type/FK mismatch was allowed';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.equine_ownerships (
      equine_id, owner_type, owner_person_id, ownership_percentage
    ) values (
      equine_id, 'PERSON', caller_person_id, 0
    );
    raise exception 'Zero ownership percentage was allowed';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.equine_ownerships (
      equine_id, owner_type, owner_person_id, ownership_percentage
    ) values (
      equine_id, 'PERSON', caller_person_id, 101
    );
    raise exception 'Ownership percentage above 100 was allowed';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.equine_ownerships (
      equine_id, owner_type, owner_person_id, ownership_percentage, status
    ) values (
      equine_id, 'PERSON', caller_person_id, 40, 'INVITED'
    );
    raise exception 'INVITED ownership status was allowed';
  exception
    when check_violation then null;
  end;

  insert into public.equine_ownerships (
    equine_id, owner_type, owner_person_id, ownership_percentage
  ) values (
    equine_id, 'PERSON', caller_person_id, 60
  )
  returning id into ownership_id;

  insert into public.equine_ownerships (
    equine_id, owner_type, owner_person_id, ownership_percentage
  ) values (
    equine_id, 'PERSON', other_person_id, 60
  );

  begin
    insert into public.equine_ownerships (
      equine_id, owner_type, owner_person_id, ownership_percentage
    ) values (
      equine_id, 'PERSON', caller_person_id, 10
    );
    raise exception 'Duplicate active person ownership was allowed';
  exception
    when unique_violation then null;
  end;

  insert into public.equine_ownerships (
    equine_id, owner_type, owner_center_id, ownership_percentage
  ) values (
    second_equine_id, 'CENTER', center_id, 100
  );

  begin
    insert into public.equine_management_assignments (
      equine_id, manager_type, manager_person_id, management_role,
      granted_by_person_id
    ) values (
      equine_id, 'PERSON', caller_person_id, 'OWNER', caller_person_id
    );
    raise exception 'Invalid management role was allowed';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.equine_management_assignments (
      equine_id, manager_type, manager_person_id, manager_center_id,
      management_role, granted_by_person_id
    ) values (
      equine_id, 'PERSON', caller_person_id, center_id,
      'AUTHORIZED_MANAGER', caller_person_id
    );
    raise exception 'Manager PERSON with both FKs was allowed';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.equine_management_assignments (
      equine_id, manager_type, management_role, granted_by_person_id
    ) values (
      equine_id, 'PERSON', 'AUTHORIZED_MANAGER', caller_person_id
    );
    raise exception 'Manager PERSON with neither FK was allowed';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.equine_management_assignments (
      equine_id, manager_type, management_role, granted_by_person_id
    ) values (
      equine_id, 'CENTER', 'AUTHORIZED_MANAGER', caller_person_id
    );
    raise exception 'Manager CENTER with neither FK was allowed';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.equine_management_assignments (
      equine_id, manager_type, manager_center_id, management_role,
      granted_by_person_id
    ) values (
      equine_id, 'PERSON', center_id, 'AUTHORIZED_MANAGER', caller_person_id
    );
    raise exception 'Manager type/FK mismatch was allowed';
  exception
    when check_violation then null;
  end;

  insert into public.equine_management_assignments (
    equine_id, manager_type, manager_center_id, management_role,
    granted_by_person_id
  ) values (
    equine_id, 'CENTER', center_id, 'AUTHORIZED_MANAGER', caller_person_id
  );

  insert into public.equine_management_assignments (
    equine_id, manager_type, manager_person_id, management_role,
    granted_by_person_id
  ) values (
    equine_id, 'PERSON', caller_person_id, 'PRIMARY_MANAGER', caller_person_id
  );

  insert into public.equine_management_assignments (
    equine_id, manager_type, manager_person_id, management_role,
    granted_by_person_id
  ) values (
    equine_id, 'PERSON', other_person_id, 'CO_MANAGER', caller_person_id
  );

  begin
    insert into public.equine_management_assignments (
      equine_id, manager_type, manager_person_id, management_role,
      granted_by_person_id
    ) values (
      equine_id, 'PERSON', other_person_id, 'PRIMARY_MANAGER', caller_person_id
    );
    raise exception 'Second active PRIMARY_MANAGER was allowed';
  exception
    when unique_violation then null;
  end;

  if not public.has_active_equine_management_role(
    caller_person_id, equine_id, 'PRIMARY_MANAGER'
  ) then
    raise exception 'Caller is not the active PRIMARY_MANAGER';
  end if;

  begin
    insert into public.equine_ownerships (
      equine_id, owner_type, owner_person_id, ownership_percentage,
      status, started_at, ended_at
    ) values (
      ended_equine_id, 'PERSON', caller_person_id, 25, 'ENDED',
      timestamptz '2026-01-02 00:00:00+00',
      timestamptz '2026-01-01 00:00:00+00'
    );
    raise exception 'Ownership with ended_at before started_at was allowed';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.equine_management_assignments (
      equine_id, manager_type, manager_person_id, management_role,
      granted_by_person_id, status, valid_from, valid_until
    ) values (
      ended_equine_id, 'PERSON', caller_person_id, 'CO_MANAGER',
      caller_person_id, 'ENDED',
      timestamptz '2026-01-02 00:00:00+00',
      timestamptz '2026-01-01 00:00:00+00'
    );
    raise exception 'Management with valid_until before valid_from was allowed';
  exception
    when check_violation then null;
  end;

  insert into public.equine_ownerships (
    equine_id, owner_type, owner_person_id, ownership_percentage,
    status, started_at, ended_at
  ) values (
    ended_equine_id, 'PERSON', caller_person_id, 40, 'ENDED',
    timestamptz '2025-01-01 00:00:00+00',
    timestamptz '2025-06-01 00:00:00+00'
  );

  insert into public.equine_management_assignments (
    equine_id, manager_type, manager_person_id, management_role,
    granted_by_person_id, status, valid_from, valid_until
  ) values (
    ended_equine_id, 'PERSON', caller_person_id, 'CO_MANAGER',
    caller_person_id, 'ENDED',
    timestamptz '2025-01-01 00:00:00+00',
    timestamptz '2025-06-01 00:00:00+00'
  );

  if not exists (
    select 1
      from public.equine_ownerships as ownership
     where ownership.equine_id = ended_equine_id
       and ownership.owner_person_id = caller_person_id
       and ownership.status = 'ENDED'
       and ownership.ended_at is not null
  ) then
    raise exception 'Valid historical ENDED ownership was not preserved';
  end if;

  if not exists (
    select 1
      from public.equine_management_assignments as assignment
     where assignment.equine_id = ended_equine_id
       and assignment.manager_person_id = caller_person_id
       and assignment.status = 'ENDED'
       and assignment.valid_until is not null
  ) then
    raise exception 'Valid historical ENDED management was not preserved';
  end if;

  insert into public.equine_ownerships (
    equine_id, owner_type, owner_person_id, ownership_percentage, started_at
  ) values (
    future_equine_id, 'PERSON', caller_person_id, 100,
    now() + interval '7 days'
  );

  insert into public.equine_management_assignments (
    equine_id, manager_type, manager_person_id, management_role,
    granted_by_person_id, valid_from
  ) values (
    future_equine_id, 'PERSON', caller_person_id, 'PRIMARY_MANAGER',
    caller_person_id, now() + interval '7 days'
  );

  if public.has_active_equine_management_role(
    caller_person_id, future_equine_id, 'PRIMARY_MANAGER'
  ) then
    raise exception 'Future management assignment was treated as effective';
  end if;

  perform set_config('app.caller_person', caller_person_id::text, true);
  perform set_config('app.other_person', other_person_id::text, true);
  perform set_config('app.unlinked_person', unlinked_person_id::text, true);
  perform set_config('app.equine_id', equine_id::text, true);
  perform set_config('app.second_equine_id', second_equine_id::text, true);
  perform set_config('app.future_equine_id', future_equine_id::text, true);
  perform set_config('app.ended_equine_id', ended_equine_id::text, true);
  perform set_config('app.center_id', center_id::text, true);
  perform set_config('app.ownership_id', ownership_id::text, true);
end;
$$;

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '80000000-0000-0000-0000-000000000001',
  true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"80000000-0000-0000-0000-000000000001"}',
  true
);

do $$
declare
  listed_count integer;
  other_owner_seen boolean;
  center_share_seen boolean;
begin
  begin
    perform * from public.equine_ownerships;
    raise exception 'Authenticated role selected ownerships';
  exception
    when insufficient_privilege then null;
  end;

  begin
    insert into public.equine_ownerships (
      equine_id, owner_type, owner_person_id, ownership_percentage
    ) values (
      current_setting('app.equine_id', true)::uuid,
      'PERSON',
      current_setting('app.caller_person', true)::uuid,
      5
    );
    raise exception 'Authenticated role inserted ownership';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform * from public.equine_management_assignments;
    raise exception 'Authenticated role selected management assignments';
  exception
    when insufficient_privilege then null;
  end;

  begin
    update public.equine_ownerships
       set ownership_percentage = 1;
    raise exception 'Authenticated role updated ownerships';
  exception
    when insufficient_privilege then null;
  end;

  begin
    delete from public.equine_ownerships;
    raise exception 'Authenticated role deleted ownerships';
  exception
    when insufficient_privilege then null;
  end;

  begin
    update public.equine_management_assignments
       set management_role = 'CO_MANAGER';
    raise exception 'Authenticated role updated management assignments';
  exception
    when insufficient_privilege then null;
  end;

  begin
    delete from public.equine_management_assignments;
    raise exception 'Authenticated role deleted management assignments';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform public.has_active_equine_management_role(
      current_setting('app.caller_person', true)::uuid,
      current_setting('app.equine_id', true)::uuid,
      'PRIMARY_MANAGER'
    );
    raise exception 'Authenticated role executed internal management helper';
  exception
    when insufficient_privilege then null;
  end;

  select count(*) into listed_count from public.list_my_equine_ownerships();
  if listed_count <> 3 then
    raise exception 'Caller did not receive only their ownership rows';
  end if;

  if not exists (
    select 1
      from public.list_my_equine_ownerships() as listed
     where listed.equine_name = 'phase4a-horse'
       and listed.status = 'ACTIVE'
       and listed.is_currently_effective
  ) then
    raise exception 'Current ownership was not listed as effective';
  end if;

  if not exists (
    select 1
      from public.list_my_equine_ownerships() as listed
     where listed.equine_name = 'phase4a-future'
       and listed.status = 'ACTIVE'
       and not listed.is_currently_effective
  ) then
    raise exception 'Future ownership displayed as currently effective';
  end if;

  if not exists (
    select 1
      from public.list_my_equine_ownerships() as listed
     where listed.equine_name = 'phase4a-ended'
       and listed.status = 'ENDED'
       and not listed.is_currently_effective
  ) then
    raise exception 'Historical ENDED ownership was not listed as stored history';
  end if;

  select exists (
    select 1
      from public.list_my_equine_ownerships() as listed
     where listed.ownership_percentage = 60
       and listed.equine_name = 'phase4a-horse'
       and listed.owner_type <> 'PERSON'
  ) into other_owner_seen;

  if other_owner_seen then
    raise exception 'Ownership RPC exposed a non-person owner type';
  end if;

  select exists (
    select 1
      from public.list_my_equine_ownerships() as listed
     where listed.equine_name = 'phase4a-pony'
  ) into center_share_seen;

  if center_share_seen then
    raise exception 'Person caller saw a CENTER-owned equine';
  end if;

  select count(*) into listed_count
    from public.list_my_equine_management_assignments();

  if listed_count <> 3 then
    raise exception 'Caller did not receive only their management assignments';
  end if;

  if not exists (
    select 1
      from public.list_my_equine_management_assignments() as listed
     where listed.equine_name = 'phase4a-horse'
       and listed.management_role = 'PRIMARY_MANAGER'
       and listed.is_currently_effective
  ) then
    raise exception 'Current management was not listed as effective';
  end if;

  if not exists (
    select 1
      from public.list_my_equine_management_assignments() as listed
     where listed.equine_name = 'phase4a-future'
       and listed.status = 'ACTIVE'
       and not listed.is_currently_effective
  ) then
    raise exception 'Future management displayed as currently effective';
  end if;

  if not exists (
    select 1
      from public.list_my_equine_management_assignments() as listed
     where listed.equine_name = 'phase4a-ended'
       and listed.status = 'ENDED'
       and not listed.is_currently_effective
  ) then
    raise exception 'Historical ENDED management was not listed as stored history';
  end if;

  if exists (
    select 1
      from public.list_my_equine_management_assignments() as listed
     where listed.management_role = 'CO_MANAGER'
       and listed.equine_name = 'phase4a-horse'
  ) then
    raise exception 'Caller enumerated another person management assignment';
  end if;
end;
$$;

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '80000000-0000-0000-0000-000000000002',
  true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"80000000-0000-0000-0000-000000000002"}',
  true
);

do $$
declare
  listed_count integer;
  role_codes text;
begin
  select count(*) into listed_count from public.list_my_equine_ownerships();
  if listed_count <> 1 then
    raise exception 'Second caller did not receive only their ownership';
  end if;

  select count(*) into listed_count
    from public.list_my_equine_management_assignments();
  if listed_count <> 1 then
    raise exception 'Second caller did not receive only their management row';
  end if;

  select string_agg(management_role, ',')
    into role_codes
    from public.list_my_equine_management_assignments();

  if role_codes is distinct from 'CO_MANAGER' then
    raise exception 'Second caller enumerated another person management';
  end if;
end;
$$;

set local role anon;
select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claims', '', true);

do $$
begin
  begin
    perform * from public.list_my_equine_ownerships();
    raise exception 'Anonymous role listed ownerships';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform * from public.equine_ownerships;
    raise exception 'Anonymous role selected ownerships';
  exception
    when insufficient_privilege then null;
  end;

  begin
    insert into public.equine_ownerships (
      equine_id, owner_type, owner_person_id, ownership_percentage
    ) values (
      current_setting('app.equine_id', true)::uuid,
      'PERSON',
      current_setting('app.caller_person', true)::uuid,
      15
    );
    raise exception 'Anonymous role inserted ownership';
  exception
    when insufficient_privilege then null;
  end;

  begin
    update public.equine_ownerships
       set status = 'ENDED',
           ended_at = now();
    raise exception 'Anonymous role updated ownerships';
  exception
    when insufficient_privilege then null;
  end;

  begin
    delete from public.equine_ownerships;
    raise exception 'Anonymous role deleted ownerships';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform * from public.equine_management_assignments;
    raise exception 'Anonymous role selected management assignments';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

reset role;

do $$
begin
  if has_table_privilege('anon', 'public.equine_ownerships', 'select')
     or has_table_privilege('authenticated', 'public.equine_ownerships', 'select')
     or has_table_privilege('anon', 'public.equine_management_assignments', 'select')
     or has_table_privilege(
          'authenticated',
          'public.equine_management_assignments',
          'insert'
        )
     or has_function_privilege(
          'public',
          'public.has_active_equine_management_role(uuid,uuid,text)',
          'execute'
        )
     or has_function_privilege(
          'anon',
          'public.has_active_equine_management_role(uuid,uuid,text)',
          'execute'
        )
     or has_function_privilege(
          'authenticated',
          'public.has_active_equine_management_role(uuid,uuid,text)',
          'execute'
        )
     or has_function_privilege(
          'anon',
          'public.list_my_equine_ownerships()',
          'execute'
        )
     or not has_function_privilege(
          'authenticated',
          'public.list_my_equine_ownerships()',
          'execute'
        )
  then
    raise exception 'Ownership privileges are not the 012 deny-by-default model';
  end if;
end;
$$;

rollback;
