-- Phase 13C critical audit coverage.
-- Assumes migrations 001-029. Runnable without psql meta-commands.

begin;

set session_replication_role = replica;

do $$
#variable_conflict use_variable
declare
  fixture_auth uuid[] := array[
    '98900000-0000-0000-0000-000000000001'::uuid,
    '98900000-0000-0000-0000-000000000002'::uuid,
    '98900000-0000-0000-0000-000000000003'::uuid,
    '98900000-0000-0000-0000-000000000004'::uuid,
    '98900000-0000-0000-0000-000000000005'::uuid,
    '98900000-0000-0000-0000-000000000006'::uuid
  ];
  fixture_center_ids uuid[];
  fixture_equine_ids uuid[];
  fixture_service_ids uuid[];
  fixture_document_ids uuid[];
  fixture_session_ids uuid[];
  fixture_zero_ids uuid[];
  fixture_booking_ids uuid[];
  fixture_consent_ids uuid[];
  fixture_assessment_ids uuid[];
  linked_person_ids uuid[];
  fixture_account_ids uuid[];
begin
  select coalesce(array_agg(id), '{}') into fixture_center_ids
    from public.equestrian_centers where slug like 'phase13c-%';
  select coalesce(array_agg(id), '{}') into fixture_equine_ids
    from public.equines where name like 'phase13c-%';
  select coalesce(array_agg(id), '{}') into fixture_service_ids
    from public.center_services where center_id = any(fixture_center_ids);
  select coalesce(array_agg(id), '{}') into fixture_document_ids
    from public.policy_documents where market_code = 'Z9';
  select coalesce(array_agg(id), '{}') into fixture_session_ids
    from public.sessions
   where equine_id = any(fixture_equine_ids)
      or center_id = any(fixture_center_ids);
  select coalesce(array_agg(id), '{}') into fixture_zero_ids
    from public.zero_sessions
   where equine_id = any(fixture_equine_ids)
      or center_id = any(fixture_center_ids);
  select coalesce(array_agg(id), '{}') into fixture_booking_ids
    from public.bookings
   where equine_id = any(fixture_equine_ids)
      or center_id = any(fixture_center_ids);
  select coalesce(array_agg(id), '{}') into fixture_consent_ids
    from public.guardian_consents
   where guardian_relationship_id in (
     select id from public.guardian_relationships
      where guardian_person_id in (
        select person_id from public.user_accounts
         where auth_user_id = any(fixture_auth)
      )
   );
  select coalesce(array_agg(id), '{}') into fixture_assessment_ids
    from public.rider_assessments where center_id = any(fixture_center_ids);
  select coalesce(array_agg(id), '{}') into fixture_account_ids
    from public.user_accounts
   where auth_user_id = any(fixture_auth);

  delete from public.audit_events
   where actor_account_id = any(fixture_account_ids)
      or entity_id = any(fixture_session_ids)
      or entity_id = any(fixture_zero_ids)
      or entity_id = any(fixture_booking_ids)
      or entity_id = any(fixture_consent_ids)
      or entity_id = any(fixture_assessment_ids)
      or entity_id = any(fixture_document_ids)
      or metadata->>'center_id' in (
        select id::text from unnest(fixture_center_ids) as id
      );
  delete from public.reviews
   where booking_id = any(fixture_booking_ids);
  delete from public.incidents
   where booking_id = any(fixture_booking_ids);
  delete from public.equine_activities
   where session_id = any(fixture_session_ids);
  delete from public.session_evidence where session_id = any(fixture_session_ids);
  delete from public.session_events where session_id = any(fixture_session_ids);
  delete from public.session_permits where booking_id = any(fixture_booking_ids);
  delete from public.sessions where id = any(fixture_session_ids);
  delete from public.booking_requirements where booking_id = any(fixture_booking_ids);
  delete from public.equine_calendar_blocks
   where equine_id = any(fixture_equine_ids);
  delete from public.bookings where id = any(fixture_booking_ids);
  delete from public.zero_sessions where id = any(fixture_zero_ids);
  delete from public.rider_assessment_restrictions
   where assessment_id = any(fixture_assessment_ids);
  delete from public.rider_assessment_disciplines
   where assessment_id = any(fixture_assessment_ids);
  delete from public.rider_assessments where id = any(fixture_assessment_ids);
  delete from public.guardian_consents where id = any(fixture_consent_ids);
  delete from public.guardian_relationships
   where guardian_person_id in (
     select person_id from public.user_accounts where auth_user_id = any(fixture_auth)
   )
      or minor_person_id in (
     select person_id from public.user_accounts where auth_user_id = any(fixture_auth)
   );
  delete from public.equine_availability_rules
   where equine_id = any(fixture_equine_ids);
  delete from public.service_equines
   where service_id = any(fixture_service_ids)
      or equine_id = any(fixture_equine_ids);
  delete from public.center_services where id = any(fixture_service_ids);
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
  select coalesce(array_agg(person_id), '{}') into linked_person_ids
    from public.user_accounts
   where auth_user_id = any(fixture_auth);
  delete from public.user_accounts where auth_user_id = any(fixture_auth);
  delete from public.persons where id = any(linked_person_ids);
  delete from public.market_age_rules where country_code = 'Z9';
  delete from public.markets where country_code = 'Z9';
  delete from auth.users where id = any(fixture_auth);
