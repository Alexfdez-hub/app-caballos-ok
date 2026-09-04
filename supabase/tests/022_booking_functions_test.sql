-- Phase 11B local booking-function tests.
-- Assumes migrations 001-current. Later-domain operations are tested separately.
-- Eligibility callers: participant, current VERIFIED guardian, or MANAGE_BOOKINGS.
-- create_booking_request never confirms. confirm_booking needs MANAGE_BOOKINGS
-- and an APPROVED row. A Zero Session result alone does not satisfy
-- ZERO_SESSION_REQUIRED. Runnable without psql meta-commands.

begin;

do $$
declare
  fixture_auth uuid[] := array[
    '99000000-0000-0000-0000-000000000001'::uuid,
    '99000000-0000-0000-0000-000000000002'::uuid,
    '99000000-0000-0000-0000-000000000003'::uuid,
    '99000000-0000-0000-0000-000000000004'::uuid,
    '99000000-0000-0000-0000-000000000005'::uuid,
    '99000000-0000-0000-0000-000000000006'::uuid,
    '99000000-0000-0000-0000-000000000007'::uuid
  ];
  linked_person_ids uuid[];
  fixture_center_ids uuid[];
  fixture_equine_ids uuid[];
  fixture_service_ids uuid[];
  fixture_document_ids uuid[];
  fixture_system_ids uuid[];
  fixture_discipline_ids uuid[];
  fixture_person_ids uuid[];
begin
  select coalesce(array_agg(id), '{}') into fixture_center_ids
    from public.equestrian_centers where slug like 'phase11b-%';
  select coalesce(array_agg(id), '{}') into fixture_equine_ids
    from public.equines where name like 'phase11b-%';
  select coalesce(array_agg(id), '{}') into fixture_service_ids
    from public.center_services where center_id = any(fixture_center_ids);
  select coalesce(array_agg(id), '{}') into fixture_document_ids
    from public.policy_documents where market_code = 'ZP';

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
  delete from public.rider_equine_authorizations
   where equine_id = any(fixture_equine_ids);
  delete from public.zero_sessions
   where equine_id = any(fixture_equine_ids)
      or center_id = any(fixture_center_ids);
  delete from public.rider_assessment_restrictions
   where assessment_id in (
     select id from public.rider_assessments
      where center_id = any(fixture_center_ids)
   );
  delete from public.rider_assessment_disciplines
   where assessment_id in (
     select id from public.rider_assessments
      where center_id = any(fixture_center_ids)
   );
  delete from public.rider_assessments
   where center_id = any(fixture_center_ids);
  delete from public.equine_requirements
   where equine_id = any(fixture_equine_ids);
  select coalesce(array_agg(person_id), '{}') into fixture_person_ids
    from public.user_accounts where auth_user_id = any(fixture_auth);
  delete from public.rider_qualifications
   where rider_person_id = any(fixture_person_ids)
      or verified_by_person_id = any(fixture_person_ids);
  delete from public.rider_profiles
   where person_id = any(fixture_person_ids);
  select coalesce(array_agg(id), '{}') into fixture_system_ids
    from public.qualification_systems where code like 'phase11b-%';
  delete from public.qualification_levels
   where qualification_system_id = any(fixture_system_ids);
  delete from public.qualification_systems
   where id = any(fixture_system_ids);
  select coalesce(array_agg(id), '{}') into fixture_discipline_ids
    from public.disciplines where code like 'phase11b-%';
  delete from public.equine_disciplines
   where discipline_id = any(fixture_discipline_ids)
      or equine_id = any(fixture_equine_ids);
  delete from public.discipline_translations
   where discipline_id = any(fixture_discipline_ids);
  delete from public.disciplines
   where id = any(fixture_discipline_ids);
  delete from public.service_equines
   where service_id = any(fixture_service_ids)
      or equine_id = any(fixture_equine_ids);
  delete from public.center_services
   where id = any(fixture_service_ids);
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
  delete from public.market_age_rules where country_code = 'ZP';
  delete from public.markets where country_code = 'ZP';
  delete from auth.users where id = any(fixture_auth);
end;
$$;

insert into public.markets (country_code, status) values ('ZP', 'ACTIVE');
insert into public.market_age_rules (
  country_code, legal_adult_age, guardian_consent_required, effective_from
) values ('ZP', 18, true, date '2000-01-01');

insert into auth.users (id) values
  ('99000000-0000-0000-0000-000000000001'),
  ('99000000-0000-0000-0000-000000000002'),
  ('99000000-0000-0000-0000-000000000003'),
  ('99000000-0000-0000-0000-000000000004'),
  ('99000000-0000-0000-0000-000000000005'),
  ('99000000-0000-0000-0000-000000000006'),
  ('99000000-0000-0000-0000-000000000007');

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
  center_a_id uuid;
  center_b_id uuid;
  equine_id uuid;
  service_a_id uuid;
  terms_id uuid;
  relationship_id uuid;
  window_start timestamptz := timestamptz '2026-11-01 10:00:00+00';
begin

  if (
    select count(*)
      from pg_catalog.pg_proc as procedure
      join pg_catalog.pg_namespace as namespace
        on namespace.oid = procedure.pronamespace
     where namespace.nspname = 'public'
       and procedure.proname in (
         'check_booking_eligibility',
         'create_booking_request',
         'confirm_booking'
       )
  ) <> 3 then
    raise exception '022 must add the three booking RPCs';
  end if;

  select person_id, id into rider_person_id, rider_account_id
    from public.user_accounts
   where auth_user_id = '99000000-0000-0000-0000-000000000001';
  select person_id into other_person_id
    from public.user_accounts
   where auth_user_id = '99000000-0000-0000-0000-000000000002';
  select person_id, id into guardian_person_id, guardian_account_id
    from public.user_accounts
   where auth_user_id = '99000000-0000-0000-0000-000000000003';
  select person_id into minor_person_id
    from public.user_accounts
   where auth_user_id = '99000000-0000-0000-0000-000000000004';
  select person_id, id into staff_person_id, staff_account_id
    from public.user_accounts
   where auth_user_id = '99000000-0000-0000-0000-000000000005';
  select person_id into assessor_person_id
    from public.user_accounts
   where auth_user_id = '99000000-0000-0000-0000-000000000006';
  select person_id into owner_person_id
    from public.user_accounts
   where auth_user_id = '99000000-0000-0000-0000-000000000007';

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

  insert into public.equestrian_centers (name, slug, country_code, status)
  values ('Phase11B Alpha', 'phase11b-alpha', 'ZP', 'ACTIVE')
  returning id into center_a_id;
  insert into public.equestrian_centers (name, slug, country_code, status)
  values ('Phase11B Beta', 'phase11b-beta', 'ZP', 'ACTIVE')
  returning id into center_b_id;

  insert into public.equines (name, equine_type)
  values ('phase11b-school', 'HORSE')
  returning id into equine_id;

  insert into public.center_memberships (center_id, person_id, role_code)
  values
    (center_a_id, staff_person_id, 'MANAGER'),
    (center_a_id, assessor_person_id, 'ASSESSOR');

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
    (equine_id, center_a_id, staff_person_id, 'ASSESS_RIDERS');

  insert into public.center_services (
    center_id, service_type, name
  ) values (
    center_a_id, 'EQUINE_SESSION', 'Phase11B ride'
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
    timestamptz '2026-11-01 00:00:00+00',
    timestamptz '2026-11-11 00:00:00+00',
    staff_account_id
  );

  insert into public.policy_documents (
    policy_code, policy_type, market_code, locale, version, title, content,
    effective_from, status, requires_reacceptance
  ) values (
    'TERMS_ZP', 'TERMS_OF_SERVICE', 'ZP', 'es', '1',
    'Terms', 'Phase 11B terms', now() - interval '1 day', 'ACTIVE', false
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
    guardian_account_id, 'EQUESTRIAN_ACTIVITY', 'GENERAL', 'phase11b', 'ACTIVE'
  );

  perform set_config('app.rider_person_id', rider_person_id::text, true);
  perform set_config('app.rider_account_id', rider_account_id::text, true);
  perform set_config('app.other_person_id', other_person_id::text, true);
  perform set_config('app.guardian_person_id', guardian_person_id::text, true);
  perform set_config('app.guardian_account_id', guardian_account_id::text, true);
  perform set_config('app.minor_person_id', minor_person_id::text, true);
  perform set_config('app.terms_id', terms_id::text, true);
  perform set_config('app.staff_person_id', staff_person_id::text, true);
  perform set_config('app.staff_account_id', staff_account_id::text, true);
  perform set_config('app.assessor_person_id', assessor_person_id::text, true);
  perform set_config('app.owner_person_id', owner_person_id::text, true);
  perform set_config('app.center_a_id', center_a_id::text, true);
  perform set_config('app.center_b_id', center_b_id::text, true);
  perform set_config('app.equine_id', equine_id::text, true);
  perform set_config('app.service_a_id', service_a_id::text, true);
  perform set_config('app.window_start', window_start::text, true);
