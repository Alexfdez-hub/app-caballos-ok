-- Stage 1 schema checks for migration 036. One transaction, then rollback.
-- No client RPC, no vendor, and no biometric payload.

begin;

do $$
declare
  forbidden text;
  role_name text;
  checked_table text;
  privilege_name text;
begin
  select string_agg(column_name, ', ' order by column_name)
    into forbidden
    from information_schema.columns
   where table_schema = 'public'
     and table_name in (
       'identity_verification_cases',
       'identity_verification_decisions',
       'equine_ownership_claims',
       'equine_management_authority_claims',
       'equine_relationship_decisions',
       'verification_evidence',
       'verification_review_grants'
     )
     and (
       data_type = 'bytea'
       or column_name ~* '(biometric|vendor|document_number|nationality|residence|jurisdiction)'
     );

  if forbidden is not null then
    raise exception 'Verification schema stores a forbidden column: %', forbidden;
  end if;

  if exists (
    select 1
      from pg_catalog.pg_proc as procedure
      join pg_catalog.pg_namespace as namespace
        on namespace.oid = procedure.pronamespace
     where namespace.nspname = 'public'
       and procedure.proname = 'enforce_verification_decision_immutability'
       and procedure.prosecdef
  ) then
    raise exception 'Verification decision trigger must stay SECURITY INVOKER';
  end if;

  foreach role_name in array array['anon', 'authenticated']
  loop
    foreach checked_table in array array[
      'identity_verification_cases',
      'identity_verification_decisions',
      'equine_ownership_claims',
      'equine_management_authority_claims',
      'equine_relationship_decisions',
      'verification_evidence',
      'verification_review_grants'
    ]
    loop
      foreach privilege_name in array array['SELECT', 'INSERT', 'UPDATE', 'DELETE']
      loop
        if has_table_privilege(
          role_name,
          format('public.%s', checked_table),
          privilege_name
        ) then
          raise exception '% retains % on %', role_name, privilege_name, checked_table;
        end if;
      end loop;
    end loop;

    if has_function_privilege(
      role_name,
      'public.enforce_verification_decision_immutability()',
      'EXECUTE'
    ) then
      raise exception '% can execute the verification decision trigger', role_name;
    end if;
  end loop;

  if has_function_privilege(
    'public',
    'public.enforce_verification_decision_immutability()',
    'EXECUTE'
  ) then
    raise exception 'public can execute the verification decision trigger';
  end if;
end;
$$;

insert into auth.users (id) values
  ('03610000-0000-4000-8000-000000000001'),
  ('03610000-0000-4000-8000-000000000002'),
  ('03610000-0000-4000-8000-000000000003');

do $$
declare
  subject_person uuid;
  subject_account uuid;
  reviewer_person uuid;
  reviewer_account uuid;
  other_person uuid;
  other_account uuid;
  case_id uuid;
  decision_id uuid;
  equine_id uuid;
  claim_id uuid;
  ownership_count integer;
  ownership_after integer;
