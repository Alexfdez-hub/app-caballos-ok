-- Phase 12A local verified-session tests.
-- Assumes migrations 001-023. reviews, incidents,
-- audit_events and approve_zero_session remain deferred.
-- Runnable without psql meta-commands.

begin;

set session_replication_role = replica;

do $$
#variable_conflict use_variable
declare
  fixture_auth uuid[] := array[
    '88000000-0000-0000-0000-000000000001'::uuid,
    '88000000-0000-0000-0000-000000000002'::uuid,
    '88000000-0000-0000-0000-000000000003'::uuid,
    '88000000-0000-0000-0000-000000000004'::uuid,
    '88000000-0000-0000-0000-000000000005'::uuid,
    '88000000-0000-0000-0000-000000000006'::uuid,
    '88000000-0000-0000-0000-000000000007'::uuid,
    '88000000-0000-0000-0000-000000000008'::uuid,
    '88000000-0000-0000-0000-000000000009'::uuid
  ];
  linked_person_ids uuid[];
  fixture_center_ids uuid[];
  fixture_equine_ids uuid[];
  fixture_service_ids uuid[];
  fixture_document_ids uuid[];
  fixture_person_ids uuid[];
  fixture_session_ids uuid[];
begin
  select coalesce(array_agg(id), '{}') into fixture_center_ids
    from public.equestrian_centers where slug like 'phase12a-%';
  select coalesce(array_agg(id), '{}') into fixture_equine_ids
    from public.equines where name like 'phase12a-%';
  select coalesce(array_agg(id), '{}') into fixture_service_ids
    from public.center_services where center_id = any(fixture_center_ids);
  select coalesce(array_agg(id), '{}') into fixture_document_ids
    from public.policy_documents where market_code = 'ZR';
  select coalesce(array_agg(id), '{}') into fixture_session_ids
    from public.sessions
   where equine_id = any(fixture_equine_ids)
      or center_id = any(fixture_center_ids);

  delete from public.equine_activities where session_id = any(fixture_session_ids);
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
  delete from public.guardian_consents
   where guardian_person_id in (
     select person_id from public.user_accounts where auth_user_id = any(fixture_auth)
   )
      or minor_person_id in (
     select person_id from public.user_accounts where auth_user_id = any(fixture_auth)
   );
  delete from public.guardian_relationships
   where guardian_person_id in (
     select person_id from public.user_accounts where auth_user_id = any(fixture_auth)
   )
      or minor_person_id in (
     select person_id from public.user_accounts where auth_user_id = any(fixture_auth)
   );
  delete from public.policy_acceptances
   where user_account_id in (
     select id from public.user_accounts where auth_user_id = any(fixture_auth)
   )
      or policy_document_id = any(fixture_document_ids);
  delete from public.policy_documents where id = any(fixture_document_ids);
  select coalesce(array_agg(person_id), '{}') into linked_person_ids
    from public.user_accounts where auth_user_id = any(fixture_auth);
  delete from public.user_accounts where auth_user_id = any(fixture_auth);
  delete from public.persons where id = any(linked_person_ids);
  delete from public.market_age_rules where country_code = 'ZR';
  delete from public.markets where country_code = 'ZR';
  delete from auth.users where id = any(fixture_auth);
end;
$$;

set session_replication_role = origin;

insert into public.markets (country_code, status) values ('ZR', 'ACTIVE');
insert into public.market_age_rules (
  country_code, legal_adult_age, guardian_consent_required, effective_from
) values ('ZR', 18, true, date '2000-01-01');

insert into auth.users (id) values
  ('88000000-0000-0000-0000-000000000001'),
  ('88000000-0000-0000-0000-000000000002'),
  ('88000000-0000-0000-0000-000000000003'),
  ('88000000-0000-0000-0000-000000000004'),
  ('88000000-0000-0000-0000-000000000005'),
  ('88000000-0000-0000-0000-000000000006'),
  ('88000000-0000-0000-0000-000000000007'),
  ('88000000-0000-0000-0000-000000000008'),
  ('88000000-0000-0000-0000-000000000009');

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
  second_guardian_person_id uuid;
  center_a_id uuid;
  equine_id uuid;
  service_a_id uuid;
  terms_id uuid;
  relationship_id uuid;
  window_start timestamptz := timestamptz '2026-12-01 10:00:00+00';
