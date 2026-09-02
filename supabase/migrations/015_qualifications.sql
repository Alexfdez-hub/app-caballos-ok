-- Phase 5B: qualifications foundation.
--
-- Adds public.qualification_systems, public.qualification_levels and
-- public.rider_qualifications. Does not implement assessments,
-- authorizations, eligibility, Zero Session, bookings, Expo selectors,
-- mutation RPC or a caller-scoped read RPC.
--
-- A qualification belongs to a rider PERSON, never to an account.
-- QUALIFICATION != ASSESSMENT != AUTHORIZATION. verified_by_person_id is a
-- person identity and does not imply Center membership, equine permission
-- or assessment authority. This migration does not seed a catalog:
-- Product Owner must supply authoritative systems/levels before any seed.
-- Architecture 2.1 forbids hardcoded Galopes and automatic international
-- equivalences. level_order is an ordering hint inside one system, not an
-- international rank.
--
-- Architecture 2.1 names status on systems/levels without enumerating
-- values. This migration reuses the Product Owner-approved catalog
-- operational pair ACTIVE | INACTIVE (2026-09-02, disciplines) so invalid
-- strings are rejected. That pair is not a qualification verification
-- state. Invitation, equivalence and assessment tokens are not invented.
-- Rider verification_status is frozen exactly as
-- DECLARED | PENDING | VERIFIED | REJECTED | EXPIRED.
--
-- Access model follows migrations 006–014:
--   - RLS enabled, deny-by-default, no client table policies.
--   - No table INSERT/UPDATE/DELETE/SELECT for anon or authenticated.
--   - No client list/declare/verify RPC. Current UI has no qualifications
--     surface that requires a caller-scoped read.
--   - Catalog and rider-qualification provisioning remain controlled
--     outside the app.

create table public.qualification_systems (
  id uuid primary key default gen_random_uuid(),
  code text not null,
  name text not null,
  country_code text references public.markets (country_code),
  issuing_organization text,
  status text not null default 'ACTIVE',
  created_at timestamptz not null default now(),
  constraint qualification_systems_code_check
    check (code = btrim(code) and char_length(code) > 0),
  constraint qualification_systems_name_check
    check (name = btrim(name) and char_length(name) > 0),
  constraint qualification_systems_issuing_organization_check
    check (
      issuing_organization is null
      or (
        issuing_organization = btrim(issuing_organization)
        and char_length(issuing_organization) > 0
      )
    ),
  constraint qualification_systems_status_check
    check (status in ('ACTIVE', 'INACTIVE'))
);

create unique index qualification_systems_code_key
  on public.qualification_systems (code);

create index qualification_systems_country_code_idx
  on public.qualification_systems (country_code);

comment on table public.qualification_systems is
  'Configurable qualification catalog identity. May be market/country scoped via optional country_code. Not a Galope seed, not an international equivalence table and not an assessment. This foundation does not seed codes.';
comment on column public.qualification_systems.code is
  'Globally unique trimmed non-empty catalog code. Not a translated label and not a riding-level token.';
comment on column public.qualification_systems.country_code is
  'Optional market scope. Null means the system is not bound to one market. Not an automatic equivalence key.';
comment on column public.qualification_systems.issuing_organization is
  'Optional issuer name for the system. Not a person, not a Center and not verification authority.';
comment on column public.qualification_systems.status is
  'Catalog operational pair ACTIVE (in the catalog) or INACTIVE (retained, not operational). Reuses the Product Owner-approved disciplines pair (2026-09-02). Not a rider verification state.';

create table public.qualification_levels (
  id uuid primary key default gen_random_uuid(),
  qualification_system_id uuid not null
    references public.qualification_systems (id),
  code text not null,
  level_order integer not null default 0,
  name text not null,
  description text,
  discipline_id uuid references public.disciplines (id),
  status text not null default 'ACTIVE',
  created_at timestamptz not null default now(),
  constraint qualification_levels_code_check
    check (code = btrim(code) and char_length(code) > 0),
  constraint qualification_levels_name_check
    check (name = btrim(name) and char_length(name) > 0),
  constraint qualification_levels_order_check
    check (level_order >= 0),
  constraint qualification_levels_status_check
    check (status in ('ACTIVE', 'INACTIVE'))
);

