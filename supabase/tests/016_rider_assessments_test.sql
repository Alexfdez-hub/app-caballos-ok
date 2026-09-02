-- Phase 6A local rider-assessment foundation tests.
-- Assumes migrations 001-016. Zero Session / authorizations remain deferred.
-- Runnable without psql meta-commands.

begin;

do $$
declare
  fixture_auth uuid[] := array[
    '93000000-0000-0000-0000-000000000001'::uuid,
    '93000000-0000-0000-0000-000000000002'::uuid,
    '93000000-0000-0000-0000-000000000003'::uuid
  ];
  linked_person_ids uuid[];
  fixture_center_ids uuid[];
  fixture_equine_ids uuid[];
  fixture_discipline_ids uuid[];
  fixture_assessment_ids uuid[];
begin
  select coalesce(array_agg(id), '{}') into fixture_center_ids
    from public.equestrian_centers where slug like 'phase6a-%';
  select coalesce(array_agg(id), '{}') into fixture_equine_ids
    from public.equines where name like 'phase6a-%';
  select coalesce(array_agg(id), '{}') into fixture_discipline_ids
    from public.disciplines where code like 'phase6a-%';
  select coalesce(array_agg(id), '{}') into fixture_assessment_ids
    from public.rider_assessments where center_id = any(fixture_center_ids);

  delete from public.rider_assessment_restrictions
   where assessment_id = any(fixture_assessment_ids);
  delete from public.rider_assessment_disciplines
   where assessment_id = any(fixture_assessment_ids);
  delete from public.rider_assessments
   where id = any(fixture_assessment_ids);
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
  delete from public.center_memberships
   where center_id = any(fixture_center_ids);
  delete from public.center_languages
   where center_id = any(fixture_center_ids);
  delete from public.equestrian_centers
   where id = any(fixture_center_ids);
  delete from public.policy_acceptances
   where user_account_id in (
     select id from public.user_accounts where auth_user_id = any(fixture_auth)
   );
  select coalesce(array_agg(person_id), '{}') into linked_person_ids
    from public.user_accounts where auth_user_id = any(fixture_auth);
  delete from public.user_accounts where auth_user_id = any(fixture_auth);
  delete from public.persons where id = any(linked_person_ids);
  delete from public.market_age_rules where country_code = 'ZJ';
  delete from public.markets where country_code = 'ZJ';
  delete from auth.users where id = any(fixture_auth);
end;
$$;

insert into public.markets (country_code, status) values ('ZJ', 'ACTIVE');
insert into auth.users (id) values
  ('93000000-0000-0000-0000-000000000001'),
  ('93000000-0000-0000-0000-000000000002'),
  ('93000000-0000-0000-0000-000000000003');

do $$
declare
  rider_person_id uuid;
  assessor_person_id uuid;
  other_person_id uuid;
  center_a_id uuid;
  center_b_id uuid;
  fixture_equine_id uuid;
  fixture_discipline_id uuid;
  kept_assessment_id uuid;
  cascade_assessment_id uuid;
  remaining_id uuid;
  child_count integer;
