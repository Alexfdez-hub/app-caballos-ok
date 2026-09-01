-- Phase 3D local centers foundation tests.
-- Assumes migrations 001-009 are applied and auth.uid() reads
-- request.jwt.claim.sub. Runnable without psql meta-commands.

begin;

do $$
declare
  fixture_auth uuid[] := array[
    '50000000-0000-0000-0000-000000000001'::uuid
  ];
  linked_person_ids uuid[];
begin
  delete from public.center_languages
   where center_id in (
     select id from public.equestrian_centers where slug like 'phase3d-%'
   );

  delete from public.equestrian_centers
   where slug like 'phase3d-%';

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
   where id = any(linked_person_ids);

  delete from public.market_age_rules
   where country_code = 'ZC';

  delete from public.markets
   where country_code = 'ZC';

  delete from auth.users
   where id = any(fixture_auth);
end;
$$;

insert into public.markets (country_code, status)
values ('ZC', 'ACTIVE');

insert into auth.users (id)
values ('50000000-0000-0000-0000-000000000001');

do $$
declare
  center_id uuid;
  other_center_id uuid;
begin
  if exists (
    select 1
      from information_schema.columns
     where table_schema = 'public'
       and table_name = 'equestrian_centers'
       and column_name in (
         'auth_user_id',
         'owner_auth_user_id',
         'manager_person_id',
         'is_center',
         'role'
       )
  ) then
    raise exception 'Center owner shortcut or account-level center role must not exist';
  end if;

  if exists (
    select 1
      from information_schema.columns
     where table_schema = 'public'
       and table_name in ('persons', 'user_accounts')
       and column_name in ('is_center', 'role')
  ) then
    raise exception 'Account-level is_center or users.role must not exist';
  end if;

  if exists (
    select 1
      from information_schema.tables
     where table_schema = 'public'
       and table_name in (
         'center_memberships',
         'rider_assessments',
         'equines',
         'center_services',
         'bookings'
       )
  ) then
    raise exception 'Later center domains must remain deferred';
  end if;

  if (
    select count(*)
      from pg_catalog.pg_class
     where oid in (
       'public.equestrian_centers'::regclass,
       'public.center_languages'::regclass
     )
       and relrowsecurity
  ) <> 2 then
    raise exception 'Center RLS is not enabled';
  end if;

  if exists (
    select 1
      from pg_catalog.pg_policy
     where polrelid in (
       'public.equestrian_centers'::regclass,
       'public.center_languages'::regclass
     )
  ) then
    raise exception 'Center tables unexpectedly gained client RLS policies';
  end if;

  insert into public.equestrian_centers (
    name,
    slug,
    country_code,
    latitude,
    longitude,
    timezone,
    default_currency
  ) values (
    'Pilot Center',
    'phase3d-pilot',
    'ZC',
    40.4,
    -3.7,
    'Europe/Madrid',
    'EUR'
  ) returning id into center_id;

  if pg_typeof(center_id) is distinct from 'uuid'::regtype then
    raise exception 'Center primary key is not uuid';
  end if;

  insert into public.center_languages (center_id, locale)
  values (center_id, 'es'), (center_id, 'en-US');

  begin
    insert into public.equestrian_centers (name, slug, country_code)
    values ('   ', 'phase3d-empty-name', 'ZC');
    raise exception 'Empty center name was allowed';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.equestrian_centers (name, slug, country_code)
    values ('Duplicate slug', 'phase3d-pilot', 'ZC');
    raise exception 'Duplicate center slug was allowed';
  exception
    when unique_violation then null;
  end;

  begin
    insert into public.equestrian_centers (
      name, slug, country_code, latitude, longitude
    ) values ('Bad lat', 'phase3d-bad-lat', 'ZC', 91, 0);
    raise exception 'Invalid latitude was allowed';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.equestrian_centers (
      name, slug, country_code, latitude, longitude
    ) values ('Lon only', 'phase3d-lon-only', 'ZC', null, 10);
    raise exception 'Partial coordinates were allowed';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.equestrian_centers (
      name, slug, country_code, default_currency
    ) values ('Bad currency', 'phase3d-bad-currency', 'ZC', 'euro');
    raise exception 'Invalid currency was allowed';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.equestrian_centers (
      name, slug, country_code, verification_status
    ) values ('Bad verification', 'phase3d-bad-ver', 'ZC', 'APPROVED');
    raise exception 'Invalid verification status was allowed';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.equestrian_centers (
      name, slug, country_code, status
    ) values ('Bad status', 'phase3d-bad-status', 'ZC', 'PUBLIC');
    raise exception 'Invalid lifecycle status was allowed';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.center_languages (center_id, locale)
    values (center_id, 'es');
    raise exception 'Duplicate center locale was allowed';
  exception
    when unique_violation then null;
  end;

  begin
    insert into public.center_languages (center_id, locale)
    values ('00000000-0000-0000-0000-000000000000', 'fr');
    raise exception 'Language without a valid center was allowed';
  exception
    when foreign_key_violation then null;
  end;

  begin
    insert into public.center_languages (center_id, locale)
    values (center_id, 'ES-es');
    raise exception 'Invalid locale was allowed';
  exception
    when check_violation then null;
  end;

  insert into public.equestrian_centers (
    name, slug, country_code, status, verification_status
  ) values (
    'Draft unpublished',
    'phase3d-draft',
    'ZC',
    'DRAFT',
    'UNVERIFIED'
  ) returning id into other_center_id;

  perform set_config('app.center_id', center_id::text, true);
  perform set_config('app.draft_center_id', other_center_id::text, true);
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '50000000-0000-0000-0000-000000000001', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"50000000-0000-0000-0000-000000000001"}',
  true
);