end;
$$;

set session_replication_role = origin;

insert into public.markets (country_code, status) values ('Z9', 'ACTIVE');
insert into public.market_age_rules (
  country_code, legal_adult_age, guardian_consent_required, effective_from
) values ('Z9', 18, true, date '2000-01-01');

insert into auth.users (id) values
  ('98900000-0000-0000-0000-000000000001'),
  ('98900000-0000-0000-0000-000000000002'),
  ('98900000-0000-0000-0000-000000000003'),
  ('98900000-0000-0000-0000-000000000004'),
  ('98900000-0000-0000-0000-000000000005'),
  ('98900000-0000-0000-0000-000000000006');

do $$
#variable_conflict use_variable
declare
  rider_id uuid;
  rider_account uuid;
  evaluator_id uuid;
  evaluator_account uuid;
  intruder_id uuid;
  minor_id uuid;
  guardian_id uuid;
  guardian_account uuid;
  manager_id uuid;
  manager_account uuid;
  center_id constant uuid := '98900000-0000-0000-0000-00000000c001';
  equine_id constant uuid := '98900000-0000-0000-0000-00000000e001';
  service_id uuid;
  window_start timestamptz := timestamptz '2026-12-15 10:00:00+00';
begin
  select person_id, id into rider_id, rider_account
    from public.user_accounts
   where auth_user_id = '98900000-0000-0000-0000-000000000001';
  select person_id, id into evaluator_id, evaluator_account
    from public.user_accounts
   where auth_user_id = '98900000-0000-0000-0000-000000000002';
  select person_id into intruder_id
    from public.user_accounts
   where auth_user_id = '98900000-0000-0000-0000-000000000003';
  select person_id into minor_id
    from public.user_accounts
   where auth_user_id = '98900000-0000-0000-0000-000000000004';
  select person_id, id into guardian_id, guardian_account
    from public.user_accounts
   where auth_user_id = '98900000-0000-0000-0000-000000000005';
  select person_id, id into manager_id, manager_account
    from public.user_accounts
   where auth_user_id = '98900000-0000-0000-0000-000000000006';

  update public.persons set
    first_name = 'Phase13C', last_name = 'Adult Rider',
    date_of_birth = date '1990-01-01'
   where id = rider_id;
  update public.persons set
    first_name = 'Phase13C', last_name = 'Evaluator',
    date_of_birth = date '1980-01-01'
   where id = evaluator_id;
  update public.persons set
    first_name = 'Phase13C', last_name = 'Intruder',
    date_of_birth = date '1985-01-01'
   where id = intruder_id;
  update public.persons set
    first_name = 'Phase13C', last_name = 'Minor Rider',
    date_of_birth = (current_date - interval '12 years')::date
   where id = minor_id;
  update public.persons set
    first_name = 'Phase13C', last_name = 'Guardian',
    date_of_birth = date '1980-01-01'
   where id = guardian_id;
  update public.persons set
    first_name = 'Phase13C', last_name = 'Manager',
    date_of_birth = date '1980-01-01'
   where id = manager_id;

  insert into public.equestrian_centers (
    id, name, slug, country_code, status
  ) values (
    center_id, 'Phase13C Center', 'phase13c-center', 'Z9', 'ACTIVE'
  );

  insert into public.equines (id, name, equine_type, status)
  values (equine_id, 'phase13c-equine', 'HORSE', 'ACTIVE');

  insert into public.center_memberships (center_id, person_id, role_code)
  values
    (center_id, evaluator_id, 'ASSESSOR'),
    (center_id, manager_id, 'MANAGER');

  insert into public.equine_center_assignments (
    equine_id, center_id, assignment_type
  ) values (equine_id, center_id, 'SCHOOL');

  insert into public.equine_center_permissions (
    equine_id, center_id, granted_by_person_id, permission_code
  ) values
    (equine_id, center_id, manager_id, 'ASSESS_RIDERS'),
    (equine_id, center_id, manager_id, 'MANAGE_BOOKINGS'),
    (equine_id, center_id, manager_id, 'MANAGE_AVAILABILITY'),
    (equine_id, center_id, manager_id, 'MANAGE_REQUIREMENTS');

  insert into public.center_services (center_id, service_type, name)
  values (center_id, 'EQUINE_SESSION', 'Phase13C ride')
  returning id into service_id;

  insert into public.service_equines (service_id, equine_id, enabled, status)
  values (service_id, equine_id, true, 'ACTIVE');

  insert into public.equine_availability_rules (
    equine_id, center_id, starts_at, ends_at, created_by_account_id
  ) values (
    equine_id, center_id,
    timestamptz '2026-01-01 00:00:00+00',
    timestamptz '2028-01-01 00:00:00+00',
    manager_account
  );

  insert into public.policy_documents (
    id, policy_code, policy_type, market_code, locale, version,
    title, content, effective_from, status, requires_reacceptance
  ) values
    (
      '98900000-0000-0000-0000-00000000d001',
      'CENTER_Z9', 'CENTER_POLICY', 'Z9', 'es', '1',
      'Center policy', 'Phase 13C Center policy body must not be audited',
      now() - interval '1 day', 'ACTIVE', false
    ),
    (
      '98900000-0000-0000-0000-00000000d002',
      'GUARDIAN_Z9', 'GUARDIAN_POLICY', 'Z9', 'es', '1',
      'Guardian policy', 'Phase 13C guardian policy body',
      now() - interval '1 day', 'ACTIVE', false
    ),
    (
      '98900000-0000-0000-0000-00000000d003',
      'TERMS_Z9', 'TERMS_OF_SERVICE', 'Z9', 'es', '1',
      'Terms', 'Phase 13C terms body must not be audited',
      now() - interval '1 day', 'ACTIVE', false
    );

  insert into public.policy_acceptances (
    policy_document_id, person_id, user_account_id, accepted_at
  ) values (
    '98900000-0000-0000-0000-00000000d001',
    evaluator_id, evaluator_account, now()
  );

  insert into public.zero_sessions (
    id, rider_person_id, equine_id, center_id, requested_by_account_id,
    scheduled_at
  ) values (
    '98900000-0000-0000-0000-00000000a001',
    rider_id, equine_id, center_id, rider_account,
    now() - interval '1 hour'
  );

  insert into public.guardian_relationships (
    id, guardian_person_id, minor_person_id, relationship_type,
    verification_status, verified_at
  ) values (
    '98900000-0000-0000-0000-00000000f001',
    guardian_id, minor_id, 'LEGAL_GUARDIAN',
    'VERIFIED', now() - interval '1 day'
  );

  perform set_config('app.rider_person_id', rider_id::text, true);
  perform set_config('app.rider_account_id', rider_account::text, true);
  perform set_config('app.evaluator_person_id', evaluator_id::text, true);
  perform set_config('app.evaluator_account_id', evaluator_account::text, true);
  perform set_config('app.guardian_person_id', guardian_id::text, true);
  perform set_config('app.guardian_account_id', guardian_account::text, true);
  perform set_config('app.manager_person_id', manager_id::text, true);
  perform set_config('app.manager_account_id', manager_account::text, true);
  perform set_config('app.center_id', center_id::text, true);
  perform set_config('app.equine_id', equine_id::text, true);
  perform set_config('app.service_id', service_id::text, true);
  perform set_config('app.window_start', window_start::text, true);
