-- Phase 3C local rider-profile tests.
-- Assumes migrations 001-008 are applied and auth.uid() reads
-- request.jwt.claim.sub. Runnable without psql meta-commands.

begin;

do $$
declare
  fixture_auth uuid[] := array[
    '40000000-0000-0000-0000-000000000001'::uuid,
    '40000000-0000-0000-0000-000000000002'::uuid
  ];
  linked_person_ids uuid[];
begin
  delete from public.rider_profiles
   where person_id in (
     select person_id from public.user_accounts where auth_user_id = any(fixture_auth)
   )
      or person_id in (
        select id from public.persons where last_name in ('NoAccountRider', 'MinorRider')
      );

  delete from public.guardian_relationships
   where guardian_person_id in (
     select person_id from public.user_accounts where auth_user_id = any(fixture_auth)
   )
      or minor_person_id in (
        select id from public.persons where last_name = 'MinorRider'
      );

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
      or last_name in ('NoAccountRider', 'MinorRider');

  delete from auth.users
   where id = any(fixture_auth);
end;
$$;

insert into auth.users (id)
values
  ('40000000-0000-0000-0000-000000000001'),
  ('40000000-0000-0000-0000-000000000002');

do $$
declare
  rider_person_id uuid;
  other_person_id uuid;
  unlinked_person_id uuid;
  minor_person_id uuid;
begin
  if exists (
    select 1
      from information_schema.columns
     where table_schema = 'public'
       and table_name in ('persons', 'user_accounts', 'rider_profiles')
       and column_name in (
         'is_rider',
         'role',
         'galope',
         'qualification_level',
         'riding_level'
       )
  ) then
    raise exception 'Account-level rider role or qualification fields must not exist';
  end if;

  if exists (
    select 1
      from information_schema.parameters
     where specific_schema = 'public'
       and specific_name like 'upsert_my_rider_profile%'
       and parameter_name = 'p_person_id'
  ) then
    raise exception 'Rider upsert must not accept a caller-supplied person_id';
  end if;

  if exists (
    select 1
      from information_schema.tables
     where table_schema = 'public'
       and table_name in (
         'sessions'
       )
  ) then
    raise exception 'Later passport domains must remain deferred';
  end if;

  if not (
    select relrowsecurity
      from pg_catalog.pg_class
     where oid = 'public.rider_profiles'::regclass
  ) then
    raise exception 'Rider profile RLS is not enabled';
  end if;

  if exists (
    select 1
      from pg_catalog.pg_policy
     where polrelid = 'public.rider_profiles'::regclass
  ) then
    raise exception 'Rider profiles unexpectedly gained client RLS policies';
  end if;

  select person_id into rider_person_id
    from public.user_accounts
   where auth_user_id = '40000000-0000-0000-0000-000000000001';

  select person_id into other_person_id
    from public.user_accounts
   where auth_user_id = '40000000-0000-0000-0000-000000000002';

  update public.persons
     set first_name = 'Rider', last_name = 'One', date_of_birth = date '1990-01-01'
   where id = rider_person_id;

  update public.persons
     set first_name = 'Rider', last_name = 'Two', date_of_birth = date '1991-01-01'
   where id = other_person_id;

  insert into public.persons (first_name, last_name, date_of_birth)
  values ('Unlinked', 'NoAccountRider', date '1985-01-01')
  returning id into unlinked_person_id;

  insert into public.persons (first_name, last_name, date_of_birth)
  values ('Minor', 'MinorRider', date '2015-01-01')
  returning id into minor_person_id;

  if exists (
    select 1 from public.user_accounts where person_id = unlinked_person_id
  ) then
    raise exception 'A person must be able to exist without an Auth account';
  end if;

  insert into public.rider_profiles (person_id, bio, profile_visibility)
  values (unlinked_person_id, 'Unlinked rider', 'PRIVATE');

  insert into public.rider_profiles (person_id, bio, profile_visibility)
  values (minor_person_id, 'Minor structural profile', 'PRIVATE');

  insert into public.guardian_relationships (
    guardian_person_id, minor_person_id, relationship_type, verification_status
  ) values (rider_person_id, minor_person_id, 'PARENT', 'PENDING');

  insert into public.rider_profiles (
    person_id, bio, experience_start_year, profile_visibility
  ) values (rider_person_id, 'Own profile', 2010, 'PRIVATE');

  if exists (
    select 1
      from public.rider_profiles
     where person_id = rider_person_id
       and person_id = '40000000-0000-0000-0000-000000000001'
  ) then
    raise exception 'Rider identity used an Auth UUID as person_id';
  end if;

  begin
    insert into public.rider_profiles (person_id, profile_visibility)
    values ('00000000-0000-0000-0000-000000000000', 'PRIVATE');
    raise exception 'Rider profile without a valid person was allowed';
  exception
    when foreign_key_violation then null;
  end;

  begin
    insert into public.rider_profiles (person_id, profile_visibility)
    values (rider_person_id, 'PRIVATE');
    raise exception 'Duplicate rider profiles were allowed';
  exception
    when unique_violation then null;
  end;

  begin
    insert into public.rider_profiles (person_id, profile_visibility)
    values (other_person_id, 'SECRET');
    raise exception 'Invalid visibility was allowed';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.rider_profiles (
      person_id, experience_start_year, profile_visibility
    ) values (other_person_id, 1800, 'PRIVATE');
    raise exception 'Invalid experience year was allowed';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.rider_profiles (
      person_id, experience_start_year, profile_visibility
    ) values (other_person_id, 2101, 'PRIVATE');
    raise exception 'Experience year above the documented bound was allowed';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.rider_profiles (person_id, bio, profile_visibility)
    values (other_person_id, repeat('x', 2001), 'PRIVATE');
    raise exception 'Oversized bio was allowed by the table';
  exception
    when check_violation then null;
  end;

  perform set_config('app.rider_person', rider_person_id::text, true);
  perform set_config('app.other_person', other_person_id::text, true);
  perform set_config('app.unlinked_person', unlinked_person_id::text, true);
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '40000000-0000-0000-0000-000000000001', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"40000000-0000-0000-0000-000000000001"}',
  true
);

