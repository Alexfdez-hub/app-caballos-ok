set statement_timeout = '15s';
select pg_sleep(1);
begin;

select set_config(
  'request.jwt.claim.sub',
  '04020000-0000-4000-8000-000000000001',
  true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"04020000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
set local role authenticated;

do $$
begin
  perform public.get_my_review_case(
    'IDENTITY',
    '04020000-0000-4000-8000-0000000000a1'
  );
  raise exception 'Review detail succeeded after the grant suspension won';
exception
  when insufficient_privilege then
    null;
end;
$$;

select pg_sleep(1);
commit;