end;
$$;

create or replace function pg_temp.set_auth(p_auth_user_id uuid)
returns void
language plpgsql
as $$
begin
  perform set_config('request.jwt.claim.sub', p_auth_user_id::text, true);
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', p_auth_user_id::text, 'role', 'authenticated')::text,
    true
  );
end;
$$;

grant execute on function pg_temp.set_auth(uuid) to authenticated, postgres;

do $$
declare
  helper_oid oid := 'public.record_authenticated_audit_event(text,text,uuid,jsonb)'::regprocedure;
  emit_name text;
begin
  if not exists (
    select 1 from pg_catalog.pg_proc as procedure
     where procedure.oid = helper_oid
       and procedure.prosecdef
       and procedure.proconfig @> array['search_path=pg_catalog, public']
  ) then
    raise exception 'record_authenticated_audit_event is not hardened SECURITY DEFINER';
  end if;

  if has_function_privilege('anon', helper_oid, 'EXECUTE')
     or has_function_privilege('authenticated', helper_oid, 'EXECUTE') then
    raise exception '029 audit helper must stay revoked from clients';
  end if;

  foreach emit_name in array array[
    'public.emit_policy_acceptance_audit()',
    'public.emit_guardian_consent_audit()',
    'public.emit_rider_assessment_audit()',
    'public.emit_equine_permission_audit()',
    'public.emit_zero_session_audit()',
    'public.emit_booking_audit()'
  ]
  loop
    if not exists (
      select 1 from pg_catalog.pg_proc as procedure
       where procedure.oid = emit_name::regprocedure
         and procedure.prosecdef
         and procedure.proconfig @> array['search_path=pg_catalog, public']
    ) then
      raise exception '% is not hardened SECURITY DEFINER', emit_name;
    end if;

    if has_function_privilege('anon', emit_name::regprocedure, 'EXECUTE')
       or has_function_privilege('authenticated', emit_name::regprocedure, 'EXECUTE') then
      raise exception '% must stay revoked from clients', emit_name;
    end if;
  end loop;

  if has_table_privilege('authenticated', 'public.audit_events', 'select')
     or has_table_privilege('authenticated', 'public.audit_events', 'insert') then
    raise exception '029 must not grant client audit table access';
  end if;