begin
  if exists (
    select 1 from information_schema.tables
     where table_schema = 'public'
       and table_name in (
         'sessions'
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
         'create_rider_assessment',
         'validate_rider_assessment',
         'list_my_assessments',
         'approve_zero_session'
       )
  ) then
    raise exception 'Assessment mutation or later-domain RPC must not exist';
  end if;

  if (
    select count(*) from pg_catalog.pg_class
     where oid in (
       'public.rider_assessments'::regclass,
       'public.rider_assessment_disciplines'::regclass,
       'public.rider_assessment_restrictions'::regclass
     ) and relrowsecurity
  ) <> 3 then
    raise exception '016 RLS is not enabled';
  end if;

  if exists (
    select 1 from pg_catalog.pg_policy
     where polrelid in (
       'public.rider_assessments'::regclass,
       'public.rider_assessment_disciplines'::regclass,
       'public.rider_assessment_restrictions'::regclass
     )
  ) then
    raise exception '016 tables unexpectedly gained client RLS policies';
  end if;

  select person_id into rider_person_id
    from public.user_accounts
   where auth_user_id = '93000000-0000-0000-0000-000000000001';
  select person_id into assessor_person_id
    from public.user_accounts
   where auth_user_id = '93000000-0000-0000-0000-000000000002';
  select person_id into other_person_id
    from public.user_accounts
   where auth_user_id = '93000000-0000-0000-0000-000000000003';

  update public.persons
     set first_name = 'Rider', last_name = 'One', date_of_birth = date '1992-01-01'
   where id = rider_person_id;
  update public.persons
     set first_name = 'Assessor', last_name = 'Two', date_of_birth = date '1980-01-01'
   where id = assessor_person_id;
  update public.persons
     set first_name = 'Other', last_name = 'Three', date_of_birth = date '1982-01-01'
   where id = other_person_id;

  insert into public.equestrian_centers (name, slug, country_code, status)
  values ('Phase6A Alpha', 'phase6a-alpha', 'ZJ', 'ACTIVE')
  returning id into center_a_id;

  insert into public.equestrian_centers (name, slug, country_code, status)
  values ('Phase6A Beta', 'phase6a-beta', 'ZJ', 'ACTIVE')
  returning id into center_b_id;

  insert into public.disciplines (code)
  values ('phase6a-fixture')
  returning id into fixture_discipline_id;

  insert into public.equines (name, equine_type)
  values ('phase6a-horse', 'HORSE')
  returning id into fixture_equine_id;

  insert into public.equine_center_permissions (
    equine_id, center_id, granted_by_person_id, permission_code
  ) values (
    fixture_equine_id, center_a_id, other_person_id, 'ASSESS_RIDERS'
  );

  begin
    insert into public.rider_assessments (
      rider_person_id, center_id, assessor_person_id, assessment_type
    ) values (
      rider_person_id, center_a_id, assessor_person_id, 'ACCESS_TEST'
    );
    raise exception 'Assessment without assessor membership was allowed';
  exception
    when insufficient_privilege then null;
  end;

  insert into public.center_memberships (
    center_id, person_id, role_code
  ) values (
    center_a_id, other_person_id, 'INSTRUCTOR'
  );

  begin
    insert into public.rider_assessments (
      rider_person_id, center_id, assessor_person_id, assessment_type
    ) values (
      rider_person_id, center_a_id, other_person_id, 'RIDING_LESSON'
    );
    raise exception 'INSTRUCTOR membership was treated as assessor authority';
  exception
    when insufficient_privilege then null;
  end;

  insert into public.center_memberships (
    center_id, person_id, role_code
  ) values (
    center_b_id, assessor_person_id, 'ASSESSOR'
  );

  begin
    insert into public.rider_assessments (
      rider_person_id, center_id, assessor_person_id, assessment_type
    ) values (
      rider_person_id, center_a_id, assessor_person_id, 'ACCESS_TEST'
    );
    raise exception 'Cross-center assessor authority was allowed';
  exception
    when insufficient_privilege then null;
  end;

  insert into public.center_memberships (
    center_id, person_id, role_code
  ) values (
    center_a_id, assessor_person_id, 'ASSESSOR'
  );

  begin
    insert into public.rider_assessments (
      rider_person_id, center_id, assessor_person_id, assessment_type
    ) values (
      assessor_person_id, center_a_id, assessor_person_id, 'ACCESS_TEST'
    );
    raise exception 'Self-assessment was allowed';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.rider_assessments (
      rider_person_id, center_id, assessor_person_id, assessment_type
    ) values (
      '93000000-0000-0000-0000-000000000099'::uuid,
      center_a_id,
      assessor_person_id,
      'ACCESS_TEST'
    );
    raise exception 'Assessment with invalid rider FK was allowed';
  exception
    when foreign_key_violation then null;
  end;

  begin
    insert into public.rider_assessments (
      rider_person_id, center_id, assessor_person_id, assessment_type
    ) values (
      rider_person_id,
      '93000000-0000-0000-0000-000000000098'::uuid,
      assessor_person_id,
      'ACCESS_TEST'
    );
    raise exception 'Assessment with invalid center FK was allowed';
  exception
    when foreign_key_violation then null;
    when insufficient_privilege then null;
  end;

  begin
    insert into public.rider_assessments (
      rider_person_id, center_id, assessor_person_id, assessment_type
    ) values (
      rider_person_id, center_a_id, assessor_person_id, 'SESSION_ZERO'
    );
    raise exception 'Invalid assessment type was allowed';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.rider_assessments (
      rider_person_id, center_id, assessor_person_id, assessment_type, status
    ) values (
      rider_person_id, center_a_id, assessor_person_id, 'ACCESS_TEST', 'APPROVED'
    );
    raise exception 'Invalid assessment status was allowed';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.rider_assessments (
      rider_person_id,
      center_id,
      assessor_person_id,
      assessment_type,
      performed_at,
      valid_until
    ) values (
      rider_person_id,
      center_a_id,
      assessor_person_id,
      'ACCESS_TEST',
      timestamptz '2026-06-01 00:00:00+00',
      timestamptz '2026-05-01 00:00:00+00'
    );
    raise exception 'valid_until preceding performed_at was allowed';
  exception
    when check_violation then null;
  end;

  insert into public.rider_assessments (
    rider_person_id,
    center_id,
    assessor_person_id,
    assessment_type,
    performed_at,
    valid_until,
    status,
    general_notes
  ) values (
    rider_person_id,
    center_a_id,
    assessor_person_id,
    'PRACTICAL_TEST',
    timestamptz '2026-04-01 00:00:00+00',
    timestamptz '2027-04-01 00:00:00+00',
    'VALID',
    'fixture assessment'
  )
  returning id into kept_assessment_id;

  insert into public.rider_assessment_disciplines (
    assessment_id, discipline_id, observed_level, supervision_required
  ) values (
    kept_assessment_id, fixture_discipline_id, 'observed note', true
  );

  begin
    insert into public.rider_assessment_disciplines (
      assessment_id, discipline_id
    ) values (
      kept_assessment_id, '93000000-0000-0000-0000-000000000098'::uuid
    );
    raise exception 'Discipline child with invalid discipline FK was allowed';
  exception
    when foreign_key_violation then null;
  end;

  insert into public.rider_assessment_restrictions (
    assessment_id, restriction_code, value_json, notes
  ) values (
    kept_assessment_id,
    'SUPERVISION',
    '{"required": true}'::jsonb,
    'fixture restriction'
  );

  begin
    insert into public.rider_assessment_restrictions (
      assessment_id, restriction_code, value_json
    ) values (
      kept_assessment_id, 'BAD_JSON', '[]'::jsonb
    );
    raise exception 'Non-object restriction value_json was allowed';
  exception
    when check_violation then null;
  end;

  insert into public.rider_assessments (
    rider_person_id, center_id, assessor_person_id, assessment_type, status
  ) values (
    rider_person_id, center_a_id, assessor_person_id, 'OTHER', 'DRAFT'
  )
  returning id into cascade_assessment_id;

  insert into public.rider_assessment_disciplines (
    assessment_id, discipline_id
  ) values (
    cascade_assessment_id, fixture_discipline_id
  );

  insert into public.rider_assessment_restrictions (
    assessment_id, restriction_code
  ) values (
    cascade_assessment_id, 'TEMP'
  );

  delete from public.rider_assessments where id = cascade_assessment_id;

  select count(*) into child_count
    from public.rider_assessment_disciplines as observation
   where observation.assessment_id = cascade_assessment_id;
  if child_count <> 0 then
    raise exception 'Discipline rows did not cascade on assessment delete';
  end if;

  select count(*) into child_count
    from public.rider_assessment_restrictions as restriction
   where restriction.assessment_id = cascade_assessment_id;
  if child_count <> 0 then
    raise exception 'Restriction rows did not cascade on assessment delete';
  end if;

  begin
    update public.rider_assessments
       set rider_person_id = other_person_id
     where id = kept_assessment_id;
    raise exception 'Historical rider identity rewrite was allowed';
  exception
    when insufficient_privilege then null;
  end;

  begin
    update public.rider_assessments
       set center_id = center_b_id
     where id = kept_assessment_id;
    raise exception 'Historical center identity rewrite was allowed';
  exception
    when insufficient_privilege then null;
  end;

  update public.center_memberships
     set status = 'ENDED',
         ended_at = now()
   where center_id = center_a_id
     and person_id = assessor_person_id
     and role_code = 'ASSESSOR'
     and status = 'ACTIVE';

  select id into remaining_id
    from public.rider_assessments
   where id = kept_assessment_id;

  if remaining_id is null then
    raise exception 'Historical assessment was removed after membership end';
  end if;

  begin
    update public.rider_assessments
       set status = 'REVOKED'
     where id = kept_assessment_id;
    raise exception 'Assessment mutation after membership end was allowed';
  exception
    when insufficient_privilege then null;
  end;

  begin
    insert into public.rider_assessment_disciplines (
      assessment_id, discipline_id
    ) values (
      kept_assessment_id, fixture_discipline_id
    );
    raise exception 'Child discipline insert after membership end was allowed';
  exception
    when unique_violation then
      raise exception 'Child discipline insert after membership end hit uniqueness instead of authority';
    when insufficient_privilege then null;
  end;

  begin
    update public.rider_assessment_restrictions as restriction
       set notes = 'rewritten after leave'
     where restriction.assessment_id = kept_assessment_id;
    raise exception 'Child restriction update after membership end was allowed';
  exception
    when insufficient_privilege then null;
  end;

  begin
    delete from public.rider_assessment_restrictions as restriction
     where restriction.assessment_id = kept_assessment_id;
    raise exception 'Child restriction delete after membership end was allowed';
  exception
    when insufficient_privilege then null;
  end;

  perform set_config('app.assessment_id', kept_assessment_id::text, true);
  perform set_config('app.center_a_id', center_a_id::text, true);
  perform set_config('app.discipline_id', fixture_discipline_id::text, true);
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '93000000-0000-0000-0000-000000000002', true);
select set_config('request.jwt.claims', '{"sub":"93000000-0000-0000-0000-000000000002"}', true);

