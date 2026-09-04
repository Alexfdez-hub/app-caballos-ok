select pg_advisory_unlock_all();
set session_replication_role = replica;

delete from public.rider_equine_authorizations
 where source_zero_session_id = '98100000-0000-0000-0000-00000000a001';
delete from public.zero_sessions
 where id = '98100000-0000-0000-0000-00000000a001';
delete from public.equine_center_permissions
 where equine_id = '98100000-0000-0000-0000-00000000e001';
delete from public.center_memberships
 where center_id = '98100000-0000-0000-0000-00000000c001';
delete from public.equines
 where id = '98100000-0000-0000-0000-00000000e001';
delete from public.equestrian_centers
 where id = '98100000-0000-0000-0000-00000000c001';
delete from public.user_accounts
 where auth_user_id in (
   '98100000-0000-0000-0000-000000000001',
   '98100000-0000-0000-0000-000000000002',
   '98100000-0000-0000-0000-000000000003',
   '98100000-0000-0000-0000-000000000004'
 );
delete from public.persons
 where first_name = 'Conc9B';
delete from public.market_age_rules where country_code = 'Z9';
delete from public.markets where country_code = 'Z9';
delete from auth.users
 where id in (
   '98100000-0000-0000-0000-000000000001',
   '98100000-0000-0000-0000-000000000002',
   '98100000-0000-0000-0000-000000000003',
   '98100000-0000-0000-0000-000000000004'
 );

set session_replication_role = origin;

insert into public.markets (country_code, status) values ('Z9', 'ACTIVE');
insert into public.market_age_rules (
  country_code, legal_adult_age, guardian_consent_required, effective_from
) values ('Z9', 18, true, date '2000-01-01');
insert into auth.users (id) values
  ('98100000-0000-0000-0000-000000000001'),
  ('98100000-0000-0000-0000-000000000002'),
  ('98100000-0000-0000-0000-000000000003'),
  ('98100000-0000-0000-0000-000000000004');

do $$
#variable_conflict use_variable
declare
  rider_id uuid;
  evaluator_a_id uuid;
  evaluator_b_id uuid;
  manager_id uuid;
  rider_account_id uuid;
begin
  select person_id, id into rider_id, rider_account_id from public.user_accounts
   where auth_user_id = '98100000-0000-0000-0000-000000000001';
  select person_id into evaluator_a_id from public.user_accounts
   where auth_user_id = '98100000-0000-0000-0000-000000000002';
  select person_id into evaluator_b_id from public.user_accounts
   where auth_user_id = '98100000-0000-0000-0000-000000000003';
  select person_id into manager_id from public.user_accounts
   where auth_user_id = '98100000-0000-0000-0000-000000000004';

  update public.persons set first_name = 'Conc9B', last_name = 'Rider',
    date_of_birth = date '1990-01-01' where id = rider_id;
  update public.persons set first_name = 'Conc9B', last_name = 'EvaluatorA',
    date_of_birth = date '1980-01-01' where id = evaluator_a_id;
  update public.persons set first_name = 'Conc9B', last_name = 'EvaluatorB',
    date_of_birth = date '1980-01-01' where id = evaluator_b_id;
  update public.persons set first_name = 'Conc9B', last_name = 'Manager',
    date_of_birth = date '1980-01-01' where id = manager_id;

  insert into public.equestrian_centers (
    id, name, slug, country_code, status
  ) values (
    '98100000-0000-0000-0000-00000000c001',
    'Phase9B Concurrency', 'phase9b-concurrency', 'Z9', 'ACTIVE'
  );
  insert into public.equines (id, name, equine_type, status) values (
    '98100000-0000-0000-0000-00000000e001',
    'phase9b-concurrency-equine', 'HORSE', 'ACTIVE'
  );
  insert into public.center_memberships (center_id, person_id, role_code) values
    ('98100000-0000-0000-0000-00000000c001', evaluator_a_id, 'ASSESSOR'),
    ('98100000-0000-0000-0000-00000000c001', evaluator_b_id, 'ASSESSOR'),
    ('98100000-0000-0000-0000-00000000c001', manager_id, 'MANAGER');
  insert into public.equine_center_permissions (
    equine_id, center_id, granted_by_person_id, permission_code
  ) values (
    '98100000-0000-0000-0000-00000000e001',
    '98100000-0000-0000-0000-00000000c001', manager_id, 'ASSESS_RIDERS'
  );
  insert into public.zero_sessions (
    id, rider_person_id, equine_id, center_id, requested_by_account_id,
    scheduled_at
  ) values (
    '98100000-0000-0000-0000-00000000a001', rider_id,
    '98100000-0000-0000-0000-00000000e001',
    '98100000-0000-0000-0000-00000000c001', rider_account_id,
    now() - interval '1 hour'
  );
end;
$$;
