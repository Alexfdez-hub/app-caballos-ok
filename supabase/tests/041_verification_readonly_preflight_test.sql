-- Local execution of docs/VERIFICATION_READONLY_PREFLIGHT_041.sql.
-- Migrations 001–041 are already applied by PostgreSQL quality.
-- Fixture addresses and ids are fictitious. The preflight file is inserted
-- by the runner at each RUN_PREFLIGHT line, with only its two placeholders
-- replaced. This file does not call a remote project.

-- BEGIN STANDALONE_CLEANUP
do $$
declare
  auth_ids uuid[] := array[
    '04120000-0000-4000-8000-0000000000a1'::uuid,
    '04120000-0000-4000-8000-0000000000a2'::uuid,
    '04120000-0000-4000-8000-0000000000b1'::uuid
  ];
  account_ids uuid[];
  person_ids uuid[];
  target record;
begin
  select
    coalesce(array_agg(account.id), '{}'),
    coalesce(array_agg(account.person_id), '{}')
    into account_ids, person_ids
    from public.user_accounts as account
   where account.auth_user_id = any (auth_ids);

  delete from public.verification_evidence as evidence
   where evidence.submitted_by_account_id = any (account_ids)
      or evidence.identity_case_id in (
        select identity_case.id
          from public.identity_verification_cases as identity_case
         where identity_case.submitted_by_account_id = any (account_ids)
            or identity_case.subject_person_id = any (person_ids)
      )
      or evidence.ownership_claim_id in (
        select claim.id
          from public.equine_ownership_claims as claim
         where claim.submitted_by_account_id = any (account_ids)
            or claim.owner_person_id = any (person_ids)
      )
      or evidence.management_claim_id in (
        select claim.id
          from public.equine_management_authority_claims as claim
         where claim.submitted_by_account_id = any (account_ids)
            or claim.manager_person_id = any (person_ids)
      );

  delete from public.identity_verification_cases as identity_case
   where identity_case.submitted_by_account_id = any (account_ids)
      or identity_case.subject_person_id = any (person_ids);

  delete from public.equine_ownership_claims as claim
   where claim.submitted_by_account_id = any (account_ids)
      or claim.owner_person_id = any (person_ids);

  delete from public.equine_management_authority_claims as claim
   where claim.submitted_by_account_id = any (account_ids)
      or claim.manager_person_id = any (person_ids);

  delete from public.equine_ownerships as ownership
   where ownership.owner_person_id = any (person_ids);

  delete from public.equine_management_assignments as assignment
   where assignment.manager_person_id = any (person_ids)
      or assignment.granted_by_person_id = any (person_ids);

  delete from public.equines
   where id in (
     '04120000-0000-4000-8000-0000000000e1',
     '04120000-0000-4000-8000-0000000000e2'
   );

  delete from public.verification_review_grants as grant_row
   where grant_row.id = '04120000-0000-4000-8000-0000000000f1'
      or grant_row.reviewer_person_id = any (person_ids);

  alter table public.verification_review_cohorts
    disable trigger verification_review_cohorts_composition;
  begin
    delete from public.verification_review_cohorts
     where code = 'PREFLIGHT041';
    alter table public.verification_review_cohorts
      enable trigger verification_review_cohorts_composition;
  exception
    when others then
      alter table public.verification_review_cohorts
        enable trigger verification_review_cohorts_composition;
      raise;
  end;

  delete from public.user_accounts as account
   where account.id = any (account_ids);

  delete from public.persons as person
   where person.id = any (person_ids);

  for target in
    select child.relname
      from pg_catalog.pg_class as child
      join pg_catalog.pg_namespace as child_namespace
        on child_namespace.oid = child.relnamespace
      join pg_catalog.pg_attribute as attribute
        on attribute.attrelid = child.oid
     where child_namespace.nspname = 'auth'
       and child.relkind = 'r'
       and child.relname <> 'users'
       and attribute.attname = 'user_id'
       and attribute.atttypid = 'uuid'::regtype
       and attribute.attnum > 0
       and not attribute.attisdropped
  loop
    execute format(
      'delete from auth.%I where user_id = any ($1)',
      target.relname
    ) using auth_ids;
  end loop;

  delete from auth.users
   where id = any (auth_ids);
end;
$$;
-- END STANDALONE_CLEANUP