begin
  if not exists (
    select 1 from information_schema.tables
     where table_schema = 'public'
       and table_name in ('sessions', 'session_events', 'session_evidence', 'session_permits')
  ) then
    raise exception '023 must add session tables';
  end if;

  if exists (
    select 1 from information_schema.tables
     where table_schema = 'public'
       and table_name in ('reviews', 'incidents', 'audit_events')
  ) then
    raise exception 'Reviews, incidents and audit must remain deferred';
  end if;

  if exists (
    select 1 from pg_catalog.pg_proc as procedure
      join pg_catalog.pg_namespace as namespace
        on namespace.oid = procedure.pronamespace
     where namespace.nspname = 'public'
       and procedure.proname = 'approve_zero_session'
  ) then
    raise exception '023 must not add approve_zero_session';
  end if;

  if (
    select count(*)
      from pg_catalog.pg_proc as procedure
      join pg_catalog.pg_namespace as namespace
        on namespace.oid = procedure.pronamespace
     where namespace.nspname = 'public'
       and procedure.proname in (
         'start_session',
         'end_session',
         'issue_session_permit',
         'attach_session_evidence'
       )
  ) <> 4 then
    raise exception '023 must add the session RPCs';
  end if;

  if (
    select count(*) from pg_catalog.pg_class
     where oid in (
       'public.sessions'::regclass,
       'public.session_events'::regclass,
       'public.session_evidence'::regclass,
       'public.session_permits'::regclass
     ) and relrowsecurity
  ) <> 4 then
    raise exception '023 RLS is not enabled';
  end if;

  select person_id, id into rider_person_id, rider_account_id
    from public.user_accounts
   where auth_user_id = '88000000-0000-0000-0000-000000000001';
  select person_id into other_person_id
    from public.user_accounts
   where auth_user_id = '88000000-0000-0000-0000-000000000002';
  select person_id, id into guardian_person_id, guardian_account_id
    from public.user_accounts
   where auth_user_id = '88000000-0000-0000-0000-000000000003';
  select person_id into minor_person_id
    from public.user_accounts
   where auth_user_id = '88000000-0000-0000-0000-000000000004';
  select person_id, id into staff_person_id, staff_account_id
    from public.user_accounts
   where auth_user_id = '88000000-0000-0000-0000-000000000005';
  select person_id into assessor_person_id
    from public.user_accounts
   where auth_user_id = '88000000-0000-0000-0000-000000000006';
  select person_id into owner_person_id
    from public.user_accounts
   where auth_user_id = '88000000-0000-0000-0000-000000000007';
  select person_id into instructor_person_id
    from public.user_accounts
   where auth_user_id = '88000000-0000-0000-0000-000000000008';
  select person_id into second_guardian_person_id
    from public.user_accounts
   where auth_user_id = '88000000-0000-0000-0000-000000000009';

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
  update public.persons
     set first_name = 'Guardian', last_name = 'Two', date_of_birth = date '1979-01-01'
   where id = second_guardian_person_id;

  insert into public.equestrian_centers (name, slug, country_code, status)
  values ('Phase12A Alpha', 'phase12a-alpha', 'ZR', 'ACTIVE')
  returning id into center_a_id;

  insert into public.equines (name, equine_type)
  values ('phase12a-school', 'HORSE')
  returning id into equine_id;

  insert into public.center_memberships (center_id, person_id, role_code)
  values
    (center_a_id, staff_person_id, 'MANAGER'),
    (center_a_id, assessor_person_id, 'ASSESSOR'),
    (center_a_id, instructor_person_id, 'INSTRUCTOR');

  insert into public.equine_center_assignments (
    equine_id, center_id, assignment_type
  ) values (
    equine_id, center_a_id, 'SCHOOL'
  );

  insert into public.equine_ownerships (
    equine_id, owner_type, owner_person_id, ownership_percentage
  ) values (
    equine_id, 'PERSON', owner_person_id, 100
  );

  insert into public.equine_center_permissions (
    equine_id, center_id, granted_by_person_id, permission_code
  ) values
    (equine_id, center_a_id, staff_person_id, 'MANAGE_BOOKINGS'),
    (equine_id, center_a_id, staff_person_id, 'MANAGE_AVAILABILITY'),
    (equine_id, center_a_id, staff_person_id, 'MANAGE_REQUIREMENTS'),
    (equine_id, center_a_id, staff_person_id, 'ASSESS_RIDERS'),
    (equine_id, center_a_id, staff_person_id, 'VIEW_ACTIVITY');

  insert into public.center_services (
    center_id, service_type, name
  ) values (
    center_a_id, 'EQUINE_SESSION', 'Phase12A ride'
  ) returning id into service_a_id;

  insert into public.service_equines (
    service_id, equine_id, enabled, status
  ) values (
    service_a_id, equine_id, true, 'ACTIVE'
  );

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
    'TERMS_ZR', 'TERMS_OF_SERVICE', 'ZR', 'es', '1',
    'Terms', 'Phase 12A terms', now() - interval '1 day', 'ACTIVE', false
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

  insert into public.guardian_relationships (
    guardian_person_id, minor_person_id, relationship_type,
    verification_status, verified_at
  ) values (
    second_guardian_person_id, minor_person_id, 'PARENT', 'VERIFIED', now()
  );

  insert into public.guardian_consents (
    guardian_relationship_id, guardian_person_id, minor_person_id,
    granted_by_account_id, consent_type, scope_type, terms_version, status
  ) values (
    relationship_id, guardian_person_id, minor_person_id,
    guardian_account_id, 'EQUESTRIAN_ACTIVITY', 'GENERAL', 'phase12a', 'ACTIVE'
  );

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
  perform set_config('app.second_guardian_person_id', second_guardian_person_id::text, true);
  perform set_config('app.center_a_id', center_a_id::text, true);
  perform set_config('app.equine_id', equine_id::text, true);
  perform set_config('app.service_a_id', service_a_id::text, true);
  perform set_config('app.window_start', window_start::text, true);
  perform set_config('app.now_base', now()::text, true);
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

