-- Best-effort cleanup of committed 029 concurrency fixtures.
set session_replication_role = replica;

delete from public.audit_events
 where metadata->>'guardian_relationship_id' = '98800000-0000-0000-0000-0000000000aa'
    or entity_id in (
      select id from public.guardian_consents
       where guardian_relationship_id = '98800000-0000-0000-0000-0000000000aa'
    );

delete from public.guardian_consents
 where guardian_relationship_id = '98800000-0000-0000-0000-0000000000aa'
    or id = '98800000-0000-0000-0000-0000000000ee';

delete from public.guardian_relationships
 where id = '98800000-0000-0000-0000-0000000000aa';

delete from public.policy_acceptances
 where user_account_id in (
   select id from public.user_accounts
    where auth_user_id in (
      '98800000-0000-0000-0000-000000000001',
      '98800000-0000-0000-0000-000000000003'
    )
 );

delete from public.policy_documents
 where market_code = 'XD'
   and policy_type = 'GUARDIAN_POLICY';

delete from public.market_age_rules where country_code = 'XD';
delete from public.markets where country_code = 'XD';

delete from public.user_accounts
 where auth_user_id in (
   '98800000-0000-0000-0000-000000000001',
   '98800000-0000-0000-0000-000000000003'
 );

delete from public.persons where last_name = 'AuditRace';

delete from auth.users
 where id in (
   '98800000-0000-0000-0000-000000000001',
   '98800000-0000-0000-0000-000000000003'
 );

set session_replication_role = origin;