end;
$$;

-- Rider can check eligibility.
set local role authenticated;
select set_config('request.jwt.claim.sub', '99000000-0000-0000-0000-000000000001', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"99000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);

do $$
declare
  overall text;
  created_id uuid;
begin
  select eligibility.overall_status
    into overall
    from public.check_booking_eligibility(
      current_setting('app.rider_person_id')::uuid,
      current_setting('app.equine_id')::uuid,
      current_setting('app.center_a_id')::uuid,
      current_setting('app.window_start')::timestamptz,
      current_setting('app.window_start')::timestamptz + interval '1 hour',
      current_setting('app.service_a_id')::uuid
    ) as eligibility
   limit 1;

  if overall is distinct from 'ELIGIBLE' then
    raise exception 'Adult rider should be ELIGIBLE, got %', overall;
  end if;

  created_id := public.create_booking_request(
    current_setting('app.rider_person_id')::uuid,
    current_setting('app.equine_id')::uuid,
    current_setting('app.center_a_id')::uuid,
    current_setting('app.service_a_id')::uuid,
    current_setting('app.window_start')::timestamptz,
    current_setting('app.window_start')::timestamptz + interval '1 hour'
  );
  perform set_config('app.created_booking_id', created_id::text, true);

  begin
    perform public.confirm_booking(created_id);
    raise exception 'Booker confirmed without MANAGE_BOOKINGS';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

reset role;

do $$
begin
  if (
    select booking.status
      from public.bookings as booking
     where booking.id = current_setting('app.created_booking_id')::uuid
  ) is distinct from 'APPROVED' then
    raise exception 'create_booking_request did not classify ELIGIBLE as APPROVED';
  end if;

  if (
    select booking.status
      from public.bookings as booking
     where booking.id = current_setting('app.created_booking_id')::uuid
  ) = 'CONFIRMED' then
    raise exception 'create_booking_request confirmed a booking';
  end if;
end;
$$;

-- Unrelated account cannot check.
set local role authenticated;
select set_config('request.jwt.claim.sub', '99000000-0000-0000-0000-000000000002', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"99000000-0000-0000-0000-000000000002","role":"authenticated"}',
  true
);

do $$
begin
  begin
    perform * from public.check_booking_eligibility(
      current_setting('app.rider_person_id')::uuid,
      current_setting('app.equine_id')::uuid,
      current_setting('app.center_a_id')::uuid,
      current_setting('app.window_start')::timestamptz,
      current_setting('app.window_start')::timestamptz + interval '1 hour',
      current_setting('app.service_a_id')::uuid
    );
    raise exception 'Unrelated account checked eligibility';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform public.create_booking_request(
      current_setting('app.rider_person_id')::uuid,
      current_setting('app.equine_id')::uuid,
      current_setting('app.center_a_id')::uuid,
      current_setting('app.service_a_id')::uuid,
      current_setting('app.window_start')::timestamptz + interval '6 hours',
      current_setting('app.window_start')::timestamptz + interval '7 hours'
    );
    raise exception 'Unrelated account created a booking request';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform * from public.bookings;
    raise exception 'Authenticated role selected bookings';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform public.confirm_booking(
      current_setting('app.created_booking_id')::uuid
    );
    raise exception 'Unrelated account confirmed a booking';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

-- Guardian can check and request for the minor.
select set_config('request.jwt.claim.sub', '99000000-0000-0000-0000-000000000003', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"99000000-0000-0000-0000-000000000003","role":"authenticated"}',
  true
);

do $$
declare
  overall text;
  minor_booking uuid;
begin
  select eligibility.overall_status
    into overall
    from public.check_booking_eligibility(
      current_setting('app.minor_person_id')::uuid,
      current_setting('app.equine_id')::uuid,
      current_setting('app.center_a_id')::uuid,
      current_setting('app.window_start')::timestamptz + interval '8 hours',
      current_setting('app.window_start')::timestamptz + interval '9 hours',
      current_setting('app.service_a_id')::uuid
    ) as eligibility
   limit 1;

  if overall is distinct from 'ELIGIBLE' then
    raise exception 'Verified guardian should see ELIGIBLE for the minor, got %', overall;
  end if;

  minor_booking := public.create_booking_request(
    current_setting('app.minor_person_id')::uuid,
    current_setting('app.equine_id')::uuid,
    current_setting('app.center_a_id')::uuid,
    current_setting('app.service_a_id')::uuid,
    current_setting('app.window_start')::timestamptz + interval '8 hours',
    current_setting('app.window_start')::timestamptz + interval '9 hours'
  );
  perform set_config('app.minor_booking_id', minor_booking::text, true);
end;
$$;

reset role;

-- Confirm must work with MANAGE_BOOKINGS and without MANAGE_AVAILABILITY.
do $$
begin
  update public.equine_center_permissions
     set status = 'REVOKED',
         revoked_at = now()
   where equine_id = current_setting('app.equine_id')::uuid
     and permission_code = 'MANAGE_AVAILABILITY'
     and status = 'ACTIVE';
end;
$$;

-- ASSESSOR membership is not confirm authority.
set local role authenticated;
select set_config('request.jwt.claim.sub', '99000000-0000-0000-0000-000000000006', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"99000000-0000-0000-0000-000000000006","role":"authenticated"}',
  true
);

do $$
begin
  begin
    perform public.confirm_booking(
      current_setting('app.created_booking_id')::uuid
    );
    raise exception 'ASSESSOR confirmed a booking';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

reset role;

-- Staff with MANAGE_BOOKINGS can check and confirm. Confirm only APPROVED.
set local role authenticated;
select set_config('request.jwt.claim.sub', '99000000-0000-0000-0000-000000000005', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"99000000-0000-0000-0000-000000000005","role":"authenticated"}',
  true
);

do $$
declare
  overall text;
  confirmed_id uuid;
  pending_id uuid;
begin
  select eligibility.overall_status
    into overall
    from public.check_booking_eligibility(
      current_setting('app.rider_person_id')::uuid,
      current_setting('app.equine_id')::uuid,
      current_setting('app.center_a_id')::uuid,
      current_setting('app.window_start')::timestamptz,
      current_setting('app.window_start')::timestamptz + interval '1 hour',
      current_setting('app.service_a_id')::uuid
    ) as eligibility
   limit 1;

  if overall is distinct from 'ELIGIBLE' then
    raise exception 'MANAGE_BOOKINGS staff should inspect eligibility, got %', overall;
  end if;

  begin
    perform public.create_booking_request(
      current_setting('app.rider_person_id')::uuid,
      current_setting('app.equine_id')::uuid,
      current_setting('app.center_a_id')::uuid,
      current_setting('app.service_a_id')::uuid,
      current_setting('app.window_start')::timestamptz + interval '10 hours',
      current_setting('app.window_start')::timestamptz + interval '11 hours'
    );
    raise exception 'Staff created a booking without being the booker or guardian';
  exception
    when insufficient_privilege then null;
  end;

  perform set_config('app.confirm_pause_after_eval', '1', true);
  perform set_config('statement_timeout', '5s', true);

  confirmed_id := public.confirm_booking(
    current_setting('app.created_booking_id')::uuid
  );

  perform set_config('statement_timeout', '0', true);

  if exists (
    select 1
      from pg_locks as advisory_lock
     where advisory_lock.locktype = 'advisory'
       and advisory_lock.classid = 0
       and advisory_lock.objid in (22022021, 22022022)
       and advisory_lock.granted
       and advisory_lock.pid = pg_backend_pid()
  ) then
    raise exception 'confirm_booking honored a caller-controlled pause GUC';
  end if;

  if confirmed_id is distinct from current_setting('app.created_booking_id')::uuid then
    raise exception 'confirm_booking did not return the booking id';
  end if;
