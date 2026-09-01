-- Best-effort cleanup of committed concurrency fixtures.
delete from public.guardian_consents
 where guardian_relationship_id = '30000000-0000-0000-0000-0000000000aa'
    or id = '30000000-0000-0000-0000-0000000000ee';

delete from public.guardian_relationships
 where id = '30000000-0000-0000-0000-0000000000aa';

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
