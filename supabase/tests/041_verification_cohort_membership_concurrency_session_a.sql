set statement_timeout = '15s';
begin;

do $$
begin
  perform public.add_verification_review_cohort_case(
    'ES-041-A',
    'IDENTITY',
    '04130000-0000-4000-8000-0000000000c1'
  );
exception
  when insufficient_privilege then
    null;
end;
$$;

select pg_sleep(1);
commit;
