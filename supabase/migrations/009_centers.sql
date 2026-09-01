-- Phase 3D: equestrian centers foundation.
--
-- Adds public.equestrian_centers and public.center_languages. Does not
-- implement center_memberships, staff roles, Center Policy activation,
-- assessments, equines, services, bookings or public discovery.
--
-- Access model follows migrations 006–008:
--   - RLS enabled, deny-by-default, no client table policies.
--   - No table INSERT/UPDATE/DELETE/SELECT for anon or authenticated.
--   - No self-service creation, verification or management RPC.
--   - Center provisioning remains a controlled process outside the app.
--
-- Architecture 2.1 names verification_status and status without enumerating
-- values for centers. This migration constrains them so invalid strings are
-- rejected. The values do not authorize client verification or publication.

create table public.equestrian_centers (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text not null,
  description text,
  country_code text not null references public.markets (country_code),
  region text,
  city text,
  postal_code text,
  address_line text,
  latitude numeric,
  longitude numeric,
  timezone text,
  default_currency text,
  verification_status text not null default 'UNVERIFIED',
  status text not null default 'DRAFT',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint equestrian_centers_name_check
    check (char_length(btrim(name)) > 0),
  constraint equestrian_centers_slug_format_check
    check (slug = lower(slug) and slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  constraint equestrian_centers_coordinates_check
    check (
      (latitude is null and longitude is null)
      or (
        latitude is not null
        and longitude is not null
        and latitude >= -90
        and latitude <= 90
        and longitude >= -180
        and longitude <= 180
      )
    ),
  constraint equestrian_centers_currency_check
    check (
      default_currency is null
      or default_currency ~ '^[A-Z]{3}$'
    ),
  constraint equestrian_centers_timezone_check
    check (timezone is null or char_length(btrim(timezone)) > 0),
  constraint equestrian_centers_verification_status_check
    check (
      verification_status in (
        'UNVERIFIED',
        'PENDING',
        'VERIFIED',
        'REJECTED'
      )
    ),
  constraint equestrian_centers_status_check
    check (
      status in ('DRAFT', 'ACTIVE', 'INACTIVE', 'ARCHIVED')
    )
);

create unique index equestrian_centers_slug_key
  on public.equestrian_centers (slug);

create index equestrian_centers_country_code_idx
  on public.equestrian_centers (country_code);

comment on table public.equestrian_centers is
  'Canonical equestrian organization. Existence does not grant membership, Center Policy acceptance, equine ownership, management authority, assessment or booking rights. Provisioning and verification remain controlled and are not client-callable.';
comment on column public.equestrian_centers.id is
  'Stable Center domain identity. Never an Auth UUID and never a person_id.';
comment on column public.equestrian_centers.slug is
  'Unique lowercase hyphenated identifier. Not a public directory by itself.';
comment on column public.equestrian_centers.country_code is
  'Market country. Not a Spain-specific constant.';
comment on column public.equestrian_centers.verification_status is
  'UNVERIFIED (default), PENDING, VERIFIED or REJECTED. Clients cannot set VERIFIED.';
comment on column public.equestrian_centers.status is
  'DRAFT (default), ACTIVE, INACTIVE or ARCHIVED. ACTIVE does not publish a discovery feed in this phase.';

create table public.center_languages (
  center_id uuid not null references public.equestrian_centers (id),
  locale text not null,
  created_at timestamptz not null default now(),
  primary key (center_id, locale),
  constraint center_languages_locale_check
    check (locale ~ '^[a-z]{2}(-[A-Z]{2})?$')
);

comment on table public.center_languages is
  'Locales a Center can operate in. Duplicate locales per Center are rejected. Center deletion is restricted so language history is not silently dropped.';
comment on column public.center_languages.locale is
  'BCP 47 language tag, language or language-region. Not hardcoded to Spanish.';

alter table public.equestrian_centers enable row level security;
alter table public.center_languages enable row level security;

revoke all on table public.equestrian_centers from anon, authenticated;
revoke all on table public.center_languages from anon, authenticated;
