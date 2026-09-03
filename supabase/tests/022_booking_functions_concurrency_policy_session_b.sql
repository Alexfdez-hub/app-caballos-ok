-- Session B: hold persist gate, wait until A finished eval, then revoke
-- the participant policy acceptance used at evaluation time.
set statement_timeout = '20s';
begin;
select pg_advisory_lock(22022022);
select 'session_b_holding' as marker;
select pg_advisory_lock(22022021);

delete from public.policy_acceptances
 where person_id in (
   select account.person_id
     from public.user_accounts as account
    where account.auth_user_id = '99100000-0000-0000-0000-000000000001'
 )
   and policy_document_id in (
     select document.id
       from public.policy_documents as document
      where document.policy_code = 'TERMS_ZQ'
        and document.market_code = 'ZQ'
   );

select pg_advisory_unlock(22022022);
select pg_advisory_unlock(22022021);
commit;
select 'session_b_mutated' as marker;
