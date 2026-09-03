-- Session A: start, hold the booking row lock for 2s, commit.
set statement_timeout = '15s';
begin;
select pg_backend_pid() as session_a_pid, clock_timestamp() as session_a_begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '88100000-0000-0000-0000-000000000001', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"88100000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);
select clock_timestamp() as session_a_before_start;
select public.start_session('88100000-0000-0000-0000-00000000b001') as session_a_id;
select clock_timestamp() as session_a_after_start;
select pg_sleep(2);
select clock_timestamp() as session_a_before_commit;
commit;
select clock_timestamp() as session_a_after_commit;
select 'session_a_committed' as marker;
