insert into auth.users (id) values
  ('03930000-0000-4000-8000-000000000001');

select public.bootstrap_verification_review_grant(account.person_id)
  from public.user_accounts as account
 where account.auth_user_id = '03930000-0000-4000-8000-000000000001';
