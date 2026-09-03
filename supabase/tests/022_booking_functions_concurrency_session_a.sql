-- Session A: confirm, handshake after one materialized evaluation.
set statement_timeout = '20s';
begin;
select pg_backend_pid() as session_a_pid;
set local role authenticated;
select set_config('request.jwt.claim.sub', '99100000-0000-0000-0000-000000000005', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"99100000-0000-0000-0000-000000000005","role":"authenticated"}',
  true
);
select set_config('app.confirm_pause_after_eval', '1', true);
select public.confirm_booking('99100000-0000-0000-0000-00000000b001') as confirmed_id;
commit;
select 'session_a_committed' as marker;
