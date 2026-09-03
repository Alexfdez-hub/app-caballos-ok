-- Session B: start after A holds the booking lock.
set statement_timeout = '15s';
begin;
select pg_backend_pid() as session_b_pid, clock_timestamp() as session_b_begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '88100000-0000-0000-0000-000000000001', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"88100000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);
select clock_timestamp() as session_b_before_start;
select public.start_session('88100000-0000-0000-0000-00000000b001') as session_b_id;
select clock_timestamp() as session_b_after_start;
commit;
select clock_timestamp() as session_b_after_commit;
select 'session_b_committed' as marker;