end;
$$;

reset role;

do $$
declare
  pending_id uuid;
begin
  if (
    select booking.status
      from public.bookings as booking
     where booking.id = current_setting('app.created_booking_id')::uuid
  ) is distinct from 'CONFIRMED' then
    raise exception 'confirm_booking did not set CONFIRMED';
  end if;

  if (
    select booking.confirmed_at
      from public.bookings as booking
     where booking.id = current_setting('app.created_booking_id')::uuid
  ) is null then
    raise exception 'confirm_booking did not set confirmed_at';
  end if;

  if not exists (
    select 1
      from public.equine_calendar_blocks as calendar_block
     where calendar_block.source_id = current_setting('app.created_booking_id')::uuid
       and calendar_block.block_type = 'BOOKING'
       and calendar_block.source_type = 'BOOKING'
       and calendar_block.status = 'ACTIVE'
  ) then
    raise exception 'confirm_booking did not create a BOOKING calendar block';
  end if;

  if not exists (
    select 1
      from public.booking_requirements as requirement
     where requirement.booking_id = current_setting('app.created_booking_id')::uuid
       and requirement.requirement_type = 'POLICY_ACCEPTANCE'
       and requirement.status = 'SATISFIED'
  ) then
    raise exception 'Successful confirm did not retain SATISFIED policy requirement rows';
  end if;

  if exists (
    select 1
      from public.booking_requirements as requirement
     where requirement.booking_id = current_setting('app.created_booking_id')::uuid
       and requirement.status = 'PENDING'
  ) then
    raise exception 'CONFIRMED booking stored PENDING requirement rows';
  end if;

  perform set_config(
    'app.confirmed_policy_snapshot',
    (
      select booking.booking_policy_snapshot::text
        from public.bookings as booking
       where booking.id = current_setting('app.created_booking_id')::uuid
    ),
    true
  );
  perform set_config(
    'app.confirmed_requirement_fingerprint',
    (
      select coalesce(
        string_agg(
          requirement.requirement_type || ':' || requirement.status || ':' ||
            coalesce(requirement.source_id::text, 'none'),
          '|'
          order by requirement.requirement_type, requirement.source_id
        ),
        ''
      )
        from public.booking_requirements as requirement
       where requirement.booking_id = current_setting('app.created_booking_id')::uuid
    ),
    true
  );

  insert into public.bookings (
    participant_person_id, booked_by_account_id, equine_id, center_id,
    service_id, starts_at, ends_at, status, eligibility_status
  ) values (
    current_setting('app.rider_person_id')::uuid,
    current_setting('app.rider_account_id')::uuid,
    current_setting('app.equine_id')::uuid,
    current_setting('app.center_a_id')::uuid,
    current_setting('app.service_a_id')::uuid,
    current_setting('app.window_start')::timestamptz + interval '2 hours',
    current_setting('app.window_start')::timestamptz + interval '3 hours',
    'PENDING_REQUIREMENTS',
    'REQUIRES_ZERO_SESSION'
  ) returning id into pending_id;
  perform set_config('app.pending_booking_id', pending_id::text, true);
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '99000000-0000-0000-0000-000000000005', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"99000000-0000-0000-0000-000000000005","role":"authenticated"}',
  true
);

do $$
begin
  begin
    perform public.confirm_booking(current_setting('app.pending_booking_id')::uuid);
    raise exception 'Non-APPROVED booking was confirmed';
  exception
    when check_violation then null;
  end;
end;
$$;

reset role;

-- Overlapping confirms: two APPROVED rows, second confirm must fail.
do $$
declare
  first_id uuid;
  second_id uuid;
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
    current_setting('app.window_start')::timestamptz + interval '4 hours',
    current_setting('app.window_start')::timestamptz + interval '5 hours',
    'APPROVED',
    'ELIGIBLE'
  ) returning id into first_id;

  insert into public.bookings (
    participant_person_id, booked_by_account_id, equine_id, center_id,
    service_id, starts_at, ends_at, status, eligibility_status
  ) values (
    current_setting('app.rider_person_id')::uuid,
    current_setting('app.rider_account_id')::uuid,
    current_setting('app.equine_id')::uuid,
    current_setting('app.center_a_id')::uuid,
    current_setting('app.service_a_id')::uuid,
    current_setting('app.window_start')::timestamptz + interval '4 hours',
    current_setting('app.window_start')::timestamptz + interval '5 hours',
    'APPROVED',
    'ELIGIBLE'
  ) returning id into second_id;

  perform set_config('app.overlap_first_id', first_id::text, true);
  perform set_config('app.overlap_second_id', second_id::text, true);
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '99000000-0000-0000-0000-000000000005', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"99000000-0000-0000-0000-000000000005","role":"authenticated"}',
  true
);

do $$
begin
  perform public.confirm_booking(current_setting('app.overlap_first_id')::uuid);

  begin
    perform public.confirm_booking(current_setting('app.overlap_second_id')::uuid);
    raise exception 'Overlapping confirm both succeeded';
  exception
    when exclusion_violation then null;
    when insufficient_privilege then null;
  end;
end;
$$;

reset role;

-- ZERO_SESSION result alone is not enough; effective authorization is.
do $$
declare
  approved_session uuid;
begin
  insert into public.equine_requirements (
    equine_id, requirement_type, boolean_value, source_type
  ) values (
    current_setting('app.equine_id')::uuid,
    'ZERO_SESSION_REQUIRED',
    true,
    'CENTER'
  );

  insert into public.zero_sessions (
    rider_person_id, equine_id, center_id, requested_by_account_id,
    evaluator_person_id, result, performed_at
  ) values (
    current_setting('app.rider_person_id')::uuid,
    current_setting('app.equine_id')::uuid,
    current_setting('app.center_a_id')::uuid,
    current_setting('app.rider_account_id')::uuid,
    current_setting('app.assessor_person_id')::uuid,
    'APPROVED',
    now()
  ) returning id into approved_session;
  perform set_config('app.approved_session_id', approved_session::text, true);
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '99000000-0000-0000-0000-000000000001', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"99000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);

do $$
declare
  overall text;
begin
  select eligibility.overall_status
    into overall
    from public.check_booking_eligibility(
      current_setting('app.rider_person_id')::uuid,
      current_setting('app.equine_id')::uuid,
      current_setting('app.center_a_id')::uuid,
      current_setting('app.window_start')::timestamptz + interval '12 hours',
      current_setting('app.window_start')::timestamptz + interval '13 hours',
      current_setting('app.service_a_id')::uuid
    ) as eligibility
   limit 1;

  if overall is distinct from 'REQUIRES_ZERO_SESSION' then
    raise exception 'Zero Session result alone must not satisfy ZERO_SESSION_REQUIRED, got %', overall;
  end if;
end;
$$;

reset role;

do $$
begin
  insert into public.rider_equine_authorizations (
    rider_person_id, equine_id, authorization_type, issued_by_person_id,
    source_zero_session_id, center_id
  ) values (
    current_setting('app.rider_person_id')::uuid,
    current_setting('app.equine_id')::uuid,
    'ZERO_SESSION',
    current_setting('app.assessor_person_id')::uuid,
    current_setting('app.approved_session_id')::uuid,
    current_setting('app.center_a_id')::uuid
  );
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '99000000-0000-0000-0000-000000000001', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"99000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);

do $$
declare
  overall text;
begin
  select eligibility.overall_status
    into overall
    from public.check_booking_eligibility(
      current_setting('app.rider_person_id')::uuid,
      current_setting('app.equine_id')::uuid,
      current_setting('app.center_a_id')::uuid,
      current_setting('app.window_start')::timestamptz + interval '12 hours',
      current_setting('app.window_start')::timestamptz + interval '13 hours',
      current_setting('app.service_a_id')::uuid
    ) as eligibility
   limit 1;

  if overall is distinct from 'ELIGIBLE' then
    raise exception 'Effective ZERO_SESSION authorization should satisfy the requirement, got %', overall;
  end if;
end;
$$;

reset role;

