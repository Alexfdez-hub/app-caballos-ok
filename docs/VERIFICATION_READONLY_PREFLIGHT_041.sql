-- Consolidated read-only preflight for the 041 verification pilot.
-- Not authorized against the remote database. Do not substitute real
-- addresses in Git. The result is verdicts and counts, not identifiers.
-- Section B of the runbook stays unauthorized even when earlier rows pass.

begin read only;

select set_config(
  'app.pilot_address_a',
  '<address-of-A-typed-in-this-session>',
  true
) is not null as address_a_accepted;

select set_config(
  'app.pilot_address_b',
  '<address-of-B-typed-in-this-session>',
  true
) is not null as address_b_accepted;

with typed as (
  select 'A'::text as party, current_setting('app.pilot_address_a', false) as address
  union all
  select 'B'::text, current_setting('app.pilot_address_b', false)
),
resolved as (
  select
    typed.party,
    person.id as person_id,
    person.status as person_status,
    person.country_code,
    account.id as account_id,
    account.status as account_status,
    auth_user.id as auth_user_id
  from typed
  left join auth.users as auth_user
    on auth_user.email = typed.address
  left join public.user_accounts as account
    on account.auth_user_id = auth_user.id
  left join public.persons as person
    on person.id = account.person_id
),
account_gate as (
  select
    (
      count(*) filter (where party = 'A') = 1
      and count(*) filter (where party = 'B') = 1
      and count(*) filter (where party = 'A' and person_id is not null) = 1
      and count(*) filter (where party = 'B' and person_id is not null) = 1
      and count(distinct person_id) filter (where person_id is not null) = 2
      and count(distinct account_id) filter (where account_id is not null) = 2
      and count(distinct auth_user_id) filter (where auth_user_id is not null) = 2
      and bool_and(person_status = 'ACTIVE') filter (where person_id is not null) is true
      and bool_and(account_status = 'ACTIVE') filter (where account_id is not null) is true
    ) as ok
  from resolved
),
-- person_id and account_id are uuid. PostgreSQL 15–17 have no max(uuid).
-- array_agg(...)[1] runs only after account_gate.ok proved a single row.
-- A failed gate leaves every chosen value null. array_agg does not
-- replace a null country_code with another country.
chosen as (
  select
    case
      when (select ok from account_gate) then (
        array_agg(person_id) filter (where party = 'A')
      )[1]
    end as person_a,
    case
      when (select ok from account_gate) then (
        array_agg(account_id) filter (where party = 'A')
      )[1]
    end as account_a,
    case
      when (select ok from account_gate) then (
        array_agg(country_code) filter (where party = 'A')
      )[1]
    end as country_a,
    case
      when (select ok from account_gate) then (
        array_agg(person_id) filter (where party = 'B')
      )[1]
    end as person_b,
    case
      when (select ok from account_gate) then (
        array_agg(account_id) filter (where party = 'B')
      )[1]
    end as account_b,
    case
      when (select ok from account_gate) then (
        array_agg(country_code) filter (where party = 'B')
      )[1]
    end as country_b
  from resolved
),
inventory as (
  select
    (select count(*) from public.verification_review_cohorts) as cohorts,
    (select count(*) from public.verification_review_cohort_cases) as cohort_cases,
    (select count(*) from public.verification_review_cohort_events) as cohort_events,
    (select count(*) from public.verification_review_grants) as grants,
    (select count(*) from public.verification_review_grant_events) as grant_events,
    (select count(*)
       from public.audit_events
      where event_type = 'verification_review_opened') as opened_audits,
    (select count(*) from public.identity_verification_decisions) as identity_decisions,
    (select count(*) from public.equine_relationship_decisions) as relationship_decisions
),
version_gate as (
  select
    (select max(version) from supabase_migrations.schema_migrations) as schema_version,
    exists (
      select 1
        from supabase_migrations.schema_migrations
       where version = '042'
    ) as has_042
),
signature_gate as (
  select
    count(*) = 1
    and bool_and(
      regexp_replace(
        pg_get_function_identity_arguments(p.oid),
        '[A-Za-z_][A-Za-z0-9_]* ',
        '',
        'g'
      ) = 'uuid, text'
    ) is true as ok
  from pg_proc as p
  join pg_namespace as n
    on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname = 'bootstrap_verification_review_grant'
),
client_execute as (
  select
    case
      when not signature_gate.ok then false
      else
        not has_function_privilege(
          'public',
          'public.bootstrap_verification_review_grant(uuid, text)',
          'EXECUTE'
        )
        and not has_function_privilege(
          'anon',
          'public.bootstrap_verification_review_grant(uuid, text)',
          'EXECUTE'
        )
        and not has_function_privilege(
          'authenticated',
          'public.bootstrap_verification_review_grant(uuid, text)',
          'EXECUTE'
        )
        and not has_function_privilege(
          'service_role',
          'public.bootstrap_verification_review_grant(uuid, text)',
          'EXECUTE'
        )
    end as blocked
  from signature_gate
),
identity_open as (
  select identity_case.id, identity_case.state
    from chosen
    join public.identity_verification_cases as identity_case
      on identity_case.subject_person_id = chosen.person_a
     and identity_case.submitted_by_account_id = chosen.account_a
   where chosen.person_a is not null
     and identity_case.market_country_code = 'ES'
     and identity_case.state in ('SUBMITTED', 'IN_REVIEW', 'RESUBMITTED')
),
ownership_open as (
  select claim.id, claim.state
    from chosen
    join public.equine_ownership_claims as claim
      on claim.owner_person_id = chosen.person_a
     and claim.submitted_by_account_id = chosen.account_a
   where chosen.person_a is not null
     and claim.owner_type = 'PERSON'
     and claim.owner_center_id is null
     and claim.market_country_code = 'ES'
     and claim.state in ('SUBMITTED', 'IN_REVIEW', 'RESUBMITTED')
),
management_open as (
  select claim.id, claim.state
    from chosen
    join public.equine_management_authority_claims as claim
      on claim.manager_person_id = chosen.person_a
     and claim.submitted_by_account_id = chosen.account_a
   where chosen.person_a is not null
     and claim.manager_type = 'PERSON'
     and claim.manager_center_id is null
     and claim.market_country_code = 'ES'
     and claim.state in ('SUBMITTED', 'IN_REVIEW', 'RESUBMITTED')
),
case_counts as (
  select
    (select count(*) from identity_open) as identity_open_count,
    (select count(*) from ownership_open) as ownership_open_count,
    (select count(*) from management_open) as management_open_count,
    (select count(*) from identity_open where state = 'SUBMITTED') as identity_submitted_count,
    (select count(*) from ownership_open where state = 'SUBMITTED') as ownership_submitted_count,
    (select count(*) from management_open where state = 'SUBMITTED') as management_submitted_count
),
single_cases as (
  select
    case
      when (select identity_open_count from case_counts) = 1
        then (select id from identity_open)
      else null
    end as identity_id,
    case
      when (select ownership_open_count from case_counts) = 1
        then (select id from ownership_open)
      else null
    end as ownership_id,
    case
      when (select management_open_count from case_counts) = 1
        then (select id from management_open)
      else null
    end as management_id
),
ownership_effective as (
  select
    ownership_claim.effective_ownership_id is not null as present,
    (
      ownership_claim.effective_ownership_id is not null
      and ownership.id is not null
      and ownership.status = 'ACTIVE'
      and ownership.ended_at is null
      and ownership.started_at <= pg_catalog.now()
      and ownership.equine_id = ownership_claim.equine_id
      and ownership.owner_type = 'PERSON'
      and ownership.owner_person_id = chosen.person_a
      and ownership.owner_center_id is null
      and ownership.ownership_percentage is not distinct from ownership_claim.ownership_percentage
    ) as matches
  from single_cases
  join chosen on true
  join public.equine_ownership_claims as ownership_claim
    on ownership_claim.id = single_cases.ownership_id
  left join public.equine_ownerships as ownership
    on ownership.id = ownership_claim.effective_ownership_id
),
management_effective as (
  select
    management_claim.effective_assignment_id is not null as present,
    management_claim.valid_until is null as claim_valid_until_null,
    assignment.valid_until is null as assignment_valid_until_null,
    (
      management_claim.effective_assignment_id is not null
      and assignment.id is not null
      and assignment.status = 'ACTIVE'
      and assignment.valid_from <= pg_catalog.now()
      and (
        assignment.valid_until is null
        or assignment.valid_until >= pg_catalog.now()
      )
      and assignment.equine_id = management_claim.equine_id
      and assignment.manager_type = 'PERSON'
      and assignment.manager_person_id = chosen.person_a
      and assignment.manager_center_id is null
      and assignment.management_role = management_claim.management_role
      and assignment.valid_from is not distinct from management_claim.valid_from
      and assignment.valid_until is not distinct from management_claim.valid_until
    ) as matches
  from single_cases
  join chosen on true
  join public.equine_management_authority_claims as management_claim
    on management_claim.id = single_cases.management_id
  left join public.equine_management_assignments as assignment
    on assignment.id = management_claim.effective_assignment_id
),
conflict as (
  select
    (
      identity_case.subject_person_id is not distinct from chosen.person_b
      or identity_case.submitted_by_account_id = chosen.account_b
      or ownership_claim.owner_person_id is not distinct from chosen.person_b
      or ownership_claim.submitted_by_account_id = chosen.account_b
      or public.verification_person_acts_for_center(
        chosen.person_b,
        ownership_claim.owner_center_id
      )
      or management_claim.manager_person_id is not distinct from chosen.person_b
      or management_claim.submitted_by_account_id = chosen.account_b
      or public.verification_person_acts_for_center(
        chosen.person_b,
        management_claim.manager_center_id
      )
      or chosen.person_a = chosen.person_b
    ) as blocked
  from single_cases
  join chosen on true
  join public.identity_verification_cases as identity_case
    on identity_case.id = single_cases.identity_id
  join public.equine_ownership_claims as ownership_claim
    on ownership_claim.id = single_cases.ownership_id
  join public.equine_management_authority_claims as management_claim
    on management_claim.id = single_cases.management_id
),
evidence as (
  select
    case
      when single_cases.identity_id is null then null
      else public.verification_case_evidence_is_sufficient(
        'IDENTITY_CASE',
        single_cases.identity_id
      )
    end as identity_sufficient,
    case
      when single_cases.ownership_id is null then null
      else public.verification_case_evidence_is_sufficient(
        'OWNERSHIP_CLAIM',
        single_cases.ownership_id
      )
    end as ownership_sufficient,
    case
      when single_cases.management_id is null then null
      else public.verification_case_evidence_is_sufficient(
        'MANAGEMENT_CLAIM',
        single_cases.management_id
      )
    end as management_sufficient,
    case
      when single_cases.identity_id is null
        or single_cases.ownership_id is null
        or single_cases.management_id is null then null
      else (
        select count(*)
          from public.verification_evidence as evidence_row
         where evidence_row.identity_case_id = single_cases.identity_id
            or evidence_row.ownership_claim_id = single_cases.ownership_id
            or evidence_row.management_claim_id = single_cases.management_id
      )
    end as evidence_rows
  from single_cases
),
checks as (
  select
    10 as sort_order,
    'technical_principal'::text as check_name,
    case when current_user = 'postgres' then 'PASS' else 'STOP' end as verdict,
    case when current_user = 'postgres' then 'PASS' else 'STOP' end as runbook_mark,
    current_user = 'postgres' as detail_ok
  union all
  select
    20,
    'transaction_is_read_only',
    case
      when current_setting('transaction_read_only') = 'on' then 'PASS'
      else 'STOP'
    end,
    case
      when current_setting('transaction_read_only') = 'on' then 'PASS'
      else 'STOP'
    end,
    current_setting('transaction_read_only') = 'on'
  union all
  select
    30,
    'schema_exact_041',
    case
      when schema_version = '041' and not has_042 then 'PASS'
      else 'STOP'
    end,
    case
      when schema_version = '041' and not has_042 then 'PASS'
      else 'STOP'
    end,
    schema_version = '041' and not has_042
  from version_gate
  union all
  select
    40,
    'bootstrap_signature',
    case when ok then 'PASS' else 'STOP' end,
    case when ok then 'PASS' else 'STOP' end,
    ok
  from signature_gate
  union all
  select
    50,
    'bootstrap_not_client_executable',
    case when blocked then 'PASS' else 'STOP' end,
    case when blocked then 'PASS' else 'STOP' end,
    blocked
  from client_execute
  union all
  select
    60,
    'clean_start_inventory',
    case
      when cohorts = 0
       and cohort_cases = 0
       and cohort_events = 0
       and grants = 0
       and grant_events = 0
        then 'PASS'
      else 'OPERATOR_ESCALATION_REQUIRED'
    end,
    case
      when cohorts = 0
       and cohort_cases = 0
       and cohort_events = 0
       and grants = 0
       and grant_events = 0
        then 'PASS'
      else 'OPERATOR_ESCALATION_REQUIRED'
    end,
    cohorts = 0
      and cohort_cases = 0
      and cohort_events = 0
      and grants = 0
      and grant_events = 0
  from inventory
  union all
  select
    70,
    'two_distinct_active_accounts',
    case when ok then 'PASS' else 'STOP' end,
    case when ok then 'PASS' else 'STOP' end,
    ok
  from account_gate
  union all
  select
    80,
    'both_identity_markets_es',
    case
      when (select ok from account_gate)
       and country_a = 'ES'
       and country_b = 'ES'
        then 'PASS'
      else 'STOP'
    end,
    case
      when (select ok from account_gate)
       and country_a = 'ES'
       and country_b = 'ES'
        then 'PASS'
      else 'STOP'
    end,
    (select ok from account_gate)
      and country_a = 'ES'
      and country_b = 'ES'
  from chosen
  union all
  select
    90,
    'applicant_open_case_set',
    case
      when identity_open_count = 1
       and ownership_open_count = 1
       and management_open_count = 1
        then 'PASS'
      else 'STOP'
    end,
    case
      when identity_open_count = 1
       and ownership_open_count = 1
       and management_open_count = 1
        then 'PASS'
      else 'DECISION_REQUIRED'
    end,
    identity_open_count = 1
      and ownership_open_count = 1
      and management_open_count = 1
  from case_counts
  union all
  select
    100,
    'ownership_effective_row',
    case
      when (select ownership_open_count from case_counts) <> 1 then 'STOP'
      when not present then 'STOP'
      when matches then 'PASS'
      else 'STOP'
    end,
    case
      when (select ownership_open_count from case_counts) <> 1 then 'DECISION_REQUIRED'
      when not present then 'DECISION_REQUIRED'
      when matches then 'PASS'
      else 'STOP'
    end,
    (select ownership_open_count from case_counts) = 1 and present and matches
  from ownership_effective
  union all
  select
    100,
    'ownership_effective_row',
    'STOP',
    'DECISION_REQUIRED',
    false
  where not exists (select 1 from ownership_effective)
  union all
  select
    110,
    'management_effective_row',
    case
      when (select management_open_count from case_counts) <> 1 then 'STOP'
      when not present then 'STOP'
      when matches then 'PASS'
      else 'STOP'
    end,
    case
      when (select management_open_count from case_counts) <> 1 then 'DECISION_REQUIRED'
      when not present then 'DECISION_REQUIRED'
      when matches then 'PASS'
      else 'STOP'
    end,
    (select management_open_count from case_counts) = 1 and present and matches
  from management_effective
  union all
  select
    110,
    'management_effective_row',
    'STOP',
    'DECISION_REQUIRED',
    false
  where not exists (select 1 from management_effective)
  union all
  select
    120,
    'management_valid_until_null',
    case
      when (select management_open_count from case_counts) <> 1 then 'STOP'
      when claim_valid_until_null then 'PASS'
      else 'STOP'
    end,
    case
      when (select management_open_count from case_counts) <> 1 then 'DECISION_REQUIRED'
      when claim_valid_until_null then 'PASS'
      else 'ARCHITECTURE_CONFLICT'
    end,
    (select management_open_count from case_counts) = 1 and claim_valid_until_null
  from management_effective
  union all
  select
    120,
    'management_valid_until_null',
    'STOP',
    'DECISION_REQUIRED',
    false
  where not exists (select 1 from management_effective)
  union all
  select
    130,
    'reviewer_has_no_conflict',
    case when blocked then 'STOP' else 'PASS' end,
    case when blocked then 'STOP' else 'PASS' end,
    not blocked
  from conflict
  union all
  select
    130,
    'reviewer_has_no_conflict',
    'STOP',
    'DECISION_REQUIRED',
    false
  where not exists (select 1 from conflict)
  union all
  select
    140,
    'evidence_predicate_read',
    case
      when identity_sufficient is null
        or ownership_sufficient is null
        or management_sufficient is null
        then 'STOP'
      else 'PASS'
    end,
    case
      when identity_sufficient is null
        or ownership_sufficient is null
        or management_sufficient is null
        then 'DECISION_REQUIRED'
      else 'NOT_A_GATE'
    end,
    identity_sufficient is not null
      and ownership_sufficient is not null
      and management_sufficient is not null
  from evidence
  union all
  select
    150,
    'section_b_remains_unauthorized',
    'STOP',
    'NOT_AUTHORIZED',
    false
)
select
  checks.sort_order,
  checks.check_name,
  checks.verdict,
  checks.runbook_mark,
  case checks.check_name
    when 'clean_start_inventory' then concat(
      'cohorts=', inventory.cohorts,
      ';cohort_cases=', inventory.cohort_cases,
      ';cohort_events=', inventory.cohort_events,
      ';grants=', inventory.grants,
      ';grant_events=', inventory.grant_events,
      ';opened_audits=', inventory.opened_audits,
      ';identity_decisions=', inventory.identity_decisions,
      ';relationship_decisions=', inventory.relationship_decisions
    )
    when 'applicant_open_case_set' then concat(
      'open=', case_counts.identity_open_count,
      '/', case_counts.ownership_open_count,
      '/', case_counts.management_open_count,
      ';submitted=', case_counts.identity_submitted_count,
      '/', case_counts.ownership_submitted_count,
      '/', case_counts.management_submitted_count
    )
    when 'management_valid_until_null' then concat(
      'claim_null=', coalesce(management_effective.claim_valid_until_null::text, 'not_evaluated'),
      ';assignment_null=', coalesce(management_effective.assignment_valid_until_null::text, 'not_evaluated')
    )
    when 'evidence_predicate_read' then concat(
      'identity=', coalesce(evidence.identity_sufficient::text, 'not_evaluated'),
      ';ownership=', coalesce(evidence.ownership_sufficient::text, 'not_evaluated'),
      ';management=', coalesce(evidence.management_sufficient::text, 'not_evaluated'),
      ';rows=', coalesce(evidence.evidence_rows::text, 'not_evaluated')
    )
    else checks.detail_ok::text
  end as detail
from checks
cross join inventory
cross join case_counts
left join management_effective on true
left join evidence on true
order by checks.sort_order, checks.check_name;

rollback;
