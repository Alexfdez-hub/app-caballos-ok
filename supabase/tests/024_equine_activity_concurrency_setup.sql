-- Two-connection record_equine_activity setup. Commits so both
-- connections can see the started session.

select pg_advisory_unlock_all();

set session_replication_role = replica;

delete from public.equine_activities
 where session_id in (
   select id from public.sessions
    where booking_id = '88300000-0000-0000-0000-00000000b001'
 );
delete from public.session_evidence
 where session_id in (
   select id from public.sessions
    where booking_id = '88300000-0000-0000-0000-00000000b001'
 );
delete from public.session_events
 where session_id in (
   select id from public.sessions
    where booking_id = '88300000-0000-0000-0000-00000000b001'
 );
delete from public.session_permits
 where booking_id = '88300000-0000-0000-0000-00000000b001';
delete from public.sessions
 where booking_id = '88300000-0000-0000-0000-00000000b001';
delete from public.booking_requirements
 where booking_id = '88300000-0000-0000-0000-00000000b001';
delete from public.equine_calendar_blocks
 where source_id = '88300000-0000-0000-0000-00000000b001';
delete from public.bookings
 where id = '88300000-0000-0000-0000-00000000b001';

delete from public.service_equines
 where equine_id in (
   select id from public.equines where name = 'phase12b-conc-school'
 );
delete from public.equine_availability_rules
 where equine_id in (
   select id from public.equines where name = 'phase12b-conc-school'
 );
delete from public.equine_center_permissions
 where equine_id in (
   select id from public.equines where name = 'phase12b-conc-school'
 );
delete from public.equine_center_assignments
 where equine_id in (
   select id from public.equines where name = 'phase12b-conc-school'
 );
delete from public.equine_ownerships
 where equine_id in (
   select id from public.equines where name = 'phase12b-conc-school'
 );
delete from public.equines where name = 'phase12b-conc-school';
delete from public.center_services
 where center_id in (
   select id from public.equestrian_centers where slug = 'phase12b-conc'
 );
delete from public.center_memberships
 where center_id in (
   select id from public.equestrian_centers where slug = 'phase12b-conc'
 );
delete from public.center_languages
 where center_id in (
   select id from public.equestrian_centers where slug = 'phase12b-conc'
 );
delete from public.equestrian_centers where slug = 'phase12b-conc';

delete from public.policy_acceptances
 where user_account_id in (
   select id from public.user_accounts
    where auth_user_id in (
      '88300000-0000-0000-0000-000000000001'::uuid,
      '88300000-0000-0000-0000-000000000005'::uuid
    )
 );
delete from public.policy_documents
 where policy_code = 'TERMS_ZU' and market_code = 'ZU';
delete from public.user_accounts
 where auth_user_id in (
   '88300000-0000-0000-0000-000000000001'::uuid,
   '88300000-0000-0000-0000-000000000005'::uuid,
   '88300000-0000-0000-0000-000000000007'::uuid
 );
delete from public.persons
 where first_name = 'Conc12B'
   and last_name in ('Rider', 'Staff', 'Owner');
delete from public.market_age_rules where country_code = 'ZU';
delete from public.markets where country_code = 'ZU';
delete from auth.users
 where id in (
   '88300000-0000-0000-0000-000000000001'::uuid,
   '88300000-0000-0000-0000-000000000005'::uuid,
   '88300000-0000-0000-0000-000000000007'::uuid
 );

set session_replication_role = origin;

insert into public.markets (country_code, status) values ('ZU', 'ACTIVE');
insert into public.market_age_rules (
  country_code, legal_adult_age, guardian_consent_required, effective_from
) values ('ZU', 18, true, date '2000-01-01');

insert into auth.users (id) values
  ('88300000-0000-0000-0000-000000000001'),
  ('88300000-0000-0000-0000-000000000005'),
  ('88300000-0000-0000-0000-000000000007');

do $$
declare
  rider_person_id uuid;
  rider_account_id uuid;
  staff_person_id uuid;
  staff_account_id uuid;
  owner_person_id uuid;
  center_id uuid;
  equine_id uuid;
  service_id uuid;
  terms_id uuid;
