-- Stage 3. Read-only trust predicates over 036/037 decisions.
--
-- A result is current only when the latest relevant decision is ACCEPTED
-- and expires_at is null or still ahead of the queried instant. These
-- functions do not write, do not choose a retention interval, do not grant
-- review authority, and are not called by publication, services, bookings
-- or payments. Center corroboration is not derived here: migration 036
-- does not record the attesting center or the attester's authority.

create function public.verification_identity_is_verified(
  p_person_id uuid,
  p_market_country_code text,
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
      from (
        select decision.outcome, decision.expires_at
          from public.identity_verification_decisions as decision
          join public.identity_verification_cases as subject_case
            on subject_case.id = decision.case_id
         where subject_case.subject_person_id = p_person_id
           and subject_case.market_country_code = upper(btrim(coalesce(p_market_country_code, '')))
         order by decision.decided_at desc, decision.id desc
         limit 1
      ) as latest
     where latest.outcome = 'ACCEPTED'
       and (
         latest.expires_at is null
         or latest.expires_at > coalesce(p_as_of, pg_catalog.clock_timestamp())
       )
  );
$$;

comment on function public.verification_identity_is_verified(uuid, text, timestamptz) is
  'True when the latest identity decision for that PERSON and market is ACCEPTED and still current. Does not set expires_at. Not executable by PUBLIC, anon or authenticated.';

revoke all on function public.verification_identity_is_verified(uuid, text, timestamptz)
  from public, anon, authenticated;

create function public.verification_ownership_is_verified(
  p_ownership_id uuid,
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
      from public.equine_ownerships as ownership
      join lateral (
        select
          decision.outcome,
          decision.expires_at,
          claim.equine_id,
          claim.owner_type,
          claim.owner_person_id,
          claim.owner_center_id,
          claim.ownership_percentage
          from public.equine_relationship_decisions as decision
          join public.equine_ownership_claims as claim
            on claim.id = decision.ownership_claim_id
         where claim.effective_ownership_id = ownership.id
         order by decision.decided_at desc, decision.id desc
         limit 1
      ) as latest on true
     where ownership.id = p_ownership_id
       and latest.outcome = 'ACCEPTED'
       and (
         latest.expires_at is null
         or latest.expires_at > coalesce(p_as_of, pg_catalog.clock_timestamp())
       )
       and ownership.status = 'ACTIVE'
       and ownership.ended_at is null
       and ownership.started_at <= coalesce(p_as_of, pg_catalog.clock_timestamp())
       and ownership.equine_id = latest.equine_id
       and ownership.owner_type = latest.owner_type
       and ownership.owner_person_id is not distinct from latest.owner_person_id
       and ownership.owner_center_id is not distinct from latest.owner_center_id
       and ownership.ownership_percentage is not distinct from latest.ownership_percentage
  );
$$;

comment on function public.verification_ownership_is_verified(uuid, timestamptz) is
  'True when the latest decision for that effective ownership is a current acceptance and the row still matches the accepted claim. Does not write equine_ownerships.';

revoke all on function public.verification_ownership_is_verified(uuid, timestamptz)
  from public, anon, authenticated;

create function public.verification_management_is_verified(
  p_assignment_id uuid,
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
      from public.equine_management_assignments as assignment
      join lateral (
        select
          decision.outcome,
          decision.expires_at,
          claim.equine_id,
          claim.manager_type,
          claim.manager_person_id,
          claim.manager_center_id,
          claim.management_role,
          claim.valid_from,
          claim.valid_until
          from public.equine_relationship_decisions as decision
          join public.equine_management_authority_claims as claim
            on claim.id = decision.management_claim_id
         where claim.effective_assignment_id = assignment.id
         order by decision.decided_at desc, decision.id desc
         limit 1
      ) as latest on true
     where assignment.id = p_assignment_id
       and latest.outcome = 'ACCEPTED'
       and (
         latest.expires_at is null
         or latest.expires_at > coalesce(p_as_of, pg_catalog.clock_timestamp())
       )
       and assignment.status = 'ACTIVE'
       and assignment.valid_until is null
       and assignment.valid_from <= coalesce(p_as_of, pg_catalog.clock_timestamp())
       and assignment.equine_id = latest.equine_id
       and assignment.manager_type = latest.manager_type
       and assignment.manager_person_id is not distinct from latest.manager_person_id
       and assignment.manager_center_id is not distinct from latest.manager_center_id
       and assignment.management_role = latest.management_role
       and assignment.valid_from is not distinct from latest.valid_from
       and assignment.valid_until is not distinct from latest.valid_until
  );
$$;

comment on function public.verification_management_is_verified(uuid, timestamptz) is
  'True when the latest decision for that effective assignment is a current acceptance and the row still matches the accepted claim. Does not write equine_management_assignments.';

revoke all on function public.verification_management_is_verified(uuid, timestamptz)
  from public, anon, authenticated;

create function public.list_my_verification_status()
returns table (
  subject_kind text,
  market_country_code text,
  equine_id uuid,
  effective_id uuid,
  status_code text
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  caller_person uuid;
  queried_at timestamptz := pg_catalog.clock_timestamp();
begin
  select resolved.person_id
    into caller_person
    from public.verification_resolve_caller() as resolved;

  return query
  select
    'IDENTITY'::text,
    identity_market.market_country_code,
    null::uuid,
    null::uuid,
    case
      when public.verification_identity_is_verified(
        caller_person,
        identity_market.market_country_code,
        queried_at
      ) then 'VERIFIED'
      else 'NOT_VERIFIED'
    end
    from (
      select distinct subject_case.market_country_code
        from public.identity_verification_cases as subject_case
       where subject_case.subject_person_id = caller_person
    ) as identity_market;

  return query
  select
    'OWNERSHIP'::text,
    null::text,
    ownership.equine_id,
    ownership.id,
    case
      when public.verification_ownership_is_verified(ownership.id, queried_at)
        then 'VERIFIED'
      else 'NOT_VERIFIED'
    end
    from public.equine_ownerships as ownership
   where ownership.owner_person_id = caller_person;

  return query
  select
    'MANAGEMENT'::text,
    null::text,
    assignment.equine_id,
    assignment.id,
    case
      when public.verification_management_is_verified(assignment.id, queried_at)
        then 'VERIFIED'
      else 'NOT_VERIFIED'
    end
    from public.equine_management_assignments as assignment
   where assignment.manager_person_id = caller_person;
end;
$$;

comment on function public.list_my_verification_status() is
  'Caller-only identity, ownership and management codes. PERSON comes from auth.uid(). Omits reviewer identity, evidence paths, notes and other people. A CENTER_CORROBORATION evidence label is not a trusted status. Does not open publication, services, bookings or payments.';

revoke all on function public.list_my_verification_status() from public, anon;
grant execute on function public.list_my_verification_status() to authenticated;