do $$
declare
  profile_row record;
  listed_count integer;
begin
  select count(*) into listed_count from public.get_my_rider_profile();
  if listed_count <> 1 then
    raise exception 'Caller did not receive exactly their rider profile';
  end if;

  select * into profile_row from public.get_my_rider_profile();
  if profile_row.person_id is distinct from current_setting('app.rider_person', true)::uuid
     or profile_row.profile_visibility <> 'PRIVATE'
     or profile_row.experience_start_year <> 2010 then
    raise exception 'Caller could not read their rider profile';
  end if;

  if profile_row.person_id = '40000000-0000-0000-0000-000000000001' then
    raise exception 'Returned rider identity was the Auth UUID';
  end if;

  begin
    perform * from public.upsert_my_rider_profile('too late', 2099::smallint, 'PRIVATE');
    raise exception 'Future experience year was accepted by RPC';
  exception
    when invalid_parameter_value then null;
  end;

  begin
    perform * from public.upsert_my_rider_profile(repeat('x', 2001), 2010::smallint, 'PRIVATE');
    raise exception 'Oversized bio was accepted by RPC';
  exception
    when invalid_parameter_value then null;
  end;

  select * into profile_row
  from public.upsert_my_rider_profile('Updated bio', 2012::smallint, 'PUBLIC');

  if profile_row.bio <> 'Updated bio'
     or profile_row.experience_start_year <> 2012
     or profile_row.profile_visibility <> 'PUBLIC'
     or profile_row.person_id is distinct from current_setting('app.rider_person', true)::uuid then
    raise exception 'Caller could not update their rider profile';
  end if;

  begin
    perform * from public.rider_profiles;
    raise exception 'Authenticated role selected rider profiles directly';
  exception
    when insufficient_privilege then null;
  end;

  begin
    insert into public.rider_profiles (
      person_id, profile_visibility
    ) values (current_setting('app.other_person', true)::uuid, 'PRIVATE');
    raise exception 'Authenticated role created another person rider profile';
  exception
    when insufficient_privilege then null;
  end;

  begin
    update public.rider_profiles
       set person_id = current_setting('app.other_person', true)::uuid;
    raise exception 'Authenticated role transferred a rider profile';
  exception
    when insufficient_privilege then null;
  end;

  begin
    delete from public.rider_profiles;
    raise exception 'Authenticated role deleted rider profiles';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform * from public.upsert_my_rider_profile('x', 2010::smallint, 'SECRET');
    raise exception 'Invalid visibility was accepted by RPC';
  exception
    when invalid_parameter_value then null;
  end;
