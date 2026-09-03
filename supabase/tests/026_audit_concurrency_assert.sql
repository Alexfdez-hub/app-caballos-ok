-- Final row assertions after both incident reports have finished.
do $$
declare
  incident_count integer;
  audit_count integer;
begin
  select count(*)
    into incident_count
    from public.incidents
   where booking_id = '88700000-0000-0000-0000-00000000b001';

  select count(*)
    into audit_count
    from public.audit_events
   where event_type = 'incident_reported'
     and metadata->>'booking_id' = '88700000-0000-0000-0000-00000000b001';

  if incident_count <> 2 then
    raise exception 'Expected two incidents for the session, found %', incident_count;
  end if;

  if audit_count <> 2 then
    raise exception 'Expected two incident_reported audits, found %', audit_count;
  end if;
end;
$$;

select id, booking_id, session_id, reported_by_person_id
  from public.incidents
 where booking_id = '88700000-0000-0000-0000-00000000b001';

select id, event_type, entity_type, entity_id, actor_account_id, metadata
  from public.audit_events
 where metadata->>'booking_id' = '88700000-0000-0000-0000-00000000b001'
    or entity_id in (
      select id from public.sessions
       where booking_id = '88700000-0000-0000-0000-00000000b001'
    );
