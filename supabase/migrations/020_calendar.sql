-- Phase 10A: equine availability rules and canonical calendar blocks.
--
-- Adds public.equine_availability_rules and public.equine_calendar_blocks.
-- Does not implement bookings, confirm_booking(), eligibility, sessions
-- or client occupancy UI.
--
-- AVAILABILITY != OCCUPANCY. An availability rule is potential time.
-- A calendar block is canonical occupancy. Recurrence text is stored
-- only; occurrences are not expanded in 020.
--
-- Product Owner 2026-09-02 (PR #19):
--   availability status ACTIVE | INACTIVE;
--   calendar block status ACTIVE | CANCELLED;
--   source_type BOOKING | ACTIVITY | MANUAL | SYSTEM;
--   source_id opaque uuid;
--   all ACTIVE same-equine overlapping tstzranges are incompatible.
-- Membership, assignment and ownership never substitute
-- MANAGE_AVAILABILITY. now() is not used in a table CHECK.
--
-- Access model follows migrations 006–019:
--   - RLS enabled, deny-by-default, no client table policies.
--   - No table INSERT/UPDATE/DELETE/SELECT for anon or authenticated.
--   - No client calendar RPC.
--   - Authority is enforced server-side via SECURITY DEFINER triggers.

create extension if not exists btree_gist;

create table public.equine_availability_rules (
  id uuid primary key default gen_random_uuid(),
  equine_id uuid not null references public.equines (id),
  center_id uuid not null references public.equestrian_centers (id),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  recurrence_rule text,
  status text not null default 'ACTIVE',
  created_by_account_id uuid not null references public.user_accounts (id),
  created_at timestamptz not null default now(),
  constraint equine_availability_rules_status_check
    check (status in ('ACTIVE', 'INACTIVE')),
  constraint equine_availability_rules_range_check
    check (ends_at > starts_at),
  constraint equine_availability_rules_recurrence_check
    check (
      recurrence_rule is null
      or (
        recurrence_rule = btrim(recurrence_rule)
        and char_length(recurrence_rule) > 0
      )
    )
);

create index equine_availability_rules_equine_id_idx
  on public.equine_availability_rules (equine_id);

create index equine_availability_rules_center_id_idx
  on public.equine_availability_rules (center_id);

comment on table public.equine_availability_rules is
  'Potential availability of one equine at one Center. Not occupancy, not a booking and not a calendar block. Recurrence text is not expanded.';
comment on column public.equine_availability_rules.status is
  'Product Owner 2026-09-02: ACTIVE or INACTIVE. Not occupancy.';
comment on column public.equine_availability_rules.recurrence_rule is
  'Optional trimmed non-empty text. 020 stores the string only and does not expand occurrences.';
comment on column public.equine_availability_rules.created_by_account_id is
  'Authenticated creating/audit actor. ACCOUNT only.';
comment on column public.equine_availability_rules.starts_at is
  'Inclusive start of the stored window. CHECK requires ends_at > starts_at. now() is not used in a CHECK.';

create table public.equine_calendar_blocks (
  id uuid primary key default gen_random_uuid(),
  equine_id uuid not null references public.equines (id),
  center_id uuid not null references public.equestrian_centers (id),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  block_type text not null,
  source_type text not null,
  source_id uuid,
  status text not null default 'ACTIVE',
  created_by_account_id uuid not null references public.user_accounts (id),
  created_at timestamptz not null default now(),
  cancelled_at timestamptz,
  constraint equine_calendar_blocks_type_check
    check (
      block_type in (
        'BOOKING',
        'OWNER_USE',
        'LESSON',
        'COURSE',
        'TRAIL_RIDE',
        'VET',
        'REST',
        'MANUAL_BLOCK',
        'OTHER'
      )
    ),
  constraint equine_calendar_blocks_source_type_check
    check (source_type in ('BOOKING', 'ACTIVITY', 'MANUAL', 'SYSTEM')),
  constraint equine_calendar_blocks_status_check
    check (status in ('ACTIVE', 'CANCELLED')),
  constraint equine_calendar_blocks_lifecycle_check
    check (
      (
        status = 'ACTIVE'
        and cancelled_at is null
      )
      or (
        status = 'CANCELLED'
        and cancelled_at is not null
      )
    ),
  constraint equine_calendar_blocks_range_check
    check (ends_at > starts_at),
  constraint equine_calendar_blocks_active_overlap_excl
    exclude using gist (
      equine_id with =,
      tstzrange(starts_at, ends_at, '[)') with &&
    )
    where (status = 'ACTIVE')
);

create index equine_calendar_blocks_equine_id_idx
  on public.equine_calendar_blocks (equine_id);

create index equine_calendar_blocks_center_id_idx
  on public.equine_calendar_blocks (center_id);

comment on table public.equine_calendar_blocks is
  'Canonical occupancy of one equine. Distinct from availability. All ACTIVE same-equine overlapping tstzranges are mutually incompatible.';
comment on column public.equine_calendar_blocks.block_type is
  'Architecture 2.1 occupancy kinds: BOOKING, OWNER_USE, LESSON, COURSE, TRAIL_RIDE, VET, REST, MANUAL_BLOCK or OTHER.';
comment on column public.equine_calendar_blocks.source_type is
  'Product Owner 2026-09-02 foundation vocabulary: BOOKING, ACTIVITY, MANUAL or SYSTEM. source_id is an opaque uuid.';
comment on column public.equine_calendar_blocks.source_id is
  'Opaque source uuid. Semantic pairing is validated by later server functions when used. Not a polymorphic FK.';
comment on column public.equine_calendar_blocks.status is
  'Product Owner 2026-09-02: ACTIVE (occupies the equine) or CANCELLED (historical, cancelled_at required).';
comment on column public.equine_calendar_blocks.created_by_account_id is
  'Authenticated creating/audit actor. ACCOUNT only.';

create function public.has_effective_equine_availability(
  p_equine_id uuid,
  p_center_id uuid,
  p_starts_at timestamptz,
  p_ends_at timestamptz
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1
      from public.equine_availability_rules as availability_rule
     where availability_rule.equine_id = p_equine_id
       and availability_rule.center_id = p_center_id
       and availability_rule.status = 'ACTIVE'
       and availability_rule.starts_at <= p_starts_at
       and availability_rule.ends_at >= p_ends_at
       and p_ends_at > p_starts_at
  );
$$;

comment on function public.has_effective_equine_availability(uuid, uuid, timestamptz, timestamptz) is
  'Server-internal potential availability. Stored ACTIVE rule at that Center whose window covers the requested range. Recurrence is not expanded. Not occupancy. Not executable by PUBLIC, anon or authenticated.';

revoke all on function public.has_effective_equine_availability(uuid, uuid, timestamptz, timestamptz)
  from public, anon, authenticated;

create function public.has_active_equine_calendar_overlap(
  p_equine_id uuid,
  p_starts_at timestamptz,
  p_ends_at timestamptz
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1
      from public.equine_calendar_blocks as calendar_block
     where calendar_block.equine_id = p_equine_id
       and calendar_block.status = 'ACTIVE'
       and calendar_block.cancelled_at is null
       and tstzrange(calendar_block.starts_at, calendar_block.ends_at, '[)')
           && tstzrange(p_starts_at, p_ends_at, '[)')
  );
$$;

comment on function public.has_active_equine_calendar_overlap(uuid, timestamptz, timestamptz) is
  'Server-internal occupancy overlap. True when an ACTIVE same-equine block intersects the requested half-open range. Not executable by PUBLIC, anon or authenticated.';

revoke all on function public.has_active_equine_calendar_overlap(uuid, timestamptz, timestamptz)
  from public, anon, authenticated;

create function public.enforce_equine_availability_manage_authority()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if TG_OP = 'DELETE' then
    raise exception using
      errcode = '42501',
      message = 'Availability rules cannot be deleted';
  end if;

  if TG_OP = 'UPDATE' then
    if new.equine_id is distinct from old.equine_id
       or new.center_id is distinct from old.center_id
       or new.created_by_account_id is distinct from old.created_by_account_id
       or new.created_at is distinct from old.created_at then
      raise exception using
        errcode = '42501',
        message = 'Historical availability identity cannot be rewritten';
    end if;

    if old.status = 'ACTIVE'
       and new.status = 'INACTIVE'
       and new.starts_at is not distinct from old.starts_at
       and new.ends_at is not distinct from old.ends_at
       and new.recurrence_rule is not distinct from old.recurrence_rule then
      return new;
    end if;
  end if;

  if not public.has_active_equine_center_permission(
    new.equine_id,
    new.center_id,
    'MANAGE_AVAILABILITY'
  ) then
    raise exception using
      errcode = '42501',
      message = 'Availability changes require effective MANAGE_AVAILABILITY for this equine at this Center';
  end if;

  return new;
end;
$$;

comment on function public.enforce_equine_availability_manage_authority() is
  'BEFORE INSERT OR UPDATE OR DELETE: INSERT/mutation requires effective MANAGE_AVAILABILITY. Membership, assignment and ownership are not sufficient. Deactivate-only UPDATE does not re-check authority. Identity cannot be retargeted. DELETE is rejected. Not executable by anon or authenticated.';

revoke all on function public.enforce_equine_availability_manage_authority()
  from public, anon, authenticated;

create trigger equine_availability_rules_manage_authority
before insert or update or delete on public.equine_availability_rules
for each row execute function public.enforce_equine_availability_manage_authority();

create function public.enforce_equine_calendar_block_manage_authority()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if TG_OP = 'DELETE' then
    raise exception using
      errcode = '42501',
      message = 'Calendar blocks cannot be deleted';
  end if;

  if TG_OP = 'UPDATE' then
    if new.equine_id is distinct from old.equine_id
       or new.center_id is distinct from old.center_id
       or new.created_by_account_id is distinct from old.created_by_account_id
       or new.created_at is distinct from old.created_at then
      raise exception using
        errcode = '42501',
        message = 'Historical calendar block identity cannot be rewritten';
    end if;

    if old.status = 'ACTIVE'
       and new.status = 'CANCELLED'
       and old.cancelled_at is null
       and new.cancelled_at is not null
       and new.starts_at is not distinct from old.starts_at
       and new.ends_at is not distinct from old.ends_at
       and new.block_type is not distinct from old.block_type
       and new.source_type is not distinct from old.source_type
       and new.source_id is not distinct from old.source_id then
      return new;
    end if;
  end if;

  if not public.has_active_equine_center_permission(
    new.equine_id,
    new.center_id,
    'MANAGE_AVAILABILITY'
  ) then
    raise exception using
      errcode = '42501',
      message = 'Calendar occupancy changes require effective MANAGE_AVAILABILITY for this equine at this Center';
  end if;

  return new;
end;
$$;

comment on function public.enforce_equine_calendar_block_manage_authority() is
  'BEFORE INSERT OR UPDATE OR DELETE: INSERT/mutation requires effective MANAGE_AVAILABILITY. Membership, assignment and ownership are not sufficient. Cancel-only UPDATE does not re-check authority so a prior block remains auditable after permission lapse. Identity cannot be retargeted. DELETE is rejected. Not executable by anon or authenticated.';

revoke all on function public.enforce_equine_calendar_block_manage_authority()
  from public, anon, authenticated;

create trigger equine_calendar_blocks_manage_authority
before insert or update or delete on public.equine_calendar_blocks
for each row execute function public.enforce_equine_calendar_block_manage_authority();

alter table public.equine_availability_rules enable row level security;
alter table public.equine_calendar_blocks enable row level security;
revoke all on table public.equine_availability_rules from anon, authenticated;
revoke all on table public.equine_calendar_blocks from anon, authenticated;
