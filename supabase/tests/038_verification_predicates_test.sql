-- Stage 3. Read-only trust predicates. One transaction, then rollback.

begin;

insert into public.markets (country_code, status)
values ('FR', 'ACTIVE');

insert into auth.users (id) values
  ('03810000-0000-4000-8000-000000000001'),
  ('03810000-0000-4000-8000-000000000002'),
  ('03810000-0000-4000-8000-000000000003');

insert into public.equines (id, name, equine_type)
values ('03810000-0000-4000-8000-0000000000e1', 'Predicate Horse', 'HORSE');

do $$
declare
  subject_person uuid;
  subject_account uuid;
  other_person uuid;
  reviewer_person uuid;
  reviewer_account uuid;
  ownership_stamp text;
  stored_percentage numeric;
  ownership_owner uuid;
  function_name text;
begin
  select account.person_id, account.id
    into subject_person, subject_account
    from public.user_accounts as account
   where account.auth_user_id = '03810000-0000-4000-8000-000000000001';

  select account.person_id
    into other_person
    from public.user_accounts as account
   where account.auth_user_id = '03810000-0000-4000-8000-000000000002';

  select account.person_id, account.id
    into reviewer_person, reviewer_account
    from public.user_accounts as account
   where account.auth_user_id = '03810000-0000-4000-8000-000000000003';

  insert into public.equine_ownerships (
    id, equine_id, owner_type, owner_person_id, ownership_percentage,
    status, started_at
  ) values (
    '03810000-0000-4000-8000-0000000000a1',
    '03810000-0000-4000-8000-0000000000e1',
    'PERSON',
    subject_person,
    100,
    'ACTIVE',
    timestamptz '2020-01-01 00:00:00+00'
  );

  insert into public.equine_ownerships (
    id, equine_id, owner_type, owner_person_id, ownership_percentage,
    status, started_at
  ) values (
    '03810000-0000-4000-8000-0000000000a2',
    '03810000-0000-4000-8000-0000000000e1',
    'PERSON',
    other_person,
    50,
    'ACTIVE',
    timestamptz '2020-01-01 00:00:00+00'
  );

  insert into public.equine_management_assignments (
    id, equine_id, manager_type, manager_person_id, management_role,
    status, valid_from, granted_by_person_id
  ) values (
    '03810000-0000-4000-8000-0000000000b1',
    '03810000-0000-4000-8000-0000000000e1',
    'PERSON',
    subject_person,
    'PRIMARY_MANAGER',
    'ACTIVE',
    timestamptz '2020-01-01 00:00:00+00',
    subject_person
  );

  insert into public.identity_verification_cases (
    id, subject_person_id, market_country_code, state, submitted_by_account_id
  ) values (
    '03810000-0000-4000-8000-0000000000c1',
    subject_person,
    'ES',
    'SUBMITTED',
    subject_account
  );

  insert into public.equine_ownership_claims (
    id, equine_id, market_country_code, state, owner_type, owner_person_id,
    ownership_percentage, effective_ownership_id, submitted_by_account_id
  ) values (
    '03810000-0000-4000-8000-0000000000d1',
    '03810000-0000-4000-8000-0000000000e1',
    'ES',
    'SUBMITTED',
    'PERSON',
    subject_person,
    100,
    '03810000-0000-4000-8000-0000000000a1',
    subject_account
  );

  insert into public.equine_management_authority_claims (
    id, equine_id, market_country_code, state, manager_type, manager_person_id,
    management_role, valid_from, effective_assignment_id, submitted_by_account_id
  ) values (
    '03810000-0000-4000-8000-0000000000f1',
    '03810000-0000-4000-8000-0000000000e1',
    'ES',
    'SUBMITTED',
    'PERSON',
    subject_person,
    'PRIMARY_MANAGER',
    timestamptz '2020-01-01 00:00:00+00',
    '03810000-0000-4000-8000-0000000000b1',
    subject_account
  );

  foreach function_name in array array[
    'verification_identity_is_verified(uuid,text,timestamp with time zone)',
    'verification_ownership_is_verified(uuid,timestamp with time zone)',
    'verification_management_is_verified(uuid,timestamp with time zone)',
    'verification_center_corroboration_is_current(text,uuid,timestamp with time zone)'
  ]
  loop
    if has_function_privilege('anon', format('public.%s', function_name), 'EXECUTE')
       or has_function_privilege('authenticated', format('public.%s', function_name), 'EXECUTE') then
      raise exception 'Internal predicate % is client-executable', function_name;
    end if;
  end loop;

  if has_function_privilege('anon', 'public.list_my_verification_status()', 'EXECUTE')
     or not has_function_privilege('authenticated', 'public.list_my_verification_status()', 'EXECUTE') then
    raise exception 'Caller status RPC has the wrong execute grant';
  end if;

  if pg_catalog.pg_get_function_result('public.list_my_verification_status()'::regprocedure)
     ~* 'reviewer|provider_reference|storage_bucket|storage_path|reason_code' then
    raise exception 'Caller status RPC exposes a private field';
  end if;

  if public.verification_identity_is_verified(subject_person, 'ES', timestamptz '2024-01-01')
     or public.verification_identity_is_verified(subject_person, 'FR', timestamptz '2024-01-01')
     or public.verification_ownership_is_verified('03810000-0000-4000-8000-0000000000a1', timestamptz '2024-01-01')
     or public.verification_management_is_verified('03810000-0000-4000-8000-0000000000b1', timestamptz '2024-01-01') then
    raise exception 'Missing decisions were treated as verified';
  end if;

  insert into public.identity_verification_decisions (
    case_id, reviewer_account_id, reviewer_person_id, outcome, reason_code, decided_at
  ) values (
    '03810000-0000-4000-8000-0000000000c1',
    reviewer_account, reviewer_person, 'ACCEPTED', 'identity-current',
    timestamptz '2024-01-01 00:00:00+00'
  );

  if not public.verification_identity_is_verified(subject_person, 'ES', timestamptz '2024-06-01')
     or public.verification_identity_is_verified(subject_person, 'FR', timestamptz '2024-06-01')
     or public.verification_identity_is_verified(other_person, 'ES', timestamptz '2024-06-01') then
    raise exception 'Identity acceptance did not stay scoped to PERSON and market';
  end if;

  insert into public.identity_verification_decisions (
    case_id, reviewer_account_id, reviewer_person_id, outcome, reason_code, decided_at
  ) values (
    '03810000-0000-4000-8000-0000000000c1',
    reviewer_account, reviewer_person, 'REJECTED', 'identity-rejected',
    timestamptz '2024-02-01 00:00:00+00'
  );

  if public.verification_identity_is_verified(subject_person, 'ES', timestamptz '2024-06-01') then
    raise exception 'A later rejection still counted as verified';
  end if;

  insert into public.identity_verification_decisions (
    case_id, reviewer_account_id, reviewer_person_id, outcome, reason_code, decided_at
  ) values (
    '03810000-0000-4000-8000-0000000000c1',
    reviewer_account, reviewer_person, 'ACCEPTED', 'identity-again',
    timestamptz '2024-03-01 00:00:00+00'
  );

  if not public.verification_identity_is_verified(subject_person, 'ES', timestamptz '2024-06-01') then
    raise exception 'The latest acceptance did not win';
  end if;

  insert into public.identity_verification_decisions (
    case_id, reviewer_account_id, reviewer_person_id, outcome, reason_code, decided_at
  ) values (
    '03810000-0000-4000-8000-0000000000c1',
    reviewer_account, reviewer_person, 'REVOKED', 'identity-revoked',
    timestamptz '2024-04-01 00:00:00+00'
  );

  if public.verification_identity_is_verified(subject_person, 'ES', timestamptz '2024-06-01') then
    raise exception 'A later revocation still counted as verified';
  end if;

  insert into public.identity_verification_decisions (
    case_id, reviewer_account_id, reviewer_person_id, outcome, reason_code,
    decided_at, expires_at
  ) values (
    '03810000-0000-4000-8000-0000000000c1',
    reviewer_account, reviewer_person, 'ACCEPTED', 'identity-expired',
    timestamptz '2024-05-01 00:00:00+00',
    timestamptz '2024-05-02 00:00:00+00'
  );

  if public.verification_identity_is_verified(subject_person, 'ES', timestamptz '2024-06-01')
     or not public.verification_identity_is_verified(subject_person, 'ES', timestamptz '2024-05-01 12:00:00+00') then
    raise exception 'Expiry was not evaluated at the queried instant';
  end if;

  insert into public.equine_relationship_decisions (
    claim_type, ownership_claim_id, reviewer_account_id, reviewer_person_id,
    outcome, reason_code, decided_at
  ) values (
    'OWNERSHIP',
    '03810000-0000-4000-8000-0000000000d1',
    reviewer_account, reviewer_person, 'ACCEPTED', 'ownership-current',
    timestamptz '2024-01-01 00:00:00+00'
  );

  select ownership.status, ownership.ownership_percentage, ownership.owner_person_id
    into ownership_stamp, stored_percentage, ownership_owner
    from public.equine_ownerships as ownership
   where ownership.id = '03810000-0000-4000-8000-0000000000a1';

  if not public.verification_ownership_is_verified(
    '03810000-0000-4000-8000-0000000000a1',
    timestamptz '2024-06-01'
  ) then
    raise exception 'Matching current ownership was not verified';
  end if;

  if exists (
    select 1
      from public.equine_ownerships as ownership
     where ownership.id = '03810000-0000-4000-8000-0000000000a1'
       and (
         ownership.status is distinct from ownership_stamp
         or ownership.ownership_percentage is distinct from stored_percentage
         or ownership.owner_person_id is distinct from ownership_owner
       )
  ) then
    raise exception 'The ownership predicate wrote the effective row';
  end if;

  update public.equine_ownerships
     set status = 'ENDED',
         ended_at = timestamptz '2024-03-01 00:00:00+00'
   where id = '03810000-0000-4000-8000-0000000000a1';

  if public.verification_ownership_is_verified(
    '03810000-0000-4000-8000-0000000000a1',
    timestamptz '2024-06-01'
  ) then
    raise exception 'An ended ownership stayed verified';
  end if;

  update public.equine_ownerships
     set status = 'ACTIVE',
         ended_at = null,
         ownership_percentage = 40
   where id = '03810000-0000-4000-8000-0000000000a1';

  if public.verification_ownership_is_verified(
    '03810000-0000-4000-8000-0000000000a1',
    timestamptz '2024-06-01'
  ) then
    raise exception 'A different percentage stayed verified';
  end if;

  update public.equine_ownerships
     set ownership_percentage = 100,
         owner_person_id = reviewer_person
   where id = '03810000-0000-4000-8000-0000000000a1';

  if public.verification_ownership_is_verified(
    '03810000-0000-4000-8000-0000000000a1',
    timestamptz '2024-06-01'
  ) then
    raise exception 'A different owner stayed verified';
  end if;

  update public.equine_ownerships
     set owner_person_id = subject_person
   where id = '03810000-0000-4000-8000-0000000000a1';

  insert into public.equine_relationship_decisions (
    claim_type, ownership_claim_id, reviewer_account_id, reviewer_person_id,
    outcome, reason_code, decided_at, expires_at
  ) values (
    'OWNERSHIP',
    '03810000-0000-4000-8000-0000000000d1',
    reviewer_account, reviewer_person, 'ACCEPTED', 'ownership-expired',
    timestamptz '2024-05-01 00:00:00+00',
    timestamptz '2024-05-02 00:00:00+00'
  );

  if public.verification_ownership_is_verified(
    '03810000-0000-4000-8000-0000000000a1',
    timestamptz '2024-06-01'
  ) then
    raise exception 'An expired ownership acceptance stayed verified';
  end if;

  insert into public.equine_relationship_decisions (
    claim_type, ownership_claim_id, reviewer_account_id, reviewer_person_id,
    outcome, reason_code, decided_at
  ) values (
    'OWNERSHIP',
    '03810000-0000-4000-8000-0000000000d1',
    reviewer_account, reviewer_person, 'REVOKED', 'ownership-revoked',
    timestamptz '2024-07-01 00:00:00+00'
  );

  if public.verification_ownership_is_verified(
    '03810000-0000-4000-8000-0000000000a1',
    timestamptz '2024-08-01'
  ) then
    raise exception 'A revoked ownership acceptance stayed verified';
  end if;

  insert into public.equine_relationship_decisions (
    claim_type, ownership_claim_id, reviewer_account_id, reviewer_person_id,
    outcome, reason_code, decided_at
  ) values (
    'OWNERSHIP',
    '03810000-0000-4000-8000-0000000000d1',
    reviewer_account, reviewer_person, 'ACCEPTED', 'ownership-restored',
    timestamptz '2024-09-01 00:00:00+00'
  );

  insert into public.verification_evidence (
    parent_type, ownership_claim_id, category, storage_bucket, storage_path,
    submitted_by_account_id
  ) values (
    'OWNERSHIP_CLAIM',
    '03810000-0000-4000-8000-0000000000d1',
    'CENTER_CORROBORATION',
    'private-documents',
    'centers/secret-object-path',
    subject_account
  );

  if not public.verification_center_corroboration_is_current(
    'OWNERSHIP_CLAIM',
    '03810000-0000-4000-8000-0000000000d1',
    timestamptz '2024-10-01'
  ) then
    raise exception 'Current center corroboration was not derived from the accepted claim';
  end if;

  if public.verification_center_corroboration_is_current(
    'IDENTITY_CASE',
    '03810000-0000-4000-8000-0000000000c1',
    timestamptz '2024-10-01'
  ) then
    raise exception 'Center corroboration was treated as identity';
  end if;

  insert into public.equine_relationship_decisions (
    claim_type, management_claim_id, reviewer_account_id, reviewer_person_id,
    outcome, reason_code, decided_at
  ) values (
    'MANAGEMENT',
    '03810000-0000-4000-8000-0000000000f1',
    reviewer_account, reviewer_person, 'ACCEPTED', 'management-current',
    timestamptz '2024-01-01 00:00:00+00'
  );

  if not public.verification_management_is_verified(
    '03810000-0000-4000-8000-0000000000b1',
    timestamptz '2024-06-01'
  ) then
    raise exception 'Matching current management was not verified';
  end if;

  update public.equine_management_assignments
     set status = 'ENDED',
         valid_until = timestamptz '2024-03-01 00:00:00+00'
   where id = '03810000-0000-4000-8000-0000000000b1';

  if public.verification_management_is_verified(
    '03810000-0000-4000-8000-0000000000b1',
    timestamptz '2024-06-01'
  ) then
    raise exception 'An ended assignment stayed verified';
  end if;

  update public.equine_management_assignments
     set status = 'ACTIVE',
         valid_until = null,
         management_role = 'CO_MANAGER'
   where id = '03810000-0000-4000-8000-0000000000b1';

  if public.verification_management_is_verified(
    '03810000-0000-4000-8000-0000000000b1',
    timestamptz '2024-06-01'
  ) then
    raise exception 'A different management role stayed verified';
  end if;

  update public.equine_management_assignments
     set management_role = 'PRIMARY_MANAGER'
   where id = '03810000-0000-4000-8000-0000000000b1';

  if not public.verification_management_is_verified(
    '03810000-0000-4000-8000-0000000000b1',
    timestamptz '2024-06-01'
  ) then
    raise exception 'Restored management was not verified';
  end if;

  perform set_config('verification.predicate_reviewer', reviewer_person::text, true);