-- OWNER_APPROVAL and CENTER assessment.
do $$
begin
  update public.equine_requirements
     set status = 'INACTIVE'
   where equine_id = current_setting('app.equine_id')::uuid
     and requirement_type = 'ZERO_SESSION_REQUIRED';

  insert into public.equine_requirements (
    equine_id, requirement_type, boolean_value, source_type
  ) values (
    current_setting('app.equine_id')::uuid,
    'OWNER_APPROVAL_REQUIRED',
    true,
    'OWNER'
  );
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '99000000-0000-0000-0000-000000000001', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"99000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);

do $$
declare
  overall text;
begin
  select eligibility.overall_status
    into overall
    from public.check_booking_eligibility(
      current_setting('app.rider_person_id')::uuid,
      current_setting('app.equine_id')::uuid,
      current_setting('app.center_a_id')::uuid,
      current_setting('app.window_start')::timestamptz + interval '14 hours',
      current_setting('app.window_start')::timestamptz + interval '15 hours',
      current_setting('app.service_a_id')::uuid
    ) as eligibility
   limit 1;

  if overall is distinct from 'REQUIRES_OWNER_APPROVAL' then
    raise exception 'Missing OWNER_APPROVAL must block, got %', overall;
  end if;
end;
$$;

reset role;

do $$
begin
  insert into public.rider_equine_authorizations (
    rider_person_id, equine_id, authorization_type, issued_by_person_id
  ) values (
    current_setting('app.rider_person_id')::uuid,
    current_setting('app.equine_id')::uuid,
    'OWNER_APPROVAL',
    current_setting('app.owner_person_id')::uuid
  );
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '99000000-0000-0000-0000-000000000001', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"99000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);

do $$
declare
  overall text;
begin
  select eligibility.overall_status
    into overall
    from public.check_booking_eligibility(
      current_setting('app.rider_person_id')::uuid,
      current_setting('app.equine_id')::uuid,
      current_setting('app.center_a_id')::uuid,
      current_setting('app.window_start')::timestamptz + interval '14 hours',
      current_setting('app.window_start')::timestamptz + interval '15 hours',
      current_setting('app.service_a_id')::uuid
    ) as eligibility
   limit 1;

  if overall is distinct from 'ELIGIBLE' then
    raise exception 'Effective OWNER_APPROVAL should satisfy the requirement, got %', overall;
  end if;
end;
$$;

reset role;

do $$
begin
  update public.equine_requirements
     set status = 'INACTIVE'
   where equine_id = current_setting('app.equine_id')::uuid
     and requirement_type = 'OWNER_APPROVAL_REQUIRED';

  insert into public.equine_requirements (
    equine_id, requirement_type, boolean_value, source_type
  ) values (
    current_setting('app.equine_id')::uuid,
    'CENTER_ASSESSMENT_REQUIRED',
    true,
    'CENTER'
  );
end;
$$;

-- Other-center VALID assessment must not satisfy. Assessor is only at center A,
-- so the insert above should have been rejected. Recreate assessor at B for the
-- negative fixture, then prove a VALID row at A is required.
do $$
begin
  begin
    insert into public.rider_assessments (
      rider_person_id, center_id, assessor_person_id, assessment_type,
      performed_at, valid_until, status
    ) values (
      current_setting('app.rider_person_id')::uuid,
      current_setting('app.center_b_id')::uuid,
      current_setting('app.assessor_person_id')::uuid,
      'PRACTICAL_TEST',
      timestamptz '2026-04-01 00:00:00+00',
      timestamptz '2027-04-01 00:00:00+00',
      'VALID'
    );
    raise exception 'Assessment at another Center without ASSESSOR membership was allowed';
  exception
    when insufficient_privilege then null;
  end;

  insert into public.center_memberships (center_id, person_id, role_code)
  values (
    current_setting('app.center_b_id')::uuid,
    current_setting('app.assessor_person_id')::uuid,
    'ASSESSOR'
  );

  insert into public.rider_assessments (
    rider_person_id, center_id, assessor_person_id, assessment_type,
    performed_at, valid_until, status
  ) values (
    current_setting('app.rider_person_id')::uuid,
    current_setting('app.center_b_id')::uuid,
    current_setting('app.assessor_person_id')::uuid,
    'PRACTICAL_TEST',
    timestamptz '2026-04-01 00:00:00+00',
    timestamptz '2027-04-01 00:00:00+00',
    'VALID'
  );
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '99000000-0000-0000-0000-000000000001', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"99000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);

do $$
declare
  overall text;
begin
  select eligibility.overall_status
    into overall
    from public.check_booking_eligibility(
      current_setting('app.rider_person_id')::uuid,
      current_setting('app.equine_id')::uuid,
      current_setting('app.center_a_id')::uuid,
      current_setting('app.window_start')::timestamptz + interval '16 hours',
      current_setting('app.window_start')::timestamptz + interval '17 hours',
      current_setting('app.service_a_id')::uuid
    ) as eligibility
   limit 1;

  if overall is distinct from 'REQUIRES_CENTER_ASSESSMENT' then
    raise exception 'Other-center VALID assessment must not satisfy, got %', overall;
  end if;
end;
$$;

reset role;

do $$
begin
  insert into public.rider_assessments (
    rider_person_id, center_id, assessor_person_id, assessment_type,
    performed_at, valid_until, status
  ) values (
    current_setting('app.rider_person_id')::uuid,
    current_setting('app.center_a_id')::uuid,
    current_setting('app.assessor_person_id')::uuid,
    'ACCESS_TEST',
    timestamptz '2026-04-01 00:00:00+00',
    timestamptz '2027-04-01 00:00:00+00',
    'VALID'
  );
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '99000000-0000-0000-0000-000000000001', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"99000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);

do $$
declare
  overall text;
begin
  select eligibility.overall_status
    into overall
    from public.check_booking_eligibility(
      current_setting('app.rider_person_id')::uuid,
      current_setting('app.equine_id')::uuid,
      current_setting('app.center_a_id')::uuid,
      current_setting('app.window_start')::timestamptz + interval '16 hours',
      current_setting('app.window_start')::timestamptz + interval '17 hours',
      current_setting('app.service_a_id')::uuid
    ) as eligibility
   limit 1;

  if overall is distinct from 'ELIGIBLE' then
    raise exception 'Current VALID assessment at that Center should satisfy, got %', overall;
  end if;

  begin
    insert into public.bookings (
      participant_person_id, booked_by_account_id, equine_id, center_id,
      service_id, starts_at, ends_at
    ) values (
      current_setting('app.rider_person_id')::uuid,
      current_setting('app.rider_account_id')::uuid,
      current_setting('app.equine_id')::uuid,
      current_setting('app.center_a_id')::uuid,
      current_setting('app.service_a_id')::uuid,
      timestamptz '2026-11-02 10:00:00+00',
      timestamptz '2026-11-02 11:00:00+00'
    );
    raise exception 'Authenticated role inserted a booking';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

reset role;

-- P0-1: service-equine compatibility.
do $$
declare
  missing_service uuid;
  compat_service uuid;
  overall text;
