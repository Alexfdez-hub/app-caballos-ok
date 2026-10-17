-- Local vertical bookable-offer tests. Rolls back. Does not create a
-- remote fixture and does not call the hosted project.

begin;

insert into auth.users (id) values
  ('04220000-0000-4000-8000-0000000000a1'),
  ('04220000-0000-4000-8000-0000000000a2'),
  ('04220000-0000-4000-8000-0000000000a3');

do $$
declare
  rider_auth uuid := '04220000-0000-4000-8000-0000000000a1';
  staff_auth uuid := '04220000-0000-4000-8000-0000000000a2';
  offer_count integer;
  audit_before bigint;
  audit_after bigint;
  created_id uuid;
  replay_id uuid;
  other_id uuid;
  created_status text;
  created_outcome text;
  slot_count integer;
begin
  if has_function_privilege(
    'authenticated',
    'public.list_bookable_offers(timestamptz, timestamptz)',
    'EXECUTE'
  ) is not true
  or has_function_privilege(
    'authenticated',
    'public.get_bookable_offer(uuid, uuid, uuid, timestamptz, timestamptz)',
    'EXECUTE'
  ) is not true
  or has_function_privilege(
    'authenticated',
    'public.request_bookable_slot(uuid, uuid, uuid, uuid, timestamptz, timestamptz)',
    'EXECUTE'
  ) is not true
  or has_function_privilege(
    'authenticated',
    'public.get_my_booking_request(uuid)',
    'EXECUTE'
  ) is not true
  or has_function_privilege(
    'authenticated',
    'public.list_bookings_i_can_confirm()',
    'EXECUTE'
  ) is not true then
    raise exception 'authenticated is missing a bookable RPC';
  end if;

  if has_function_privilege(
    'anon',
    'public.list_bookable_offers(timestamptz, timestamptz)',
    'EXECUTE'
  )
  or has_function_privilege(
    'service_role',
    'public.list_bookable_offers(timestamptz, timestamptz)',
    'EXECUTE'
  )
  or has_function_privilege(
    'authenticated',
    'public.vertical_fixture_install(uuid, uuid)',
    'EXECUTE'
  )
  or has_function_privilege(
    'authenticated',
    'public.vertical_fixture_retire()',
    'EXECUTE'
  )
  or has_function_privilege(
    'service_role',
    'public.vertical_fixture_install(uuid, uuid)',
    'EXECUTE'
  )
  or has_function_privilege(
    'public',
    'public.assert_bookable_reader()',
    'EXECUTE'
  )
  or has_function_privilege(
    'authenticated',
    'public.open_bookable_pilot(text)',
    'EXECUTE'
  )
  or has_function_privilege(
    'service_role',
    'public.open_bookable_pilot(text)',
    'EXECUTE'
  )
  or has_function_privilege(
    'authenticated',
    'public.add_bookable_pilot_subject(uuid, uuid, uuid)',
    'EXECUTE'
  )
  or has_function_privilege(
    'authenticated',
    'public.end_bookable_pilot_subject(uuid, uuid, uuid)',
    'EXECUTE'
  )
  or has_function_privilege(
    'authenticated',
    'public.close_bookable_pilot(uuid)',
    'EXECUTE'
  )
  or has_function_privilege(
    'anon',
    'public.equine_center_is_in_open_bookable_pilot(uuid, uuid)',
    'EXECUTE'
  ) then
    raise exception 'bookable execute grants are wider than authenticated reads';
  end if;

  begin
    perform public.vertical_fixture_install(rider_auth, staff_auth);
    raise exception 'fixture ran without the local gate';
  exception
    when insufficient_privilege then
      null;
  end;

  perform set_config('app.vertical_fixture_local', '1', true);

  begin
    perform public.vertical_fixture_install(
      '04220000-0000-4000-8000-000000000099',
      staff_auth
    );
    raise exception 'fixture created an auth user';
  exception
    when sqlstate 'P0002' then
      null;
  end;

  perform public.vertical_fixture_install(rider_auth, staff_auth);
  perform public.vertical_fixture_install(rider_auth, staff_auth);

  if (
    select count(*)
      from public.equestrian_centers
     where id = '04210000-0000-4000-8000-0000000000c1'
  ) <> 1 then
    raise exception 'fixture install was not idempotent';
  end if;

  if (
    select count(*)
      from public.bookable_pilot_events
  ) <> 2
  or (
    select count(*)
      from public.bookable_pilot_subjects as subject
     where subject.equine_id = '04210000-0000-4000-8000-0000000000e1'
       and subject.center_id = '04210000-0000-4000-8000-0000000000c1'
       and subject.status = 'ACTIVE'
  ) <> 1 then
    raise exception 'pilot enrollment was not audited once';
  end if;

  insert into public.equines (
    id, name, equine_type, status, visibility_status
  ) values (
    '04210000-0000-4000-8000-0000000000e3',
    'TEST_ONLY Public Outside Pilot',
    'HORSE',
    'ACTIVE',
    'PUBLIC'
  );

  insert into public.equine_center_assignments (
    id, equine_id, center_id, assignment_type
  ) values (
    '04210000-0000-4000-8000-0000000000a3',
    '04210000-0000-4000-8000-0000000000e3',
    '04210000-0000-4000-8000-0000000000c1',
    'SCHOOL'
  );

  insert into public.equine_center_permissions (
    id, equine_id, center_id, granted_by_person_id, permission_code
  )
  select
    permission.id,
    '04210000-0000-4000-8000-0000000000e3',
    '04210000-0000-4000-8000-0000000000c1',
    account.person_id,
    permission.permission_code
  from public.user_accounts as account
  cross join (
    values
      ('04210000-0000-4000-8000-0000000000d6'::uuid, 'MANAGE_REQUIREMENTS'),
      ('04210000-0000-4000-8000-0000000000d7'::uuid, 'MANAGE_AVAILABILITY')
  ) as permission (id, permission_code)
  where account.auth_user_id = staff_auth;

  insert into public.service_equines (
    service_id, equine_id, enabled, status
  ) values (
    '04210000-0000-4000-8000-0000000000f1',
    '04210000-0000-4000-8000-0000000000e3',
    true,
    'ACTIVE'
  );

  insert into public.equine_availability_rules (
    id, equine_id, center_id, starts_at, ends_at, created_by_account_id
  )
  select
    '04210000-0000-4000-8000-0000000000f6',
    '04210000-0000-4000-8000-0000000000e3',
    '04210000-0000-4000-8000-0000000000c1',
    timestamptz '2026-12-02 09:00:00+00',
    timestamptz '2026-12-02 12:00:00+00',
    account.id
  from public.user_accounts as account
  where account.auth_user_id = staff_auth;

  update public.persons
     set first_name = 'TEST_ONLY',
         last_name = 'Rider',
         date_of_birth = date '1990-01-01'
   where id = (
     select person_id from public.user_accounts where auth_user_id = rider_auth
   );

  update public.persons
     set first_name = 'TEST_ONLY',
         last_name = 'Staff',
         date_of_birth = date '1985-01-01'
   where id = (
     select person_id from public.user_accounts where auth_user_id = staff_auth
   );

  update public.persons
     set first_name = 'TEST_ONLY',
         last_name = 'Other',
         date_of_birth = date '1988-01-01'
   where id = (
     select person_id
       from public.user_accounts
      where auth_user_id = '04220000-0000-4000-8000-0000000000a3'
   );

  insert into public.policy_documents (
    policy_code, policy_type, market_code, locale, version, title, content,
    effective_from, status, requires_reacceptance
  ) values (
    'TERMS_VT', 'TERMS_OF_SERVICE', 'VT', 'es', '1',
    'TEST_ONLY terms', 'TEST_ONLY', now() - interval '1 day', 'ACTIVE', false
  );

  insert into public.policy_acceptances (
    policy_document_id, person_id, user_account_id, accepted_at
  )
  select document.id, account.person_id, account.id, now()
    from public.policy_documents as document
    join public.user_accounts as account
      on account.auth_user_id in (rider_auth, '04220000-0000-4000-8000-0000000000a3')
   where document.policy_code = 'TERMS_VT';
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '04220000-0000-4000-8000-0000000000a1', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"04220000-0000-4000-8000-0000000000a1","role":"authenticated"}',
  true
);

