-- Local test-operator gate. One transaction, then ROLLBACK.
-- Does not call the hosted project and does not keep rows.

begin;

create function pg_temp.operator_jwt(p_auth uuid)
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

insert into public.markets (country_code, status)
values ('QZ', 'ACTIVE')
on conflict (country_code) do nothing;

insert into public.market_age_rules (
  country_code, legal_adult_age, guardian_consent_required, effective_from
)
select 'QZ', 18, true, date '2000-01-01'
where not exists (
  select 1 from public.market_age_rules as rule where rule.country_code = 'QZ'
);

insert into auth.users (id) values
  ('04410000-0000-4000-8000-000000000001'),
  ('04410000-0000-4000-8000-000000000002');

update auth.users
   set email = 'owner@test-only.example'
 where id = '04410000-0000-4000-8000-000000000001';

update auth.users
   set email = 'rider@test-only.example'
 where id = '04410000-0000-4000-8000-000000000002';

update public.persons as person
   set first_name = 'TEST_ONLY',
       last_name = 'Owner',
       date_of_birth = date '1990-01-01',
       country_code = 'QZ'
  from public.user_accounts as account
 where account.auth_user_id = '04410000-0000-4000-8000-000000000001'
   and person.id = account.person_id;

update public.persons as person
   set first_name = 'TEST_ONLY',
       last_name = 'Rider',
       date_of_birth = date '1992-02-02',
       country_code = 'QZ'
  from public.user_accounts as account
 where account.auth_user_id = '04410000-0000-4000-8000-000000000002'
   and person.id = account.person_id;

do $$
#variable_conflict use_variable
declare
  center_id uuid;
  equine_id uuid;
  service_id uuid;
  pilot_id uuid;
  foreign_center_id uuid;
  foreign_status text;
  owner_account uuid;
  slot_start timestamptz;
  slot_end timestamptz;
  booking_id uuid;
  booking_status text;
  request_outcome text;
  session_id uuid;
  result_count integer;
  offer_count integer;
  audit_count integer;
  closed_status text;
