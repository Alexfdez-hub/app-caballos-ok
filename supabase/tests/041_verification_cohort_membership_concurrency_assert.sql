do $$
declare
  membership_count integer;
begin
  select count(*)
    into membership_count
    from public.verification_review_cohort_cases
   where case_id = '04130000-0000-4000-8000-0000000000c1';

  if membership_count <> 1 then
    raise exception 'Concurrent cohort adds left % memberships', membership_count;
  end if;
end;
$$;