do $$
begin
  begin
    perform * from public.equestrian_centers;
    raise exception 'Authenticated role selected centers directly';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform * from public.center_languages;
    raise exception 'Authenticated role selected center languages directly';
  exception
    when insufficient_privilege then null;
  end;

  begin
    insert into public.equestrian_centers (name, slug, country_code)
    values ('Self created', 'phase3d-self', 'ZC');
    raise exception 'Authenticated role created a center';
  exception
    when insufficient_privilege then null;
  end;

  begin
    update public.equestrian_centers
       set verification_status = 'VERIFIED';
    raise exception 'Authenticated role set a center to VERIFIED';
  exception
    when insufficient_privilege then null;
  end;

  begin
    update public.equestrian_centers
       set status = 'ACTIVE',
           name = 'Taken over';
    raise exception 'Authenticated role edited a center';
  exception
    when insufficient_privilege then null;
  end;

  begin
    delete from public.equestrian_centers;
    raise exception 'Authenticated role deleted centers';
  exception
    when insufficient_privilege then null;
  end;

  begin
    insert into public.center_languages (center_id, locale)
    values (current_setting('app.center_id', true)::uuid, 'fr');
    raise exception 'Authenticated role assigned a center language';
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
    perform * from public.equestrian_centers;
    raise exception 'Anonymous role selected centers';
  exception
    when insufficient_privilege then null;
  end;

  begin
    insert into public.equestrian_centers (name, slug, country_code)
    values ('Anon center', 'phase3d-anon', 'ZC');
    raise exception 'Anonymous role created a center';
  exception
    when insufficient_privilege then null;
  end;

  begin
    update public.equestrian_centers
       set verification_status = 'VERIFIED';
    raise exception 'Anonymous role verified a center';
  exception
    when insufficient_privilege then null;
  end;

  begin
    delete from public.equestrian_centers;
    raise exception 'Anonymous role deleted centers';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

reset role;

do $$
declare
  membership_count integer;
  assessment_exists boolean;
begin
  select count(*) into membership_count
    from information_schema.tables
   where table_schema = 'public'
     and table_name = 'center_memberships';

  if membership_count <> 0 then
    raise exception 'Creating a center created memberships';
  end if;

  if exists (
    select 1
      from public.policy_acceptances as acceptance
      join public.user_accounts as account
        on account.id = acceptance.user_account_id
     where account.auth_user_id = '50000000-0000-0000-0000-000000000001'
  ) then
    raise exception 'Creating a center created policy acceptance';
  end if;

  select exists (
    select 1
      from information_schema.tables
     where table_schema = 'public'
       and table_name = 'rider_assessments'
  ) into assessment_exists;

  if assessment_exists then
    raise exception 'Creating a center created assessments';
  end if;

  if has_table_privilege('authenticated', 'public.equestrian_centers', 'select')
     or has_table_privilege('authenticated', 'public.equestrian_centers', 'insert')
     or has_table_privilege('authenticated', 'public.equestrian_centers', 'update')
     or has_table_privilege('authenticated', 'public.equestrian_centers', 'delete')
     or has_table_privilege('anon', 'public.equestrian_centers', 'select')
     or has_table_privilege('authenticated', 'public.center_languages', 'select')
     or has_table_privilege('anon', 'public.center_languages', 'select') then
    raise exception 'Center tables expose forbidden client privileges';
  end if;

  if exists (
    select 1
      from pg_catalog.pg_proc as procedure
      join pg_catalog.pg_namespace as namespace
        on namespace.oid = procedure.pronamespace
     where namespace.nspname = 'public'
       and procedure.proname like '%center%'
       and has_function_privilege('anon', procedure.oid, 'execute')
  ) then
    raise exception 'Anonymous execute was granted on a center function';
  end if;
end;
$$;

rollback;
