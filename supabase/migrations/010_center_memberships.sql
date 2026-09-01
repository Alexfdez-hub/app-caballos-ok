-- Phase 3E: center memberships foundation.
--
-- Adds public.center_memberships as PERSON + CENTER domain relationships.
-- Does not implement invitations, first-admin bootstrap, Center Policy
-- activation, assessments, equines, services, bookings or staff management.
--
-- Access model follows migrations 006–009:
--   - RLS enabled, deny-by-default, no client table policies.
--   - No table INSERT/UPDATE/DELETE/SELECT for anon or authenticated.
--   - No self-assignment, grant, revoke or bootstrap RPC.
--   - Membership provisioning remains a controlled process outside the app.
--   - Authenticated reads go through a caller-context SECURITY DEFINER RPC.
--
-- Architecture 2.1 names status without enumerating membership values.
-- This migration constrains ACTIVE | ENDED so invalid strings are rejected.
-- Invitation, suspension and reactivation tokens are not invented here.

create table public.center_memberships (
  id uuid primary key default gen_random_uuid(),
  center_id uuid not null references public.equestrian_centers (id),
  person_id uuid not null references public.persons (id),
  role_code text not null,
  status text not null default 'ACTIVE',
  joined_at timestamptz not null default now(),
  ended_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint center_memberships_role_code_check
    check (
      role_code in ('ADMIN', 'MANAGER', 'INSTRUCTOR', 'ASSESSOR')
    ),
  constraint center_memberships_status_check
    check (status in ('ACTIVE', 'ENDED')),
  constraint center_memberships_lifecycle_check
    check (
      (
        status = 'ACTIVE'
        and ended_at is null
      )
      or (
        status = 'ENDED'
        and ended_at is not null
        and ended_at >= joined_at
      )
    )
);

create index center_memberships_center_id_idx
  on public.center_memberships (center_id);

create index center_memberships_person_id_idx
  on public.center_memberships (person_id);

create unique index center_memberships_active_center_person_role_key
  on public.center_memberships (center_id, person_id, role_code)
  where status = 'ACTIVE';

create index center_memberships_active_role_lookup_idx
  on public.center_memberships (person_id, center_id, role_code)
  where status = 'ACTIVE';

comment on table public.center_memberships is
  'Center-scoped PERSON relationship. A row is not ownership, Center Policy acceptance, equine authority, assessment rights or a global account role. Provisioning, grant and revoke remain controlled and are not client-callable.';
comment on column public.center_memberships.id is
  'Stable membership identity. Never an Auth UUID.';
comment on column public.center_memberships.center_id is
  'Equestrian Center this relationship is scoped to. Authority does not transfer to other Centers.';
comment on column public.center_memberships.person_id is
  'Domain identity. Never an Auth UUID and never a user_accounts.id.';
comment on column public.center_memberships.role_code is
  'Internal Center-scoped role: ADMIN, MANAGER, INSTRUCTOR or ASSESSOR. Not a translated display string and not a global users.role.';
comment on column public.center_memberships.status is
  'ACTIVE (currently in force) or ENDED (historical). Invitation and suspension tokens are not part of this foundation.';
comment on column public.center_memberships.joined_at is
  'When this Center/person/role relationship began.';
comment on column public.center_memberships.ended_at is
  'Required when status is ENDED; must be null while ACTIVE. Historical rows are retained.';

alter table public.center_memberships enable row level security;
revoke all on table public.center_memberships from anon, authenticated;

create function public.has_active_center_role(
  p_person_id uuid,
  p_center_id uuid,
  p_role_code text
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1
      from public.center_memberships as membership
     where membership.person_id = p_person_id
       and membership.center_id = p_center_id
       and membership.role_code = p_role_code
       and membership.status = 'ACTIVE'
       and membership.ended_at is null
  );
$$;

comment on function public.has_active_center_role(uuid, uuid, text) is
  'Server-internal PERSON + CENTER + role check. Returns true only for an active membership. Not a global role, not a roster read, and not executable by anon or authenticated clients.';

revoke all on function public.has_active_center_role(uuid, uuid, text)
  from public, anon, authenticated;

create function public.list_my_center_memberships()
returns table (
  membership_id uuid,
  center_id uuid,
  center_name text,
  role_code text,
  status text,
  joined_at timestamptz,
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
    membership.id,
    membership.center_id,
    center.name,
    membership.role_code,
    membership.status,
    membership.joined_at,
    membership.ended_at
  from public.center_memberships as membership
  join public.equestrian_centers as center
    on center.id = membership.center_id
  where membership.person_id = caller_person_id
  order by
    case when membership.status = 'ACTIVE' then 0 else 1 end,
    membership.joined_at desc,
    membership.created_at desc;
end;
$$;

comment on function public.list_my_center_memberships() is
  'Returns only the authenticated caller''s Center memberships with safe Center display fields. Person is derived from auth.uid() through user_accounts. Does not expose other members, grant roles, or accept a person_id argument.';

revoke all on function public.list_my_center_memberships()
  from public, anon, authenticated;
grant execute on function public.list_my_center_memberships() to authenticated;