do $$
begin
  begin
    perform * from public.rider_assessments;
    raise exception 'Authenticated role selected rider assessments';
  exception
    when insufficient_privilege then null;
  end;

  begin
    insert into public.rider_assessments (
      rider_person_id, center_id, assessor_person_id, assessment_type
    ) values (
      '93000000-0000-0000-0000-000000000001'::uuid,
      current_setting('app.center_a_id', true)::uuid,
      '93000000-0000-0000-0000-000000000002'::uuid,
      'ACCESS_TEST'
    );
    raise exception 'Authenticated role inserted a rider assessment';
  exception
    when insufficient_privilege then null;
  end;

  begin
    update public.rider_assessments
       set status = 'VALID';
    raise exception 'Authenticated role updated rider assessments';
  exception
    when insufficient_privilege then null;
  end;

  begin
    delete from public.rider_assessments;
    raise exception 'Authenticated role deleted rider assessments';
  exception
    when insufficient_privilege then null;
  end;

  begin
    insert into public.rider_assessment_disciplines (
      assessment_id, discipline_id
    ) values (
      current_setting('app.assessment_id', true)::uuid,
      current_setting('app.discipline_id', true)::uuid
    );
    raise exception 'Authenticated role inserted an assessment discipline';
  exception
    when insufficient_privilege then null;
  end;

  begin
    update public.rider_assessment_disciplines
       set notes = 'x';
    raise exception 'Authenticated role updated assessment disciplines';
  exception
    when insufficient_privilege then null;
  end;

  begin
    delete from public.rider_assessment_disciplines;
    raise exception 'Authenticated role deleted assessment disciplines';
  exception
    when insufficient_privilege then null;
  end;

  begin
    insert into public.rider_assessment_restrictions (
      assessment_id, restriction_code
    ) values (
      current_setting('app.assessment_id', true)::uuid,
      'CLIENT'
    );
    raise exception 'Authenticated role inserted an assessment restriction';
  exception
    when insufficient_privilege then null;
  end;

  begin
    update public.rider_assessment_restrictions
       set notes = 'x';
    raise exception 'Authenticated role updated assessment restrictions';
  exception
    when insufficient_privilege then null;
  end;

  begin
    delete from public.rider_assessment_restrictions;
    raise exception 'Authenticated role deleted assessment restrictions';
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
    perform * from public.rider_assessments;
    raise exception 'Anonymous role selected rider assessments';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

