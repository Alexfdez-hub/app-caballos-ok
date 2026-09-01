-- Phase 3A local identity tests.
-- Assumes migrations 001-006 have been applied and auth.uid() reads
-- request.jwt.claim.sub / request.jwt.claims.
-- Runnable with `npx supabase db query --local -f` (no psql meta-commands).

begin;

do $$
declare
  fixture_ids uuid[] := array[
    '10000000-0000-0000-0000-000000000001'::uuid,
    '10000000-0000-0000-0000-000000000002'::uuid,
    '10000000-0000-0000-0000-000000000003'::uuid
  ];
  linked_person_ids uuid[];
begin
  select coalesce(array_agg(person_id), '{}')
    into linked_person_ids
    from public.user_accounts
   where auth_user_id = any(fixture_ids);

  delete from public.user_accounts
   where auth_user_id = any(fixture_ids);

  delete from public.persons
   where id = any(linked_person_ids);

  delete from auth.users
   where id = any(fixture_ids);
end;
$$;

insert into auth.users (id)
values
  ('10000000-0000-0000-0000-000000000001'),
  ('10000000-0000-0000-0000-000000000002');

do $$
declare
  unlinked_person_id uuid;
  fixture_account_count integer;
  fixture_linked_person_count integer;
begin
  select count(*)
    into fixture_account_count
    from public.user_accounts
   where auth_user_id in (
     '10000000-0000-0000-0000-000000000001',
     '10000000-0000-0000-0000-000000000002'
   );

  if fixture_account_count <> 2 then
    raise exception 'Expected one user account per Auth user';
  end if;

  select count(distinct person.id)
    into fixture_linked_person_count
    from public.persons as person
    join public.user_accounts as account on account.person_id = person.id
   where account.auth_user_id in (
     '10000000-0000-0000-0000-000000000001',
     '10000000-0000-0000-0000-000000000002'
   );

  if fixture_linked_person_count <> 2 then
    raise exception 'Expected one distinct linked person per Auth user';
  end if;

  insert into public.persons default values
    returning id into unlinked_person_id;

  if exists (
    select 1
      from public.user_accounts
     where person_id = unlinked_person_id
  ) then
    raise exception 'Persons without accounts must remain possible';
  end if;

  if exists (
    select 1
    from public.persons as person
    join public.user_accounts as account on account.person_id = person.id
    where account.auth_user_id in (
      '10000000-0000-0000-0000-000000000001',
      '10000000-0000-0000-0000-000000000002'
    )
      and (
        person.first_name is not null
        or person.last_name is not null
        or person.date_of_birth is not null
      )
  ) then
    raise exception 'Provisioning fabricated personal data';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_class
    where oid in ('public.persons'::regclass, 'public.user_accounts'::regclass)
      and relrowsecurity
    group by relrowsecurity
    having count(*) = 2
  ) then
    raise exception 'Identity RLS is not enabled';
  end if;

  if exists (
    select 1
    from pg_catalog.pg_policy
    where polrelid in (
      'public.persons'::regclass,
      'public.user_accounts'::regclass
    )
  ) then
    raise exception 'Identity tables unexpectedly gained client RLS policies';
  end if;

  if (
    select count(*)
    from pg_catalog.pg_proc as procedure
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'public'
      and procedure.proname in (
        'handle_new_identity_account',
        'ensure_my_identity',
        'complete_my_identity'
      )
      and procedure.prosecdef
      and procedure.proconfig @> array['search_path=pg_catalog, public']
  ) <> 3 then
    raise exception 'Identity functions lack required security settings';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_trigger
    where tgname = 'on_auth_user_identity_created'
      and tgrelid = 'auth.users'::regclass
      and not tgisinternal
  ) then
    raise exception 'Identity provisioning trigger is missing';
  end if;

  if exists (
    select 1
    from pg_catalog.pg_trigger
    where tgname = 'on_auth_user_created'
      and tgrelid = 'auth.users'::regclass
      and not tgisinternal
  ) then
    raise exception 'Legacy Auth trigger was recreated';
  end if;

  if has_table_privilege('authenticated', 'public.persons', 'select')
     or has_table_privilege('authenticated', 'public.persons', 'insert')
     or has_table_privilege('authenticated', 'public.persons', 'update')
     or has_table_privilege('authenticated', 'public.persons', 'delete')
     or has_table_privilege('authenticated', 'public.user_accounts', 'select')
     or has_table_privilege('authenticated', 'public.user_accounts', 'insert')
     or has_table_privilege('authenticated', 'public.user_accounts', 'update')
     or has_table_privilege('authenticated', 'public.user_accounts', 'delete')
     or has_table_privilege('anon', 'public.persons', 'select')
     or has_table_privilege('anon', 'public.user_accounts', 'select') then
    raise exception 'Identity tables expose forbidden client privileges';
  end if;

  if not has_function_privilege(
    'authenticated',
    'public.ensure_my_identity()',
    'execute'
  ) or not has_function_privilege(
    'authenticated',
    'public.complete_my_identity(text,text,date)',
    'execute'
  ) or has_function_privilege(
    'anon',
    'public.ensure_my_identity()',
    'execute'
  ) or has_function_privilege(
    'anon',
    'public.complete_my_identity(text,text,date)',
    'execute'
  ) or has_function_privilege(
    'authenticated',
    'public.handle_new_identity_account()',
    'execute'
  ) then
    raise exception 'Identity function grants are not least-privilege';
  end if;
