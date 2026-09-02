-- Phase 3F: equines foundation.
--
-- Adds public.equines and public.equine_media. Does not implement ownership,
-- management, center assignment, center permissions, disciplines,
-- qualifications, assessments, requirements, services, Zero Session,
-- rider-equine authorizations, availability, calendar, bookings, sessions,
-- public directory or Storage buckets/policies.
--
-- Access model follows migrations 006–010:
--   - RLS enabled, deny-by-default, no client table policies.
--   - No table INSERT/UPDATE/DELETE/SELECT for anon or authenticated.
--   - No client-callable mutation or "my equines" RPC.
--   - Equine provisioning remains a controlled process outside the app.
--   - PUBLIC visibility_status is stored intent only; it does not grant
--     public or authenticated SELECT in this phase.
--
-- Architecture 2.1 freezes equine_type as HORSE | PONY and names status,
-- visibility_status and media_type without enumerating values. Product
-- Owner confirmed equine lifecycle as ACTIVE | INACTIVE | ARCHIVED |
-- DECEASED. Visibility PRIVATE | PUBLIC and media_type PHOTO remain the
-- Phase 3F foundation set. These values do not authorize discovery,
-- ownership, management or upload.

create table public.equines (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  equine_type text not null,
  birth_date date,
  sex text,
  breed text,
  height_cm numeric,
  description text,
  temperament_description text,
  status text not null default 'ACTIVE',
  visibility_status text not null default 'PRIVATE',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint equines_name_check
    check (name = btrim(name) and char_length(name) > 0),
  constraint equines_type_check
    check (equine_type in ('HORSE', 'PONY')),
  constraint equines_sex_check
    check (
      sex is null
      or (sex = btrim(sex) and char_length(sex) > 0)
    ),
  constraint equines_height_cm_check
    check (height_cm is null or height_cm > 0),
  constraint equines_birth_date_check
    check (birth_date is null or birth_date <= created_at::date),
  constraint equines_status_check
    check (status in ('ACTIVE', 'INACTIVE', 'ARCHIVED', 'DECEASED')),
  constraint equines_visibility_status_check
    check (visibility_status in ('PRIVATE', 'PUBLIC'))
);

create index equines_type_idx
  on public.equines (equine_type);

create index equines_status_idx
  on public.equines (status);

comment on table public.equines is
  'Canonical equine identity. HORSE and PONY are types, not separate entities. A row is not ownership, management, center assignment, availability, calendar occupancy, service eligibility or booking rights. Provisioning remains controlled and is not client-callable.';
comment on column public.equines.id is
  'Stable equine domain identity. Never an Auth UUID, person_id, account id, owner_id, manager_id or center_id.';
comment on column public.equines.name is
  'Trimmed non-empty display name. Not a slug and not a public directory key.';
comment on column public.equines.equine_type is
  'Frozen Architecture 2.1 type: HORSE or PONY. Not a translated label and not an access rule.';
comment on column public.equines.height_cm is
  'Optional height in centimetres. When present it must be strictly positive. Not a horse/pony classifier.';
comment on column public.equines.birth_date is
  'Optional calendar date of birth. Null is allowed. Must not be after created_at::date. Age is not stored and this column is not an access rule.';
comment on column public.equines.status is
  'Product Owner confirmed lifecycle: ACTIVE (default, operational record), INACTIVE (temporarily not operational), ARCHIVED (retained historical record of a living equine withdrawn from operational use) or DECEASED (the equine has died). DECEASED is distinct from ARCHIVED. RETIRED is not a token. Not calendar occupancy and not availability. DRAFT is not copied from Centers.';
comment on column public.equines.visibility_status is
  'PRIVATE (default) or PUBLIC. PUBLIC is stored publication intent only; it does not grant public or authenticated SELECT, directory listing or edit authority in this phase.';

create table public.equine_media (
  id uuid primary key default gen_random_uuid(),
  equine_id uuid not null references public.equines (id),
  storage_path text not null,
  media_type text not null,
  sort_order integer not null default 0,
  is_primary boolean not null default false,
  created_at timestamptz not null default now(),
  constraint equine_media_storage_path_check
    check (
      storage_path = btrim(storage_path)
      and char_length(storage_path) > 0
    ),
  constraint equine_media_storage_path_key unique (storage_path),
  constraint equine_media_type_check
    check (media_type in ('PHOTO')),
  constraint equine_media_sort_order_check
    check (sort_order >= 0)
);

create index equine_media_equine_id_idx
  on public.equine_media (equine_id);

create unique index equine_media_one_primary_per_equine_key
  on public.equine_media (equine_id)
  where is_primary;

comment on table public.equine_media is
  'Smallest safe media metadata for an equine. storage_path is a path string only. This phase does not create Storage buckets, storage policies, upload workflow or a production-ready bucket assumption.';
comment on column public.equine_media.id is
  'Stable media metadata identity. Never an Auth UUID.';
comment on column public.equine_media.equine_id is
  'Equine this metadata belongs to. Media does not grant ownership, management or public visibility.';
comment on column public.equine_media.storage_path is
  'Non-empty trimmed object path, unique across equine_media. Not a public URL, not proof that a Storage object exists, and not a Storage bucket, object or policy.';
comment on column public.equine_media.media_type is
  'Phase 3F foundation type: PHOTO. Architecture 2.1 does not mention VIDEO for equine_media; VIDEO is not invented here.';
comment on column public.equine_media.sort_order is
  'Non-negative display order. Does not imply primary media.';
comment on column public.equine_media.is_primary is
  'At most one primary media row per equine. Zero primary rows are allowed. Primary is not publication and not edit authority.';

alter table public.equines enable row level security;
alter table public.equine_media enable row level security;

revoke all on table public.equines from anon, authenticated;
revoke all on table public.equine_media from anon, authenticated;
