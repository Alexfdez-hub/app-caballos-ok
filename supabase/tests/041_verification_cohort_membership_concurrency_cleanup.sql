create temporary table cohort_membership_cleanup_persons (id uuid);

insert into cohort_membership_cleanup_persons (id)
select account.person_id
  from public.user_accounts as account
 where account.auth_user_id = '04130000-0000-4000-8000-000000000001';

set session_replication_role = replica;

delete from public.verification_review_cohort_events
 where cohort_code in ('ES-041-A', 'ES-041-B');

delete from public.verification_review_cohort_cases
 where case_id = '04130000-0000-4000-8000-0000000000c1';

delete from public.verification_review_cohorts
 where code in ('ES-041-A', 'ES-041-B');

delete from public.identity_verification_cases
 where id = '04130000-0000-4000-8000-0000000000c1';

delete from public.user_accounts as account
 where account.auth_user_id = '04130000-0000-4000-8000-000000000001';

delete from public.persons as person
 where person.id in (select id from cohort_membership_cleanup_persons);

delete from auth.users
 where id = '04130000-0000-4000-8000-000000000001';

set session_replication_role = origin;

drop table cohort_membership_cleanup_persons;
