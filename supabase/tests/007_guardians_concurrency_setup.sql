-- Committed fixtures for the two-session guardian consent race.
-- Orchestrated by scripts/run-guardians-concurrency-test.cjs.
-- Not a single-transaction test; do not wrap this file in rollback.

delete from public.guardian_consents
 where guardian_relationship_id = '30000000-0000-0000-0000-0000000000aa'
    or id = '30000000-0000-0000-0000-0000000000ee';

delete from public.guardian_relationships
 where id = '30000000-0000-0000-0000-0000000000aa'
    or guardian_person_id in (
      select person_id from public.user_accounts
       where auth_user_id in (
         '30000000-0000-0000-0000-000000000001',
         '30000000-0000-0000-0000-000000000003'
       )
    );

delete from public.policy_acceptances
 where user_account_id in (
   select id from public.user_accounts
    where auth_user_id in (
      '30000000-0000-0000-0000-000000000001',
      '30000000-0000-0000-0000-000000000003'
    )
 );

delete from public.policy_documents
 where market_code = 'XC'
   and policy_type = 'GUARDIAN_POLICY';

delete from public.market_age_rules
 where country_code = 'XC';

delete from public.markets
 where country_code = 'XC';

delete from public.user_accounts
 where auth_user_id in (
   '30000000-0000-0000-0000-000000000001',
   '30000000-0000-0000-0000-000000000003'
 );

delete from public.persons
 where last_name = 'Concurrency';

delete from auth.users
 where id in (
   '30000000-0000-0000-0000-000000000001',
   '30000000-0000-0000-0000-000000000003'
 );

insert into public.markets (country_code, status)
values ('XC', 'ACTIVE');

insert into public.market_age_rules (
  country_code,
  legal_adult_age,
  guardian_consent_required,
  effective_from
)
values ('XC', 18, true, date '2000-01-01');

insert into auth.users (id)
values
  ('30000000-0000-0000-0000-000000000001'),
  ('30000000-0000-0000-0000-000000000003');

update public.persons as person
   set first_name = 'Guardian',
       last_name = 'Concurrency',
       date_of_birth = date '1980-01-01'
 where person.id = (
   select account.person_id
     from public.user_accounts as account
    where account.auth_user_id = '30000000-0000-0000-0000-000000000001'
 );

update public.persons as person
   set first_name = 'Minor',
       last_name = 'Concurrency',
       date_of_birth = date '2018-06-15'
 where person.id = (
   select account.person_id
     from public.user_accounts as account
    where account.auth_user_id = '30000000-0000-0000-0000-000000000003'
 );

insert into public.guardian_relationships (
  id,
  guardian_person_id,
  minor_person_id,
  relationship_type,
  verification_status,
  verified_at
)
select
  '30000000-0000-0000-0000-0000000000aa',
  guardian.person_id,
  minor.person_id,
  'PARENT',
  'VERIFIED',
  now()
from public.user_accounts as guardian
join public.user_accounts as minor
  on minor.auth_user_id = '30000000-0000-0000-0000-000000000003'
where guardian.auth_user_id = '30000000-0000-0000-0000-000000000001';

insert into public.policy_documents (
  policy_code, policy_type, market_code, locale, version, title, content,
  effective_from, status, requires_reacceptance
)
values (
  'GUARDIAN_POLICY', 'GUARDIAN_POLICY', 'XC', 'es', '1',
  'Guardian policy XC', 'Concurrency test guardian policy',
  now() - interval '1 day', 'ACTIVE', true
);

insert into public.policy_acceptances (
  policy_document_id, person_id, user_account_id, accepted_at
)
select document.id, account.person_id, account.id, now()
from public.policy_documents as document
join public.user_accounts as account
  on account.auth_user_id = '30000000-0000-0000-0000-000000000001'
where document.market_code = 'XC'
  and document.policy_type = 'GUARDIAN_POLICY';

insert into public.guardian_consents (
  id,
  guardian_relationship_id,
  guardian_person_id,
  minor_person_id,
  granted_by_account_id,
  consent_type,
  scope_type,
  terms_version,
  status,
  granted_at,
  expires_at
)
select
  '30000000-0000-0000-0000-0000000000ee',
  '30000000-0000-0000-0000-0000000000aa',
  guardian.person_id,
  minor.person_id,
  guardian.id,
  'EQUESTRIAN_ACTIVITY',
  'GENERAL',
  'expired-fixture',
  'ACTIVE',
  now() - interval '10 days',
  now() - interval '1 minute'
from public.user_accounts as guardian
join public.user_accounts as minor
  on minor.auth_user_id = '30000000-0000-0000-0000-000000000003'
where guardian.auth_user_id = '30000000-0000-0000-0000-000000000001';
