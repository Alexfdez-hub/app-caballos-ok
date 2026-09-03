-- Session A: test-only probe, handshake after one materialized evaluation.
-- Does not call public.confirm_booking and does not use a production GUC.
set statement_timeout = '20s';
begin;
select pg_backend_pid() as session_a_pid;
select set_config('request.jwt.claim.sub', '99100000-0000-0000-0000-000000000005', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"99100000-0000-0000-0000-000000000005","role":"authenticated"}',
  true
);
select public.confirm_booking_concurrency_probe('99100000-0000-0000-0000-00000000b001') as confirmed_id;
commit;
select 'session_a_committed' as marker;
