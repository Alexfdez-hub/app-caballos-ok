-- Issue #35 Stage 1 pilot journey.
-- One transaction. Local/CI only. Ends in ROLLBACK.
-- Fixture rows use deterministic ids. Client steps call existing RPCs.
-- Direct SQL is server-side provisioning, not a new client API.
-- Market QX and adult age 18 are fixture data, not a legal ruling.
-- No Galope catalog, no equine-media policy, no migration 030.

begin;

create function pg_temp.pilot_jwt(p_auth uuid)
returns void
language plpgsql
as $$
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_auth::text, ''), true);
  if p_auth is null then
    perform set_config('request.jwt.claims', '{}', true);
  else
    perform set_config(
      'request.jwt.claims',
      json_build_object('sub', p_auth::text, 'role', 'authenticated')::text,
      true
    );
  end if;
end;
$$;

create function pg_temp.pilot_rebind(
  p_auth uuid,
  p_person uuid,
  p_account uuid,
  p_first text,
  p_last text,
  p_dob date
)
returns void
language plpgsql
as $$
declare
  old_person uuid;
begin
  select account.person_id
    into old_person
    from public.user_accounts as account
   where account.auth_user_id = p_auth;

  delete from public.user_accounts where auth_user_id = p_auth;
  delete from public.persons where id = old_person;

  insert into public.persons (id, first_name, last_name, date_of_birth)
  values (p_person, p_first, p_last, p_dob);

  insert into public.user_accounts (id, auth_user_id, person_id)
  values (p_account, p_auth, p_person);
end;
$$;

create function pg_temp.pilot_overall(
  p_participant uuid,
  p_equine uuid,
  p_center uuid,
  p_starts timestamptz,
  p_ends timestamptz,
  p_service uuid
)
returns text
language plpgsql
as $$
declare
  overall text;
begin
  select ranked.overall_status
    into overall
    from (
      select
        eligibility.overall_status,
        case eligibility.overall_status
          when 'NOT_ELIGIBLE' then 7
          when 'QUALIFICATION_NOT_VERIFIED' then 6
          when 'REQUIRES_GUARDIAN_CONSENT' then 5
          when 'REQUIRES_OWNER_APPROVAL' then 4
          when 'REQUIRES_ZERO_SESSION' then 3
          when 'REQUIRES_CENTER_ASSESSMENT' then 2
          when 'ELIGIBLE_WITH_SUPERVISION' then 1
          else 0
        end as rank
        from public.check_booking_eligibility(
          p_participant,
          p_equine,
          p_center,
          p_starts,
          p_ends,
          p_service
        ) as eligibility
    ) as ranked
   order by ranked.rank desc
   limit 1;

  if overall is null then
    raise exception 'Pilot eligibility returned no row';
  end if;

  return overall;
end;
$$;

grant execute on function pg_temp.pilot_jwt(uuid) to authenticated;
grant execute on function pg_temp.pilot_overall(uuid, uuid, uuid, timestamptz, timestamptz, uuid)
  to authenticated;

insert into auth.users (id) values
  ('03100000-0000-4000-8000-000000000001'),
  ('03100000-0000-4000-8000-000000000002'),
  ('03100000-0000-4000-8000-000000000003'),
  ('03100000-0000-4000-8000-000000000004'),
  ('03100000-0000-4000-8000-000000000005'),
  ('03100000-0000-4000-8000-000000000006'),
  ('03100000-0000-4000-8000-000000000007');

do $$
declare
  accepted_at timestamptz := timestamptz '2026-09-01 00:00:00+00';
  policy_id uuid;
  policy_type text;
  policy_code text;