do $$
declare
  offer_count integer;
begin
  begin
    perform public.vertical_fixture_install(
      '04220000-0000-4000-8000-0000000000a1',
      '04220000-0000-4000-8000-0000000000a2'
    );
    raise exception 'authenticated installed the fixture';
  exception
    when insufficient_privilege then
      null;
  end;

  select count(*)
    into offer_count
    from public.list_bookable_offers(
      timestamptz '2026-12-02 09:00:00+00',
      timestamptz '2026-12-02 12:00:00+00'
    ) as offer
   where offer.equine_name = 'TEST_ONLY Equine';

  if offer_count <> 3 then
    raise exception 'expected 3 bookable slots, got %', offer_count;
  end if;

  if exists (
    select 1
      from public.list_bookable_offers(
        timestamptz '2026-12-02 09:00:00+00',
        timestamptz '2026-12-02 12:00:00+00'
      ) as offer
     where offer.equine_name = 'TEST_ONLY Private Equine'
  ) then
    raise exception 'private equine was listed';
  end if;

  if exists (
    select 1
      from public.get_bookable_offer(
        '04210000-0000-4000-8000-0000000000e2',
        '04210000-0000-4000-8000-0000000000c1',
        '04210000-0000-4000-8000-0000000000f1',
        timestamptz '2026-12-02 09:00:00+00',
        timestamptz '2026-12-02 10:00:00+00'
      )
  ) then
    raise exception 'private equine was readable by uuid';
  end if;

  if exists (
    select 1
      from public.get_bookable_offer(
        '04210000-0000-4000-8000-000000000099',
        '04210000-0000-4000-8000-0000000000c1',
        '04210000-0000-4000-8000-0000000000f1',
        timestamptz '2026-12-02 09:00:00+00',
        timestamptz '2026-12-02 10:00:00+00'
      )
  ) then
    raise exception 'unknown equine uuid returned a row';
  end if;

  if exists (
    select 1
      from public.list_bookable_offers(
        timestamptz '2026-12-02 09:00:00+00',
        timestamptz '2026-12-02 12:00:00+00'
      ) as offer
     where offer.equine_id = '04210000-0000-4000-8000-0000000000e3'
  ) or exists (
    select 1
      from public.get_bookable_offer(
        '04210000-0000-4000-8000-0000000000e3',
        '04210000-0000-4000-8000-0000000000c1',
        '04210000-0000-4000-8000-0000000000f1',
        timestamptz '2026-12-02 09:00:00+00',
        timestamptz '2026-12-02 10:00:00+00'
      )
  ) then
    raise exception 'a public equine outside the pilot was bookable';
  end if;

  begin
    perform public.open_bookable_pilot('VERTICAL_MVP_042');
    raise exception 'authenticated opened a pilot';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    perform public.list_bookable_offers(
      timestamptz '2026-12-02 09:00:00+00',
      timestamptz '2026-12-20 09:00:00+00'
    );
    raise exception '15 day query was accepted';
  exception
    when invalid_parameter_value then
      null;
  end;