end;
$$;

select set_config('request.jwt.claim.sub', '40000000-0000-0000-0000-000000000002', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"40000000-0000-0000-0000-000000000002"}',
  true
);

do $$
declare
  listed_count integer;
  profile_row record;
begin
  select count(*) into listed_count from public.get_my_rider_profile();
  if listed_count <> 0 then
    raise exception 'Caller read another person rider profile';
  end if;

  select * into profile_row
  from public.upsert_my_rider_profile('Other rider', null::smallint, 'PRIVATE');

  if profile_row.person_id is distinct from current_setting('app.other_person', true)::uuid then
    raise exception 'Second caller did not create their own rider profile';
  end if;

  select count(*) into listed_count from public.get_my_rider_profile();
  if listed_count <> 1 then
    raise exception 'Second caller profile was not isolated to themselves';
  end if;
end;
$$;

set local role anon;
select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claims', '', true);

do $$
begin
  begin
    perform * from public.get_my_rider_profile();
    raise exception 'Anonymous role read rider profiles';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform * from public.upsert_my_rider_profile('anon', 2010::smallint, 'PRIVATE');
    raise exception 'Anonymous role created a rider profile';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform * from public.rider_profiles;
    raise exception 'Anonymous role selected rider profiles';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

reset role;

do $$
declare
  rider_person_id uuid := current_setting('app.rider_person', true)::uuid;
  acceptance_count integer;
  consent_count integer;
  relationship_count integer;
begin
  select count(*) into acceptance_count
    from public.policy_acceptances
   where person_id = rider_person_id;

  select count(*) into consent_count
    from public.guardian_consents
   where guardian_person_id = rider_person_id
      or minor_person_id = rider_person_id;

  select count(*) into relationship_count
    from public.guardian_relationships
   where guardian_person_id = rider_person_id;

  if acceptance_count <> 0 then
    raise exception 'Rider profile created policy acceptance';
  end if;

  if consent_count <> 0 then
    raise exception 'Rider profile created guardian consent';
  end if;

  if relationship_count <> 1 then
    raise exception 'Rider profile removed or replaced guardian relationships';
  end if;

  if has_table_privilege('authenticated', 'public.rider_profiles', 'select')
     or has_table_privilege('authenticated', 'public.rider_profiles', 'insert')
     or has_table_privilege('authenticated', 'public.rider_profiles', 'update')
     or has_table_privilege('authenticated', 'public.rider_profiles', 'delete')
     or has_table_privilege('anon', 'public.rider_profiles', 'select') then
    raise exception 'Rider profiles expose forbidden client privileges';
  end if;

  if has_function_privilege(
       'anon',
       'public.upsert_my_rider_profile(text,smallint,text)',
       'execute'
     )
     or not has_function_privilege(
       'authenticated',
       'public.get_my_rider_profile()',
       'execute'
     )
     or not has_function_privilege(
       'authenticated',
       'public.upsert_my_rider_profile(text,smallint,text)',
       'execute'
     ) then
    raise exception 'Rider function grants are not least-privilege';
  end if;

  if (
    select count(*)
      from pg_catalog.pg_proc as procedure
      join pg_catalog.pg_namespace as namespace
        on namespace.oid = procedure.pronamespace
     where namespace.nspname = 'public'
       and procedure.proname in (
         'get_my_rider_profile',
         'upsert_my_rider_profile'
       )
       and procedure.prosecdef
       and procedure.proconfig @> array['search_path=pg_catalog, public']
  ) <> 2 then
    raise exception 'Rider functions lack required security settings';
  end if;
end;
$$;

rollback;
