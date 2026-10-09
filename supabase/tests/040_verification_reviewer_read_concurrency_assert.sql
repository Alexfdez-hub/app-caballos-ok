do $$
declare
  reviewer_person uuid;
  grant_status text;
  opened_count integer;
begin
  select account.person_id
    into reviewer_person
    from public.user_accounts as account
   where account.auth_user_id = '04020000-0000-4000-8000-000000000001';

  select grant_row.status
    into grant_status
    from public.verification_review_grants as grant_row
   where grant_row.reviewer_person_id = reviewer_person
     and grant_row.scope_type = 'MARKET'
     and grant_row.market_country_code = 'ES';

  select count(*)
    into opened_count
    from public.audit_events as event
   where event.entity_id = '04020000-0000-4000-8000-0000000000a1'
     and event.event_type = 'verification_review_opened';

  if grant_status is distinct from 'SUSPENDED' or opened_count <> 0 then
    raise exception
      'Suspend-versus-open left status % and % audit rows',
      grant_status,
      opened_count;
  end if;
end;
$$;