end;
$$;

reset role;

do $$
declare
  probe_id uuid;
begin
  probe_id := public.open_bookable_pilot('PILOT_CLOSED_PROBE');
  perform public.add_bookable_pilot_subject(
    probe_id,
    '04210000-0000-4000-8000-0000000000c1',
    '04210000-0000-4000-8000-0000000000e3'
  );
  perform public.add_bookable_pilot_subject(
    probe_id,
    '04210000-0000-4000-8000-0000000000c1',
    '04210000-0000-4000-8000-0000000000e3'
  );
  if (
    select count(*)
      from public.bookable_pilot_events
     where event_type = 'SUBJECT_ADDED'
       and equine_id = '04210000-0000-4000-8000-0000000000e3'
  ) <> 1 then
    raise exception 'adding an active subject wrote another event';
  end if;
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '04220000-0000-4000-8000-0000000000a1', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"04220000-0000-4000-8000-0000000000a1","role":"authenticated"}',
  true
);

do $$
declare
  outside_count integer;
begin
  select count(*)
    into outside_count
    from public.list_bookable_offers(
      timestamptz '2026-12-02 09:00:00+00',
      timestamptz '2026-12-02 12:00:00+00'
    ) as offer
   where offer.equine_id = '04210000-0000-4000-8000-0000000000e3';
  if outside_count <> 3 then
    raise exception 'an admitted public equine stayed hidden, got %', outside_count;
  end if;
end;
$$;

reset role;

do $$
declare
  probe_id uuid;
  vertical_id uuid;
begin
  select id
    into probe_id
    from public.bookable_pilots
   where pilot_code = 'PILOT_CLOSED_PROBE';

  perform public.close_bookable_pilot(probe_id);

  begin
    perform public.open_bookable_pilot('PILOT_CLOSED_PROBE');
    raise exception 'a closed pilot was reopened';
  exception
    when insufficient_privilege then
      null;
  end;

  select id
    into vertical_id
    from public.bookable_pilots
   where pilot_code = 'VERTICAL_MVP_042';

  perform public.end_bookable_pilot_subject(
    vertical_id,
    '04210000-0000-4000-8000-0000000000c1',
    '04210000-0000-4000-8000-0000000000e1'
  );
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '04220000-0000-4000-8000-0000000000a1', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"04220000-0000-4000-8000-0000000000a1","role":"authenticated"}',
  true
);

do $$
declare
  offer_count integer;
  outside_count integer;
begin
  select count(*)
    into outside_count
    from public.list_bookable_offers(
      timestamptz '2026-12-02 09:00:00+00',
      timestamptz '2026-12-02 12:00:00+00'
    ) as offer
   where offer.equine_id = '04210000-0000-4000-8000-0000000000e3';
  if outside_count <> 0 then
    raise exception 'a closed pilot still published a public equine';
  end if;

  select count(*)
    into offer_count
    from public.list_bookable_offers(
      timestamptz '2026-12-02 09:00:00+00',
      timestamptz '2026-12-02 12:00:00+00'
    );
  if offer_count <> 0 then
    raise exception 'ending the pilot subject still published slots';
  end if;

  begin
    perform public.request_bookable_slot(
      '04220000-0000-4000-8000-0000000000c6',
      '04210000-0000-4000-8000-0000000000e1',
      '04210000-0000-4000-8000-0000000000c1',
      '04210000-0000-4000-8000-0000000000f1',
      timestamptz '2026-12-02 09:00:00+00',
      timestamptz '2026-12-02 10:00:00+00'
    );
    raise exception 'request succeeded outside the pilot';
  exception
    when insufficient_privilege then
      if sqlerrm is distinct from 'Bookable offer is not available' then
        raise;
      end if;
  end;

  if exists (
    select 1
      from public.get_bookable_offer(
        '04210000-0000-4000-8000-0000000000e1',
        '04210000-0000-4000-8000-0000000000c1',
        '04210000-0000-4000-8000-0000000000f1',
        timestamptz '2026-12-02 09:00:00+00',
        timestamptz '2026-12-02 10:00:00+00'
      )
  ) then
    raise exception 'exact uuid bypassed the pilot gate';
  end if;
end;
$$;

reset role;

do $$
declare
  vertical_id uuid;