end;
$$;

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '10000000-0000-0000-0000-000000000001',
  true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000001"}',
  true
);

do $$
declare
  first_result record;
  second_result record;
  completed_result record;
  other_result record;
begin
  select * into first_result from public.ensure_my_identity();
  select * into second_result from public.ensure_my_identity();

  if first_result.person_id is null
     or first_result.user_account_id is null
     or first_result.is_complete then
    raise exception 'Incomplete caller identity did not resolve correctly';
  end if;

  if first_result.person_id <> second_result.person_id
     or first_result.user_account_id <> second_result.user_account_id then
    raise exception 'Identity provisioning is not idempotent';
  end if;

  select * into completed_result
  from public.complete_my_identity('  Ana  ', '  Example  ', '2000-01-02');

  if completed_result.first_name <> 'Ana'
     or completed_result.last_name <> 'Example'
     or completed_result.date_of_birth <> date '2000-01-02'
     or not completed_result.is_complete then
    raise exception 'Profile completion returned unexpected values';
  end if;

  if completed_result.person_id <> first_result.person_id then
    raise exception 'Profile completion targeted a different person';
  end if;

  begin
    perform * from public.persons;
    raise exception 'Authenticated role read private persons directly';
  exception
    when insufficient_privilege then null;
  end;

  begin
    update public.persons
       set first_name = 'Taken over';
    raise exception 'Authenticated role modified persons directly';
  exception
    when insufficient_privilege then null;
  end;

  begin
    insert into public.user_accounts (auth_user_id, person_id)
    values (
      '10000000-0000-0000-0000-000000000002',
      '10000000-0000-0000-0000-000000000099'
    );
    raise exception 'Authenticated role inserted an arbitrary account link';
  exception
    when insufficient_privilege then null;
  end;

  begin
    update public.user_accounts
       set person_id = '10000000-0000-0000-0000-000000000099'
     where auth_user_id = '10000000-0000-0000-0000-000000000001';
    raise exception 'Authenticated role relinked an account';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform *
    from public.complete_my_identity('Ana', 'Example', current_date + 1);
    raise exception 'Future date of birth was accepted';
  exception
    when invalid_parameter_value then null;
  end;

  perform set_config(
    'request.jwt.claim.sub',
    '10000000-0000-0000-0000-000000000002',
    true
  );
  perform set_config(
    'request.jwt.claims',
    '{"sub":"10000000-0000-0000-0000-000000000002"}',
    true
  );

  select * into other_result from public.ensure_my_identity();

  if other_result.person_id = completed_result.person_id
     or other_result.is_complete
     or other_result.first_name is not null then
    raise exception 'Caller resolved an unrelated person identity';
  end if;