create or replace function pg_temp.preflight_prepare(p_mode text)
returns void
language plpgsql
set search_path = pg_catalog, public
as $$
declare
  auth_a uuid := '04120000-0000-4000-8000-0000000000a1';
  auth_b uuid := '04120000-0000-4000-8000-0000000000b1';
  equine_a uuid := '04120000-0000-4000-8000-0000000000e1';
  equine_b uuid := '04120000-0000-4000-8000-0000000000e2';
  ownership_a uuid := '04120000-0000-4000-8000-0000000000c1';
  ownership_b uuid := '04120000-0000-4000-8000-0000000000c2';
  assignment_a uuid := '04120000-0000-4000-8000-0000000000d1';
  person_a uuid;
  account_a uuid;
  person_b uuid;
  country_a text;
begin
  if p_mode <> 'missing_a' then
    insert into auth.users (id) values (auth_a);
  end if;
  insert into auth.users (id) values (auth_b);

  if p_mode <> 'missing_a' then
    update auth.users
       set email = 'a.preflight@fixture.invalid'
     where id = auth_a;
  end if;

  update auth.users
     set email = 'b.preflight@fixture.invalid'
   where id = auth_b;

  if p_mode <> 'missing_a' then
    select account.person_id, account.id
      into person_a, account_a
      from public.user_accounts as account
     where account.auth_user_id = auth_a;
  end if;

  select account.person_id
    into person_b
    from public.user_accounts as account
   where account.auth_user_id = auth_b;

  country_a := case p_mode
    when 'null_country' then null
    when 'other_country' then 'ZZ'
    else 'ES'
  end;

  if p_mode <> 'missing_a' then
    update public.persons
       set country_code = country_a
     where id = person_a;
  end if;
  update public.persons
     set country_code = 'ES'
   where id = person_b;

  if p_mode in (
    'valid',
    'null_country',
    'other_country',
    'prior_cohort',
    'prior_grant',
    'multiple_dossiers'
  ) then
    insert into public.equines (id, name, equine_type)
    values (equine_a, 'Preflight Horse', 'HORSE');

    insert into public.equine_ownerships (
      id, equine_id, owner_type, owner_person_id, ownership_percentage,
      status, started_at
    ) values (
      ownership_a, equine_a, 'PERSON', person_a, 100, 'ACTIVE',
      timestamptz '2020-01-01 00:00:00+00'
    );

    insert into public.equine_management_assignments (
      id, equine_id, manager_type, manager_person_id, management_role,
      status, valid_from, granted_by_person_id
    ) values (
      assignment_a, equine_a, 'PERSON', person_a, 'PRIMARY_MANAGER',
      'ACTIVE', timestamptz '2020-01-01 00:00:00+00', person_a
    );

    insert into public.identity_verification_cases (
      subject_person_id, market_country_code, state, submitted_by_account_id
    ) values (
      person_a, 'ES', 'SUBMITTED', account_a
    );

    insert into public.equine_ownership_claims (
      equine_id, market_country_code, state, owner_type, owner_person_id,
      ownership_percentage, effective_ownership_id, submitted_by_account_id
    ) values (
      equine_a, 'ES', 'SUBMITTED', 'PERSON', person_a,
      100, ownership_a, account_a
    );

    insert into public.equine_management_authority_claims (
      equine_id, market_country_code, state, manager_type, manager_person_id,
      management_role, valid_from, valid_until, effective_assignment_id,
      submitted_by_account_id
    ) values (
      equine_a, 'ES', 'SUBMITTED', 'PERSON', person_a,
      'PRIMARY_MANAGER', timestamptz '2020-01-01 00:00:00+00', null,
      assignment_a, account_a
    );
  end if;

  if p_mode = 'multiple_dossiers' then
    insert into public.equines (id, name, equine_type)
    values (equine_b, 'Preflight Pony', 'PONY');

    insert into public.equine_ownerships (
      id, equine_id, owner_type, owner_person_id, ownership_percentage,
      status, started_at
    ) values (
      ownership_b, equine_b, 'PERSON', person_a, 100, 'ACTIVE',
      timestamptz '2020-01-01 00:00:00+00'
    );

    insert into public.equine_ownership_claims (
      equine_id, market_country_code, state, owner_type, owner_person_id,
      ownership_percentage, effective_ownership_id, submitted_by_account_id
    ) values (
      equine_b, 'ES', 'SUBMITTED', 'PERSON', person_a,
      100, ownership_b, account_a
    );
  end if;

  if p_mode = 'prior_cohort' then
    insert into public.verification_review_cohorts (
      code, market_country_code, composition_status
    ) values (
      'PREFLIGHT041', 'ES', 'OPEN'
    );
  end if;

  if p_mode = 'prior_grant' then
    insert into public.verification_review_grants (
      id, reviewer_person_id, scope_type, market_country_code, status
    ) values (
      '04120000-0000-4000-8000-0000000000f1',
      person_b, 'MARKET', 'ES', 'ACTIVE'
    );
  end if;
