-- Two-connection confirm handshake setup. Commits so sessions can see it.

select pg_advisory_unlock_all();

-- Test-only teardown. Confirmed requirement/calendar rows cannot be
-- deleted under product triggers.
set session_replication_role = replica;

delete from public.booking_requirements
 where booking_id = '99100000-0000-0000-0000-00000000b001';
delete from public.equine_calendar_blocks
 where source_id = '99100000-0000-0000-0000-00000000b001';
delete from public.bookings
 where id = '99100000-0000-0000-0000-00000000b001';

delete from public.service_equines
 where equine_id in (
   select id from public.equines where name = 'phase11b-conc-school'
 );
delete from public.equine_requirements
 where equine_id in (
   select id from public.equines where name = 'phase11b-conc-school'
 );
delete from public.equine_availability_rules
 where equine_id in (
   select id from public.equines where name = 'phase11b-conc-school'
 );
delete from public.equine_center_permissions
 where equine_id in (
   select id from public.equines where name = 'phase11b-conc-school'
 );
delete from public.equine_center_assignments
 where equine_id in (
   select id from public.equines where name = 'phase11b-conc-school'
 );
delete from public.equine_ownerships
 where equine_id in (
   select id from public.equines where name = 'phase11b-conc-school'
 );
delete from public.equines where name = 'phase11b-conc-school';
delete from public.center_services
 where center_id in (
   select id from public.equestrian_centers where slug = 'phase11b-conc'
 );
delete from public.center_memberships
 where center_id in (
   select id from public.equestrian_centers where slug = 'phase11b-conc'
 );
delete from public.center_languages
 where center_id in (
   select id from public.equestrian_centers where slug = 'phase11b-conc'
 );
delete from public.equestrian_centers where slug = 'phase11b-conc';

delete from public.policy_acceptances
 where user_account_id in (
   select id from public.user_accounts
    where auth_user_id in (
      '99100000-0000-0000-0000-000000000001'::uuid,
      '99100000-0000-0000-0000-000000000005'::uuid
    )
 );
delete from public.policy_documents
 where policy_code = 'TERMS_ZQ' and market_code = 'ZQ';
delete from public.user_accounts
 where auth_user_id in (
   '99100000-0000-0000-0000-000000000001'::uuid,
   '99100000-0000-0000-0000-000000000005'::uuid,
   '99100000-0000-0000-0000-000000000007'::uuid
 );
delete from public.persons
 where first_name = 'Conc'
   and last_name in ('Rider', 'Staff', 'Owner');
delete from public.market_age_rules where country_code = 'ZQ';
delete from public.markets where country_code = 'ZQ';
delete from auth.users
 where id in (
   '99100000-0000-0000-0000-000000000001'::uuid,
   '99100000-0000-0000-0000-000000000005'::uuid,
   '99100000-0000-0000-0000-000000000007'::uuid
 );

set session_replication_role = origin;

insert into public.markets (country_code, status) values ('ZQ', 'ACTIVE');
insert into public.market_age_rules (
  country_code, legal_adult_age, guardian_consent_required, effective_from
) values ('ZQ', 18, true, date '2000-01-01');

