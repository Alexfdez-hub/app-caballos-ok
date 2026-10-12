insert into auth.users (id) values
  ('03930000-0000-4000-8000-000000000001');

select public.create_verification_review_cohort('ES-039-LIFECYCLE');
select public.close_verification_review_cohort_composition('ES-039-LIFECYCLE');

select public.bootstrap_verification_review_grant(account.person_id, 'ES-039-LIFECYCLE')
  from public.user_accounts as account
 where account.auth_user_id = '03930000-0000-4000-8000-000000000001';
