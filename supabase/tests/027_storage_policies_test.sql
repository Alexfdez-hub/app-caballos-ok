-- Phase 14A local Storage security tests.
-- Assumes migrations 001-027. approve_zero_session remains deferred.
-- Runnable without psql meta-commands.

begin;

set session_replication_role = replica;

do $$
#variable_conflict use_variable
declare
  fixture_auth uuid[] := array[
    '88700000-0000-0000-0000-000000000001'::uuid,
    '88700000-0000-0000-0000-000000000002'::uuid,
    '88700000-0000-0000-0000-000000000003'::uuid,
    '88700000-0000-0000-0000-000000000004'::uuid,
    '88700000-0000-0000-0000-000000000005'::uuid,
    '88700000-0000-0000-0000-000000000006'::uuid,
    '88700000-0000-0000-0000-000000000007'::uuid,
    '88700000-0000-0000-0000-000000000008'::uuid
  ];
  fixture_center_ids uuid[];
  fixture_equine_ids uuid[];
  fixture_service_ids uuid[];
  fixture_document_ids uuid[];
  fixture_session_ids uuid[];
  fixture_qualification_ids uuid[];
  fixture_assessment_ids uuid[];
  linked_person_ids uuid[];
  fixture_account_ids uuid[];
begin
  select coalesce(array_agg(id), '{}') into fixture_center_ids
    from public.equestrian_centers where slug like 'phase14a-%';
  select coalesce(array_agg(id), '{}') into fixture_equine_ids
    from public.equines where name like 'phase14a-%';
  select coalesce(array_agg(id), '{}') into fixture_service_ids
    from public.center_services where center_id = any(fixture_center_ids);
  select coalesce(array_agg(id), '{}') into fixture_document_ids
    from public.policy_documents where market_code = 'ZY';
  select coalesce(array_agg(id), '{}') into fixture_session_ids
    from public.sessions
   where equine_id = any(fixture_equine_ids)
      or center_id = any(fixture_center_ids);
  select coalesce(array_agg(id), '{}') into fixture_account_ids
    from public.user_accounts
   where auth_user_id = any(fixture_auth);
  select coalesce(array_agg(id), '{}') into fixture_qualification_ids
    from public.rider_qualifications
   where rider_person_id in (
     select person_id from public.user_accounts
      where auth_user_id = any(fixture_auth)
   );
  select coalesce(array_agg(id), '{}') into fixture_assessment_ids
    from public.rider_assessments
   where center_id = any(fixture_center_ids);

  -- storage.protect_delete() blocks SQL DELETE. 027 tests run in one
  -- rolled-back transaction and do not rewrite existing objects.

  delete from public.session_evidence where session_id = any(fixture_session_ids);
  delete from public.session_events where session_id = any(fixture_session_ids);
  delete from public.session_permits
   where equine_id = any(fixture_equine_ids)
      or center_id = any(fixture_center_ids);
  delete from public.sessions where id = any(fixture_session_ids);
  delete from public.booking_requirements
   where booking_id in (
     select id from public.bookings
      where equine_id = any(fixture_equine_ids)
         or center_id = any(fixture_center_ids)
   );
  delete from public.bookings
   where equine_id = any(fixture_equine_ids)
      or center_id = any(fixture_center_ids);
  delete from public.equine_calendar_blocks
   where equine_id = any(fixture_equine_ids);
  delete from public.equine_availability_rules
   where equine_id = any(fixture_equine_ids);
  delete from public.service_equines
   where service_id = any(fixture_service_ids)
      or equine_id = any(fixture_equine_ids);
  delete from public.center_services where id = any(fixture_service_ids);
  delete from public.rider_assessment_restrictions
   where assessment_id = any(fixture_assessment_ids);
  delete from public.rider_assessment_disciplines
   where assessment_id = any(fixture_assessment_ids);
  delete from public.rider_assessments where id = any(fixture_assessment_ids);
  delete from public.rider_qualifications
   where id = any(fixture_qualification_ids);
  delete from public.qualification_levels
   where qualification_system_id in (
     select id from public.qualification_systems where code like 'phase14a-%'
   );
  delete from public.qualification_systems where code like 'phase14a-%';
  delete from public.equine_center_permissions
   where equine_id = any(fixture_equine_ids);
  delete from public.equine_center_assignments
   where equine_id = any(fixture_equine_ids);
  delete from public.equine_ownerships
   where equine_id = any(fixture_equine_ids);
  delete from public.equines where id = any(fixture_equine_ids);
  delete from public.center_memberships
   where center_id = any(fixture_center_ids);
  delete from public.center_languages
   where center_id = any(fixture_center_ids);
  delete from public.equestrian_centers where id = any(fixture_center_ids);
  delete from public.policy_acceptances
   where policy_document_id = any(fixture_document_ids);
  delete from public.policy_documents where id = any(fixture_document_ids);
  delete from public.guardian_consents
   where granted_by_account_id = any(fixture_account_ids);
  delete from public.guardian_relationships
   where guardian_person_id in (
     select person_id from public.user_accounts
      where auth_user_id = any(fixture_auth)
   )
      or minor_person_id in (
     select person_id from public.user_accounts
      where auth_user_id = any(fixture_auth)
   );

  select coalesce(array_agg(person_id), '{}') into linked_person_ids
    from public.user_accounts
   where auth_user_id = any(fixture_auth);
  delete from public.user_accounts where auth_user_id = any(fixture_auth);
  delete from public.persons where id = any(linked_person_ids);
  delete from public.market_age_rules where country_code = 'ZY';
  delete from public.markets where country_code = 'ZY';
  delete from auth.users where id = any(fixture_auth);
