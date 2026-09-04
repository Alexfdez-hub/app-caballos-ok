do $$
declare
  row_count integer;
  stored public.zero_sessions%rowtype;
begin
  select * into stored from public.zero_sessions
   where id = '98100000-0000-0000-0000-00000000a001';
  select count(*) into row_count from public.zero_sessions
   where id = '98100000-0000-0000-0000-00000000a001'
     and result in ('APPROVED', 'APPROVED_WITH_RESTRICTIONS')
     and evaluator_person_id is not null
     and performed_at is not null;
  if row_count <> 1 or stored.notes <> 'Evaluator A' then
    raise exception 'Concurrent approval did not preserve exactly one winner';
  end if;
end;
$$;
