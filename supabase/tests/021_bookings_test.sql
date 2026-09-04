-- Phase 11A local booking foundation tests.
-- Assumes migrations 001-current. Sessions are tested separately.
-- Booker is own PERSON or a current VERIFIED guardian. No confirm path.
-- Runnable without psql meta-commands.

begin;

do $$
declare
  fixture_auth uuid[] := array[
    '98000000-0000-0000-0000-000000000001'::uuid,
    '98000000-0000-0000-0000-000000000002'::uuid,
    '98000000-0000-0000-0000-000000000003'::uuid,
    '98000000-0000-0000-0000-000000000004'::uuid
  ];
  linked_person_ids uuid[];
  fixture_center_ids uuid[];
  fixture_equine_ids uuid[];
  fixture_service_ids uuid[];
begin
  select coalesce(array_agg(id), '{}') into fixture_center_ids
    from public.equestrian_centers where slug like 'phase11a-%';
  select coalesce(array_agg(id), '{}') into fixture_equine_ids
    from public.equines where name like 'phase11a-%';
  select coalesce(array_agg(id), '{}') into fixture_service_ids
    from public.center_services where center_id = any(fixture_center_ids);

  delete from public.booking_requirements
   where booking_id in (
     select id from public.bookings
      where equine_id = any(fixture_equine_ids)
         or center_id = any(fixture_center_ids)
   );
  delete from public.bookings
   where equine_id = any(fixture_equine_ids)
      or center_id = any(fixture_center_ids);
  delete from public.service_equines
   where service_id = any(fixture_service_ids)
      or equine_id = any(fixture_equine_ids);
  delete from public.center_services
   where id = any(fixture_service_ids);
  delete from public.equine_calendar_blocks
   where equine_id = any(fixture_equine_ids);
  delete from public.equine_availability_rules
   where equine_id = any(fixture_equine_ids);
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
   );
  select coalesce(array_agg(person_id), '{}') into linked_person_ids
    from public.user_accounts where auth_user_id = any(fixture_auth);
  delete from public.user_accounts where auth_user_id = any(fixture_auth);
  delete from public.persons where id = any(linked_person_ids);
  delete from public.market_age_rules where country_code = 'ZO';
  delete from public.markets where country_code = 'ZO';
  delete from auth.users where id = any(fixture_auth);
end;
$$;

insert into public.markets (country_code, status) values ('ZO', 'ACTIVE');
insert into auth.users (id) values
  ('98000000-0000-0000-0000-000000000001'),
  ('98000000-0000-0000-0000-000000000002'),
  ('98000000-0000-0000-0000-000000000003'),
  ('98000000-0000-0000-0000-000000000004');

do $$
#variable_conflict use_variable
declare
  rider_person_id uuid;
  rider_account_id uuid;
  other_person_id uuid;
  other_account_id uuid;
  guardian_person_id uuid;
  guardian_account_id uuid;
  minor_person_id uuid;
  center_a_id uuid;
  center_b_id uuid;
  equine_id uuid;
  service_a_id uuid;
  service_b_id uuid;
  booking_id uuid;
  window_start timestamptz := timestamptz '2026-11-01 10:00:00+00';
