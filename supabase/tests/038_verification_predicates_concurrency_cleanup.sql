do $$
declare
  person_ids uuid[];
begin
  select coalesce(array_agg(account.person_id), '{}')
    into person_ids
    from public.user_accounts as account
   where account.auth_user_id in (
     '03820000-0000-4000-8000-000000000001',
     '03820000-0000-4000-8000-000000000002'
   );

  alter table public.identity_verification_decisions
    disable trigger identity_verification_decisions_immutable;

  delete from public.identity_verification_decisions
   where case_id = '03820000-0000-4000-8000-0000000000c1';

  alter table public.identity_verification_decisions
    enable trigger identity_verification_decisions_immutable;

  delete from public.identity_verification_cases
   where id = '03820000-0000-4000-8000-0000000000c1';

  delete from public.verification_review_grants
   where reviewer_person_id = any (person_ids);

  delete from public.user_accounts where person_id = any (person_ids);
  delete from public.persons where id = any (person_ids);
  delete from auth.users
   where id in (
     '03820000-0000-4000-8000-000000000001',
     '03820000-0000-4000-8000-000000000002'
   );
end;
$$;
