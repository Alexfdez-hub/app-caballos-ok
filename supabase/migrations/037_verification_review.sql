-- Stage 2. Submit, read, and review RPCs for identity cases and equine claims.
--
-- ACCOUNT and PERSON come only from auth.uid(). Reviewer, subject, and
-- submitter ids are not client parameters. This migration does not grant
-- or manage review grants, call a KYC vendor, store biometrics or KYC
-- documents, or write equine_ownerships / equine_management_assignments.

create function public.verification_resolve_caller()
returns table (
  account_id uuid,
  person_id uuid
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  current_auth_user_id uuid := auth.uid();
begin
  if current_auth_user_id is null then
    raise exception using
      errcode = '42501',
      message = 'Authentication required';
  end if;

  select account.id, account.person_id
    into account_id, person_id
    from public.user_accounts as account
    join public.persons as person
      on person.id = account.person_id
   where account.auth_user_id = current_auth_user_id
     and account.status = 'ACTIVE'
     and person.status = 'ACTIVE';

  if account_id is null or person_id is null then
    raise exception using
      errcode = '42501',
      message = 'Verification request is not available';
  end if;

  return next;
end;
$$;

comment on function public.verification_resolve_caller() is
  'Resolves the active ACCOUNT and PERSON from auth.uid(). Missing or suspended callers fail closed. Not executable by PUBLIC, anon or authenticated.';

revoke all on function public.verification_resolve_caller()
  from public, anon, authenticated;

create function public.verification_review_grant_matches(
  p_person_id uuid,
  p_domain text,
  p_market_country_code text
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1
      from public.verification_review_grants as grant_row
     where grant_row.reviewer_person_id = p_person_id
       and grant_row.status = 'ACTIVE'
       and grant_row.valid_from <= now()
       and (
         (
           p_domain = 'IDENTITY'
           and grant_row.scope_type = 'PLATFORM_IDENTITY'
         )
         or (
           p_domain = 'EQUINE'
           and grant_row.scope_type = 'PLATFORM_EQUINE'
         )
         or (
           grant_row.scope_type = 'MARKET'
           and grant_row.market_country_code = p_market_country_code
         )
       )
  );
$$;

comment on function public.verification_review_grant_matches(uuid, text, text) is
  'True when the person has a current grant for the domain, or a MARKET grant for that country. Does not create grants. Not executable by PUBLIC, anon or authenticated.';

revoke all on function public.verification_review_grant_matches(uuid, text, text)
  from public, anon, authenticated;

create function public.verification_person_acts_for_center(
  p_person_id uuid,
  p_center_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select p_center_id is not null
     and exists (
       select 1
         from public.center_memberships as membership
        where membership.person_id = p_person_id
          and membership.center_id = p_center_id
          and membership.status = 'ACTIVE'
     );
$$;

comment on function public.verification_person_acts_for_center(uuid, uuid) is
  'True when the person has an active membership at the center. Membership is not a review grant. Not executable by PUBLIC, anon or authenticated.';

revoke all on function public.verification_person_acts_for_center(uuid, uuid)
  from public, anon, authenticated;

create function public.verification_has_current_identity_acceptance(
  p_person_id uuid,
  p_market_country_code text,
  p_except_case_id uuid,
  p_as_of timestamptz
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1
      from public.identity_verification_cases as other_case
      join lateral (
        select decision.outcome, decision.expires_at
          from public.identity_verification_decisions as decision
         where decision.case_id = other_case.id
         order by decision.decided_at desc, decision.id desc
         limit 1
      ) as latest on true
     where other_case.subject_person_id = p_person_id
       and other_case.market_country_code = p_market_country_code
       and other_case.id is distinct from p_except_case_id
       and latest.outcome = 'ACCEPTED'
       and (
         latest.expires_at is null
         or latest.expires_at > p_as_of
       )
  );
$$;

comment on function public.verification_has_current_identity_acceptance(uuid, text, uuid, timestamptz) is
  'True when another case for the same PERSON and market has a latest ACCEPTED decision that is still current. expires_at null means no stored expiry. This does not choose a retention interval.';

revoke all on function public.verification_has_current_identity_acceptance(uuid, text, uuid, timestamptz)
  from public, anon, authenticated;

create function public.verification_has_current_ownership_acceptance(
  p_effective_ownership_id uuid,
  p_except_claim_id uuid,
  p_as_of timestamptz
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select p_effective_ownership_id is not null
     and exists (
       select 1
         from public.equine_ownership_claims as other_claim
         join lateral (
           select decision.outcome, decision.expires_at
             from public.equine_relationship_decisions as decision
            where decision.ownership_claim_id = other_claim.id
            order by decision.decided_at desc, decision.id desc
            limit 1
         ) as latest on true
        where other_claim.effective_ownership_id = p_effective_ownership_id
          and other_claim.id is distinct from p_except_claim_id
          and latest.outcome = 'ACCEPTED'
          and (
            latest.expires_at is null
            or latest.expires_at > p_as_of
          )
     );
$$;

comment on function public.verification_has_current_ownership_acceptance(uuid, uuid, timestamptz) is
  'True when another claim for the same effective ownership has a latest ACCEPTED decision that is still current. Does not set expires_at.';

revoke all on function public.verification_has_current_ownership_acceptance(uuid, uuid, timestamptz)
  from public, anon, authenticated;

create function public.verification_has_current_management_acceptance(
  p_effective_assignment_id uuid,
  p_except_claim_id uuid,
  p_as_of timestamptz
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select p_effective_assignment_id is not null
     and exists (
       select 1
         from public.equine_management_authority_claims as other_claim
         join lateral (
           select decision.outcome, decision.expires_at
             from public.equine_relationship_decisions as decision
            where decision.management_claim_id = other_claim.id
            order by decision.decided_at desc, decision.id desc
            limit 1
         ) as latest on true
        where other_claim.effective_assignment_id = p_effective_assignment_id
          and other_claim.id is distinct from p_except_claim_id
          and latest.outcome = 'ACCEPTED'
          and (
            latest.expires_at is null
            or latest.expires_at > p_as_of
          )
     );
$$;

comment on function public.verification_has_current_management_acceptance(uuid, uuid, timestamptz) is
  'True when another claim for the same effective assignment has a latest ACCEPTED decision that is still current. Does not set expires_at.';

revoke all on function public.verification_has_current_management_acceptance(uuid, uuid, timestamptz)
  from public, anon, authenticated;

create function public.submit_my_identity_case(
  p_market_country_code text
)
returns table (
  case_id uuid,
  state text,
  market_country_code text
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller_account uuid;
  caller_person uuid;
  normalized_market text := upper(btrim(coalesce(p_market_country_code, '')));
begin
  select resolved.account_id, resolved.person_id
    into caller_account, caller_person
    from public.verification_resolve_caller() as resolved;

  if not public.identity_market_is_selectable(normalized_market) then
    raise exception using
      errcode = '42501',
      message = 'Verification request is not available';
  end if;

  return query
  insert into public.identity_verification_cases (
    subject_person_id,
    market_country_code,
    state,
    submitted_by_account_id
  ) values (
    caller_person,
    normalized_market,
    'SUBMITTED',
    caller_account
  )
  returning
    identity_verification_cases.id,
    identity_verification_cases.state,
    identity_verification_cases.market_country_code;
end;
$$;

comment on function public.submit_my_identity_case(text) is
  'Submits an identity case for the caller PERSON in an explicit selectable market. Does not accept a subject or submitter id.';

create function public.submit_my_equine_ownership_claim(
  p_equine_id uuid,
  p_market_country_code text,
  p_owner_type text,
  p_owner_center_id uuid,
  p_ownership_percentage numeric,
  p_effective_ownership_id uuid
)
returns table (
  claim_id uuid,
  state text,
  market_country_code text
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller_account uuid;
  caller_person uuid;
  normalized_market text := upper(btrim(coalesce(p_market_country_code, '')));
  owner_person uuid;
begin
  select resolved.account_id, resolved.person_id
    into caller_account, caller_person
    from public.verification_resolve_caller() as resolved;

  if not public.identity_market_is_selectable(normalized_market)
     or p_owner_type not in ('PERSON', 'CENTER') then
    raise exception using
      errcode = '42501',
      message = 'Verification request is not available';
  end if;

  if p_owner_type = 'PERSON' then
    if p_owner_center_id is not null then
      raise exception using
        errcode = '42501',
        message = 'Verification request is not available';
    end if;
    owner_person := caller_person;
  else
    if p_owner_center_id is null
       or not public.verification_person_acts_for_center(
         caller_person,
         p_owner_center_id
       ) then
      raise exception using
        errcode = '42501',
        message = 'Verification request is not available';
    end if;
    owner_person := null;
  end if;

  if p_effective_ownership_id is not null and not exists (
    select 1
      from public.equine_ownerships as ownership
     where ownership.id = p_effective_ownership_id
       and ownership.equine_id = p_equine_id
       and (
         (
           p_owner_type = 'PERSON'
           and ownership.owner_person_id = owner_person
         )
         or (
           p_owner_type = 'CENTER'
           and ownership.owner_center_id = p_owner_center_id
         )
       )
  ) then
    raise exception using
      errcode = '42501',
      message = 'Verification request is not available';
  end if;

  begin
    return query
    insert into public.equine_ownership_claims (
      equine_id,
      market_country_code,
      state,
      owner_type,
      owner_person_id,
      owner_center_id,
      ownership_percentage,
      effective_ownership_id,
      submitted_by_account_id
    ) values (
      p_equine_id,
      normalized_market,
      'SUBMITTED',
      p_owner_type,
      owner_person,
      case when p_owner_type = 'CENTER' then p_owner_center_id else null end,
      p_ownership_percentage,
      p_effective_ownership_id,
      caller_account
    )
    returning
      equine_ownership_claims.id,
      equine_ownership_claims.state,
      equine_ownership_claims.market_country_code;
  exception
    when check_violation or foreign_key_violation or not_null_violation then
      raise exception using
        errcode = '42501',
        message = 'Verification request is not available';
  end;
end;
$$;

comment on function public.submit_my_equine_ownership_claim(uuid, text, text, uuid, numeric, uuid) is
  'Submits an ownership claim. A PERSON owner is the caller. A CENTER claim requires the caller''s active affiliation with that center. Affiliation is not review authority. Does not write equine_ownerships.';

create function public.submit_my_equine_management_claim(
  p_equine_id uuid,
  p_market_country_code text,
  p_manager_type text,
  p_manager_center_id uuid,
  p_management_role text,
  p_valid_from timestamptz,
  p_valid_until timestamptz,
  p_effective_assignment_id uuid
)
returns table (
  claim_id uuid,
  state text,
  market_country_code text
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller_account uuid;
  caller_person uuid;
  normalized_market text := upper(btrim(coalesce(p_market_country_code, '')));
  manager_person uuid;
begin
  select resolved.account_id, resolved.person_id
    into caller_account, caller_person
    from public.verification_resolve_caller() as resolved;

  if not public.identity_market_is_selectable(normalized_market)
     or p_manager_type not in ('PERSON', 'CENTER') then
    raise exception using
      errcode = '42501',
      message = 'Verification request is not available';
  end if;

  if p_manager_type = 'PERSON' then
    if p_manager_center_id is not null then
      raise exception using
        errcode = '42501',
        message = 'Verification request is not available';
    end if;
    manager_person := caller_person;
  else
    if p_manager_center_id is null
       or not public.verification_person_acts_for_center(
         caller_person,
         p_manager_center_id
       ) then
      raise exception using
        errcode = '42501',
        message = 'Verification request is not available';
    end if;
    manager_person := null;
  end if;

  if p_effective_assignment_id is not null and not exists (
    select 1
      from public.equine_management_assignments as assignment
     where assignment.id = p_effective_assignment_id
       and assignment.equine_id = p_equine_id
       and (
         (
           p_manager_type = 'PERSON'
           and assignment.manager_person_id = manager_person
         )
         or (
           p_manager_type = 'CENTER'
           and assignment.manager_center_id = p_manager_center_id
         )
       )
  ) then
    raise exception using
      errcode = '42501',
      message = 'Verification request is not available';
  end if;

  begin
    return query
    insert into public.equine_management_authority_claims (
      equine_id,
      market_country_code,
      state,
      manager_type,
      manager_person_id,
      manager_center_id,
      management_role,
      valid_from,
      valid_until,
      effective_assignment_id,
      submitted_by_account_id
    ) values (
      p_equine_id,
      normalized_market,
      'SUBMITTED',
      p_manager_type,
      manager_person,
      case when p_manager_type = 'CENTER' then p_manager_center_id else null end,
      p_management_role,
      p_valid_from,
      p_valid_until,
      p_effective_assignment_id,
      caller_account
    )
    returning
      equine_management_authority_claims.id,
      equine_management_authority_claims.state,
      equine_management_authority_claims.market_country_code;
  exception
    when check_violation or foreign_key_violation or not_null_violation then
      raise exception using
        errcode = '42501',
        message = 'Verification request is not available';
  end;
end;
$$;

comment on function public.submit_my_equine_management_claim(uuid, text, text, uuid, text, timestamptz, timestamptz, uuid) is
  'Submits a management-authority claim. A PERSON manager is the caller. A CENTER claim requires the caller''s active affiliation with that center. Affiliation is not review authority. Does not write equine_management_assignments.';

create function public.list_my_identity_cases()
returns table (
  case_id uuid,
  state text,
  market_country_code text,
  outcome text,
  reason_code text,
  decided_at timestamptz
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  caller_account uuid;
  caller_person uuid;
begin
  select resolved.account_id, resolved.person_id
    into caller_account, caller_person
    from public.verification_resolve_caller() as resolved;

  return query
  select
    subject_case.id,
    subject_case.state,
    subject_case.market_country_code,
    latest.outcome,
    latest.reason_code,
    latest.decided_at
    from public.identity_verification_cases as subject_case
    left join lateral (
      select
        decision.outcome,
        decision.reason_code,
        decision.decided_at
        from public.identity_verification_decisions as decision
       where decision.case_id = subject_case.id
       order by decision.decided_at desc
       limit 1
    ) as latest on true
   where subject_case.submitted_by_account_id = caller_account
      or subject_case.subject_person_id = caller_person;
end;
$$;

comment on function public.list_my_identity_cases() is
  'Caller-owned identity cases. Returns state, reason code, and timestamps only.';

create function public.list_my_equine_ownership_claims()
returns table (
  claim_id uuid,
  equine_id uuid,
  state text,
  market_country_code text,
  owner_type text,
  ownership_percentage numeric,
  outcome text,
  reason_code text,
  decided_at timestamptz
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  caller_account uuid;
begin
  select resolved.account_id
    into caller_account
    from public.verification_resolve_caller() as resolved;

  return query
  select
    claim.id,
    claim.equine_id,
    claim.state,
    claim.market_country_code,
    claim.owner_type,
    claim.ownership_percentage,
    latest.outcome,
    latest.reason_code,
    latest.decided_at
    from public.equine_ownership_claims as claim
    left join lateral (
      select
        decision.outcome,
        decision.reason_code,
        decision.decided_at
        from public.equine_relationship_decisions as decision
       where decision.ownership_claim_id = claim.id
       order by decision.decided_at desc
       limit 1
    ) as latest on true
   where claim.submitted_by_account_id = caller_account;
end;
$$;

comment on function public.list_my_equine_ownership_claims() is
  'Caller-submitted ownership claims. Omits reviewer identity and private evidence fields.';

create function public.list_my_equine_management_claims()
returns table (
  claim_id uuid,
  equine_id uuid,
  state text,
  market_country_code text,
  manager_type text,
  management_role text,
  outcome text,
  reason_code text,
  decided_at timestamptz
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  caller_account uuid;
begin
  select resolved.account_id
    into caller_account
    from public.verification_resolve_caller() as resolved;

  return query
  select
    claim.id,
    claim.equine_id,
    claim.state,
    claim.market_country_code,
    claim.manager_type,
    claim.management_role,
    latest.outcome,
    latest.reason_code,
    latest.decided_at
    from public.equine_management_authority_claims as claim
    left join lateral (
      select
        decision.outcome,
        decision.reason_code,
        decision.decided_at
        from public.equine_relationship_decisions as decision
       where decision.management_claim_id = claim.id
       order by decision.decided_at desc
       limit 1
    ) as latest on true
   where claim.submitted_by_account_id = caller_account;
end;
$$;

comment on function public.list_my_equine_management_claims() is
  'Caller-submitted management claims. Omits reviewer identity and private evidence fields.';

create function public.review_identity_case(
  p_case_id uuid,
  p_outcome text,
  p_reason_code text
)
returns table (
  case_id uuid,
  state text,
  outcome text,
  reason_code text,
  decided_at timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller_account uuid;
  caller_person uuid;
  subject_case public.identity_verification_cases%rowtype;
  decision_at timestamptz;
begin
  select resolved.account_id, resolved.person_id
    into caller_account, caller_person
    from public.verification_resolve_caller() as resolved;

  if p_outcome is null
     or p_outcome not in ('ACCEPTED', 'REJECTED')
     or p_reason_code is null
     or char_length(btrim(p_reason_code)) not between 1 and 80 then
    raise exception using
      errcode = '42501',
      message = 'Verification request is not available';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(371, pg_catalog.hashtext(p_case_id::text));

  select subject_case_row.*
    into subject_case
    from public.identity_verification_cases as subject_case_row
   where subject_case_row.id = p_case_id
   for update;

  if not found
     or subject_case.state not in ('SUBMITTED', 'IN_REVIEW', 'RESUBMITTED')
     or not public.verification_review_grant_matches(
       caller_person,
       'IDENTITY',
       subject_case.market_country_code
     )
     or caller_person = subject_case.subject_person_id
     or caller_account = subject_case.submitted_by_account_id then
    raise exception using
      errcode = '42501',
      message = 'Verification request is not available';
  end if;

  decision_at := clock_timestamp();

  if p_outcome = 'ACCEPTED' then
    perform pg_catalog.pg_advisory_xact_lock(
      374,
      pg_catalog.hashtext(
        subject_case.subject_person_id::text || ':' || subject_case.market_country_code
      )
    );

    if public.verification_has_current_identity_acceptance(
      subject_case.subject_person_id,
      subject_case.market_country_code,
      subject_case.id,
      decision_at
    ) then
      raise exception using
        errcode = '42501',
        message = 'Verification request is not available';
    end if;
  end if;

  update public.identity_verification_cases as open_case
     set state = p_outcome,
         updated_at = decision_at
   where open_case.id = p_case_id
     and open_case.state in ('SUBMITTED', 'IN_REVIEW', 'RESUBMITTED');

  if not found then
    raise exception using
      errcode = '42501',
      message = 'Verification request is not available';
  end if;

  begin
    insert into public.identity_verification_decisions (
      case_id,
      reviewer_account_id,
      reviewer_person_id,
      outcome,
      reason_code,
      decided_at
    ) values (
      p_case_id,
      caller_account,
      caller_person,
      p_outcome,
      btrim(p_reason_code),
      decision_at
    );
  exception
    when insufficient_privilege then
      raise exception using
        errcode = '42501',
        message = 'Verification request is not available';
  end;

  perform public.record_audit_event(
    'verification_case_reviewed',
    'identity_verification_case',
    p_case_id,
    jsonb_build_object(
      'outcome', p_outcome,
      'reason_code', btrim(p_reason_code)
    )
  );

  return query
  select
    p_case_id,
    p_outcome,
    p_outcome,
    btrim(p_reason_code),
    decision_at;
end;
$$;

comment on function public.review_identity_case(uuid, text, text) is
  'Reviews one identity case. The reviewer is auth.uid(). Acceptance serializes on PERSON plus market and refuses a second current acceptance. Decision and audit_events commit together. Does not set expires_at.';

create function public.review_equine_ownership_claim(
  p_claim_id uuid,
  p_outcome text,
  p_reason_code text
)
returns table (
  claim_id uuid,
  state text,
  outcome text,
  reason_code text,
  decided_at timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller_account uuid;
  caller_person uuid;
  claim public.equine_ownership_claims%rowtype;
  ownership public.equine_ownerships%rowtype;
  decision_at timestamptz;
begin
  select resolved.account_id, resolved.person_id
    into caller_account, caller_person
    from public.verification_resolve_caller() as resolved;

  if p_outcome is null
     or p_outcome not in ('ACCEPTED', 'REJECTED')
     or p_reason_code is null
     or char_length(btrim(p_reason_code)) not between 1 and 80 then
    raise exception using
      errcode = '42501',
      message = 'Verification request is not available';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(372, pg_catalog.hashtext(p_claim_id::text));

  select claim_row.*
    into claim
    from public.equine_ownership_claims as claim_row
   where claim_row.id = p_claim_id
   for update;

  if not found
     or claim.state not in ('SUBMITTED', 'IN_REVIEW', 'RESUBMITTED')
     or not public.verification_review_grant_matches(
       caller_person,
       'EQUINE',
       claim.market_country_code
     )
     or caller_person is not distinct from claim.owner_person_id
     or caller_account = claim.submitted_by_account_id
     or public.verification_person_acts_for_center(
       caller_person,
       claim.owner_center_id
     ) then
    raise exception using
      errcode = '42501',
      message = 'Verification request is not available';
  end if;

  decision_at := clock_timestamp();

  if p_outcome = 'ACCEPTED' then
    if claim.effective_ownership_id is null then
      raise exception using
        errcode = '42501',
        message = 'Verification request is not available';
    end if;

    perform pg_catalog.pg_advisory_xact_lock(
      375,
      pg_catalog.hashtext(claim.effective_ownership_id::text)
    );

    select ownership_row.*
      into ownership
      from public.equine_ownerships as ownership_row
     where ownership_row.id = claim.effective_ownership_id
     for update;

    if not found
       or ownership.status is distinct from 'ACTIVE'
       or ownership.ended_at is not null
       or ownership.started_at > decision_at
       or ownership.equine_id is distinct from claim.equine_id
       or ownership.owner_type is distinct from claim.owner_type
       or ownership.owner_person_id is distinct from claim.owner_person_id
       or ownership.owner_center_id is distinct from claim.owner_center_id
       or ownership.ownership_percentage is distinct from claim.ownership_percentage
       or public.verification_has_current_ownership_acceptance(
         claim.effective_ownership_id,
         claim.id,
         decision_at
       ) then
      raise exception using
        errcode = '42501',
        message = 'Verification request is not available';
    end if;
  end if;

  update public.equine_ownership_claims as open_claim
     set state = p_outcome,
         updated_at = decision_at
   where open_claim.id = p_claim_id
     and open_claim.state in ('SUBMITTED', 'IN_REVIEW', 'RESUBMITTED');

  if not found then
    raise exception using
      errcode = '42501',
      message = 'Verification request is not available';
  end if;

  begin
    insert into public.equine_relationship_decisions (
      claim_type,
      ownership_claim_id,
      reviewer_account_id,
      reviewer_person_id,
      outcome,
      reason_code,
      decided_at
    ) values (
      'OWNERSHIP',
      p_claim_id,
      caller_account,
      caller_person,
      p_outcome,
      btrim(p_reason_code),
      decision_at
    );
  exception
    when insufficient_privilege then
      raise exception using
        errcode = '42501',
        message = 'Verification request is not available';
  end;

  perform public.record_audit_event(
    'verification_ownership_claim_reviewed',
    'equine_ownership_claim',
    p_claim_id,
    jsonb_build_object(
      'outcome', p_outcome,
      'reason_code', btrim(p_reason_code)
    )
  );

  return query
  select
    p_claim_id,
    p_outcome,
    p_outcome,
    btrim(p_reason_code),
    decision_at;
end;
$$;

comment on function public.review_equine_ownership_claim(uuid, text, text) is
  'Reviews one ownership claim. Acceptance requires the locked current effective ownership to match equine, owner and percentage, and refuses a second current acceptance of that row. Rejection may describe an unlinked claim. Does not write equine_ownerships.';

create function public.review_equine_management_claim(
  p_claim_id uuid,
  p_outcome text,
  p_reason_code text
)
returns table (
  claim_id uuid,
  state text,
  outcome text,
  reason_code text,
  decided_at timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller_account uuid;
  caller_person uuid;
  claim public.equine_management_authority_claims%rowtype;
  assignment public.equine_management_assignments%rowtype;
  decision_at timestamptz;
begin
  select resolved.account_id, resolved.person_id
    into caller_account, caller_person
    from public.verification_resolve_caller() as resolved;

  if p_outcome is null
     or p_outcome not in ('ACCEPTED', 'REJECTED')
     or p_reason_code is null
     or char_length(btrim(p_reason_code)) not between 1 and 80 then
    raise exception using
      errcode = '42501',
      message = 'Verification request is not available';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(373, pg_catalog.hashtext(p_claim_id::text));

  select claim_row.*
    into claim
    from public.equine_management_authority_claims as claim_row
   where claim_row.id = p_claim_id
   for update;

  if not found
     or claim.state not in ('SUBMITTED', 'IN_REVIEW', 'RESUBMITTED')
     or not public.verification_review_grant_matches(
       caller_person,
       'EQUINE',
       claim.market_country_code
     )
     or caller_person is not distinct from claim.manager_person_id
     or caller_account = claim.submitted_by_account_id
     or public.verification_person_acts_for_center(
       caller_person,
       claim.manager_center_id
     ) then
    raise exception using
      errcode = '42501',
      message = 'Verification request is not available';
  end if;

  decision_at := clock_timestamp();

  if p_outcome = 'ACCEPTED' then
    if claim.effective_assignment_id is null then
      raise exception using
        errcode = '42501',
        message = 'Verification request is not available';
    end if;

    perform pg_catalog.pg_advisory_xact_lock(
      376,
      pg_catalog.hashtext(claim.effective_assignment_id::text)
    );

    select assignment_row.*
      into assignment
      from public.equine_management_assignments as assignment_row
     where assignment_row.id = claim.effective_assignment_id
     for update;

    if not found
       or assignment.status is distinct from 'ACTIVE'
       or assignment.valid_until is not null
       or assignment.valid_from > decision_at
       or assignment.equine_id is distinct from claim.equine_id
       or assignment.manager_type is distinct from claim.manager_type
       or assignment.manager_person_id is distinct from claim.manager_person_id
       or assignment.manager_center_id is distinct from claim.manager_center_id
       or assignment.management_role is distinct from claim.management_role
       or assignment.valid_from is distinct from claim.valid_from
       or assignment.valid_until is distinct from claim.valid_until
       or public.verification_has_current_management_acceptance(
         claim.effective_assignment_id,
         claim.id,
         decision_at
       ) then
      raise exception using
        errcode = '42501',
        message = 'Verification request is not available';
    end if;
  end if;

  update public.equine_management_authority_claims as open_claim
     set state = p_outcome,
         updated_at = decision_at
   where open_claim.id = p_claim_id
     and open_claim.state in ('SUBMITTED', 'IN_REVIEW', 'RESUBMITTED');

  if not found then
    raise exception using
      errcode = '42501',
      message = 'Verification request is not available';
  end if;

  begin
    insert into public.equine_relationship_decisions (
      claim_type,
      management_claim_id,
      reviewer_account_id,
      reviewer_person_id,
      outcome,
      reason_code,
      decided_at
    ) values (
      'MANAGEMENT',
      p_claim_id,
      caller_account,
      caller_person,
      p_outcome,
      btrim(p_reason_code),
      decision_at
    );
  exception
    when insufficient_privilege then
      raise exception using
        errcode = '42501',
        message = 'Verification request is not available';
  end;

  perform public.record_audit_event(
    'verification_management_claim_reviewed',
    'equine_management_authority_claim',
    p_claim_id,
    jsonb_build_object(
      'outcome', p_outcome,
      'reason_code', btrim(p_reason_code)
    )
  );

  return query
  select
    p_claim_id,
    p_outcome,
    p_outcome,
    btrim(p_reason_code),
    decision_at;
end;
$$;

comment on function public.review_equine_management_claim(uuid, text, text) is
  'Reviews one management claim. Acceptance requires the locked current effective assignment to match equine, manager, role and validity window, and refuses a second current acceptance of that row. Rejection may describe an unlinked claim. Does not write equine_management_assignments.';

revoke all on function public.submit_my_identity_case(text) from public, anon;
revoke all on function public.submit_my_equine_ownership_claim(uuid, text, text, uuid, numeric, uuid) from public, anon;
revoke all on function public.submit_my_equine_management_claim(uuid, text, text, uuid, text, timestamptz, timestamptz, uuid) from public, anon;
revoke all on function public.list_my_identity_cases() from public, anon;
revoke all on function public.list_my_equine_ownership_claims() from public, anon;
revoke all on function public.list_my_equine_management_claims() from public, anon;
revoke all on function public.review_identity_case(uuid, text, text) from public, anon;
revoke all on function public.review_equine_ownership_claim(uuid, text, text) from public, anon;
revoke all on function public.review_equine_management_claim(uuid, text, text) from public, anon;

grant execute on function public.submit_my_identity_case(text) to authenticated;
grant execute on function public.submit_my_equine_ownership_claim(uuid, text, text, uuid, numeric, uuid) to authenticated;
grant execute on function public.submit_my_equine_management_claim(uuid, text, text, uuid, text, timestamptz, timestamptz, uuid) to authenticated;
grant execute on function public.list_my_identity_cases() to authenticated;
grant execute on function public.list_my_equine_ownership_claims() to authenticated;
grant execute on function public.list_my_equine_management_claims() to authenticated;
grant execute on function public.review_identity_case(uuid, text, text) to authenticated;
grant execute on function public.review_equine_ownership_claim(uuid, text, text) to authenticated;
grant execute on function public.review_equine_management_claim(uuid, text, text) to authenticated;
