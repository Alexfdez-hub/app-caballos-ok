-- Phase 12B local equine-activity tests.
-- Assumes migrations 001-current. Zero Session approval is tested separately.
-- Runnable without psql meta-commands.

begin;

set session_replication_role = replica;

do $$
#variable_conflict use_variable
declare
  fixture_auth uuid[] := array[
    '88200000-0000-0000-0000-000000000001'::uuid,
    '88200000-0000-0000-0000-000000000002'::uuid,
    '88200000-0000-0000-0000-000000000005'::uuid,
    '88200000-0000-0000-0000-000000000007'::uuid,
    '88200000-0000-0000-0000-000000000008'::uuid
  ];
  fixture_center_ids uuid[];
  fixture_equine_ids uuid[];
  fixture_service_ids uuid[];
  fixture_document_ids uuid[];
  fixture_session_ids uuid[];
  linked_person_ids uuid[];
begin
  select coalesce(array_agg(id), '{}') into fixture_center_ids
    from public.equestrian_centers where slug like 'phase12b-%';
  select coalesce(array_agg(id), '{}') into fixture_equine_ids
    from public.equines where name like 'phase12b-%';
  select coalesce(array_agg(id), '{}') into fixture_service_ids
    from public.center_services where center_id = any(fixture_center_ids);
  select coalesce(array_agg(id), '{}') into fixture_document_ids
    from public.policy_documents where market_code = 'ZT';
  select coalesce(array_agg(id), '{}') into fixture_session_ids
    from public.sessions
   where equine_id = any(fixture_equine_ids)
      or center_id = any(fixture_center_ids);

  delete from public.reviews
   where booking_id in (
     select id from public.bookings
      where equine_id = any(fixture_equine_ids)
         or center_id = any(fixture_center_ids)
   );
  delete from public.incidents
   where session_id = any(fixture_session_ids)
      or equine_id = any(fixture_equine_ids)
      or center_id = any(fixture_center_ids);
  delete from public.equine_activities
   where session_id = any(fixture_session_ids)
      or equine_id = any(fixture_equine_ids)
      or center_id = any(fixture_center_ids);
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
  delete from public.equestrian_centers where id = any(fixture_center_ids);
  delete from public.policy_acceptances
   where policy_document_id = any(fixture_document_ids);
  delete from public.policy_documents where id = any(fixture_document_ids);

  select coalesce(array_agg(person_id), '{}') into linked_person_ids
    from public.user_accounts
   where auth_user_id = any(fixture_auth);
  delete from public.user_accounts where auth_user_id = any(fixture_auth);
  delete from public.persons where id = any(linked_person_ids);
  delete from public.market_age_rules where country_code = 'ZT';
  delete from public.markets where country_code = 'ZT';
  delete from auth.users where id = any(fixture_auth);
end;
$$;

set session_replication_role = origin;

insert into public.markets (country_code, status) values ('ZT', 'ACTIVE');
insert into public.market_age_rules (
  country_code, legal_adult_age, guardian_consent_required, effective_from
) values ('ZT', 18, true, date '2000-01-01');

insert into auth.users (id) values
  ('88200000-0000-0000-0000-000000000001'),
  ('88200000-0000-0000-0000-000000000002'),
  ('88200000-0000-0000-0000-000000000005'),
  ('88200000-0000-0000-0000-000000000007'),
  ('88200000-0000-0000-0000-000000000008');

do $$
#variable_conflict use_variable
declare
  rider_person_id uuid;
  rider_account_id uuid;
  other_person_id uuid;
  staff_person_id uuid;
  staff_account_id uuid;
  owner_person_id uuid;
  instructor_person_id uuid;
  center_a_id uuid;
  equine_id uuid;
  other_equine_id uuid;
  service_a_id uuid;
  terms_id uuid;
  window_start timestamptz := timestamptz '2026-12-01 10:00:00+00';
