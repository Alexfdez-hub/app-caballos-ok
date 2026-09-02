-- Phase 4B: equine–center relations foundation.
--
-- Adds public.equine_center_assignments and public.equine_center_permissions.
-- Does not implement public directory, availability, bookings, assessments,
-- Expo assign/grant/revoke or mutation RPC.
--
-- ASSIGNMENT ≠ OWNERSHIP ≠ MANAGEMENT ≠ PUBLISH.
-- An assignment or membership or ownership row does not create a permission.
-- Permission is explicit. Helpers are not executable by PUBLIC/anon/authenticated.
--
-- Access model follows migrations 006–012:
--   - RLS enabled, deny-by-default, no client table policies.
--   - No table INSERT/UPDATE/DELETE/SELECT for anon or authenticated.
--   - No client grant/revoke/assign RPC.
--   - Provisioning remains a controlled process outside the app.

create table public.equine_center_assignments (
  id uuid primary key default gen_random_uuid(),
  equine_id uuid not null references public.equines (id),
  center_id uuid not null references public.equestrian_centers (id),
  assignment_type text not null,
  status text not null default 'ACTIVE',
  started_at timestamptz not null default now(),
  ended_at timestamptz,
  created_at timestamptz not null default now(),
  constraint equine_center_assignments_type_check
    check (
      assignment_type in (
        'BOARDING',
        'CENTER_OWNED',
        'SCHOOL',
        'TEMPORARY',
        'OTHER'
      )
    ),
  constraint equine_center_assignments_status_check
    check (status in ('ACTIVE', 'ENDED')),
  constraint equine_center_assignments_lifecycle_check
    check (
      (
        status = 'ACTIVE'
        and ended_at is null
      )
      or (
        status = 'ENDED'
        and ended_at is not null
        and ended_at >= started_at
      )
    )
);

create index equine_center_assignments_equine_id_idx
  on public.equine_center_assignments (equine_id);

create index equine_center_assignments_center_id_idx
  on public.equine_center_assignments (center_id);

create unique index equine_center_assignments_active_exact_key
  on public.equine_center_assignments (equine_id, center_id, assignment_type)
  where status = 'ACTIVE';

comment on table public.equine_center_assignments is
  'Equine located/used at a Center. Not ownership, not management, not publication and not a permission grant. Duplicate active exact equine+center+type rows are rejected.';
comment on column public.equine_center_assignments.assignment_type is
  'BOARDING, CENTER_OWNED, SCHOOL, TEMPORARY or OTHER. Not an access rule.';
comment on column public.equine_center_assignments.status is
  'ACTIVE (in force, ended_at null) or ENDED (historical). Assignment end does not revoke permissions automatically.';

create table public.equine_center_permissions (
  id uuid primary key default gen_random_uuid(),
  equine_id uuid not null references public.equines (id),
  center_id uuid not null references public.equestrian_centers (id),
  granted_by_person_id uuid not null references public.persons (id),
  permission_code text not null,
  status text not null default 'ACTIVE',
  granted_at timestamptz not null default now(),
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  constraint equine_center_permissions_code_check
    check (
      permission_code in (
        'MANAGE_AVAILABILITY',
        'MANAGE_BOOKINGS',
        'ASSESS_RIDERS',
        'APPROVE_RIDERS',
        'MANAGE_REQUIREMENTS',
        'VIEW_ACTIVITY'
      )
    ),
  constraint equine_center_permissions_status_check
    check (status in ('ACTIVE', 'REVOKED')),
  constraint equine_center_permissions_lifecycle_check
    check (
      (
        status = 'ACTIVE'
        and revoked_at is null
      )
      or (
        status = 'REVOKED'
        and revoked_at is not null
        and revoked_at >= granted_at
      )
    )
);

create index equine_center_permissions_equine_id_idx
  on public.equine_center_permissions (equine_id);

create index equine_center_permissions_center_id_idx
  on public.equine_center_permissions (center_id);

create unique index equine_center_permissions_active_code_key
  on public.equine_center_permissions (equine_id, center_id, permission_code)
  where status = 'ACTIVE';

comment on table public.equine_center_permissions is
  'Explicit Center permission over an equine. Assignment, membership and ownership do not create this row. Not executable by ordinary clients.';
comment on column public.equine_center_permissions.permission_code is
  'MANAGE_AVAILABILITY, MANAGE_BOOKINGS, ASSESS_RIDERS, APPROVE_RIDERS, MANAGE_REQUIREMENTS or VIEW_ACTIVITY. Not implied by assignment or membership.';
comment on column public.equine_center_permissions.status is
  'ACTIVE (in force, revoked_at null) or REVOKED (historical, revoked_at required). Distinct from assignment ENDED.';

alter table public.equine_center_assignments enable row level security;
alter table public.equine_center_permissions enable row level security;
revoke all on table public.equine_center_assignments from anon, authenticated;
revoke all on table public.equine_center_permissions from anon, authenticated;

create function public.has_active_equine_center_permission(
  p_equine_id uuid,
  p_center_id uuid,
  p_permission_code text
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1
      from public.equine_center_permissions as permission
     where permission.equine_id = p_equine_id
       and permission.center_id = p_center_id
       and permission.permission_code = p_permission_code
       and permission.status = 'ACTIVE'
       and permission.revoked_at is null
  );
$$;

comment on function public.has_active_equine_center_permission(uuid, uuid, text) is
  'Server-internal equine + center + permission check. Not executable by PUBLIC, anon or authenticated. Assignment and membership do not imply this result.';

revoke all on function public.has_active_equine_center_permission(uuid, uuid, text)
  from public, anon, authenticated;