begin
  perform pg_temp.operator_jwt('04410000-0000-4000-8000-000000000001');
  update public.test_operator_gate set enabled = false where singleton;

  begin
    perform public.create_test_center('TEST_ONLY Centro', 'Europe/Madrid');
    raise exception 'gate should refuse';
  exception
    when sqlstate '42501' then
      null;
  end;

  update public.test_operator_gate set enabled = true where singleton;

  begin
    perform public.create_test_center('Centro real', 'Europe/Madrid');
    raise exception 'name should refuse';
  exception
    when sqlstate '22023' then
      null;
  end;

  center_id := public.create_test_center('TEST_ONLY Centro', 'Europe/Madrid');
  equine_id := public.create_my_equine('TEST_ONLY Caballo', 'HORSE');
  perform public.register_test_equine(equine_id);

  perform pg_temp.operator_jwt('04410000-0000-4000-8000-000000000002');
  begin
    perform public.register_test_equine(equine_id);
    raise exception 'stranger should refuse';
  exception
    when sqlstate '42501' then
      null;
  end;
  begin
    perform public.assign_test_center_role(
      center_id, 'owner@test-only.example', 'MANAGER'
    );
    raise exception 'stranger should refuse role';
  exception
    when sqlstate '42501' then
      null;
  end;
  begin
    perform public.grant_test_equine_permission(
      equine_id, center_id, 'MANAGE_BOOKINGS'
    );
    raise exception 'stranger should refuse permission';
  exception
    when sqlstate '42501' then
      null;
  end;

  perform pg_temp.operator_jwt('04410000-0000-4000-8000-000000000001');
  perform public.assign_test_center_role(
    center_id, 'rider@test-only.example', 'MANAGER'
  );
  perform public.assign_test_equine_to_center(equine_id, center_id, 'SCHOOL');
  perform public.grant_test_equine_permission(
    equine_id, center_id, 'MANAGE_AVAILABILITY'
  );
  perform public.grant_test_equine_permission(
    equine_id, center_id, 'MANAGE_BOOKINGS'
  );
  perform public.grant_test_equine_permission(
    equine_id, center_id, 'MANAGE_REQUIREMENTS'
  );
  perform public.grant_test_equine_permission(
    equine_id, center_id, 'VIEW_ACTIVITY'
  );
  service_id := public.create_test_service(center_id, 'TEST_ONLY Sesion', 60);
  perform public.link_test_service_equine(service_id, equine_id);
  perform public.set_test_availability(
    equine_id,
    center_id,
    now() + interval '2 hours',
    now() + interval '4 hours'
  );
  perform public.mark_test_equine_visibility(equine_id, 'PUBLIC');
  pilot_id := public.open_test_bookable_pilot('TEST_ONLY_FLOW', center_id, equine_id);
  perform public.add_test_calendar_block(
    equine_id,
    center_id,
    now() + interval '30 minutes',
    now() + interval '90 minutes',
    'REST'
  );

  perform pg_temp.operator_jwt('04410000-0000-4000-8000-000000000002');
  select count(*)
    into offer_count
    from public.list_bookable_offers(now(), now() + interval '1 day') as offer
   where offer.equine_id = equine_id;

  if offer_count < 1 then
    raise exception 'expected a derived TEST_ONLY slot';
  end if;

  select offer.starts_at, offer.ends_at
    into slot_start, slot_end
    from public.list_bookable_offers(now(), now() + interval '1 day') as offer
   where offer.equine_id = equine_id
     and offer.service_id = service_id
   order by offer.starts_at
   limit 1;

  if slot_start is null or slot_end is null then
    raise exception 'the screen offer had no slot to request';
  end if;

  select result.booking_id, result.booking_status, result.outcome
    into booking_id, booking_status, request_outcome
    from public.request_bookable_slot(
      '04410000-0000-4000-8000-000000000099',
      equine_id,
      center_id,
      service_id,
      slot_start,
      slot_end
    ) as result;

  if request_outcome is distinct from 'CREATED'
     or booking_status is distinct from 'APPROVED' then
    raise exception 'request outcome % status %', request_outcome, booking_status;
  end if;

  perform pg_temp.operator_jwt('04410000-0000-4000-8000-000000000001');
  perform public.confirm_booking(booking_id);

  perform pg_temp.operator_jwt('04410000-0000-4000-8000-000000000002');
  session_id := public.start_session(booking_id);
  perform public.end_session(session_id);

  perform pg_temp.operator_jwt('04410000-0000-4000-8000-000000000001');
  select count(*)
    into result_count
    from public.list_authorized_activity_results() as result
   where result.booking_id = booking_id
     and result.session_status = 'COMPLETED'
     and result.caller_relation = 'VIEW_ACTIVITY';

  if result_count <> 1 then
    raise exception 'authorized result missing for the center admin';
  end if;

  perform pg_temp.operator_jwt('04410000-0000-4000-8000-000000000002');
  foreign_center_id := public.create_test_center('TEST_ONLY Ajeno', 'Europe/Madrid');

  perform pg_temp.operator_jwt('04410000-0000-4000-8000-000000000001');
  perform public.retire_test_operator_data();

  select center.status
    into foreign_status
    from public.equestrian_centers as center
   where center.id = foreign_center_id;

  if foreign_status is distinct from 'ACTIVE' then
    raise exception 'retire must leave another account center untouched';
  end if;

  select account.id
    into owner_account
    from public.user_accounts as account
   where account.auth_user_id = '04410000-0000-4000-8000-000000000001';

  select count(*)
    into audit_count
    from public.audit_events as event
   where event.event_type = 'TEST_OPERATOR_RETIRED'
     and event.actor_account_id = owner_account;

  if audit_count < 1 then
    raise exception 'retire must keep an audit row';
  end if;

  select pilot.status
    into closed_status
    from public.bookable_pilots as pilot
   where pilot.id = pilot_id;

  if closed_status is distinct from 'CLOSED' then
    raise exception 'TEST_ONLY pilot must close';
  end if;

  perform pg_temp.operator_jwt('04410000-0000-4000-8000-000000000002');
  select count(*)
    into offer_count
    from public.list_bookable_offers(now(), now() + interval '1 day') as offer
   where offer.equine_id = equine_id;

  if offer_count <> 0 then
    raise exception 'retired pair must leave explore empty';
  end if;
end;
$$;

set local role authenticated;

do $$
begin
  perform count(*) from public.test_operator_records;
  raise exception 'registry must not be readable';
exception
  when insufficient_privilege then
    null;
end;
$$;

reset role;

rollback;
