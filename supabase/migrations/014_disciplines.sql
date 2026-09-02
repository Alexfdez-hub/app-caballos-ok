-- Phase 5A: disciplines foundation.
--
-- Adds public.disciplines, public.discipline_translations and
-- public.equine_disciplines. Does not implement qualification systems,
-- qualification levels, rider qualifications, assessments, bookings,
-- eligibility, Expo selectors or mutation RPC.
--
-- A discipline code is a catalog identity, not a Galope level and not an
-- international equivalence. This migration does not seed a catalog:
-- Product Owner must supply authoritative codes before any seed.
-- experience_level on equine_disciplines is optional free text; it is not
-- a qualification and is not constrained to invented tokens.
--
-- Access model follows migrations 006–013:
--   - RLS enabled, deny-by-default, no client table policies.
--   - No table INSERT/UPDATE/DELETE/SELECT for anon or authenticated.
--   - No client list/create/assign RPC.
--   - Catalog and association provisioning remain controlled outside the app.

create table public.disciplines (
  id uuid primary key default gen_random_uuid(),
  code text not null,
  status text not null default 'ACTIVE',
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  constraint disciplines_code_check
    check (code = btrim(code) and char_length(code) > 0),
  constraint disciplines_status_check
    check (status in ('ACTIVE', 'INACTIVE'))
);

create unique index disciplines_code_key
  on public.disciplines (code);

comment on table public.disciplines is
  'Coded discipline catalog identity. Not a qualification system, not a Galope level and not an automatic international equivalence. This foundation does not seed codes.';
comment on column public.disciplines.code is
  'Unique trimmed non-empty catalog code. Not a translated label and not a riding-level token.';
comment on column public.disciplines.status is
  'ACTIVE (in the catalog) or INACTIVE (retained, not operational). Not ARCHIVED and not a qualification verification state.';
comment on column public.disciplines.sort_order is
  'Display ordering hint. Duplicates are allowed. Not an access rule.';

create table public.discipline_translations (
  id uuid primary key default gen_random_uuid(),
  discipline_id uuid not null references public.disciplines (id),
  locale text not null,
  name text not null,
  description text,
  created_at timestamptz not null default now(),
  constraint discipline_translations_locale_check
    check (locale ~ '^[a-z]{2}(-[A-Z]{2})?$'),
  constraint discipline_translations_name_check
    check (name = btrim(name) and char_length(name) > 0)
);

create unique index discipline_translations_discipline_locale_key
  on public.discipline_translations (discipline_id, locale);

comment on table public.discipline_translations is
  'Localized name and optional description for a discipline code. Duplicate locale per discipline is rejected. Not a catalog seed.';
comment on column public.discipline_translations.locale is
  'BCP 47 language tag, language or language-region. Not hardcoded to Spanish.';

create table public.equine_disciplines (
  id uuid primary key default gen_random_uuid(),
  equine_id uuid not null references public.equines (id),
  discipline_id uuid not null references public.disciplines (id),
  experience_level text,
  notes text,
  created_at timestamptz not null default now(),
  constraint equine_disciplines_experience_level_check
    check (
      experience_level is null
      or (
        experience_level = btrim(experience_level)
        and char_length(experience_level) > 0
      )
    )
);

create unique index equine_disciplines_equine_discipline_key
  on public.equine_disciplines (equine_id, discipline_id);

create index equine_disciplines_discipline_id_idx
  on public.equine_disciplines (discipline_id);

comment on table public.equine_disciplines is
  'Association of an equine with a discipline code. Not ownership, management, center assignment, qualification or booking eligibility. Duplicate equine+discipline rows are rejected.';
comment on column public.equine_disciplines.experience_level is
  'Optional free-text note. Not a Galope, not a qualification_level and not an invented token set.';

alter table public.disciplines enable row level security;
alter table public.discipline_translations enable row level security;
alter table public.equine_disciplines enable row level security;
revoke all on table public.disciplines from anon, authenticated;
revoke all on table public.discipline_translations from anon, authenticated;
revoke all on table public.equine_disciplines from anon, authenticated;
