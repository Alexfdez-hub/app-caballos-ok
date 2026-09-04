-- Phase 13B local audit tests.
-- Assumes migrations 001-current. Zero Session approval is tested separately.
-- Runnable without psql meta-commands.

begin;

set session_replication_role = replica;

do $$
#variable_conflict use_variable
declare
  fixture_auth uuid[] := array[
    '88600000-0000-0000-0000-000000000001'::uuid,
    '88600000-0000-0000-0000-000000000002'::uuid,
    '88600000-0000-0000-0000-000000000005'::uuid,
    '88600000-0000-0000-0000-000000000007'::uuid,
    '88600000-0000-0000-0000-000000000008'::uuid
  ];
  fixture_center_ids uuid[];
  fixture_equine_ids uuid[];
  fixture_service_ids uuid[];
  fixture_document_ids uuid[];
  fixture_session_ids uuid[];
  linked_person_ids uuid[];
  fixture_account_ids uuid[];
begin
  select coalesce(array_agg(id), '{}') into fixture_center_ids
    from public.equestrian_centers where slug like 'phase13b-%';
  select coalesce(array_agg(id), '{}') into fixture_equine_ids
    from public.equines where name like 'phase13b-%';
  select coalesce(array_agg(id), '{}') into fixture_service_ids
    from public.center_services where center_id = any(fixture_center_ids);
  select coalesce(array_agg(id), '{}') into fixture_document_ids
    from public.policy_documents where market_code = 'ZX';
  select coalesce(array_agg(id), '{}') into fixture_session_ids
    from public.sessions
   where equine_id = any(fixture_equine_ids)
      or center_id = any(fixture_center_ids);
  select coalesce(array_agg(id), '{}') into fixture_account_ids
    from public.user_accounts
   where auth_user_id = any(fixture_auth);

  delete from public.audit_events
   where actor_account_id = any(fixture_account_ids)
      or entity_id = any(fixture_session_ids);
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
      or equine_id = any(fixture_equine_ids);
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
  delete from public.market_age_rules where country_code = 'ZX';
  delete from public.markets where country_code = 'ZX';
  delete from auth.users where id = any(fixture_auth);
end;
$$;

set session_replication_role = origin;

insert into public.markets (country_code, status) values ('ZX', 'ACTIVE');
insert into public.market_age_rules (
  country_code, legal_adult_age, guardian_consent_required, effective_from
) values ('ZX', 18, true, date '2000-01-01');

insert into auth.users (id) values
  ('88600000-0000-0000-0000-000000000001'),
  ('88600000-0000-0000-0000-000000000002'),
  ('88600000-0000-0000-0000-000000000005'),
  ('88600000-0000-0000-0000-000000000007'),
  ('88600000-0000-0000-0000-000000000008');

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
  service_a_id uuid;
  terms_id uuid;
  window_start timestamptz := timestamptz '2026-12-01 10:00:00+00';
