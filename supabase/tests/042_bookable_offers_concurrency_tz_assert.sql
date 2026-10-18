do $$
declare
  booking_count integer;
  shared_booking uuid;
  key_count integer;
begin
  select count(*), (array_agg(booking.id))[1]
    into booking_count, shared_booking
    from public.bookings as booking
   where booking.equine_id = '04210000-0000-4000-8000-0000000000e1'
     and booking.center_id = '04210000-0000-4000-8000-0000000000c1'
     and booking.service_id = '04210000-0000-4000-8000-0000000000f1'
     and booking.starts_at = timestamptz '2026-12-02 11:00:00+00'
     and booking.ends_at = timestamptz '2026-12-02 12:00:00+00'
     and booking.status not in ('REJECTED', 'CANCELLED', 'EXPIRED', 'COMPLETED');

  if booking_count <> 1 then
    raise exception 'timezone-variant keys left % open bookings', booking_count;
  end if;

  select count(*)
    into key_count
    from public.booking_request_keys as key
   where key.client_request_id in (
       '04220000-0000-4000-8000-0000000000d5',
       '04220000-0000-4000-8000-0000000000d6'
     )
     and key.booking_id = shared_booking
     and key.starts_at = timestamptz '2026-12-02 11:00:00+00'
     and key.ends_at = timestamptz '2026-12-02 12:00:00+00';

  if key_count <> 2 then
    raise exception 'timezone-variant keys must share one UTC slot, got %', key_count;
  end if;
end;
$$;