begin
  insert into public.center_services (
    center_id, service_type, name
  ) values (
    current_setting('app.center_a_id')::uuid,
    'EQUINE_SESSION',
    'Phase11B missing link'
  ) returning id into missing_service;

  insert into public.center_services (
    center_id, service_type, name
  ) values (
    current_setting('app.center_a_id')::uuid,
    'EQUINE_SESSION',
    'Phase11B compat'
  ) returning id into compat_service;
  perform set_config('app.compat_service_id', compat_service::text, true);

  select eligibility.overall_status
    into overall
    from public.collect_booking_eligibility(
      current_setting('app.rider_person_id')::uuid,
      current_setting('app.equine_id')::uuid,
      current_setting('app.center_a_id')::uuid,
      current_setting('app.window_start')::timestamptz + interval '20 hours',
      current_setting('app.window_start')::timestamptz + interval '21 hours',
      missing_service,
      current_setting('app.rider_person_id')::uuid
    ) as eligibility
   where eligibility.detail = 'No matching service_equines link'
   limit 1;

  if overall is distinct from 'NOT_ELIGIBLE' then
    raise exception 'Missing service_equines link must be NOT_ELIGIBLE, got %', overall;
  end if;

  insert into public.service_equines (
    service_id, equine_id, enabled, status
  ) values (
    compat_service,
    current_setting('app.equine_id')::uuid,
    true,
    'INACTIVE'
  );

  select eligibility.overall_status
    into overall
    from public.collect_booking_eligibility(
      current_setting('app.rider_person_id')::uuid,
      current_setting('app.equine_id')::uuid,
      current_setting('app.center_a_id')::uuid,
      current_setting('app.window_start')::timestamptz + interval '20 hours',
      current_setting('app.window_start')::timestamptz + interval '21 hours',
      compat_service,
      current_setting('app.rider_person_id')::uuid
    ) as eligibility
   where eligibility.detail = 'Service-equine link is not ACTIVE and enabled'
   limit 1;

  if overall is distinct from 'NOT_ELIGIBLE' then
    raise exception 'INACTIVE service_equines link must be NOT_ELIGIBLE, got %', overall;
  end if;

  update public.service_equines
     set status = 'ACTIVE',
         enabled = false
   where service_id = compat_service
     and equine_id = current_setting('app.equine_id')::uuid;

  select eligibility.overall_status
    into overall
    from public.collect_booking_eligibility(
      current_setting('app.rider_person_id')::uuid,
      current_setting('app.equine_id')::uuid,
      current_setting('app.center_a_id')::uuid,
      current_setting('app.window_start')::timestamptz + interval '20 hours',
      current_setting('app.window_start')::timestamptz + interval '21 hours',
      compat_service,
      current_setting('app.rider_person_id')::uuid
    ) as eligibility
   where eligibility.detail = 'Service-equine link is not ACTIVE and enabled'
   limit 1;

  if overall is distinct from 'NOT_ELIGIBLE' then
    raise exception 'Disabled service_equines link must be NOT_ELIGIBLE, got %', overall;
  end if;

  update public.service_equines
     set enabled = true,
         supervision_required = true,
         duration_limit_minutes = null
   where service_id = compat_service
     and equine_id = current_setting('app.equine_id')::uuid;

  select eligibility.overall_status
    into overall
    from public.collect_booking_eligibility(
      current_setting('app.rider_person_id')::uuid,
      current_setting('app.equine_id')::uuid,
      current_setting('app.center_a_id')::uuid,
      current_setting('app.window_start')::timestamptz + interval '20 hours',
      current_setting('app.window_start')::timestamptz + interval '21 hours',
      compat_service,
      current_setting('app.rider_person_id')::uuid
    ) as eligibility
   order by case eligibility.overall_status
     when 'NOT_ELIGIBLE' then 7
     when 'ELIGIBLE_WITH_SUPERVISION' then 1
     else 0
   end desc
   limit 1;

  if overall is distinct from 'ELIGIBLE_WITH_SUPERVISION' then
    raise exception 'service_equines.supervision_required must apply, got %', overall;
  end if;

  update public.service_equines
     set supervision_required = false,
         duration_limit_minutes = 30
   where service_id = compat_service
     and equine_id = current_setting('app.equine_id')::uuid;

  select eligibility.overall_status
    into overall
    from public.collect_booking_eligibility(
      current_setting('app.rider_person_id')::uuid,
      current_setting('app.equine_id')::uuid,
      current_setting('app.center_a_id')::uuid,
      current_setting('app.window_start')::timestamptz + interval '20 hours',
      current_setting('app.window_start')::timestamptz + interval '21 hours',
      compat_service,
      current_setting('app.rider_person_id')::uuid
    ) as eligibility
   where eligibility.detail = 'Requested interval exceeds duration_limit_minutes'
   limit 1;

  if overall is distinct from 'NOT_ELIGIBLE' then
    raise exception 'duration_limit_minutes must block a longer interval, got %', overall;
  end if;
end;
$$;

-- P0-2: MIN_QUALIFICATION and MIN_EXPERIENCE.
do $$
declare
  system_a uuid;
  system_b uuid;
  level_low uuid;
  level_high uuid;
  level_other uuid;
  level_jump uuid;
  jump_discipline_id uuid;
  req_qual uuid;
  req_exp uuid;
  overall text;
