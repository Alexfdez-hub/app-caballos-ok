-- Session A: grant, hold the transaction for 2s, commit.
set statement_timeout = '15s';
begin;
select pg_backend_pid() as session_a_pid, clock_timestamp() as session_a_begin;
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
select clock_timestamp() as session_a_before_grant;
select *
  from public.grant_guardian_consent(
    '98800000-0000-0000-0000-00000000aa',
    'EQUESTRIAN_ACTIVITY',
    'GENERAL',
    'v-race-a',
    'XD',
    null
  );
select clock_timestamp() as session_a_after_grant;
select pg_sleep(2);
select clock_timestamp() as session_a_before_commit;
commit;
select clock_timestamp() as session_a_after_commit;