begin
  select id
    into vertical_id
    from public.bookable_pilots
   where pilot_code = 'VERTICAL_MVP_042';

  perform public.add_bookable_pilot_subject(
    vertical_id,
    '04210000-0000-4000-8000-0000000000c1',
    '04210000-0000-4000-8000-0000000000e1'
  );
end;
$$;

do $$
declare
  staff_account uuid;
  offer_count integer;
begin
  select id
    into staff_account
    from public.user_accounts
   where auth_user_id = '04220000-0000-4000-8000-0000000000a2';

  insert into public.equine_calendar_blocks (
    equine_id, center_id, starts_at, ends_at, block_type, source_type, status,
    created_by_account_id
  ) values (
    '04210000-0000-4000-8000-0000000000e1',
    '04210000-0000-4000-8000-0000000000c1',
    timestamptz '2026-12-02 08:00:00+00',
    timestamptz '2026-12-02 09:00:00+00',
    'REST',
    'MANUAL',
    'ACTIVE',
    staff_account
  );

  insert into public.equine_availability_rules (
    equine_id, center_id, starts_at, ends_at, recurrence_rule, created_by_account_id
  ) values (
    '04210000-0000-4000-8000-0000000000e1',
    '04210000-0000-4000-8000-0000000000c1',
    timestamptz '2026-12-02 13:00:00+00',
    timestamptz '2026-12-02 14:00:00+00',
    'FREQ=DAILY',
    staff_account
  );
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '04220000-0000-4000-8000-0000000000a3', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"04220000-0000-4000-8000-0000000000a3","role":"authenticated"}',
  true
);

do $$
declare
  offer_count integer;
begin
  select count(*)
    into offer_count
    from public.list_bookable_offers(
      timestamptz '2026-12-02 08:00:00+00',
      timestamptz '2026-12-02 15:00:00+00'
    ) as offer
   where offer.equine_id = '04210000-0000-4000-8000-0000000000e1';

  if offer_count <> 3 then
    raise exception 'opening boundary or recurrence changed the slot count to %', offer_count;
  end if;
end;
$$;

reset role;

do $$
declare
  staff_account uuid;
begin
  select id
    into staff_account
    from public.user_accounts
   where auth_user_id = '04220000-0000-4000-8000-0000000000a2';

  update public.equine_calendar_blocks
     set status = 'CANCELLED',
         cancelled_at = now()
   where equine_id = '04210000-0000-4000-8000-0000000000e1'
     and starts_at = timestamptz '2026-12-02 08:00:00+00';

  insert into public.equine_calendar_blocks (
    equine_id, center_id, starts_at, ends_at, block_type, source_type, status,
    created_by_account_id
  ) values (
    '04210000-0000-4000-8000-0000000000e1',
    '04210000-0000-4000-8000-0000000000c1',
    timestamptz '2026-12-02 09:30:00+00',
    timestamptz '2026-12-02 10:30:00+00',
    'REST',
    'MANUAL',
    'ACTIVE',
    staff_account
  );
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '04220000-0000-4000-8000-0000000000a1', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"04220000-0000-4000-8000-0000000000a1","role":"authenticated"}',
  true
);

do $$
declare
  offer_count integer;
begin
  select count(*)
    into offer_count
    from public.list_bookable_offers(
      timestamptz '2026-12-02 09:00:00+00',
      timestamptz '2026-12-02 12:00:00+00'
    );
  if offer_count <> 1 then
    raise exception 'partial overlap should leave one slot, got %', offer_count;
  end if;
end;
$$;

reset role;

do $$
declare
  staff_account uuid;
begin
  select id
    into staff_account
    from public.user_accounts
   where auth_user_id = '04220000-0000-4000-8000-0000000000a2';

  update public.equine_calendar_blocks
     set status = 'CANCELLED',
         cancelled_at = now()
   where equine_id = '04210000-0000-4000-8000-0000000000e1'
     and status = 'ACTIVE'
     and block_type = 'REST';

  insert into public.equine_calendar_blocks (
    equine_id, center_id, starts_at, ends_at, block_type, source_type, status,
    created_by_account_id
  ) values (
    '04210000-0000-4000-8000-0000000000e1',
    '04210000-0000-4000-8000-0000000000c1',
    timestamptz '2026-12-02 10:00:00+00',
    timestamptz '2026-12-02 11:00:00+00',
    'REST',
    'MANUAL',
    'ACTIVE',
    staff_account
  );
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '04220000-0000-4000-8000-0000000000a1', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"04220000-0000-4000-8000-0000000000a1","role":"authenticated"}',
  true
);

do $$
declare
  early_count integer;
  late_count integer;
begin
  select count(*)
    into early_count
    from public.list_bookable_offers(
      timestamptz '2026-12-02 09:00:00+00',
      timestamptz '2026-12-02 10:00:00+00'
    );
  select count(*)
    into late_count
    from public.list_bookable_offers(
      timestamptz '2026-12-02 11:00:00+00',
      timestamptz '2026-12-02 12:00:00+00'
    );
  if early_count <> 1 or late_count <> 1 then
    raise exception 'exact block boundary failed early=% late=%', early_count, late_count;
  end if;
end;
$$;

reset role;