begin
  select account.person_id, account.id
    into subject_person, subject_account
    from public.user_accounts as account
   where account.auth_user_id = '03610000-0000-4000-8000-000000000001';

  select account.person_id, account.id
    into reviewer_person, reviewer_account
    from public.user_accounts as account
   where account.auth_user_id = '03610000-0000-4000-8000-000000000002';

  select account.person_id, account.id
    into other_person, other_account
    from public.user_accounts as account
   where account.auth_user_id = '03610000-0000-4000-8000-000000000003';

  insert into public.identity_verification_cases (
    subject_person_id,
    market_country_code,
    state,
    submitted_by_account_id
  ) values (
    subject_person,
    'ES',
    'SUBMITTED',
    subject_account
  ) returning id into case_id;

  insert into public.verification_evidence (
    parent_type,
    identity_case_id,
    category,
    document_country_code,
    provider_reference,
    provider_outcome,
    assurance_level,
    submitted_by_account_id
  ) values (
    'IDENTITY_CASE',
    case_id,
    'IDENTITY_PROVIDER_REFERENCE',
    'FR',
    'opaque-reference',
    'accepted',
    'high',
    subject_account
  );

  begin
    insert into public.verification_evidence (
      parent_type,
      identity_case_id,
      category,
      provider_reference,
      storage_bucket,
      storage_path,
      submitted_by_account_id
    ) values (
      'IDENTITY_CASE',
      case_id,
      'IDENTITY_PROVIDER_REFERENCE',
      'opaque-reference',
      'private',
      'kyc/document.jpg',
      subject_account
    );
    raise exception using errcode = 'P0002', message = 'Identity evidence accepted a stored document';
  exception
    when check_violation then null;
  end;

  insert into public.identity_verification_decisions (
    case_id,
    outcome,
    reason_code,
    reviewer_account_id,
    reviewer_person_id,
    expires_at
  ) values (
    case_id,
    'ACCEPTED',
    'manual-review',
    reviewer_account,
    reviewer_person,
    null
  ) returning id into decision_id;

  begin
    update public.identity_verification_decisions
       set reason_code = 'changed'
     where id = decision_id;
    raise exception using errcode = 'P0002', message = 'Decision update was accepted';
  exception
    when insufficient_privilege then
      if sqlerrm is distinct from 'Verification decisions are append-only' then
        raise;
      end if;
  end;

  begin
    delete from public.identity_verification_decisions
     where id = decision_id;
    raise exception using errcode = 'P0002', message = 'Decision delete was accepted';
  exception
    when insufficient_privilege then
      if sqlerrm is distinct from 'Verification decisions are append-only' then
        raise;
      end if;
  end;

  begin
    insert into public.identity_verification_decisions (
      case_id,
      outcome,
      reason_code,
      reviewer_account_id,
      reviewer_person_id
    ) values (
      case_id,
      'ACCEPTED',
      'self',
      subject_account,
      subject_person
    );
    raise exception using errcode = 'P0002', message = 'Self approval was accepted';
  exception
    when insufficient_privilege then
      if sqlerrm is distinct from 'Verification review is not available' then
        raise;
      end if;
  end;

  begin
    insert into public.identity_verification_decisions (
      case_id,
      outcome,
      reason_code,
      reviewer_account_id,
      reviewer_person_id
    ) values (
      case_id,
      'ACCEPTED',
      'mismatch',
      other_account,
      reviewer_person
    );
    raise exception using errcode = 'P0002', message = 'Mismatched identity reviewer was accepted';
  exception
    when foreign_key_violation then null;
  end;

  begin
    insert into public.identity_verification_cases (
      subject_person_id,
      market_country_code,
      state
    ) values (
      subject_person,
      'ES',
      'DRAFT'
    );
    raise exception using errcode = 'P0002', message = 'Null case submitter was accepted';
  exception
    when not_null_violation then null;
  end;

  insert into public.equines (name, equine_type)
  values ('Foundation', 'HORSE')
  returning id into equine_id;

  select count(*) into ownership_count from public.equine_ownerships;

  insert into public.equine_ownership_claims (
    equine_id,
    market_country_code,
    state,
    owner_type,
    owner_person_id,
    ownership_percentage,
    submitted_by_account_id
  ) values (
    equine_id,
    'ES',
    'SUBMITTED',
    'PERSON',
    subject_person,
    100,
    subject_account
  ) returning id into claim_id;

  begin
    insert into public.equine_ownership_claims (
      equine_id,
      market_country_code,
      state,
      owner_type,
      owner_person_id,
      ownership_percentage
    ) values (
      equine_id,
      'ES',
      'SUBMITTED',
      'PERSON',
      subject_person,
      100
    );
    raise exception using errcode = 'P0002', message = 'Null ownership submitter was accepted';
  exception
    when not_null_violation then null;
  end;

  begin
    insert into public.equine_management_authority_claims (
      equine_id,
      market_country_code,
      state,
      manager_type,
      manager_person_id,
      management_role,
      valid_from
    ) values (
      equine_id,
      'ES',
      'SUBMITTED',
      'PERSON',
      subject_person,
      'PRIMARY_MANAGER',
      now()
    );
    raise exception using errcode = 'P0002', message = 'Null management submitter was accepted';
  exception
    when not_null_violation then null;
  end;

  begin
    insert into public.verification_evidence (
      parent_type,
      identity_case_id,
      category,
      provider_reference
    ) values (
      'IDENTITY_CASE',
      case_id,
      'IDENTITY_PROVIDER_REFERENCE',
      'opaque-without-actor'
    );
    raise exception using errcode = 'P0002', message = 'Null evidence submitter was accepted';
  exception
    when not_null_violation then null;
  end;

  begin
    insert into public.equine_relationship_decisions (
      claim_type,
      ownership_claim_id,
      outcome,
      reason_code,
      reviewer_account_id,
      reviewer_person_id
    ) values (
      'OWNERSHIP',
      claim_id,
      'ACCEPTED',
      'mismatch',
      other_account,
      reviewer_person
    );
    raise exception using errcode = 'P0002', message = 'Mismatched relationship reviewer was accepted';
  exception
    when foreign_key_violation then null;
  end;

  begin
    insert into public.equine_relationship_decisions (
      claim_type,
      ownership_claim_id,
      outcome,
      reason_code,
      reviewer_account_id,
      reviewer_person_id
    ) values (
      'OWNERSHIP',
      claim_id,
      'ACCEPTED',
      'self',
      subject_account,
      subject_person
    );
    raise exception using errcode = 'P0002', message = 'Ownership self approval was accepted';
  exception
    when insufficient_privilege then
      if sqlerrm is distinct from 'Verification review is not available' then
        raise;
      end if;
  end;

  insert into public.verification_evidence (
    parent_type,
    ownership_claim_id,
    category,
    storage_bucket,
    storage_path,
    submitted_by_account_id
  ) values (
    'OWNERSHIP_CLAIM',
    claim_id,
    'CENTER_CORROBORATION',
    'verification-evidence',
    'center/check',
    reviewer_account
  );

  select count(*) into ownership_after from public.equine_ownerships;
  if ownership_after is distinct from ownership_count then
    raise exception 'Center corroboration changed effective ownership';
  end if;
end;
$$;

set local role authenticated;

do $$
begin
  begin
    perform 1 from public.verification_evidence;
    raise exception using errcode = 'P0002', message = 'Authenticated read was accepted';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

reset role;

rollback;