begin
  insert into public.disciplines (code)
  values ('phase11b-jump')
  returning id into jump_discipline_id;

  insert into public.qualification_systems (code, name)
  values ('phase11b-sys-a', 'Phase11B system A')
  returning id into system_a;

  insert into public.qualification_systems (code, name)
  values ('phase11b-sys-b', 'Phase11B system B')
  returning id into system_b;

  insert into public.qualification_levels (
    qualification_system_id, code, level_order, name
  ) values (system_a, 'L1', 1, 'Low')
  returning id into level_low;

  insert into public.qualification_levels (
    qualification_system_id, code, level_order, name
  ) values (system_a, 'L2', 2, 'High')
  returning id into level_high;

  insert into public.qualification_levels (
    qualification_system_id, code, level_order, name
  ) values (system_b, 'X1', 9, 'Other system')
  returning id into level_other;

  insert into public.qualification_levels (
    qualification_system_id, code, level_order, name, discipline_id
  ) values (
    system_a, 'L2-JUMP', 2, 'High jump', jump_discipline_id
  ) returning id into level_jump;

  insert into public.equine_requirements (
    equine_id, requirement_type, qualification_level_id, source_type
  ) values (
    current_setting('app.equine_id')::uuid,
    'MIN_QUALIFICATION',
    level_high,
    'CENTER'
  ) returning id into req_qual;

  select eligibility.overall_status
    into overall
    from public.collect_booking_eligibility(
      current_setting('app.rider_person_id')::uuid,
      current_setting('app.equine_id')::uuid,
      current_setting('app.center_a_id')::uuid,
      current_setting('app.window_start')::timestamptz + interval '22 hours',
      current_setting('app.window_start')::timestamptz + interval '23 hours',
      current_setting('app.service_a_id')::uuid,
      current_setting('app.rider_person_id')::uuid
    ) as eligibility
   where eligibility.requirement_type = 'MIN_QUALIFICATION'
   limit 1;

  if overall is distinct from 'QUALIFICATION_NOT_VERIFIED' then
    raise exception 'Missing MIN_QUALIFICATION must be QUALIFICATION_NOT_VERIFIED, got %', overall;
  end if;

  insert into public.rider_qualifications (
    rider_person_id, qualification_level_id, verification_status,
    verified_by_person_id
  ) values (
    current_setting('app.rider_person_id')::uuid,
    level_low,
    'VERIFIED',
    current_setting('app.owner_person_id')::uuid
  );

  select eligibility.overall_status
    into overall
    from public.collect_booking_eligibility(
      current_setting('app.rider_person_id')::uuid,
      current_setting('app.equine_id')::uuid,
      current_setting('app.center_a_id')::uuid,
      current_setting('app.window_start')::timestamptz + interval '22 hours',
      current_setting('app.window_start')::timestamptz + interval '23 hours',
      current_setting('app.service_a_id')::uuid,
      current_setting('app.rider_person_id')::uuid
    ) as eligibility
   where eligibility.requirement_type = 'MIN_QUALIFICATION'
   limit 1;

  if overall is distinct from 'QUALIFICATION_NOT_VERIFIED' then
    raise exception 'Lower-level qualification must not satisfy MIN_QUALIFICATION, got %', overall;
  end if;

  update public.rider_qualifications
     set qualification_level_id = level_other
   where rider_person_id = current_setting('app.rider_person_id')::uuid
     and qualification_level_id = level_low;

  select eligibility.overall_status
    into overall
    from public.collect_booking_eligibility(
      current_setting('app.rider_person_id')::uuid,
      current_setting('app.equine_id')::uuid,
      current_setting('app.center_a_id')::uuid,
      current_setting('app.window_start')::timestamptz + interval '22 hours',
      current_setting('app.window_start')::timestamptz + interval '23 hours',
      current_setting('app.service_a_id')::uuid,
      current_setting('app.rider_person_id')::uuid
    ) as eligibility
   where eligibility.requirement_type = 'MIN_QUALIFICATION'
   limit 1;

  if overall is distinct from 'QUALIFICATION_NOT_VERIFIED' then
    raise exception 'Different-system qualification must not satisfy MIN_QUALIFICATION, got %', overall;
  end if;

  update public.rider_qualifications
     set qualification_level_id = level_high,
         expires_at = current_setting('app.window_start')::timestamptz - interval '1 hour'
   where rider_person_id = current_setting('app.rider_person_id')::uuid
     and qualification_level_id = level_other;

  select eligibility.overall_status
    into overall
    from public.collect_booking_eligibility(
      current_setting('app.rider_person_id')::uuid,
      current_setting('app.equine_id')::uuid,
      current_setting('app.center_a_id')::uuid,
      current_setting('app.window_start')::timestamptz + interval '22 hours',
      current_setting('app.window_start')::timestamptz + interval '23 hours',
      current_setting('app.service_a_id')::uuid,
      current_setting('app.rider_person_id')::uuid
    ) as eligibility
   where eligibility.requirement_type = 'MIN_QUALIFICATION'
   limit 1;

  if overall is distinct from 'QUALIFICATION_NOT_VERIFIED' then
    raise exception 'Expired qualification must not satisfy MIN_QUALIFICATION, got %', overall;
  end if;

  update public.rider_qualifications
     set expires_at = current_setting('app.window_start')::timestamptz + interval '30 days'
   where rider_person_id = current_setting('app.rider_person_id')::uuid
     and qualification_level_id = level_high;

  select eligibility.overall_status
    into overall
    from public.collect_booking_eligibility(
      current_setting('app.rider_person_id')::uuid,
      current_setting('app.equine_id')::uuid,
      current_setting('app.center_a_id')::uuid,
      current_setting('app.window_start')::timestamptz + interval '22 hours',
      current_setting('app.window_start')::timestamptz + interval '23 hours',
      current_setting('app.service_a_id')::uuid,
      current_setting('app.rider_person_id')::uuid
    ) as eligibility
   where eligibility.requirement_type = 'MIN_QUALIFICATION'
   limit 1;

  if overall is distinct from 'ELIGIBLE'
     or not exists (
       select 1
         from public.collect_booking_eligibility(
           current_setting('app.rider_person_id')::uuid,
           current_setting('app.equine_id')::uuid,
           current_setting('app.center_a_id')::uuid,
           current_setting('app.window_start')::timestamptz + interval '22 hours',
           current_setting('app.window_start')::timestamptz + interval '23 hours',
           current_setting('app.service_a_id')::uuid,
           current_setting('app.rider_person_id')::uuid
         ) as eligibility
        where eligibility.requirement_type = 'MIN_QUALIFICATION'
          and eligibility.is_met
     ) then
    raise exception 'Matching VERIFIED qualification should satisfy MIN_QUALIFICATION, got %', overall;
  end if;

  update public.equine_requirements
     set discipline_id = jump_discipline_id
   where id = req_qual;

  select eligibility.overall_status
    into overall
    from public.collect_booking_eligibility(
      current_setting('app.rider_person_id')::uuid,
      current_setting('app.equine_id')::uuid,
      current_setting('app.center_a_id')::uuid,
      current_setting('app.window_start')::timestamptz + interval '22 hours',
      current_setting('app.window_start')::timestamptz + interval '23 hours',
      current_setting('app.service_a_id')::uuid,
      current_setting('app.rider_person_id')::uuid
    ) as eligibility
   where eligibility.requirement_type = 'MIN_QUALIFICATION'
   limit 1;

  if overall is distinct from 'QUALIFICATION_NOT_VERIFIED' then
    raise exception 'Discipline-scoped MIN_QUALIFICATION must ignore unscope qualification, got %', overall;
  end if;

  update public.rider_qualifications
     set qualification_level_id = level_jump
   where rider_person_id = current_setting('app.rider_person_id')::uuid
     and qualification_level_id = level_high;

  select eligibility.overall_status
    into overall
    from public.collect_booking_eligibility(
      current_setting('app.rider_person_id')::uuid,
      current_setting('app.equine_id')::uuid,
      current_setting('app.center_a_id')::uuid,
      current_setting('app.window_start')::timestamptz + interval '22 hours',
      current_setting('app.window_start')::timestamptz + interval '23 hours',
      current_setting('app.service_a_id')::uuid,
      current_setting('app.rider_person_id')::uuid
    ) as eligibility
   where eligibility.requirement_type = 'MIN_QUALIFICATION'
   limit 1;

  if overall is distinct from 'ELIGIBLE' then
    raise exception 'Discipline-scoped VERIFIED qualification should satisfy, got %', overall;
  end if;

  update public.equine_requirements
     set status = 'INACTIVE'
   where id = req_qual;

  insert into public.equine_requirements (
    equine_id, requirement_type, numeric_value, source_type
  ) values (
    current_setting('app.equine_id')::uuid,
    'MIN_EXPERIENCE',
    5,
    'CENTER'
  ) returning id into req_exp;

  select eligibility.overall_status
    into overall
    from public.collect_booking_eligibility(
      current_setting('app.rider_person_id')::uuid,
      current_setting('app.equine_id')::uuid,
      current_setting('app.center_a_id')::uuid,
      current_setting('app.window_start')::timestamptz + interval '22 hours',
      current_setting('app.window_start')::timestamptz + interval '23 hours',
      current_setting('app.service_a_id')::uuid,
      current_setting('app.rider_person_id')::uuid
    ) as eligibility
   where eligibility.requirement_type = 'MIN_EXPERIENCE'
   limit 1;

  if overall is distinct from 'QUALIFICATION_NOT_VERIFIED' then
    raise exception 'Missing experience_start_year must not satisfy MIN_EXPERIENCE, got %', overall;
  end if;

  insert into public.rider_profiles (
    person_id, experience_start_year
  ) values (
    current_setting('app.rider_person_id')::uuid,
    2024
  );

  select eligibility.overall_status
    into overall
    from public.collect_booking_eligibility(
      current_setting('app.rider_person_id')::uuid,
      current_setting('app.equine_id')::uuid,
      current_setting('app.center_a_id')::uuid,
      current_setting('app.window_start')::timestamptz + interval '22 hours',
      current_setting('app.window_start')::timestamptz + interval '23 hours',
      current_setting('app.service_a_id')::uuid,
      current_setting('app.rider_person_id')::uuid
    ) as eligibility
   where eligibility.requirement_type = 'MIN_EXPERIENCE'
   limit 1;

  if overall is distinct from 'QUALIFICATION_NOT_VERIFIED' then
    raise exception 'Too-recent experience_start_year must not satisfy MIN_EXPERIENCE, got %', overall;
  end if;

  update public.rider_profiles
     set experience_start_year = 2018
   where person_id = current_setting('app.rider_person_id')::uuid;

  select eligibility.overall_status
    into overall
    from public.collect_booking_eligibility(
      current_setting('app.rider_person_id')::uuid,
      current_setting('app.equine_id')::uuid,
      current_setting('app.center_a_id')::uuid,
      current_setting('app.window_start')::timestamptz + interval '22 hours',
      current_setting('app.window_start')::timestamptz + interval '23 hours',
      current_setting('app.service_a_id')::uuid,
      current_setting('app.rider_person_id')::uuid
    ) as eligibility
   where eligibility.requirement_type = 'MIN_EXPERIENCE'
   limit 1;

  if overall is distinct from 'ELIGIBLE'
     or not exists (
       select 1
         from public.collect_booking_eligibility(
           current_setting('app.rider_person_id')::uuid,
           current_setting('app.equine_id')::uuid,
           current_setting('app.center_a_id')::uuid,
           current_setting('app.window_start')::timestamptz + interval '22 hours',
           current_setting('app.window_start')::timestamptz + interval '23 hours',
           current_setting('app.service_a_id')::uuid,
           current_setting('app.rider_person_id')::uuid
         ) as eligibility
        where eligibility.requirement_type = 'MIN_EXPERIENCE'
          and eligibility.is_met
     ) then
    raise exception 'experience_start_year should satisfy MIN_EXPERIENCE, got %', overall;
  end if;

  update public.equine_requirements
     set status = 'INACTIVE'
   where id = req_exp;
end;
$$;

-- P0-5: multiple locales/versions and snapshot stability.
do $$
declare
  terms_en uuid;
  rider_old uuid;
  rider_new uuid;
  snapshot_one jsonb;
  snapshot_two jsonb;
  overall text;