create unique index qualification_levels_system_code_key
  on public.qualification_levels (qualification_system_id, code);

create index qualification_levels_system_id_idx
  on public.qualification_levels (qualification_system_id);

create index qualification_levels_discipline_id_idx
  on public.qualification_levels (discipline_id);

comment on table public.qualification_levels is
  'A level belonging to exactly one qualification_system. Level code uniqueness is scoped to that system. Not an international equivalence and not an assessment result.';
comment on column public.qualification_levels.level_order is
  'Non-negative ordering hint inside one system. Duplicate values are allowed. Not an international rank and not an automatic equivalence.';
comment on column public.qualification_levels.discipline_id is
  'Optional typed reference to a discipline. Null is allowed by Architecture 2.1. Not a Galope and not required for the level to exist.';
comment on column public.qualification_levels.status is
  'Catalog operational pair ACTIVE | INACTIVE, same meaning as qualification_systems.status. Not a rider verification state.';

create table public.rider_qualifications (
  id uuid primary key default gen_random_uuid(),
  rider_person_id uuid not null references public.persons (id),
  qualification_level_id uuid not null
    references public.qualification_levels (id),
  certificate_number text,
  issued_at timestamptz,
  expires_at timestamptz,
  verification_status text not null default 'DECLARED',
  verified_by_person_id uuid references public.persons (id),
  document_path text,
  created_at timestamptz not null default now(),
  constraint rider_qualifications_certificate_number_check
    check (
      certificate_number is null
      or (
        certificate_number = btrim(certificate_number)
        and char_length(certificate_number) > 0
      )
    ),
  constraint rider_qualifications_document_path_check
    check (
      document_path is null
      or (
        document_path = btrim(document_path)
        and char_length(document_path) > 0
      )
    ),
  constraint rider_qualifications_dates_check
    check (
      expires_at is null
      or issued_at is null
      or expires_at >= issued_at
    ),
  constraint rider_qualifications_verification_status_check
    check (
      verification_status in (
        'DECLARED',
        'PENDING',
        'VERIFIED',
        'REJECTED',
        'EXPIRED'
      )
    ),
  constraint rider_qualifications_verified_actor_check
    check (
      verification_status <> 'VERIFIED'
      or verified_by_person_id is not null
    ),
  constraint rider_qualifications_self_verification_check
    check (verified_by_person_id is distinct from rider_person_id)
);

create index rider_qualifications_rider_person_id_idx
  on public.rider_qualifications (rider_person_id);

create index rider_qualifications_qualification_level_id_idx
  on public.rider_qualifications (qualification_level_id);

create index rider_qualifications_verified_by_person_id_idx
  on public.rider_qualifications (verified_by_person_id);

comment on table public.rider_qualifications is
  'A qualification held by a rider PERSON. Not an account attribute, not an assessment, not a Zero Session, not rider-equine authorization and not eligibility.';
comment on column public.rider_qualifications.rider_person_id is
  'Domain rider identity. Never an Auth UUID and never a user_accounts.id.';
comment on column public.rider_qualifications.verification_status is
  'Frozen Architecture 2.1 states exactly: DECLARED, PENDING, VERIFIED, REJECTED or EXPIRED. Stored EXPIRED is not computed from now().';
comment on column public.rider_qualifications.verified_by_person_id is
  'Optional person who recorded VERIFIED. Required when verification_status is VERIFIED. Must not be the rider. Does not imply Center membership, equine permission, assessment authority or a Center acting as issuer.';
comment on column public.rider_qualifications.document_path is
  'Optional private document metadata path. 015 does not create a Storage bucket and does not grant public read.';
comment on column public.rider_qualifications.issued_at is
  'Optional issuance timestamp. expires_at must not precede issued_at when both are present. now() is not used in a CHECK.';

alter table public.qualification_systems enable row level security;
alter table public.qualification_levels enable row level security;
alter table public.rider_qualifications enable row level security;
revoke all on table public.qualification_systems from anon, authenticated;
revoke all on table public.qualification_levels from anon, authenticated;
revoke all on table public.rider_qualifications from anon, authenticated;
