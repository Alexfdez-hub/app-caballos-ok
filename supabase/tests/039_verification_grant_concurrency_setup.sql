insert into auth.users (id) values
  ('03920000-0000-4000-8000-000000000001');

select public.create_verification_review_cohort('ES-039-CONCURRENCY');
select public.close_verification_review_cohort_composition('ES-039-CONCURRENCY');