-- Rider requests, staff confirms.
set local role authenticated;
select pg_temp.set_auth('88000000-0000-0000-0000-000000000001');

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
select pg_temp.set_auth('88000000-0000-0000-0000-000000000005');

do $$
begin
  perform public.confirm_booking(current_setting('app.rider_booking_id')::uuid);
end;
$$;

-- Unconfirmed APPROVED booking cannot start.
reset role;

do $$
#variable_conflict use_variable
declare
  pending_id uuid;
begin
  insert into public.bookings (
    participant_person_id, booked_by_account_id, equine_id, center_id,
    service_id, starts_at, ends_at, status, eligibility_status
  ) values (
    current_setting('app.rider_person_id')::uuid,
    current_setting('app.rider_account_id')::uuid,
    current_setting('app.equine_id')::uuid,
    current_setting('app.center_a_id')::uuid,
    current_setting('app.service_a_id')::uuid,
    current_setting('app.window_start')::timestamptz + interval '1 hour',
    current_setting('app.window_start')::timestamptz + interval '2 hours',
    'APPROVED',
    'ELIGIBLE'
  ) returning id into pending_id;
  perform set_config('app.unconfirmed_booking_id', pending_id::text, true);
end;
$$;

set local role authenticated;
select pg_temp.set_auth('88000000-0000-0000-0000-000000000001');

do $$
begin
  begin
    perform public.start_session(current_setting('app.unconfirmed_booking_id')::uuid);
    raise exception 'Unconfirmed booking started a session';
  exception
    when check_violation then null;
  end;
end;
$$;

-- Unauthorized callers cannot start the confirmed booking.
reset role;
set local role authenticated;
select pg_temp.set_auth('88000000-0000-0000-0000-000000000002');

do $$
begin
  begin
    perform public.start_session(current_setting('app.rider_booking_id')::uuid);
    raise exception 'Unrelated account started a session';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

