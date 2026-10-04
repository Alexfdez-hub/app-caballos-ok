set statement_timeout = '15s';
begin;
select set_config(
  'request.jwt.claim.sub',
  '03730000-0000-4000-8000-000000000002',
  true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"03730000-0000-4000-8000-000000000002","role":"authenticated"}',
  true
);
set local role authenticated;

do $$
begin
  perform public.review_identity_case(
    '03730000-0000-4000-8000-0000000000c1',
    'ACCEPTED',
    'subject-race'
  );
exception
  when insufficient_privilege then
    null;
end;
$$;

select pg_sleep(2);
commit;