end;
$$;

-- Unauthenticated fixture writes must not create audit rows.
do $$
begin
  if exists (
    select 1 from public.audit_events
     where event_type = 'policy_accepted'
       and metadata->>'target_id' = '98900000-0000-0000-0000-00000000d001'
  ) then
    raise exception 'Unauthenticated CENTER_POLICY fixture was audited';
  end if;

  if exists (
    select 1 from public.audit_events
     where event_type = 'equine_permission_granted'
       and metadata->>'equine_id' = '98900000-0000-0000-0000-00000000e001'
  ) then
    raise exception 'Unauthenticated permission fixture was audited';
  end if;
end;
$$;

-- Policy acceptance: JWT-backed insert is audited; body and free metadata are not.
select pg_temp.set_auth('98900000-0000-0000-0000-000000000001');

do $$
#variable_conflict use_variable
declare
  acceptance_id uuid;
  rider_account uuid := current_setting('app.rider_account_id')::uuid;
begin
  insert into public.policy_acceptances (
    policy_document_id, person_id, user_account_id, accepted_at,
    acceptance_context, metadata
  ) values (
    '98900000-0000-0000-0000-00000000d003',
    current_setting('app.rider_person_id')::uuid,
    rider_account,
    now(),
    'secret context',
    jsonb_build_object(
      'jwt', 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.aaa.bbb',
      'policy', 'should-not-copy'
    )
  ) returning id into acceptance_id;

  perform set_config('app.terms_acceptance_id', acceptance_id::text, true);

  if (
    select count(*) from public.audit_events
     where entity_id = acceptance_id and event_type = 'policy_accepted'
  ) <> 1 then
    raise exception 'Expected one policy_accepted audit';
  end if;

  if (
    select actor_account_id from public.audit_events
     where entity_id = acceptance_id
  ) is distinct from rider_account then
    raise exception 'Policy actor was not the JWT ACCOUNT';
  end if;

  if exists (
    select 1 from public.audit_events as audit
     where audit.entity_id = acceptance_id
       and (
         audit.metadata ? 'jwt'
         or audit.metadata ? 'policy'
         or audit.metadata ? 'policy_document_id'
         or audit.metadata ? 'content'
         or audit.metadata ? 'acceptance_context'
         or audit.metadata::text ilike '%eyJ%'
         or audit.metadata::text ilike '%must not be audited%'
         or exists (
           select 1
             from jsonb_object_keys(audit.metadata) as key
            where key ~* '(jwt|token|secret|policy|document|evidence)'
         )
       )
  ) then
    raise exception 'Policy audit stored forbidden metadata';
  end if;

  if (
    select audit.metadata->>'target_id'
      from public.audit_events as audit
     where audit.entity_id = acceptance_id
  ) is distinct from '98900000-0000-0000-0000-00000000d003' then
    raise exception 'Policy audit target_id was missing';
  end if;