end;
$$;

set session_replication_role = origin;

insert into public.markets (country_code, status) values ('ZY', 'ACTIVE');
insert into public.market_age_rules (
  country_code, legal_adult_age, guardian_consent_required, effective_from
) values ('ZY', 18, true, date '2000-01-01');

insert into auth.users (id) values
  ('88700000-0000-0000-0000-000000000001'),
  ('88700000-0000-0000-0000-000000000002'),
  ('88700000-0000-0000-0000-000000000003'),
  ('88700000-0000-0000-0000-000000000004'),
  ('88700000-0000-0000-0000-000000000005'),
  ('88700000-0000-0000-0000-000000000006'),
  ('88700000-0000-0000-0000-000000000007'),
  ('88700000-0000-0000-0000-000000000008');

do $$
#variable_conflict use_variable
declare
  rider_person_id uuid;
  rider_account_id uuid;
  other_person_id uuid;
  guardian_person_id uuid;
  guardian_account_id uuid;
  minor_person_id uuid;
  staff_person_id uuid;
  staff_account_id uuid;
  assessor_person_id uuid;
  owner_person_id uuid;
  instructor_person_id uuid;
  center_a_id uuid;
  equine_id uuid;
  service_a_id uuid;
  terms_id uuid;
  relationship_id uuid;
  qualification_system_id uuid;
  qualification_level_id uuid;
  qualification_id uuid;
  minor_qualification_id uuid;
  assessment_id uuid;
  window_start timestamptz := timestamptz '2026-12-02 10:00:00+00';
