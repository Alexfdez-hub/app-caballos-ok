create temporary table cohort_submit_cleanup_persons (id uuid);

insert into cohort_submit_cleanup_persons (id)
select account.person_id
  from public.user_accounts as account
 where account.auth_user_id = '04120000-0000-4000-8000-000000000001';

set session_replication_role = replica;

delete from public.identity_verification_cases
 where subject_person_id in (select id from cohort_submit_cleanup_persons);

delete from public.user_accounts as account
 where account.auth_user_id = '04120000-0000-4000-8000-000000000001';

delete from public.persons as person
 where person.id in (select id from cohort_submit_cleanup_persons);

delete from auth.users
 where id = '04120000-0000-4000-8000-000000000001';

set session_replication_role = origin;

drop table cohort_submit_cleanup_persons;