reset role;
set local role authenticated;
select pg_temp.set_auth('88000000-0000-0000-0000-000000000006');

do $$
begin
  begin
    perform public.start_session(current_setting('app.rider_booking_id')::uuid);
    raise exception 'Assessor started a session';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

reset role;
set local role authenticated;
select pg_temp.set_auth('88000000-0000-0000-0000-000000000008');

do $$
begin
  begin
    perform public.start_session(current_setting('app.rider_booking_id')::uuid);
    raise exception 'Instructor started a session';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

reset role;
set local role anon;
select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claims', '{"role":"anon"}', true);

do $$
begin
  begin
    perform public.start_session(current_setting('app.rider_booking_id')::uuid);
    raise exception 'Anonymous role started a session';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

-- Happy path: rider starts with a fake device clock; server time wins.
reset role;
set local role authenticated;
select pg_temp.set_auth('88000000-0000-0000-0000-000000000001');

do $$
#variable_conflict use_variable
declare
  session_id uuid;
  device_time timestamptz := timestamptz '2020-01-01 00:00:00+00';
begin
  session_id := public.start_session(
    current_setting('app.rider_booking_id')::uuid,
    false,
    null,
    40.4,
    -3.7,
    'device-1',
    device_time
  );
  perform set_config('app.rider_session_id', session_id::text, true);
end;
$$;

reset role;

do $$
#variable_conflict use_variable
declare
  session_id uuid := current_setting('app.rider_session_id')::uuid;
  started_at timestamptz;
  device_time timestamptz := timestamptz '2020-01-01 00:00:00+00';
  event_device timestamptz;
  event_server timestamptz;
begin
  select session.started_at
    into started_at
    from public.sessions as session
   where session.id = session_id;
  perform set_config('app.rider_started_at', started_at::text, true);

  if started_at is null or started_at = device_time then
    raise exception 'start_session used client/device time as authority';
  end if;

  if (
    select session.status
      from public.sessions as session
     where session.id = session_id
  ) is distinct from 'ACTIVE' then
    raise exception 'start_session did not set ACTIVE';
  end if;

  if (
    select booking.status
      from public.bookings as booking
     where booking.id = current_setting('app.rider_booking_id')::uuid
  ) is distinct from 'ACTIVE' then
    raise exception 'start_session did not move the booking to ACTIVE';
  end if;

  select event.occurred_at_device, event.received_at_server
    into event_device, event_server
    from public.session_events as event
   where event.session_id = session_id
     and event.event_type = 'START';

  if event_device is distinct from device_time then
    raise exception 'Device time was not stored on the START event';
  end if;

  if event_server = device_time then
    raise exception 'received_at_server used device time';
  end if;

  if current_setting('app.session_transition', true) = '1' then
    raise exception 'start_session left app.session_transition enabled';
  end if;
end;
$$;

set local role authenticated;
select pg_temp.set_auth('88000000-0000-0000-0000-000000000001');

do $$
#variable_conflict use_variable
declare
  session_id uuid := current_setting('app.rider_session_id')::uuid;
  replay_id uuid;
  evidence_id uuid;
begin
  replay_id := public.start_session(current_setting('app.rider_booking_id')::uuid);
  if replay_id is distinct from session_id then
    raise exception 'Replay start created a second session';
  end if;

  evidence_id := public.attach_session_evidence(
    session_id,
    'START_PHOTO',
    'session-evidence/phase12a/start.jpg',
    timestamptz '2020-01-01 00:00:00+00',
    40.4,
    -3.7
  );
  perform set_config('app.evidence_id', evidence_id::text, true);
end;
$$;

reset role;

do $$
#variable_conflict use_variable
declare
  session_id uuid := current_setting('app.rider_session_id')::uuid;
begin
  if (
    select count(*) from public.sessions
     where booking_id = current_setting('app.rider_booking_id')::uuid
  ) <> 1 then
    raise exception 'Duplicate session rows for one booking';
  end if;

  if (
    select session.started_at
      from public.sessions as session
     where session.id = session_id
  ) is distinct from current_setting('app.rider_started_at')::timestamptz then
    raise exception 'Replay start mutated started_at';
  end if;

  if current_setting('app.session_transition', true) = '1' then
    raise exception 'attach_session_evidence left app.session_transition enabled';
  end if;