begin
  perform pg_temp.pilot_rebind(
    '03100000-0000-4000-8000-000000000001',
    '03100000-0000-4000-8000-000000000011',
    '03100000-0000-4000-8000-000000000021',
    'Avery', 'Rider', date '1990-04-12'
  );
  perform pg_temp.pilot_rebind(
    '03100000-0000-4000-8000-000000000002',
    '03100000-0000-4000-8000-000000000012',
    '03100000-0000-4000-8000-000000000022',
    'Quinn', 'Guardian', date '1982-02-02'
  );
  perform pg_temp.pilot_rebind(
    '03100000-0000-4000-8000-000000000003',
    '03100000-0000-4000-8000-000000000013',
    '03100000-0000-4000-8000-000000000023',
    'Indigo', 'Instructor', date '1987-07-07'
  );
  perform pg_temp.pilot_rebind(
    '03100000-0000-4000-8000-000000000004',
    '03100000-0000-4000-8000-000000000014',
    '03100000-0000-4000-8000-000000000024',
    'Morgan', 'Manager', date '1984-08-08'
  );
  perform pg_temp.pilot_rebind(
    '03100000-0000-4000-8000-000000000005',
    '03100000-0000-4000-8000-000000000015',
    '03100000-0000-4000-8000-000000000025',
    'Reese', 'Assessor', date '1981-01-09'
  );
  perform pg_temp.pilot_rebind(
    '03100000-0000-4000-8000-000000000006',
    '03100000-0000-4000-8000-000000000016',
    '03100000-0000-4000-8000-000000000026',
    'Parker', 'Owner', date '1979-05-05'
  );
  perform pg_temp.pilot_rebind(
    '03100000-0000-4000-8000-000000000007',
    '03100000-0000-4000-8000-000000000017',
    '03100000-0000-4000-8000-000000000027',
    'Skyler', 'Intruder', date '1993-03-03'
  );

  insert into public.persons (id, first_name, last_name, date_of_birth)
  values
    ('03100000-0000-4000-8000-000000000018', 'Rowan', 'Minor', date '2014-03-03'),
    ('03100000-0000-4000-8000-000000000019', 'Sage', 'Unconsented', date '2014-06-06'),
    ('03100000-0000-4000-8000-00000000001a', 'Jules', 'Revoked', date '2014-09-09');

  insert into public.markets (country_code, status)
  values ('QX', 'ACTIVE');
  insert into public.market_age_rules (
    country_code, legal_adult_age, guardian_consent_required, effective_from
  ) values ('QX', 18, true, date '2000-01-01');

  insert into public.equestrian_centers (
    id, name, slug, country_code, status
  ) values (
    '03100000-0000-4000-8000-000000000031',
    'Pilot Center',
    'pilot-center',
    'QX',
    'ACTIVE'
  );

  insert into public.equines (id, name, equine_type, visibility_status)
  values
    ('03100000-0000-4000-8000-000000000032', 'Pilot Horse', 'HORSE', 'PRIVATE'),
    ('03100000-0000-4000-8000-000000000033', 'Pilot Pony', 'PONY', 'PRIVATE');

  insert into public.center_memberships (center_id, person_id, role_code)
  values
    ('03100000-0000-4000-8000-000000000031', '03100000-0000-4000-8000-000000000014', 'MANAGER'),
    ('03100000-0000-4000-8000-000000000031', '03100000-0000-4000-8000-000000000013', 'INSTRUCTOR'),
    ('03100000-0000-4000-8000-000000000031', '03100000-0000-4000-8000-000000000015', 'ASSESSOR');

  insert into public.equine_ownerships (
    equine_id, owner_type, owner_person_id, ownership_percentage
  ) values
    ('03100000-0000-4000-8000-000000000032', 'PERSON', '03100000-0000-4000-8000-000000000016', 100),
    ('03100000-0000-4000-8000-000000000033', 'PERSON', '03100000-0000-4000-8000-000000000016', 100);

  insert into public.equine_management_assignments (
    equine_id, manager_type, manager_person_id, management_role, granted_by_person_id
  ) values
    ('03100000-0000-4000-8000-000000000032', 'PERSON', '03100000-0000-4000-8000-000000000016', 'PRIMARY_MANAGER', '03100000-0000-4000-8000-000000000016'),
    ('03100000-0000-4000-8000-000000000033', 'PERSON', '03100000-0000-4000-8000-000000000016', 'PRIMARY_MANAGER', '03100000-0000-4000-8000-000000000016');

  insert into public.equine_center_assignments (
    equine_id, center_id, assignment_type
  ) values
    ('03100000-0000-4000-8000-000000000032', '03100000-0000-4000-8000-000000000031', 'SCHOOL'),
    ('03100000-0000-4000-8000-000000000033', '03100000-0000-4000-8000-000000000031', 'SCHOOL');

  perform pg_temp.pilot_jwt('03100000-0000-4000-8000-000000000004');
  insert into public.equine_center_permissions (
    equine_id, center_id, granted_by_person_id, permission_code
  )
  select equine.id,
         '03100000-0000-4000-8000-000000000031',
         '03100000-0000-4000-8000-000000000014',
         permission.code
    from (
      values
        ('03100000-0000-4000-8000-000000000032'::uuid),
        ('03100000-0000-4000-8000-000000000033'::uuid)
    ) as equine(id)
    cross join (
      values
        ('MANAGE_BOOKINGS'),
        ('MANAGE_AVAILABILITY'),
        ('MANAGE_REQUIREMENTS'),
        ('ASSESS_RIDERS'),
        ('APPROVE_RIDERS'),
        ('VIEW_ACTIVITY')
    ) as permission(code);
  perform pg_temp.pilot_jwt(null);

  insert into public.disciplines (id, code, status, sort_order)
  values (
    '03100000-0000-4000-8000-000000000035',
    'PILOT-RIDE',
    'ACTIVE',
    0
  );
  insert into public.discipline_translations (discipline_id, locale, name)
  values (
    '03100000-0000-4000-8000-000000000035',
    'en',
    'Pilot ride'
  );
  insert into public.equine_disciplines (equine_id, discipline_id)
  values
    ('03100000-0000-4000-8000-000000000032', '03100000-0000-4000-8000-000000000035'),
    ('03100000-0000-4000-8000-000000000033', '03100000-0000-4000-8000-000000000035');

  insert into public.qualification_systems (id, code, name, country_code, status)
  values (
    '03100000-0000-4000-8000-000000000036',
    'PILOT-QS',
    'Pilot qualification system',
    'QX',
    'ACTIVE'
  );
  insert into public.qualification_levels (
    id, qualification_system_id, code, level_order, name, discipline_id, status
  ) values (
    '03100000-0000-4000-8000-000000000037',
    '03100000-0000-4000-8000-000000000036',
    'PILOT-L1',
    1,
    'Pilot level 1',
    '03100000-0000-4000-8000-000000000035',
    'ACTIVE'
  );

  insert into public.center_services (id, center_id, service_type, name)
  values (
    '03100000-0000-4000-8000-000000000034',
    '03100000-0000-4000-8000-000000000031',
    'EQUINE_SESSION',
    'Pilot session'
  );
  insert into public.service_equines (service_id, equine_id, enabled, status)
  values
    ('03100000-0000-4000-8000-000000000034', '03100000-0000-4000-8000-000000000032', true, 'ACTIVE'),
    ('03100000-0000-4000-8000-000000000034', '03100000-0000-4000-8000-000000000033', true, 'ACTIVE');

  insert into public.equine_availability_rules (
    equine_id, center_id, starts_at, ends_at, created_by_account_id
  ) values
    (
      '03100000-0000-4000-8000-000000000032',
      '03100000-0000-4000-8000-000000000031',
      timestamptz '2026-11-02 08:00:00+00',
      timestamptz '2026-11-02 18:00:00+00',
      '03100000-0000-4000-8000-000000000024'
    ),
    (
      '03100000-0000-4000-8000-000000000033',
      '03100000-0000-4000-8000-000000000031',
      timestamptz '2026-11-02 08:00:00+00',
      timestamptz '2026-11-02 18:00:00+00',
      '03100000-0000-4000-8000-000000000024'
    );

  insert into public.equine_requirements (
    equine_id, requirement_type, boolean_value, numeric_value,
    qualification_level_id, discipline_id, source_type, source_id
  ) values
    (
      '03100000-0000-4000-8000-000000000032',
      'CENTER_ASSESSMENT_REQUIRED', true, null, null, null, 'CENTER',
      '03100000-0000-4000-8000-000000000031'
    ),
    (
      '03100000-0000-4000-8000-000000000032',
      'ZERO_SESSION_REQUIRED', true, null, null, null, 'CENTER',
      '03100000-0000-4000-8000-000000000031'
    ),
    (
      '03100000-0000-4000-8000-000000000032',
      'MIN_QUALIFICATION', null, null,
      '03100000-0000-4000-8000-000000000037',
      '03100000-0000-4000-8000-000000000035',
      'CENTER',
      '03100000-0000-4000-8000-000000000031'
    ),
    (
      '03100000-0000-4000-8000-000000000032',
      'MIN_EXPERIENCE', null, 1, null, null, 'CENTER',
      '03100000-0000-4000-8000-000000000031'
    ),
    (
      '03100000-0000-4000-8000-000000000032',
      'MIN_AGE', null, 16, null, null, 'CENTER',
      '03100000-0000-4000-8000-000000000031'
    ),
    (
      '03100000-0000-4000-8000-000000000033',
      'MIN_AGE', null, 8, null, null, 'CENTER',
      '03100000-0000-4000-8000-000000000031'
    );

  for policy_type, policy_code in
    select policy.policy_type, policy.policy_code
      from (
        values
          ('TERMS_OF_SERVICE', 'QX_TERMS'),
          ('PRIVACY_POLICY', 'QX_PRIVACY'),
          ('RIDER_POLICY', 'QX_RIDER'),
          ('ACTIVITY_POLICY', 'QX_ACTIVITY'),
          ('CENTER_POLICY', 'QX_CENTER'),
          ('ASSESSOR_POLICY', 'QX_ASSESSOR'),
          ('GUARDIAN_POLICY', 'QX_GUARDIAN'),
          ('OWNER_POLICY', 'QX_OWNER')
      ) as policy(policy_type, policy_code)
  loop
    insert into public.policy_documents (
      policy_code, policy_type, market_code, locale, version, title, content,
      effective_from, effective_to, status, requires_reacceptance
    ) values (
      policy_code, policy_type, 'QX', 'en', '2026-01',
      policy_code || ' obsolete', 'Obsolete pilot policy text',
      timestamptz '2026-01-01 00:00:00+00',
      timestamptz '2026-08-01 00:00:00+00',
      'INACTIVE', false
    );
    insert into public.policy_documents (
      policy_code, policy_type, market_code, locale, version, title, content,
      effective_from, status, requires_reacceptance
    ) values (
      policy_code, policy_type, 'QX', 'en', '2026-09',
      policy_code || ' current', 'Current pilot policy text',
      timestamptz '2026-08-01 00:00:00+00',
      'ACTIVE', false
    );
  end loop;

  for policy_type in
    select unnest(array[
      'TERMS_OF_SERVICE',
      'PRIVACY_POLICY',
      'RIDER_POLICY',
      'ACTIVITY_POLICY'
    ])
  loop
    select document.id
      into policy_id
      from public.policy_documents as document
     where document.policy_type = policy_type
       and document.market_code = 'QX'
       and document.version = '2026-09';

    perform pg_temp.pilot_jwt('03100000-0000-4000-8000-000000000001');
    insert into public.policy_acceptances (
      policy_document_id, person_id, user_account_id, accepted_at
    ) values (
      policy_id,
      '03100000-0000-4000-8000-000000000011',
      '03100000-0000-4000-8000-000000000021',
      accepted_at
    );

    perform pg_temp.pilot_jwt('03100000-0000-4000-8000-000000000002');
    insert into public.policy_acceptances (
      policy_document_id, person_id, user_account_id, accepted_at
    ) values
      (
        policy_id,
        '03100000-0000-4000-8000-000000000012',
        '03100000-0000-4000-8000-000000000022',
        accepted_at
      ),
      (
        policy_id,
        '03100000-0000-4000-8000-000000000018',
        '03100000-0000-4000-8000-000000000022',
        accepted_at
      ),
      (
        policy_id,
        '03100000-0000-4000-8000-000000000019',
        '03100000-0000-4000-8000-000000000022',
        accepted_at
      ),
      (
        policy_id,
        '03100000-0000-4000-8000-00000000001a',
        '03100000-0000-4000-8000-000000000022',
        accepted_at
      );
  end loop;

  perform pg_temp.pilot_jwt('03100000-0000-4000-8000-000000000002');
  insert into public.policy_acceptances (
    policy_document_id, person_id, user_account_id, accepted_at
  )
  select document.id,
         '03100000-0000-4000-8000-000000000012',
         '03100000-0000-4000-8000-000000000022',
         accepted_at
    from public.policy_documents as document
   where document.policy_type = 'GUARDIAN_POLICY'
     and document.market_code = 'QX'
     and document.version = '2026-09';

  perform pg_temp.pilot_jwt('03100000-0000-4000-8000-000000000005');
  insert into public.policy_acceptances (
    policy_document_id, person_id, user_account_id, accepted_at
  )
  select document.id,
         '03100000-0000-4000-8000-000000000015',
         '03100000-0000-4000-8000-000000000025',
         accepted_at
    from public.policy_documents as document
   where document.policy_type in ('CENTER_POLICY', 'ASSESSOR_POLICY')
     and document.market_code = 'QX'
     and document.version = '2026-09';
  perform pg_temp.pilot_jwt(null);

  insert into public.guardian_relationships (
    id, guardian_person_id, minor_person_id, relationship_type,
    verification_status, verified_at
  ) values
    (
      '03100000-0000-4000-8000-000000000051',
      '03100000-0000-4000-8000-000000000012',
      '03100000-0000-4000-8000-000000000018',
      'PARENT', 'VERIFIED', accepted_at
    ),
    (
      '03100000-0000-4000-8000-000000000052',
      '03100000-0000-4000-8000-000000000012',
      '03100000-0000-4000-8000-000000000019',
      'PARENT', 'VERIFIED', accepted_at
    ),
    (
      '03100000-0000-4000-8000-000000000053',
      '03100000-0000-4000-8000-000000000012',
      '03100000-0000-4000-8000-00000000001a',
      'PARENT', 'VERIFIED', accepted_at
    );