reset role;

do $$
begin
  if has_table_privilege('anon', 'public.rider_assessments', 'select')
     or has_table_privilege('authenticated', 'public.rider_assessments', 'insert')
     or has_table_privilege('authenticated', 'public.rider_assessments', 'update')
     or has_table_privilege('authenticated', 'public.rider_assessments', 'delete')
     or has_table_privilege('anon', 'public.rider_assessment_disciplines', 'select')
     or has_table_privilege('authenticated', 'public.rider_assessment_disciplines', 'insert')
     or has_table_privilege('authenticated', 'public.rider_assessment_disciplines', 'update')
     or has_table_privilege('authenticated', 'public.rider_assessment_disciplines', 'delete')
     or has_table_privilege('anon', 'public.rider_assessment_restrictions', 'select')
     or has_table_privilege('authenticated', 'public.rider_assessment_restrictions', 'insert')
     or has_table_privilege('authenticated', 'public.rider_assessment_restrictions', 'update')
     or has_table_privilege('authenticated', 'public.rider_assessment_restrictions', 'delete')
  then
    raise exception '016 privileges are not deny-by-default';
  end if;

  if has_function_privilege(
       'authenticated',
       'public.enforce_rider_assessment_assessor_authority()',
       'execute'
     )
     or has_function_privilege(
       'anon',
       'public.enforce_rider_assessment_assessor_authority()',
       'execute'
     )
     or has_function_privilege(
       'authenticated',
       'public.enforce_rider_assessment_child_authority()',
       'execute'
     )
     or has_function_privilege(
       'anon',
       'public.enforce_rider_assessment_child_authority()',
       'execute'
     )
  then
    raise exception '016 trigger function is executable by clients';
  end if;
end;
$$;

rollback;
