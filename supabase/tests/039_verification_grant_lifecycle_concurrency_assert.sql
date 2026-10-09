do $$
declare
  reviewer_person uuid;
  grant_status text;
  suspended_count integer;
  closed_count integer;
  closed_previous text;
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
    into suspended_count
    from public.verification_review_grant_events as event
   where event.reviewer_person_id = reviewer_person
     and event.event_type = 'SUSPENDED'
     and event.previous_status = 'ACTIVE'
     and event.new_status = 'SUSPENDED';

  select count(*), min(event.previous_status)
    into closed_count, closed_previous
    from public.verification_review_grant_events as event
   where event.reviewer_person_id = reviewer_person
     and event.event_type = 'CLOSED'
     and event.new_status = 'ENDED';

  if grant_status is distinct from 'ENDED'
     or public.verification_review_grant_matches(reviewer_person, 'IDENTITY', 'ES')
     or public.verification_review_grant_matches(reviewer_person, 'EQUINE', 'ES')
     or closed_count <> 1
     or suspended_count > 1
     or (
       suspended_count = 0
       and closed_previous is distinct from 'ACTIVE'
     )
     or (
       suspended_count = 1
       and closed_previous is distinct from 'SUSPENDED'
     ) then
    raise exception
      'Concurrent suspend/close left status %, % suspended events, % closed events from %',
      grant_status,
      suspended_count,
      closed_count,
      closed_previous;
  end if;
end;
$$;
