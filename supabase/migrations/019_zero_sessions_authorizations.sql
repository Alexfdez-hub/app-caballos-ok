-- Phase 9A: Zero Sessions and rider-equine authorizations.
--
-- Adds public.zero_sessions and public.rider_equine_authorizations.
-- Does not implement eligibility, calendar, bookings, sessions,
-- approve_zero_session(), Expo mutation UI or client table CRUD.
--
-- ASSESSMENT != ZERO SESSION != AUTHORIZATION.
-- Rider, evaluator and issuer are PERSON. requested_by_account_id is
-- ACCOUNT only. A Zero Session result never auto-creates an
-- authorization. OWNER_APPROVAL, ZERO_SESSION and
-- CENTER_DELEGATED_APPROVAL stay distinguishable.
--
-- Product Owner 2026-09-02 (PR #19):
--   authorization status ACTIVE | REVOKED (no stored EXPIRED);
--   evaluator requires ASSESSOR at center_id AND ASSESS_RIDERS on the
--   equine at that Center; issuer rules per authorization type.
-- Membership, assignment and management alone never substitute.
-- now() is not used in a table CHECK.
--
-- Access model follows migrations 006–018:
--   - RLS enabled, deny-by-default, no client table policies.
--   - No table INSERT/UPDATE/DELETE/SELECT for anon or authenticated.
--   - No client approval RPC.
--   - Authority is enforced server-side via SECURITY DEFINER triggers.

create table public.zero_sessions (
  id uuid primary key default gen_random_uuid(),
  rider_person_id uuid not null references public.persons (id),
  equine_id uuid not null references public.equines (id),
  center_id uuid not null references public.equestrian_centers (id),
  requested_by_account_id uuid not null references public.user_accounts (id),
  scheduled_at timestamptz,
  performed_at timestamptz,
  evaluator_person_id uuid references public.persons (id),
  result text not null default 'PENDING',
  notes text,
  created_at timestamptz not null default now(),
  constraint zero_sessions_result_check
    check (
      result in (
        'PENDING',
        'APPROVED',
        'APPROVED_WITH_RESTRICTIONS',
        'REJECTED',
        'CANCELLED'
      )
    ),
  constraint zero_sessions_self_evaluation_check
    check (
      evaluator_person_id is null
      or evaluator_person_id <> rider_person_id
    ),
  constraint zero_sessions_approved_fields_check
    check (
      result not in ('APPROVED', 'APPROVED_WITH_RESTRICTIONS')
      or (
        evaluator_person_id is not null
        and performed_at is not null
      )
    ),
  constraint zero_sessions_notes_check
    check (
      notes is null
      or (
        notes = btrim(notes)
        and char_length(notes) > 0
      )
    )
);

create index zero_sessions_rider_person_id_idx
  on public.zero_sessions (rider_person_id);

create index zero_sessions_equine_id_idx
  on public.zero_sessions (equine_id);

create index zero_sessions_center_id_idx
  on public.zero_sessions (center_id);

create index zero_sessions_evaluator_person_id_idx
  on public.zero_sessions (evaluator_person_id);

comment on table public.zero_sessions is
  'Zero Session record for one rider PERSON and one equine at one Center. Not a Center assessment, not a rider-equine authorization and not eligibility. Result never auto-creates an authorization.';
comment on column public.zero_sessions.rider_person_id is
  'Domain rider identity. Never an Auth UUID and never a user_accounts.id.';
comment on column public.zero_sessions.requested_by_account_id is
  'Authenticated requesting/audit actor. ACCOUNT only.';
comment on column public.zero_sessions.evaluator_person_id is
  'Domain evaluator PERSON. Required for APPROVED and APPROVED_WITH_RESTRICTIONS. Must differ from the rider. Creating or completing requires ASSESSOR at center_id and effective ASSESS_RIDERS on the equine.';
comment on column public.zero_sessions.result is
  'Frozen Architecture 2.1 results: PENDING, APPROVED, APPROVED_WITH_RESTRICTIONS, REJECTED or CANCELLED.';
comment on column public.zero_sessions.performed_at is
  'Required when result is APPROVED or APPROVED_WITH_RESTRICTIONS. now() is not used in a CHECK.';

create table public.rider_equine_authorizations (
  id uuid primary key default gen_random_uuid(),
  rider_person_id uuid not null references public.persons (id),
  equine_id uuid not null references public.equines (id),
  authorization_type text not null,
  issued_by_person_id uuid not null references public.persons (id),
  center_id uuid references public.equestrian_centers (id),
  source_zero_session_id uuid references public.zero_sessions (id),
  status text not null default 'ACTIVE',
  valid_from timestamptz not null default now(),
  valid_until timestamptz,
  supervision_required boolean not null default false,
  restrictions_json jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  revoked_at timestamptz,
  constraint rider_equine_authorizations_type_check
    check (
      authorization_type in (
        'OWNER_APPROVAL',
        'ZERO_SESSION',
        'CENTER_DELEGATED_APPROVAL'
      )
    ),
  constraint rider_equine_authorizations_status_check
    check (status in ('ACTIVE', 'REVOKED')),
  constraint rider_equine_authorizations_lifecycle_check
    check (
      (
        status = 'ACTIVE'
        and revoked_at is null
      )
      or (
        status = 'REVOKED'
        and revoked_at is not null
        and revoked_at >= valid_from
      )
    ),
  constraint rider_equine_authorizations_dates_check
    check (
      valid_until is null
      or valid_until >= valid_from
    ),
  constraint rider_equine_authorizations_source_type_check
    check (
      (
        authorization_type = 'ZERO_SESSION'
        and source_zero_session_id is not null
      )
      or (
        authorization_type <> 'ZERO_SESSION'
        and source_zero_session_id is null
      )
    ),
  constraint rider_equine_authorizations_center_type_check
    check (
      (
        authorization_type = 'CENTER_DELEGATED_APPROVAL'
        and center_id is not null
      )
      or (
        authorization_type = 'OWNER_APPROVAL'
      )
      or (
        authorization_type = 'ZERO_SESSION'
      )
    ),
  constraint rider_equine_authorizations_restrictions_check
    check (jsonb_typeof(restrictions_json) = 'object')
);

create index rider_equine_authorizations_rider_person_id_idx
  on public.rider_equine_authorizations (rider_person_id);

create index rider_equine_authorizations_equine_id_idx
  on public.rider_equine_authorizations (equine_id);

create index rider_equine_authorizations_center_id_idx
  on public.rider_equine_authorizations (center_id);

create index rider_equine_authorizations_source_zero_session_id_idx
  on public.rider_equine_authorizations (source_zero_session_id);

comment on table public.rider_equine_authorizations is
  'Rider-equine authorization. Distinct from Zero Session result, Center assessment and qualification. OWNER_APPROVAL, ZERO_SESSION and CENTER_DELEGATED_APPROVAL stay distinguishable.';
comment on column public.rider_equine_authorizations.issued_by_person_id is
  'Issuer PERSON. Authority depends on authorization_type. Never an Auth UUID.';
comment on column public.rider_equine_authorizations.status is
  'Product Owner 2026-09-02: ACTIVE (revoked_at null) or REVOKED (revoked_at required). Expiry is derived from valid_until. Stored ACTIVE is currently effective only when valid_from <= now() and valid_until is null or in the future.';
comment on column public.rider_equine_authorizations.source_zero_session_id is
  'Required for type ZERO_SESSION; forbidden otherwise. Must be the same rider+equine with result APPROVED or APPROVED_WITH_RESTRICTIONS.';
comment on column public.rider_equine_authorizations.center_id is
  'Required for CENTER_DELEGATED_APPROVAL. Null for PERSON OWNER_APPROVAL. Owning Center for CENTER-owner OWNER_APPROVAL. Optional historical Center on ZERO_SESSION type.';
comment on column public.rider_equine_authorizations.valid_until is
  'Optional end of stored validity. Must not precede valid_from. now() is not used in a CHECK.';

create function public.has_effective_equine_person_ownership(
  p_person_id uuid,
  p_equine_id uuid
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
     where ownership.owner_person_id = p_person_id
       and ownership.equine_id = p_equine_id
       and ownership.owner_type = 'PERSON'
       and ownership.status = 'ACTIVE'
       and ownership.ended_at is null
       and ownership.started_at <= now()
  );
$$;

comment on function public.has_effective_equine_person_ownership(uuid, uuid) is
  'Server-internal effective PERSON ownership. Stored ACTIVE with started_at <= now() and ended_at null. Not management and not executable by PUBLIC, anon or authenticated.';

revoke all on function public.has_effective_equine_person_ownership(uuid, uuid)
  from public, anon, authenticated;

create function public.has_effective_equine_center_ownership(
  p_center_id uuid,
  p_equine_id uuid
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
     where ownership.owner_center_id = p_center_id
       and ownership.equine_id = p_equine_id
       and ownership.owner_type = 'CENTER'
       and ownership.status = 'ACTIVE'
       and ownership.ended_at is null
       and ownership.started_at <= now()
  );
$$;

comment on function public.has_effective_equine_center_ownership(uuid, uuid) is
  'Server-internal effective CENTER ownership. Stored ACTIVE with started_at <= now() and ended_at null. Not membership and not executable by PUBLIC, anon or authenticated.';

revoke all on function public.has_effective_equine_center_ownership(uuid, uuid)
  from public, anon, authenticated;

create function public.has_effective_rider_equine_authorization(
  p_rider_person_id uuid,
  p_equine_id uuid,
  p_authorization_type text
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1
      from public.rider_equine_authorizations as authorization
     where authorization.rider_person_id = p_rider_person_id
       and authorization.equine_id = p_equine_id
       and authorization.authorization_type = p_authorization_type
       and authorization.status = 'ACTIVE'
       and authorization.revoked_at is null
       and authorization.valid_from <= now()
       and (
         authorization.valid_until is null
         or authorization.valid_until > now()
       )
  );
$$;

comment on function public.has_effective_rider_equine_authorization(uuid, uuid, text) is
  'Server-internal current authorization. Stored ACTIVE with valid_from <= now() and null or future valid_until. Expiry is not a stored EXPIRED token. Not executable by PUBLIC, anon or authenticated.';

revoke all on function public.has_effective_rider_equine_authorization(uuid, uuid, text)
  from public, anon, authenticated;

create function public.enforce_zero_session_evaluator_authority()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if TG_OP = 'UPDATE' then
    if new.rider_person_id is distinct from old.rider_person_id
       or new.equine_id is distinct from old.equine_id
       or new.center_id is distinct from old.center_id
       or new.requested_by_account_id is distinct from old.requested_by_account_id then
      raise exception using
        errcode = '42501',
        message = 'Historical Zero Session identity cannot be rewritten';
    end if;

    if old.evaluator_person_id is not null
       and new.evaluator_person_id is distinct from old.evaluator_person_id then
      raise exception using
        errcode = '42501',
        message = 'Historical Zero Session evaluator cannot be rewritten';
    end if;
  end if;

  if new.evaluator_person_id is not null then
    if new.evaluator_person_id = new.rider_person_id then
      raise exception using
        errcode = '23514',
        message = 'A Zero Session evaluator cannot be the rider';
    end if;

    if not public.has_active_center_role(
      new.evaluator_person_id,
      new.center_id,
      'ASSESSOR'
    ) then
      raise exception using
        errcode = '42501',
        message = 'Zero Session evaluation requires an active ASSESSOR membership at this Center';
    end if;

    if not public.has_active_equine_center_permission(
      new.equine_id,
      new.center_id,
      'ASSESS_RIDERS'
    ) then
      raise exception using
        errcode = '42501',
        message = 'Zero Session evaluation requires effective ASSESS_RIDERS for this equine at this Center';
    end if;
  end if;

  return new;
end;
$$;

comment on function public.enforce_zero_session_evaluator_authority() is
  'BEFORE INSERT OR UPDATE: when evaluator_person_id is set, that PERSON must have ASSESSOR at center_id and the equine must have effective ASSESS_RIDERS at that Center. Rider, equine, Center and requester cannot be retargeted. Evaluator cannot change once set. ASSESSOR alone is not enough. Not executable by anon or authenticated.';

revoke all on function public.enforce_zero_session_evaluator_authority()
  from public, anon, authenticated;

create trigger zero_sessions_evaluator_authority
before insert or update on public.zero_sessions
for each row execute function public.enforce_zero_session_evaluator_authority();

create function public.enforce_rider_equine_authorization_authority()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  source_rider uuid;
  source_equine uuid;
  source_center uuid;
  source_result text;
  source_evaluator uuid;
begin
  if TG_OP = 'UPDATE' then
    if new.rider_person_id is distinct from old.rider_person_id
       or new.equine_id is distinct from old.equine_id
       or new.authorization_type is distinct from old.authorization_type
       or new.issued_by_person_id is distinct from old.issued_by_person_id
       or new.center_id is distinct from old.center_id
       or new.source_zero_session_id is distinct from old.source_zero_session_id then
      raise exception using
        errcode = '42501',
        message = 'Historical authorization identity cannot be rewritten';
    end if;
  end if;

  if new.authorization_type = 'ZERO_SESSION' then
    select session.rider_person_id,
           session.equine_id,
           session.center_id,
           session.result,
           session.evaluator_person_id
      into source_rider, source_equine, source_center, source_result, source_evaluator
      from public.zero_sessions as session
     where session.id = new.source_zero_session_id;

    if source_rider is null then
      raise exception using
        errcode = '23503',
        message = 'ZERO_SESSION authorization requires an existing Zero Session';
    end if;

    if source_rider is distinct from new.rider_person_id
       or source_equine is distinct from new.equine_id then
      raise exception using
        errcode = '23514',
        message = 'ZERO_SESSION authorization source must be the same rider and equine';
    end if;

    if source_result not in ('APPROVED', 'APPROVED_WITH_RESTRICTIONS') then
      raise exception using
        errcode = '23514',
        message = 'ZERO_SESSION authorization requires an approved Zero Session result';
    end if;

    if new.issued_by_person_id is distinct from source_evaluator then
      raise exception using
        errcode = '42501',
        message = 'ZERO_SESSION authorization issuer must be the source session evaluator';
    end if;

    if new.issued_by_person_id = new.rider_person_id then
      raise exception using
        errcode = '23514',
        message = 'ZERO_SESSION authorization issuer cannot be the rider';
    end if;

    if new.center_id is not null
       and new.center_id is distinct from source_center then
      raise exception using
        errcode = '23514',
        message = 'ZERO_SESSION authorization center must match the source session';
    end if;
  elsif new.authorization_type = 'CENTER_DELEGATED_APPROVAL' then
    if new.center_id is null then
      raise exception using
        errcode = '23514',
        message = 'CENTER_DELEGATED_APPROVAL requires center_id';
    end if;

    if new.issued_by_person_id = new.rider_person_id then
      raise exception using
        errcode = '23514',
        message = 'CENTER_DELEGATED_APPROVAL issuer cannot be the rider';
    end if;

    if not public.has_active_equine_center_permission(
      new.equine_id,
      new.center_id,
      'APPROVE_RIDERS'
    ) then
      raise exception using
        errcode = '42501',
        message = 'CENTER_DELEGATED_APPROVAL requires effective APPROVE_RIDERS for this equine at this Center';
    end if;
  elsif new.authorization_type = 'OWNER_APPROVAL' then
    if new.center_id is null then
      if not public.has_effective_equine_person_ownership(
        new.issued_by_person_id,
        new.equine_id
      ) then
        raise exception using
          errcode = '42501',
          message = 'PERSON OWNER_APPROVAL requires effective PERSON ownership of this equine';
      end if;
    else
      if not public.has_effective_equine_center_ownership(
        new.center_id,
        new.equine_id
      ) then
        raise exception using
          errcode = '42501',
          message = 'CENTER OWNER_APPROVAL requires effective CENTER ownership of this equine';
      end if;

      if not public.has_active_equine_center_permission(
        new.equine_id,
        new.center_id,
        'APPROVE_RIDERS'
      ) then
        raise exception using
          errcode = '42501',
          message = 'CENTER OWNER_APPROVAL requires effective APPROVE_RIDERS at the owning Center';
      end if;

      if new.issued_by_person_id = new.rider_person_id then
        raise exception using
          errcode = '23514',
          message = 'CENTER OWNER_APPROVAL issuer cannot be the rider';
      end if;
    end if;
  end if;

  return new;
end;
$$;

comment on function public.enforce_rider_equine_authorization_authority() is
  'BEFORE INSERT OR UPDATE: issuer authority per Product Owner 2026-09-02. Membership, assignment and management are not sufficient. Identity columns cannot be retargeted. Not executable by anon or authenticated.';

revoke all on function public.enforce_rider_equine_authorization_authority()
  from public, anon, authenticated;

create trigger rider_equine_authorizations_issuer_authority
before insert or update on public.rider_equine_authorizations
for each row execute function public.enforce_rider_equine_authorization_authority();

alter table public.zero_sessions enable row level security;
alter table public.rider_equine_authorizations enable row level security;
revoke all on table public.zero_sessions from anon, authenticated;
revoke all on table public.rider_equine_authorizations from anon, authenticated;
