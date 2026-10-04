do $$
declare
  decision_count integer;
  matching_audit integer;
begin
  select count(*)
    into decision_count
    from public.identity_verification_decisions as decision
   where decision.case_id = '03720000-0000-4000-8000-0000000000c1';

  if decision_count <> 1 then
    raise exception 'Concurrent reviews stored % decisions', decision_count;
  end if;

  select count(*)
    into matching_audit
    from public.audit_events as event
    join public.identity_verification_decisions as decision
      on decision.case_id = event.entity_id
   where event.entity_id = '03720000-0000-4000-8000-0000000000c1'
     and event.event_type = 'verification_case_reviewed'
     and event.occurred_at >= decision.decided_at - interval '2 seconds'
     and event.occurred_at <= decision.decided_at + interval '2 seconds';

  if matching_audit <> 1 then
    raise exception 'Concurrent review stored % matching audit events', matching_audit;
  end if;

  if (
    select subject_case.state
      from public.identity_verification_cases as subject_case
     where subject_case.id = '03720000-0000-4000-8000-0000000000c1'
  ) is distinct from 'ACCEPTED' then
    raise exception 'Concurrent review left the case unaccepted';
  end if;
end;
$$;