end;
$$;

-- Adult rider profile is a caller RPC. Horse is not eligible yet.
select pg_temp.pilot_jwt('03100000-0000-4000-8000-000000000001');
set local role authenticated;

do $$
declare
  overall text;
  profile_year smallint;
begin
  overall := pg_temp.pilot_overall(
    '03100000-0000-4000-8000-000000000011',
    '03100000-0000-4000-8000-000000000032',
    '03100000-0000-4000-8000-000000000031',
    timestamptz '2026-11-02 10:00:00+00',
    timestamptz '2026-11-02 11:00:00+00',
    '03100000-0000-4000-8000-000000000034'
  );
  if overall is distinct from 'QUALIFICATION_NOT_VERIFIED' then
    raise exception 'Adult horse should start QUALIFICATION_NOT_VERIFIED, got %', overall;
  end if;

  select saved.experience_start_year
    into profile_year
    from public.upsert_my_rider_profile(null, 2010, 'PRIVATE') as saved;
  if profile_year is distinct from 2010 then
    raise exception 'Rider profile experience year was not stored';
  end if;

  perform public.get_my_rider_profile();
end;
$$;

reset role;
select pg_temp.pilot_jwt(null);

do $$
begin
  insert into public.rider_qualifications (
    rider_person_id, qualification_level_id, verification_status,
    verified_by_person_id, issued_at
  ) values (
    '03100000-0000-4000-8000-000000000011',
    '03100000-0000-4000-8000-000000000037',
    'VERIFIED',
    '03100000-0000-4000-8000-000000000015',
    timestamptz '2026-09-01 00:00:00+00'
  );

  perform pg_temp.pilot_jwt('03100000-0000-4000-8000-000000000005');
  insert into public.rider_assessments (
    rider_person_id, center_id, assessor_person_id, assessment_type,
    performed_at, status
  ) values (
    '03100000-0000-4000-8000-000000000011',
    '03100000-0000-4000-8000-000000000031',
    '03100000-0000-4000-8000-000000000015',
    'ACCESS_TEST',
    timestamptz '2026-09-15 10:00:00+00',
    'VALID'
  );

  insert into public.zero_sessions (
    id, rider_person_id, equine_id, center_id, requested_by_account_id,
    scheduled_at, result
  ) values (
    '03100000-0000-4000-8000-000000000038',
    '03100000-0000-4000-8000-000000000011',
    '03100000-0000-4000-8000-000000000032',
    '03100000-0000-4000-8000-000000000031',
    '03100000-0000-4000-8000-000000000021',
    timestamptz '2026-09-20 10:00:00+00',
    'PENDING'
  );
  perform pg_temp.pilot_jwt(null);