begin
  if (
    select count(*) from storage.buckets
     where id in (
       'avatars',
       'equine-media',
       'qualification-documents',
       'session-evidence',
       'assessment-documents'
     )
       and public is distinct from false
  ) <> 0 then
    raise exception '027 target buckets must be private';
  end if;

  if exists (
    select 1 from storage.buckets
     where id in (
       'avatars',
       'equine-media',
       'qualification-documents',
       'session-evidence',
       'assessment-documents'
     )
       and public
  ) then
    raise exception '027 must not create a public target bucket';
  end if;

  if exists (
    select 1 from pg_catalog.pg_proc as procedure
      join pg_catalog.pg_namespace as namespace
        on namespace.oid = procedure.pronamespace
     where namespace.nspname = 'public'
       and procedure.proname = 'approve_zero_session'
  ) then
    raise exception '027 must not add approve_zero_session';
  end if;

  if exists (
    select 1 from pg_catalog.pg_proc as procedure
      join pg_catalog.pg_namespace as namespace
        on namespace.oid = procedure.pronamespace
     where procedure.proname ~* '(signed_url|create_signed|service_role)'
  ) then
    raise exception '027 must not add a signed-URL or service_role helper';
  end if;

  if exists (
    select 1 from pg_catalog.pg_policy
     where polrelid = 'storage.objects'::regclass
       and (
         polcmd in ('u', 'd', '*')
         or polname ilike '%upsert%'
         or polname ilike '%update%'
         or polname ilike '%delete%'
         or polname ilike '%move%'
       )
       and (
         polname like 'storage_027_%'
         or pg_catalog.pg_get_expr(polqual, polrelid) ilike '%session-evidence%'
         or pg_catalog.pg_get_expr(polwithcheck, polrelid) ilike '%session-evidence%'
         or pg_catalog.pg_get_expr(polqual, polrelid) ilike '%qualification-documents%'
         or pg_catalog.pg_get_expr(polwithcheck, polrelid) ilike '%qualification-documents%'
         or pg_catalog.pg_get_expr(polqual, polrelid) ilike '%assessment-documents%'
         or pg_catalog.pg_get_expr(polwithcheck, polrelid) ilike '%assessment-documents%'
         or pg_catalog.pg_get_expr(polqual, polrelid) ilike '%avatars%'
         or pg_catalog.pg_get_expr(polwithcheck, polrelid) ilike '%avatars%'
         or pg_catalog.pg_get_expr(polqual, polrelid) ilike '%equine-media%'
         or pg_catalog.pg_get_expr(polwithcheck, polrelid) ilike '%equine-media%'
       )
  ) then
    raise exception '027 must not allow Storage upsert, move or delete';
  end if;

  if exists (
    select 1 from pg_catalog.pg_policy
     where polrelid = 'storage.objects'::regclass
       and (
         polname ilike '%avatar%'
         or polname ilike '%equine-media%'
         or pg_catalog.pg_get_expr(polqual, polrelid) ilike '%avatars%'
         or pg_catalog.pg_get_expr(polwithcheck, polrelid) ilike '%avatars%'
         or pg_catalog.pg_get_expr(polqual, polrelid) ilike '%equine-media%'
         or pg_catalog.pg_get_expr(polwithcheck, polrelid) ilike '%equine-media%'
       )
  ) then
    raise exception '027 must keep avatars and equine-media deny-by-default';
  end if;

  if exists (
    select 1
      from pg_catalog.pg_proc as procedure
      join pg_catalog.pg_namespace as namespace
        on namespace.oid = procedure.pronamespace
      left join pg_catalog.pg_depend as depend
        on depend.objid = procedure.oid
       and depend.deptype = 'e'
     where namespace.nspname = 'public'
       and procedure.proname like 'storage_%'
       and depend.objid is null
       and (
         not procedure.prosecdef
         or not coalesce(
           procedure.proconfig,
           array[]::text[]
         ) @> array['search_path=pg_catalog, public']
       )
       and procedure.proname not in (
         'storage_object_name_is_safe',
         'storage_path_uuid',
         'storage_path_has_leaf'
       )
  ) then
    raise exception '027 SECURITY DEFINER storage helpers must fix search_path';
  end if;

  if has_function_privilege(
       'anon',
       'public.storage_session_evidence_allowed(text)',
       'execute'
     )
     or has_function_privilege(
       'public',
       'public.storage_session_evidence_allowed(text)',
       'execute'
     )
     or not has_function_privilege(
       'authenticated',
       'public.storage_session_evidence_allowed(text)',
       'execute'
     ) then
    raise exception '027 storage helpers have incorrect EXECUTE grants';
  end if;

  select person_id, id into rider_person_id, rider_account_id
    from public.user_accounts
   where auth_user_id = '88700000-0000-0000-0000-000000000001';
  select person_id into other_person_id
    from public.user_accounts
   where auth_user_id = '88700000-0000-0000-0000-000000000002';
  select person_id, id into guardian_person_id, guardian_account_id
    from public.user_accounts
   where auth_user_id = '88700000-0000-0000-0000-000000000003';
  select person_id into minor_person_id
    from public.user_accounts
   where auth_user_id = '88700000-0000-0000-0000-000000000004';
  select person_id, id into staff_person_id, staff_account_id
    from public.user_accounts
   where auth_user_id = '88700000-0000-0000-0000-000000000005';
  select person_id into assessor_person_id
    from public.user_accounts
   where auth_user_id = '88700000-0000-0000-0000-000000000006';
  select person_id into owner_person_id
    from public.user_accounts
   where auth_user_id = '88700000-0000-0000-0000-000000000007';
  select person_id into instructor_person_id
    from public.user_accounts
   where auth_user_id = '88700000-0000-0000-0000-000000000008';

  update public.persons
     set first_name = 'Rider', last_name = 'Adult', date_of_birth = date '1990-01-01'
   where id = rider_person_id;
  update public.persons
     set first_name = 'Other', last_name = 'Adult', date_of_birth = date '1988-01-01'
   where id = other_person_id;
  update public.persons
     set first_name = 'Guardian', last_name = 'Adult', date_of_birth = date '1980-01-01'
   where id = guardian_person_id;
  update public.persons
     set first_name = 'Minor', last_name = 'Child', date_of_birth = date '2015-06-15'
   where id = minor_person_id;
  update public.persons
     set first_name = 'Staff', last_name = 'Manager', date_of_birth = date '1985-01-01'
   where id = staff_person_id;
  update public.persons
     set first_name = 'Assessor', last_name = 'One', date_of_birth = date '1982-01-01'
   where id = assessor_person_id;
  update public.persons
     set first_name = 'Owner', last_name = 'Person', date_of_birth = date '1975-01-01'
   where id = owner_person_id;
  update public.persons
     set first_name = 'Instructor', last_name = 'One', date_of_birth = date '1984-01-01'
   where id = instructor_person_id;

  insert into public.equestrian_centers (name, slug, country_code, status)
  values ('Phase14A Alpha', 'phase14a-alpha', 'ZY', 'ACTIVE')
  returning id into center_a_id;

  insert into public.equines (name, equine_type)
  values ('phase14a-school', 'HORSE')
  returning id into equine_id;

  insert into public.center_memberships (center_id, person_id, role_code)
  values
    (center_a_id, staff_person_id, 'MANAGER'),
    (center_a_id, assessor_person_id, 'ASSESSOR'),
    (center_a_id, instructor_person_id, 'INSTRUCTOR');

  insert into public.equine_center_assignments (
    equine_id, center_id, assignment_type
  ) values (equine_id, center_a_id, 'SCHOOL');

  insert into public.equine_ownerships (
    equine_id, owner_type, owner_person_id, ownership_percentage
  ) values (equine_id, 'PERSON', owner_person_id, 100);

  insert into public.equine_center_permissions (
    equine_id, center_id, granted_by_person_id, permission_code
  ) values
    (equine_id, center_a_id, staff_person_id, 'MANAGE_BOOKINGS'),
    (equine_id, center_a_id, staff_person_id, 'MANAGE_AVAILABILITY'),
    (equine_id, center_a_id, staff_person_id, 'MANAGE_REQUIREMENTS'),
    (equine_id, center_a_id, staff_person_id, 'ASSESS_RIDERS');

  insert into public.center_services (center_id, service_type, name)
  values (center_a_id, 'EQUINE_SESSION', 'Phase14A ride')
  returning id into service_a_id;

  insert into public.service_equines (service_id, equine_id, enabled, status)
  values (service_a_id, equine_id, true, 'ACTIVE');

  insert into public.equine_availability_rules (
    equine_id, center_id, starts_at, ends_at, created_by_account_id
  ) values (
    equine_id, center_a_id,
    timestamptz '2026-01-01 00:00:00+00',
    timestamptz '2028-01-01 00:00:00+00',
    staff_account_id
  );

  insert into public.policy_documents (
    policy_code, policy_type, market_code, locale, version, title, content,
    effective_from, status, requires_reacceptance
  ) values (
    'TERMS_ZY', 'TERMS_OF_SERVICE', 'ZY', 'es', '1',
    'Terms', 'Phase 14A terms', now() - interval '1 day', 'ACTIVE', false
  ) returning id into terms_id;

  insert into public.policy_acceptances (
    policy_document_id, person_id, user_account_id, accepted_at
  ) values
    (terms_id, rider_person_id, rider_account_id, now()),
    (terms_id, guardian_person_id, guardian_account_id, now()),
    (terms_id, minor_person_id, guardian_account_id, now());

  insert into public.guardian_relationships (
    guardian_person_id, minor_person_id, relationship_type,
    verification_status, verified_at
  ) values (
    guardian_person_id, minor_person_id, 'PARENT', 'VERIFIED', now()
  ) returning id into relationship_id;

  insert into public.guardian_consents (
    guardian_relationship_id, guardian_person_id, minor_person_id,
    granted_by_account_id, consent_type, scope_type, terms_version, status
  ) values (
    relationship_id, guardian_person_id, minor_person_id,
    guardian_account_id, 'EQUESTRIAN_ACTIVITY', 'GENERAL', 'phase14a', 'ACTIVE'
  );

  insert into public.qualification_systems (code, name, country_code)
  values ('phase14a-fixture', 'Phase14A system', 'ZY')
  returning id into qualification_system_id;

  insert into public.qualification_levels (
    qualification_system_id, code, name
  ) values (
    qualification_system_id, 'phase14a-level', 'Phase14A level'
  ) returning id into qualification_level_id;

  insert into public.rider_qualifications (
    rider_person_id, qualification_level_id, verification_status
  ) values (
    rider_person_id, qualification_level_id, 'DECLARED'
  ) returning id into qualification_id;

  insert into public.rider_qualifications (
    rider_person_id, qualification_level_id, verification_status
  ) values (
    minor_person_id, qualification_level_id, 'DECLARED'
  ) returning id into minor_qualification_id;

  insert into public.rider_assessments (
    rider_person_id, center_id, assessor_person_id, assessment_type, status
  ) values (
    rider_person_id, center_a_id, assessor_person_id, 'ACCESS_TEST', 'DRAFT'
  ) returning id into assessment_id;

  perform set_config('app.rider_person_id', rider_person_id::text, true);
  perform set_config('app.rider_account_id', rider_account_id::text, true);
  perform set_config('app.other_person_id', other_person_id::text, true);
  perform set_config('app.guardian_person_id', guardian_person_id::text, true);
  perform set_config('app.guardian_account_id', guardian_account_id::text, true);
  perform set_config('app.minor_person_id', minor_person_id::text, true);
  perform set_config('app.staff_person_id', staff_person_id::text, true);
  perform set_config('app.staff_account_id', staff_account_id::text, true);
  perform set_config('app.assessor_person_id', assessor_person_id::text, true);
  perform set_config('app.owner_person_id', owner_person_id::text, true);
  perform set_config('app.instructor_person_id', instructor_person_id::text, true);
  perform set_config('app.center_a_id', center_a_id::text, true);
  perform set_config('app.equine_id', equine_id::text, true);
  perform set_config('app.service_a_id', service_a_id::text, true);
  perform set_config('app.qualification_id', qualification_id::text, true);
  perform set_config('app.minor_qualification_id', minor_qualification_id::text, true);
  perform set_config('app.assessment_id', assessment_id::text, true);
  perform set_config('app.window_start', window_start::text, true);
