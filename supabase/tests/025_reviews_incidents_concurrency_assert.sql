-- Final row assertions after both review attempts have finished.
do $$
declare
  review_count integer;
  rating_values integer;
begin
  select count(*)
    into review_count
    from public.reviews
   where booking_id = '88500000-0000-0000-0000-00000000b001';

  select count(distinct rating)
    into rating_values
    from public.reviews
   where booking_id = '88500000-0000-0000-0000-00000000b001';

  if review_count <> 1 then
    raise exception 'Expected exactly one review for the booking subject, found %', review_count;
  end if;

  if rating_values <> 1 then
    raise exception 'Concurrent review mutated rating';
  end if;
end;
$$;

select id, booking_id, reviewer_person_id, subject_id, rating
  from public.reviews
 where booking_id = '88500000-0000-0000-0000-00000000b001';
