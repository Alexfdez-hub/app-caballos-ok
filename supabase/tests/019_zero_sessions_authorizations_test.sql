-- Phase 9A local Zero Session and authorization foundation tests.
-- Assumes migrations 001-019. Bookings and eligibility remain deferred.
-- CENTER OWNER_APPROVAL requires ADMIN or MANAGER plus APPROVE_RIDERS;
-- INSTRUCTOR plus APPROVE_RIDERS is rejected.
-- Runnable without psql meta-commands.

begin;

do $$
declare
  fixture_auth uuid[] := array[
    '96000000-0000-0000-0000-000000000001'::uuid,
    '96000000-0000-0000-0000-000000000002'::uuid,
    '96000000-0000-0000-0000-000000000003'::uuid,
    '96000000-0000-0000-0000-000000000004'::uuid,
    '96000000-0000-0000-0000-000000000005'::uuid,
    '96000000-0000-0000-0000-000000000006'::uuid
  ];
  linked_person_ids uuid[];
  fixture_center_ids uuid[];
  fixture_equine_ids uuid[];
  fixture_session_ids uuid[];
begin
  select coalesce(array_agg(id), '{}') into fixture_center_ids
    from public.equestrian_centers where slug like 'phase9a-%';
  select coalesce(array_agg(id), '{}') into fixture_equine_ids
    from public.equines where name like 'phase9a-%';
  select coalesce(array_agg(id), '{}') into fixture_session_ids
    from public.zero_sessions where center_id = any(fixture_center_ids);

  delete from public.rider_equine_authorizations
   where rider_person_id in (
     select person_id from public.user_accounts where auth_user_id = any(fixture_auth)
   )
      or equine_id = any(fixture_equine_ids)
      or source_zero_session_id = any(fixture_session_ids);
  delete from public.zero_sessions
   where id = any(fixture_session_ids)
      or equine_id = any(fixture_equine_ids);
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
  delete from public.market_age_rules where country_code = 'ZM';
  delete from public.markets where country_code = 'ZM';
  delete from auth.users where id = any(fixture_auth);
end;
$$;

insert into public.markets (country_code, status) values ('ZM', 'ACTIVE');
insert into auth.users (id) values
  ('96000000-0000-0000-0000-000000000001'),
  ('96000000-0000-0000-0000-000000000002'),
  ('96000000-0000-0000-0000-000000000003'),
  ('96000000-0000-0000-0000-000000000004'),
  ('96000000-0000-0000-0000-000000000005'),
  ('96000000-0000-0000-0000-000000000006');

do $$
#variable_conflict use_variable
declare
  rider_person_id uuid;
  evaluator_person_id uuid;
  instructor_person_id uuid;
  owner_person_id uuid;
  staff_person_id uuid;
  other_assessor_id uuid;
  rider_account_id uuid;
  center_a_id uuid;
  center_b_id uuid;
  school_equine_id uuid;
  person_owned_id uuid;
  center_owned_id uuid;
  pending_id uuid;
  approved_id uuid;
  rejected_id uuid;
  kept_id uuid;
  auth_id uuid;
  remaining_count integer;