begin
  select person_id, id into rider_person_id, rider_account_id
    from public.user_accounts
   where auth_user_id = '88300000-0000-0000-0000-000000000001';
  select person_id, id into staff_person_id, staff_account_id
    from public.user_accounts
   where auth_user_id = '88300000-0000-0000-0000-000000000005';
  select person_id into owner_person_id
    from public.user_accounts
   where auth_user_id = '88300000-0000-0000-0000-000000000007';

  update public.persons
     set first_name = 'Conc12B', last_name = 'Rider', date_of_birth = date '1990-01-01'
   where id = rider_person_id;
  update public.persons
     set first_name = 'Conc12B', last_name = 'Staff', date_of_birth = date '1985-01-01'
   where id = staff_person_id;
  update public.persons
     set first_name = 'Conc12B', last_name = 'Owner', date_of_birth = date '1975-01-01'
   where id = owner_person_id;

  insert into public.equestrian_centers (name, slug, country_code, status)
  values ('Phase12B Conc', 'phase12b-conc', 'ZU', 'ACTIVE')
  returning id into center_id;

  insert into public.equines (name, equine_type)
  values ('phase12b-conc-school', 'HORSE')
  returning id into equine_id;

  insert into public.center_memberships (center_id, person_id, role_code)
  values (center_id, staff_person_id, 'MANAGER');

  insert into public.equine_center_assignments (
    equine_id, center_id, assignment_type
  ) values (equine_id, center_id, 'SCHOOL');

  insert into public.equine_ownerships (
    equine_id, owner_type, owner_person_id, ownership_percentage
  ) values (equine_id, 'PERSON', owner_person_id, 100);

  insert into public.equine_center_permissions (
    equine_id, center_id, granted_by_person_id, permission_code
  ) values
    (equine_id, center_id, staff_person_id, 'MANAGE_BOOKINGS'),
    (equine_id, center_id, staff_person_id, 'MANAGE_AVAILABILITY'),
    (equine_id, center_id, staff_person_id, 'MANAGE_REQUIREMENTS');

  insert into public.center_services (center_id, service_type, name)
  values (center_id, 'EQUINE_SESSION', 'Conc ride')
  returning id into service_id;

  insert into public.service_equines (service_id, equine_id, enabled, status)
  values (service_id, equine_id, true, 'ACTIVE');

  insert into public.equine_availability_rules (
    equine_id, center_id, starts_at, ends_at, created_by_account_id
  ) values (
    equine_id, center_id,
    timestamptz '2026-12-01 00:00:00+00',
    timestamptz '2026-12-11 00:00:00+00',
    staff_account_id
  );

  insert into public.policy_documents (
    policy_code, policy_type, market_code, locale, version, title, content,
    effective_from, status, requires_reacceptance
  ) values (
    'TERMS_ZU', 'TERMS_OF_SERVICE', 'ZU', 'es', '1',
    'Terms', 'Conc terms', now() - interval '1 day', 'ACTIVE', false
  ) returning id into terms_id;

  insert into public.policy_acceptances (
    policy_document_id, person_id, user_account_id, accepted_at
  ) values (terms_id, rider_person_id, rider_account_id, now());

  insert into public.bookings (
    id, participant_person_id, booked_by_account_id, equine_id, center_id,
    service_id, starts_at, ends_at, status, eligibility_status
  ) values (
    '88300000-0000-0000-0000-00000000b001',
    rider_person_id,
    rider_account_id,
    equine_id,
    center_id,
    service_id,
    timestamptz '2026-12-01 10:00:00+00',
    timestamptz '2026-12-01 11:00:00+00',
    'APPROVED',
    'ELIGIBLE'
  );
end;
$$;

begin;
select set_config('request.jwt.claim.sub', '88300000-0000-0000-0000-000000000005', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"88300000-0000-0000-0000-000000000005","role":"authenticated"}',
  true
);
select public.confirm_booking('88300000-0000-0000-0000-00000000b001') as confirmed_id;
commit;

begin;
select set_config('request.jwt.claim.sub', '88300000-0000-0000-0000-000000000001', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"88300000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);
select public.start_session('88300000-0000-0000-0000-00000000b001') as started_id;
commit;
