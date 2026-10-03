-- Issue #41 stage 031. Committed fixture for two concurrent creates.
-- Cleanup removes these rows. This file is not a migration.

insert into auth.users (id)
values ('03120000-0000-4000-8000-000000000001');

do $$
declare
  generated_person uuid;
begin
  select account.person_id
    into generated_person
    from public.user_accounts as account
   where account.auth_user_id = '03120000-0000-4000-8000-000000000001';

  delete from public.user_accounts
   where auth_user_id = '03120000-0000-4000-8000-000000000001';
  delete from public.persons
   where id = generated_person;
end;
$$;

insert into public.markets (country_code, status)
values ('QR', 'ACTIVE');

insert into public.market_age_rules (
  country_code, legal_adult_age, guardian_consent_required, effective_from
) values ('QR', 18, true, date '2000-01-01');

insert into public.persons (
  id, first_name, last_name, date_of_birth, country_code
) values (
  '03120000-0000-4000-8000-000000000011',
  'Race', 'Adult', date '1992-06-06', 'QR'
);

insert into public.user_accounts (id, auth_user_id, person_id)
values (
  '03120000-0000-4000-8000-000000000021',
  '03120000-0000-4000-8000-000000000001',
  '03120000-0000-4000-8000-000000000011'
);