end;
$$;

create or replace function pg_temp.preflight_mark()
returns void
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  drop table if exists pg_temp.preflight_baseline;
  create temp table preflight_baseline as
  select
    (select count(*) from public.verification_review_cohorts) as cohorts,
    (select count(*) from public.verification_review_cohort_cases) as cohort_cases,
    (select count(*) from public.verification_review_cohort_events) as cohort_events,
    (select count(*) from public.verification_review_grants) as grants,
    (select count(*) from public.verification_review_grant_events) as grant_events,
    (select count(*) from public.identity_verification_cases) as identity_cases,
    (select count(*) from public.identity_verification_decisions) as identity_decisions,
    (select count(*) from public.equine_ownership_claims) as ownership_claims,
    (select count(*) from public.equine_management_authority_claims) as management_claims,
    (select count(*) from public.equine_relationship_decisions) as relationship_decisions,
    (select count(*) from public.verification_evidence) as evidence_rows,
    (select count(*) from public.audit_events) as audit_events,
    (select count(*) from public.persons) as persons,
    (select count(*) from public.user_accounts) as accounts,
    (select count(*) from auth.users) as auth_users,
    (select count(*) from public.equines) as equines,
    (select count(*) from public.equine_ownerships) as ownerships,
    (select count(*) from public.equine_management_assignments) as assignments,
    (select count(*) from supabase_migrations.schema_migrations) as schema_versions;
end;
$$;

create or replace function pg_temp.preflight_assert_unchanged()
returns void
language plpgsql
set search_path = pg_catalog, public
as $$
declare
  changed boolean;
begin
  if current_setting('transaction_read_only') is distinct from 'off' then
    raise exception 'preflight left a read only transaction open';
  end if;

  select
    (select count(*) from public.verification_review_cohorts) is distinct from baseline.cohorts
    or (select count(*) from public.verification_review_cohort_cases) is distinct from baseline.cohort_cases
    or (select count(*) from public.verification_review_cohort_events) is distinct from baseline.cohort_events
    or (select count(*) from public.verification_review_grants) is distinct from baseline.grants
    or (select count(*) from public.verification_review_grant_events) is distinct from baseline.grant_events
    or (select count(*) from public.identity_verification_cases) is distinct from baseline.identity_cases
    or (select count(*) from public.identity_verification_decisions) is distinct from baseline.identity_decisions
    or (select count(*) from public.equine_ownership_claims) is distinct from baseline.ownership_claims
    or (select count(*) from public.equine_management_authority_claims) is distinct from baseline.management_claims
    or (select count(*) from public.equine_relationship_decisions) is distinct from baseline.relationship_decisions
    or (select count(*) from public.verification_evidence) is distinct from baseline.evidence_rows
    or (select count(*) from public.audit_events) is distinct from baseline.audit_events
    or (select count(*) from public.persons) is distinct from baseline.persons
    or (select count(*) from public.user_accounts) is distinct from baseline.accounts
    or (select count(*) from auth.users) is distinct from baseline.auth_users
    or (select count(*) from public.equines) is distinct from baseline.equines
    or (select count(*) from public.equine_ownerships) is distinct from baseline.ownerships
    or (select count(*) from public.equine_management_assignments) is distinct from baseline.assignments
    or (select count(*) from supabase_migrations.schema_migrations) is distinct from baseline.schema_versions
    into changed
    from pg_temp.preflight_baseline as baseline;

  if changed then
    raise exception 'preflight persisted a database change';
  end if;
end;
$$;

