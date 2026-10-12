insert into auth.users (id) values
  ('04130000-0000-4000-8000-000000000001');

insert into public.identity_verification_cases (
  id,
  subject_person_id,
  market_country_code,
  state,
  submitted_by_account_id
)
select
  '04130000-0000-4000-8000-0000000000c1',
  account.person_id,
  'ES',
  'SUBMITTED',
  account.id
  from public.user_accounts as account
 where account.auth_user_id = '04130000-0000-4000-8000-000000000001';

select public.create_verification_review_cohort('ES-041-A');
select public.create_verification_review_cohort('ES-041-B');
