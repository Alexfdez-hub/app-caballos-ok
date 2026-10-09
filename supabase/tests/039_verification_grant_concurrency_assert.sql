do $$
declare
  reviewer_person uuid;
  grant_count integer;
  event_count integer;
begin
  select account.person_id
    into reviewer_person
    from public.user_accounts as account
   where account.auth_user_id = '03920000-0000-4000-8000-000000000001';

  select count(*)
    into grant_count
    from public.verification_review_grants as grant_row
   where grant_row.reviewer_person_id = reviewer_person
     and grant_row.scope_type = 'MARKET'
     and grant_row.market_country_code = 'ES'
     and grant_row.status = 'ACTIVE';

  select count(*)
    into event_count
    from public.verification_review_grant_events as event
   where event.reviewer_person_id = reviewer_person
     and event.event_type = 'GRANTED'
     and event.actor_kind = 'TECHNICAL'
     and event.actor_account_id is null
     and event.actor_person_id is null;

  if grant_count <> 1 or event_count <> 1 then
    raise exception
      'Concurrent bootstrap committed % grants and % GRANTED events',
      grant_count,
      event_count;
  end if;
end;
$$;
