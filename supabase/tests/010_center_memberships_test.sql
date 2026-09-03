-- Phase 3E local center-membership tests.
-- Assumes migrations 001-010 are applied and auth.uid() reads
-- request.jwt.claim.sub. Compatible with 011 equines foundation.
-- Runnable without psql meta-commands.

begin;

do $$
declare
  fixture_auth uuid[] := array[
    '60000000-0000-0000-0000-000000000001'::uuid,
    '60000000-0000-0000-0000-000000000002'::uuid
  ];
  linked_person_ids uuid[];
  membership_center_ids uuid[];
begin
  select coalesce(array_agg(id), '{}')
    into membership_center_ids
    from public.equestrian_centers
   where slug like 'phase3e-%';

  delete from public.center_memberships
   where center_id = any(membership_center_ids)
      or person_id in (
        select person_id from public.user_accounts where auth_user_id = any(fixture_auth)
      )
      or person_id in (
        select id from public.persons where last_name in ('NoAccountMember', 'StaffTwo')
      );

  delete from public.center_languages
   where center_id = any(membership_center_ids);

  delete from public.equestrian_centers
   where id = any(membership_center_ids);

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
      or last_name in ('NoAccountMember', 'StaffTwo');

  delete from public.market_age_rules
   where country_code = 'ZD';

  delete from public.markets
   where country_code = 'ZD';

  delete from auth.users
   where id = any(fixture_auth);
end;
$$;

insert into public.markets (country_code, status)
values ('ZD', 'ACTIVE');

insert into auth.users (id)
values
  ('60000000-0000-0000-0000-000000000001'),
  ('60000000-0000-0000-0000-000000000002');

do $$
declare
  caller_person_id uuid;
  other_person_id uuid;
  unlinked_person_id uuid;
  center_a_id uuid;
  center_b_id uuid;
  membership_id uuid;
  ended_membership_id uuid;
  listed_count integer;