begin

  if (
    select count(*) from pg_catalog.pg_class
     where oid in (
       'public.zero_sessions'::regclass,
       'public.rider_equine_authorizations'::regclass
     ) and relrowsecurity
  ) <> 2 then
    raise exception '019 RLS is not enabled';
  end if;

  if exists (
    select 1 from pg_catalog.pg_policy
     where polrelid in (
       'public.zero_sessions'::regclass,
       'public.rider_equine_authorizations'::regclass
     )
  ) then
    raise exception '019 tables unexpectedly gained client RLS policies';
  end if;

  if exists (
    select 1
      from information_schema.check_constraints as constraint_row
      join information_schema.constraint_column_usage as usage
        on usage.constraint_schema = constraint_row.constraint_schema
       and usage.constraint_name = constraint_row.constraint_name
     where constraint_row.constraint_schema = 'public'
       and usage.table_name in ('zero_sessions', 'rider_equine_authorizations')
       and constraint_row.check_clause ilike '%now()%'
  ) then
    raise exception '019 table CHECKs must not use now()';
  end if;

  select person_id, id into rider_person_id, rider_account_id
    from public.user_accounts
   where auth_user_id = '96000000-0000-0000-0000-000000000001';
  select person_id into evaluator_person_id
    from public.user_accounts
   where auth_user_id = '96000000-0000-0000-0000-000000000002';
  select person_id into instructor_person_id
    from public.user_accounts
   where auth_user_id = '96000000-0000-0000-0000-000000000003';
  select person_id into owner_person_id
    from public.user_accounts
   where auth_user_id = '96000000-0000-0000-0000-000000000004';
  select person_id into staff_person_id
    from public.user_accounts
   where auth_user_id = '96000000-0000-0000-0000-000000000005';
  select person_id into other_assessor_id
    from public.user_accounts
   where auth_user_id = '96000000-0000-0000-0000-000000000006';

  insert into public.equestrian_centers (name, slug, country_code, status)
  values ('Phase9A Alpha', 'phase9a-alpha', 'ZM', 'ACTIVE')
  returning id into center_a_id;
  insert into public.equestrian_centers (name, slug, country_code, status)
  values ('Phase9A Beta', 'phase9a-beta', 'ZM', 'ACTIVE')
  returning id into center_b_id;

  insert into public.equines (name, equine_type)
  values ('phase9a-school', 'HORSE')
  returning id into school_equine_id;
  insert into public.equines (name, equine_type)
  values ('phase9a-person-owned', 'HORSE')
  returning id into person_owned_id;
  insert into public.equines (name, equine_type)
  values ('phase9a-center-owned', 'HORSE')
  returning id into center_owned_id;

  insert into public.center_memberships (center_id, person_id, role_code)
  values
    (center_a_id, evaluator_person_id, 'ASSESSOR'),
    (center_a_id, instructor_person_id, 'INSTRUCTOR'),
    (center_a_id, staff_person_id, 'MANAGER'),
    (center_b_id, other_assessor_id, 'ASSESSOR');

  insert into public.equine_center_permissions (
    equine_id, center_id, granted_by_person_id, permission_code
  ) values (
    school_equine_id, center_a_id, staff_person_id, 'ASSESS_RIDERS'
  );

  insert into public.equine_ownerships (
    equine_id, owner_type, owner_person_id, ownership_percentage
  ) values (
    person_owned_id, 'PERSON', owner_person_id, 100
  );

  insert into public.equine_ownerships (
    equine_id, owner_type, owner_center_id, ownership_percentage
  ) values (
    center_owned_id, 'CENTER', center_a_id, 100
  );

  insert into public.zero_sessions (
    rider_person_id, equine_id, center_id, requested_by_account_id, result
  ) values (
    rider_person_id, school_equine_id, center_a_id, rider_account_id, 'PENDING'
  ) returning id into pending_id;

  begin
    insert into public.zero_sessions (
      rider_person_id, equine_id, center_id, requested_by_account_id,
      evaluator_person_id, result, performed_at
    ) values (
      rider_person_id, school_equine_id, center_a_id, rider_account_id,
      rider_person_id, 'APPROVED', now()
    );
    raise exception 'Self-evaluation was allowed';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.zero_sessions (
      rider_person_id, equine_id, center_id, requested_by_account_id, result
    ) values (
      rider_person_id, school_equine_id, center_a_id, rider_account_id, 'APPROVED'
    );
    raise exception 'APPROVED without evaluator was allowed';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.zero_sessions (
      rider_person_id, equine_id, center_id, requested_by_account_id,
      evaluator_person_id, result
    ) values (
      rider_person_id, school_equine_id, center_a_id, rider_account_id,
      evaluator_person_id, 'APPROVED'
    );
    raise exception 'APPROVED without performed_at was allowed';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.zero_sessions (
      rider_person_id, equine_id, center_id, requested_by_account_id,
      evaluator_person_id, result, performed_at
    ) values (
      rider_person_id, school_equine_id, center_a_id, rider_account_id,
      instructor_person_id, 'APPROVED', now()
    );
    raise exception 'INSTRUCTOR evaluator was allowed';
  exception
    when insufficient_privilege then null;
  end;

  begin
    insert into public.zero_sessions (
      rider_person_id, equine_id, center_id, requested_by_account_id,
      evaluator_person_id, result, performed_at
    ) values (
      rider_person_id, person_owned_id, center_a_id, rider_account_id,
      evaluator_person_id, 'APPROVED', now()
    );
    raise exception 'ASSESSOR without ASSESS_RIDERS was allowed';
  exception
    when insufficient_privilege then null;
  end;

  begin
    insert into public.zero_sessions (
      rider_person_id, equine_id, center_id, requested_by_account_id,
      evaluator_person_id, result, performed_at
    ) values (
      rider_person_id, school_equine_id, center_a_id, rider_account_id,
      other_assessor_id, 'APPROVED', now()
    );
    raise exception 'Cross-center ASSESSOR was allowed';
  exception
    when insufficient_privilege then null;
  end;

  insert into public.zero_sessions (
    rider_person_id, equine_id, center_id, requested_by_account_id,
    evaluator_person_id, result, performed_at
  ) values (
    rider_person_id, school_equine_id, center_a_id, rider_account_id,
    evaluator_person_id, 'APPROVED', now()
  ) returning id into approved_id;

  if exists (
    select 1 from public.rider_equine_authorizations
     where source_zero_session_id = approved_id
  ) then
    raise exception 'Approved Zero Session auto-created an authorization';
  end if;

  insert into public.zero_sessions (
    rider_person_id, equine_id, center_id, requested_by_account_id,
    evaluator_person_id, result, performed_at
  ) values (
    rider_person_id, school_equine_id, center_a_id, rider_account_id,
    evaluator_person_id, 'REJECTED', now()
  ) returning id into rejected_id;

  begin
    update public.zero_sessions
       set rider_person_id = owner_person_id
     where id = approved_id;
    raise exception 'Zero Session rider retarget was allowed';
  exception
    when insufficient_privilege then null;
  end;

  begin
    update public.zero_sessions
       set evaluator_person_id = other_assessor_id
     where id = approved_id;
    raise exception 'Zero Session evaluator rewrite was allowed';
  exception
    when insufficient_privilege then null;
  end;

  begin
    insert into public.rider_equine_authorizations (
      rider_person_id, equine_id, authorization_type, issued_by_person_id,
      source_zero_session_id
    ) values (
      rider_person_id, school_equine_id, 'ZERO_SESSION', evaluator_person_id,
      rejected_id
    );
    raise exception 'Rejected Zero Session authorized a rider';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.rider_equine_authorizations (
      rider_person_id, equine_id, authorization_type, issued_by_person_id,
      source_zero_session_id
    ) values (
      owner_person_id, school_equine_id, 'ZERO_SESSION', evaluator_person_id,
      approved_id
    );
    raise exception 'ZERO_SESSION authorization with a different rider was allowed';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.rider_equine_authorizations (
      rider_person_id, equine_id, authorization_type, issued_by_person_id,
      source_zero_session_id
    ) values (
      rider_person_id, school_equine_id, 'ZERO_SESSION', staff_person_id,
      approved_id
    );
    raise exception 'ZERO_SESSION authorization issued by a non-evaluator was allowed';
  exception
    when insufficient_privilege then null;
  end;

  insert into public.rider_equine_authorizations (
    rider_person_id, equine_id, authorization_type, issued_by_person_id,
    source_zero_session_id, center_id
  ) values (
    rider_person_id, school_equine_id, 'ZERO_SESSION', evaluator_person_id,
    approved_id, center_a_id
  ) returning id into auth_id;

  if not public.has_effective_rider_equine_authorization(
    rider_person_id, school_equine_id, 'ZERO_SESSION'
  ) then
    raise exception 'Approved ZERO_SESSION authorization is not currently effective';
  end if;

  begin
    insert into public.rider_equine_authorizations (
      rider_person_id, equine_id, authorization_type, issued_by_person_id,
      center_id
    ) values (
      rider_person_id, school_equine_id, 'CENTER_DELEGATED_APPROVAL',
      staff_person_id, center_a_id
    );
    raise exception 'CENTER_DELEGATED_APPROVAL without APPROVE_RIDERS was allowed';
  exception
    when insufficient_privilege then null;
  end;

  insert into public.equine_center_permissions (
    equine_id, center_id, granted_by_person_id, permission_code
  ) values (
    school_equine_id, center_a_id, staff_person_id, 'APPROVE_RIDERS'
  );

  begin
    insert into public.rider_equine_authorizations (
      rider_person_id, equine_id, authorization_type, issued_by_person_id,
      center_id
    ) values (
      rider_person_id, school_equine_id, 'CENTER_DELEGATED_APPROVAL',
      rider_person_id, center_a_id
    );
    raise exception 'CENTER_DELEGATED_APPROVAL self-approval was allowed';
  exception
    when check_violation then null;
  end;

  insert into public.rider_equine_authorizations (
    rider_person_id, equine_id, authorization_type, issued_by_person_id,
    center_id
  ) values (
    rider_person_id, school_equine_id, 'CENTER_DELEGATED_APPROVAL',
    staff_person_id, center_a_id
  );

  begin
    insert into public.rider_equine_authorizations (
      rider_person_id, equine_id, authorization_type, issued_by_person_id
    ) values (
      rider_person_id, person_owned_id, 'OWNER_APPROVAL', staff_person_id
    );
    raise exception 'OWNER_APPROVAL without PERSON ownership was allowed';
  exception
    when insufficient_privilege then null;
  end;

  insert into public.equine_management_assignments (
    equine_id, manager_type, manager_person_id, management_role,
    granted_by_person_id
  ) values (
    person_owned_id, 'PERSON', staff_person_id, 'PRIMARY_MANAGER', owner_person_id
  );

  begin
    insert into public.rider_equine_authorizations (
      rider_person_id, equine_id, authorization_type, issued_by_person_id
    ) values (
      rider_person_id, person_owned_id, 'OWNER_APPROVAL', staff_person_id
    );
    raise exception 'PRIMARY_MANAGER was treated as OWNER_APPROVAL';
  exception
    when insufficient_privilege then null;
  end;

  insert into public.rider_equine_authorizations (
    rider_person_id, equine_id, authorization_type, issued_by_person_id
  ) values (
    owner_person_id, person_owned_id, 'OWNER_APPROVAL', owner_person_id
  );

  if not public.has_effective_rider_equine_authorization(
    owner_person_id, person_owned_id, 'OWNER_APPROVAL'
  ) then
    raise exception 'Owner-as-rider OWNER_APPROVAL is not currently effective';
  end if;

  begin
    insert into public.rider_equine_authorizations (
      rider_person_id, equine_id, authorization_type, issued_by_person_id,
      center_id
    ) values (
      rider_person_id, center_owned_id, 'OWNER_APPROVAL', staff_person_id,
      center_a_id
    );
    raise exception 'CENTER OWNER_APPROVAL without APPROVE_RIDERS was allowed';
  exception
    when insufficient_privilege then null;
  end;

  insert into public.equine_center_permissions (
    equine_id, center_id, granted_by_person_id, permission_code
  ) values (
    center_owned_id, center_a_id, staff_person_id, 'APPROVE_RIDERS'
  );

  begin
    insert into public.rider_equine_authorizations (
      rider_person_id, equine_id, authorization_type, issued_by_person_id,
      center_id
    ) values (
      rider_person_id, center_owned_id, 'OWNER_APPROVAL', instructor_person_id,
      center_a_id
    );
    raise exception 'CENTER OWNER_APPROVAL by INSTRUCTOR was allowed';
  exception
    when insufficient_privilege then null;
  end;

  begin
    insert into public.rider_equine_authorizations (
      rider_person_id, equine_id, authorization_type, issued_by_person_id,
      center_id
    ) values (
      rider_person_id, center_owned_id, 'OWNER_APPROVAL', rider_person_id,
      center_a_id
    );
    raise exception 'CENTER OWNER_APPROVAL self-approval was allowed';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.rider_equine_authorizations (
      rider_person_id, equine_id, authorization_type, issued_by_person_id,
      center_id
    ) values (
      staff_person_id, center_owned_id, 'OWNER_APPROVAL', staff_person_id,
      center_a_id
    );
    raise exception 'CENTER OWNER_APPROVAL by MANAGER rider was allowed';
  exception
    when check_violation then null;
  end;

  insert into public.rider_equine_authorizations (
    rider_person_id, equine_id, authorization_type, issued_by_person_id,
    center_id
  ) values (
    rider_person_id, center_owned_id, 'OWNER_APPROVAL', staff_person_id,
    center_a_id
  );

  begin
    insert into public.rider_equine_authorizations (
      rider_person_id, equine_id, authorization_type, issued_by_person_id,
      source_zero_session_id
    ) values (
      rider_person_id, person_owned_id, 'OWNER_APPROVAL', owner_person_id,
      approved_id
    );
    raise exception 'OWNER_APPROVAL with a source Zero Session was allowed';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.rider_equine_authorizations (
      rider_person_id, equine_id, authorization_type, issued_by_person_id,
      status
    ) values (
      rider_person_id, person_owned_id, 'OWNER_APPROVAL', owner_person_id,
      'EXPIRED'
    );
    raise exception 'Stored EXPIRED authorization status was allowed';
  exception
    when check_violation then null;
  end;

  insert into public.rider_equine_authorizations (
    rider_person_id, equine_id, authorization_type, issued_by_person_id,
    valid_from, valid_until
  ) values (
    rider_person_id, person_owned_id, 'OWNER_APPROVAL', owner_person_id,
    now() + interval '2 days', now() + interval '10 days'
  );

  if public.has_effective_rider_equine_authorization(
    rider_person_id, person_owned_id, 'OWNER_APPROVAL'
  ) then
    raise exception 'Future-dated OWNER_APPROVAL was treated as currently effective';
  end if;

  update public.zero_sessions
     set result = 'REJECTED'
   where id = approved_id;

  begin
    update public.rider_equine_authorizations
       set restrictions_json = '{"after":"reject"}'::jsonb
     where id = auth_id;
    raise exception 'ZERO_SESSION authorization mutation after source rejection was allowed';
  exception
    when check_violation then null;
  end;

  update public.rider_equine_authorizations
     set status = 'REVOKED',
         revoked_at = now()
   where id = auth_id;

  if public.has_effective_rider_equine_authorization(
    rider_person_id, school_equine_id, 'ZERO_SESSION'
  ) then
    raise exception 'Revoked ZERO_SESSION authorization is still currently effective';
  end if;

  insert into public.zero_sessions (
    rider_person_id, equine_id, center_id, requested_by_account_id,
    evaluator_person_id, result, performed_at
  ) values (
    rider_person_id, school_equine_id, center_a_id, rider_account_id,
    evaluator_person_id, 'APPROVED', now()
  ) returning id into kept_id;

  update public.center_memberships
     set status = 'ENDED', ended_at = now()
   where center_id = center_a_id
     and person_id = evaluator_person_id
     and role_code = 'ASSESSOR';

  if not exists (
    select 1 from public.zero_sessions where id = kept_id
  ) then
    raise exception 'Historical Zero Session was lost after membership end';
  end if;

  begin
    update public.zero_sessions
       set notes = 'after-leave'
     where id = kept_id;
    raise exception 'Zero Session mutation after evaluator membership end was allowed';
  exception
    when insufficient_privilege then null;
  end;

  update public.center_memberships
     set status = 'ENDED', ended_at = now()
   where center_id = center_a_id
     and person_id = staff_person_id
     and role_code = 'MANAGER';

  begin
    update public.rider_equine_authorizations
       set supervision_required = true
     where equine_id = center_owned_id
       and authorization_type = 'OWNER_APPROVAL'
       and status = 'ACTIVE';
    raise exception 'CENTER OWNER_APPROVAL mutation after MANAGER end was allowed';
  exception
    when insufficient_privilege then null;
  end;

  update public.rider_equine_authorizations
     set status = 'REVOKED',
         revoked_at = now()
   where equine_id = center_owned_id
     and authorization_type = 'OWNER_APPROVAL'
     and status = 'ACTIVE';

  if public.has_effective_rider_equine_authorization(
    rider_person_id, center_owned_id, 'OWNER_APPROVAL'
  ) then
    raise exception 'Revoked CENTER OWNER_APPROVAL is still currently effective';
  end if;

  update public.equine_ownerships
     set status = 'ENDED', ended_at = now()
   where equine_id = person_owned_id
     and owner_type = 'PERSON'
     and equine_ownerships.owner_person_id = owner_person_id;

  begin
    update public.rider_equine_authorizations
       set supervision_required = true
     where equine_id = person_owned_id
       and authorization_type = 'OWNER_APPROVAL'
       and public.rider_equine_authorizations.rider_person_id = owner_person_id
       and status = 'ACTIVE'
       and valid_from <= now();
    raise exception 'PERSON OWNER_APPROVAL mutation after ownership end was allowed';
  exception
    when insufficient_privilege then null;
  end;

  update public.rider_equine_authorizations
     set status = 'REVOKED',
         revoked_at = now()
   where equine_id = person_owned_id
     and authorization_type = 'OWNER_APPROVAL'
     and public.rider_equine_authorizations.rider_person_id = owner_person_id
     and status = 'ACTIVE'
     and valid_from <= now();

  if public.has_effective_rider_equine_authorization(
    owner_person_id, person_owned_id, 'OWNER_APPROVAL'
  ) then
    raise exception 'Revoked PERSON OWNER_APPROVAL is still currently effective';
  end if;

  perform set_config('app.zero_session_id', kept_id::text, true);
  perform set_config('app.auth_id', auth_id::text, true);
  perform set_config('app.center_a_id', center_a_id::text, true);
  perform set_config('app.school_equine_id', school_equine_id::text, true);
  perform set_config('app.rider_person_id', rider_person_id::text, true);
  perform set_config('app.evaluator_person_id', evaluator_person_id::text, true);
  perform set_config('app.rider_account_id', rider_account_id::text, true);
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '96000000-0000-0000-0000-000000000001', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"96000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);