-- RUN_CLEANUP
select pg_temp.preflight_prepare('valid');
select pg_temp.preflight_mark();
-- EXPECT technical_principal PASS
-- EXPECT transaction_is_read_only PASS
-- EXPECT schema_exact_041 STOP
-- EXPECT bootstrap_signature PASS
-- EXPECT bootstrap_not_client_executable PASS
-- EXPECT clean_start_inventory PASS
-- EXPECT two_distinct_active_accounts PASS
-- EXPECT both_identity_markets_es PASS
-- EXPECT applicant_open_case_set PASS
-- EXPECT ownership_effective_row PASS
-- EXPECT management_effective_row PASS
-- EXPECT management_valid_until_null PASS
-- EXPECT reviewer_has_no_conflict PASS
-- EXPECT evidence_predicate_read PASS
-- EXPECT_DETAIL evidence_predicate_read identity=false
-- EXPECT section_b_remains_unauthorized STOP
-- EXPECT_MARK section_b_remains_unauthorized NOT_AUTHORIZED
-- RUN_PREFLIGHT a.preflight@fixture.invalid b.preflight@fixture.invalid
select pg_temp.preflight_assert_unchanged();

-- RUN_CLEANUP
select pg_temp.preflight_prepare('missing_a');
select pg_temp.preflight_mark();
-- EXPECT technical_principal PASS
-- EXPECT transaction_is_read_only PASS
-- EXPECT schema_exact_041 STOP
-- EXPECT bootstrap_signature PASS
-- EXPECT bootstrap_not_client_executable PASS
-- EXPECT clean_start_inventory PASS
-- EXPECT two_distinct_active_accounts STOP
-- EXPECT both_identity_markets_es STOP
-- EXPECT applicant_open_case_set STOP
-- EXPECT_MARK applicant_open_case_set DECISION_REQUIRED
-- EXPECT ownership_effective_row STOP
-- EXPECT management_effective_row STOP
-- EXPECT management_valid_until_null STOP
-- EXPECT reviewer_has_no_conflict STOP
-- EXPECT evidence_predicate_read STOP
-- EXPECT section_b_remains_unauthorized STOP
-- RUN_PREFLIGHT missing.preflight@fixture.invalid b.preflight@fixture.invalid
select pg_temp.preflight_assert_unchanged();

-- RUN_CLEANUP
select pg_temp.preflight_prepare('null_country');
select pg_temp.preflight_mark();
-- EXPECT technical_principal PASS
-- EXPECT transaction_is_read_only PASS
-- EXPECT schema_exact_041 STOP
-- EXPECT bootstrap_signature PASS
-- EXPECT bootstrap_not_client_executable PASS
-- EXPECT clean_start_inventory PASS
-- EXPECT two_distinct_active_accounts PASS
-- EXPECT both_identity_markets_es STOP
-- EXPECT applicant_open_case_set PASS
-- EXPECT ownership_effective_row PASS
-- EXPECT management_effective_row PASS
-- EXPECT management_valid_until_null PASS
-- EXPECT reviewer_has_no_conflict PASS
-- EXPECT evidence_predicate_read PASS
-- EXPECT section_b_remains_unauthorized STOP
-- RUN_PREFLIGHT a.preflight@fixture.invalid b.preflight@fixture.invalid
select pg_temp.preflight_assert_unchanged();

-- RUN_CLEANUP
select pg_temp.preflight_prepare('other_country');
select pg_temp.preflight_mark();
-- EXPECT technical_principal PASS
-- EXPECT transaction_is_read_only PASS
-- EXPECT schema_exact_041 STOP
-- EXPECT bootstrap_signature PASS
-- EXPECT bootstrap_not_client_executable PASS
-- EXPECT clean_start_inventory PASS
-- EXPECT two_distinct_active_accounts PASS
-- EXPECT both_identity_markets_es STOP
-- EXPECT applicant_open_case_set PASS
-- EXPECT ownership_effective_row PASS
-- EXPECT management_effective_row PASS
-- EXPECT management_valid_until_null PASS
-- EXPECT reviewer_has_no_conflict PASS
-- EXPECT evidence_predicate_read PASS
-- EXPECT section_b_remains_unauthorized STOP
-- RUN_PREFLIGHT a.preflight@fixture.invalid b.preflight@fixture.invalid
select pg_temp.preflight_assert_unchanged();