end;
$$;

create or replace function pg_temp.set_auth(p_auth_user_id uuid)
returns void
language plpgsql
as $$
begin
  perform set_config(
    'request.jwt.claim.sub',
    coalesce(p_auth_user_id::text, ''),
    true
  );
  perform set_config(
    'request.jwt.claims',
    case
      when p_auth_user_id is null then '{}'::text
      else json_build_object(
        'sub', p_auth_user_id::text,
        'role', 'authenticated'
      )::text
    end,
    true
  );
end;
$$;

create or replace function pg_temp.insert_storage_object(
  p_bucket text,
  p_name text
)
returns void
language plpgsql
as $$
begin
  insert into storage.objects (bucket_id, name, owner, owner_id, metadata)
  values (
    p_bucket,
    p_name,
    auth.uid(),
    auth.uid()::text,
    jsonb_build_object('spoof_person', 'ignore-me')
  );
end;
$$;

grant execute on function pg_temp.set_auth(uuid) to authenticated, anon, postgres;
grant execute on function pg_temp.insert_storage_object(text, text)
  to authenticated, anon, postgres;

-- Booking + session for evidence paths.
set local role authenticated;
select pg_temp.set_auth('88700000-0000-0000-0000-000000000001');

do $$
#variable_conflict use_variable
declare
  created_id uuid;
