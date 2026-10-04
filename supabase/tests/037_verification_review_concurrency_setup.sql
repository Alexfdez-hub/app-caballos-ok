insert into auth.users (id) values
  ('03720000-0000-4000-8000-000000000001'),
  ('03720000-0000-4000-8000-000000000002'),
  ('03720000-0000-4000-8000-000000000003');

insert into public.identity_verification_cases (
  id,
  subject_person_id,
  market_country_code,
  state,
  submitted_by_account_id
)
select
  '03720000-0000-4000-8000-0000000000c1',
  account.person_id,
  'ES',
  'SUBMITTED',
  account.id
  from public.user_accounts as account
 where account.auth_user_id = '03720000-0000-4000-8000-000000000001';

insert into public.verification_review_grants (reviewer_person_id, scope_type)
select account.person_id, 'PLATFORM_IDENTITY'
  from public.user_accounts as account
 where account.auth_user_id in (
   '03720000-0000-4000-8000-000000000002',
   '03720000-0000-4000-8000-000000000003'
 );
