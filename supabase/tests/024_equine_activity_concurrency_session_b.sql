-- Session B: record after A holds the session lock.
set statement_timeout = '15s';
begin;
select pg_backend_pid() as session_b_pid, clock_timestamp() as session_b_begin;
select set_config(
  'app.conc_session_id',
  (select session.id::text
     from public.sessions as session
    where session.booking_id = '88300000-0000-0000-0000-00000000b001'),
  true
);
set local role authenticated;
select set_config('request.jwt.claim.sub', '88300000-0000-0000-0000-000000000001', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"88300000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);
select clock_timestamp() as session_b_before_record;
select public.record_equine_activity(current_setting('app.conc_session_id')::uuid) as session_b_activity_id;
select clock_timestamp() as session_b_after_record;
commit;
select clock_timestamp() as session_b_after_commit;
select 'session_b_committed' as marker;
