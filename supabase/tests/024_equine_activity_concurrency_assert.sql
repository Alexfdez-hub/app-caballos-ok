-- Final row assertions after both record attempts have finished.
do $$
declare
  activity_count integer;
  session_count integer;
begin
  select count(*)
    into session_count
    from public.sessions
   where booking_id = '88300000-0000-0000-0000-00000000b001';

  select count(*)
    into activity_count
    from public.equine_activities as activity
    join public.sessions as session
      on session.id = activity.session_id
   where session.booking_id = '88300000-0000-0000-0000-00000000b001';

  if session_count <> 1 then
    raise exception 'Expected exactly one session for the booking, found %', session_count;
  end if;

  if activity_count <> 1 then
    raise exception 'Expected exactly one activity row for the session, found %', activity_count;
  end if;
end;
$$;

select activity.id, activity.session_id, activity.booking_id, activity.starts_at, activity.ends_at
  from public.equine_activities as activity
  join public.sessions as session
    on session.id = activity.session_id
 where session.booking_id = '88300000-0000-0000-0000-00000000b001';