begin
  created_id := public.create_booking_request(
    current_setting('app.rider_person_id')::uuid,
    current_setting('app.equine_id')::uuid,
    current_setting('app.center_a_id')::uuid,
    current_setting('app.service_a_id')::uuid,
    current_setting('app.window_start')::timestamptz,
    current_setting('app.window_start')::timestamptz + interval '1 hour'
  );
  perform set_config('app.rider_booking_id', created_id::text, true);
end;
$$;

reset role;
set local role authenticated;
select pg_temp.set_auth('88700000-0000-0000-0000-000000000005');

do $$
begin
  perform public.confirm_booking(current_setting('app.rider_booking_id')::uuid);
end;
$$;

reset role;
set local role authenticated;
select pg_temp.set_auth('88700000-0000-0000-0000-000000000001');

do $$
#variable_conflict use_variable
declare
  session_id uuid;
begin
  session_id := public.start_session(
    current_setting('app.rider_booking_id')::uuid
  );
  perform set_config('app.session_id', session_id::text, true);
end;
$$;

-- Authorized rider can upload and read session evidence.
do $$
#variable_conflict use_variable
declare
  object_name text := current_setting('app.session_id') || '/start.jpg';
  seen integer;
begin
  perform pg_temp.insert_storage_object('session-evidence', object_name);
  select count(*) into seen
    from storage.objects
   where bucket_id = 'session-evidence'
     and name = object_name;
  if seen <> 1 then
    raise exception 'Authorized rider could not read own session evidence';
  end if;
  perform set_config('app.evidence_name', object_name, true);
