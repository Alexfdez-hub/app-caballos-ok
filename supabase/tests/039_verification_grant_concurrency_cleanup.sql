create temporary table grant_cleanup_persons (id uuid);

insert into grant_cleanup_persons (id)
select account.person_id
  from public.user_accounts as account
 where account.auth_user_id = '03920000-0000-4000-8000-000000000001';

set session_replication_role = replica;

delete from public.verification_review_grant_events as event
 where event.reviewer_person_id in (select id from grant_cleanup_persons);

delete from public.verification_review_grants as grant_row
 where grant_row.reviewer_person_id in (select id from grant_cleanup_persons);

delete from public.user_accounts as account
 where account.auth_user_id = '03920000-0000-4000-8000-000000000001';

delete from public.persons as person
 where person.id in (select id from grant_cleanup_persons);

delete from auth.users
 where id = '03920000-0000-4000-8000-000000000001';

set session_replication_role = origin;

drop table grant_cleanup_persons;
