do $$
declare
  accepted_count integer;
  open_count integer;
  matching_audit integer;
begin
  select count(*)
    into accepted_count
    from public.identity_verification_cases as subject_case
   where subject_case.id in (
     '03730000-0000-4000-8000-0000000000c1',
     '03730000-0000-4000-8000-0000000000c2'
   )
     and subject_case.state = 'ACCEPTED';

  select count(*)
    into open_count
    from public.identity_verification_cases as subject_case
   where subject_case.id in (
     '03730000-0000-4000-8000-0000000000c1',
     '03730000-0000-4000-8000-0000000000c2'
   )
     and subject_case.state = 'SUBMITTED';

  if accepted_count <> 1 or open_count <> 1 then
    raise exception
      'Same-subject race stored % acceptances and left % submitted',
      accepted_count,
      open_count;
  end if;

  select count(*)
    into matching_audit
    from public.audit_events as event
    join public.identity_verification_decisions as decision
      on decision.case_id = event.entity_id
     and decision.outcome = 'ACCEPTED'
   where event.entity_id in (
     '03730000-0000-4000-8000-0000000000c1',
     '03730000-0000-4000-8000-0000000000c2'
   )
     and event.event_type = 'verification_case_reviewed'
     and event.occurred_at >= decision.decided_at - interval '2 seconds'
     and event.occurred_at <= decision.decided_at + interval '2 seconds';

  if matching_audit <> 1 then
    raise exception 'Same-subject race stored % matching audit events', matching_audit;
  end if;
end;
$$;
