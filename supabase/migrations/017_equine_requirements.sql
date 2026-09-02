-- Phase 8A: equine requirements foundation.
--
-- Adds public.equine_requirements. Does not implement eligibility
-- evaluation, Zero Session records, rider-equine authorizations,
-- bookings, calendar, client CRUD or fabricated requirement rows.
--
-- A requirement is attached to an EQUINE. Source type (OWNER, CENTER,
-- MARKET) is provenance, not mutation authority. Ownership is not
-- management. Center assignment or membership does not grant
-- MANAGE_REQUIREMENTS and does not open a client write path.
-- Age is not stored on persons or rider_profiles. Numeric age bounds
-- are requirement values, not rider age and not Spanish adulthood.
--
-- Architecture 2.1 already names typed value columns
-- (numeric_value, boolean_value, text_value, qualification_level_id).
-- This migration maps each frozen requirement_type onto the matching
-- column set. That is not a new polymorphic model.
--
-- Access model follows migrations 006–016:
--   - RLS enabled, deny-by-default, no client table policies.
--   - No table INSERT/UPDATE/DELETE/SELECT for anon or authenticated.
--   - No client create/update RPC. Current UI has no requirements surface.

create table public.equine_requirements (
  id uuid primary key default gen_random_uuid(),
  equine_id uuid not null references public.equines (id),
  requirement_type text not null,
  discipline_id uuid references public.disciplines (id),
  qualification_level_id uuid references public.qualification_levels (id),
  numeric_value numeric,
  boolean_value boolean,
  text_value text,
  source_type text not null,
  source_id uuid,
  status text not null default 'ACTIVE',
  created_at timestamptz not null default now(),
  constraint equine_requirements_type_check
    check (
      requirement_type in (
        'MIN_AGE',
        'MAX_AGE',
        'MIN_QUALIFICATION',
        'CENTER_ASSESSMENT_REQUIRED',
        'ZERO_SESSION_REQUIRED',
        'OWNER_APPROVAL_REQUIRED',
        'SUPERVISION_REQUIRED',
        'MIN_EXPERIENCE'
      )
    ),
  constraint equine_requirements_source_type_check
    check (source_type in ('OWNER', 'CENTER', 'MARKET')),
  constraint equine_requirements_status_check
    check (status in ('ACTIVE', 'INACTIVE')),
  constraint equine_requirements_text_value_check
    check (
      text_value is null
      or (
        text_value = btrim(text_value)
        and char_length(text_value) > 0
      )
    ),
  constraint equine_requirements_typed_value_check
    check (
      case requirement_type
        when 'MIN_AGE' then
          numeric_value is not null
          and numeric_value >= 0
          and boolean_value is null
          and text_value is null
          and qualification_level_id is null
        when 'MAX_AGE' then
          numeric_value is not null
          and numeric_value >= 0
          and boolean_value is null
          and text_value is null
          and qualification_level_id is null
        when 'MIN_EXPERIENCE' then
          numeric_value is not null
          and numeric_value >= 0
          and boolean_value is null
          and text_value is null
          and qualification_level_id is null
        when 'MIN_QUALIFICATION' then
          qualification_level_id is not null
          and numeric_value is null
          and boolean_value is null
          and text_value is null
        when 'CENTER_ASSESSMENT_REQUIRED' then
          boolean_value is not null
          and numeric_value is null
          and text_value is null
          and qualification_level_id is null
        when 'ZERO_SESSION_REQUIRED' then
          boolean_value is not null
          and numeric_value is null
          and text_value is null
          and qualification_level_id is null
        when 'OWNER_APPROVAL_REQUIRED' then
          boolean_value is not null
          and numeric_value is null
          and text_value is null
          and qualification_level_id is null
        when 'SUPERVISION_REQUIRED' then
          boolean_value is not null
          and numeric_value is null
          and text_value is null
          and qualification_level_id is null
        else false
      end
    )
);

create index equine_requirements_equine_id_idx
  on public.equine_requirements (equine_id);

create index equine_requirements_discipline_id_idx
  on public.equine_requirements (discipline_id);

create index equine_requirements_qualification_level_id_idx
  on public.equine_requirements (qualification_level_id);

comment on table public.equine_requirements is
  'Requirement attached to an equine. Source is provenance, not write authority. Not eligibility evaluation, not rider age storage, not Zero Session and not authorization.';
comment on column public.equine_requirements.requirement_type is
  'Frozen Architecture 2.1 types: MIN_AGE, MAX_AGE, MIN_QUALIFICATION, CENTER_ASSESSMENT_REQUIRED, ZERO_SESSION_REQUIRED, OWNER_APPROVAL_REQUIRED, SUPERVISION_REQUIRED, MIN_EXPERIENCE.';
comment on column public.equine_requirements.numeric_value is
  'Required for MIN_AGE, MAX_AGE and MIN_EXPERIENCE. Non-negative. Not a stored rider age and not a hardcoded adulthood threshold.';
comment on column public.equine_requirements.boolean_value is
  'Required for CENTER_ASSESSMENT_REQUIRED, ZERO_SESSION_REQUIRED, OWNER_APPROVAL_REQUIRED and SUPERVISION_REQUIRED.';
comment on column public.equine_requirements.qualification_level_id is
  'Required for MIN_QUALIFICATION. Optional unused (must be null) for other types.';
comment on column public.equine_requirements.discipline_id is
  'Optional typed discipline scope. Null means the requirement is not discipline-scoped.';
comment on column public.equine_requirements.source_type is
  'OWNER, CENTER or MARKET provenance. Not mutation authority.';
comment on column public.equine_requirements.source_id is
  'Optional opaque source identity. No polymorphic FK in this foundation.';
comment on column public.equine_requirements.status is
  'Catalog operational pair ACTIVE | INACTIVE, reused from the Product Owner-approved disciplines pair (2026-09-02). Not an eligibility result.';

alter table public.equine_requirements enable row level security;
revoke all on table public.equine_requirements from anon, authenticated;
