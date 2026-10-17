-- Rider-visible bookable offers and an idempotent request wrapper.
--
-- Does not add payments, opening hours, exterior handover windows, a
-- welfare hour constant, recurrence expansion, or Storage evidence.
-- Reuses equine_availability_rules, equine_calendar_blocks,
-- center_services, service_equines, equine_center_assignments,
-- create_booking_request, confirm_booking, and list_my_activity.
--
-- The stored ACTIVE availability window is the released time. This
-- migration does not add a second owner-release layer. A center
-- restriction is an ACTIVE calendar block or a shorter stored window:
-- the read never extends a window. Recurrence text stays unexpanded.
-- default_duration_minutes, when set, is the only slot length. When it
-- is null, the whole stored window is the offer and is not sliced.
-- duration_limit_minutes, when set, rejects a longer offer. A null
-- limit is not replaced with a number.
--
-- PUBLIC visibility is required together with an ACTIVE center
-- assignment and an enabled ACTIVE service link. PUBLIC alone is not a
-- directory. PRIVATE equines are absent. The read does not return
-- owners, blocks, policies, or media.
--
-- Tables stay revoked from anon and authenticated. RPCs resolve the
-- caller from auth.uid().

create table public.booking_request_keys (
  account_id uuid not null references public.user_accounts (id),
  client_request_id uuid not null,
  equine_id uuid not null,
  center_id uuid not null,
  service_id uuid not null,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  booking_id uuid references public.bookings (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (account_id, client_request_id),
  constraint booking_request_keys_range_check
    check (ends_at > starts_at)
);

comment on table public.booking_request_keys is
  'Idempotency key for request_bookable_slot. One key belongs to the caller account. A committed booking_id is replayed. A null booking_id is an ambiguous outcome and must not create another booking.';

alter table public.booking_request_keys enable row level security;
revoke all on table public.booking_request_keys from anon, authenticated;

create function public.assert_bookable_reader()
returns uuid
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  current_auth_user_id uuid := auth.uid();
  caller_account uuid;
begin
  if current_auth_user_id is null then
    raise exception using
      errcode = '42501',
      message = 'Authentication required';
  end if;

  select account.id
    into caller_account
    from public.user_accounts as account
   where account.auth_user_id = current_auth_user_id;

  if caller_account is null then
    raise exception using
      errcode = 'P0001',
      message = 'Identity could not be resolved';
  end if;

  return caller_account;
end;
$$;

comment on function public.assert_bookable_reader() is
  'Server-internal caller account resolved from auth.uid(). Not executable by PUBLIC, anon, authenticated or service_role.';

revoke all on function public.assert_bookable_reader()
  from public, anon, authenticated, service_role;

create function public.list_bookable_offers(
  p_range_start timestamptz,
  p_range_end timestamptz
)
returns table (
  center_id uuid,
  center_name text,
  center_timezone text,
  equine_id uuid,
  equine_name text,
  service_id uuid,
  service_name text,
  service_type text,
  starts_at timestamptz,
  ends_at timestamptz,
  default_duration_minutes integer,
  duration_limit_minutes integer
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
begin
  perform public.assert_bookable_reader();

  if p_range_start is null or p_range_end is null or p_range_end <= p_range_start then
    raise exception using
      errcode = '22023',
      message = 'A bookable query range must end after it starts';
  end if;

  if p_range_end > p_range_start + interval '14 days' then
    raise exception using
      errcode = '22023',
      message = 'Bookable query range cannot exceed 14 days';
  end if;

  return query
  select
    center.id,
    center.name,
    center.timezone,
    equine.id,
    equine.name,
    service.id,
    service.name,
    service.service_type,
    slot.slot_start,
    slot.slot_end,
    service.default_duration_minutes,
    link.duration_limit_minutes
  from public.equine_availability_rules as rule
  join public.equines as equine
    on equine.id = rule.equine_id
  join public.equestrian_centers as center
    on center.id = rule.center_id
  join public.center_services as service
    on service.center_id = rule.center_id
  join public.service_equines as link
    on link.service_id = service.id
   and link.equine_id = equine.id
  join lateral (
    select
      series.slot_start,
      series.slot_start
        + make_interval(mins => service.default_duration_minutes) as slot_end
    from generate_series(
      rule.starts_at,
      rule.ends_at - make_interval(mins => service.default_duration_minutes),
      make_interval(mins => service.default_duration_minutes)
    ) as series (slot_start)
    where service.default_duration_minutes is not null
      and (
        link.duration_limit_minutes is null
        or service.default_duration_minutes <= link.duration_limit_minutes
      )
    union all
    select rule.starts_at, rule.ends_at
    where service.default_duration_minutes is null
      and (
        link.duration_limit_minutes is null
        or (
          extract(epoch from (rule.ends_at - rule.starts_at)) / 60.0
        ) <= link.duration_limit_minutes
      )
  ) as slot on true
  where rule.status = 'ACTIVE'
    and rule.recurrence_rule is null
    and equine.status = 'ACTIVE'
    and equine.visibility_status = 'PUBLIC'
    and center.status = 'ACTIVE'
    and service.status = 'ACTIVE'
    and link.status = 'ACTIVE'
    and link.enabled is true
    and exists (
      select 1
        from public.equine_center_assignments as assignment
       where assignment.equine_id = equine.id
         and assignment.center_id = center.id
         and assignment.status = 'ACTIVE'
         and assignment.ended_at is null
         and assignment.started_at <= now()
    )
    and slot.slot_end > slot.slot_start
    and slot.slot_end <= rule.ends_at
    and slot.slot_start >= p_range_start
    and slot.slot_end <= p_range_end
    and slot.slot_start >= now()
    and not public.has_active_equine_calendar_overlap(
      equine.id,
      slot.slot_start,
      slot.slot_end
    )
  order by slot.slot_start, center.id, equine.id, service.id;
end;
$$;

comment on function public.list_bookable_offers(timestamptz, timestamptz) is
  'Authenticated derived bookable slots. Stored ACTIVE windows only; recurrence is not expanded. default_duration_minutes slices the window when set. A null duration returns the whole window and does not invent a shorter slot. A null duration_limit_minutes is not replaced. PRIVATE equines, inactive assignments, and ACTIVE occupancy are absent. The 14-day argument is a read bound, not a welfare limit. No opening-hour or payment column is read.';

revoke all on function public.list_bookable_offers(timestamptz, timestamptz)
  from public, anon, authenticated, service_role;
grant execute on function public.list_bookable_offers(timestamptz, timestamptz)
  to authenticated;

create function public.get_bookable_offer(
  p_equine_id uuid,
  p_center_id uuid,
  p_service_id uuid,
  p_starts_at timestamptz,
  p_ends_at timestamptz
)
returns table (
  center_id uuid,
  center_name text,
  center_timezone text,
  equine_id uuid,
  equine_name text,
  service_id uuid,
  service_name text,
  service_type text,
  starts_at timestamptz,
  ends_at timestamptz,
  default_duration_minutes integer,
  duration_limit_minutes integer
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
begin
  perform public.assert_bookable_reader();

  if p_equine_id is null
     or p_center_id is null
     or p_service_id is null
     or p_starts_at is null
     or p_ends_at is null then
    raise exception using
      errcode = '22023',
      message = 'Equine, Center, service and slot are required';
  end if;

  return query
  select
    offer.center_id,
    offer.center_name,
    offer.center_timezone,
    offer.equine_id,
    offer.equine_name,
    offer.service_id,
    offer.service_name,
    offer.service_type,
    offer.starts_at,
    offer.ends_at,
    offer.default_duration_minutes,
    offer.duration_limit_minutes
  from public.list_bookable_offers(p_starts_at, p_ends_at) as offer
  where offer.equine_id = p_equine_id
    and offer.center_id = p_center_id
    and offer.service_id = p_service_id
    and offer.starts_at = p_starts_at
    and offer.ends_at = p_ends_at;
end;
$$;

comment on function public.get_bookable_offer(uuid, uuid, uuid, timestamptz, timestamptz) is
  'Authenticated exact bookable slot. An unknown or out-of-scope UUID returns no row. Does not accept a caller-supplied person id.';

revoke all on function public.get_bookable_offer(uuid, uuid, uuid, timestamptz, timestamptz)
  from public, anon, authenticated, service_role;
grant execute on function public.get_bookable_offer(uuid, uuid, uuid, timestamptz, timestamptz)
  to authenticated;

create function public.request_bookable_slot(
  p_client_request_id uuid,
  p_equine_id uuid,
  p_center_id uuid,
  p_service_id uuid,
  p_starts_at timestamptz,
  p_ends_at timestamptz
)
returns table (
  booking_id uuid,
  booking_status text,
  outcome text
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  current_auth_user_id uuid := auth.uid();
  caller_account uuid;
  caller_person uuid;
  key_row public.booking_request_keys%rowtype;
  existing_booking uuid;
  created_booking uuid;
  created_status text;
  inserted_key uuid;
begin
  if current_auth_user_id is null then
    raise exception using
      errcode = '42501',
      message = 'Authentication required';
  end if;

  if p_client_request_id is null
     or p_equine_id is null
     or p_center_id is null
     or p_service_id is null
     or p_starts_at is null
     or p_ends_at is null
     or p_ends_at <= p_starts_at then
    raise exception using
      errcode = '22023',
      message = 'Request key, equine, Center, service and slot are required';
  end if;

  select account.id, account.person_id
    into caller_account, caller_person
    from public.user_accounts as account
   where account.auth_user_id = current_auth_user_id;

  if caller_person is null or caller_account is null then
    raise exception using
      errcode = 'P0001',
      message = 'Identity could not be resolved';
  end if;

  insert into public.booking_request_keys (
    account_id,
    client_request_id,
    equine_id,
    center_id,
    service_id,
    starts_at,
    ends_at
  ) values (
    caller_account,
    p_client_request_id,
    p_equine_id,
    p_center_id,
    p_service_id,
    p_starts_at,
    p_ends_at
  )
  on conflict (account_id, client_request_id) do nothing
  returning client_request_id into inserted_key;

  select key.*
    into key_row
    from public.booking_request_keys as key
   where key.account_id = caller_account
     and key.client_request_id = p_client_request_id
   for update;

  if key_row.equine_id is distinct from p_equine_id
     or key_row.center_id is distinct from p_center_id
     or key_row.service_id is distinct from p_service_id
     or key_row.starts_at is distinct from p_starts_at
     or key_row.ends_at is distinct from p_ends_at then
    raise exception using
      errcode = '22023',
      message = 'client_request_id already used';
  end if;

  if key_row.booking_id is not null then
    select booking.status
      into created_status
      from public.bookings as booking
     where booking.id = key_row.booking_id;

    booking_id := key_row.booking_id;
    booking_status := created_status;
    outcome := 'REPLAYED';
    return next;
    return;
  end if;

  if key_row.booking_id is null and inserted_key is null then
    raise exception using
      errcode = 'P0001',
      message = 'Booking request outcome is ambiguous';
  end if;

  if not exists (
    select 1
      from public.get_bookable_offer(
        p_equine_id,
        p_center_id,
        p_service_id,
        p_starts_at,
        p_ends_at
      ) as offer
  ) then
    raise exception using
      errcode = '42501',
      message = 'Bookable offer is not available';
  end if;

  select booking.id
    into existing_booking
    from public.bookings as booking
   where booking.booked_by_account_id = caller_account
     and booking.equine_id = p_equine_id
     and booking.center_id = p_center_id
     and booking.service_id = p_service_id
     and booking.starts_at = p_starts_at
     and booking.ends_at = p_ends_at
     and booking.status not in ('REJECTED', 'CANCELLED', 'EXPIRED', 'COMPLETED')
   for update;

  if existing_booking is not null then
    update public.booking_request_keys as key
       set booking_id = existing_booking
     where key.account_id = caller_account
       and key.client_request_id = p_client_request_id;

    select booking.status
      into created_status
      from public.bookings as booking
     where booking.id = existing_booking;

    booking_id := existing_booking;
    booking_status := created_status;
    outcome := 'REPLAYED';
    return next;
    return;
  end if;

  begin
    created_booking := public.create_booking_request(
      caller_person,
      p_equine_id,
      p_center_id,
      p_service_id,
      p_starts_at,
      p_ends_at
    );
  exception
    when unique_violation then
      select booking.id
        into existing_booking
        from public.bookings as booking
       where booking.booked_by_account_id = caller_account
         and booking.equine_id = p_equine_id
         and booking.center_id = p_center_id
         and booking.service_id = p_service_id
         and booking.starts_at = p_starts_at
         and booking.ends_at = p_ends_at
         and booking.status not in ('REJECTED', 'CANCELLED', 'EXPIRED', 'COMPLETED')
       for update;

      if existing_booking is null then
        raise;
      end if;

      update public.booking_request_keys as key
         set booking_id = existing_booking
       where key.account_id = caller_account
         and key.client_request_id = p_client_request_id;

      select booking.status
        into created_status
        from public.bookings as booking
       where booking.id = existing_booking;

      booking_id := existing_booking;
      booking_status := created_status;
      outcome := 'REPLAYED';
      return next;
      return;
  end;

  update public.booking_request_keys as key
     set booking_id = created_booking
   where key.account_id = caller_account
     and key.client_request_id = p_client_request_id;

  select booking.status
    into created_status
    from public.bookings as booking
   where booking.id = created_booking;

  booking_id := created_booking;
  booking_status := created_status;
  outcome := 'CREATED';
  return next;
end;
$$;

comment on function public.request_bookable_slot(uuid, uuid, uuid, uuid, timestamptz, timestamptz) is
  'Authenticated request for the caller PERSON. Re-checks the derived slot, then calls create_booking_request. Never confirms and never writes a payment status. The same client_request_id replays the committed booking. A key with no booking is ambiguous and does not insert another row. There is no no-payment-required status in the schema.';

revoke all on function public.request_bookable_slot(uuid, uuid, uuid, uuid, timestamptz, timestamptz)
  from public, anon, authenticated, service_role;
grant execute on function public.request_bookable_slot(uuid, uuid, uuid, uuid, timestamptz, timestamptz)
  to authenticated;

create function public.get_my_booking_request(
  p_client_request_id uuid
)
returns table (
  booking_id uuid,
  booking_status text,
  starts_at timestamptz,
  ends_at timestamptz,
  outcome text
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  caller_account uuid;
begin
  caller_account := public.assert_bookable_reader();

  if p_client_request_id is null then
    raise exception using
      errcode = '22023',
      message = 'Request key is required';
  end if;

  return query
  select
    key.booking_id,
    booking.status,
    key.starts_at,
    key.ends_at,
    case
      when key.booking_id is null then 'AMBIGUOUS'
      else 'COMMITTED'
    end
  from public.booking_request_keys as key
  left join public.bookings as booking
    on booking.id = key.booking_id
  where key.account_id = caller_account
    and key.client_request_id = p_client_request_id;
end;
$$;

comment on function public.get_my_booking_request(uuid) is
  'Authenticated read of the caller account request key. Empty means the key was not committed. AMBIGUOUS means the key exists without a booking. Does not insert.';

revoke all on function public.get_my_booking_request(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.get_my_booking_request(uuid)
  to authenticated;

create function public.list_bookings_i_can_confirm()
returns table (
  booking_id uuid,
  equine_name text,
  center_name text,
  service_name text,
  starts_at timestamptz,
  ends_at timestamptz,
  booking_status text
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  current_auth_user_id uuid := auth.uid();
  caller_person uuid;
begin
  if current_auth_user_id is null then
    raise exception using
      errcode = '42501',
      message = 'Authentication required';
  end if;

  select account.person_id
    into caller_person
    from public.user_accounts as account
   where account.auth_user_id = current_auth_user_id;

  if caller_person is null then
    raise exception using
      errcode = 'P0001',
      message = 'Identity could not be resolved';
  end if;

  return query
  select
    booking.id,
    equine.name,
    center.name,
    service.name,
    booking.starts_at,
    booking.ends_at,
    booking.status
  from public.bookings as booking
  join public.equines as equine
    on equine.id = booking.equine_id
  join public.equestrian_centers as center
    on center.id = booking.center_id
  join public.center_services as service
    on service.id = booking.service_id
  where booking.status = 'APPROVED'
    and public.caller_has_booking_manage_authority(
      caller_person,
      booking.equine_id,
      booking.center_id
    )
  order by booking.starts_at, booking.id;
end;
$$;

comment on function public.list_bookings_i_can_confirm() is
  'Authenticated APPROVED bookings the caller can confirm with existing MANAGE_BOOKINGS authority. Does not return the participant. Does not confirm.';

revoke all on function public.list_bookings_i_can_confirm()
  from public, anon, authenticated, service_role;
grant execute on function public.list_bookings_i_can_confirm()
  to authenticated;

create function public.vertical_fixture_guard()
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if current_user is distinct from 'postgres' then
    raise exception using
      errcode = '42501',
      message = 'Vertical fixture requires the local postgres role';
  end if;

  if current_setting('app.vertical_fixture_local', true) is distinct from '1' then
    raise exception using
      errcode = '42501',
      message = 'Vertical fixture is local-only';
  end if;
end;
$$;

comment on function public.vertical_fixture_guard() is
  'Local fixture gate. Requires postgres and app.vertical_fixture_local=1. Not executable by clients.';

revoke all on function public.vertical_fixture_guard()
  from public, anon, authenticated, service_role;

create function public.vertical_fixture_install(
  p_rider_auth_user_id uuid,
  p_staff_auth_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  fixture_center uuid := '04210000-0000-4000-8000-0000000000c1';
  fixture_equine uuid := '04210000-0000-4000-8000-0000000000e1';
  fixture_private uuid := '04210000-0000-4000-8000-0000000000e2';
  fixture_service uuid := '04210000-0000-4000-8000-0000000000f1';
  rider_person uuid;
  rider_account uuid;
  staff_person uuid;
  staff_account uuid;
begin
  perform public.vertical_fixture_guard();

  if p_rider_auth_user_id is null
     or p_staff_auth_user_id is null
     or p_rider_auth_user_id = p_staff_auth_user_id then
    raise exception using
      errcode = '22023',
      message = 'Vertical fixture needs two distinct existing auth users';
  end if;

  select account.person_id, account.id
    into rider_person, rider_account
    from public.user_accounts as account
   where account.auth_user_id = p_rider_auth_user_id;

  select account.person_id, account.id
    into staff_person, staff_account
    from public.user_accounts as account
   where account.auth_user_id = p_staff_auth_user_id;

  if rider_person is null or staff_person is null then
    raise exception using
      errcode = 'P0002',
      message = 'Vertical fixture does not create auth users';
  end if;

  if exists (
    select 1
      from public.equestrian_centers as center
     where center.id = fixture_center
  ) then
    if not exists (
      select 1
        from public.equestrian_centers as center
       where center.id = fixture_center
         and center.name = 'TEST_ONLY Vertical Center'
    ) then
      raise exception using
        errcode = '42501',
        message = 'Vertical fixture id is already used outside the fixture';
    end if;

    update public.equine_center_assignments as assignment
       set status = 'ACTIVE',
           ended_at = null
     where assignment.id in (
       '04210000-0000-4000-8000-0000000000a1',
       '04210000-0000-4000-8000-0000000000a2'
     )
       and assignment.status = 'ENDED';

    update public.center_memberships as membership
       set status = 'ACTIVE',
           ended_at = null
     where membership.id = '04210000-0000-4000-8000-0000000000f7'
       and membership.status = 'ENDED';

    update public.equine_availability_rules as rule
       set status = 'ACTIVE'
     where rule.id in (
       '04210000-0000-4000-8000-0000000000f4',
       '04210000-0000-4000-8000-0000000000f5'
     )
       and rule.status = 'INACTIVE';
    return;
  end if;

  insert into public.markets (country_code, status)
  values ('VT', 'ACTIVE')
  on conflict (country_code) do nothing;

  insert into public.market_age_rules (
    country_code,
    legal_adult_age,
    guardian_consent_required,
    effective_from
  )
  select 'VT', 18, true, date '2000-01-01'
  where not exists (
    select 1
      from public.market_age_rules as rule
     where rule.country_code = 'VT'
  );

  insert into public.equestrian_centers (
    id, name, slug, country_code, timezone, status
  ) values (
    fixture_center,
    'TEST_ONLY Vertical Center',
    'test-only-vertical-center',
    'VT',
    'Europe/Madrid',
    'ACTIVE'
  );

  insert into public.equines (
    id, name, equine_type, status, visibility_status
  ) values
    (fixture_equine, 'TEST_ONLY Equine', 'HORSE', 'ACTIVE', 'PUBLIC'),
    (fixture_private, 'TEST_ONLY Private Equine', 'HORSE', 'ACTIVE', 'PRIVATE');

  insert into public.center_memberships (
    id, center_id, person_id, role_code
  ) values (
    '04210000-0000-4000-8000-0000000000f7',
    fixture_center,
    staff_person,
    'MANAGER'
  );

  insert into public.equine_center_assignments (
    id, equine_id, center_id, assignment_type
  ) values
    (
      '04210000-0000-4000-8000-0000000000a1',
      fixture_equine,
      fixture_center,
      'SCHOOL'
    ),
    (
      '04210000-0000-4000-8000-0000000000a2',
      fixture_private,
      fixture_center,
      'SCHOOL'
    );

  insert into public.equine_ownerships (
    id, equine_id, owner_type, owner_person_id, ownership_percentage
  ) values (
    '04210000-0000-4000-8000-0000000000b1',
    fixture_equine,
    'PERSON',
    staff_person,
    100
  );

  insert into public.equine_center_permissions (
    id, equine_id, center_id, granted_by_person_id, permission_code
  ) values
    (
      '04210000-0000-4000-8000-0000000000d1',
      fixture_equine,
      fixture_center,
      staff_person,
      'MANAGE_AVAILABILITY'
    ),
    (
      '04210000-0000-4000-8000-0000000000d2',
      fixture_equine,
      fixture_center,
      staff_person,
      'MANAGE_BOOKINGS'
    ),
    (
      '04210000-0000-4000-8000-0000000000d3',
      fixture_equine,
      fixture_center,
      staff_person,
      'MANAGE_REQUIREMENTS'
    ),
    (
      '04210000-0000-4000-8000-0000000000d4',
      fixture_private,
      fixture_center,
      staff_person,
      'MANAGE_AVAILABILITY'
    ),
    (
      '04210000-0000-4000-8000-0000000000d5',
      fixture_private,
      fixture_center,
      staff_person,
      'MANAGE_REQUIREMENTS'
    );

  insert into public.center_services (
    id, center_id, service_type, name, default_duration_minutes, status
  ) values (
    fixture_service,
    fixture_center,
    'EQUINE_SESSION',
    'TEST_ONLY Session',
    60,
    'ACTIVE'
  );

  insert into public.service_equines (
    id, service_id, equine_id, enabled, status
  ) values
    (
      '04210000-0000-4000-8000-0000000000f2',
      fixture_service,
      fixture_equine,
      true,
      'ACTIVE'
    ),
    (
      '04210000-0000-4000-8000-0000000000f3',
      fixture_service,
      fixture_private,
      true,
      'ACTIVE'
    );

  insert into public.equine_availability_rules (
    id, equine_id, center_id, starts_at, ends_at, created_by_account_id
  ) values
    (
      '04210000-0000-4000-8000-0000000000f4',
      fixture_equine,
      fixture_center,
      timestamptz '2026-12-02 09:00:00+00',
      timestamptz '2026-12-02 12:00:00+00',
      staff_account
    ),
    (
      '04210000-0000-4000-8000-0000000000f5',
      fixture_private,
      fixture_center,
      timestamptz '2026-12-02 09:00:00+00',
      timestamptz '2026-12-02 12:00:00+00',
      staff_account
    );

  perform rider_account;
end;
$$;

comment on function public.vertical_fixture_install(uuid, uuid) is
  'Local idempotent TEST_ONLY center, public equine, private equine, service and stored window. Does not create auth users. Does not run unless app.vertical_fixture_local=1. Not granted to clients.';

revoke all on function public.vertical_fixture_install(uuid, uuid)
  from public, anon, authenticated, service_role;

create function public.vertical_fixture_retire()
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  fixture_center uuid := '04210000-0000-4000-8000-0000000000c1';
  fixture_equine uuid := '04210000-0000-4000-8000-0000000000e1';
  fixture_private uuid := '04210000-0000-4000-8000-0000000000e2';
  fixture_ids uuid[] := array[
    fixture_center,
    fixture_equine,
    fixture_private
  ];
begin
  perform public.vertical_fixture_guard();

  if not exists (
    select 1
      from public.equestrian_centers as center
     where center.id = fixture_center
  ) then
    return;
  end if;

  if not exists (
    select 1
      from public.equestrian_centers as center
     where center.id = fixture_center
       and center.name = 'TEST_ONLY Vertical Center'
  ) or not exists (
    select 1
      from public.equines as equine
     where equine.id = fixture_equine
       and equine.name = 'TEST_ONLY Equine'
  ) then
    raise exception using
      errcode = '42501',
      message = 'Vertical fixture retire refused an unmarked row';
  end if;

  update public.equine_availability_rules as rule
     set status = 'INACTIVE'
   where rule.equine_id in (fixture_equine, fixture_private)
     and rule.center_id = fixture_center
     and rule.status = 'ACTIVE';

  update public.equine_calendar_blocks as block
     set status = 'CANCELLED',
         cancelled_at = coalesce(block.cancelled_at, now())
   where block.equine_id in (fixture_equine, fixture_private)
     and block.center_id = fixture_center
     and block.status = 'ACTIVE';

  delete from public.booking_requirements as requirement
   where requirement.booking_id in (
     select booking.id
       from public.bookings as booking
      where booking.equine_id in (fixture_equine, fixture_private)
        and booking.center_id = fixture_center
        and booking.status in (
          'DRAFT',
          'REQUESTED',
          'PENDING_REQUIREMENTS',
          'PENDING_APPROVAL',
          'APPROVED',
          'REJECTED',
          'EXPIRED',
          'DISPUTED'
        )
   );

  delete from public.bookings as booking
   where booking.equine_id in (fixture_equine, fixture_private)
     and booking.center_id = fixture_center
     and booking.status in (
       'DRAFT',
       'REQUESTED',
       'PENDING_REQUIREMENTS',
       'PENDING_APPROVAL',
       'APPROVED',
       'REJECTED',
       'EXPIRED',
       'DISPUTED'
     );

  update public.bookings as booking
     set status = 'CANCELLED',
         cancelled_at = coalesce(booking.cancelled_at, now())
   where booking.equine_id in (fixture_equine, fixture_private)
     and booking.center_id = fixture_center
     and booking.status in ('CONFIRMED', 'ACTIVE');

  delete from public.booking_request_keys as key
   where key.equine_id in (fixture_equine, fixture_private)
     and key.center_id = fixture_center
     and key.booking_id is null;

  perform fixture_ids;
end;
$$;

comment on function public.vertical_fixture_retire() is
  'Local cleanup of TEST_ONLY vertical fixture effects. Deactivates the fixture windows and cancels fixture occupancy. Deletes only open fixture requests. Does not delete audit_events, auth.users, persons, the fixture center, or confirmed history. Availability rules cannot be deleted, so the marked rows stay inactive until install reactivates those ids. Not granted to clients.';

revoke all on function public.vertical_fixture_retire()
  from public, anon, authenticated, service_role;
