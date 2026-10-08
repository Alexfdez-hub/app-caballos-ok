set statement_timeout = '15s';
begin;

do $$
declare
  grant_id uuid;
begin
  select grant_row.id
    into grant_id
    from public.verification_review_grants as grant_row
    join public.user_accounts as account
      on account.person_id = grant_row.reviewer_person_id
   where account.auth_user_id = '03930000-0000-4000-8000-000000000001'
     and grant_row.scope_type = 'MARKET'
     and grant_row.market_country_code = 'ES'
     and grant_row.status = 'ACTIVE';

  perform public.close_verification_review_grant(grant_id);
exception
  when insufficient_privilege then
    null;
end;
$$;

select pg_sleep(2);
commit;
