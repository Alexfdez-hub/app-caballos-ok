-- Phase 13A local reviews/incidents tests.
-- Assumes migrations 001-current. Zero Session approval is tested separately. Runnable without psql meta-commands.

begin;

set session_replication_role = replica;

do $$
#variable_conflict use_variable
declare
  fixture_auth uuid[] := array[
    '88400000-0000-0000-0000-000000000001'::uuid,
    '88400000-0000-0000-0000-000000000002'::uuid,
    '88400000-0000-0000-0000-000000000005'::uuid,
    '88400000-0000-0000-0000-000000000007'::uuid,
    '88400000-0000-0000-0000-000000000008'::uuid
  ];
  fixture_center_ids uuid[];
  fixture_equine_ids uuid[];
  fixture_service_ids uuid[];
  fixture_document_ids uuid[];
  fixture_session_ids uuid[];
  linked_person_ids uuid[];
begin
  select coalesce(array_agg(id), '{}') into fixture_center_ids
    from public.equestrian_centers where slug like 'phase13a-%';
  select coalesce(array_agg(id), '{}') into fixture_equine_ids
    from public.equines where name like 'phase13a-%';
  select coalesce(array_agg(id), '{}') into fixture_service_ids
    from public.center_services where center_id = any(fixture_center_ids);
  select coalesce(array_agg(id), '{}') into fixture_document_ids
    from public.policy_documents where market_code = 'ZV';
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
  delete from public.market_age_rules where country_code = 'ZV';
  delete from public.markets where country_code = 'ZV';
  delete from auth.users where id = any(fixture_auth);
end;
$$;

set session_replication_role = origin;

insert into public.markets (country_code, status) values ('ZV', 'ACTIVE');
insert into public.market_age_rules (
  country_code, legal_adult_age, guardian_consent_required, effective_from
) values ('ZV', 18, true, date '2000-01-01');

insert into auth.users (id) values
  ('88400000-0000-0000-0000-000000000001'),
  ('88400000-0000-0000-0000-000000000002'),
  ('88400000-0000-0000-0000-000000000005'),
  ('88400000-0000-0000-0000-000000000007'),
  ('88400000-0000-0000-0000-000000000008');

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
     where table_schema = 'public'
       and table_name in ('reviews', 'incidents')
  ) then
    raise exception '025 must add reviews and incidents';
  end if;


  if (
    select count(*) from pg_catalog.pg_class
     where oid in ('public.reviews'::regclass, 'public.incidents'::regclass)
       and relrowsecurity
  ) <> 2 then
    raise exception '025 RLS is not enabled';
  end if;

  select person_id, id into rider_person_id, rider_account_id
    from public.user_accounts
   where auth_user_id = '88400000-0000-0000-0000-000000000001';
  select person_id into other_person_id
    from public.user_accounts
   where auth_user_id = '88400000-0000-0000-0000-000000000002';
  select person_id, id into staff_person_id, staff_account_id
    from public.user_accounts
   where auth_user_id = '88400000-0000-0000-0000-000000000005';
  select person_id into owner_person_id
    from public.user_accounts
   where auth_user_id = '88400000-0000-0000-0000-000000000007';
  select person_id into instructor_person_id
    from public.user_accounts
   where auth_user_id = '88400000-0000-0000-0000-000000000008';

  update public.persons
     set first_name = 'Rider13A', last_name = 'Adult', date_of_birth = date '1990-01-01'
   where id = rider_person_id;
  update public.persons
     set first_name = 'Other13A', last_name = 'Adult', date_of_birth = date '1988-01-01'
   where id = other_person_id;
  update public.persons
     set first_name = 'Staff13A', last_name = 'Manager', date_of_birth = date '1985-01-01'
   where id = staff_person_id;
  update public.persons
     set first_name = 'Owner13A', last_name = 'Person', date_of_birth = date '1975-01-01'
   where id = owner_person_id;
  update public.persons
     set first_name = 'Instructor13A', last_name = 'One', date_of_birth = date '1984-01-01'
   where id = instructor_person_id;

  insert into public.equestrian_centers (name, slug, country_code, status)
  values ('Phase13A Alpha', 'phase13a-alpha', 'ZV', 'ACTIVE')
  returning id into center_a_id;

  insert into public.equines (name, equine_type)
  values ('phase13a-school', 'HORSE')
  returning id into equine_id;

  insert into public.equines (name, equine_type)
  values ('phase13a-other', 'HORSE')
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
    (equine_id, center_a_id, staff_person_id, 'MANAGE_REQUIREMENTS');

  insert into public.center_services (center_id, service_type, name)
  values (center_a_id, 'EQUINE_SESSION', 'Phase13A ride')
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
    'TERMS_ZV', 'TERMS_OF_SERVICE', 'ZV', 'es', '1',
    'Terms', 'Phase 13A terms', now() - interval '1 day', 'ACTIVE', false
  ) returning id into terms_id;

  insert into public.policy_acceptances (
    policy_document_id, person_id, user_account_id, accepted_at
  ) values (terms_id, rider_person_id, rider_account_id, now());

  perform set_config('app.rider_person_id', rider_person_id::text, true);
  perform set_config('app.rider_account_id', rider_account_id::text, true);
  perform set_config('app.other_person_id', other_person_id::text, true);
  perform set_config('app.staff_person_id', staff_person_id::text, true);
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
select pg_temp.set_auth('88400000-0000-0000-0000-000000000001');

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
select pg_temp.set_auth('88400000-0000-0000-0000-000000000005');

