-- Phase 5B local qualifications foundation tests.
-- Assumes migrations 001-015. Assessments remain deferred.
-- Runnable without psql meta-commands.

begin;

do $$
declare
  fixture_auth uuid[] := array[
    '92000000-0000-0000-0000-000000000001'::uuid,
    '92000000-0000-0000-0000-000000000002'::uuid
  ];
  linked_person_ids uuid[];
  fixture_system_ids uuid[];
  fixture_level_ids uuid[];
  fixture_discipline_ids uuid[];
begin
  select coalesce(array_agg(id), '{}') into fixture_system_ids
    from public.qualification_systems where code like 'phase5b-%';
  select coalesce(array_agg(id), '{}') into fixture_level_ids
    from public.qualification_levels
   where qualification_system_id = any(fixture_system_ids)
      or code like 'phase5b-%';
  select coalesce(array_agg(id), '{}') into fixture_discipline_ids
    from public.disciplines where code like 'phase5b-%';

  delete from public.rider_qualifications
   where qualification_level_id = any(fixture_level_ids)
      or rider_person_id in (
        select person_id from public.user_accounts
         where auth_user_id = any(fixture_auth)
      );
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
  delete from public.policy_acceptances
   where user_account_id in (
     select id from public.user_accounts where auth_user_id = any(fixture_auth)
   );
  select coalesce(array_agg(person_id), '{}') into linked_person_ids
    from public.user_accounts where auth_user_id = any(fixture_auth);
  delete from public.user_accounts where auth_user_id = any(fixture_auth);
  delete from public.persons where id = any(linked_person_ids);
  delete from public.market_age_rules where country_code = 'ZI';
  delete from public.markets where country_code = 'ZI';
  delete from auth.users where id = any(fixture_auth);
end;
$$;

insert into public.markets (country_code, status) values ('ZI', 'ACTIVE');
insert into auth.users (id) values
  ('92000000-0000-0000-0000-000000000001'),
  ('92000000-0000-0000-0000-000000000002');

do $$
declare
  rider_person_id uuid;
  verifier_person_id uuid;
  fixture_system_id uuid;
  other_system_id uuid;
  fixture_level_id uuid;
  other_level_id uuid;
  fixture_discipline_id uuid;
  catalog_count integer;
  duplicate_order_level_id uuid;