end;
$$;

-- Rolled-back acceptance creates no event.
do $$
#variable_conflict use_variable
declare
  before_count integer;
  after_count integer;
begin
  select count(*) into before_count
    from public.audit_events
   where event_type = 'policy_accepted';

  begin
    insert into public.policy_acceptances (
      policy_document_id, person_id, user_account_id, accepted_at
    ) values (
      '98900000-0000-0000-0000-00000000d003',
      current_setting('app.rider_person_id')::uuid,
      current_setting('app.rider_account_id')::uuid,
      now()
    );
    raise exception 'rollback_policy_audit';
  exception
    when raise_exception then
      if sqlerrm is distinct from 'rollback_policy_audit' then
        raise;
      end if;
  end;

  select count(*) into after_count
    from public.audit_events
   where event_type = 'policy_accepted';

  if after_count <> before_count then
    raise exception 'Rolled-back policy acceptance wrote audit';
  end if;
end;
$$;

-- Failed consent grant writes no event.
set local role authenticated;
select pg_temp.set_auth('98900000-0000-0000-0000-000000000005');

do $$
begin
  begin
    perform * from public.grant_guardian_consent(
      '98900000-0000-0000-0000-00000000f001',
      'EQUESTRIAN_ACTIVITY',
      'GENERAL',
      'phase13c-terms',
      'Z9',
      null
    );
    raise exception 'Consent grant without guardian policy was allowed';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;
reset role;

do $$
begin
  if exists (
    select 1 from public.audit_events
     where event_type = 'guardian_consent_granted'
       and metadata->>'guardian_relationship_id' = '98900000-0000-0000-0000-00000000f001'
  ) then
    raise exception 'Failed consent grant wrote audit';
  end if;
