-- Phase 11A: booking foundation.
--
-- Adds public.bookings and public.booking_requirements. Does not
-- implement check_booking_eligibility(), create_booking_request(),
-- confirm_booking(), sessions or client booking UI.
--
-- PARTICIPANT != BOOKER. PERSON != ACCOUNT. A booker may request only
-- for their own PERSON or a minor covered by a current VERIFIED
-- guardian relationship. Activity-specific consent may be pending at
-- request time.
--
-- Product Owner 2026-09-02 (PR #19):
--   eligibility_status uses Architecture 2.1 tokens;
--   requirement types are equine types plus GUARDIAN_CONSENT and
--   POLICY_ACCEPTANCE;
--   requirement source types OWNER | CENTER | MARKET | EQUINE |
--   SERVICE | GUARDIAN | POLICY;
--   WAIVED is stored but there is no waive path in this train;
--   client CRUD cannot force CONFIRMED | ACTIVE | COMPLETED.
-- now() is not used in a table CHECK.
--
-- Access model follows migrations 006–020:
--   - RLS enabled, deny-by-default, no client table policies.
--   - No table INSERT/UPDATE/DELETE/SELECT for anon or authenticated.
--   - No client booking RPC in 021.

create table public.bookings (
  id uuid primary key default gen_random_uuid(),
  participant_person_id uuid not null references public.persons (id),
  booked_by_account_id uuid not null references public.user_accounts (id),
  equine_id uuid not null references public.equines (id),
  center_id uuid not null references public.equestrian_centers (id),
  service_id uuid not null references public.center_services (id),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  status text not null default 'DRAFT',
  eligibility_status text,
  booking_policy_snapshot jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  confirmed_at timestamptz,
  cancelled_at timestamptz,
  completed_at timestamptz,
  constraint bookings_range_check
    check (ends_at > starts_at),
  constraint bookings_status_check
    check (
      status in (
        'DRAFT',
        'REQUESTED',
        'PENDING_REQUIREMENTS',
        'PENDING_APPROVAL',
        'APPROVED',
        'CONFIRMED',
        'ACTIVE',
        'COMPLETED',
        'REJECTED',
        'CANCELLED',
        'EXPIRED',
        'DISPUTED'
      )
    ),
  constraint bookings_eligibility_status_check
    check (
      eligibility_status is null
      or eligibility_status in (
        'ELIGIBLE',
        'ELIGIBLE_WITH_SUPERVISION',
        'REQUIRES_CENTER_ASSESSMENT',
        'REQUIRES_ZERO_SESSION',
        'REQUIRES_OWNER_APPROVAL',
        'REQUIRES_GUARDIAN_CONSENT',
        'QUALIFICATION_NOT_VERIFIED',
        'NOT_ELIGIBLE'
      )
    ),
  constraint bookings_policy_snapshot_check
    check (jsonb_typeof(booking_policy_snapshot) = 'object'),
  constraint bookings_confirmed_lifecycle_check
    check (
      (
        status <> 'CONFIRMED'
        and confirmed_at is null
      )
      or (
        status in ('CONFIRMED', 'ACTIVE', 'COMPLETED', 'DISPUTED')
        and confirmed_at is not null
      )
    ),
  constraint bookings_cancelled_lifecycle_check
    check (
      (
        status <> 'CANCELLED'
        and cancelled_at is null
      )
      or (
        status = 'CANCELLED'
        and cancelled_at is not null
      )
    ),
  constraint bookings_completed_lifecycle_check
    check (
      (
        status <> 'COMPLETED'
        and completed_at is null
      )
      or (
        status = 'COMPLETED'
        and completed_at is not null
        and confirmed_at is not null
      )
    )
);

create index bookings_participant_person_id_idx
  on public.bookings (participant_person_id);

create index bookings_booked_by_account_id_idx
  on public.bookings (booked_by_account_id);

create index bookings_equine_id_idx
  on public.bookings (equine_id);

create index bookings_center_id_idx
  on public.bookings (center_id);

comment on table public.bookings is
  'Booking request/record. Participant is PERSON. Booker is ACCOUNT. Not occupancy until 022 creates a canonical BOOKING calendar block.';
comment on column public.bookings.participant_person_id is
  'Domain rider/participant PERSON. Never an Auth UUID and never a user_accounts.id.';
comment on column public.bookings.booked_by_account_id is
  'Authenticated requesting account. Distinct from the participant PERSON.';
comment on column public.bookings.status is
  'Frozen Architecture 2.1 booking statuses. CONFIRMED/ACTIVE/COMPLETED cannot be forced in 021.';
comment on column public.bookings.eligibility_status is
  'Optional frozen Architecture 2.1 eligibility token. Multiple unmet requirements live on booking_requirements.';
comment on column public.bookings.booking_policy_snapshot is
  'Policy snapshot for this booking. Ordinary later policy edits must not rewrite a confirmed snapshot.';

create table public.booking_requirements (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null
    references public.bookings (id) on delete cascade,
  requirement_type text not null,
  source_type text not null,
  source_id uuid,
  status text not null default 'PENDING',
  resolved_at timestamptz,
  resolved_by_account_id uuid references public.user_accounts (id),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint booking_requirements_type_check
    check (
      requirement_type in (
        'MIN_AGE',
        'MAX_AGE',
        'MIN_QUALIFICATION',
        'CENTER_ASSESSMENT_REQUIRED',
        'ZERO_SESSION_REQUIRED',
        'OWNER_APPROVAL_REQUIRED',
        'SUPERVISION_REQUIRED',
        'MIN_EXPERIENCE',
        'GUARDIAN_CONSENT',
        'POLICY_ACCEPTANCE'
      )
    ),
  constraint booking_requirements_source_type_check
    check (
      source_type in (
        'OWNER',
        'CENTER',
        'MARKET',
        'EQUINE',
        'SERVICE',
        'GUARDIAN',
        'POLICY'
      )
    ),
  constraint booking_requirements_status_check
    check (
      status in (
        'PENDING',
        'SATISFIED',
        'WAIVED',
        'FAILED',
        'EXPIRED'
      )
    ),
  constraint booking_requirements_metadata_check
    check (jsonb_typeof(metadata) = 'object'),
  constraint booking_requirements_resolved_check
    check (
      (
        status = 'PENDING'
        and resolved_at is null
        and resolved_by_account_id is null
      )
      or (
        status in ('SATISFIED', 'WAIVED', 'FAILED', 'EXPIRED')
        and resolved_at is not null
      )
    )
);

create index booking_requirements_booking_id_idx
  on public.booking_requirements (booking_id);

comment on table public.booking_requirements is
  'Explainable unmet or resolved requirements for one booking. WAIVED is a stored token with no waive RPC in this train.';
comment on column public.booking_requirements.requirement_type is
  'Frozen equine requirement types plus GUARDIAN_CONSENT and POLICY_ACCEPTANCE.';
comment on column public.booking_requirements.source_type is
  'Product Owner 2026-09-02: OWNER, CENTER, MARKET, EQUINE, SERVICE, GUARDIAN or POLICY.';
comment on column public.booking_requirements.source_id is
  'Opaque source uuid. Not a polymorphic FK.';

create function public.has_current_verified_guardian_relationship(
  p_guardian_person_id uuid,
  p_minor_person_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1
      from public.guardian_relationships as relationship
     where relationship.guardian_person_id = p_guardian_person_id
       and relationship.minor_person_id = p_minor_person_id
       and relationship.verification_status = 'VERIFIED'
       and relationship.revoked_at is null
       and (
         relationship.expires_at is null
         or relationship.expires_at > now()
       )
  );
$$;

comment on function public.has_current_verified_guardian_relationship(uuid, uuid) is
  'Server-internal current VERIFIED guardian relationship. Stored VERIFIED with revoked_at null and null or future expires_at. Not executable by PUBLIC, anon or authenticated.';

revoke all on function public.has_current_verified_guardian_relationship(uuid, uuid)
  from public, anon, authenticated;

create function public.enforce_booking_request_authority()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  booker_person uuid;
  service_center uuid;
  critical_states text[] := array['CONFIRMED', 'ACTIVE', 'COMPLETED'];
begin
  if TG_OP = 'DELETE' then
    if old.status = any(critical_states) then
      raise exception using
        errcode = '42501',
        message = 'Confirmed booking history cannot be deleted';
    end if;
    return old;
  end if;

  if TG_OP = 'UPDATE' then
    if old.status = any(critical_states) then
      if new.participant_person_id is distinct from old.participant_person_id
         or new.booked_by_account_id is distinct from old.booked_by_account_id
         or new.equine_id is distinct from old.equine_id
         or new.center_id is distinct from old.center_id
         or new.service_id is distinct from old.service_id
         or new.starts_at is distinct from old.starts_at
         or new.ends_at is distinct from old.ends_at
         or new.booking_policy_snapshot is distinct from old.booking_policy_snapshot
         or new.confirmed_at is distinct from old.confirmed_at then
        raise exception using
          errcode = '42501',
          message = 'Confirmed booking history cannot be silently rewritten';
      end if;
    end if;

    if old.status is distinct from new.status
       and new.status = any(critical_states) then
      raise exception using
        errcode = '42501',
        message = '021 cannot force CONFIRMED, ACTIVE or COMPLETED';
    end if;
  end if;

  if TG_OP = 'INSERT' and new.status = any(critical_states) then
    raise exception using
      errcode = '42501',
      message = '021 cannot insert CONFIRMED, ACTIVE or COMPLETED bookings';
  end if;

  select account.person_id
    into booker_person
    from public.user_accounts as account
   where account.id = new.booked_by_account_id;

  if booker_person is null then
    raise exception using
      errcode = '23503',
      message = 'Booking booker account must have a PERSON';
  end if;

  if booker_person is distinct from new.participant_person_id
     and not public.has_current_verified_guardian_relationship(
       booker_person,
       new.participant_person_id
     ) then
    raise exception using
      errcode = '42501',
      message = 'A booker may request only for their own PERSON or a minor with a current VERIFIED guardian relationship';
  end if;

  select service.center_id
    into service_center
    from public.center_services as service
   where service.id = new.service_id;

  if service_center is null then
    raise exception using
      errcode = '23503',
      message = 'Booking requires an existing service';
  end if;

  if service_center is distinct from new.center_id then
    raise exception using
      errcode = '23514',
      message = 'Booking center must match the service Center';
  end if;

  return new;
end;
$$;

comment on function public.enforce_booking_request_authority() is
  'BEFORE INSERT OR UPDATE OR DELETE: booker is own PERSON or current VERIFIED guardian. Service must belong to center_id. CONFIRMED/ACTIVE/COMPLETED cannot be forced in 021. Confirmed history cannot be rewritten. Not executable by anon or authenticated.';

revoke all on function public.enforce_booking_request_authority()
  from public, anon, authenticated;

create trigger bookings_request_authority
before insert or update or delete on public.bookings
for each row execute function public.enforce_booking_request_authority();

create function public.enforce_booking_requirement_rules()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  booking_status text;
begin
  if TG_OP = 'DELETE' then
    select booking.status
      into booking_status
      from public.bookings as booking
     where booking.id = old.booking_id;

    if booking_status in ('CONFIRMED', 'ACTIVE', 'COMPLETED') then
      raise exception using
        errcode = '42501',
        message = 'Confirmed booking requirements cannot be deleted';
    end if;
    return old;
  end if;

  if new.status = 'WAIVED' then
    raise exception using
      errcode = '42501',
      message = 'There is no waive path in this train';
  end if;

  if TG_OP = 'UPDATE'
     and old.booking_id is distinct from new.booking_id then
    raise exception using
      errcode = '42501',
      message = 'Booking requirement identity cannot be retargeted';
  end if;

  select booking.status
    into booking_status
    from public.bookings as booking
   where booking.id = new.booking_id;

  if booking_status in ('CONFIRMED', 'ACTIVE', 'COMPLETED') then
    raise exception using
      errcode = '42501',
      message = 'Confirmed booking requirements cannot be rewritten';
  end if;

  return new;
end;
$$;

comment on function public.enforce_booking_requirement_rules() is
  'BEFORE INSERT OR UPDATE OR DELETE: WAIVED cannot be set. Confirmed booking requirement rows cannot be rewritten. Not executable by anon or authenticated.';

revoke all on function public.enforce_booking_requirement_rules()
  from public, anon, authenticated;

create trigger booking_requirements_rules
before insert or update or delete on public.booking_requirements
for each row execute function public.enforce_booking_requirement_rules();

alter table public.bookings enable row level security;
alter table public.booking_requirements enable row level security;
revoke all on table public.bookings from anon, authenticated;
revoke all on table public.booking_requirements from anon, authenticated;