end;
$$;

-- Transition tampering and evidence immutability.
do $$
#variable_conflict use_variable
declare
  session_id uuid := current_setting('app.rider_session_id')::uuid;
begin
  begin
    update public.sessions
       set status = 'COMPLETED',
           ended_at = clock_timestamp() + interval '1 second'
     where id = session_id;
    raise exception 'Direct session update succeeded';
  exception
    when insufficient_privilege then null;
  end;

  begin
    insert into public.sessions (
      booking_id, equine_id, participant_person_id, center_id, status
    ) values (
      current_setting('app.unconfirmed_booking_id')::uuid,
      current_setting('app.equine_id')::uuid,
      current_setting('app.rider_person_id')::uuid,
      current_setting('app.center_a_id')::uuid,
      'ACTIVE'
    );
    raise exception 'Direct session insert succeeded';
  exception
    when insufficient_privilege then null;
  end;

  begin
    update public.session_evidence
       set storage_path = 'tampered.jpg'
     where id = current_setting('app.evidence_id')::uuid;
    raise exception 'Direct evidence update succeeded';
  exception
    when insufficient_privilege then null;
  end;

  begin
    delete from public.session_evidence
     where id = current_setting('app.evidence_id')::uuid;
    raise exception 'Direct evidence delete succeeded';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

set local role authenticated;
select pg_temp.set_auth('88000000-0000-0000-0000-000000000001');

do $$
#variable_conflict use_variable
declare
  ended_id uuid;
begin
  ended_id := public.end_session(
    current_setting('app.rider_session_id')::uuid,
    false,
    40.5,
    -3.8,
    'device-1',
    timestamptz '2019-01-01 00:00:00+00'
  );
  perform set_config('app.rider_session_id', ended_id::text, true);
end;
$$;

reset role;

do $$
#variable_conflict use_variable
declare
  ended_id uuid := current_setting('app.rider_session_id')::uuid;
  ended_at timestamptz;
  device_time timestamptz := timestamptz '2019-01-01 00:00:00+00';
begin
  select session.ended_at
    into ended_at
    from public.sessions as session
   where session.id = ended_id;

  if ended_at is null or ended_at = device_time then
    raise exception 'end_session used client/device time as authority';
  end if;

  if ended_at <= (
    select session.started_at
      from public.sessions as session
     where session.id = ended_id
  ) then
    raise exception 'Official end was not after official start';
  end if;

  if (
    select session.status
      from public.sessions as session
     where session.id = ended_id
  ) is distinct from 'COMPLETED' then
    raise exception 'end_session did not complete the session';
  end if;

  if (
    select booking.status
      from public.bookings as booking
     where booking.id = current_setting('app.rider_booking_id')::uuid
  ) is distinct from 'COMPLETED' then
    raise exception 'end_session did not complete the booking';
  end if;

  if current_setting('app.session_transition', true) = '1' then
    raise exception 'end_session left app.session_transition enabled';
  end if;
end;
$$;

set local role authenticated;
select pg_temp.set_auth('88000000-0000-0000-0000-000000000001');

do $$
#variable_conflict use_variable
declare
  ended_id uuid := current_setting('app.rider_session_id')::uuid;
  replay_id uuid;
begin
  replay_id := public.end_session(ended_id);
  if replay_id is distinct from ended_id then
    raise exception 'Replay end created a different session';
  end if;

  begin
    perform public.attach_session_evidence(
      ended_id,
      'END_PHOTO',
      'session-evidence/phase12a/end.jpg'
    );
    raise exception 'Evidence attached after completion';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform public.start_session(current_setting('app.rider_booking_id')::uuid);
    raise exception 'Completed session was started again';
  exception
    when check_violation then null;
  end;
end;
$$;

-- Guardian booker can start a minor session; unrelated verified guardian cannot.
reset role;
set local role authenticated;
select pg_temp.set_auth('88000000-0000-0000-0000-000000000003');

do $$
#variable_conflict use_variable
declare
  minor_booking uuid;
