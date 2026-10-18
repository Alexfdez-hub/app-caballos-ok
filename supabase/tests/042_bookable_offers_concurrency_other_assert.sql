do $$
declare
  booking_count integer;
  distinct_keys integer;
begin
  select count(*)
    into booking_count
    from public.bookings as booking
   where booking.equine_id = '04210000-0000-4000-8000-0000000000e1'
     and booking.center_id = '04210000-0000-4000-8000-0000000000c1'
     and booking.service_id = '04210000-0000-4000-8000-0000000000f1'
     and booking.starts_at = timestamptz '2026-12-02 09:00:00+00'
     and booking.ends_at = timestamptz '2026-12-02 10:00:00+00'
     and booking.status not in ('REJECTED', 'CANCELLED', 'EXPIRED', 'COMPLETED');

  if booking_count <> 2 then
    raise exception 'different accounts left % open bookings', booking_count;
  end if;

  select count(distinct key.booking_id)
    into distinct_keys
    from public.booking_request_keys as key
   where key.client_request_id in (
     '04220000-0000-4000-8000-0000000000d3',
     '04220000-0000-4000-8000-0000000000d4'
   );

  if distinct_keys <> 2 then
    raise exception 'different accounts were serialized onto % booking', distinct_keys;
  end if;
end;
$$;