begin
  if not exists (
    select 1 from information_schema.tables
     where table_schema = 'public' and table_name = 'equine_activities'
  ) then
    raise exception '024 must add equine_activities';
  end if;


  if (
    select relrowsecurity
      from pg_catalog.pg_class
     where oid = 'public.equine_activities'::regclass
  ) is not true then
    raise exception '024 RLS is not enabled';
  end if;

  select person_id, id into rider_person_id, rider_account_id
    from public.user_accounts
   where auth_user_id = '88200000-0000-0000-0000-000000000001';
  select person_id into other_person_id
    from public.user_accounts
   where auth_user_id = '88200000-0000-0000-0000-000000000002';
  select person_id, id into staff_person_id, staff_account_id
    from public.user_accounts
   where auth_user_id = '88200000-0000-0000-0000-000000000005';
  select person_id into owner_person_id
    from public.user_accounts
   where auth_user_id = '88200000-0000-0000-0000-000000000007';
  select person_id into instructor_person_id
    from public.user_accounts
   where auth_user_id = '88200000-0000-0000-0000-000000000008';

  update public.persons
     set first_name = 'Rider12B', last_name = 'Adult', date_of_birth = date '1990-01-01'
   where id = rider_person_id;
  update public.persons
     set first_name = 'Other12B', last_name = 'Adult', date_of_birth = date '1988-01-01'
   where id = other_person_id;
  update public.persons
     set first_name = 'Staff12B', last_name = 'Manager', date_of_birth = date '1985-01-01'
   where id = staff_person_id;
  update public.persons
     set first_name = 'Owner12B', last_name = 'Person', date_of_birth = date '1975-01-01'
   where id = owner_person_id;
  update public.persons
     set first_name = 'Instructor12B', last_name = 'One', date_of_birth = date '1984-01-01'
   where id = instructor_person_id;

  insert into public.equestrian_centers (name, slug, country_code, status)
  values ('Phase12B Alpha', 'phase12b-alpha', 'ZT', 'ACTIVE')
  returning id into center_a_id;

  insert into public.equines (name, equine_type)
  values ('phase12b-school', 'HORSE')
  returning id into equine_id;

  insert into public.equines (name, equine_type)
  values ('phase12b-other', 'HORSE')
  returning id into other_equine_id;

  insert into public.center_memberships (center_id, person_id, role_code)
  values
    (center_a_id, staff_person_id, 'MANAGER'),
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
    (equine_id, center_a_id, staff_person_id, 'VIEW_ACTIVITY');

  insert into public.center_services (center_id, service_type, name)
  values (center_a_id, 'EQUINE_SESSION', 'Phase12B ride')
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
    'TERMS_ZT', 'TERMS_OF_SERVICE', 'ZT', 'es', '1',
    'Terms', 'Phase 12B terms', now() - interval '1 day', 'ACTIVE', false
  ) returning id into terms_id;

  insert into public.policy_acceptances (
    policy_document_id, person_id, user_account_id, accepted_at
  ) values (terms_id, rider_person_id, rider_account_id, now());

  perform set_config('app.rider_person_id', rider_person_id::text, true);
  perform set_config('app.rider_account_id', rider_account_id::text, true);
  perform set_config('app.other_person_id', other_person_id::text, true);
  perform set_config('app.staff_person_id', staff_person_id::text, true);
  perform set_config('app.staff_account_id', staff_account_id::text, true);
  perform set_config('app.instructor_person_id', instructor_person_id::text, true);
  perform set_config('app.center_a_id', center_a_id::text, true);
  perform set_config('app.equine_id', equine_id::text, true);
  perform set_config('app.other_equine_id', other_equine_id::text, true);
  perform set_config('app.service_a_id', service_a_id::text, true);
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

set local role authenticated;
select pg_temp.set_auth('88200000-0000-0000-0000-000000000001');

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
select pg_temp.set_auth('88200000-0000-0000-0000-000000000005');

do $$
begin
  perform public.confirm_booking(current_setting('app.rider_booking_id')::uuid);
end;
$$;

reset role;
set local role authenticated;
select pg_temp.set_auth('88200000-0000-0000-0000-000000000001');

do $$
#variable_conflict use_variable
declare
  session_id uuid;
begin
  session_id := public.start_session(current_setting('app.rider_booking_id')::uuid);
  perform set_config('app.rider_session_id', session_id::text, true);
end;
$$;

reset role;

do $$
#variable_conflict use_variable
declare
  activity_id uuid;
  replay_id uuid;
