set statement_timeout = '15s';
begin;

select set_config('request.jwt.claim.sub', '04120000-0000-4000-8000-000000000001', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"04120000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
set local role authenticated;

do $$
begin
  perform public.submit_my_identity_case('ES');
exception
  when insufficient_privilege then
    null;
end;
$$;

select pg_sleep(1);
commit;