end;
$$;

select pg_temp.pilot_jwt('03100000-0000-4000-8000-000000000001');
set local role authenticated;

do $$
declare
  overall text;
begin
  overall := pg_temp.pilot_overall(
    '03100000-0000-4000-8000-000000000011',
    '03100000-0000-4000-8000-000000000032',
    '03100000-0000-4000-8000-000000000031',
    timestamptz '2026-11-02 10:00:00+00',
    timestamptz '2026-11-02 11:00:00+00',
    '03100000-0000-4000-8000-000000000034'
  );
  if overall is distinct from 'REQUIRES_ZERO_SESSION' then
    raise exception 'Approved Zero Session is still required, got %', overall;
  end if;
end;
$$;

reset role;

select pg_temp.pilot_jwt('03100000-0000-4000-8000-000000000005');
set local role authenticated;

do $$
declare
  approved text;
begin
  select approval.result
    into approved
    from public.approve_zero_session(
      '03100000-0000-4000-8000-000000000038',
      'APPROVED',
      'Pilot approval'
    ) as approval;
  if approved is distinct from 'APPROVED' then
    raise exception 'Zero Session approval returned %', approved;
  end if;
end;
$$;

reset role;
select pg_temp.pilot_jwt(null);

do $$
begin
  insert into public.rider_equine_authorizations (
    rider_person_id, equine_id, authorization_type, issued_by_person_id,
    center_id, source_zero_session_id, status
  ) values (
    '03100000-0000-4000-8000-000000000011',
    '03100000-0000-4000-8000-000000000032',
    'ZERO_SESSION',
    '03100000-0000-4000-8000-000000000015',
    '03100000-0000-4000-8000-000000000031',
    '03100000-0000-4000-8000-000000000038',
    'ACTIVE'
  );