begin
  set local role authenticated;
  perform pg_temp.set_auth('88200000-0000-0000-0000-000000000001');
  activity_id := public.record_equine_activity(
    current_setting('app.rider_session_id')::uuid
  );
  reset role;

  if (
    select count(*) from public.equine_activities
     where session_id = current_setting('app.rider_session_id')::uuid
  ) <> 1 then
    raise exception 'record_equine_activity did not insert one activity row';
  end if;

  if (
    select activity.booking_id
      from public.equine_activities as activity
     where activity.id = activity_id
  ) is distinct from current_setting('app.rider_booking_id')::uuid then
    raise exception 'Activity booking was not copied from the session';
  end if;

  if (
    select activity.equine_id
      from public.equine_activities as activity
     where activity.id = activity_id
  ) is distinct from current_setting('app.equine_id')::uuid then
    raise exception 'Activity equine was not copied from the session';
  end if;

  if (
    select activity.starts_at
      from public.equine_activities as activity
     where activity.id = activity_id
  ) is distinct from (
    select session.started_at
      from public.sessions as session
     where session.id = current_setting('app.rider_session_id')::uuid
  ) then
    raise exception 'Activity starts_at was not the official session start';
  end if;

  if (
    select activity.ends_at
      from public.equine_activities as activity
     where activity.id = activity_id
  ) is not null then
    raise exception 'Active session activity must not invent ended_at';
  end if;

  perform set_config('app.activity_id', activity_id::text, true);

  set local role authenticated;
  perform pg_temp.set_auth('88200000-0000-0000-0000-000000000001');
  replay_id := public.record_equine_activity(
    current_setting('app.rider_session_id')::uuid
  );
  reset role;

  if replay_id is distinct from activity_id then
    raise exception 'Replay record created a second activity';
  end if;

  if (
    select count(*) from public.equine_activities
     where session_id = current_setting('app.rider_session_id')::uuid
  ) <> 1 then
    raise exception 'Replay record duplicated activity rows';
  end if;
end;
$$;

set local role authenticated;
select pg_temp.set_auth('88200000-0000-0000-0000-000000000001');

do $$
begin
  begin
    perform public.record_equine_activity(
      current_setting('app.rider_session_id')::uuid,
      current_setting('app.rider_booking_id')::uuid,
      current_setting('app.other_equine_id')::uuid,
      current_setting('app.center_a_id')::uuid
    );
    raise exception 'Cross-context equine id was accepted';
  exception
    when check_violation then null;
  end;
end;
$$;

reset role;
set local role authenticated;
select pg_temp.set_auth('88200000-0000-0000-0000-000000000002');

do $$
begin
  begin
    perform public.record_equine_activity(
      current_setting('app.rider_session_id')::uuid
    );
    raise exception 'Unrelated caller recorded equine activity';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

reset role;
set local role authenticated;
select pg_temp.set_auth('88200000-0000-0000-0000-000000000008');

do $$
begin
  begin
    perform public.record_equine_activity(
      current_setting('app.rider_session_id')::uuid
    );
    raise exception 'Instructor recorded equine activity';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

reset role;

do $$
#variable_conflict use_variable
declare
  activity_id uuid := current_setting('app.activity_id')::uuid;
begin
  begin
    update public.equine_activities
       set ends_at = clock_timestamp() + interval '1 second'
     where id = activity_id;
    raise exception 'Direct activity update succeeded';
  exception
    when insufficient_privilege then null;
  end;

  begin
    insert into public.equine_activities (
      equine_id, center_id, booking_id, session_id, starts_at, created_by_account_id
    ) values (
      current_setting('app.equine_id')::uuid,
      current_setting('app.center_a_id')::uuid,
      current_setting('app.rider_booking_id')::uuid,
      current_setting('app.rider_session_id')::uuid,
      clock_timestamp(),
      current_setting('app.rider_account_id')::uuid
    );
    raise exception 'Direct activity insert succeeded';
  exception
    when unique_violation then
      raise exception 'Direct activity insert reached unique instead of trigger';
    when insufficient_privilege then null;
  end;

  begin
    delete from public.equine_activities where id = activity_id;
    raise exception 'Direct activity delete succeeded';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

-- READY session cannot be recorded.
reset role;
set local role authenticated;
select pg_temp.set_auth('88200000-0000-0000-0000-000000000001');

do $$
#variable_conflict use_variable
declare
  ready_booking_id uuid;
begin
  ready_booking_id := public.create_booking_request(
    current_setting('app.rider_person_id')::uuid,
    current_setting('app.equine_id')::uuid,
    current_setting('app.center_a_id')::uuid,
    current_setting('app.service_a_id')::uuid,
    current_setting('app.window_start')::timestamptz + interval '2 hours',
    current_setting('app.window_start')::timestamptz + interval '3 hours'
  );
  perform set_config('app.ready_booking_id', ready_booking_id::text, true);
end;
$$;

reset role;
set local role authenticated;
select pg_temp.set_auth('88200000-0000-0000-0000-000000000005');

do $$
begin
  perform public.confirm_booking(current_setting('app.ready_booking_id')::uuid);
end;
$$;

reset role;
set local role authenticated;
select pg_temp.set_auth('88200000-0000-0000-0000-000000000001');

do $$
begin
  perform public.issue_session_permit(current_setting('app.ready_booking_id')::uuid);
