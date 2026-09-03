-- Session A: report incident, hold the session row lock for 2s, commit.
set statement_timeout = '15s';
begin;
select pg_backend_pid() as session_a_pid, clock_timestamp() as session_a_begin;
select set_config(
  'app.conc_session_id',
  (select session.id::text
     from public.sessions as session
    where session.booking_id = '88700000-0000-0000-0000-00000000b001'),
  true
);
set local role authenticated;
select set_config('request.jwt.claim.sub', '88700000-0000-0000-0000-000000000001', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"88700000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);
select clock_timestamp() as session_a_before_incident;
select public.report_incident(
  '88700000-0000-0000-0000-00000000b001',
  current_setting('app.conc_session_id')::uuid,
  'Concurrent incident A'
) as session_a_incident_id;
select clock_timestamp() as session_a_after_incident;
select pg_sleep(2);
select clock_timestamp() as session_a_before_commit;
commit;
select clock_timestamp() as session_a_after_commit;
select 'session_a_committed' as marker;
