-- Stage 1 schema checks for migration 036. One transaction, then rollback.
-- No client RPC, no vendor, and no biometric payload.

begin;

do $$
declare
  forbidden text;
  leaked text;
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

  select string_agg(table_name, ', ' order by table_name)
    into leaked
    from information_schema.role_table_grants
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
     and grantee in ('anon', 'authenticated', 'public')
     and privilege_type in ('SELECT', 'INSERT', 'UPDATE', 'DELETE');

  if leaked is not null then
    raise exception 'Verification tables are readable by a client role: %', leaked;
  end if;
end;
$$;

insert into auth.users (id) values
  ('03610000-0000-4000-8000-000000000001'),
  ('03610000-0000-4000-8000-000000000002');

do $$
declare
  subject_person uuid;
  subject_account uuid;
  reviewer_person uuid;
  reviewer_account uuid;
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
      storage_path
    ) values (
      'IDENTITY_CASE',
      case_id,
      'IDENTITY_PROVIDER_REFERENCE',
      'opaque-reference',
      'private',
      'kyc/document.jpg'
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