end;
$$;

select pg_temp.pilot_jwt('03100000-0000-4000-8000-000000000001');
set local role authenticated;

do $$
declare
  overall text;
  first_id uuid;
  second_id uuid;
begin
  overall := pg_temp.pilot_overall(
    '03100000-0000-4000-8000-000000000011',
    '03100000-0000-4000-8000-000000000032',
    '03100000-0000-4000-8000-000000000031',
    timestamptz '2026-11-02 10:00:00+00',
    timestamptz '2026-11-02 11:00:00+00',
    '03100000-0000-4000-8000-000000000034'
  );
  if overall is distinct from 'ELIGIBLE' then
    raise exception 'Adult horse should be ELIGIBLE, got %', overall;
  end if;

  first_id := public.create_booking_request(
    '03100000-0000-4000-8000-000000000011',
    '03100000-0000-4000-8000-000000000032',
    '03100000-0000-4000-8000-000000000031',
    '03100000-0000-4000-8000-000000000034',
    timestamptz '2026-11-02 10:00:00+00',
    timestamptz '2026-11-02 11:00:00+00'
  );
  second_id := public.create_booking_request(
    '03100000-0000-4000-8000-000000000011',
    '03100000-0000-4000-8000-000000000032',
    '03100000-0000-4000-8000-000000000031',
    '03100000-0000-4000-8000-000000000034',
    timestamptz '2026-11-02 10:30:00+00',
    timestamptz '2026-11-02 11:30:00+00'
  );
  perform set_config('pilot.first_booking', first_id::text, true);
  perform set_config('pilot.second_booking', second_id::text, true);

  begin
    perform public.confirm_booking(first_id);
    raise exception 'Adult rider self-confirmed';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