do $$
begin
  update public.equine_calendar_blocks
     set status = 'CANCELLED',
         cancelled_at = now()
   where equine_id = '04210000-0000-4000-8000-0000000000e1'
     and status = 'ACTIVE'
     and block_type = 'REST';

  update public.equine_ownerships
     set status = 'ENDED',
         ended_at = now()
   where id = '04210000-0000-4000-8000-0000000000b1';
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '04220000-0000-4000-8000-0000000000a1', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"04220000-0000-4000-8000-0000000000a1","role":"authenticated"}',
  true
);

do $$
declare
  offer_count integer;
  request_row record;
  replay_row record;
  activity_count integer;
begin
  select count(*)
    into offer_count
    from public.list_bookable_offers(
      timestamptz '2026-12-02 09:00:00+00',
      timestamptz '2026-12-02 12:00:00+00'
    );
  if offer_count <> 3 then
    raise exception 'ended ownership hid a bookable slot, got %', offer_count;
  end if;

  select result.booking_id, result.booking_status, result.outcome
    into request_row
    from public.request_bookable_slot(
      '04220000-0000-4000-8000-0000000000c1',
      '04210000-0000-4000-8000-0000000000e1',
      '04210000-0000-4000-8000-0000000000c1',
      '04210000-0000-4000-8000-0000000000f1',
      timestamptz '2026-12-02 09:00:00+00',
      timestamptz '2026-12-02 10:00:00+00'
    ) as result;

  if request_row.outcome is distinct from 'CREATED'
     or request_row.booking_status is distinct from 'APPROVED' then
    raise exception 'request outcome % status %', request_row.outcome, request_row.booking_status;
  end if;

  select result.booking_id, result.outcome
    into replay_row
    from public.request_bookable_slot(
      '04220000-0000-4000-8000-0000000000c1',
      '04210000-0000-4000-8000-0000000000e1',
      '04210000-0000-4000-8000-0000000000c1',
      '04210000-0000-4000-8000-0000000000f1',
      timestamptz '2026-12-02 09:00:00+00',
      timestamptz '2026-12-02 10:00:00+00'
    ) as result;

  if replay_row.outcome is distinct from 'REPLAYED'
     or replay_row.booking_id is distinct from request_row.booking_id then
    raise exception 'same key did not replay';
  end if;

  select result.outcome
    into replay_row
    from public.request_bookable_slot(
      '04220000-0000-4000-8000-0000000000c2',
      '04210000-0000-4000-8000-0000000000e1',
      '04210000-0000-4000-8000-0000000000c1',
      '04210000-0000-4000-8000-0000000000f1',
      timestamptz '2026-12-02 09:00:00+00',
      timestamptz '2026-12-02 10:00:00+00'
    ) as result;

  if replay_row.outcome is distinct from 'REPLAYED' then
    raise exception 'second key created another open request';
  end if;

  select count(*)
    into activity_count
    from public.list_my_activity() as activity
   where activity.booking_id = request_row.booking_id;
  if activity_count <> 1 then
    raise exception 'rider activity did not show the request';
  end if;

  perform set_config('app.vertical_booking_id', request_row.booking_id::text, true);
end;
$$;

reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '04220000-0000-4000-8000-0000000000a3', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"04220000-0000-4000-8000-0000000000a3","role":"authenticated"}',
  true
);

do $$
declare
  activity_count integer;
  other_row record;
  confirm_count integer;
begin
  select count(*)
    into activity_count
    from public.list_my_activity() as activity
   where activity.booking_id = current_setting('app.vertical_booking_id')::uuid;
  if activity_count <> 0 then
    raise exception 'the other account saw the rider booking';
  end if;

  select count(*)
    into confirm_count
    from public.list_bookings_i_can_confirm();
  if confirm_count <> 0 then
    raise exception 'a rider without MANAGE_BOOKINGS saw the confirm queue';
  end if;

  select result.booking_id, result.booking_status, result.outcome
    into other_row
    from public.request_bookable_slot(
      '04220000-0000-4000-8000-0000000000c3',
      '04210000-0000-4000-8000-0000000000e1',
      '04210000-0000-4000-8000-0000000000c1',
      '04210000-0000-4000-8000-0000000000f1',
      timestamptz '2026-12-02 09:00:00+00',
      timestamptz '2026-12-02 10:00:00+00'
    ) as result;

  if other_row.outcome is distinct from 'CREATED'
     or other_row.booking_id = current_setting('app.vertical_booking_id')::uuid then
    raise exception 'second account could not request the same slot';
  end if;

  perform set_config('app.vertical_other_booking_id', other_row.booking_id::text, true);

  begin
    perform public.confirm_booking(current_setting('app.vertical_booking_id')::uuid);
    raise exception 'rider confirmed a booking';
  exception
    when insufficient_privilege then
      null;
  end;
end;
$$;

reset role;

reset role;

do $$
declare
  vertical_id uuid;
begin
  select id
    into vertical_id
    from public.bookable_pilots
   where pilot_code = 'VERTICAL_MVP_042';

  perform public.end_bookable_pilot_subject(
    vertical_id,
    '04210000-0000-4000-8000-0000000000c1',
    '04210000-0000-4000-8000-0000000000e1'
  );
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '04220000-0000-4000-8000-0000000000a2', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"04220000-0000-4000-8000-0000000000a2","role":"authenticated"}',
  true
);

do $$
declare
  confirm_count integer;
