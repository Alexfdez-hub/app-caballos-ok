insert into auth.users (id) values
  ('04020000-0000-4000-8000-000000000001'),
  ('04020000-0000-4000-8000-000000000002');

insert into public.identity_verification_cases (
  id,
  subject_person_id,
  market_country_code,
  state,
  submitted_by_account_id
)
select
  '04020000-0000-4000-8000-0000000000a1',
  subject.person_id,
  'ES',
  'SUBMITTED',
  subject.id
  from public.user_accounts as subject
 where subject.auth_user_id = '04020000-0000-4000-8000-000000000002';

select public.create_verification_review_cohort('ES-040-CONCURRENCY');

select public.add_verification_review_cohort_case(
  'ES-040-CONCURRENCY',
  'IDENTITY',
  '04020000-0000-4000-8000-0000000000a1'
);

select public.close_verification_review_cohort_composition('ES-040-CONCURRENCY');

insert into public.verification_review_grants (
  reviewer_person_id,
  scope_type,
  market_country_code,
  cohort_code
)
select account.person_id, 'MARKET', 'ES', 'ES-040-CONCURRENCY'
  from public.user_accounts as account
 where account.auth_user_id = '04020000-0000-4000-8000-000000000001';