end;
$$;

select pg_temp.set_auth('98900000-0000-0000-0000-000000000005');

do $$
begin
  insert into public.policy_acceptances (
    policy_document_id, person_id, user_account_id, accepted_at
  ) values (
    '98900000-0000-0000-0000-00000000d002',
    current_setting('app.guardian_person_id')::uuid,
    current_setting('app.guardian_account_id')::uuid,
    now()
  );
end;
$$;

set local role authenticated;
select pg_temp.set_auth('98900000-0000-0000-0000-000000000005');

do $$
#variable_conflict use_variable
declare
  granted record;
  consent_id uuid;
begin
  select * into granted
    from public.grant_guardian_consent(
      '98900000-0000-0000-0000-00000000f001',
      'EQUESTRIAN_ACTIVITY',
      'GENERAL',
      'phase13c-terms',
      'Z9',
      null
    );
  consent_id := granted.id;
  perform set_config('app.consent_id', consent_id::text, true);

  begin
    perform * from public.grant_guardian_consent(
      '98900000-0000-0000-0000-00000000f001',
      'EQUESTRIAN_ACTIVITY',
      'GENERAL',
      'phase13c-terms-replay',
      'Z9',
      null
    );
    raise exception 'Duplicate active consent was allowed';
  exception
    when unique_violation then null;
  end;

  perform * from public.revoke_guardian_consent(consent_id);
  perform * from public.revoke_guardian_consent(consent_id);
end;
$$;
reset role;

do $$
#variable_conflict use_variable
declare
  consent_id uuid := current_setting('app.consent_id')::uuid;
  guardian_account uuid := current_setting('app.guardian_account_id')::uuid;
begin
  if (
    select count(*) from public.audit_events
     where entity_id = consent_id and event_type = 'guardian_consent_granted'
  ) <> 1 then
    raise exception 'Expected one guardian_consent_granted audit';
  end if;

  if (
    select count(*) from public.audit_events
     where entity_id = consent_id and event_type = 'guardian_consent_revoked'
  ) <> 1 then
    raise exception 'Expected one guardian_consent_revoked after idempotent revoke';
  end if;

  if (
    select actor_account_id from public.audit_events
     where entity_id = consent_id and event_type = 'guardian_consent_granted'
  ) is distinct from guardian_account then
    raise exception 'Consent grant actor was not the caller ACCOUNT';
  end if;
end;
$$;

-- Rider assessment validated; notes stay out of metadata.
select pg_temp.set_auth('98900000-0000-0000-0000-000000000002');

do $$
#variable_conflict use_variable
declare
  assessment_id uuid;
begin
  insert into public.rider_assessments (
    rider_person_id, center_id, assessor_person_id, assessment_type,
    status, general_notes
  ) values (
    current_setting('app.rider_person_id')::uuid,
    current_setting('app.center_id')::uuid,
    current_setting('app.evaluator_person_id')::uuid,
    'ACCESS_TEST',
    'DRAFT',
    'Private assessor notes'
  ) returning id into assessment_id;

  perform set_config('app.assessment_id', assessment_id::text, true);

  if exists (
    select 1 from public.audit_events
     where entity_id = assessment_id
  ) then
    raise exception 'DRAFT assessment was audited';
  end if;

  update public.rider_assessments
     set status = 'VALID',
         performed_at = now(),
         general_notes = 'Private assessor notes'
   where id = assessment_id;

  update public.rider_assessments
     set general_notes = 'mutated notes'
   where id = assessment_id;
end;
$$;

do $$
#variable_conflict use_variable
declare
  assessment_id uuid := current_setting('app.assessment_id')::uuid;
begin
  if (
    select count(*) from public.audit_events
     where entity_id = assessment_id
       and event_type = 'rider_assessment_validated'
  ) <> 1 then
    raise exception 'Expected one rider_assessment_validated audit';
  end if;

  if exists (
    select 1 from public.audit_events as audit
     where audit.entity_id = assessment_id
       and (
         audit.metadata ? 'general_notes'
         or audit.metadata::text ilike '%Private assessor%'
       )
  ) then
    raise exception 'Assessment notes were stored in audit metadata';
  end if;
