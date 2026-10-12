do $$
declare
  open_count integer;
begin
  select count(*)
    into open_count
    from public.identity_verification_cases as identity_case
    join public.user_accounts as account
      on account.person_id = identity_case.subject_person_id
   where account.auth_user_id = '04120000-0000-4000-8000-000000000001'
     and identity_case.market_country_code = 'ES'
     and identity_case.state = 'SUBMITTED';

  if open_count <> 1 then
    raise exception 'Concurrent identity submits left % open cases', open_count;
  end if;
end;
$$;
