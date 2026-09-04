begin;
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"98100000-0000-0000-0000-000000000002","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '98100000-0000-0000-0000-000000000002',
  true
);
select * from public.approve_zero_session(
  '98100000-0000-0000-0000-00000000a001', 'APPROVED', 'Evaluator A'
);
select 'approval_a_holding' as phase;
select pg_sleep(2);
commit;
select 'approval_a_committed' as phase;
