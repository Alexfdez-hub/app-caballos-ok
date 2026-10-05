set statement_timeout = '15s';
begin;
select set_config('request.jwt.claim.sub', '03820000-0000-4000-8000-000000000001', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"03820000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
set local role authenticated;
select pg_sleep(1);

do $$
begin
  if exists (
    select 1
      from public.list_my_verification_status() as status_row
     where status_row.subject_kind = 'IDENTITY'
       and status_row.market_country_code = 'ES'
       and status_row.status_code = 'VERIFIED'
  ) then
    raise exception 'Uncommitted acceptance was visible';
  end if;
end;
$$;

commit;
