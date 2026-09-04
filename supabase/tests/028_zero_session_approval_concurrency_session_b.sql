begin;
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"98100000-0000-0000-0000-000000000003","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '98100000-0000-0000-0000-000000000003',
  true
);
select * from public.approve_zero_session(
  '98100000-0000-0000-0000-00000000a001',
  'APPROVED_WITH_RESTRICTIONS',
  'Evaluator B'
);
commit;
