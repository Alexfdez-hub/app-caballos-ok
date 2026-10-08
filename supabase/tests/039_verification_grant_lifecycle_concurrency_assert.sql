do $$
declare
  reviewer_person uuid;
  grant_status text;
  transition_count integer;
begin
  select account.person_id
    into reviewer_person
    from public.user_accounts as account
   where account.auth_user_id = '03930000-0000-4000-8000-000000000001';

  select grant_row.status
    into grant_status
    from public.verification_review_grants as grant_row
   where grant_row.reviewer_person_id = reviewer_person
     and grant_row.scope_type = 'MARKET'
     and grant_row.market_country_code = 'ES';

  select count(*)
    into transition_count
    from public.verification_review_grant_events as event
   where event.reviewer_person_id = reviewer_person
     and event.event_type in ('SUSPENDED', 'CLOSED');

  if transition_count <> 1
     or grant_status not in ('SUSPENDED', 'ENDED')
     or public.verification_review_grant_matches(reviewer_person, 'IDENTITY', 'ES') then
    raise exception
      'Concurrent suspend/close left status % and % transition events',
      grant_status,
      transition_count;
  end if;
end;
$$;