begin
  if exists (
    select 1
      from information_schema.columns
     where table_schema = 'public'
       and table_name in ('persons', 'user_accounts', 'equestrian_centers')
       and column_name in (
         'is_center_admin',
         'is_assessor',
         'is_center',
         'role'
       )
  ) then
    raise exception 'Account-level Center role flags must not exist';
  end if;

  if exists (
    select 1
      from information_schema.columns
     where table_schema = 'public'
       and table_name = 'center_memberships'
       and column_name in ('auth_user_id', 'user_account_id')
  ) then
    raise exception 'Membership identity must not use Auth or account UUIDs';
  end if;

  if exists (
    select 1
      from information_schema.parameters
     where specific_schema = 'public'
       and specific_name like 'list_my_center_memberships%'
       and parameter_name = 'p_person_id'
  ) then
    raise exception 'Membership list must not accept a caller-supplied person_id';
  end if;

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
         'reviews',
         'incidents',
         'audit_events'
       )
  ) then
    raise exception 'Later domains must remain deferred';
  end if;

  if exists (
    select 1
      from pg_catalog.pg_proc as procedure
      join pg_catalog.pg_namespace as namespace
        on namespace.oid = procedure.pronamespace
     where namespace.nspname = 'public'
       and procedure.proname in (
         'grant_center_role',
         'revoke_center_role',
         'create_center_membership',
         'upsert_my_center_membership',
         'bootstrap_center_admin',
         'assign_center_membership'
       )
  ) then
    raise exception 'First-admin or membership mutation RPC must not exist';
  end if;

  if not (
    select relrowsecurity
      from pg_catalog.pg_class
     where oid = 'public.center_memberships'::regclass
  ) then
    raise exception 'Membership RLS is not enabled';
  end if;

  if exists (
    select 1
      from pg_catalog.pg_policy
     where polrelid = 'public.center_memberships'::regclass
  ) then
    raise exception 'Memberships unexpectedly gained client RLS policies';
  end if;

  select person_id into caller_person_id
    from public.user_accounts
   where auth_user_id = '60000000-0000-0000-0000-000000000001';

  select person_id into other_person_id
    from public.user_accounts
   where auth_user_id = '60000000-0000-0000-0000-000000000002';

  update public.persons
     set first_name = 'Staff', last_name = 'One', date_of_birth = date '1988-01-01'
   where id = caller_person_id;

  update public.persons
     set first_name = 'Staff', last_name = 'Two', date_of_birth = date '1989-01-01'
   where id = other_person_id;

  insert into public.persons (first_name, last_name, date_of_birth)
  values ('Unlinked', 'NoAccountMember', date '1984-01-01')
  returning id into unlinked_person_id;

  insert into public.equestrian_centers (name, slug, country_code)
  values ('Alpha Yard', 'phase3e-alpha', 'ZD')
  returning id into center_a_id;

  insert into public.equestrian_centers (name, slug, country_code)
  values ('Beta Yard', 'phase3e-beta', 'ZD')
  returning id into center_b_id;

  begin
    insert into public.center_memberships (
      center_id, person_id, role_code
    ) values (
      '00000000-0000-0000-0000-000000000000',
      caller_person_id,
      'ADMIN'
    );
    raise exception 'Membership without a valid Center was allowed';
  exception
    when foreign_key_violation then null;
  end;

  begin
    insert into public.center_memberships (
      center_id, person_id, role_code
    ) values (
      center_a_id,
      '00000000-0000-0000-0000-000000000000',
      'ADMIN'
    );
    raise exception 'Membership without a valid person was allowed';
  exception
    when foreign_key_violation then null;
  end;

  begin
    insert into public.center_memberships (
      center_id, person_id, role_code
    ) values (
      center_a_id,
      caller_person_id,
      'OWNER'
    );
    raise exception 'Invalid membership role was allowed';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.center_memberships (
      center_id, person_id, role_code, status
    ) values (
      center_a_id,
      caller_person_id,
      'ADMIN',
      'INVITED'
    );
    raise exception 'Invalid membership status was allowed';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.center_memberships (
      center_id, person_id, role_code, status, ended_at
    ) values (
      center_a_id,
      caller_person_id,
      'ADMIN',
      'ACTIVE',
      now()
    );
    raise exception 'Active membership with ended_at was allowed';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.center_memberships (
      center_id, person_id, role_code, status, joined_at, ended_at
    ) values (
      center_a_id,
      caller_person_id,
      'ADMIN',
      'ENDED',
      now(),
      now() - interval '1 day'
    );
    raise exception 'Ended membership with ended_at before joined_at was allowed';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.center_memberships (
      center_id, person_id, role_code, status
    ) values (
      center_a_id,
      caller_person_id,
      'ADMIN',
      'ENDED'
    );
    raise exception 'Ended membership without ended_at was allowed';
  exception
    when check_violation then null;
  end;

  insert into public.center_memberships (
    center_id, person_id, role_code, status, joined_at, ended_at
  ) values (
    center_a_id,
    caller_person_id,
    'INSTRUCTOR',
    'ENDED',
    now() - interval '400 days',
    now() - interval '10 days'
  ) returning id into ended_membership_id;

  insert into public.center_memberships (
    center_id, person_id, role_code
  ) values (
    center_a_id,
    caller_person_id,
    'ADMIN'
  ) returning id into membership_id;

  begin
    insert into public.center_memberships (
      center_id, person_id, role_code
    ) values (
      center_a_id,
      caller_person_id,
      'ADMIN'
    );
    raise exception 'Duplicate active Center/person/role was allowed';
  exception
    when unique_violation then null;
  end;

  if not exists (
    select 1
      from public.center_memberships
     where id = ended_membership_id
       and status = 'ENDED'
  ) then
    raise exception 'Historical ended membership was not retained';
  end if;

  insert into public.center_memberships (
    center_id, person_id, role_code
  ) values (
    center_a_id,
    caller_person_id,
    'INSTRUCTOR'
  );

  insert into public.center_memberships (
    center_id, person_id, role_code
  ) values (
    center_b_id,
    caller_person_id,
    'ASSESSOR'
  );

  insert into public.center_memberships (
    center_id, person_id, role_code
  ) values (
    center_a_id,
    other_person_id,
    'MANAGER'
  );

  insert into public.center_memberships (
    center_id, person_id, role_code
  ) values (
    center_a_id,
    unlinked_person_id,
    'INSTRUCTOR'
  );

  if exists (
    select 1
      from public.center_memberships
     where id = membership_id
       and person_id = '60000000-0000-0000-0000-000000000001'
  ) then
    raise exception 'Membership identity used an Auth UUID as person_id';
  end if;

  if exists (
    select 1 from public.user_accounts where person_id = unlinked_person_id
  ) then
    raise exception 'A person must be able to exist without an Auth account';
  end if;

  if (
    select verification_status
      from public.equestrian_centers
     where id = center_a_id
  ) <> 'UNVERIFIED' then
    raise exception 'Creating a membership verified a Center';
  end if;

  select count(*) into listed_count
    from public.policy_acceptances
   where person_id in (caller_person_id, other_person_id, unlinked_person_id);

  if listed_count <> 0 then
    raise exception 'Creating a membership created policy acceptance';
  end if;

  if not public.has_active_center_role(caller_person_id, center_a_id, 'ADMIN') then
    raise exception 'Active-role helper missed a valid active membership';
  end if;

  if public.has_active_center_role(caller_person_id, center_a_id, 'INSTRUCTOR') is not true then
    raise exception 'Active second role at the same Center was not recognized';
  end if;

  if public.has_active_center_role(
       caller_person_id,
       center_a_id,
       'INSTRUCTOR'
     )
     and not exists (
       select 1
         from public.center_memberships
        where person_id = caller_person_id
          and center_id = center_a_id
          and role_code = 'INSTRUCTOR'
          and status = 'ENDED'
     ) then
    raise exception 'Historical instructor row was lost after a new active instructor row';
  end if;

  if public.has_active_center_role(caller_person_id, center_a_id, 'MANAGER') then
    raise exception 'Wrong role returned true';
  end if;

  if public.has_active_center_role(caller_person_id, center_b_id, 'ADMIN') then
    raise exception 'Center A role returned true for Center B';
  end if;

  if public.has_active_center_role(other_person_id, center_a_id, 'ADMIN') then
    raise exception 'Another person inherited an ADMIN role';
  end if;

  update public.center_memberships
     set status = 'ENDED',
         ended_at = now(),
         updated_at = now()
   where id = membership_id;

  if public.has_active_center_role(caller_person_id, center_a_id, 'ADMIN') then
    raise exception 'Ended membership still returned true';
  end if;

  if not exists (
    select 1 from public.center_memberships where id = membership_id
  ) then
    raise exception 'Ending a membership deleted the historical row';
  end if;

  update public.center_memberships
     set status = 'ACTIVE',
         ended_at = null,
         updated_at = now()
   where id = membership_id;

  perform set_config('app.caller_person', caller_person_id::text, true);
  perform set_config('app.other_person', other_person_id::text, true);
  perform set_config('app.unlinked_person', unlinked_person_id::text, true);
  perform set_config('app.center_a', center_a_id::text, true);
  perform set_config('app.center_b', center_b_id::text, true);
  perform set_config('app.admin_membership', membership_id::text, true);
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '60000000-0000-0000-0000-000000000001', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"60000000-0000-0000-0000-000000000001"}',
  true
);