end;
$$;

reset role;

do $$
#variable_conflict use_variable
declare
  ready_session_id uuid;
begin
  select session.id
    into ready_session_id
    from public.sessions as session
   where session.booking_id = current_setting('app.ready_booking_id')::uuid;
  perform set_config('app.ready_session_id', ready_session_id::text, true);

  if (
    select session.status
      from public.sessions as session
     where session.id = ready_session_id
  ) is distinct from 'READY' then
    raise exception 'Permit did not leave a READY session';
  end if;
end;
$$;

set local role authenticated;
select pg_temp.set_auth('88200000-0000-0000-0000-000000000001');

do $$
begin
  begin
    perform public.record_equine_activity(current_setting('app.ready_session_id')::uuid);
    raise exception 'READY session recorded equine activity';
  exception
    when check_violation then null;
  end;
end;
$$;

reset role;
set local role authenticated;
select pg_temp.set_auth('88200000-0000-0000-0000-000000000001');

do $$
#variable_conflict use_variable
declare
  activity_id uuid;
  completed_ends timestamptz;
  replay_id uuid;
begin
  perform public.end_session(current_setting('app.rider_session_id')::uuid);
  activity_id := public.record_equine_activity(
    current_setting('app.rider_session_id')::uuid
  );
  perform set_config('app.activity_id', activity_id::text, true);
end;
$$;

reset role;

do $$
#variable_conflict use_variable
declare
  activity_id uuid := current_setting('app.activity_id')::uuid;
  session_ended_at timestamptz;
  activity_ended_at timestamptz;
  replay_id uuid;
begin
  select session.ended_at
    into session_ended_at
    from public.sessions as session
   where session.id = current_setting('app.rider_session_id')::uuid;

  select activity.ends_at
    into activity_ended_at
    from public.equine_activities as activity
   where activity.id = activity_id;

  if activity_ended_at is null or activity_ended_at is distinct from session_ended_at then
    raise exception 'Completed session activity did not copy official ended_at';
  end if;

  set local role authenticated;
  perform pg_temp.set_auth('88200000-0000-0000-0000-000000000001');
  replay_id := public.record_equine_activity(
    current_setting('app.rider_session_id')::uuid
  );
  reset role;

  if replay_id is distinct from activity_id then
    raise exception 'Completed replay created a different activity';
  end if;

  if (
    select activity.ends_at
      from public.equine_activities as activity
     where activity.id = activity_id
  ) is distinct from activity_ended_at then
    raise exception 'Completed replay rewrote ends_at';
  end if;

  begin
    update public.equine_activities
       set ends_at = activity_ended_at + interval '1 second'
     where id = activity_id;
    raise exception 'Completed activity update succeeded';
  exception
    when insufficient_privilege then null;
  end;

  if current_setting('app.activity_transition', true) = '1' then
    raise exception 'record_equine_activity left app.activity_transition enabled';
  end if;
end;
$$;

reset role;

do $$
begin
  if has_table_privilege('anon', 'public.equine_activities', 'select')
     or has_table_privilege('authenticated', 'public.equine_activities', 'insert')
     or has_table_privilege('authenticated', 'public.equine_activities', 'update')
     or has_table_privilege('authenticated', 'public.equine_activities', 'delete')
     or has_table_privilege('authenticated', 'public.equine_activities', 'select')
  then
    raise exception '024 client table privileges must stay revoked';
  end if;

  if not has_function_privilege(
       'authenticated',
       'public.record_equine_activity(uuid,uuid,uuid,uuid)',
       'execute'
     )
     or has_function_privilege(
       'anon',
       'public.record_equine_activity(uuid,uuid,uuid,uuid)',
       'execute'
     )
  then
    raise exception '024 public RPC must be executable by authenticated only';
  end if;

  if has_function_privilege(
       'authenticated',
       'public.set_activity_transition(boolean)',
       'execute'
     )
     or has_function_privilege(
       'authenticated',
       'public.enforce_equine_activity_immutability()',
       'execute'
     )
  then
    raise exception '024 internal activity helpers must not be executable by clients';
  end if;

  if (
    select count(*)
      from pg_catalog.pg_proc as procedure
     where procedure.oid in (
       'public.record_equine_activity(uuid,uuid,uuid,uuid)'::regprocedure,
       'public.set_activity_transition(boolean)'::regprocedure
     )
       and procedure.prosecdef
       and procedure.proconfig @> array['search_path=pg_catalog, public']
  ) <> 2 then
    raise exception '024 activity functions lack SECURITY DEFINER or search_path';
  end if;
end;
$$;

rollback;
