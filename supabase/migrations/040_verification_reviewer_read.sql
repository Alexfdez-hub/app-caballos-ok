-- Stage 4B.3. Read-only Spain-pilot review queue and authorized detail.
--
-- The caller is always auth.uid(). These functions do not accept an
-- account, a person, a scope, or a market. They do not decide a case,
-- write evidence, or sign a URL. A missing grant, a suspended grant, a
-- closed grant, a conflict, a closed case, and an unknown id all fail
-- with the same 42501, except get_my_review_capabilities(), which
-- returns no row when the caller has no current MARKET / ES grant.
--
-- Opening a case writes audit_events through record_audit_event. The
-- reviewer session has auth.uid(), so the existing writer can store the
-- ACCOUNT and PERSON. Metadata is the case type, market, and state.

create function public.verification_person_minimum_name(p_person_id uuid)
returns text
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select coalesce(
    nullif(btrim(person.display_name), ''),
    nullif(btrim(concat_ws(' ', person.first_name, person.last_name)), '')
  )
    from public.persons as person
   where person.id = p_person_id;
$$;

comment on function public.verification_person_minimum_name(uuid) is
  'Display name, or first and last name, for an authorized review detail. Not a client API.';

revoke all on function public.verification_person_minimum_name(uuid)
  from public, anon, authenticated, service_role;

create function public.verification_lock_spain_review_grant(p_person_id uuid)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  locked_grant_id uuid;
begin
  select grant_row.id
    into locked_grant_id
    from public.verification_review_grants as grant_row
   where grant_row.reviewer_person_id = p_person_id
     and grant_row.status = 'ACTIVE'
     and grant_row.valid_from <= pg_catalog.now()
     and grant_row.scope_type = 'MARKET'
     and grant_row.market_country_code = 'ES'
   order by grant_row.id
   limit 1;

  if locked_grant_id is null then
    return null;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    392,
    pg_catalog.hashtext(locked_grant_id::text)
  );

  select grant_row.id
    into locked_grant_id
    from public.verification_review_grants as grant_row
   where grant_row.id = locked_grant_id
     and grant_row.reviewer_person_id = p_person_id
     and grant_row.status = 'ACTIVE'
     and grant_row.valid_from <= pg_catalog.now()
     and grant_row.scope_type = 'MARKET'
     and grant_row.market_country_code = 'ES'
   for update;

  return locked_grant_id;
end;
$$;

comment on function public.verification_lock_spain_review_grant(uuid) is
  'Locks the current MARKET / ES grant, or returns null when it is absent, suspended, or closed. Shares lock 392 with suspend and close. Not a client API.';

revoke all on function public.verification_lock_spain_review_grant(uuid)
  from public, anon, authenticated, service_role;