reset role;

select pg_temp.pilot_jwt('03100000-0000-4000-8000-000000000007');
set local role authenticated;

do $$
begin
  begin
    perform pg_temp.pilot_overall(
      '03100000-0000-4000-8000-000000000011',
      '03100000-0000-4000-8000-000000000032',
      '03100000-0000-4000-8000-000000000031',
      timestamptz '2026-11-02 10:00:00+00',
      timestamptz '2026-11-02 11:00:00+00',
      '03100000-0000-4000-8000-000000000034'
    );
    raise exception 'Intruder inspected foreign eligibility';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform public.confirm_booking(current_setting('pilot.first_booking')::uuid);
    raise exception 'Intruder confirmed a foreign booking';
  exception
    when insufficient_privilege then null;
  end;

end;
$$;

reset role;

select pg_temp.pilot_jwt('03100000-0000-4000-8000-000000000003');
set local role authenticated;

do $$
begin
  begin
    perform public.confirm_booking(current_setting('pilot.first_booking')::uuid);
    raise exception 'Instructor confirmed without MANAGE_BOOKINGS authority';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

reset role;

select pg_temp.pilot_jwt('03100000-0000-4000-8000-000000000004');
set local role authenticated;

do $$
declare
  confirmed_id uuid;
begin
  confirmed_id := public.confirm_booking(current_setting('pilot.first_booking')::uuid);
  if confirmed_id is distinct from current_setting('pilot.first_booking')::uuid then
    raise exception 'confirm_booking returned an unexpected id';
  end if;

  begin
    perform public.confirm_booking(current_setting('pilot.second_booking')::uuid);
    raise exception 'Overlapping confirm succeeded';
  exception
    when exclusion_violation then null;
    when check_violation then null;
    when insufficient_privilege then null;
  end;
end;
$$;

reset role;

select pg_temp.pilot_jwt('03100000-0000-4000-8000-000000000007');
set local role authenticated;

do $$
begin
  begin
    perform public.start_session(
      current_setting('pilot.first_booking')::uuid,
      false, null, null, null, null, null
    );
    raise exception 'Intruder started a confirmed foreign session';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

reset role;

select pg_temp.pilot_jwt('03100000-0000-4000-8000-000000000002');
set local role authenticated;

do $$
declare
  overall text;
  missing_id uuid;
  revoked_consent uuid;
  minor_booking uuid;
