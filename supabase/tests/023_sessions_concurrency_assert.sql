-- Final row assertions after both start attempts have finished.
do $$
declare
  session_count integer;
  active_count integer;
  started_values integer;
begin
  select count(*)
    into session_count
    from public.sessions
   where booking_id = '88100000-0000-0000-0000-00000000b001';

  select count(*)
    into active_count
    from public.sessions
   where booking_id = '88100000-0000-0000-0000-00000000b001'
     and status = 'ACTIVE';

  select count(distinct started_at)
    into started_values
    from public.sessions
   where booking_id = '88100000-0000-0000-0000-00000000b001';

  if session_count <> 1 then
    raise exception 'Expected exactly one session for the booking, found %', session_count;
  end if;

  if active_count <> 1 then
    raise exception 'Expected the concurrent start to leave one ACTIVE session, found %', active_count;
  end if;

  if started_values <> 1 then
    raise exception 'Concurrent start mutated started_at';
  end if;
end;
$$;

select id, booking_id, status, started_at, started_offline
  from public.sessions
 where booking_id = '88100000-0000-0000-0000-00000000b001';
