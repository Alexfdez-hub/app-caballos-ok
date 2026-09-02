-- Phase 4A: equine ownership and management foundation.
--
-- Adds public.equine_ownerships and public.equine_management_assignments.
-- Does not implement center assignment, center permissions, public directory,
-- invitations, suspension, verification, Expo create/edit or mutation RPC.
--
-- OWNERSHIP ≠ MANAGEMENT ≠ CENTER ASSIGNMENT ≠ CENTER PERMISSION.
-- Center membership and rider profile do not grant equine authority.
-- An owner may also be a manager. No owner_id / manager_id on equines.
--
-- Access model follows migrations 006–011:
--   - RLS enabled, deny-by-default, no client table policies.
--   - No table INSERT/UPDATE/DELETE/SELECT for anon or authenticated.
--   - No self-assignment, grant, revoke or mutation RPC.
--   - Provisioning remains a controlled process outside the app.
--   - Authenticated reads go through caller-context SECURITY DEFINER RPCs
--     that derive PERSON from auth.uid() and do not expose other
--     owners or managers.
--
-- Architecture 2.1 names ownership/management status without enumerating
-- values. This migration constrains ACTIVE | ENDED as a provisional
-- foundation convention awaiting Product Owner acceptance. Invitation,
-- suspension and verification tokens are not invented here.