end;
$$;

-- Equine permission grant/revoke.
select pg_temp.set_auth('98900000-0000-0000-0000-000000000006');

do $$
#variable_conflict use_variable
declare
  permission_id uuid;
begin
  insert into public.equine_center_permissions (
    equine_id, center_id, granted_by_person_id, permission_code
  ) values (
    current_setting('app.equine_id')::uuid,
    current_setting('app.center_id')::uuid,
    current_setting('app.manager_person_id')::uuid,
    'VIEW_ACTIVITY'
  ) returning id into permission_id;

  perform set_config('app.permission_id', permission_id::text, true);

  update public.equine_center_permissions
     set status = 'REVOKED',
         revoked_at = now()
   where id = permission_id;

  update public.equine_center_permissions
     set status = 'REVOKED',
         revoked_at = now()
   where id = permission_id;
end;
$$;

do $$
#variable_conflict use_variable
declare
  permission_id uuid := current_setting('app.permission_id')::uuid;
begin
  if (
    select count(*) from public.audit_events
     where entity_id = permission_id
       and event_type = 'equine_permission_granted'
  ) <> 1 then
    raise exception 'Expected one equine_permission_granted audit';
  end if;

  if (
    select count(*) from public.audit_events
     where entity_id = permission_id
       and event_type = 'equine_permission_revoked'
  ) <> 1 then
    raise exception 'Expected one equine_permission_revoked after replay';
  end if;
end;
$$;

-- Failed Zero Session approval writes no audit; success and exact replay write one.
set local role authenticated;
select pg_temp.set_auth('98900000-0000-0000-0000-000000000003');

do $$
begin
  begin
    perform * from public.approve_zero_session(
      '98900000-0000-0000-0000-00000000a001', 'APPROVED', 'intruder'
    );
    raise exception 'Intruder approved a Zero Session';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;
reset role;

do $$
begin
  if exists (
    select 1 from public.audit_events
     where entity_id = '98900000-0000-0000-0000-00000000a001'
  ) then
    raise exception 'Failed Zero Session approval wrote audit';
  end if;
end;
$$;

set local role authenticated;
select pg_temp.set_auth('98900000-0000-0000-0000-000000000002');

do $$
begin
  perform * from public.approve_zero_session(
    '98900000-0000-0000-0000-00000000a001',
    'APPROVED',
    'Safe with evaluator'
  );
  perform * from public.approve_zero_session(
    '98900000-0000-0000-0000-00000000a001',
    'APPROVED',
    'Safe with evaluator'
  );
end;
$$;
reset role;

do $$
begin
  if (
    select count(*) from public.audit_events
     where entity_id = '98900000-0000-0000-0000-00000000a001'
       and event_type = 'zero_session_approved'
  ) <> 1 then
    raise exception 'Expected one zero_session_approved after exact replay';
  end if;

  if exists (
    select 1 from public.audit_events as audit
     where audit.entity_id = '98900000-0000-0000-0000-00000000a001'
       and (
         audit.metadata ? 'notes'
         or audit.metadata::text ilike '%Safe with evaluator%'
       )
  ) then
    raise exception 'Zero Session notes were stored in audit metadata';
  end if;
end;
$$;

-- Booking confirm/cancel.
set local role authenticated;
select pg_temp.set_auth('98900000-0000-0000-0000-000000000001');

do $$
#variable_conflict use_variable
declare
  created_id uuid;
begin
  created_id := public.create_booking_request(
    current_setting('app.rider_person_id')::uuid,
    current_setting('app.equine_id')::uuid,
    current_setting('app.center_id')::uuid,
    current_setting('app.service_id')::uuid,
    current_setting('app.window_start')::timestamptz,
    current_setting('app.window_start')::timestamptz + interval '1 hour'
  );
  perform set_config('app.booking_id', created_id::text, true);