do $$
begin
  perform public.confirm_booking(current_setting('app.rider_booking_id')::uuid);
end;
$$;

reset role;
set local role authenticated;
select pg_temp.set_auth('88400000-0000-0000-0000-000000000001');

do $$
#variable_conflict use_variable
declare
  session_id uuid;
begin
  session_id := public.start_session(current_setting('app.rider_booking_id')::uuid);
  perform set_config('app.rider_session_id', session_id::text, true);

  begin
    perform public.submit_review(
      current_setting('app.rider_booking_id')::uuid,
      current_setting('app.center_a_id')::uuid,
      5
    );
    raise exception 'Review accepted before the booking was completed';
  exception
    when check_violation then null;
  end;
end;
$$;

reset role;
set local role authenticated;
select pg_temp.set_auth('88400000-0000-0000-0000-000000000001');

do $$
begin
  perform public.end_session(current_setting('app.rider_session_id')::uuid);
end;
$$;

reset role;
set local role authenticated;
select pg_temp.set_auth('88400000-0000-0000-0000-000000000001');

do $$
#variable_conflict use_variable
declare
  review_id uuid;
  replay_id uuid;
  incident_id uuid;
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

  begin
    perform public.submit_review(
      current_setting('app.rider_booking_id')::uuid,
      current_setting('app.center_a_id')::uuid,
      6
    );
    raise exception 'Rating 6 was accepted';
  exception
    when check_violation then null;
  end;

  review_id := public.submit_review(
    current_setting('app.rider_booking_id')::uuid,
    current_setting('app.center_a_id')::uuid,
    5,
    'Public review comment'
  );
  perform set_config('app.review_id', review_id::text, true);

  replay_id := public.submit_review(
    current_setting('app.rider_booking_id')::uuid,
    current_setting('app.center_a_id')::uuid,
    4,
    'mutated'
  );
  if replay_id is distinct from review_id then
    raise exception 'Replay review created a second row';
  end if;

  begin
    perform public.submit_review(
      current_setting('app.rider_booking_id')::uuid,
      current_setting('app.other_equine_id')::uuid,
      5
    );
    raise exception 'Cross-context review subject was accepted';
  exception
    when check_violation then null;
  end;

  incident_id := public.report_incident(
    current_setting('app.rider_booking_id')::uuid,
    current_setting('app.rider_session_id')::uuid,
    'Private incident description'
  );
  perform set_config('app.incident_id', incident_id::text, true);

  begin
    perform public.report_incident(
      current_setting('app.rider_booking_id')::uuid,
      current_setting('app.rider_session_id')::uuid,
      'cross equine',
      current_setting('app.other_equine_id')::uuid
    );
    raise exception 'Cross-context incident equine was accepted';
  exception
    when check_violation then null;
  end;
end;
$$;

reset role;

do $$
#variable_conflict use_variable
declare
  review_id uuid := current_setting('app.review_id')::uuid;
  incident_id uuid := current_setting('app.incident_id')::uuid;
begin
  if (
    select review.rating from public.reviews as review where review.id = review_id
  ) is distinct from 5 then
    raise exception 'Replay review mutated rating';
  end if;

  if (
    select review.comment from public.reviews as review where review.id = review_id
  ) is distinct from 'Public review comment' then
    raise exception 'Replay review mutated comment';
  end if;

  if (
    select review.reviewer_person_id
      from public.reviews as review
     where review.id = review_id
  ) is distinct from current_setting('app.rider_person_id')::uuid then
    raise exception 'Reviewer was not the caller PERSON';
  end if;

  if (
    select incident.description
      from public.incidents as incident
     where incident.id = incident_id
  ) is distinct from 'Private incident description' then
    raise exception 'Incident description was not stored';
  end if;

  if (
    select incident.equine_id
      from public.incidents as incident
     where incident.id = incident_id
  ) is distinct from current_setting('app.equine_id')::uuid then
    raise exception 'Incident equine was not copied from the session';
  end if;