do $$
declare
  listed_count integer;
  other_member_count integer;
  names text;
begin
  select count(*) into listed_count from public.list_my_center_memberships();
  if listed_count <> 4 then
    raise exception 'Caller did not receive exactly their own memberships';
  end if;

  select string_agg(distinct center_name, ',' order by center_name)
    into names
    from public.list_my_center_memberships();

  if names is distinct from 'Alpha Yard,Beta Yard' then
    raise exception 'Caller did not receive safe Center names';
  end if;

  select count(*) into other_member_count
    from public.list_my_center_memberships() as listed
   where listed.role_code = 'MANAGER';

  if other_member_count <> 0 then
    raise exception 'Caller enumerated another person membership';
  end if;

  if exists (
    select 1
      from public.list_my_center_memberships() as listed
     where listed.center_name is null
        or listed.role_code not in (
          'ADMIN',
          'MANAGER',
          'INSTRUCTOR',
          'ASSESSOR'
        )
  ) then
    raise exception 'Membership list returned unsafe or invalid fields';
  end if;

  begin
    perform public.has_active_center_role(
      current_setting('app.other_person', true)::uuid,
      current_setting('app.center_a', true)::uuid,
      'MANAGER'
    );
    raise exception 'Authenticated role executed the internal role helper';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform * from public.center_memberships;
    raise exception 'Authenticated role selected memberships directly';
  exception
    when insufficient_privilege then null;
  end;

  begin
    insert into public.center_memberships (
      center_id, person_id, role_code
    ) values (
      current_setting('app.center_a', true)::uuid,
      current_setting('app.caller_person', true)::uuid,
      'MANAGER'
    );
    raise exception 'Authenticated role inserted a membership';
  exception
    when insufficient_privilege then null;
  end;

  begin
    insert into public.center_memberships (
      center_id, person_id, role_code
    ) values (
      current_setting('app.center_a', true)::uuid,
      current_setting('app.caller_person', true)::uuid,
      'ADMIN'
    );
    raise exception 'Authenticated role self-assigned ADMIN';
  exception
    when insufficient_privilege then null;
  end;

  begin
    update public.center_memberships
       set person_id = current_setting('app.other_person', true)::uuid,
           center_id = current_setting('app.center_b', true)::uuid;
    raise exception 'Authenticated role reassigned a membership';
  exception
    when insufficient_privilege then null;
  end;

  begin
    update public.center_memberships
       set status = 'ENDED',
           ended_at = now()
     where id = current_setting('app.admin_membership', true)::uuid;

    update public.center_memberships
       set status = 'ACTIVE',
           ended_at = null
     where id = current_setting('app.admin_membership', true)::uuid;

    raise exception 'Authenticated role reactivated a membership';
  exception
    when insufficient_privilege then null;
  end;

  begin
    delete from public.center_memberships;
    raise exception 'Authenticated role deleted memberships';
  exception
    when insufficient_privilege then null;
  end;

  begin
    update public.equestrian_centers
       set verification_status = 'VERIFIED'
     where id = current_setting('app.center_a', true)::uuid;
    raise exception 'Membership path allowed a client to verify a Center';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

