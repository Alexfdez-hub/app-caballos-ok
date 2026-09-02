-- Phase 6A: rider assessments foundation.
--
-- Adds public.rider_assessments, public.rider_assessment_disciplines and
-- public.rider_assessment_restrictions. Does not implement Zero Session,
-- rider-equine authorizations, eligibility, bookings, calendar, Expo
-- mutation UI or client-callable create/validate RPC.
--
-- ASSESSMENT != QUALIFICATION != ZERO SESSION != AUTHORIZATION.
-- rider_person_id and assessor_person_id are PERSON identities, never
-- accounts. An assessor cannot assess themselves. Historical authority
-- belongs to the Center: creating or validating requires an active
-- ASSESSOR membership at that Center. Membership is not equine
-- permission. ASSESS_RIDERS on an equine does not create a rider
-- assessment. If the assessor later leaves, the historical row remains.
-- Qualification does not replace assessment.
--
-- Access model follows migrations 006–015:
--   - RLS enabled, deny-by-default, no client table policies.
--   - No table INSERT/UPDATE/DELETE/SELECT for anon or authenticated.
--   - No client create/validate RPC. Current UI has no assessments surface.
--   - Authority is enforced server-side on INSERT/UPDATE of the assessment
--     row via a SECURITY DEFINER trigger. Actor identity is not supplied
--     by the caller; the recorded assessor_person_id is checked.
--   - now() is not used in a table CHECK.

create table public.rider_assessments (
  id uuid primary key default gen_random_uuid(),
  rider_person_id uuid not null references public.persons (id),
  center_id uuid not null references public.equestrian_centers (id),
  assessor_person_id uuid not null references public.persons (id),
  assessment_type text not null,
  performed_at timestamptz,
  valid_until timestamptz,
  status text not null default 'DRAFT',
  general_notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint rider_assessments_type_check
    check (
      assessment_type in (
        'ACCESS_TEST',
        'RIDING_LESSON',
        'COURSE',
        'PRACTICAL_TEST',
        'OTHER'
      )
    ),
  constraint rider_assessments_status_check
    check (
      status in (
        'DRAFT',
        'PENDING',
        'VALID',
        'REJECTED',
        'REVOKED',
        'EXPIRED'
      )
    ),
  constraint rider_assessments_self_assessment_check
    check (rider_person_id <> assessor_person_id),
  constraint rider_assessments_dates_check
    check (
      valid_until is null
      or performed_at is null
      or valid_until >= performed_at
    )
);

create index rider_assessments_rider_person_id_idx
  on public.rider_assessments (rider_person_id);

create index rider_assessments_center_id_idx
  on public.rider_assessments (center_id);

create index rider_assessments_assessor_person_id_idx
  on public.rider_assessments (assessor_person_id);

comment on table public.rider_assessments is
  'Center-owned historical evaluation of a rider PERSON. Not a qualification, not a Zero Session, not rider-equine authorization and not eligibility. Historical rows remain if the assessor later leaves the Center.';
comment on column public.rider_assessments.rider_person_id is
  'Domain rider identity. Never an Auth UUID and never a user_accounts.id.';
comment on column public.rider_assessments.assessor_person_id is
  'Domain assessor identity. Must differ from rider_person_id. Creating or validating requires an active ASSESSOR membership at center_id. Does not grant equine permission.';
comment on column public.rider_assessments.center_id is
  'Center that holds historical assessment authority. Membership at another Center does not authorize this row.';
comment on column public.rider_assessments.assessment_type is
  'Frozen Architecture 2.1 types: ACCESS_TEST, RIDING_LESSON, COURSE, PRACTICAL_TEST or OTHER.';
comment on column public.rider_assessments.status is
  'Frozen Architecture 2.1 states: DRAFT, PENDING, VALID, REJECTED, REVOKED or EXPIRED. Stored EXPIRED is not computed from now().';
comment on column public.rider_assessments.valid_until is
  'Optional end of stored validity. Must not precede performed_at when both exist. now() is not used in a CHECK.';

create table public.rider_assessment_disciplines (
  id uuid primary key default gen_random_uuid(),
  assessment_id uuid not null
    references public.rider_assessments (id) on delete cascade,
  discipline_id uuid not null references public.disciplines (id),
  observed_level text,
  supervision_required boolean not null default false,
  notes text,
  created_at timestamptz not null default now(),
  constraint rider_assessment_disciplines_observed_level_check
    check (
      observed_level is null
      or (
        observed_level = btrim(observed_level)
        and char_length(observed_level) > 0
      )
    )
);

create unique index rider_assessment_disciplines_assessment_discipline_key
  on public.rider_assessment_disciplines (assessment_id, discipline_id);

create index rider_assessment_disciplines_discipline_id_idx
  on public.rider_assessment_disciplines (discipline_id);

comment on table public.rider_assessment_disciplines is
  'Discipline observations for one rider assessment. Deleting the assessment cascades. observed_level is optional free text, not a Galope and not a qualification_level.';
comment on column public.rider_assessment_disciplines.supervision_required is
  'Observed supervision need for this discipline on this assessment. Not an equine requirement and not a Zero Session.';

create table public.rider_assessment_restrictions (
  id uuid primary key default gen_random_uuid(),
  assessment_id uuid not null
    references public.rider_assessments (id) on delete cascade,
  restriction_code text not null,
  value_json jsonb not null default '{}'::jsonb,
  notes text,
  created_at timestamptz not null default now(),
  constraint rider_assessment_restrictions_code_check
    check (
      restriction_code = btrim(restriction_code)
      and char_length(restriction_code) > 0
    ),
  constraint rider_assessment_restrictions_value_json_check
    check (jsonb_typeof(value_json) = 'object')
);

create index rider_assessment_restrictions_assessment_id_idx
  on public.rider_assessment_restrictions (assessment_id);

comment on table public.rider_assessment_restrictions is
  'Architecture 2.1 restriction rows: restriction_code plus JSON object value. Not an eligibility engine and not a hardcoded restriction catalog.';
comment on column public.rider_assessment_restrictions.value_json is
  'JSON object payload for the restriction. Arrays and scalars are rejected. This is stored structure, not eligibility evaluation.';

create function public.enforce_rider_assessment_assessor_authority()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if new.rider_person_id = new.assessor_person_id then
    raise exception using
      errcode = '23514',
      message = 'An assessor cannot assess themselves';
  end if;

  if not public.has_active_center_role(
    new.assessor_person_id,
    new.center_id,
    'ASSESSOR'
  ) then
    raise exception using
      errcode = '42501',
      message = 'Creating or validating a rider assessment requires an active ASSESSOR membership at this Center';
  end if;

  return new;
end;
$$;

comment on function public.enforce_rider_assessment_assessor_authority() is
  'BEFORE INSERT OR UPDATE: recorded assessor_person_id must have an active ASSESSOR membership at center_id. ADMIN/MANAGER/INSTRUCTOR are not inferred. Equine ASSESS_RIDERS is not sufficient. Not executable by anon or authenticated.';

revoke all on function public.enforce_rider_assessment_assessor_authority()
  from public, anon, authenticated;

create trigger rider_assessments_assessor_authority
before insert or update on public.rider_assessments
for each row execute function public.enforce_rider_assessment_assessor_authority();

alter table public.rider_assessments enable row level security;
alter table public.rider_assessment_disciplines enable row level security;
alter table public.rider_assessment_restrictions enable row level security;
revoke all on table public.rider_assessments from anon, authenticated;
revoke all on table public.rider_assessment_disciplines from anon, authenticated;
revoke all on table public.rider_assessment_restrictions from anon, authenticated;