create table public.equine_ownerships (
  id uuid primary key default gen_random_uuid(),
  equine_id uuid not null references public.equines (id),
  owner_type text not null,
  owner_person_id uuid references public.persons (id),
  owner_center_id uuid references public.equestrian_centers (id),
  ownership_percentage numeric not null,
  status text not null default 'ACTIVE',
  started_at timestamptz not null default now(),
  ended_at timestamptz,
  created_at timestamptz not null default now(),
  constraint equine_ownerships_owner_type_check
    check (owner_type in ('PERSON', 'CENTER')),
  constraint equine_ownerships_owner_xor_check
    check (
      (
        owner_type = 'PERSON'
        and owner_person_id is not null
        and owner_center_id is null
      )
      or (
        owner_type = 'CENTER'
        and owner_center_id is not null
        and owner_person_id is null
      )
    ),
  constraint equine_ownerships_percentage_check
    check (
      ownership_percentage > 0
      and ownership_percentage <= 100
    ),
  constraint equine_ownerships_status_check
    check (status in ('ACTIVE', 'ENDED')),
  constraint equine_ownerships_lifecycle_check
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

create index equine_ownerships_equine_id_idx
  on public.equine_ownerships (equine_id);

create unique index equine_ownerships_active_person_key
  on public.equine_ownerships (equine_id, owner_person_id)
  where status = 'ACTIVE' and owner_person_id is not null;

create unique index equine_ownerships_active_center_key
  on public.equine_ownerships (equine_id, owner_center_id)
  where status = 'ACTIVE' and owner_center_id is not null;

comment on table public.equine_ownerships is
  'Equine ownership share. PERSON or CENTER XOR. Not management, not center assignment, not publish authority and not a client-writable roster. Architecture 2.1 does not require shares to sum to 100%; this foundation does not enforce an aggregate.';
comment on column public.equine_ownerships.id is
  'Stable ownership identity. Never an Auth UUID.';
comment on column public.equine_ownerships.equine_id is
  'Equine this share belongs to. Does not place owner_id on equines.';
comment on column public.equine_ownerships.owner_type is
  'PERSON or CENTER. Must match the non-null owner FK.';
comment on column public.equine_ownerships.owner_person_id is
  'Domain person owner when owner_type is PERSON. Never an Auth UUID.';
comment on column public.equine_ownerships.owner_center_id is
  'Center owner when owner_type is CENTER. Center membership does not create this row.';
comment on column public.equine_ownerships.ownership_percentage is
  'Strictly positive share up to 100 inclusive. Zero is rejected. Not an access rule.';
comment on column public.equine_ownerships.status is
  'Provisional foundation lifecycle awaiting Product Owner acceptance: ACTIVE (in force, ended_at null) or ENDED (historical, ended_at required). INVITED, SUSPENDED and verification tokens are not part of this phase.';

create table public.equine_management_assignments (
  id uuid primary key default gen_random_uuid(),
  equine_id uuid not null references public.equines (id),
  manager_type text not null,
  manager_person_id uuid references public.persons (id),
  manager_center_id uuid references public.equestrian_centers (id),
  management_role text not null,
  status text not null default 'ACTIVE',
  valid_from timestamptz not null default now(),
  valid_until timestamptz,
  granted_by_person_id uuid not null references public.persons (id),
  created_at timestamptz not null default now(),
  constraint equine_management_manager_type_check
    check (manager_type in ('PERSON', 'CENTER')),
  constraint equine_management_manager_xor_check
    check (
      (
        manager_type = 'PERSON'
        and manager_person_id is not null
        and manager_center_id is null
      )
      or (
        manager_type = 'CENTER'
        and manager_center_id is not null
        and manager_person_id is null
      )
    ),
  constraint equine_management_role_check
    check (
      management_role in (
        'PRIMARY_MANAGER',
        'CO_MANAGER',
        'AUTHORIZED_MANAGER'
      )
    ),
  constraint equine_management_status_check
    check (status in ('ACTIVE', 'ENDED')),
  constraint equine_management_lifecycle_check
    check (
      (
        status = 'ACTIVE'
        and valid_until is null
      )
      or (
        status = 'ENDED'
        and valid_until is not null
        and valid_until >= valid_from
      )
    )
);

create index equine_management_assignments_equine_id_idx
  on public.equine_management_assignments (equine_id);

create unique index equine_management_one_active_primary_key
  on public.equine_management_assignments (equine_id)
  where status = 'ACTIVE' and management_role = 'PRIMARY_MANAGER';

create unique index equine_management_active_person_role_key
  on public.equine_management_assignments (
    equine_id,
    manager_person_id,
    management_role
  )
  where status = 'ACTIVE' and manager_person_id is not null;

create unique index equine_management_active_center_role_key
  on public.equine_management_assignments (
    equine_id,
    manager_center_id,
    management_role
  )
  where status = 'ACTIVE' and manager_center_id is not null;

comment on table public.equine_management_assignments is
  'Equine management authority. PERSON or CENTER XOR. Not ownership, not center assignment and not a public directory. An owner may also hold a management row.';
comment on column public.equine_management_assignments.management_role is
  'PRIMARY_MANAGER, CO_MANAGER or AUTHORIZED_MANAGER. At most one active PRIMARY_MANAGER per equine. MVP0 publishability later requires a PRIMARY_MANAGER; this phase stores the assignment only.';
comment on column public.equine_management_assignments.status is
  'Provisional foundation lifecycle awaiting Product Owner acceptance: ACTIVE (in force, valid_until null) or ENDED (historical).';
comment on column public.equine_management_assignments.granted_by_person_id is
  'Domain person who granted the assignment during controlled provisioning. Not an Auth UUID and not a client actor argument.';

alter table public.equine_ownerships enable row level security;
alter table public.equine_management_assignments enable row level security;
revoke all on table public.equine_ownerships from anon, authenticated;
revoke all on table public.equine_management_assignments from anon, authenticated;

create function public.has_active_equine_management_role(
  p_person_id uuid,
  p_equine_id uuid,
  p_management_role text
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
     where assignment.manager_person_id = p_person_id
       and assignment.equine_id = p_equine_id
       and assignment.management_role = p_management_role
       and assignment.status = 'ACTIVE'
       and assignment.valid_until is null
  );
$$;

comment on function public.has_active_equine_management_role(uuid, uuid, text) is
  'Server-internal PERSON + equine + management-role check. Not executable by anon or authenticated. Not a roster read and not a membership shortcut.';

revoke all on function public.has_active_equine_management_role(uuid, uuid, text)
  from public, anon, authenticated;

create function public.list_my_equine_ownerships()
returns table (
  ownership_id uuid,
  equine_id uuid,
  equine_name text,
  equine_type text,
  owner_type text,
  ownership_percentage numeric,
  status text,
  started_at timestamptz,
  ended_at timestamptz
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  current_auth_user_id uuid := auth.uid();
  caller_person_id uuid;
begin
  if current_auth_user_id is null then
    raise exception using
      errcode = '42501',
      message = 'Authentication required';
  end if;

  select account.person_id
    into caller_person_id
    from public.user_accounts as account
   where account.auth_user_id = current_auth_user_id;

  if caller_person_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'Identity could not be resolved';
  end if;

  return query
  select
    ownership.id,
    ownership.equine_id,
    equine.name,
    equine.equine_type,
    ownership.owner_type,
    ownership.ownership_percentage,
    ownership.status,
    ownership.started_at,
    ownership.ended_at
  from public.equine_ownerships as ownership
  join public.equines as equine
    on equine.id = ownership.equine_id
  where ownership.owner_person_id = caller_person_id
  order by
    case when ownership.status = 'ACTIVE' then 0 else 1 end,
    ownership.started_at desc,
    ownership.created_at desc;
end;
$$;

comment on function public.list_my_equine_ownerships() is
  'Returns only the authenticated caller''s PERSON ownership rows with safe equine display fields. Person is derived from auth.uid() through user_accounts. Does not expose other owners, CENTER-owned shares, management, or accept a person_id argument.';

revoke all on function public.list_my_equine_ownerships()
  from public, anon, authenticated;
grant execute on function public.list_my_equine_ownerships() to authenticated;

create function public.list_my_equine_management_assignments()
returns table (
  assignment_id uuid,
  equine_id uuid,
  equine_name text,
  equine_type text,
  management_role text,
  status text,
  valid_from timestamptz,
  valid_until timestamptz
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  current_auth_user_id uuid := auth.uid();
  caller_person_id uuid;
begin
  if current_auth_user_id is null then
    raise exception using
      errcode = '42501',
      message = 'Authentication required';
  end if;

  select account.person_id
    into caller_person_id
    from public.user_accounts as account
   where account.auth_user_id = current_auth_user_id;

  if caller_person_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'Identity could not be resolved';
  end if;

  return query
  select
    assignment.id,
    assignment.equine_id,
    equine.name,
    equine.equine_type,
    assignment.management_role,
    assignment.status,
    assignment.valid_from,
    assignment.valid_until
  from public.equine_management_assignments as assignment
  join public.equines as equine
    on equine.id = assignment.equine_id
  where assignment.manager_person_id = caller_person_id
  order by
    case when assignment.status = 'ACTIVE' then 0 else 1 end,
    assignment.valid_from desc,
    assignment.created_at desc;
end;
$$;

comment on function public.list_my_equine_management_assignments() is
  'Returns only the authenticated caller''s PERSON management assignments with safe equine display fields. Person is derived from auth.uid() through user_accounts. Does not expose other managers, CENTER managers, ownership shares, or accept a person_id argument.';

revoke all on function public.list_my_equine_management_assignments()
  from public, anon, authenticated;
grant execute on function public.list_my_equine_management_assignments()
  to authenticated;