do $$
begin
  begin
    perform * from public.zero_sessions;
    raise exception 'Authenticated role selected zero sessions';
  exception
    when insufficient_privilege then null;
  end;

  begin
    insert into public.zero_sessions (
      rider_person_id, equine_id, center_id, requested_by_account_id
    ) values (
      current_setting('app.rider_person_id', true)::uuid,
      current_setting('app.school_equine_id', true)::uuid,
      current_setting('app.center_a_id', true)::uuid,
      current_setting('app.rider_account_id', true)::uuid
    );
    raise exception 'Authenticated role inserted a Zero Session';
  exception
    when insufficient_privilege then null;
  end;

  begin
    update public.zero_sessions set notes = 'client';
    raise exception 'Authenticated role updated zero sessions';
  exception
    when insufficient_privilege then null;
  end;

  begin
    delete from public.zero_sessions;
    raise exception 'Authenticated role deleted zero sessions';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform * from public.rider_equine_authorizations;
    raise exception 'Authenticated role selected authorizations';
  exception
    when insufficient_privilege then null;
  end;

  begin
    update public.rider_equine_authorizations set status = 'REVOKED';
    raise exception 'Authenticated role updated authorizations';
  exception
    when insufficient_privilege then null;
  end;

  begin
    delete from public.rider_equine_authorizations;
    raise exception 'Authenticated role deleted authorizations';
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
    perform * from public.zero_sessions;
    raise exception 'Anonymous role selected zero sessions';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

