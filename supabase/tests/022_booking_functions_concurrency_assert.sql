do $$
declare
  booking_status text;
  pending_count integer;
  min_age_count integer;
begin
  select booking.status
    into booking_status
    from public.bookings as booking
   where booking.id = '99100000-0000-0000-0000-00000000b001';

  select count(*)
    into pending_count
    from public.booking_requirements as requirement
   where requirement.booking_id = '99100000-0000-0000-0000-00000000b001'
     and requirement.status = 'PENDING';

  select count(*)
    into min_age_count
    from public.booking_requirements as requirement
   where requirement.booking_id = '99100000-0000-0000-0000-00000000b001'
     and requirement.requirement_type = 'MIN_AGE';

  if pending_count <> 0 then
    raise exception
      'Confirm persisted PENDING rows from a later snapshot, status=% pending=%',
      booking_status,
      pending_count;
  end if;

  if booking_status = 'CONFIRMED' then
    if min_age_count <> 0 then
      raise exception
        'Confirmed booking stored MIN_AGE from the post-eval mutation';
    end if;
  elsif booking_status is distinct from 'APPROVED' then
    raise exception
      'Unexpected booking status after concurrency handshake: %',
      booking_status;
  end if;
end;
$$;

select 'concurrency_assert_ok' as marker;
