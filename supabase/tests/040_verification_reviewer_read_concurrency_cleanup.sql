create temporary table review_read_cleanup_persons (id uuid);

insert into review_read_cleanup_persons (id)
select account.person_id
  from public.user_accounts as account
 where account.auth_user_id in (
   '04020000-0000-4000-8000-000000000001',
   '04020000-0000-4000-8000-000000000002'
 );

set session_replication_role = replica;

delete from public.audit_events as event
 where event.entity_id = '04020000-0000-4000-8000-0000000000a1'
    or event.actor_person_id in (select id from review_read_cleanup_persons);

delete from public.identity_verification_cases
 where id = '04020000-0000-4000-8000-0000000000a1';

delete from public.verification_review_grant_events as event
 where event.reviewer_person_id in (select id from review_read_cleanup_persons);

delete from public.verification_review_grants as grant_row
 where grant_row.reviewer_person_id in (select id from review_read_cleanup_persons);

delete from public.user_accounts as account
 where account.auth_user_id in (
   '04020000-0000-4000-8000-000000000001',
   '04020000-0000-4000-8000-000000000002'
 );

delete from public.persons as person
 where person.id in (select id from review_read_cleanup_persons);

delete from auth.users
 where id in (
   '04020000-0000-4000-8000-000000000001',
   '04020000-0000-4000-8000-000000000002'
 );

set session_replication_role = origin;

drop table review_read_cleanup_persons;
