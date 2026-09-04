-- Session B: started while A still holds locks. Must wait, then fail.
set statement_timeout = '15s';
set lock_timeout = '8s';
begin;
select pg_backend_pid() as session_b_pid, clock_timestamp() as session_b_begin;
set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '98800000-0000-0000-0000-000000000001',
  true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"98800000-0000-0000-0000-000000000001"}',
  true
);
select clock_timestamp() as session_b_before_grant;
select *
  from public.grant_guardian_consent(
    '98800000-0000-0000-0000-00000000aa',
    'EQUESTRIAN_ACTIVITY',
    'GENERAL',
    'v-race-b',
    'XD',
    null
  );
select clock_timestamp() as session_b_after_grant;
commit;