end;
$$;

select set_config('request.jwt.claim.sub', '03810000-0000-4000-8000-000000000001', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"03810000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
set local role authenticated;

do $$
declare
  listed text;
begin
  select string_agg(status_row::text, ' ')
    into listed
    from public.list_my_verification_status() as status_row;

  if listed like '%centers/secret-object-path%'
     or listed like '%private-documents%'
     or listed like '%' || current_setting('verification.predicate_reviewer') || '%'
     or not exists (
       select 1
         from public.list_my_verification_status() as status_row
        where status_row.subject_kind = 'OWNERSHIP'
          and status_row.effective_id = '03810000-0000-4000-8000-0000000000a1'
          and status_row.status_code = 'VERIFIED'
     )
     or not exists (
       select 1
         from public.list_my_verification_status() as status_row
        where status_row.subject_kind = 'MANAGEMENT'
          and status_row.status_code = 'VERIFIED'
     )
     or not exists (
       select 1
         from public.list_my_verification_status() as status_row
        where status_row.subject_kind = 'CENTER_CORROBORATION'
          and status_row.status_code = 'ATTESTED'
     )
     or exists (
       select 1
         from public.list_my_verification_status() as status_row
        where status_row.subject_kind = 'IDENTITY'
          and status_row.market_country_code = 'ES'
          and status_row.status_code = 'VERIFIED'
     ) then
    raise exception 'Caller status leaked private data or dropped a current result: %', listed;
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '03810000-0000-4000-8000-000000000002', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"03810000-0000-4000-8000-000000000002","role":"authenticated"}',
  true
);
set local role authenticated;

do $$
begin
  if exists (
    select 1
      from public.list_my_verification_status() as status_row
     where status_row.effective_id = '03810000-0000-4000-8000-0000000000a1'
        or status_row.market_country_code = 'ES'
  ) then
    raise exception 'Another caller can read this subject status';
  end if;

  perform count(*) from public.identity_verification_cases;
  raise exception using errcode = 'P0002', message = 'Authenticated table read was accepted';
exception
  when insufficient_privilege then
    null;
end;
$$;

rollback;
