-- Session A: submit review, hold the booking row lock for 2s, commit.
set statement_timeout = '15s';
begin;
select pg_backend_pid() as session_a_pid, clock_timestamp() as session_a_begin;
select set_config(
  'app.conc_center_id',
  (select booking.center_id::text
     from public.bookings as booking
    where booking.id = '88500000-0000-0000-0000-00000000b001'),
  true
);
set local role authenticated;
select set_config('request.jwt.claim.sub', '88500000-0000-0000-0000-000000000001', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"88500000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);
select clock_timestamp() as session_a_before_review;
select public.submit_review(
  '88500000-0000-0000-0000-00000000b001',
  current_setting('app.conc_center_id')::uuid,
  5
) as session_a_review_id;
select clock_timestamp() as session_a_after_review;
select pg_sleep(2);
select clock_timestamp() as session_a_before_commit;
commit;
select clock_timestamp() as session_a_after_commit;
select 'session_a_committed' as marker;