begin
  minor_booking := public.create_booking_request(
    current_setting('app.minor_person_id')::uuid,
    current_setting('app.equine_id')::uuid,
    current_setting('app.center_a_id')::uuid,
    current_setting('app.service_a_id')::uuid,
    current_setting('app.window_start')::timestamptz + interval '2 hours',
    current_setting('app.window_start')::timestamptz + interval '3 hours'
  );
  perform set_config('app.minor_booking_id', minor_booking::text, true);
end;
$$;

reset role;
set local role authenticated;
select pg_temp.set_auth('88000000-0000-0000-0000-000000000005');

do $$
begin
  perform public.confirm_booking(current_setting('app.minor_booking_id')::uuid);
end;
$$;

reset role;
set local role authenticated;
select pg_temp.set_auth('88000000-0000-0000-0000-000000000009');

do $$
begin
  begin
    perform public.start_session(current_setting('app.minor_booking_id')::uuid);
    raise exception 'Unrelated verified guardian started the minor session';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

reset role;
set local role authenticated;
select pg_temp.set_auth('88000000-0000-0000-0000-000000000003');

do $$
#variable_conflict use_variable
declare
  session_id uuid;
begin
  session_id := public.start_session(current_setting('app.minor_booking_id')::uuid);
  perform set_config('app.minor_session_id', session_id::text, true);
  perform public.end_session(session_id);
end;
$$;

reset role;

do $$
begin
  if (
    select session.participant_person_id
      from public.sessions as session
     where session.id = current_setting('app.minor_session_id')::uuid
  ) is distinct from current_setting('app.minor_person_id')::uuid then
    raise exception 'Minor session participant was not the minor PERSON';
  end if;
end;
$$;

-- Minor participant account can start their own later booking.
reset role;
set local role authenticated;
select pg_temp.set_auth('88000000-0000-0000-0000-000000000003');

do $$
#variable_conflict use_variable
declare
  minor_self_booking uuid;
begin
  minor_self_booking := public.create_booking_request(
    current_setting('app.minor_person_id')::uuid,
    current_setting('app.equine_id')::uuid,
    current_setting('app.center_a_id')::uuid,
    current_setting('app.service_a_id')::uuid,
    current_setting('app.window_start')::timestamptz + interval '3 hours',
    current_setting('app.window_start')::timestamptz + interval '4 hours'
  );
  perform set_config('app.minor_self_booking_id', minor_self_booking::text, true);
end;
$$;

reset role;
set local role authenticated;
select pg_temp.set_auth('88000000-0000-0000-0000-000000000005');
do $$
begin
  perform public.confirm_booking(current_setting('app.minor_self_booking_id')::uuid);
end;
$$;

reset role;
set local role authenticated;
select pg_temp.set_auth('88000000-0000-0000-0000-000000000004');

do $$
#variable_conflict use_variable
declare
  session_id uuid;
begin
  session_id := public.start_session(current_setting('app.minor_self_booking_id')::uuid);
  perform public.end_session(session_id);
end;
$$;

-- Offline start requires a server-issued permit bound to the booking.
reset role;
set local role authenticated;
select pg_temp.set_auth('88000000-0000-0000-0000-000000000001');

do $$
#variable_conflict use_variable
declare
  offline_booking uuid;
begin
  offline_booking := public.create_booking_request(
    current_setting('app.rider_person_id')::uuid,
    current_setting('app.equine_id')::uuid,
    current_setting('app.center_a_id')::uuid,
    current_setting('app.service_a_id')::uuid,
    current_setting('app.now_base')::timestamptz,
    current_setting('app.now_base')::timestamptz + interval '1 hour'
  );
  perform set_config('app.offline_booking_id', offline_booking::text, true);
end;
$$;

reset role;
set local role authenticated;
select pg_temp.set_auth('88000000-0000-0000-0000-000000000005');
do $$
begin
  perform public.confirm_booking(current_setting('app.offline_booking_id')::uuid);
end;
$$;

reset role;
set local role authenticated;
select pg_temp.set_auth('88000000-0000-0000-0000-000000000001');