end;
$$;

set local role anon;
select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claims', '', true);

do $$
begin
  begin
    perform * from public.ensure_my_identity();
    raise exception 'Anonymous role executed identity resolution';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform * from public.complete_my_identity('Ana', 'Example', '2000-01-02');
    raise exception 'Anonymous role executed identity completion';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform * from public.persons;
    raise exception 'Anonymous role read private persons';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform * from public.user_accounts;
    raise exception 'Anonymous role read private user accounts';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

reset role;

insert into auth.users (id)
values ('10000000-0000-0000-0000-000000000003');

do $$
declare
  catchup_person_id uuid;
begin
  select person_id
    into catchup_person_id
    from public.user_accounts
   where auth_user_id = '10000000-0000-0000-0000-000000000003';

  if catchup_person_id is null then
    raise exception 'Trigger did not provision the third Auth user';
  end if;

  -- Simulate an Auth user created before the identity trigger existed.
  delete from public.user_accounts
   where auth_user_id = '10000000-0000-0000-0000-000000000003';
  delete from public.persons
   where id = catchup_person_id;

  if exists (
    select 1
    from public.user_accounts
    where auth_user_id = '10000000-0000-0000-0000-000000000003'
  ) then
    raise exception 'Catch-up fixture still has an account link';
  end if;
end;
$$;

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '10000000-0000-0000-0000-000000000003',
  true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000003"}',
  true
);

do $$
declare
  catchup_result record;
  catchup_again record;
begin
  select * into catchup_result from public.ensure_my_identity();
  select * into catchup_again from public.ensure_my_identity();

  if catchup_result.person_id is null
     or catchup_result.user_account_id is null
     or catchup_result.is_complete then
    raise exception 'Catch-up identity provisioning failed';
  end if;

  if catchup_result.person_id <> catchup_again.person_id
     or catchup_result.user_account_id <> catchup_again.user_account_id then
    raise exception 'Catch-up identity provisioning is not idempotent';
  end if;
end;
$$;

reset role;

do $$
begin
  if (
    select count(*)
    from public.user_accounts
    where auth_user_id in (
      '10000000-0000-0000-0000-000000000001',
      '10000000-0000-0000-0000-000000000002',
      '10000000-0000-0000-0000-000000000003'
    )
  ) <> 3 then
    raise exception 'Repeated calls created duplicate identity links';
  end if;

  if (
    select count(distinct person_id)
    from public.user_accounts
    where auth_user_id in (
      '10000000-0000-0000-0000-000000000001',
      '10000000-0000-0000-0000-000000000002',
      '10000000-0000-0000-0000-000000000003'
    )
  ) <> 3 then
    raise exception 'Distinct Auth users did not receive distinct persons';
  end if;

  if (
    select count(*)
    from public.persons as person
    join public.user_accounts as account on account.person_id = person.id
    where account.auth_user_id = '10000000-0000-0000-0000-000000000001'
      and person.first_name = 'Ana'
      and person.last_name = 'Example'
      and person.date_of_birth = date '2000-01-02'
  ) <> 1 then
    raise exception 'Caller profile was not updated exactly once';
  end if;

  if exists (
    select 1
    from public.persons as person
    join public.user_accounts as account on account.person_id = person.id
    where account.auth_user_id in (
      '10000000-0000-0000-0000-000000000002',
      '10000000-0000-0000-0000-000000000003'
    )
      and (
        person.first_name is not null
        or person.last_name is not null
        or person.date_of_birth is not null
      )
  ) then
    raise exception 'Profile completion modified an unrelated identity';
  end if;
end;
$$;

rollback;