begin

  if exists (
    select 1 from pg_catalog.pg_proc as procedure
      join pg_catalog.pg_namespace as namespace
        on namespace.oid = procedure.pronamespace
     where namespace.nspname = 'public'
       and procedure.proname = 'waive_booking_requirement'
  ) then
    raise exception '021 must not add a waive RPC';
  end if;

  if (
    select count(*) from pg_catalog.pg_class
     where oid in (
       'public.bookings'::regclass,
       'public.booking_requirements'::regclass
     ) and relrowsecurity
  ) <> 2 then
    raise exception '021 RLS is not enabled';
  end if;

  if exists (
    select 1 from pg_catalog.pg_policy
     where polrelid in (
       'public.bookings'::regclass,
       'public.booking_requirements'::regclass
     )
  ) then
    raise exception '021 tables unexpectedly gained client RLS policies';
  end if;

  if exists (
    select 1
      from information_schema.check_constraints as constraint_row
      join information_schema.constraint_column_usage as usage
        on usage.constraint_schema = constraint_row.constraint_schema
       and usage.constraint_name = constraint_row.constraint_name
     where constraint_row.constraint_schema = 'public'
       and usage.table_name in ('bookings', 'booking_requirements')
       and constraint_row.check_clause ilike '%now()%'
  ) then
    raise exception '021 table CHECKs must not use now()';
  end if;

  select person_id, id into rider_person_id, rider_account_id
    from public.user_accounts
   where auth_user_id = '98000000-0000-0000-0000-000000000001';
  select person_id, id into other_person_id, other_account_id
    from public.user_accounts
   where auth_user_id = '98000000-0000-0000-0000-000000000002';
  select person_id, id into guardian_person_id, guardian_account_id
    from public.user_accounts
   where auth_user_id = '98000000-0000-0000-0000-000000000003';
  select person_id into minor_person_id
    from public.user_accounts
   where auth_user_id = '98000000-0000-0000-0000-000000000004';

  insert into public.equestrian_centers (name, slug, country_code, status)
  values ('Phase11A Alpha', 'phase11a-alpha', 'ZO', 'ACTIVE')
  returning id into center_a_id;
  insert into public.equestrian_centers (name, slug, country_code, status)
  values ('Phase11A Beta', 'phase11a-beta', 'ZO', 'ACTIVE')
  returning id into center_b_id;

  insert into public.equines (name, equine_type)
  values ('phase11a-school', 'HORSE')
  returning id into equine_id;

  insert into public.center_services (
    center_id, service_type, name
  ) values (
    center_a_id, 'EQUINE_SESSION', 'Phase11A ride'
  ) returning id into service_a_id;
  insert into public.center_services (
    center_id, service_type, name
  ) values (
    center_b_id, 'EQUINE_SESSION', 'Phase11A other'
  ) returning id into service_b_id;

  begin
    insert into public.bookings (
      participant_person_id, booked_by_account_id, equine_id, center_id,
      service_id, starts_at, ends_at, status
    ) values (
      rider_person_id, rider_account_id, equine_id, center_a_id,
      service_a_id, window_start, window_start, 'REQUESTED'
    );
    raise exception 'Booking ends_at = starts_at was allowed';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.bookings (
      participant_person_id, booked_by_account_id, equine_id, center_id,
      service_id, starts_at, ends_at, status
    ) values (
      other_person_id, rider_account_id, equine_id, center_a_id,
      service_a_id, window_start, window_start + interval '1 hour',
      'REQUESTED'
    );
    raise exception 'Booker requested for an unrelated PERSON';
  exception
    when insufficient_privilege then null;
  end;

  begin
    insert into public.bookings (
      participant_person_id, booked_by_account_id, equine_id, center_id,
      service_id, starts_at, ends_at, status
    ) values (
      rider_person_id, rider_account_id, equine_id, center_a_id,
      service_b_id, window_start, window_start + interval '1 hour',
      'REQUESTED'
    );
    raise exception 'Booking used a service from another Center';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.bookings (
      participant_person_id, booked_by_account_id, equine_id, center_id,
      service_id, starts_at, ends_at, status, confirmed_at
    ) values (
      rider_person_id, rider_account_id, equine_id, center_a_id,
      service_a_id, window_start, window_start + interval '1 hour',
      'CONFIRMED', now()
    );
    raise exception '021 inserted a CONFIRMED booking';
  exception
    when insufficient_privilege then null;
  end;

  begin
    insert into public.bookings (
      participant_person_id, booked_by_account_id, equine_id, center_id,
      service_id, starts_at, ends_at, status, eligibility_status
    ) values (
      rider_person_id, rider_account_id, equine_id, center_a_id,
      service_a_id, window_start, window_start + interval '1 hour',
      'REQUESTED', 'READY'
    );
    raise exception 'Invented eligibility token was allowed';
  exception
    when check_violation then null;
  end;

  insert into public.bookings (
    participant_person_id, booked_by_account_id, equine_id, center_id,
    service_id, starts_at, ends_at, status, eligibility_status
  ) values (
    rider_person_id, rider_account_id, equine_id, center_a_id,
    service_a_id, window_start, window_start + interval '1 hour',
    'REQUESTED', 'REQUIRES_GUARDIAN_CONSENT'
  ) returning id into booking_id;

  begin
    update public.bookings
       set participant_person_id = other_person_id
     where id = booking_id;
    raise exception 'Booking identity was retargeted';
  exception
    when insufficient_privilege then null;
  end;

  begin
    update public.bookings
       set status = 'CONFIRMED',
           confirmed_at = now()
     where id = booking_id;
    raise exception '021 forced CONFIRMED on UPDATE';
  exception
    when insufficient_privilege then null;
  end;

  begin
    insert into public.booking_requirements (
      booking_id, requirement_type, source_type, status
    ) values (
      booking_id, 'LIABILITY_WAIVER', 'POLICY', 'PENDING'
    );
    raise exception 'Invented requirement type was allowed';
  exception
    when check_violation then null;
  end;

  insert into public.booking_requirements (
    booking_id, requirement_type, source_type, status
  ) values (
    booking_id, 'GUARDIAN_CONSENT', 'GUARDIAN', 'PENDING'
  );

  insert into public.booking_requirements (
    booking_id, requirement_type, source_type, status, resolved_at
  ) values (
    booking_id, 'POLICY_ACCEPTANCE', 'POLICY', 'WAIVED', now()
  );

  insert into public.guardian_relationships (
    guardian_person_id, minor_person_id, relationship_type,
    verification_status
  ) values (
    guardian_person_id, minor_person_id, 'PARENT', 'PENDING'
  );

  begin
    insert into public.bookings (
      participant_person_id, booked_by_account_id, equine_id, center_id,
      service_id, starts_at, ends_at, status
    ) values (
      minor_person_id, guardian_account_id, equine_id, center_a_id,
      service_a_id, window_start + interval '2 hours',
      window_start + interval '3 hours', 'REQUESTED'
    );
    raise exception 'Unverified guardian booked a minor';
  exception
    when insufficient_privilege then null;
  end;

  update public.guardian_relationships
     set verification_status = 'VERIFIED',
         verified_at = now()
   where public.guardian_relationships.guardian_person_id = guardian_person_id
     and public.guardian_relationships.minor_person_id = minor_person_id;

  insert into public.bookings (
    participant_person_id, booked_by_account_id, equine_id, center_id,
    service_id, starts_at, ends_at, status
  ) values (
    minor_person_id, guardian_account_id, equine_id, center_a_id,
    service_a_id, window_start + interval '2 hours',
    window_start + interval '3 hours', 'REQUESTED'
  );

  begin
    insert into public.bookings (
      participant_person_id, booked_by_account_id, equine_id, center_id,
      service_id, starts_at, ends_at, status
    ) values (
      minor_person_id, other_account_id, equine_id, center_a_id,
      service_a_id, window_start + interval '4 hours',
      window_start + interval '5 hours', 'REQUESTED'
    );
    raise exception 'Unrelated account booked a minor';
  exception
    when insufficient_privilege then null;
  end;

  perform set_config('app.booking_id', booking_id::text, true);
  perform set_config('app.rider_account_id', rider_account_id::text, true);
  perform set_config('app.rider_person_id', rider_person_id::text, true);
  perform set_config('app.equine_id', equine_id::text, true);
  perform set_config('app.center_a_id', center_a_id::text, true);
  perform set_config('app.service_a_id', service_a_id::text, true);
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '98000000-0000-0000-0000-000000000001', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"98000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);