begin
  overall := pg_temp.pilot_overall(
    '03100000-0000-4000-8000-000000000019',
    '03100000-0000-4000-8000-000000000033',
    '03100000-0000-4000-8000-000000000031',
    timestamptz '2026-11-02 14:00:00+00',
    timestamptz '2026-11-02 15:00:00+00',
    '03100000-0000-4000-8000-000000000034'
  );
  if overall is distinct from 'REQUIRES_GUARDIAN_CONSENT' then
    raise exception 'Missing consent should require guardian consent, got %', overall;
  end if;

  missing_id := public.create_booking_request(
    '03100000-0000-4000-8000-000000000019',
    '03100000-0000-4000-8000-000000000033',
    '03100000-0000-4000-8000-000000000031',
    '03100000-0000-4000-8000-000000000034',
    timestamptz '2026-11-02 14:00:00+00',
    timestamptz '2026-11-02 15:00:00+00'
  );
  perform set_config('pilot.missing_booking', missing_id::text, true);

  select created.id
    into revoked_consent
    from public.grant_guardian_consent(
      '03100000-0000-4000-8000-000000000053',
      'EQUESTRIAN_ACTIVITY',
      'GENERAL',
      'pilot-qx',
      'QX',
      null
    ) as created;
  perform public.revoke_guardian_consent(revoked_consent);

  overall := pg_temp.pilot_overall(
    '03100000-0000-4000-8000-00000000001a',
    '03100000-0000-4000-8000-000000000033',
    '03100000-0000-4000-8000-000000000031',
    timestamptz '2026-11-02 15:00:00+00',
    timestamptz '2026-11-02 16:00:00+00',
    '03100000-0000-4000-8000-000000000034'
  );
  if overall is distinct from 'REQUIRES_GUARDIAN_CONSENT' then
    raise exception 'Revoked consent should require guardian consent, got %', overall;
  end if;

  select created.id
    into revoked_consent
    from public.grant_guardian_consent(
      '03100000-0000-4000-8000-000000000051',
      'EQUESTRIAN_ACTIVITY',
      'GENERAL',
      'pilot-qx',
      'QX',
      null
    ) as created;
  if revoked_consent is null then
    raise exception 'Valid guardian consent was not granted';
  end if;

  overall := pg_temp.pilot_overall(
    '03100000-0000-4000-8000-000000000018',
    '03100000-0000-4000-8000-000000000033',
    '03100000-0000-4000-8000-000000000031',
    timestamptz '2026-11-02 16:00:00+00',
    timestamptz '2026-11-02 17:00:00+00',
    '03100000-0000-4000-8000-000000000034'
  );
  if overall is distinct from 'ELIGIBLE' then
    raise exception 'Consented minor should be ELIGIBLE on the pony, got %', overall;
  end if;

  minor_booking := public.create_booking_request(
    '03100000-0000-4000-8000-000000000018',
    '03100000-0000-4000-8000-000000000033',
    '03100000-0000-4000-8000-000000000031',
    '03100000-0000-4000-8000-000000000034',
    timestamptz '2026-11-02 16:00:00+00',
    timestamptz '2026-11-02 17:00:00+00'
  );
  perform set_config('pilot.minor_booking', minor_booking::text, true);
end;
$$;

reset role;

select pg_temp.pilot_jwt('03100000-0000-4000-8000-000000000004');
set local role authenticated;

do $$
begin
  begin
    perform public.confirm_booking(current_setting('pilot.missing_booking')::uuid);
    raise exception 'Missing-consent booking was confirmed';
  exception
    when check_violation then null;
  end;

  perform public.confirm_booking(current_setting('pilot.minor_booking')::uuid);
end;
$$;

reset role;

select pg_temp.pilot_jwt('03100000-0000-4000-8000-000000000001');
set local role authenticated;

do $$
declare
  permit_id uuid;
  session_id uuid;
  activity_id uuid;
  incident_id uuid;
  review_id uuid;
begin
  permit_id := public.issue_session_permit(current_setting('pilot.first_booking')::uuid);
  if permit_id is null then
    raise exception 'Session permit was not issued';
  end if;

  session_id := public.start_session(
    current_setting('pilot.first_booking')::uuid,
    false, null, null, null, 'pilot-device', null
  );
  activity_id := public.record_equine_activity(session_id, null, null, null);
  incident_id := public.report_incident(
    current_setting('pilot.first_booking')::uuid,
    session_id,
    'Pilot fixture incident note',
    null,
    null
  );
  perform public.end_session(session_id, false, null, null, 'pilot-device', null);
  perform public.record_equine_activity(session_id, null, null, null);
  review_id := public.submit_review(
    current_setting('pilot.first_booking')::uuid,
    '03100000-0000-4000-8000-000000000032',
    5,
    'Pilot fixture review',
    null
  );

  perform set_config('pilot.session_id', session_id::text, true);
  perform set_config('pilot.activity_id', activity_id::text, true);
  perform set_config('pilot.incident_id', incident_id::text, true);
  perform set_config('pilot.review_id', review_id::text, true);
end;
$$;

reset role;

select pg_temp.pilot_jwt('03100000-0000-4000-8000-000000000006');
set local role authenticated;

do $$
declare
  ownership_count integer;
  management_count integer;
begin
  select count(*)
    into ownership_count
    from public.list_my_equine_ownerships();
  if ownership_count <> 2 then
    raise exception 'Owner should see two ownerships, got %', ownership_count;
  end if;

  select count(*)
    into management_count
    from public.list_my_equine_management_assignments();
  if management_count <> 2 then
    raise exception 'Primary manager should see two assignments, got %', management_count;
  end if;
end;
$$;

reset role;

select pg_temp.pilot_jwt('03100000-0000-4000-8000-000000000004');
set local role authenticated;