begin
  select count(*)
    into confirm_count
    from public.list_bookings_i_can_confirm();
  if confirm_count <> 0 then
    raise exception 'ended pilot subject stayed in the confirm queue';
  end if;
end;
$$;

reset role;

do $$
declare
  vertical_id uuid;
begin
  select id
    into vertical_id
    from public.bookable_pilots
   where pilot_code = 'VERTICAL_MVP_042';

  perform public.add_bookable_pilot_subject(
    vertical_id,
    '04210000-0000-4000-8000-0000000000c1',
    '04210000-0000-4000-8000-0000000000e1'
  );
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '04220000-0000-4000-8000-0000000000a2', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"04220000-0000-4000-8000-0000000000a2","role":"authenticated"}',
  true
);

do $$
declare
  confirm_count integer;
  confirmed_id uuid;
begin
  select count(*)
    into confirm_count
    from public.list_bookings_i_can_confirm() as booking
   where booking.booking_id = current_setting('app.vertical_booking_id')::uuid;
  if confirm_count <> 1 then
    raise exception 'staff confirm queue missed the approved request';
  end if;

  confirmed_id := public.confirm_booking(
    current_setting('app.vertical_booking_id')::uuid
  );
  if confirmed_id is null then
    raise exception 'staff confirm returned null';
  end if;

  begin
    perform public.confirm_booking(current_setting('app.vertical_other_booking_id')::uuid);
    raise exception 'second confirm of the same slot succeeded';
  exception
    when others then
      if sqlstate not in ('23P01', '42501', '23514', 'P0001') then
        raise;
      end if;
  end;
end;
$$;

reset role;

do $$
declare
  offer_count integer;
begin
  update public.equine_center_assignments
     set status = 'ENDED',
         ended_at = now()
   where id = '04210000-0000-4000-8000-0000000000a1';

  update public.center_memberships
     set status = 'ENDED',
         ended_at = now()
   where id = '04210000-0000-4000-8000-0000000000f7';
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '04220000-0000-4000-8000-0000000000a1', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"04220000-0000-4000-8000-0000000000a1","role":"authenticated"}',
  true
);

do $$
declare
  offer_count integer;
begin
  select count(*)
    into offer_count
    from public.list_bookable_offers(
      timestamptz '2026-12-02 11:00:00+00',
      timestamptz '2026-12-02 12:00:00+00'
    );
  if offer_count <> 0 then
    raise exception 'ended assignment still published a slot';
  end if;

  begin
    perform public.request_bookable_slot(
      '04220000-0000-4000-8000-0000000000c4',
      '04210000-0000-4000-8000-0000000000e1',
      '04210000-0000-4000-8000-0000000000c1',
      '04210000-0000-4000-8000-0000000000f1',
      timestamptz '2026-12-02 11:00:00+00',
      timestamptz '2026-12-02 12:00:00+00'
    );
    raise exception 'request succeeded after the assignment ended';
  exception
    when insufficient_privilege then
      null;
  end;
end;
$$;

reset role;

do $$
declare
  staff_account uuid;
  audit_before bigint;
  audit_after bigint;
  offer_count integer;
begin
  select count(*) into audit_before from public.audit_events;
  select count(*) into offer_count from public.bookable_pilot_events;

  perform set_config('app.vertical_fixture_local', '1', true);
  perform public.vertical_fixture_retire();

  select count(*) into audit_after from public.audit_events;
  if audit_after < audit_before then
    raise exception 'fixture retire deleted audit';
  end if;

  if (
    select count(*)
      from public.bookable_pilot_events
  ) < offer_count then
    raise exception 'fixture retire deleted pilot history';
  end if;

  begin
    update public.bookable_pilot_events
       set event_type = 'PILOT_CLOSED';
    raise exception 'pilot history was updated';
  exception
    when insufficient_privilege then
      null;
  end;

  if not exists (
    select 1
      from auth.users
     where id = '04220000-0000-4000-8000-0000000000a1'
  ) then
    raise exception 'fixture retire deleted an auth user';
  end if;

  perform public.vertical_fixture_install(
    '04220000-0000-4000-8000-0000000000a1',
    '04220000-0000-4000-8000-0000000000a2'
  );
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '04220000-0000-4000-8000-0000000000a1', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"04220000-0000-4000-8000-0000000000a1","role":"authenticated"}',
  true
);

do $$
declare
  offer_count integer;
begin
  select count(*)
    into offer_count
    from public.list_bookable_offers(
      timestamptz '2026-12-02 11:00:00+00',
      timestamptz '2026-12-02 12:00:00+00'
    ) as offer
   where offer.equine_name = 'TEST_ONLY Equine';

  if offer_count <> 1 then
    raise exception 'install after retire did not restore the remaining slot, got %', offer_count;
  end if;
end;
$$;

reset role;

do $$
declare
  staff_account uuid;
