-- Phase 3C: rider profile / passport foundations.
--
-- Adds public.rider_profiles as a 1:1 person-owned record. Does not implement
-- disciplines, qualifications, assessments, centers, equines, Session Zero,
-- authorizations or bookings.
--
-- Access model follows migrations 006 and 007:
--   - RLS enabled, deny-by-default, no client table policies.
--   - No table INSERT/UPDATE/DELETE/SELECT for anon or authenticated.
--   - Authenticated reads/writes go through SECURITY DEFINER RPCs.
--   - Actor identity is derived from auth.uid() only.
--
-- Product Owner authorized rider/passport foundations as the next phase.
-- Planned 008_centers remains deferred; this file occupies the next unused
-- migration number 008.

create table public.rider_profiles (
  person_id uuid primary key references public.persons (id),
  bio text,
  experience_start_year smallint,
  profile_visibility text not null default 'PRIVATE',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint rider_profiles_visibility_check
    check (profile_visibility in ('PRIVATE', 'PUBLIC')),
  constraint rider_profiles_experience_year_check
    check (
      experience_start_year is null
      or (
        experience_start_year >= 1900
        and experience_start_year <= 2100
      )
    ),
  constraint rider_profiles_bio_length_check
    check (bio is null or char_length(bio) <= 2000)
);

comment on table public.rider_profiles is
  'One optional equestrian passport foundation per person. Existence does not prove qualification, assessment, guardian consent, Rider Policy acceptance or equine authorization. PUBLIC visibility is stored only; public read is not implemented in 008.';
comment on column public.rider_profiles.person_id is
  'Domain identity. Never an Auth UUID.';
comment on column public.rider_profiles.profile_visibility is
  'PRIVATE (default) or PUBLIC. PUBLIC does not grant a public SELECT path in this phase.';
comment on column public.rider_profiles.experience_start_year is
  'Optional calendar year when riding experience began. Not a riding level or Galope.';

alter table public.rider_profiles enable row level security;
revoke all on table public.rider_profiles from anon, authenticated;

create function public.get_my_rider_profile()
returns table (
  person_id uuid,
  bio text,
  experience_start_year smallint,
  profile_visibility text,
  created_at timestamptz,
  updated_at timestamptz
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
    profile.person_id,
    profile.bio,
    profile.experience_start_year,
    profile.profile_visibility,
    profile.created_at,
    profile.updated_at
  from public.rider_profiles as profile
  where profile.person_id = caller_person_id;
end;
$$;

comment on function public.get_my_rider_profile() is
  'Returns the caller''s rider profile when it exists. Person is derived from auth.uid() through user_accounts.';

revoke all on function public.get_my_rider_profile()
  from public, anon, authenticated;
grant execute on function public.get_my_rider_profile() to authenticated;

create function public.upsert_my_rider_profile(
  p_bio text default null,
  p_experience_start_year smallint default null,
  p_profile_visibility text default 'PRIVATE'
)
returns table (
  person_id uuid,
  bio text,
  experience_start_year smallint,
  profile_visibility text,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  current_auth_user_id uuid := auth.uid();
  caller_person_id uuid;
  normalized_bio text := nullif(btrim(p_bio), '');
  normalized_visibility text := coalesce(nullif(btrim(p_profile_visibility), ''), 'PRIVATE');
  current_year integer := extract(year from (timezone('utc', now()))::date)::integer;
  saved public.rider_profiles%rowtype;
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

  if normalized_visibility not in ('PRIVATE', 'PUBLIC') then
    raise exception using
      errcode = '22023',
      message = 'Profile visibility must be PRIVATE or PUBLIC';
  end if;

  if normalized_bio is not null and char_length(normalized_bio) > 2000 then
    raise exception using
      errcode = '22023',
      message = 'Bio is too long';
  end if;

  if p_experience_start_year is not null
     and (
       p_experience_start_year < 1900
       or p_experience_start_year > current_year
     ) then
    raise exception using
      errcode = '22023',
      message = 'Experience start year is invalid';
  end if;

  insert into public.rider_profiles (
    person_id,
    bio,
    experience_start_year,
    profile_visibility,
    created_at,
    updated_at
  )
  values (
    caller_person_id,
    normalized_bio,
    p_experience_start_year,
    normalized_visibility,
    now(),
    now()
  )
  on conflict on constraint rider_profiles_pkey do update
    set bio = excluded.bio,
        experience_start_year = excluded.experience_start_year,
        profile_visibility = excluded.profile_visibility,
        updated_at = now()
  returning * into saved;

  person_id := saved.person_id;
  bio := saved.bio;
  experience_start_year := saved.experience_start_year;
  profile_visibility := saved.profile_visibility;
  created_at := saved.created_at;
  updated_at := saved.updated_at;
  return next;
end;
$$;

comment on function public.upsert_my_rider_profile(text, smallint, text) is
  'Creates or updates only the authenticated caller''s rider profile. Does not accept a person_id, create policy acceptance, or create guardian consent. Future sensitive Rider actions (bookings, assessments, Session Zero, equine authorization) must still check RIDER_POLICY via has_accepted_required_policy.';

revoke all on function public.upsert_my_rider_profile(text, smallint, text)
  from public, anon, authenticated;
grant execute on function public.upsert_my_rider_profile(text, smallint, text)
  to authenticated;
