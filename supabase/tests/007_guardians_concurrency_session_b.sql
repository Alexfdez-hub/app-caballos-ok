-- Session B: independent connection. Started while A still holds locks.
-- Must wait, then fail with a controlled unique/active-consent error.
set statement_timeout = '15s';
set lock_timeout = '8s';
begin;
select pg_backend_pid() as session_b_pid, clock_timestamp() as session_b_begin;
set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '30000000-0000-0000-0000-000000000001',
  true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"30000000-0000-0000-0000-000000000001"}',
  true
);
select clock_timestamp() as session_b_before_grant;
select *
  from public.grant_guardian_consent(
    '30000000-0000-0000-0000-0000000000aa',
    'EQUESTRIAN_ACTIVITY',
    'GENERAL',
    'v-race-b',
    'XC',
    null
  );
select clock_timestamp() as session_b_after_grant;
commit;
