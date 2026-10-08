set statement_timeout = '15s';
begin;

do $$
declare
  reviewer_person uuid;
begin
  select account.person_id
    into reviewer_person
    from public.user_accounts as account
   where account.auth_user_id = '03920000-0000-4000-8000-000000000001';

  perform public.bootstrap_verification_review_grant(reviewer_person);
exception
  when insufficient_privilege then
    null;
end;
$$;

select pg_sleep(2);
commit;