begin
  insert into public.policy_documents (
    policy_code, policy_type, market_code, locale, version, title, content,
    effective_from, status, requires_reacceptance
  ) values (
    'TERMS_ZP', 'TERMS_OF_SERVICE', 'ZP', 'en', '1',
    'Terms EN', 'Phase 11B terms EN', now() - interval '1 day', 'ACTIVE', false
  ) returning id into terms_en;

  if not public.has_person_accepted_required_policy(
    current_setting('app.rider_person_id')::uuid,
    'TERMS_OF_SERVICE',
    'ZP',
    current_setting('app.window_start')::timestamptz
  ) then
    raise exception 'Second locale of the same policy_code must not fail closed';
  end if;

  insert into public.policy_acceptances (
    policy_document_id, person_id, user_account_id, accepted_at
  ) values (
    terms_en,
    current_setting('app.rider_person_id')::uuid,
    current_setting('app.rider_account_id')::uuid,
    now()
  );

  snapshot_one := public.snapshot_required_policy_acceptances(
    current_setting('app.rider_person_id')::uuid,
    'ZP',
    current_setting('app.window_start')::timestamptz,
    false
  );
  snapshot_two := public.snapshot_required_policy_acceptances(
    current_setting('app.rider_person_id')::uuid,
    'ZP',
    current_setting('app.window_start')::timestamptz,
    false
  );

  if snapshot_one is distinct from snapshot_two then
    raise exception 'Policy snapshot is not stable';
  end if;

  if jsonb_typeof(snapshot_one -> 'documents') is distinct from 'array'
     or jsonb_array_length(snapshot_one -> 'documents') < 2 then
    raise exception 'Policy snapshot must include accepted current locales';
  end if;

  if (snapshot_one -> 'documents' -> 0 ->> 'locale')
       > (snapshot_one -> 'documents' -> 1 ->> 'locale') then
    raise exception 'Policy snapshot locales are not deterministically ordered';
  end if;

  if (snapshot_one -> 'documents' -> 0 ->> 'document_id') is null
     or (snapshot_one -> 'documents' -> 0 ->> 'policy_code') is null
     or (snapshot_one -> 'documents' -> 0 ->> 'policy_type') is null
     or (snapshot_one -> 'documents' -> 0 ->> 'version') is null then
    raise exception 'Policy snapshot is missing required document fields';
  end if;

  insert into public.policy_documents (
    policy_code, policy_type, market_code, locale, version, title, content,
    effective_from, status, requires_reacceptance
  ) values (
    'TERMS_ZP', 'TERMS_OF_SERVICE', 'ZP', 'es', '2',
    'Terms v2', 'Phase 11B terms v2', now() - interval '1 hour', 'ACTIVE', false
  );

  if public.has_person_accepted_required_policy(
    current_setting('app.rider_person_id')::uuid,
    'TERMS_OF_SERVICE',
    'ZP',
    current_setting('app.window_start')::timestamptz
  ) then
    raise exception 'Simultaneous current versions of one policy_code must fail closed';
  end if;

  select eligibility.overall_status
    into overall
    from public.collect_booking_eligibility(
      current_setting('app.rider_person_id')::uuid,
      current_setting('app.equine_id')::uuid,
      current_setting('app.center_a_id')::uuid,
      current_setting('app.window_start')::timestamptz + interval '18 hours',
      current_setting('app.window_start')::timestamptz + interval '19 hours',
      current_setting('app.service_a_id')::uuid,
      current_setting('app.rider_person_id')::uuid
    ) as eligibility
   where eligibility.requirement_type = 'POLICY_ACCEPTANCE'
     and eligibility.detail like '%Ambiguous current versions%'
   limit 1;

  if overall is distinct from 'NOT_ELIGIBLE' then
    raise exception 'Ambiguous current policy versions must be NOT_ELIGIBLE, got %', overall;
  end if;

  update public.policy_documents
     set effective_to = now()
   where policy_code = 'TERMS_ZP'
     and market_code = 'ZP'
     and version = '2'
     and status = 'ACTIVE';

  insert into public.policy_documents (
    policy_code, policy_type, market_code, locale, version, title, content,
    effective_from, effective_to, status, requires_reacceptance
  ) values (
    'RIDER_ZP', 'RIDER_POLICY', 'ZP', 'es', '1',
    'Old rider', 'obsolete', now() - interval '30 days', now() - interval '1 day',
    'ACTIVE', false
  ) returning id into rider_old;

  insert into public.policy_acceptances (
    policy_document_id, person_id, user_account_id, accepted_at
  ) values (
    rider_old,
    current_setting('app.rider_person_id')::uuid,
    current_setting('app.rider_account_id')::uuid,
    now() - interval '20 days'
  );

  insert into public.policy_documents (
    policy_code, policy_type, market_code, locale, version, title, content,
    effective_from, status, requires_reacceptance
  ) values (
    'RIDER_ZP', 'RIDER_POLICY', 'ZP', 'es', '2',
    'Current rider', 'current', now() - interval '12 hours', 'ACTIVE', false
  ) returning id into rider_new;

  select eligibility.overall_status
    into overall
    from public.collect_booking_eligibility(
      current_setting('app.rider_person_id')::uuid,
      current_setting('app.equine_id')::uuid,
      current_setting('app.center_a_id')::uuid,
      current_setting('app.window_start')::timestamptz + interval '18 hours',
      current_setting('app.window_start')::timestamptz + interval '19 hours',
      current_setting('app.service_a_id')::uuid,
      current_setting('app.rider_person_id')::uuid
    ) as eligibility
   where eligibility.requirement_type = 'POLICY_ACCEPTANCE'
     and eligibility.detail like '%RIDER_POLICY%'
   limit 1;

  if overall is distinct from 'NOT_ELIGIBLE' then
    raise exception 'Obsolete policy version must not satisfy, got %', overall;
  end if;

  insert into public.policy_acceptances (
    policy_document_id, person_id, user_account_id, accepted_at
  ) values (
    rider_new,
    current_setting('app.rider_person_id')::uuid,
    current_setting('app.rider_account_id')::uuid,
    now()
  );

  if not public.has_person_accepted_required_policy(
    current_setting('app.rider_person_id')::uuid,
    'RIDER_POLICY',
    'ZP',
    current_setting('app.window_start')::timestamptz
  ) then
    raise exception 'Current RIDER_POLICY version should satisfy after acceptance';
  end if;

  update public.policy_documents
     set status = 'INACTIVE'
   where id = rider_new;
end;
$$;

-- P0-4: guardian-own and staff-own acceptances never substitute.
do $$
declare
  overall text;
begin
  delete from public.policy_acceptances
   where person_id = current_setting('app.minor_person_id')::uuid
     and policy_document_id = current_setting('app.terms_id')::uuid;

  select eligibility.overall_status
    into overall
    from public.collect_booking_eligibility(
      current_setting('app.minor_person_id')::uuid,
      current_setting('app.equine_id')::uuid,
      current_setting('app.center_a_id')::uuid,
      current_setting('app.window_start')::timestamptz + interval '8 hours',
      current_setting('app.window_start')::timestamptz + interval '9 hours',
      current_setting('app.service_a_id')::uuid,
      current_setting('app.guardian_person_id')::uuid
    ) as eligibility
   where eligibility.requirement_type = 'POLICY_ACCEPTANCE'
   limit 1;

  if overall is distinct from 'NOT_ELIGIBLE' then
    raise exception 'Guardian-own policy acceptance must not satisfy the minor, got %', overall;
  end if;

  insert into public.policy_acceptances (
    policy_document_id, person_id, user_account_id, accepted_at
  ) values (
    current_setting('app.terms_id')::uuid,
    current_setting('app.staff_person_id')::uuid,
    current_setting('app.staff_account_id')::uuid,
    now()
  );

  select eligibility.overall_status
    into overall
    from public.collect_booking_eligibility(
      current_setting('app.minor_person_id')::uuid,
      current_setting('app.equine_id')::uuid,
      current_setting('app.center_a_id')::uuid,
      current_setting('app.window_start')::timestamptz + interval '8 hours',
      current_setting('app.window_start')::timestamptz + interval '9 hours',
      current_setting('app.service_a_id')::uuid,
      current_setting('app.staff_person_id')::uuid
    ) as eligibility
   where eligibility.requirement_type = 'POLICY_ACCEPTANCE'
   limit 1;

  if overall is distinct from 'NOT_ELIGIBLE' then
    raise exception 'Staff-own policy acceptance must not satisfy the minor, got %', overall;
  end if;

  insert into public.policy_acceptances (
    policy_document_id, person_id, user_account_id, accepted_at
  ) values (
    current_setting('app.terms_id')::uuid,
    current_setting('app.minor_person_id')::uuid,
    current_setting('app.staff_account_id')::uuid,
    now()
  );

  select eligibility.overall_status
    into overall
    from public.collect_booking_eligibility(
      current_setting('app.minor_person_id')::uuid,
      current_setting('app.equine_id')::uuid,
      current_setting('app.center_a_id')::uuid,
      current_setting('app.window_start')::timestamptz + interval '8 hours',
      current_setting('app.window_start')::timestamptz + interval '9 hours',
      current_setting('app.service_a_id')::uuid,
      current_setting('app.staff_person_id')::uuid
    ) as eligibility
   where eligibility.requirement_type = 'POLICY_ACCEPTANCE'
   limit 1;

  if overall is distinct from 'NOT_ELIGIBLE' then
    raise exception 'Staff-recorded minor acceptance must not satisfy without a guardian acceptor, got %', overall;
  end if;

  insert into public.policy_acceptances (
    policy_document_id, person_id, user_account_id, accepted_at
  ) values (
    current_setting('app.terms_id')::uuid,
    current_setting('app.minor_person_id')::uuid,
    current_setting('app.guardian_account_id')::uuid,
    now()
  );