-- RUN_CLEANUP
select pg_temp.preflight_prepare('prior_cohort');
select pg_temp.preflight_mark();
-- EXPECT technical_principal PASS
-- EXPECT transaction_is_read_only PASS
-- EXPECT schema_exact_041 STOP
-- EXPECT bootstrap_signature PASS
-- EXPECT bootstrap_not_client_executable PASS
-- EXPECT clean_start_inventory OPERATOR_ESCALATION_REQUIRED
-- EXPECT two_distinct_active_accounts PASS
-- EXPECT both_identity_markets_es PASS
-- EXPECT applicant_open_case_set PASS
-- EXPECT ownership_effective_row PASS
-- EXPECT management_effective_row PASS
-- EXPECT management_valid_until_null PASS
-- EXPECT reviewer_has_no_conflict PASS
-- EXPECT evidence_predicate_read PASS
-- EXPECT section_b_remains_unauthorized STOP
-- RUN_PREFLIGHT a.preflight@fixture.invalid b.preflight@fixture.invalid
select pg_temp.preflight_assert_unchanged();

-- RUN_CLEANUP
select pg_temp.preflight_prepare('prior_grant');
select pg_temp.preflight_mark();
-- EXPECT technical_principal PASS
-- EXPECT transaction_is_read_only PASS
-- EXPECT schema_exact_041 STOP
-- EXPECT bootstrap_signature PASS
-- EXPECT bootstrap_not_client_executable PASS
-- EXPECT clean_start_inventory OPERATOR_ESCALATION_REQUIRED
-- EXPECT two_distinct_active_accounts PASS
-- EXPECT both_identity_markets_es PASS
-- EXPECT applicant_open_case_set PASS
-- EXPECT ownership_effective_row PASS
-- EXPECT management_effective_row PASS
-- EXPECT management_valid_until_null PASS
-- EXPECT reviewer_has_no_conflict PASS
-- EXPECT evidence_predicate_read PASS
-- EXPECT section_b_remains_unauthorized STOP
-- RUN_PREFLIGHT a.preflight@fixture.invalid b.preflight@fixture.invalid
select pg_temp.preflight_assert_unchanged();

-- RUN_CLEANUP
select pg_temp.preflight_prepare('missing_dossier');
select pg_temp.preflight_mark();
-- EXPECT technical_principal PASS
-- EXPECT transaction_is_read_only PASS
-- EXPECT schema_exact_041 STOP
-- EXPECT bootstrap_signature PASS
-- EXPECT bootstrap_not_client_executable PASS
-- EXPECT clean_start_inventory PASS
-- EXPECT two_distinct_active_accounts PASS
-- EXPECT both_identity_markets_es PASS
-- EXPECT applicant_open_case_set STOP
-- EXPECT_MARK applicant_open_case_set DECISION_REQUIRED
-- EXPECT ownership_effective_row STOP
-- EXPECT management_effective_row STOP
-- EXPECT management_valid_until_null STOP
-- EXPECT reviewer_has_no_conflict STOP
-- EXPECT evidence_predicate_read STOP
-- EXPECT section_b_remains_unauthorized STOP
-- RUN_PREFLIGHT a.preflight@fixture.invalid b.preflight@fixture.invalid
select pg_temp.preflight_assert_unchanged();

-- RUN_CLEANUP
select pg_temp.preflight_prepare('multiple_dossiers');
select pg_temp.preflight_mark();
-- EXPECT technical_principal PASS
-- EXPECT transaction_is_read_only PASS
-- EXPECT schema_exact_041 STOP
-- EXPECT bootstrap_signature PASS
-- EXPECT bootstrap_not_client_executable PASS
-- EXPECT clean_start_inventory PASS
-- EXPECT two_distinct_active_accounts PASS
-- EXPECT both_identity_markets_es PASS
-- EXPECT applicant_open_case_set STOP
-- EXPECT_MARK applicant_open_case_set DECISION_REQUIRED
-- EXPECT ownership_effective_row STOP
-- EXPECT_MARK ownership_effective_row DECISION_REQUIRED
-- EXPECT management_effective_row PASS
-- EXPECT management_valid_until_null PASS
-- EXPECT reviewer_has_no_conflict STOP
-- EXPECT evidence_predicate_read STOP
-- EXPECT section_b_remains_unauthorized STOP
-- RUN_PREFLIGHT a.preflight@fixture.invalid b.preflight@fixture.invalid
select pg_temp.preflight_assert_unchanged();

-- RUN_CLEANUP
drop function pg_temp.preflight_prepare(text);
drop function pg_temp.preflight_mark();
drop function pg_temp.preflight_assert_unchanged();
