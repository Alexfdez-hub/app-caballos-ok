-- Phase 8B: center services foundation.
--
-- Adds public.center_services and public.service_equines. Does not
-- implement Zero Session records, rider-equine authorization logic,
-- availability, calendar, bookings, sessions or Expo catalogs.
--
-- A service belongs to one Center. Linking an equine requires an
-- effective MANAGE_REQUIREMENTS permission at that service's Center.
-- Membership, ownership and assignment do not permit linking any equine.
-- The service row itself does not grant equine authority.
--
-- Product Owner approved catalog lifecycle ACTIVE | INACTIVE for
-- center_services.status and service_equines.status (2026-09-02),
-- reusing the disciplines/qualifications/equine_requirements pair.
-- authorization_policy remains optional trimmed non-empty free text.
-- Do not invent a policy enum or authorization engine in 018.
-- Service type tokens are frozen:
-- EQUINE_SESSION, RIDER_ASSESSMENT, ZERO_SESSION.
--
-- Access model follows migrations 006–017:
--   - RLS enabled, deny-by-default, no client table policies.
--   - No table INSERT/UPDATE/DELETE/SELECT for anon or authenticated.
--   - No client create/link RPC. Current UI has no services catalog.
--   - now() is not used in a table CHECK.

create table public.center_services (
  id uuid primary key default gen_random_uuid(),
  center_id uuid not null references public.equestrian_centers (id),
  service_type text not null,
  name text not null,
  description text,
  default_duration_minutes integer,
  status text not null default 'ACTIVE',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint center_services_type_check
    check (
      service_type in (
        'EQUINE_SESSION',
        'RIDER_ASSESSMENT',
        'ZERO_SESSION'
      )
    ),
  constraint center_services_name_check
    check (name = btrim(name) and char_length(name) > 0),
  constraint center_services_duration_check
    check (
      default_duration_minutes is null
      or default_duration_minutes > 0
    ),
  constraint center_services_status_check
    check (status in ('ACTIVE', 'INACTIVE'))
);

create index center_services_center_id_idx
  on public.center_services (center_id);

comment on table public.center_services is
  'A service offered by one Center. Not equine authority, not a Zero Session record, not a booking and not a calendar block.';
comment on column public.center_services.service_type is
  'Frozen Architecture 2.1 MVP0 types: EQUINE_SESSION, RIDER_ASSESSMENT or ZERO_SESSION. ZERO_SESSION here is a service kind, not a zero_sessions row.';
comment on column public.center_services.status is
  'Product Owner approved lifecycle (2026-09-02): ACTIVE or INACTIVE. Reuses the catalog pair. Not DRAFT, ARCHIVED or REVOKED. Default ACTIVE.';
comment on column public.center_services.default_duration_minutes is
  'Optional positive duration in minutes. Null is allowed. now() is not used in a CHECK.';

create table public.service_equines (
  id uuid primary key default gen_random_uuid(),
  service_id uuid not null
    references public.center_services (id) on delete cascade,
  equine_id uuid not null references public.equines (id),
  enabled boolean not null default true,
  supervision_required boolean not null default false,
  requirements jsonb not null default '{}'::jsonb,
  duration_limit_minutes integer,
  authorization_policy text,
  status text not null default 'ACTIVE',
  created_at timestamptz not null default now(),
  constraint service_equines_requirements_check
    check (jsonb_typeof(requirements) = 'object'),
  constraint service_equines_duration_check
    check (
      duration_limit_minutes is null
      or duration_limit_minutes > 0
    ),
  constraint service_equines_authorization_policy_check
    check (
      authorization_policy is null
      or (
        authorization_policy = btrim(authorization_policy)
        and char_length(authorization_policy) > 0
      )
    ),
  constraint service_equines_status_check
    check (status in ('ACTIVE', 'INACTIVE'))
);

create unique index service_equines_service_equine_key
  on public.service_equines (service_id, equine_id);

create index service_equines_equine_id_idx
  on public.service_equines (equine_id);

comment on table public.service_equines is
  'Link between an existing center_services row and an existing equine. Duplicate service+equine is rejected. Deleting the service cascades. Linking requires effective MANAGE_REQUIREMENTS at the service Center. The link does not grant equine authority.';
comment on column public.service_equines.enabled is
  'Whether this link is currently offered. Distinct from catalog status ACTIVE|INACTIVE.';
comment on column public.service_equines.authorization_policy is
  'Optional trimmed non-empty free text when present. Product Owner (2026-09-02): no enum and no authorization engine in 018. Vocabulary belongs to the later authorization / Zero Session / booking train.';
comment on column public.service_equines.status is
  'Product Owner approved lifecycle (2026-09-02): ACTIVE or INACTIVE. Reuses the catalog pair. Not DRAFT, ARCHIVED or REVOKED. Default ACTIVE.';

create function public.enforce_service_equine_manage_requirements()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  service_center uuid;
  target_service uuid;
  target_equine uuid;
begin
  if TG_OP = 'UPDATE'
     and (
       new.service_id is distinct from old.service_id
       or new.equine_id is distinct from old.equine_id
     ) then
    raise exception using
      errcode = '42501',
      message = 'Service-equine identity cannot be rewritten';
  end if;

  if TG_OP = 'DELETE' then
    target_service := old.service_id;
    target_equine := old.equine_id;
  else
    target_service := new.service_id;
    target_equine := new.equine_id;
  end if;

  select service.center_id
    into service_center
    from public.center_services as service
   where service.id = target_service;

  if service_center is null then
    if TG_OP = 'DELETE' then
      return old;
    end if;
    raise exception using
      errcode = '23503',
      message = 'Service does not exist';
  end if;

  if not public.has_active_equine_center_permission(
    target_equine,
    service_center,
    'MANAGE_REQUIREMENTS'
  ) then
    raise exception using
      errcode = '42501',
      message = 'Linking a service equine requires effective MANAGE_REQUIREMENTS at the service Center';
  end if;

  if TG_OP = 'DELETE' then
    return old;
  end if;

  return new;
end;
$$;

comment on function public.enforce_service_equine_manage_requirements() is
  'BEFORE INSERT OR UPDATE OR DELETE on service_equines: effective MANAGE_REQUIREMENTS at the service Center is required. Membership and assignment are not sufficient. Identity columns cannot be retargeted. Not executable by anon or authenticated.';

revoke all on function public.enforce_service_equine_manage_requirements()
  from public, anon, authenticated;

create trigger service_equines_manage_requirements
before insert or update or delete on public.service_equines
for each row execute function public.enforce_service_equine_manage_requirements();

alter table public.center_services enable row level security;
alter table public.service_equines enable row level security;
revoke all on table public.center_services from anon, authenticated;
revoke all on table public.service_equines from anon, authenticated;