begin
  if exists (
    select 1 from information_schema.tables
     where table_schema = 'public'
       and table_name in (
         'center_services',
         'zero_sessions',
         'rider_equine_authorizations',
         'bookings'
       )
  ) then
    raise exception 'Later domains must remain deferred';
  end if;

  if exists (
    select 1 from pg_catalog.pg_proc as procedure
      join pg_catalog.pg_namespace as namespace
        on namespace.oid = procedure.pronamespace
     where namespace.nspname = 'public'
       and procedure.proname in (
         'list_qualification_systems',
         'list_my_qualifications',
         'declare_rider_qualification',
         'verify_rider_qualification',
         'upsert_rider_qualification'
       )
  ) then
    raise exception 'Qualification catalog or mutation RPC must not exist';
  end if;

  if (
    select count(*) from pg_catalog.pg_class
     where oid in (
       'public.qualification_systems'::regclass,
       'public.qualification_levels'::regclass,
       'public.rider_qualifications'::regclass
     ) and relrowsecurity
  ) <> 3 then
    raise exception '015 RLS is not enabled';
  end if;

  if exists (
    select 1 from pg_catalog.pg_policy
     where polrelid in (
       'public.qualification_systems'::regclass,
       'public.qualification_levels'::regclass,
       'public.rider_qualifications'::regclass
     )
  ) then
    raise exception '015 tables unexpectedly gained client RLS policies';
  end if;

  select count(*) into catalog_count from public.qualification_systems;
  if catalog_count <> 0 then
    raise exception '015 must not seed qualification systems';
  end if;

  select count(*) into catalog_count from public.qualification_levels;
  if catalog_count <> 0 then
    raise exception '015 must not seed qualification levels';
  end if;

  if exists (
    select 1 from information_schema.tables
     where table_schema = 'public'
       and table_name ~* 'galope|equivalence'
  ) then
    raise exception '015 must not create Galope or equivalence tables';
  end if;

  if exists (
    select 1
      from information_schema.columns
     where table_schema = 'public'
       and table_name in ('persons', 'user_accounts', 'rider_profiles')
       and column_name in (
         'age',
         'role',
         'galope',
         'qualification_level',
         'riding_level'
       )
  ) then
    raise exception 'Account-level qualification fields must not exist';
  end if;

  select person_id into rider_person_id
    from public.user_accounts
   where auth_user_id = '92000000-0000-0000-0000-000000000001';

  select person_id into verifier_person_id
    from public.user_accounts
   where auth_user_id = '92000000-0000-0000-0000-000000000002';

  update public.persons
     set first_name = 'Rider', last_name = 'One', date_of_birth = date '1990-01-01'
   where id = rider_person_id;

  update public.persons
     set first_name = 'Verifier', last_name = 'Two', date_of_birth = date '1985-01-01'
   where id = verifier_person_id;

  insert into public.disciplines (code)
  values ('phase5b-fixture')
  returning id into fixture_discipline_id;

  begin
    insert into public.qualification_systems (code, name, country_code)
    values ('phase5b-orphan-market', 'Orphan', 'ZZ');
    raise exception 'System with invalid market FK was allowed';
  exception
    when foreign_key_violation then null;
  end;

  begin
    insert into public.qualification_systems (code, name, status)
    values ('phase5b-bad-status', 'Bad', 'ARCHIVED');
    raise exception 'Invalid system status was allowed';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.qualification_systems (code, name)
    values ('', 'Blank');
    raise exception 'Empty system code was allowed';
  exception
    when check_violation then null;
  end;

  insert into public.qualification_systems (
    code, name, country_code, issuing_organization
  ) values (
    'phase5b-fixture', 'Fixture system', 'ZI', 'Fixture issuer'
  )
  returning id into fixture_system_id;

  insert into public.qualification_systems (code, name)
  values ('phase5b-other', 'Other system')
  returning id into other_system_id;

  begin
    insert into public.qualification_systems (code, name)
    values ('phase5b-fixture', 'Duplicate');
    raise exception 'Duplicate system code was allowed';
  exception
    when unique_violation then null;
  end;

  begin
    insert into public.qualification_levels (
      qualification_system_id, code, name
    ) values (
      '92000000-0000-0000-0000-000000000099'::uuid,
      'phase5b-orphan-level',
      'Orphan'
    );
    raise exception 'Level with invalid system FK was allowed';
  exception
    when foreign_key_violation then null;
  end;

  begin
    insert into public.qualification_levels (
      qualification_system_id, code, name, discipline_id
    ) values (
      fixture_system_id,
      'phase5b-bad-discipline',
      'Bad discipline',
      '92000000-0000-0000-0000-000000000098'::uuid
    );
    raise exception 'Level with invalid discipline FK was allowed';
  exception
    when foreign_key_violation then null;
  end;

  begin
    insert into public.qualification_levels (
      qualification_system_id, code, name, level_order
    ) values (
      fixture_system_id, 'phase5b-negative', 'Negative', -1
    );
    raise exception 'Negative level_order was allowed';
  exception
    when check_violation then null;
  end;

  insert into public.qualification_levels (
    qualification_system_id, code, name, level_order, discipline_id
  ) values (
    fixture_system_id, 'phase5b-l1', 'Level one', 10, fixture_discipline_id
  )
  returning id into fixture_level_id;

  insert into public.qualification_levels (
    qualification_system_id, code, name, level_order
  ) values (
    fixture_system_id, 'phase5b-l1-dup-order', 'Same order', 10
  )
  returning id into duplicate_order_level_id;

  if duplicate_order_level_id is null then
    raise exception 'Duplicate non-negative level_order was rejected';
  end if;

  insert into public.qualification_levels (
    qualification_system_id, code, name
  ) values (
    other_system_id, 'phase5b-l1', 'Same code other system'
  )
  returning id into other_level_id;

  if other_level_id is null then
    raise exception 'Same level code in another system was rejected';
  end if;

  begin
    insert into public.qualification_levels (
      qualification_system_id, code, name
    ) values (
      fixture_system_id, 'phase5b-l1', 'Duplicate scoped code'
    );
    raise exception 'Duplicate scoped level code was allowed';
  exception
    when unique_violation then null;
  end;

  begin
    insert into public.rider_qualifications (
      rider_person_id, qualification_level_id
    ) values (
      rider_person_id,
      '92000000-0000-0000-0000-000000000097'::uuid
    );
    raise exception 'Qualification with invalid level FK was allowed';
  exception
    when foreign_key_violation then null;
  end;

  begin
    insert into public.rider_qualifications (
      rider_person_id, qualification_level_id
    ) values (
      '92000000-0000-0000-0000-000000000096'::uuid,
      fixture_level_id
    );
    raise exception 'Qualification with invalid rider FK was allowed';
  exception
    when foreign_key_violation then null;
  end;

  begin
    insert into public.rider_qualifications (
      rider_person_id,
      qualification_level_id,
      issued_at,
      expires_at
    ) values (
      rider_person_id,
      fixture_level_id,
      timestamptz '2026-06-01 00:00:00+00',
      timestamptz '2026-05-01 00:00:00+00'
    );
    raise exception 'expires_at preceding issued_at was allowed';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.rider_qualifications (
      rider_person_id, qualification_level_id, verification_status
    ) values (
      rider_person_id, fixture_level_id, 'APPROVED'
    );
    raise exception 'Invalid verification status was allowed';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.rider_qualifications (
      rider_person_id,
      qualification_level_id,
      verification_status
    ) values (
      rider_person_id, fixture_level_id, 'VERIFIED'
    );
    raise exception 'VERIFIED without verifier was allowed';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.rider_qualifications (
      rider_person_id,
      qualification_level_id,
      verification_status,
      verified_by_person_id
    ) values (
      rider_person_id,
      fixture_level_id,
      'VERIFIED',
      rider_person_id
    );
    raise exception 'Self-verification was allowed';
  exception
    when check_violation then null;
  end;

  insert into public.rider_qualifications (
    rider_person_id,
    qualification_level_id,
    certificate_number,
    issued_at,
    expires_at,
    verification_status,
    verified_by_person_id,
    document_path
  ) values (
    rider_person_id,
    fixture_level_id,
    'CERT-015',
    timestamptz '2026-01-01 00:00:00+00',
    timestamptz '2027-01-01 00:00:00+00',
    'VERIFIED',
    verifier_person_id,
    'qualification-documents/phase5b/fixture.pdf'
  );

  insert into public.rider_qualifications (
    rider_person_id,
    qualification_level_id,
    verification_status
  ) values (
    rider_person_id,
    other_level_id,
    'DECLARED'
  );

  perform set_config('app.rider_person_id', rider_person_id::text, true);
  perform set_config('app.verifier_person_id', verifier_person_id::text, true);
  perform set_config('app.level_id', fixture_level_id::text, true);
  perform set_config('app.system_id', fixture_system_id::text, true);
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '92000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claims', '{"sub":"92000000-0000-0000-0000-000000000001"}', true);