begin
  select id
    into staff_account
    from public.user_accounts
   where auth_user_id = '04220000-0000-4000-8000-0000000000a2';

  insert into public.center_services (
    id, center_id, service_type, name, default_duration_minutes, status
  ) values (
    '04210000-0000-4000-8000-0000000000f8',
    '04210000-0000-4000-8000-0000000000c1',
    'EQUINE_SESSION',
    'TEST_ONLY Limited',
    60,
    'ACTIVE'
  );

  insert into public.service_equines (
    service_id, equine_id, enabled, duration_limit_minutes, status
  ) values (
    '04210000-0000-4000-8000-0000000000f8',
    '04210000-0000-4000-8000-0000000000e1',
    true,
    30,
    'ACTIVE'
  );

  insert into public.center_services (
    id, center_id, service_type, name, status
  ) values (
    '04210000-0000-4000-8000-0000000000f9',
    '04210000-0000-4000-8000-0000000000c1',
    'EQUINE_SESSION',
    'TEST_ONLY Whole Window',
    'ACTIVE'
  );

  insert into public.service_equines (
    service_id, equine_id, enabled, status
  ) values (
    '04210000-0000-4000-8000-0000000000f9',
    '04210000-0000-4000-8000-0000000000e1',
    true,
    'ACTIVE'
  );
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '04220000-0000-4000-8000-0000000000a1', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"04220000-0000-4000-8000-0000000000a1","role":"authenticated"}',
  true
);

do $$
declare
  limited_count integer;
  whole_count integer;
begin
  select count(*)
    into limited_count
    from public.list_bookable_offers(
      timestamptz '2026-12-02 09:00:00+00',
      timestamptz '2026-12-02 12:00:00+00'
    ) as offer
   where offer.service_id = '04210000-0000-4000-8000-0000000000f8';

  select count(*)
    into whole_count
    from public.list_bookable_offers(
      timestamptz '2026-12-02 09:00:00+00',
      timestamptz '2026-12-02 12:00:00+00'
    ) as offer
   where offer.service_id = '04210000-0000-4000-8000-0000000000f9'
     and offer.duration_limit_minutes is null
     and offer.default_duration_minutes is null;

  if limited_count <> 0 then
    raise exception 'a 60 minute slot was offered under a 30 minute limit';
  end if;

  if whole_count <> 1 then
    raise exception 'null duration should return the whole window once, got %', whole_count;
  end if;
end;
$$;

reset role;

do $$
declare
  rider_account uuid;
begin
  select id
    into rider_account
    from public.user_accounts
   where auth_user_id = '04220000-0000-4000-8000-0000000000a1';

  insert into public.booking_request_keys (
    account_id, client_request_id, equine_id, center_id, service_id,
    starts_at, ends_at
  ) values (
    rider_account,
    '04220000-0000-4000-8000-0000000000c5',
    '04210000-0000-4000-8000-0000000000e1',
    '04210000-0000-4000-8000-0000000000c1',
    '04210000-0000-4000-8000-0000000000f1',
    timestamptz '2026-12-02 11:00:00+00',
    timestamptz '2026-12-02 12:00:00+00'
  );
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '04220000-0000-4000-8000-0000000000a1', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"04220000-0000-4000-8000-0000000000a1","role":"authenticated"}',
  true
);

do $$
declare
  reconcile_outcome text;
begin
  select result.outcome
    into reconcile_outcome
    from public.get_my_booking_request(
      '04220000-0000-4000-8000-0000000000c5'
    ) as result;

  if reconcile_outcome is distinct from 'AMBIGUOUS' then
    raise exception 'null key should reconcile as AMBIGUOUS, got %', reconcile_outcome;
  end if;

  begin
    perform public.request_bookable_slot(
      '04220000-0000-4000-8000-0000000000c5',
      '04210000-0000-4000-8000-0000000000e1',
      '04210000-0000-4000-8000-0000000000c1',
      '04210000-0000-4000-8000-0000000000f1',
      timestamptz '2026-12-02 11:00:00+00',
      timestamptz '2026-12-02 12:00:00+00'
    );
    raise exception 'ambiguous key created another booking';
  exception
    when sqlstate 'P0001' then
      null;
  end;
end;
$$;

reset role;

update public.user_accounts
   set status = 'SUSPENDED'
 where auth_user_id = '04220000-0000-4000-8000-0000000000a1';

set local role authenticated;
select set_config('request.jwt.claim.sub', '04220000-0000-4000-8000-0000000000a1', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"04220000-0000-4000-8000-0000000000a1","role":"authenticated"}',
  true
);

do $$
begin
  begin
    perform public.list_bookable_offers(
      timestamptz '2026-12-02 09:00:00+00',
      timestamptz '2026-12-02 12:00:00+00'
    );
    raise exception 'suspended account listed offers';
  exception
    when insufficient_privilege then
      if sqlerrm is distinct from 'Bookable request is not available' then
        raise;
      end if;
  end;

  begin
    perform public.get_bookable_offer(
      '04210000-0000-4000-8000-0000000000e1',
      '04210000-0000-4000-8000-0000000000c1',
      '04210000-0000-4000-8000-0000000000f1',
      timestamptz '2026-12-02 11:00:00+00',
      timestamptz '2026-12-02 12:00:00+00'
    );
    raise exception 'suspended account read an offer';
  exception
    when insufficient_privilege then
      if sqlerrm is distinct from 'Bookable request is not available' then
        raise;
      end if;
  end;

  begin
    perform public.request_bookable_slot(
      '04220000-0000-4000-8000-0000000000c7',
      '04210000-0000-4000-8000-0000000000e1',
      '04210000-0000-4000-8000-0000000000c1',
      '04210000-0000-4000-8000-0000000000f1',
      timestamptz '2026-12-02 11:00:00+00',
      timestamptz '2026-12-02 12:00:00+00'
    );
    raise exception 'suspended account requested a slot';
  exception
    when insufficient_privilege then
      if sqlerrm is distinct from 'Bookable request is not available' then
        raise;
      end if;
  end;

  begin
    perform public.get_my_booking_request(
      '04220000-0000-4000-8000-0000000000c5'
    );
    raise exception 'suspended account reconciled a request';
  exception
    when insufficient_privilege then
      if sqlerrm is distinct from 'Bookable request is not available' then
        raise;
      end if;
  end;

  begin
    perform public.list_bookings_i_can_confirm();
    raise exception 'suspended account listed the confirm queue';
  exception
    when insufficient_privilege then
      if sqlerrm is distinct from 'Bookable request is not available' then
        raise;
      end if;
  end;