reset role;

do $$
begin
  if has_table_privilege('anon', 'public.zero_sessions', 'select')
     or has_table_privilege('authenticated', 'public.zero_sessions', 'insert')
     or has_table_privilege('authenticated', 'public.zero_sessions', 'update')
     or has_table_privilege('authenticated', 'public.zero_sessions', 'delete')
     or has_table_privilege('anon', 'public.rider_equine_authorizations', 'select')
     or has_table_privilege('authenticated', 'public.rider_equine_authorizations', 'insert')
     or has_table_privilege('authenticated', 'public.rider_equine_authorizations', 'update')
     or has_table_privilege('authenticated', 'public.rider_equine_authorizations', 'delete')
  then
    raise exception '019 privileges are not deny-by-default';
  end if;

  if has_function_privilege(
       'authenticated',
       'public.enforce_zero_session_evaluator_authority()',
       'execute'
     )
     or has_function_privilege(
       'anon',
       'public.has_effective_rider_equine_authorization(uuid,uuid,text)',
       'execute'
     )
     or has_function_privilege(
       'authenticated',
       'public.has_effective_equine_person_ownership(uuid,uuid)',
       'execute'
     )
     or has_function_privilege(
       'authenticated',
       'public.has_effective_equine_center_ownership(uuid,uuid)',
       'execute'
     )
  then
    raise exception '019 functions are executable by clients';
  end if;
end;
$$;

rollback;