end;
$$;

set local role authenticated;
select pg_temp.set_auth('88400000-0000-0000-0000-000000000002');

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
set local role authenticated;
select pg_temp.set_auth('88400000-0000-0000-0000-000000000008');

do $$
begin
  begin
    perform public.submit_review(
      current_setting('app.rider_booking_id')::uuid,
      current_setting('app.center_a_id')::uuid,
      5
    );
    raise exception 'Instructor submitted a review';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

reset role;
set local role authenticated;
select pg_temp.set_auth('88400000-0000-0000-0000-000000000005');

do $$
#variable_conflict use_variable
declare
  staff_incident uuid;
begin
  begin
    perform public.submit_review(
      current_setting('app.rider_booking_id')::uuid,
      current_setting('app.center_a_id')::uuid,
      5
    );
    raise exception 'Center staff submitted a review';
  exception
    when insufficient_privilege then null;
  end;

  staff_incident := public.report_incident(
    current_setting('app.rider_booking_id')::uuid,
    current_setting('app.rider_session_id')::uuid,
    'Staff safety note'
  );
  if staff_incident is null then
    raise exception 'Center staff could not report an incident';
  end if;
end;
$$;

reset role;

do $$
begin
  begin
    update public.reviews set comment = 'tampered' where id = current_setting('app.review_id')::uuid;
    raise exception 'Direct review update succeeded';
  exception
    when insufficient_privilege then null;
  end;

  begin
    delete from public.reviews where id = current_setting('app.review_id')::uuid;
    raise exception 'Direct review delete succeeded';
  exception
    when insufficient_privilege then null;
  end;

  begin
    update public.incidents set description = 'tampered' where id = current_setting('app.incident_id')::uuid;
    raise exception 'Direct incident update succeeded';
  exception
    when insufficient_privilege then null;
  end;

  begin
    delete from public.incidents where id = current_setting('app.incident_id')::uuid;
    raise exception 'Direct incident delete succeeded';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

set local role authenticated;
select pg_temp.set_auth('88400000-0000-0000-0000-000000000001');

do $$
begin
  begin
    perform * from public.reviews;
    raise exception 'Authenticated selected reviews';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform * from public.incidents;
    raise exception 'Authenticated selected incidents';
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
    perform * from public.reviews;
    raise exception 'Anon selected reviews';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform * from public.incidents;
    raise exception 'Anon selected incidents';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

reset role;

do $$
begin
  if has_table_privilege('anon', 'public.reviews', 'select')
     or has_table_privilege('authenticated', 'public.reviews', 'select')
     or has_table_privilege('authenticated', 'public.reviews', 'insert')
     or has_table_privilege('authenticated', 'public.incidents', 'select')
     or has_table_privilege('authenticated', 'public.incidents', 'insert')
  then
    raise exception '025 client table privileges must stay revoked';
  end if;

  if not has_function_privilege(
       'authenticated',
       'public.submit_review(uuid,uuid,integer,text,text)',
       'execute'
     )
     or not has_function_privilege(
       'authenticated',
       'public.report_incident(uuid,uuid,text,uuid,uuid)',
       'execute'
     )
     or has_function_privilege(
       'anon',
       'public.submit_review(uuid,uuid,integer,text,text)',
       'execute'
     )
  then
    raise exception '025 public RPCs must be executable by authenticated only';
  end if;

  if has_function_privilege(
       'authenticated',
       'public.set_review_write(boolean)',
       'execute'
     )
     or has_function_privilege(
       'authenticated',
       'public.set_incident_write(boolean)',
       'execute'
     )
     or has_function_privilege(
       'authenticated',
       'public.caller_can_submit_review(uuid,uuid)',
       'execute'
     )
  then
    raise exception '025 internal helpers must not be executable by clients';
  end if;

  if (
    select count(*)
      from pg_catalog.pg_proc as procedure
     where procedure.oid in (
       'public.submit_review(uuid,uuid,integer,text,text)'::regprocedure,
       'public.report_incident(uuid,uuid,text,uuid,uuid)'::regprocedure
     )
       and procedure.prosecdef
       and procedure.proconfig @> array['search_path=pg_catalog, public']
  ) <> 2 then
    raise exception '025 RPCs lack SECURITY DEFINER or search_path';
  end if;

  if current_setting('app.review_write', true) = '1'
     or current_setting('app.incident_write', true) = '1' then
    raise exception '025 RPCs left write GUCs enabled';
  end if;
end;
$$;

rollback;