do $$
#variable_conflict use_variable
declare
  permit_id uuid;
  replay_permit uuid;
  session_id uuid;
begin
  begin
    perform public.start_session(
      current_setting('app.offline_booking_id')::uuid,
      true,
      null
    );
    raise exception 'Offline start succeeded without a permit';
  exception
    when insufficient_privilege then null;
  end;

  permit_id := public.issue_session_permit(
    current_setting('app.offline_booking_id')::uuid
  );
  replay_permit := public.issue_session_permit(
    current_setting('app.offline_booking_id')::uuid
  );
  if replay_permit is distinct from permit_id then
    raise exception 'Permit issue was not idempotent';
  end if;
  perform set_config('app.offline_permit_id', permit_id::text, true);
end;
$$;

reset role;

do $$
begin
  if (
    select session.status
      from public.sessions as session
     where session.booking_id = current_setting('app.offline_booking_id')::uuid
  ) is distinct from 'READY' then
    raise exception 'Permit did not create a READY session';
  end if;
end;
$$;

set local role authenticated;
select pg_temp.set_auth('88000000-0000-0000-0000-000000000001');

do $$
#variable_conflict use_variable
declare
  session_id uuid;
begin
  begin
    perform public.start_session(
      current_setting('app.offline_booking_id')::uuid,
      true,
      '88000000-0000-0000-0000-00000000ffff'::uuid
    );
    raise exception 'Mismatched permit started an offline session';
  exception
    when insufficient_privilege then null;
  end;

  session_id := public.start_session(
    current_setting('app.offline_booking_id')::uuid,
    true,
    current_setting('app.offline_permit_id')::uuid
  );
  perform set_config('app.offline_session_id', session_id::text, true);
  perform public.end_session(session_id);
end;
$$;

reset role;

do $$
begin
  if (
    select session.started_offline
      from public.sessions as session
     where session.id = current_setting('app.offline_session_id')::uuid
  ) is not true then
    raise exception 'Offline start did not record started_offline';
  end if;
end;
$$;

-- End before start is rejected on a READY permit session.
reset role;
set local role authenticated;
select pg_temp.set_auth('88000000-0000-0000-0000-000000000001');

do $$
#variable_conflict use_variable
declare
  ready_booking uuid;
  ready_session uuid;
begin
  ready_booking := public.create_booking_request(
    current_setting('app.rider_person_id')::uuid,
    current_setting('app.equine_id')::uuid,
    current_setting('app.center_a_id')::uuid,
    current_setting('app.service_a_id')::uuid,
    current_setting('app.now_base')::timestamptz + interval '2 hours',
    current_setting('app.now_base')::timestamptz + interval '3 hours'
  );
  perform set_config('app.ready_booking_id', ready_booking::text, true);
end;
$$;

reset role;
set local role authenticated;
select pg_temp.set_auth('88000000-0000-0000-0000-000000000005');
do $$
begin
  perform public.confirm_booking(current_setting('app.ready_booking_id')::uuid);
end;
$$;

reset role;
set local role authenticated;
select pg_temp.set_auth('88000000-0000-0000-0000-000000000001');

do $$
begin
  perform public.issue_session_permit(current_setting('app.ready_booking_id')::uuid);
end;
$$;

reset role;

do $$
#variable_conflict use_variable
declare
  ready_session uuid;
begin
  select session.id
    into ready_session
    from public.sessions as session
   where session.booking_id = current_setting('app.ready_booking_id')::uuid;
  perform set_config('app.ready_session_id', ready_session::text, true);
end;
$$;

set local role authenticated;
select pg_temp.set_auth('88000000-0000-0000-0000-000000000001');

do $$
begin
  begin
    perform public.end_session(current_setting('app.ready_session_id')::uuid);
    raise exception 'READY session was ended before start';
  exception
    when check_violation then null;
  end;
end;
$$;

-- Staff with frozen booking authority can start.
reset role;
set local role authenticated;
select pg_temp.set_auth('88000000-0000-0000-0000-000000000001');

do $$
#variable_conflict use_variable
declare
  staff_booking uuid;