end;
$$;

-- P0-3: consent valid now but expired before activity cannot confirm.
do $$
begin
  update public.guardian_consents
     set expires_at = timestamptz '2026-10-01 00:00:00+00'
   where minor_person_id = current_setting('app.minor_person_id')::uuid
     and consent_type = 'EQUESTRIAN_ACTIVITY'
     and status = 'ACTIVE';
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '99000000-0000-0000-0000-000000000005', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"99000000-0000-0000-0000-000000000005","role":"authenticated"}',
  true
);

do $$
declare
  overall text;
begin
  select eligibility.overall_status
    into overall
    from public.check_booking_eligibility(
      current_setting('app.minor_person_id')::uuid,
      current_setting('app.equine_id')::uuid,
      current_setting('app.center_a_id')::uuid,
      current_setting('app.window_start')::timestamptz + interval '8 hours',
      current_setting('app.window_start')::timestamptz + interval '9 hours',
      current_setting('app.service_a_id')::uuid
    ) as eligibility
   limit 1;

  if overall is distinct from 'REQUIRES_GUARDIAN_CONSENT' then
    raise exception 'Consent expiring before activity must block, got %', overall;
  end if;

  begin
    perform public.confirm_booking(current_setting('app.minor_booking_id')::uuid);
    raise exception 'Confirm succeeded when consent expires before activity';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

reset role;

-- P0-6: later equine/policy changes do not rewrite confirmed evidence.
do $$
begin
  insert into public.equine_requirements (
    equine_id, requirement_type, numeric_value, source_type
  ) values (
    current_setting('app.equine_id')::uuid,
    'MIN_AGE',
    99,
    'CENTER'
  );

  begin
    perform public.persist_booking_requirement_rows(
      current_setting('app.created_booking_id')::uuid,
      current_setting('app.rider_person_id')::uuid,
      current_setting('app.equine_id')::uuid,
      current_setting('app.center_a_id')::uuid,
      current_setting('app.window_start')::timestamptz,
      current_setting('app.window_start')::timestamptz + interval '1 hour',
      current_setting('app.service_a_id')::uuid,
      current_setting('app.rider_person_id')::uuid,
      current_setting('app.staff_account_id')::uuid
    );
    raise exception 'persist_booking_requirement_rows rewrote a confirmed booking';
  exception
    when insufficient_privilege then null;
  end;

  if (
    select booking.booking_policy_snapshot::text
      from public.bookings as booking
     where booking.id = current_setting('app.created_booking_id')::uuid
  ) is distinct from current_setting('app.confirmed_policy_snapshot') then
    raise exception 'Confirmed booking_policy_snapshot was rewritten';
  end if;

  if (
    select coalesce(
      string_agg(
        requirement.requirement_type || ':' || requirement.status || ':' ||
          coalesce(requirement.source_id::text, 'none'),
        '|'
        order by requirement.requirement_type, requirement.source_id
      ),
      ''
    )
      from public.booking_requirements as requirement
     where requirement.booking_id = current_setting('app.created_booking_id')::uuid
  ) is distinct from current_setting('app.confirmed_requirement_fingerprint') then
    raise exception 'Confirmed booking_requirements were rewritten after later equine/policy changes';
  end if;

  if exists (
    select 1
      from public.booking_requirements as requirement
     where requirement.booking_id = current_setting('app.created_booking_id')::uuid
       and requirement.requirement_type = 'MIN_AGE'
  ) then
    raise exception 'Later MIN_AGE requirement leaked into a confirmed booking';
  end if;
end;
$$;

do $$
begin
  if has_table_privilege('anon', 'public.bookings', 'select')
     or has_table_privilege('authenticated', 'public.bookings', 'insert')
     or has_table_privilege('authenticated', 'public.bookings', 'update')
     or has_table_privilege('authenticated', 'public.bookings', 'delete')
     or has_table_privilege('authenticated', 'public.booking_requirements', 'insert')
     or has_table_privilege('authenticated', 'public.equine_calendar_blocks', 'insert')
     or has_function_privilege(
       'anon',
       'public.check_booking_eligibility(uuid,uuid,uuid,timestamptz,timestamptz,uuid)',
       'execute'
     )
     or not has_function_privilege(
       'authenticated',
       'public.check_booking_eligibility(uuid,uuid,uuid,timestamptz,timestamptz,uuid)',
       'execute'
     )
     or not has_function_privilege(
       'authenticated',
       'public.create_booking_request(uuid,uuid,uuid,uuid,timestamptz,timestamptz)',
       'execute'
     )
     or not has_function_privilege(
       'authenticated',
       'public.confirm_booking(uuid)',
       'execute'
     )
     or has_function_privilege(
       'authenticated',
       'public.collect_booking_eligibility(uuid,uuid,uuid,timestamptz,timestamptz,uuid,uuid)',
       'execute'
     )
     or has_function_privilege(
       'authenticated',
       'public.has_person_accepted_required_policy(uuid,text,text)',
       'execute'
     )
     or has_function_privilege(
       'authenticated',
       'public.has_person_accepted_required_policy(uuid,text,text,timestamptz)',
       'execute'
     )
     or has_function_privilege(
       'authenticated',
       'public.has_participant_accepted_required_policy(uuid,text,text,timestamptz,boolean)',
       'execute'
     )
     or has_function_privilege(
       'authenticated',
       'public.has_equestrian_activity_consent_at(uuid,timestamptz)',
       'execute'
     )
     or has_function_privilege(
       'authenticated',
       'public.snapshot_required_policy_acceptances(uuid,text,timestamptz,boolean)',
       'execute'
     )
     or has_function_privilege(
       'authenticated',
       'public.rider_satisfies_min_qualification(uuid,uuid,uuid,timestamptz)',
       'execute'
     )
     or has_function_privilege(
       'authenticated',
       'public.rider_satisfies_min_experience(uuid,numeric,timestamptz)',
       'execute'
     )
     or has_function_privilege(
       'authenticated',
       'public.has_ambiguous_current_policy_versions(text,text,timestamptz)',
       'execute'
     )
     or has_function_privilege(
       'authenticated',
       'public.persist_booking_requirement_eval_rows(uuid,jsonb,jsonb,uuid)',
       'execute'
     )
     or has_function_privilege(
       'authenticated',
       'public.materialize_booking_confirm_eval(uuid,uuid,uuid,timestamptz,timestamptz,uuid)',
       'execute'
     )
     or has_function_privilege(
       'authenticated',
       'public.apply_booking_confirm_eval(uuid,jsonb,jsonb,uuid)',
       'execute'
     )
     or to_regprocedure('public.confirm_booking_concurrency_probe(uuid)') is not null
     or pg_get_functiondef('public.confirm_booking(uuid)'::regprocedure)
        ~ 'confirm_pause_after_eval|pg_advisory_lock\\(22022021\\)|pg_sleep'
  then
    raise exception '022 RPC grants or table privileges are wrong';
  end if;
end;
$$;

rollback;