end;
$$;

-- Authorized staff (ADMIN/MANAGER + MANAGE_BOOKINGS) can read/write.
reset role;
set local role authenticated;
select pg_temp.set_auth('88700000-0000-0000-0000-000000000005');

do $$
#variable_conflict use_variable
declare
  object_name text := current_setting('app.session_id') || '/staff.jpg';
  seen integer;
begin
  perform pg_temp.insert_storage_object('session-evidence', object_name);
  select count(*) into seen
    from storage.objects
   where bucket_id = 'session-evidence'
     and name = current_setting('app.evidence_name');
  if seen <> 1 then
    raise exception 'Authorized staff could not read session evidence';
  end if;
end;
$$;

-- Unrelated authenticated user cannot read or write.
reset role;
set local role authenticated;
select pg_temp.set_auth('88700000-0000-0000-0000-000000000002');

do $$
#variable_conflict use_variable
declare
  seen integer;
begin
  select count(*) into seen
    from storage.objects
   where bucket_id = 'session-evidence';
  if seen <> 0 then
    raise exception 'Unrelated authenticated user listed session evidence';
  end if;

  begin
    perform pg_temp.insert_storage_object(
      'session-evidence',
      current_setting('app.session_id') || '/other.jpg'
    );
    raise exception 'Unrelated authenticated user wrote session evidence';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

-- Owner and instructor are not session-evidence operators.
reset role;
set local role authenticated;
select pg_temp.set_auth('88700000-0000-0000-0000-000000000007');

do $$
begin
  begin
    perform pg_temp.insert_storage_object(
      'session-evidence',
      current_setting('app.session_id') || '/owner.jpg'
    );
    raise exception 'Equine owner wrote session evidence';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

reset role;
set local role authenticated;
select pg_temp.set_auth('88700000-0000-0000-0000-000000000008');

do $$
begin
  begin
    perform pg_temp.insert_storage_object(
      'session-evidence',
      current_setting('app.session_id') || '/instructor.jpg'
    );
    raise exception 'Instructor wrote session evidence';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

-- Anon cannot read or write private evidence.
reset role;
set local role anon;
select pg_temp.set_auth(null);

do $$
#variable_conflict use_variable
declare
  seen integer;
begin
  begin
    select count(*) into seen from storage.objects;
    if seen <> 0 then
      raise exception 'Anon listed Storage objects';
    end if;
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform pg_temp.insert_storage_object(
      'session-evidence',
      current_setting('app.session_id') || '/anon.jpg'
    );
    raise exception 'Anon wrote session evidence';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

-- Wrong bucket / prefix substitution / upsert denied.
reset role;
set local role authenticated;
select pg_temp.set_auth('88700000-0000-0000-0000-000000000001');

do $$
#variable_conflict use_variable
declare
  session_id uuid := current_setting('app.session_id')::uuid;
  rider_person_id uuid := current_setting('app.rider_person_id')::uuid;
  qualification_id uuid := current_setting('app.qualification_id')::uuid;
  updated integer;