begin
  if not exists (
    select 1 from information_schema.tables
     where table_schema = 'public' and table_name = 'audit_events'
  ) then
    raise exception '026 must add audit_events';
  end if;

  if not (
    select relrowsecurity
      from pg_catalog.pg_class
     where oid = 'public.audit_events'::regclass
  ) then
    raise exception '026 RLS is not enabled';
  end if;

  select person_id, id into rider_person_id, rider_account_id
    from public.user_accounts
   where auth_user_id = '88600000-0000-0000-0000-000000000001';
  select person_id into other_person_id
    from public.user_accounts
   where auth_user_id = '88600000-0000-0000-0000-000000000002';
  select person_id, id into staff_person_id, staff_account_id
    from public.user_accounts
   where auth_user_id = '88600000-0000-0000-0000-000000000005';
  select person_id into owner_person_id
    from public.user_accounts
   where auth_user_id = '88600000-0000-0000-0000-000000000007';
  select person_id into instructor_person_id
    from public.user_accounts
   where auth_user_id = '88600000-0000-0000-0000-000000000008';

  update public.persons
     set first_name = 'Rider13B', last_name = 'Adult', date_of_birth = date '1990-01-01'
   where id = rider_person_id;
  update public.persons
     set first_name = 'Other13B', last_name = 'Adult', date_of_birth = date '1988-01-01'
   where id = other_person_id;
  update public.persons
     set first_name = 'Staff13B', last_name = 'Manager', date_of_birth = date '1985-01-01'
   where id = staff_person_id;
  update public.persons
     set first_name = 'Owner13B', last_name = 'Person', date_of_birth = date '1975-01-01'
   where id = owner_person_id;
  update public.persons
     set first_name = 'Instructor13B', last_name = 'One', date_of_birth = date '1984-01-01'
   where id = instructor_person_id;

  insert into public.equestrian_centers (name, slug, country_code, status)
  values ('Phase13B Alpha', 'phase13b-alpha', 'ZX', 'ACTIVE')
  returning id into center_a_id;

  insert into public.equines (name, equine_type)
  values ('phase13b-school', 'HORSE')
  returning id into equine_id;

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
    (equine_id, center_a_id, staff_person_id, 'MANAGE_REQUIREMENTS');

  insert into public.center_services (center_id, service_type, name)
  values (center_a_id, 'EQUINE_SESSION', 'Phase13B ride')
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
    'TERMS_ZX', 'TERMS_OF_SERVICE', 'ZX', 'es', '1',
    'Terms', 'Phase 13B terms', now() - interval '1 day', 'ACTIVE', false
  ) returning id into terms_id;

  insert into public.policy_acceptances (
    policy_document_id, person_id, user_account_id, accepted_at
  ) values (terms_id, rider_person_id, rider_account_id, now());

  perform set_config('app.rider_person_id', rider_person_id::text, true);
  perform set_config('app.rider_account_id', rider_account_id::text, true);
  perform set_config('app.other_person_id', other_person_id::text, true);
  perform set_config('app.staff_person_id', staff_person_id::text, true);
  perform set_config('app.staff_account_id', staff_account_id::text, true);
  perform set_config('app.center_a_id', center_a_id::text, true);
  perform set_config('app.equine_id', equine_id::text, true);
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
select pg_temp.set_auth('88600000-0000-0000-0000-000000000001');

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
select pg_temp.set_auth('88600000-0000-0000-0000-000000000005');

do $$
begin
  perform public.confirm_booking(current_setting('app.rider_booking_id')::uuid);
end;
$$;

reset role;
set local role authenticated;
select pg_temp.set_auth('88600000-0000-0000-0000-000000000001');

do $$
#variable_conflict use_variable
declare
  session_id uuid;
  replay_id uuid;
  activity_id uuid;
begin
  session_id := public.start_session(current_setting('app.rider_booking_id')::uuid);
  perform set_config('app.rider_session_id', session_id::text, true);

  replay_id := public.start_session(current_setting('app.rider_booking_id')::uuid);
  if replay_id is distinct from session_id then
    raise exception 'Start replay created a second session';
  end if;

  activity_id := public.record_equine_activity(session_id);
  perform set_config('app.activity_id', activity_id::text, true);

  if public.record_equine_activity(session_id) is distinct from activity_id then
    raise exception 'Activity replay created a second row';
  end if;
end;
$$;

reset role;

do $$
#variable_conflict use_variable
declare
  session_id uuid := current_setting('app.rider_session_id')::uuid;
  activity_id uuid := current_setting('app.activity_id')::uuid;
  rider_account uuid := current_setting('app.rider_account_id')::uuid;
begin
  if (
    select count(*) from public.audit_events
     where entity_id = session_id and event_type = 'session_started'
  ) <> 1 then
    raise exception 'Expected one session_started audit';
  end if;

  if (
    select actor_account_id from public.audit_events
     where entity_id = session_id and event_type = 'session_started'
  ) is distinct from rider_account then
    raise exception 'Session start actor was not the caller ACCOUNT';
  end if;

  if (
    select count(*) from public.audit_events
     where entity_id = activity_id and event_type = 'equine_activity_recorded'
  ) <> 1 then
    raise exception 'Expected one equine_activity_recorded audit';
  end if;

  -- 029 covers booking_confirmed. 026 still must not attach 023–025
  -- event types to the booking row id.
  if exists (
    select 1 from public.audit_events
     where entity_id = current_setting('app.rider_booking_id')::uuid
       and event_type in (
         'session_started',
         'session_completed',
         'equine_activity_recorded',
         'review_submitted',
         'incident_reported'
       )
  ) then
    raise exception '026 session-family events must not use booking id as entity_id';
  end if;
end;
$$;

set local role authenticated;
select pg_temp.set_auth('88600000-0000-0000-0000-000000000001');

do $$
begin
  perform public.end_session(current_setting('app.rider_session_id')::uuid);
  perform public.end_session(current_setting('app.rider_session_id')::uuid);
