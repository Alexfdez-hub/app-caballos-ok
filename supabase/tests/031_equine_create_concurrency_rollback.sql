begin;

select set_config(
  'request.jwt.claim.sub',
  '03120000-0000-4000-8000-000000000001',
  true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"03120000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);

set local role authenticated;

select public.create_my_equine('Race Rollback', 'HORSE');

rollback;