begin
  begin
    perform pg_temp.insert_storage_object(
      'avatars',
      session_id::text || '/leak.jpg'
    );
    raise exception 'Session path was accepted in avatars';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform pg_temp.insert_storage_object(
      'equine-media',
      session_id::text || '/leak.jpg'
    );
    raise exception 'Session path was accepted in equine-media';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform pg_temp.insert_storage_object(
      'qualification-documents',
      session_id::text || '/leak.jpg'
    );
    raise exception 'Session id was accepted as a qualification path';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform pg_temp.insert_storage_object(
      'session-evidence',
      replace(session_id::text, '-', '') || '/prefix.jpg'
    );
    raise exception 'Non-UUID session prefix was accepted';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform pg_temp.insert_storage_object(
      'session-evidence',
      session_id::text || 'ffff/prefix.jpg'
    );
    raise exception 'Session id prefix substitution was accepted';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform pg_temp.insert_storage_object(
      'qualification-documents',
      rider_person_id::text || qualification_id::text || '/merged.pdf'
    );
    raise exception 'Collapsed qualification path was accepted';
  exception
    when insufficient_privilege then null;
  end;

  update storage.objects
     set metadata = jsonb_build_object('hack', true)
   where bucket_id = 'session-evidence'
     and name = current_setting('app.evidence_name');
  get diagnostics updated = row_count;
  if updated <> 0 then
    raise exception 'Storage upsert/update was allowed';
  end if;

  -- SQL DELETE is blocked by storage.protect_delete() and by the
  -- absence of a 027 DELETE policy. Either outcome is deny.
  begin
    delete from storage.objects
     where bucket_id = 'session-evidence'
       and name = current_setting('app.evidence_name');
    get diagnostics updated = row_count;
    if updated <> 0 then
      raise exception '027 delete policy must not remove Storage objects';
    end if;
  exception
    when insufficient_privilege then null;
    when raise_exception then
      if sqlerrm not ilike '%Direct deletion from storage tables is not allowed%' then
        raise;
      end if;
  end;
end;
$$;

-- Qualification owner and guardian paths.
do $$
#variable_conflict use_variable
declare
  object_name text :=
    current_setting('app.rider_person_id')
    || '/'
    || current_setting('app.qualification_id')
    || '/cert.pdf';
  seen integer;
begin
  perform pg_temp.insert_storage_object('qualification-documents', object_name);
  select count(*) into seen
    from storage.objects
   where bucket_id = 'qualification-documents'
     and name = object_name;
  if seen <> 1 then
    raise exception 'Rider could not read own qualification document';
  end if;
  perform set_config('app.qualification_name', object_name, true);
end;
$$;

reset role;
set local role authenticated;
select pg_temp.set_auth('88700000-0000-0000-0000-000000000003');

do $$
#variable_conflict use_variable
declare
  object_name text :=
    current_setting('app.minor_person_id')
    || '/'
    || current_setting('app.minor_qualification_id')
    || '/minor.pdf';
  seen integer;
begin
  perform pg_temp.insert_storage_object('qualification-documents', object_name);
  select count(*) into seen
    from storage.objects
   where bucket_id = 'qualification-documents'
     and name = object_name;
  if seen <> 1 then
    raise exception 'Verified guardian could not write minor qualification document';
  end if;

  select count(*) into seen
    from storage.objects
   where bucket_id = 'qualification-documents'
     and name = current_setting('app.qualification_name');
  if seen <> 0 then
    raise exception 'Guardian read an unrelated adult qualification document';
  end if;
end;
$$;

reset role;
set local role authenticated;
select pg_temp.set_auth('88700000-0000-0000-0000-000000000002');

do $$
begin
  begin
    perform pg_temp.insert_storage_object(
      'qualification-documents',
      current_setting('app.rider_person_id')
      || '/'
      || current_setting('app.qualification_id')
      || '/other.pdf'
    );
    raise exception 'Unrelated user wrote a qualification document';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

-- Assessment write is assessor-only; rider may read.
reset role;
set local role authenticated;
select pg_temp.set_auth('88700000-0000-0000-0000-000000000006');

do $$
#variable_conflict use_variable
declare
  object_name text :=
    current_setting('app.rider_person_id')
    || '/'
    || current_setting('app.assessment_id')
    || '/notes.pdf';
begin
  perform pg_temp.insert_storage_object('assessment-documents', object_name);
  perform set_config('app.assessment_name', object_name, true);
end;
$$;

reset role;
set local role authenticated;
select pg_temp.set_auth('88700000-0000-0000-0000-000000000001');

do $$
#variable_conflict use_variable
declare
  seen integer;
begin
  select count(*) into seen
    from storage.objects
   where bucket_id = 'assessment-documents'
     and name = current_setting('app.assessment_name');
  if seen <> 1 then
    raise exception 'Rider could not read own assessment document';
  end if;

  begin
    perform pg_temp.insert_storage_object(
      'assessment-documents',
      current_setting('app.rider_person_id')
      || '/'
      || current_setting('app.assessment_id')
      || '/self.pdf'
    );
    raise exception 'Rider wrote an assessment document';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

-- Misleading metadata does not grant access.
reset role;