create function public.verification_case_evidence_is_sufficient(
  p_parent_type text,
  p_parent_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select case p_parent_type
    when 'IDENTITY_CASE' then exists (
      select 1
        from public.verification_evidence as evidence
       where evidence.identity_case_id = p_parent_id
         and evidence.category = 'IDENTITY_PROVIDER_REFERENCE'
    )
    when 'OWNERSHIP_CLAIM' then exists (
      select 1
        from public.verification_evidence as evidence
       where evidence.ownership_claim_id = p_parent_id
         and evidence.category = 'EQUINE_IDENTIFIER_REFERENCE'
    ) and exists (
      select 1
        from public.verification_evidence as evidence
       where evidence.ownership_claim_id = p_parent_id
         and evidence.category = 'OWNERSHIP_ARTIFACT'
    )
    when 'MANAGEMENT_CLAIM' then exists (
      select 1
        from public.verification_evidence as evidence
       where evidence.management_claim_id = p_parent_id
         and evidence.category = 'EQUINE_IDENTIFIER_REFERENCE'
    ) and exists (
      select 1
        from public.verification_evidence as evidence
       where evidence.management_claim_id = p_parent_id
         and evidence.category = 'MANAGEMENT_DELEGATION_ARTIFACT'
    )
    else false
  end;
$$;

comment on function public.verification_case_evidence_is_sufficient(text, uuid) is
  'Spain-first indicator from the existing evidence categories. Identity needs a provider reference. Ownership and management need an equine identifier reference plus the claim artifact. This does not accept a case. Not a client API.';

revoke all on function public.verification_case_evidence_is_sufficient(text, uuid)
  from public, anon, authenticated, service_role;

create function public.get_my_review_capabilities()
returns table (
  scope_type text,
  market_country_code text
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller_person uuid;
  grant_id uuid;
begin
  select resolved.person_id
    into caller_person
    from public.verification_resolve_caller() as resolved;

  grant_id := public.verification_lock_spain_review_grant(caller_person);

  if grant_id is null then
    return;
  end if;

  return query
  select 'MARKET'::text, 'ES'::text;
end;
$$;

comment on function public.get_my_review_capabilities() is
  'Returns MARKET / ES when auth.uid() has a current grant for that scope. Returns no row otherwise. Does not accept a client actor, scope, or market, and does not return cases or private identifiers.';

revoke all on function public.get_my_review_capabilities()
  from public, anon, service_role;

grant execute on function public.get_my_review_capabilities() to authenticated;

create function public.list_my_review_queue()
returns table (
  case_id uuid,
  case_type text,
  market_country_code text,
  state text,
  updated_at timestamptz,
  evidence_categories text[]
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller_account uuid;
  caller_person uuid;
  grant_id uuid;
begin
  select resolved.account_id, resolved.person_id
    into caller_account, caller_person
    from public.verification_resolve_caller() as resolved;

  grant_id := public.verification_lock_spain_review_grant(caller_person);

  if grant_id is null then
    raise exception using
      errcode = '42501',
      message = 'Verification request is not available';
  end if;

  return query
  select
    queued.case_id,
    queued.case_type,
    queued.market_country_code,
    queued.state,
    queued.updated_at,
    queued.evidence_categories
    from (
      select
        identity_case.id as case_id,
        'IDENTITY'::text as case_type,
        identity_case.market_country_code,
        identity_case.state,
        identity_case.updated_at,
        coalesce(
          (
            select array_agg(distinct evidence.category order by evidence.category)
              from public.verification_evidence as evidence
             where evidence.identity_case_id = identity_case.id
          ),
          '{}'::text[]
        ) as evidence_categories
        from public.identity_verification_cases as identity_case
       where identity_case.market_country_code = 'ES'
         and identity_case.state in ('SUBMITTED', 'IN_REVIEW', 'RESUBMITTED')
         and identity_case.subject_person_id is distinct from caller_person
         and identity_case.submitted_by_account_id is distinct from caller_account
      union all
      select
        ownership_claim.id,
        'OWNERSHIP'::text,
        ownership_claim.market_country_code,
        ownership_claim.state,
        ownership_claim.updated_at,
        coalesce(
          (
            select array_agg(distinct evidence.category order by evidence.category)
              from public.verification_evidence as evidence
             where evidence.ownership_claim_id = ownership_claim.id
          ),
          '{}'::text[]
        )
        from public.equine_ownership_claims as ownership_claim
       where ownership_claim.market_country_code = 'ES'
         and ownership_claim.state in ('SUBMITTED', 'IN_REVIEW', 'RESUBMITTED')
         and ownership_claim.owner_person_id is distinct from caller_person
         and ownership_claim.submitted_by_account_id is distinct from caller_account
         and not public.verification_person_acts_for_center(
           caller_person,
           ownership_claim.owner_center_id
         )
      union all
      select
        management_claim.id,
        'MANAGEMENT'::text,
        management_claim.market_country_code,
        management_claim.state,
        management_claim.updated_at,
        coalesce(
          (
            select array_agg(distinct evidence.category order by evidence.category)
              from public.verification_evidence as evidence
             where evidence.management_claim_id = management_claim.id
          ),
          '{}'::text[]
        )
        from public.equine_management_authority_claims as management_claim
       where management_claim.market_country_code = 'ES'
         and management_claim.state in ('SUBMITTED', 'IN_REVIEW', 'RESUBMITTED')
         and management_claim.manager_person_id is distinct from caller_person
         and management_claim.submitted_by_account_id is distinct from caller_account
         and not public.verification_person_acts_for_center(
           caller_person,
           management_claim.manager_center_id
         )
    ) as queued
   order by queued.updated_at desc, queued.case_type asc, queued.case_id asc
   limit 50;
end;
$$;

comment on function public.list_my_review_queue() is
  'Pseudonymous MARKET / ES queue for the auth.uid() reviewer. At most 50 open cases, excluding self-review and center conflicts. Does not return names, documents, paths, or reviewer identity.';

revoke all on function public.list_my_review_queue()
  from public, anon, service_role;

grant execute on function public.list_my_review_queue() to authenticated;

create function public.get_my_review_case(
  p_case_type text,
  p_case_id uuid
)
returns table (
  case_id uuid,
  case_type text,
  state text,
  market_country_code text,
  created_at timestamptz,
  updated_at timestamptz,
  subject_name text,
  equine_id uuid,
  equine_name text,
  relation_type text,
  relation_role text,
  evidence jsonb,
  evidence_sufficient boolean
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller_account uuid;
  caller_person uuid;
  grant_id uuid;
  identity_case public.identity_verification_cases%rowtype;
  ownership_claim public.equine_ownership_claims%rowtype;
  management_claim public.equine_management_authority_claims%rowtype;
  opened_subject_name text;
  opened_equine_id uuid;
  opened_equine_name text;
  opened_relation_type text;
  opened_relation_role text;
  opened_evidence jsonb;
  opened_sufficient boolean;
  opened_created_at timestamptz;
  opened_updated_at timestamptz;
  opened_state text;
  audit_entity_type text;
begin
  select resolved.account_id, resolved.person_id
    into caller_account, caller_person
    from public.verification_resolve_caller() as resolved;

  if p_case_id is null
     or p_case_type is null
     or p_case_type not in ('IDENTITY', 'OWNERSHIP', 'MANAGEMENT') then
    raise exception using
      errcode = '42501',
      message = 'Verification request is not available';
  end if;

  grant_id := public.verification_lock_spain_review_grant(caller_person);

  if grant_id is null then
    raise exception using
      errcode = '42501',
      message = 'Verification request is not available';
  end if;

  if p_case_type = 'IDENTITY' then
    select identity_row.*
      into identity_case
      from public.identity_verification_cases as identity_row
     where identity_row.id = p_case_id
     for update;

    if not found
       or identity_case.market_country_code is distinct from 'ES'
       or identity_case.state not in ('SUBMITTED', 'IN_REVIEW', 'RESUBMITTED')
       or identity_case.subject_person_id is not distinct from caller_person
       or identity_case.submitted_by_account_id = caller_account then
      raise exception using
        errcode = '42501',
        message = 'Verification request is not available';
    end if;

    opened_subject_name := public.verification_person_minimum_name(
      identity_case.subject_person_id
    );
    opened_created_at := identity_case.created_at;
    opened_updated_at := identity_case.updated_at;
    opened_state := identity_case.state;
    audit_entity_type := 'identity_verification_case';
    opened_sufficient := public.verification_case_evidence_is_sufficient(
      'IDENTITY_CASE',
      identity_case.id
    );
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'category', evidence.category,
          'document_country_code', evidence.document_country_code
        )
        order by evidence.category, evidence.document_country_code, evidence.id
      ),
      '[]'::jsonb
    )
      into opened_evidence
      from public.verification_evidence as evidence
     where evidence.identity_case_id = identity_case.id;
  elsif p_case_type = 'OWNERSHIP' then
    select ownership_row.*
      into ownership_claim
      from public.equine_ownership_claims as ownership_row
     where ownership_row.id = p_case_id
     for update;

    if not found
       or ownership_claim.market_country_code is distinct from 'ES'
       or ownership_claim.state not in ('SUBMITTED', 'IN_REVIEW', 'RESUBMITTED')
       or ownership_claim.owner_person_id is not distinct from caller_person
       or ownership_claim.submitted_by_account_id = caller_account
       or public.verification_person_acts_for_center(
         caller_person,
         ownership_claim.owner_center_id
       ) then
      raise exception using
        errcode = '42501',
        message = 'Verification request is not available';
    end if;

    select equine.name
      into opened_equine_name
      from public.equines as equine
     where equine.id = ownership_claim.equine_id;

    opened_equine_id := ownership_claim.equine_id;
    opened_relation_type := ownership_claim.owner_type;
    opened_relation_role := 'OWNER';
    opened_created_at := ownership_claim.created_at;
    opened_updated_at := ownership_claim.updated_at;
    opened_state := ownership_claim.state;
    audit_entity_type := 'equine_ownership_claim';
    if ownership_claim.owner_type = 'PERSON' then
      opened_subject_name := public.verification_person_minimum_name(
        ownership_claim.owner_person_id
      );
    else
      select center.name
        into opened_subject_name
        from public.equestrian_centers as center
       where center.id = ownership_claim.owner_center_id;
    end if;
    opened_sufficient := public.verification_case_evidence_is_sufficient(
      'OWNERSHIP_CLAIM',
      ownership_claim.id
    );
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'category', evidence.category,
          'document_country_code', evidence.document_country_code
        )
        order by evidence.category, evidence.document_country_code, evidence.id
      ),
      '[]'::jsonb
    )
      into opened_evidence
      from public.verification_evidence as evidence
     where evidence.ownership_claim_id = ownership_claim.id;
  else
    select management_row.*
      into management_claim
      from public.equine_management_authority_claims as management_row
     where management_row.id = p_case_id
     for update;

    if not found
       or management_claim.market_country_code is distinct from 'ES'
       or management_claim.state not in ('SUBMITTED', 'IN_REVIEW', 'RESUBMITTED')
       or management_claim.manager_person_id is not distinct from caller_person
       or management_claim.submitted_by_account_id = caller_account
       or public.verification_person_acts_for_center(
         caller_person,
         management_claim.manager_center_id
       ) then
      raise exception using
        errcode = '42501',
        message = 'Verification request is not available';
    end if;

    select equine.name
      into opened_equine_name
      from public.equines as equine
     where equine.id = management_claim.equine_id;

    opened_equine_id := management_claim.equine_id;
    opened_relation_type := management_claim.manager_type;
    opened_relation_role := management_claim.management_role;
    opened_created_at := management_claim.created_at;
    opened_updated_at := management_claim.updated_at;
    opened_state := management_claim.state;
    audit_entity_type := 'equine_management_authority_claim';
    if management_claim.manager_type = 'PERSON' then
      opened_subject_name := public.verification_person_minimum_name(
        management_claim.manager_person_id
      );
    else
      select center.name
        into opened_subject_name
        from public.equestrian_centers as center
       where center.id = management_claim.manager_center_id;
    end if;
    opened_sufficient := public.verification_case_evidence_is_sufficient(
      'MANAGEMENT_CLAIM',
      management_claim.id
    );
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'category', evidence.category,
          'document_country_code', evidence.document_country_code
        )
        order by evidence.category, evidence.document_country_code, evidence.id
      ),
      '[]'::jsonb
    )
      into opened_evidence
      from public.verification_evidence as evidence
     where evidence.management_claim_id = management_claim.id;
  end if;

  perform public.record_audit_event(
    'verification_review_opened',
    audit_entity_type,
    p_case_id,
    jsonb_build_object(
      'case_type', p_case_type,
      'market_country_code', 'ES',
      'state', opened_state
    )
  );

  return query
  select
    p_case_id,
    p_case_type,
    opened_state,
    'ES'::text,
    opened_created_at,
    opened_updated_at,
    opened_subject_name,
    opened_equine_id,
    opened_equine_name,
    opened_relation_type,
    opened_relation_role,
    opened_evidence,
    opened_sufficient;
end;
$$;

comment on function public.get_my_review_case(text, uuid) is
  'Re-authorizes one open MARKET / ES case for auth.uid(). Unknown, closed, conflicting, and unauthorized ids fail the same way. Audits the opening without names, paths, or document bodies. Does not decide.';

revoke all on function public.get_my_review_case(text, uuid)
  from public, anon, service_role;

grant execute on function public.get_my_review_case(text, uuid) to authenticated;