do $$
declare
  membership_count integer;
begin
  select count(*)
    into membership_count
    from public.list_my_center_memberships() as membership
   where membership.role_code = 'MANAGER'
     and membership.center_id = '03100000-0000-4000-8000-000000000031';
  if membership_count <> 1 then
    raise exception 'Manager membership was not visible to the caller';
  end if;
end;
$$;

reset role;
select pg_temp.pilot_jwt(null);

do $$
declare
  booking_status text;
  block_count integer;
  session_status text;
  activity_end timestamptz;
  audit_missing text;
begin
  select booking.status
    into booking_status
    from public.bookings as booking
   where booking.id = current_setting('pilot.first_booking')::uuid;
  if booking_status is distinct from 'COMPLETED' then
    raise exception 'Adult booking should be COMPLETED, got %', booking_status;
  end if;

  select booking.status
    into booking_status
    from public.bookings as booking
   where booking.id = current_setting('pilot.missing_booking')::uuid;
  if booking_status is distinct from 'PENDING_REQUIREMENTS' then
    raise exception 'Missing-consent booking should stay PENDING_REQUIREMENTS, got %', booking_status;
  end if;

  select booking.status
    into booking_status
    from public.bookings as booking
   where booking.id = current_setting('pilot.minor_booking')::uuid;
  if booking_status is distinct from 'CONFIRMED' then
    raise exception 'Minor booking should be CONFIRMED, got %', booking_status;
  end if;

  if (
    select booking.participant_person_id
      from public.bookings as booking
     where booking.id = current_setting('pilot.minor_booking')::uuid
  ) is distinct from '03100000-0000-4000-8000-000000000018'::uuid
     or (
    select booking.booked_by_account_id
      from public.bookings as booking
     where booking.id = current_setting('pilot.minor_booking')::uuid
  ) is distinct from '03100000-0000-4000-8000-000000000022'::uuid then
    raise exception 'Minor booking did not separate participant and booker';
  end if;

  select count(*)
    into block_count
    from public.equine_calendar_blocks as block
   where block.source_id = current_setting('pilot.first_booking')::uuid
     and block.block_type = 'BOOKING'
     and block.status = 'ACTIVE';
  if block_count <> 1 then
    raise exception 'Confirmed adult booking should occupy one calendar block, got %', block_count;
  end if;

  select session.status
    into session_status
    from public.sessions as session
   where session.id = current_setting('pilot.session_id')::uuid;
  if session_status is distinct from 'COMPLETED' then
    raise exception 'Session should be COMPLETED, got %', session_status;
  end if;

  select activity.ends_at
    into activity_end
    from public.equine_activities as activity
   where activity.id = current_setting('pilot.activity_id')::uuid;
  if activity_end is null then
    raise exception 'Equine activity was not closed from the completed session';
  end if;

  if not exists (
    select 1 from public.reviews as review
     where review.id = current_setting('pilot.review_id')::uuid
       and review.rating = 5
  ) then
    raise exception 'Review evidence is missing';
  end if;

  if not exists (
    select 1 from public.incidents as incident
     where incident.id = current_setting('pilot.incident_id')::uuid
  ) then
    raise exception 'Incident evidence is missing';
  end if;

  select string_agg(expected.event_type, ', ' order by expected.event_type)
    into audit_missing
    from (
      values
        ('policy_accepted'),
        ('equine_permission_granted'),
        ('rider_assessment_validated'),
        ('zero_session_approved'),
        ('guardian_consent_granted'),
        ('guardian_consent_revoked'),
        ('booking_confirmed'),
        ('session_started'),
        ('session_completed'),
        ('equine_activity_recorded'),
        ('incident_reported'),
        ('review_submitted')
    ) as expected(event_type)
   where not exists (
     select 1
       from public.audit_events as audit_event
      where audit_event.event_type = expected.event_type
   );

  if audit_missing is not null then
    raise exception 'Pilot audit evidence missing: %', audit_missing;
  end if;

  if exists (
    select 1
      from pg_catalog.pg_policy as policy
     where policy.polrelid = 'storage.objects'::regclass
       and (
         policy.polname ilike '%equine-media%'
         or pg_catalog.pg_get_expr(policy.polqual, policy.polrelid) ilike '%equine-media%'
         or pg_catalog.pg_get_expr(policy.polwithcheck, policy.polrelid) ilike '%equine-media%'
       )
  ) then
    raise exception 'equine-media must stay deny-by-default';
  end if;

  if has_function_privilege('anon', 'public.confirm_booking(uuid)', 'EXECUTE') then
    raise exception 'anon must not execute confirm_booking';
  end if;
end;
$$;

rollback;