end;
$$;
reset role;

do $$
begin
  -- Inspect as postgres; authenticated cannot SELECT bookings.
  if (
    select booking.status
      from public.bookings as booking
     where booking.id = current_setting('app.booking_id')::uuid
  ) is distinct from 'APPROVED' then
    raise exception 'Phase 13C booking fixture was not APPROVED';
  end if;
  if exists (
    select 1 from public.audit_events
     where entity_id = current_setting('app.booking_id')::uuid
  ) then
    raise exception 'Booking request was audited';
  end if;
end;
$$;

set local role authenticated;
select pg_temp.set_auth('98900000-0000-0000-0000-000000000006');

do $$
begin
  perform public.confirm_booking(current_setting('app.booking_id')::uuid);
  begin
    perform public.confirm_booking(current_setting('app.booking_id')::uuid);
    raise exception 'Confirm replay succeeded';
  exception
    when check_violation then null;
    when others then
      if sqlerrm like 'Only an APPROVED booking can be confirmed' then
        null;
      else
        raise;
      end if;
  end;
end;
$$;
reset role;

select pg_temp.set_auth('98900000-0000-0000-0000-000000000006');

do $$
#variable_conflict use_variable
declare
  booking_id uuid := current_setting('app.booking_id')::uuid;
begin
  update public.bookings
     set status = 'CANCELLED',
         cancelled_at = now(),
         updated_at = now()
   where id = booking_id;

  update public.bookings
     set status = 'CANCELLED',
         cancelled_at = cancelled_at,
         updated_at = now()
   where id = booking_id;
end;
$$;

do $$
#variable_conflict use_variable
declare
  booking_id uuid := current_setting('app.booking_id')::uuid;
  manager_account uuid := current_setting('app.manager_account_id')::uuid;
begin
  if (
    select count(*) from public.audit_events
     where entity_id = booking_id and event_type = 'booking_confirmed'
  ) <> 1 then
    raise exception 'Expected one booking_confirmed audit';
  end if;

  if (
    select count(*) from public.audit_events
     where entity_id = booking_id and event_type = 'booking_cancelled'
  ) <> 1 then
    raise exception 'Expected one booking_cancelled after replay';
  end if;

  if (
    select actor_account_id from public.audit_events
     where entity_id = booking_id and event_type = 'booking_confirmed'
  ) is distinct from manager_account then
    raise exception 'Booking confirm actor was not the caller ACCOUNT';
  end if;

  if exists (
    select 1 from public.audit_events as audit
     where audit.entity_id = booking_id
       and (
         audit.metadata ? 'booking_policy_snapshot'
         or audit.metadata ? 'snapshot'
       )
  ) then
    raise exception 'Booking policy snapshot was stored in audit metadata';
  end if;
end;
$$;

set local role authenticated;
select pg_temp.set_auth('98900000-0000-0000-0000-000000000001');

do $$
begin
  begin
    insert into public.audit_events (
      event_type, entity_type, entity_id, actor_account_id
    ) values (
      'policy_accepted',
      'policy_acceptance',
      current_setting('app.terms_acceptance_id')::uuid,
      current_setting('app.rider_account_id')::uuid
    );
    raise exception 'Authenticated inserted audit_events';
  exception
    when insufficient_privilege then null;
  end;

  begin
    update public.audit_events
       set event_type = 'spoofed'
     where entity_id = current_setting('app.terms_acceptance_id')::uuid;
    raise exception 'Authenticated updated audit_events';
  exception
    when insufficient_privilege then null;
  end;

  begin
    delete from public.audit_events
     where entity_id = current_setting('app.terms_acceptance_id')::uuid;
    raise exception 'Authenticated deleted audit_events';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform * from public.audit_events;
    raise exception 'Authenticated selected audit_events';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;
reset role;

rollback;
