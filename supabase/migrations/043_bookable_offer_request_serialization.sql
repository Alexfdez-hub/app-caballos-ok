-- Serialize concurrent request_bookable_slot keys for one account and slot.
--
-- Replaces only request_bookable_slot. Signature, SECURITY DEFINER,
-- search_path, identity and pilot checks, revokes, grants, and the
-- function comment stay as migration 042 left them. The advisory lock
-- key uses UTC calendar text of the two instants, so session TimeZone
-- cannot split one slot into two locks. No table, policy, or grant
-- outside this function changes.

create or replace function public.request_bookable_slot(
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
  caller_account uuid;
  caller_person uuid;
  key_row public.booking_request_keys%rowtype;
  existing_booking uuid;
  created_booking uuid;
  created_status text;
  inserted_key uuid;
begin
  select reader.account_id, reader.person_id
    into caller_account, caller_person
    from public.assert_bookable_reader() as reader;

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

  if not public.equine_center_is_in_open_bookable_pilot(
    key_row.center_id,
    key_row.equine_id
  ) then
    raise exception using
      errcode = '42501',
      message = 'Bookable offer is not available';
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

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      caller_account::text
      || '|'
      || p_equine_id::text
      || '|'
      || p_center_id::text
      || '|'
      || p_service_id::text
      || '|'
      || pg_catalog.to_char(p_starts_at at time zone 'UTC', 'YYYYMMDDHH24MISSUS')
      || '|'
      || pg_catalog.to_char(p_ends_at at time zone 'UTC', 'YYYYMMDDHH24MISSUS'),
      42
    )
  );

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
    if not public.equine_center_is_in_open_bookable_pilot(
      key_row.center_id,
      key_row.equine_id
    ) then
      raise exception using
        errcode = '42501',
        message = 'Bookable offer is not available';
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
  end if;

  if not public.equine_center_is_in_open_bookable_pilot(
    key_row.center_id,
    key_row.equine_id
  ) then
    raise exception using
      errcode = '42501',
      message = 'Bookable offer is not available';
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

      if not public.equine_center_is_in_open_bookable_pilot(
        key_row.center_id,
        key_row.equine_id
      ) then
        raise exception using
          errcode = '42501',
          message = 'Bookable offer is not available';
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

  if not public.equine_center_is_in_open_bookable_pilot(
    key_row.center_id,
    key_row.equine_id
  ) then
    raise exception using
      errcode = '42501',
      message = 'Bookable offer is not available';
  end if;

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
  'Authenticated request for the ACTIVE caller PERSON. CREATED and REPLAYED both require the center and equine to remain an ACTIVE subject of an OPEN pilot, including when the key already points at a confirmed booking. Ending the subject or closing the pilot does not return REPLAYED and does not insert another booking. Historical reconciliation of that key is only get_my_booking_request. Re-checks the derived slot, then calls create_booking_request. Never confirms and never writes a payment status. The same client_request_id replays the same booking while the pilot subject stays open. A key with no booking is ambiguous and does not insert another row. There is no no-payment-required status in the schema.';

revoke all on function public.request_bookable_slot(uuid, uuid, uuid, uuid, timestamptz, timestamptz)
  from public, anon, authenticated, service_role;
grant execute on function public.request_bookable_slot(uuid, uuid, uuid, uuid, timestamptz, timestamptz)
  to authenticated;