do $$
begin
  begin
    perform * from public.qualification_systems;
    raise exception 'Authenticated role selected qualification systems';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform * from public.qualification_levels;
    raise exception 'Authenticated role selected qualification levels';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform * from public.rider_qualifications;
    raise exception 'Authenticated role selected rider qualifications';
  exception
    when insufficient_privilege then null;
  end;

  begin
    insert into public.rider_qualifications (
      rider_person_id, qualification_level_id
    ) values (
      current_setting('app.rider_person_id', true)::uuid,
      current_setting('app.level_id', true)::uuid
    );
    raise exception 'Authenticated role inserted a rider qualification';
  exception
    when insufficient_privilege then null;
  end;

  begin
    update public.rider_qualifications
       set verification_status = 'VERIFIED',
           verified_by_person_id = current_setting('app.rider_person_id', true)::uuid;
    raise exception 'Authenticated role updated rider qualifications';
  exception
    when insufficient_privilege then null;
  end;

  begin
    delete from public.rider_qualifications;
    raise exception 'Authenticated role deleted rider qualifications';
  exception
    when insufficient_privilege then null;
  end;

  begin
    update public.qualification_systems
       set status = 'INACTIVE';
    raise exception 'Authenticated role updated qualification systems';
  exception
    when insufficient_privilege then null;
  end;

  begin
    delete from public.qualification_systems;
    raise exception 'Authenticated role deleted qualification systems';
  exception
    when insufficient_privilege then null;
  end;

  begin
    update public.qualification_levels
       set status = 'INACTIVE';
    raise exception 'Authenticated role updated qualification levels';
  exception
    when insufficient_privilege then null;
  end;

  begin
    delete from public.qualification_levels;
    raise exception 'Authenticated role deleted qualification levels';
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
    perform * from public.rider_qualifications;
    raise exception 'Anonymous role selected rider qualifications';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

reset role;

do $$
begin
  if has_table_privilege('anon', 'public.qualification_systems', 'select')
     or has_table_privilege('authenticated', 'public.qualification_systems', 'insert')
     or has_table_privilege('authenticated', 'public.qualification_systems', 'update')
     or has_table_privilege('authenticated', 'public.qualification_systems', 'delete')
     or has_table_privilege('anon', 'public.qualification_levels', 'select')
     or has_table_privilege('authenticated', 'public.qualification_levels', 'insert')
     or has_table_privilege('authenticated', 'public.qualification_levels', 'update')
     or has_table_privilege('authenticated', 'public.qualification_levels', 'delete')
     or has_table_privilege('anon', 'public.rider_qualifications', 'select')
     or has_table_privilege('authenticated', 'public.rider_qualifications', 'insert')
     or has_table_privilege('authenticated', 'public.rider_qualifications', 'update')
     or has_table_privilege('authenticated', 'public.rider_qualifications', 'delete')
  then
    raise exception '015 privileges are not deny-by-default';
  end if;
end;
$$;

rollback;