end;
$$;

reset role;

do $$
begin
  if (
    select count(*) from public.audit_events
     where entity_id = current_setting('app.rider_session_id')::uuid
       and event_type = 'session_completed'
  ) <> 1 then
    raise exception 'Expected one session_completed audit after end replay';
  end if;
end;
$$;

set local role authenticated;
select pg_temp.set_auth('88600000-0000-0000-0000-000000000001');

do $$
begin
  begin
    perform public.submit_review(
      current_setting('app.rider_booking_id')::uuid,
      current_setting('app.center_a_id')::uuid,
      0
    );
    raise exception 'Rating 0 was accepted';
  exception
    when check_violation then null;
  end;
end;
$$;

reset role;

do $$
begin
  if exists (
    select 1 from public.audit_events
     where event_type = 'review_submitted'
       and metadata->>'booking_id' = current_setting('app.rider_booking_id')
  ) then
    raise exception 'Failed review wrote audit';
  end if;
end;
$$;

set local role authenticated;
select pg_temp.set_auth('88600000-0000-0000-0000-000000000001');

do $$
#variable_conflict use_variable
declare
  review_id uuid;
  incident_id uuid;
begin
  review_id := public.submit_review(
    current_setting('app.rider_booking_id')::uuid,
    current_setting('app.center_a_id')::uuid,
    5,
    'Public review comment'
  );
  perform set_config('app.review_id', review_id::text, true);

  if public.submit_review(
    current_setting('app.rider_booking_id')::uuid,
    current_setting('app.center_a_id')::uuid,
    4,
    'mutated'
  ) is distinct from review_id then
    raise exception 'Replay review created a second row';
  end if;

  incident_id := public.report_incident(
    current_setting('app.rider_booking_id')::uuid,
    current_setting('app.rider_session_id')::uuid,
    'Private incident description'
  );
  perform set_config('app.incident_id', incident_id::text, true);

  perform public.report_incident(
    current_setting('app.rider_booking_id')::uuid,
    current_setting('app.rider_session_id')::uuid,
    'Second incident'
  );
end;
$$;

reset role;

do $$
#variable_conflict use_variable
declare
  review_id uuid := current_setting('app.review_id')::uuid;
  incident_id uuid := current_setting('app.incident_id')::uuid;
  session_id uuid := current_setting('app.rider_session_id')::uuid;
begin
  if (
    select count(*) from public.audit_events
     where entity_id = review_id and event_type = 'review_submitted'
  ) <> 1 then
    raise exception 'Expected one review_submitted audit';
  end if;

  if (
    select audit.metadata->>'rating'
      from public.audit_events as audit
     where audit.entity_id = review_id
  ) is distinct from '5' then
    raise exception 'Review audit rating was missing or mutated';
  end if;

  if exists (
    select 1 from public.audit_events as audit
     where audit.entity_id = review_id
       and audit.metadata ? 'comment'
  ) then
    raise exception 'Review comment must not be stored in audit metadata';
  end if;

  if (
    select count(*) from public.audit_events
     where event_type = 'incident_reported'
       and metadata->>'session_id' = session_id::text
  ) <> 2 then
    raise exception 'Expected two incident_reported audits';
  end if;

  if exists (
    select 1 from public.audit_events as audit
     where audit.event_type = 'incident_reported'
       and (
         audit.metadata ? 'description'
         or audit.metadata::text ilike '%Private incident%'
       )
  ) then
    raise exception 'Incident description must not be stored in audit metadata';
  end if;
end;
$$;

set local role authenticated;
select pg_temp.set_auth('88600000-0000-0000-0000-000000000002');

do $$
begin
  begin
    perform public.submit_review(
      current_setting('app.rider_booking_id')::uuid,
      current_setting('app.center_a_id')::uuid,
      5
    );
    raise exception 'Unrelated caller submitted a review';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform public.report_incident(
      current_setting('app.rider_booking_id')::uuid,
      current_setting('app.rider_session_id')::uuid,
      'nope'
    );
    raise exception 'Unrelated caller reported an incident';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

reset role;

do $$
#variable_conflict use_variable
declare
  after_unrelated integer;
begin
  -- Inspect as postgres; authenticated cannot SELECT audit_events.
  select count(*) into after_unrelated
    from public.audit_events
   where actor_account_id = (
     select id from public.user_accounts
      where auth_user_id = '88600000-0000-0000-0000-000000000002'
   );

  if after_unrelated <> 0 then
    raise exception 'Unauthorized caller wrote audit';
  end if;