insert into auth.users (id) values
  ('99100000-0000-0000-0000-000000000001'),
  ('99100000-0000-0000-0000-000000000005'),
  ('99100000-0000-0000-0000-000000000007');

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
   where auth_user_id = '99100000-0000-0000-0000-000000000001';
  select person_id, id into staff_person_id, staff_account_id
    from public.user_accounts
   where auth_user_id = '99100000-0000-0000-0000-000000000005';
  select person_id into owner_person_id
    from public.user_accounts
   where auth_user_id = '99100000-0000-0000-0000-000000000007';

  update public.persons
     set first_name = 'Conc', last_name = 'Rider', date_of_birth = date '1990-01-01'
   where id = rider_person_id;
  update public.persons
     set first_name = 'Conc', last_name = 'Staff', date_of_birth = date '1985-01-01'
   where id = staff_person_id;
  update public.persons
     set first_name = 'Conc', last_name = 'Owner', date_of_birth = date '1975-01-01'
   where id = owner_person_id;

  insert into public.equestrian_centers (name, slug, country_code, status)
  values ('Phase11B Conc', 'phase11b-conc', 'ZQ', 'ACTIVE')
  returning id into center_id;

  insert into public.equines (name, equine_type)
  values ('phase11b-conc-school', 'HORSE')
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
    'TERMS_ZQ', 'TERMS_OF_SERVICE', 'ZQ', 'es', '1',
    'Terms', 'Conc terms', now() - interval '1 day', 'ACTIVE', false
  ) returning id into terms_id;

  insert into public.policy_acceptances (
    policy_document_id, person_id, user_account_id, accepted_at
  ) values (terms_id, rider_person_id, rider_account_id, now());

  insert into public.bookings (
    id, participant_person_id, booked_by_account_id, equine_id, center_id,
    service_id, starts_at, ends_at, status, eligibility_status
  ) values (
    '99100000-0000-0000-0000-00000000b001',
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

drop function if exists public.confirm_booking_concurrency_probe(uuid);

-- Test-only. Not part of 022. Revoked from PUBLIC/anon/authenticated so
-- an authenticated caller cannot pause confirm_booking.
create function public.confirm_booking_concurrency_probe(p_booking_id uuid)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
#variable_conflict use_variable
declare
  current_auth_user_id uuid := auth.uid();
  caller_account uuid;
  caller_person uuid;
  booking_row public.bookings%rowtype;
  eval_rows jsonb;
  policy_snapshot jsonb;
begin
  if current_auth_user_id is null then
    raise exception using
      errcode = '42501',
      message = 'Authentication required';
  end if;

  select account.id, account.person_id
    into caller_account, caller_person
    from public.user_accounts as account
   where account.auth_user_id = current_auth_user_id;

  if caller_person is null then
    raise exception using
      errcode = 'P0001',
      message = 'Identity could not be resolved';
  end if;

  select *
    into booking_row
    from public.bookings as booking
   where booking.id = p_booking_id
   for update;

  if booking_row.id is null then
    raise exception using
      errcode = 'P0002',
      message = 'Booking not found';
  end if;

  if booking_row.status is distinct from 'APPROVED' then
    raise exception using
      errcode = '23514',
      message = 'Only an APPROVED booking can be confirmed';
  end if;

  if caller_person is not distinct from booking_row.participant_person_id
     or caller_account is not distinct from booking_row.booked_by_account_id then
    raise exception using
      errcode = '42501',
      message = 'The rider or booker cannot self-confirm';
  end if;

  if not public.caller_has_booking_manage_authority(
    caller_person,
    booking_row.equine_id,
    booking_row.center_id
  ) then
    raise exception using
      errcode = '42501',
      message = 'Confirming a booking requires a Center ADMIN or MANAGER with effective MANAGE_BOOKINGS for this equine at this Center';
  end if;

  perform set_config('app.confirming_booking', '1', true);
  perform pg_advisory_lock(22022021);
  raise notice 'confirm_eval_lock_held';

  select
    evaluation.eval_rows,
    evaluation.policy_snapshot
    into eval_rows, policy_snapshot
    from public.materialize_booking_confirm_eval(
      booking_row.participant_person_id,
      booking_row.equine_id,
      booking_row.center_id,
      booking_row.starts_at,
      booking_row.ends_at,
      booking_row.service_id
    ) as evaluation;

  raise notice 'confirm_eval_ready';
  while not exists (
    select 1
      from pg_locks as advisory_lock
     where advisory_lock.locktype = 'advisory'
       and advisory_lock.classid = 0
       and advisory_lock.objid = 22022022
       and advisory_lock.granted
  ) loop
    perform pg_sleep(0.05);
  end loop;
  perform pg_advisory_unlock(22022021);
  perform pg_advisory_lock(22022022);
  perform pg_advisory_unlock(22022022);

  return public.apply_booking_confirm_eval(
    booking_row.id,
    eval_rows,
    policy_snapshot,
    caller_account
  );
end;
$$;

revoke all on function public.confirm_booking_concurrency_probe(uuid)
  from public, anon, authenticated;

do $$
begin
  if has_function_privilege(
       'authenticated',
       'public.confirm_booking_concurrency_probe(uuid)',
       'execute'
     )
     or has_function_privilege(
       'anon',
       'public.confirm_booking_concurrency_probe(uuid)',
       'execute'
     )
  then
    raise exception 'Authenticated/anon must not execute the concurrency probe';
  end if;
end;
$$;

select 'concurrency_setup_ready' as marker;