begin
  staff_booking := public.create_booking_request(
    current_setting('app.rider_person_id')::uuid,
    current_setting('app.equine_id')::uuid,
    current_setting('app.center_a_id')::uuid,
    current_setting('app.service_a_id')::uuid,
    current_setting('app.now_base')::timestamptz + interval '4 hours',
    current_setting('app.now_base')::timestamptz + interval '5 hours'
  );
  perform set_config('app.staff_booking_id', staff_booking::text, true);
end;
$$;

reset role;
set local role authenticated;
select pg_temp.set_auth('88000000-0000-0000-0000-000000000005');
do $$
#variable_conflict use_variable
declare
  session_id uuid;
begin
  perform public.confirm_booking(current_setting('app.staff_booking_id')::uuid);
  session_id := public.start_session(current_setting('app.staff_booking_id')::uuid);
  perform public.end_session(session_id);
end;
$$;

reset role;

-- Client table CRUD is forbidden. Helpers stay revoked.
do $$
begin
  set local role authenticated;
  perform pg_temp.set_auth('88000000-0000-0000-0000-000000000001');

  begin
    perform * from public.sessions;
    raise exception 'Authenticated role selected sessions';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform * from public.session_evidence;
    raise exception 'Authenticated role selected session evidence';
  exception
    when insufficient_privilege then null;
  end;

  begin
    delete from public.sessions;
    raise exception 'Authenticated role deleted sessions';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

reset role;

do $$
begin
  if has_table_privilege('anon', 'public.sessions', 'select')
     or has_table_privilege('authenticated', 'public.sessions', 'insert')
     or has_table_privilege('authenticated', 'public.sessions', 'update')
     or has_table_privilege('authenticated', 'public.sessions', 'delete')
     or has_table_privilege('authenticated', 'public.session_events', 'select')
     or has_table_privilege('authenticated', 'public.session_evidence', 'select')
     or has_table_privilege('authenticated', 'public.session_permits', 'select')
     or has_table_privilege('authenticated', 'public.session_evidence', 'insert')
  then
    raise exception '023 client table privileges must stay revoked';
  end if;

  if not has_function_privilege(
       'authenticated',
       'public.start_session(uuid,boolean,uuid,double precision,double precision,text,timestamptz)',
       'execute'
     )
     or not has_function_privilege(
       'authenticated',
       'public.end_session(uuid,boolean,double precision,double precision,text,timestamptz)',
       'execute'
     )
     or has_function_privilege(
       'anon',
       'public.start_session(uuid,boolean,uuid,double precision,double precision,text,timestamptz)',
       'execute'
     )
  then
    raise exception '023 public RPCs must be executable by authenticated only';
  end if;

  if has_function_privilege(
       'authenticated',
       'public.caller_can_operate_session(uuid,uuid,uuid,uuid)',
       'execute'
     )
     or has_function_privilege(
       'authenticated',
       'public.resolve_session_caller()',
       'execute'
     )
     or has_function_privilege(
       'authenticated',
       'public.append_session_event(uuid,text,timestamptz,double precision,double precision,text,boolean,jsonb)',
       'execute'
     )
     or has_function_privilege(
       'authenticated',
       'public.set_session_transition(boolean)',
       'execute'
     )
     or has_function_privilege(
       'authenticated',
       'public.enforce_session_immutability()',
       'execute'
     )
  then
    raise exception '023 internal session helpers must not be executable by clients';
  end if;

  if (
    select count(*)
      from pg_catalog.pg_proc as procedure
     where procedure.oid in (
       'public.start_session(uuid,boolean,uuid,double precision,double precision,text,timestamptz)'::regprocedure,
       'public.end_session(uuid,boolean,double precision,double precision,text,timestamptz)'::regprocedure,
       'public.issue_session_permit(uuid)'::regprocedure,
       'public.attach_session_evidence(uuid,text,text,timestamptz,double precision,double precision)'::regprocedure,
       'public.set_session_transition(boolean)'::regprocedure
     )
       and procedure.prosecdef
       and procedure.proconfig @> array['search_path=pg_catalog, public']
  ) <> 5 then
    raise exception '023 session functions lack SECURITY DEFINER or search_path';
  end if;
end;
$$;

rollback;