end;
$$;

set local role authenticated;
select pg_temp.set_auth('88600000-0000-0000-0000-000000000005');

do $$
begin
  perform public.report_incident(
    current_setting('app.rider_booking_id')::uuid,
    current_setting('app.rider_session_id')::uuid,
    'Staff safety note'
  );
end;
$$;

reset role;

do $$
begin
  if (
    select count(*) from public.audit_events
     where event_type = 'incident_reported'
       and actor_account_id = current_setting('app.staff_account_id')::uuid
  ) <> 1 then
    raise exception 'Staff incident was not audited';
  end if;
end;
$$;

reset role;
select pg_temp.set_auth('88600000-0000-0000-0000-000000000001');

do $$
#variable_conflict use_variable
declare
  spoof_id uuid;
begin
  begin
    insert into public.audit_events (
      event_type, entity_type, entity_id
    ) values (
      'session_started',
      'session',
      current_setting('app.rider_session_id')::uuid
    );
    raise exception 'Direct audit insert succeeded';
  exception
    when insufficient_privilege then null;
  end;

  begin
    update public.audit_events
       set event_type = 'tampered'
     where entity_id = current_setting('app.rider_session_id')::uuid;
    raise exception 'Direct audit update succeeded';
  exception
    when insufficient_privilege then null;
  end;

  begin
    delete from public.audit_events
     where entity_id = current_setting('app.rider_session_id')::uuid;
    raise exception 'Direct audit delete succeeded';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform public.record_audit_event(
      'session_started',
      'session',
      current_setting('app.rider_session_id')::uuid,
      jsonb_build_object('jwt', 'secret-value')
    );
    raise exception 'Secret metadata was accepted';
  exception
    when check_violation then null;
  end;

  perform public.set_audit_write(true);
  insert into public.audit_events (
    actor_account_id,
    actor_person_id,
    event_type,
    entity_type,
    entity_id,
    metadata
  ) values (
    current_setting('app.staff_account_id')::uuid,
    current_setting('app.staff_person_id')::uuid,
    'session_started',
    'session',
    current_setting('app.rider_session_id')::uuid,
    jsonb_build_object('booking_id', current_setting('app.rider_booking_id')::uuid)
  ) returning id into spoof_id;
  perform public.set_audit_write(false);

  if (
    select actor_account_id from public.audit_events where id = spoof_id
  ) is distinct from current_setting('app.rider_account_id')::uuid then
    raise exception 'Spoofed audit actor was stored';
  end if;
end;
$$;

set local role authenticated;
select pg_temp.set_auth('88600000-0000-0000-0000-000000000001');

do $$
begin
  begin
    perform * from public.audit_events;
    raise exception 'Authenticated selected audit_events';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform public.record_audit_event(
      'session_started',
      'session',
      current_setting('app.rider_session_id')::uuid
    );
    raise exception 'Authenticated executed record_audit_event';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

reset role;
set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);

do $$
begin
  begin
    perform * from public.audit_events;
    raise exception 'Anon selected audit_events';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

reset role;

do $$
begin
  if has_table_privilege('anon', 'public.audit_events', 'select')
     or has_table_privilege('authenticated', 'public.audit_events', 'select')
     or has_table_privilege('authenticated', 'public.audit_events', 'insert')
  then
    raise exception '026 client table privileges must stay revoked';
  end if;

  if has_function_privilege(
       'authenticated',
       'public.record_audit_event(text,text,uuid,jsonb)',
       'execute'
     )
     or has_function_privilege(
       'authenticated',
       'public.set_audit_write(boolean)',
       'execute'
     )
     or has_function_privilege(
       'anon',
       'public.record_audit_event(text,text,uuid,jsonb)',
       'execute'
     )
  then
    raise exception '026 helpers must not be executable by clients';
  end if;

  if (
    select count(*)
      from pg_catalog.pg_proc as procedure
     where procedure.oid in (
       'public.record_audit_event(text,text,uuid,jsonb)'::regprocedure,
       'public.emit_session_audit()'::regprocedure
     )
       and procedure.prosecdef
       and procedure.proconfig @> array['search_path=pg_catalog, public']
  ) <> 2 then
    raise exception '026 functions lack SECURITY DEFINER or search_path';
  end if;

  if current_setting('app.audit_write', true) = '1' then
    raise exception '026 left audit write GUC enabled';
  end if;
end;
$$;

rollback;