end;
$$;

reset role;

update public.user_accounts
   set status = 'ACTIVE'
 where auth_user_id = '04220000-0000-4000-8000-0000000000a1';

update public.persons
   set status = 'SUSPENDED'
 where id = (
   select person_id
     from public.user_accounts
    where auth_user_id = '04220000-0000-4000-8000-0000000000a1'
 );

set local role authenticated;
select set_config('request.jwt.claim.sub', '04220000-0000-4000-8000-0000000000a1', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"04220000-0000-4000-8000-0000000000a1","role":"authenticated"}',
  true
);

do $$
begin
  begin
    perform public.list_bookable_offers(
      timestamptz '2026-12-02 09:00:00+00',
      timestamptz '2026-12-02 12:00:00+00'
    );
    raise exception 'suspended person listed offers';
  exception
    when insufficient_privilege then
      if sqlerrm is distinct from 'Bookable request is not available' then
        raise;
      end if;
  end;

  begin
    perform public.get_bookable_offer(
      '04210000-0000-4000-8000-0000000000e1',
      '04210000-0000-4000-8000-0000000000c1',
      '04210000-0000-4000-8000-0000000000f1',
      timestamptz '2026-12-02 11:00:00+00',
      timestamptz '2026-12-02 12:00:00+00'
    );
    raise exception 'suspended person read an offer';
  exception
    when insufficient_privilege then
      if sqlerrm is distinct from 'Bookable request is not available' then
        raise;
      end if;
  end;

  begin
    perform public.request_bookable_slot(
      '04220000-0000-4000-8000-0000000000c8',
      '04210000-0000-4000-8000-0000000000e1',
      '04210000-0000-4000-8000-0000000000c1',
      '04210000-0000-4000-8000-0000000000f1',
      timestamptz '2026-12-02 11:00:00+00',
      timestamptz '2026-12-02 12:00:00+00'
    );
    raise exception 'suspended person requested a slot';
  exception
    when insufficient_privilege then
      if sqlerrm is distinct from 'Bookable request is not available' then
        raise;
      end if;
  end;

  begin
    perform public.get_my_booking_request(
      '04220000-0000-4000-8000-0000000000c5'
    );
    raise exception 'suspended person reconciled a request';
  exception
    when insufficient_privilege then
      if sqlerrm is distinct from 'Bookable request is not available' then
        raise;
      end if;
  end;

  begin
    perform public.list_bookings_i_can_confirm();
    raise exception 'suspended person listed the confirm queue';
  exception
    when insufficient_privilege then
      if sqlerrm is distinct from 'Bookable request is not available' then
        raise;
      end if;
  end;
end;
$$;

reset role;

update public.persons
   set status = 'ACTIVE'
 where id = (
   select person_id
     from public.user_accounts
    where auth_user_id = '04220000-0000-4000-8000-0000000000a1'
 );

update public.user_accounts
   set status = 'SUSPENDED'
 where auth_user_id = '04220000-0000-4000-8000-0000000000a2';

set local role authenticated;
select set_config('request.jwt.claim.sub', '04220000-0000-4000-8000-0000000000a2', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"04220000-0000-4000-8000-0000000000a2","role":"authenticated"}',
  true
);

do $$
begin
  begin
    perform public.list_bookings_i_can_confirm();
    raise exception 'suspended staff listed the confirm queue';
  exception
    when insufficient_privilege then
      if sqlerrm is distinct from 'Bookable request is not available' then
        raise;
      end if;
  end;
end;
$$;

reset role;

update public.persons
   set status = 'SUSPENDED'
 where id = (
   select person_id
     from public.user_accounts
    where auth_user_id = '04220000-0000-4000-8000-0000000000a2'
 );

update public.user_accounts
   set status = 'ACTIVE'
 where auth_user_id = '04220000-0000-4000-8000-0000000000a2';

set local role authenticated;
select set_config('request.jwt.claim.sub', '04220000-0000-4000-8000-0000000000a2', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"04220000-0000-4000-8000-0000000000a2","role":"authenticated"}',
  true
);

do $$
begin
  begin
    perform public.list_bookings_i_can_confirm();
    raise exception 'suspended staff person listed the confirm queue';
  exception
    when insufficient_privilege then
      if sqlerrm is distinct from 'Bookable request is not available' then
        raise;
      end if;
  end;
end;
$$;

reset role;

rollback;