select set_config('request.jwt.claim.sub', '60000000-0000-0000-0000-000000000002', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"60000000-0000-0000-0000-000000000002"}',
  true
);

do $$
declare
  listed_count integer;
  role_codes text;
begin
  select count(*) into listed_count from public.list_my_center_memberships();
  if listed_count <> 1 then
    raise exception 'Second caller did not receive only their membership';
  end if;

  select string_agg(role_code, ',')
    into role_codes
    from public.list_my_center_memberships();

  if role_codes is distinct from 'MANAGER' then
    raise exception 'Second caller enumerated another person memberships';
  end if;
end;
$$;

set local role anon;
select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claims', '', true);

do $$
begin
  begin
    perform * from public.list_my_center_memberships();
    raise exception 'Anonymous role listed memberships';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform * from public.center_memberships;
    raise exception 'Anonymous role selected memberships';
  exception
    when insufficient_privilege then null;
  end;

  begin
    insert into public.center_memberships (
      center_id, person_id, role_code
    ) values (
      current_setting('app.center_a', true)::uuid,
      current_setting('app.caller_person', true)::uuid,
      'ADMIN'
    );
    raise exception 'Anonymous role inserted a membership';
  exception
    when insufficient_privilege then null;
  end;

  begin
    update public.center_memberships
       set status = 'ENDED',
           ended_at = now();
    raise exception 'Anonymous role updated memberships';
  exception
    when insufficient_privilege then null;
  end;

  begin
    delete from public.center_memberships;
    raise exception 'Anonymous role deleted memberships';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

reset role;

do $$
declare
  caller_person_id uuid := current_setting('app.caller_person', true)::uuid;
  center_a_id uuid := current_setting('app.center_a', true)::uuid;
  acceptance_count integer;
begin
  select count(*) into acceptance_count
    from public.policy_acceptances
   where person_id = caller_person_id;

  if acceptance_count <> 0 then
    raise exception 'Membership created Center or Assessor Policy acceptance';
  end if;

  if exists (
    select 1
      from public.policy_documents
     where policy_type in ('CENTER_POLICY', 'ASSESSOR_POLICY')
       and id in (
         select policy_document_id
           from public.policy_acceptances
          where person_id = caller_person_id
       )
  ) then
    raise exception 'Membership created policy documents or acceptances';
  end if;

  if has_table_privilege('authenticated', 'public.center_memberships', 'select')
     or has_table_privilege('authenticated', 'public.center_memberships', 'insert')
     or has_table_privilege('authenticated', 'public.center_memberships', 'update')
     or has_table_privilege('authenticated', 'public.center_memberships', 'delete')
     or has_table_privilege('anon', 'public.center_memberships', 'select')
     or has_table_privilege('anon', 'public.center_memberships', 'insert') then
    raise exception 'Memberships expose forbidden client privileges';
  end if;

  if has_function_privilege(
       'anon',
       'public.list_my_center_memberships()',
       'execute'
     )
     or has_function_privilege(
       'anon',
       'public.has_active_center_role(uuid,uuid,text)',
       'execute'
     )
     or has_function_privilege(
       'authenticated',
       'public.has_active_center_role(uuid,uuid,text)',
       'execute'
     )
     or not has_function_privilege(
       'authenticated',
       'public.list_my_center_memberships()',
       'execute'
     ) then
    raise exception 'Membership function grants are not least-privilege';
  end if;

  if (
    select count(*)
      from pg_catalog.pg_proc as procedure
      join pg_catalog.pg_namespace as namespace
        on namespace.oid = procedure.pronamespace
     where namespace.nspname = 'public'
       and procedure.proname in (
         'list_my_center_memberships',
         'has_active_center_role'
       )
       and procedure.prosecdef
       and procedure.proconfig @> array['search_path=pg_catalog, public']
  ) <> 2 then
    raise exception 'Membership functions lack required security settings';
  end if;

  if exists (
    select 1
      from information_schema.parameters
     where specific_schema = 'public'
       and specific_name like 'list_my_center_memberships%'
       and parameter_mode = 'OUT'
       and parameter_name in (
         'person_id',
         'auth_user_id',
         'verification_status',
         'latitude',
         'longitude',
         'address_line'
       )
  ) then
    raise exception 'Membership list exposes unsafe columns';
  end if;

  if (
    select verification_status
      from public.equestrian_centers
     where id = center_a_id
  ) <> 'UNVERIFIED' then
    raise exception 'Membership workflow verified a Center';
  end if;
end;
$$;

rollback;