do $$
begin
  begin
    perform * from public.bookings;
    raise exception 'Authenticated role selected bookings';
  exception
    when insufficient_privilege then null;
  end;

  begin
    insert into public.bookings (
      participant_person_id, booked_by_account_id, equine_id, center_id,
      service_id, starts_at, ends_at
    ) values (
      current_setting('app.rider_person_id', true)::uuid,
      current_setting('app.rider_account_id', true)::uuid,
      current_setting('app.equine_id', true)::uuid,
      current_setting('app.center_a_id', true)::uuid,
      current_setting('app.service_a_id', true)::uuid,
      timestamptz '2026-11-01 10:00:00+00',
      timestamptz '2026-11-01 11:00:00+00'
    );
    raise exception 'Authenticated role inserted a booking';
  exception
    when insufficient_privilege then null;
  end;

  begin
    update public.bookings set status = 'CONFIRMED';
    raise exception 'Authenticated role updated bookings';
  exception
    when insufficient_privilege then null;
  end;

  begin
    delete from public.bookings;
    raise exception 'Authenticated role deleted bookings';
  exception
    when insufficient_privilege then null;
  end;

  begin
    update public.booking_requirements set status = 'SATISFIED';
    raise exception 'Authenticated role updated booking requirements';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

reset role;

do $$
begin
  if has_table_privilege('anon', 'public.bookings', 'select')
     or has_table_privilege('authenticated', 'public.bookings', 'insert')
     or has_table_privilege('authenticated', 'public.bookings', 'update')
     or has_table_privilege('authenticated', 'public.bookings', 'delete')
     or has_table_privilege('authenticated', 'public.booking_requirements', 'insert')
     or has_function_privilege(
       'authenticated',
       'public.has_current_verified_guardian_relationship(uuid,uuid)',
       'execute'
     )
  then
    raise exception '021 client table privileges must stay revoked';
  end if;
end;
$$;

rollback;