do $$
begin
  insert into storage.objects (bucket_id, name, owner, owner_id, metadata)
  values (
    'session-evidence',
    current_setting('app.session_id') || '/meta.jpg',
    '88700000-0000-0000-0000-000000000002',
    '88700000-0000-0000-0000-000000000002',
    jsonb_build_object(
      'owner_person_id', current_setting('app.other_person_id'),
      'user_metadata', 'trusted'
    )
  );
end;
$$;

set local role authenticated;
select pg_temp.set_auth('88700000-0000-0000-0000-000000000002');

do $$
#variable_conflict use_variable
declare
  seen integer;
begin
  select count(*) into seen
    from storage.objects
   where bucket_id = 'session-evidence'
     and name = current_setting('app.session_id') || '/meta.jpg';
  if seen <> 0 then
    raise exception 'Caller metadata granted a private evidence read';
  end if;
end;
$$;

-- Private avatars / equine-media remain denied.
reset role;
set local role authenticated;
select pg_temp.set_auth('88700000-0000-0000-0000-000000000001');

do $$
begin
  begin
    perform pg_temp.insert_storage_object(
      'avatars',
      current_setting('app.rider_person_id') || '/me.png'
    );
    raise exception 'Avatar upload was allowed before path ownership is frozen';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform pg_temp.insert_storage_object(
      'equine-media',
      current_setting('app.equine_id') || '/front.jpg'
    );
    raise exception 'Equine-media upload was allowed before path ownership is frozen';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

reset role;

do $$
begin
  insert into storage.objects (bucket_id, name)
  values
    ('avatars', current_setting('app.rider_person_id') || '/seed.png'),
    ('equine-media', current_setting('app.equine_id') || '/seed.jpg');
end;
$$;

set local role authenticated;
select pg_temp.set_auth('88700000-0000-0000-0000-000000000001');

do $$
#variable_conflict use_variable
declare
  seen integer;
begin
  select count(*) into seen
    from storage.objects
   where bucket_id in ('avatars', 'equine-media');
  if seen <> 0 then
    raise exception 'Private avatar or equine-media was readable';
  end if;
end;
$$;

-- Revoked staff authority loses evidence write/read.
reset role;

do $$
begin
  update public.center_memberships
     set status = 'ENDED',
         ended_at = now()
   where person_id = current_setting('app.staff_person_id')::uuid
     and center_id = current_setting('app.center_a_id')::uuid
     and role_code = 'MANAGER';

  update public.equine_center_permissions
     set status = 'REVOKED',
         revoked_at = now()
   where equine_id = current_setting('app.equine_id')::uuid
     and center_id = current_setting('app.center_a_id')::uuid
     and permission_code = 'MANAGE_BOOKINGS';
end;
$$;

set local role authenticated;
select pg_temp.set_auth('88700000-0000-0000-0000-000000000005');

do $$
#variable_conflict use_variable
declare
  seen integer;
begin
  select count(*) into seen
    from storage.objects
   where bucket_id = 'session-evidence';
  if seen <> 0 then
    raise exception 'Revoked staff still read session evidence';
  end if;

  begin
    perform pg_temp.insert_storage_object(
      'session-evidence',
      current_setting('app.session_id') || '/revoked.jpg'
    );
    raise exception 'Revoked staff wrote session evidence';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

-- Revoked assessor loses assessment write; rider still reads.
reset role;

do $$
begin
  update public.center_memberships
     set status = 'ENDED',
         ended_at = now()
   where person_id = current_setting('app.assessor_person_id')::uuid
     and center_id = current_setting('app.center_a_id')::uuid
     and role_code = 'ASSESSOR';
end;
$$;

set local role authenticated;
select pg_temp.set_auth('88700000-0000-0000-0000-000000000006');

do $$
begin
  begin
    perform pg_temp.insert_storage_object(
      'assessment-documents',
      current_setting('app.rider_person_id')
      || '/'
      || current_setting('app.assessment_id')
      || '/revoked.pdf'
    );
    raise exception 'Revoked assessor wrote an assessment document';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

reset role;
set local role authenticated;
select pg_temp.set_auth('88700000-0000-0000-0000-000000000001');

do $$
#variable_conflict use_variable
declare
  seen integer;
begin
  select count(*) into seen
    from storage.objects
   where bucket_id = 'assessment-documents'
     and name = current_setting('app.assessment_name');
  if seen <> 1 then
    raise exception 'Rider lost assessment document read after assessor left';
  end if;
end;
$$;

reset role;

rollback;
