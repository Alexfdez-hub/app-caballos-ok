-- Phase 11B: booking eligibility and confirm RPCs.
--
-- Adds check_booking_eligibility(), create_booking_request() and
-- confirm_booking(). Does not implement approve_zero_session(),
-- sessions, client table CRUD or a waive path.
--
-- Does not edit migrations 001–021. CREATE OR REPLACE replaces the
-- 020 calendar-block authority function and the 021 booking authority
-- function so confirm_booking can set CONFIRMED and insert BOOKING
-- occupancy when transaction-local app.confirming_booking = '1'.
--
-- Product Owner 2026-09-02 (PR #19):
--   check callers are the participant account, a current VERIFIED
--   guardian, or effective MANAGE_BOOKINGS for that equine+Center;
--   create_booking_request never confirms;
--   confirm_booking requires MANAGE_BOOKINGS, accepts only APPROVED,
--   and the booker cannot self-confirm merely by being the booker;
--   ZERO_SESSION_REQUIRED needs a currently effective ZERO_SESSION
--   authorization (a Zero Session result alone is not enough);
--   OWNER_APPROVAL_REQUIRED needs currently effective OWNER_APPROVAL;
--   CENTER_ASSESSMENT_REQUIRED needs a current VALID assessment at
--   that Center;
--   guardian consent and required current policy acceptances are
--   independent; there is no waiver;
--   service-equine compatibility is required when a service is named;
--   MIN_QUALIFICATION / MIN_EXPERIENCE are evaluated (no Galope engine);
--   policy acceptance subject is always the participant PERSON;
--   guardian/staff own acceptances never substitute;
--   multiple active locales/codes of one type are not an automatic fail;
--   confirm snapshots every evaluated requirement and the exact policy
--   documents/acceptances used, materialized in one SQL statement;
--   confirm is atomic: revalidate, occupy with a BOOKING calendar
--   block, snapshot, set CONFIRMED; rollback on any failure;
--   concurrent conflicting confirms cannot both succeed (020 gist);
--   no caller-controlled pause GUC or advisory-lock test hook in
--   the deployable confirm RPC.
-- now() is not used in a table CHECK. This migration adds no tables.
--
-- Access model follows migrations 006–021:
--   - Existing table RLS stays deny-by-default.
--   - No table INSERT/UPDATE/DELETE/SELECT for anon or authenticated.
--   - The three public RPCs are executable by authenticated only.
--   - Internal helpers stay revoked from PUBLIC, anon and authenticated.

create or replace function public.enforce_equine_calendar_block_manage_authority()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if TG_OP = 'DELETE' then
    raise exception using
      errcode = '42501',
      message = 'Calendar blocks cannot be deleted';
  end if;

  if TG_OP = 'UPDATE' then
    if new.equine_id is distinct from old.equine_id
       or new.center_id is distinct from old.center_id
       or new.created_by_account_id is distinct from old.created_by_account_id
       or new.created_at is distinct from old.created_at then
      raise exception using
        errcode = '42501',
        message = 'Historical calendar block identity cannot be rewritten';
    end if;

    if old.status = 'ACTIVE'
       and new.status = 'CANCELLED'
       and old.cancelled_at is null
       and new.cancelled_at is not null
       and new.starts_at is not distinct from old.starts_at
       and new.ends_at is not distinct from old.ends_at
       and new.block_type is not distinct from old.block_type
       and new.source_type is not distinct from old.source_type
       and new.source_id is not distinct from old.source_id then
      return new;
    end if;
  end if;

  if current_setting('app.confirming_booking', true) = '1'
     and TG_OP = 'INSERT'
     and new.block_type = 'BOOKING'
     and new.source_type = 'BOOKING'
     and new.status = 'ACTIVE' then
    return new;
  end if;

  if not public.has_active_equine_center_permission(
    new.equine_id,
    new.center_id,
    'MANAGE_AVAILABILITY'
  ) then
    raise exception using
      errcode = '42501',
      message = 'Calendar occupancy changes require effective MANAGE_AVAILABILITY for this equine at this Center';
  end if;

  return new;
end;
$$;

comment on function public.enforce_equine_calendar_block_manage_authority() is
  'BEFORE INSERT OR UPDATE OR DELETE: INSERT/mutation requires effective MANAGE_AVAILABILITY unless confirm_booking sets app.confirming_booking=1 for a BOOKING occupancy insert. Cancel-only UPDATE does not re-check authority. Identity cannot be retargeted. DELETE is rejected. Not executable by anon or authenticated.';

create or replace function public.enforce_booking_request_authority()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  booker_person uuid;
  service_center uuid;
  critical_states text[] := array['CONFIRMED', 'ACTIVE', 'COMPLETED'];
  confirming boolean := current_setting('app.confirming_booking', true) = '1';
begin
  if TG_OP = 'DELETE' then
    if old.status = any(critical_states) then
      raise exception using
        errcode = '42501',
        message = 'Confirmed booking history cannot be deleted';
    end if;
    return old;
  end if;

  if TG_OP = 'UPDATE' then
    if new.participant_person_id is distinct from old.participant_person_id
       or new.booked_by_account_id is distinct from old.booked_by_account_id
       or new.equine_id is distinct from old.equine_id
       or new.center_id is distinct from old.center_id
       or new.service_id is distinct from old.service_id then
      raise exception using
        errcode = '42501',
        message = 'Historical booking identity cannot be rewritten';
    end if;

    if old.status = any(critical_states) then
      if new.starts_at is distinct from old.starts_at
         or new.ends_at is distinct from old.ends_at
         or new.booking_policy_snapshot is distinct from old.booking_policy_snapshot
         or new.confirmed_at is distinct from old.confirmed_at then
        raise exception using
          errcode = '42501',
          message = 'Confirmed booking history cannot be silently rewritten';
      end if;
    end if;

    if old.status is distinct from new.status
       and new.status = any(critical_states) then
      if not (
        confirming
        and old.status = 'APPROVED'
        and new.status = 'CONFIRMED'
      ) then
        raise exception using
          errcode = '42501',
          message = '021 cannot force CONFIRMED, ACTIVE or COMPLETED';
      end if;
    end if;
  end if;

  if TG_OP = 'INSERT' and new.status = any(critical_states) then
    raise exception using
      errcode = '42501',
      message = '021 cannot insert CONFIRMED, ACTIVE or COMPLETED bookings';
  end if;

  select account.person_id
    into booker_person
    from public.user_accounts as account
   where account.id = new.booked_by_account_id;

  if booker_person is null then
    raise exception using
      errcode = '23503',
      message = 'Booking booker account must have a PERSON';
  end if;

  if booker_person is distinct from new.participant_person_id
     and not public.has_current_verified_guardian_relationship(
       booker_person,
       new.participant_person_id
     ) then
    raise exception using
      errcode = '42501',
      message = 'A booker may request only for their own PERSON or a minor with a current VERIFIED guardian relationship';
  end if;

  select service.center_id
    into service_center
    from public.center_services as service
   where service.id = new.service_id;

  if service_center is null then
    raise exception using
      errcode = '23503',
      message = 'Booking requires an existing service';
  end if;

  if service_center is distinct from new.center_id then
    raise exception using
      errcode = '23514',
      message = 'Booking center must match the service Center';
  end if;

  return new;
end;
$$;

comment on function public.enforce_booking_request_authority() is
  'BEFORE INSERT OR UPDATE OR DELETE: booker is own PERSON or current VERIFIED guardian. Service must belong to center_id. Identity cannot be retargeted. CONFIRMED is allowed only from APPROVED when confirm_booking sets app.confirming_booking=1. ACTIVE/COMPLETED still cannot be forced. Confirmed history cannot be rewritten. Not executable by anon or authenticated.';

create function public.policy_document_is_effective_at(
  p_effective_from timestamptz,
  p_effective_to timestamptz,
  p_status text,
  p_reference_time timestamptz
)
returns boolean
language sql
immutable
set search_path = pg_catalog, public
as $$
  select p_status = 'ACTIVE'
     and p_effective_from is not null
     and p_reference_time is not null
     and p_effective_from <= p_reference_time
     and (
       p_effective_to is null
       or p_effective_to > p_reference_time
     );
$$;

comment on function public.policy_document_is_effective_at(timestamptz, timestamptz, text, timestamptz) is
  'True when an ACTIVE policy document is effective at the reference time. Translations are not considered here. Not executable by PUBLIC, anon or authenticated.';

revoke all on function public.policy_document_is_effective_at(timestamptz, timestamptz, text, timestamptz)
  from public, anon, authenticated;

create function public.has_ambiguous_current_policy_versions(
  p_policy_type text,
  p_market_code text,
  p_reference_time timestamptz
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1
      from public.policy_documents as document
     where document.policy_type = p_policy_type
       and document.market_code = p_market_code
       and public.policy_document_is_effective_at(
         document.effective_from,
         document.effective_to,
         document.status,
         p_reference_time
       )
     group by document.policy_code
    having count(distinct document.version) > 1
  );
$$;

comment on function public.has_ambiguous_current_policy_versions(text, text, timestamptz) is
  'True when one policy_code of that type+market has more than one version simultaneously current at the reference time. Locales of the same version are not ambiguous. Fail closed; do not guess. Not executable by PUBLIC, anon or authenticated.';

revoke all on function public.has_ambiguous_current_policy_versions(text, text, timestamptz)
  from public, anon, authenticated;

create function public.has_verified_guardian_relationship_at(
  p_guardian_person_id uuid,
  p_minor_person_id uuid,
  p_reference_time timestamptz
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1
      from public.guardian_relationships as relationship
     where relationship.guardian_person_id = p_guardian_person_id
       and relationship.minor_person_id = p_minor_person_id
       and relationship.verification_status = 'VERIFIED'
       and relationship.revoked_at is null
       and (
         relationship.verified_at is null
         or relationship.verified_at <= p_reference_time
       )
       and (
         relationship.expires_at is null
         or relationship.expires_at > p_reference_time
       )
  );
$$;

comment on function public.has_verified_guardian_relationship_at(uuid, uuid, timestamptz) is
  'Server-internal VERIFIED guardian relationship effective at the activity reference time. Not executable by PUBLIC, anon or authenticated.';

revoke all on function public.has_verified_guardian_relationship_at(uuid, uuid, timestamptz)
  from public, anon, authenticated;

create function public.has_any_verified_guardian_at(
  p_minor_person_id uuid,
  p_reference_time timestamptz
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1
      from public.guardian_relationships as relationship
     where relationship.minor_person_id = p_minor_person_id
       and relationship.verification_status = 'VERIFIED'
       and relationship.revoked_at is null
       and (
         relationship.verified_at is null
         or relationship.verified_at <= p_reference_time
       )
       and (
         relationship.expires_at is null
         or relationship.expires_at > p_reference_time
       )
  );
$$;

comment on function public.has_any_verified_guardian_at(uuid, timestamptz) is
  'True when the minor has at least one VERIFIED guardian relationship effective at the activity reference time. Not executable by PUBLIC, anon or authenticated.';

revoke all on function public.has_any_verified_guardian_at(uuid, timestamptz)
  from public, anon, authenticated;

create function public.has_equestrian_activity_consent_at(
  p_minor_person_id uuid,
  p_reference_time timestamptz
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1
      from public.guardian_consents as consent
      join public.guardian_relationships as relationship
        on relationship.id = consent.guardian_relationship_id
     where consent.minor_person_id = p_minor_person_id
       and consent.consent_type = 'EQUESTRIAN_ACTIVITY'
       and consent.scope_type = 'GENERAL'
       and consent.status = 'ACTIVE'
       and consent.revoked_at is null
       and consent.granted_at <= p_reference_time
       and (
         consent.expires_at is null
         or consent.expires_at > p_reference_time
       )
       and relationship.verification_status = 'VERIFIED'
       and relationship.revoked_at is null
       and (
         relationship.verified_at is null
         or relationship.verified_at <= p_reference_time
       )
       and (
         relationship.expires_at is null
         or relationship.expires_at > p_reference_time
       )
       and relationship.guardian_person_id = consent.guardian_person_id
       and relationship.minor_person_id = consent.minor_person_id
  );
$$;

comment on function public.has_equestrian_activity_consent_at(uuid, timestamptz) is
  '007 EQUESTRIAN_ACTIVITY / GENERAL consent granted by a VERIFIED guardian, evaluated at the activity reference time. Does not invent scopes. Not executable by PUBLIC, anon or authenticated.';

revoke all on function public.has_equestrian_activity_consent_at(uuid, timestamptz)
  from public, anon, authenticated;

create function public.has_person_accepted_required_policy(
  p_person_id uuid,
  p_policy_type text,
  p_market_code text,
  p_reference_time timestamptz
)
returns boolean
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  missing_code text;
begin
  if p_person_id is null
     or p_policy_type is null
     or p_market_code is null
     or p_reference_time is null then
    return false;
  end if;

  if not exists (
    select 1
      from public.policy_documents as document
     where document.policy_type = p_policy_type
       and document.market_code = p_market_code
       and public.policy_document_is_effective_at(
         document.effective_from,
         document.effective_to,
         document.status,
         p_reference_time
       )
  ) then
    return true;
  end if;

  if public.has_ambiguous_current_policy_versions(
    p_policy_type,
    p_market_code,
    p_reference_time
  ) then
    return false;
  end if;

  -- One current policy_code may have several locales. Locales are
  -- translations, not conflicting policies. Simultaneous current versions
  -- of the same policy_code already failed closed above. Every current
  -- code of this type must have at least one accepted currently-effective
  -- document. Obsolete documents never satisfy.
  select document.policy_code
    into missing_code
    from public.policy_documents as document
   where document.policy_type = p_policy_type
     and document.market_code = p_market_code
     and public.policy_document_is_effective_at(
       document.effective_from,
       document.effective_to,
       document.status,
       p_reference_time
     )
   group by document.policy_code
   having not exists (
     select 1
       from public.policy_documents as current_document
       join public.policy_acceptances as acceptance
         on acceptance.policy_document_id = current_document.id
      where current_document.policy_type = p_policy_type
        and current_document.market_code = p_market_code
        and current_document.policy_code = document.policy_code
        and public.policy_document_is_effective_at(
          current_document.effective_from,
          current_document.effective_to,
          current_document.status,
          p_reference_time
        )
        and acceptance.person_id = p_person_id
        and acceptance.accepted_at <= p_reference_time
   )
   order by document.policy_code
   limit 1;

  return missing_code is null;
end;
$$;

comment on function public.has_person_accepted_required_policy(uuid, text, text, timestamptz) is
  'Server-internal policy acceptance for a named PERSON at a reference time. Multiple current locales of the same policy_code+version are translations and do not fail closed. Simultaneous current versions of one policy_code fail closed. Each current policy_code of the type must be accepted on a currently effective document. Obsolete documents do not satisfy. Not executable by PUBLIC, anon or authenticated.';

revoke all on function public.has_person_accepted_required_policy(uuid, text, text, timestamptz)
  from public, anon, authenticated;

create function public.has_person_accepted_required_policy(
  p_person_id uuid,
  p_policy_type text,
  p_market_code text
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select public.has_person_accepted_required_policy(
    p_person_id,
    p_policy_type,
    p_market_code,
    now()
  );
$$;

comment on function public.has_person_accepted_required_policy(uuid, text, text) is
  'now() wrapper around the activity-time policy acceptance check. Not executable by PUBLIC, anon or authenticated.';

revoke all on function public.has_person_accepted_required_policy(uuid, text, text)
  from public, anon, authenticated;

create function public.has_participant_accepted_required_policy(
  p_participant_person_id uuid,
  p_policy_type text,
  p_market_code text,
  p_reference_time timestamptz,
  p_require_guardian_acceptor boolean
)
returns boolean
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  missing_code text;
begin
  if p_participant_person_id is null
     or p_policy_type is null
     or p_market_code is null
     or p_reference_time is null then
    return false;
  end if;

  if not exists (
    select 1
      from public.policy_documents as document
     where document.policy_type = p_policy_type
       and document.market_code = p_market_code
       and public.policy_document_is_effective_at(
         document.effective_from,
         document.effective_to,
         document.status,
         p_reference_time
       )
  ) then
    return true;
  end if;

  if public.has_ambiguous_current_policy_versions(
    p_policy_type,
    p_market_code,
    p_reference_time
  ) then
    return false;
  end if;

  if not p_require_guardian_acceptor then
    return public.has_person_accepted_required_policy(
      p_participant_person_id,
      p_policy_type,
      p_market_code,
      p_reference_time
    );
  end if;

  select document.policy_code
    into missing_code
    from public.policy_documents as document
   where document.policy_type = p_policy_type
     and document.market_code = p_market_code
     and public.policy_document_is_effective_at(
       document.effective_from,
       document.effective_to,
       document.status,
       p_reference_time
     )
   group by document.policy_code
   having not exists (
     select 1
       from public.policy_documents as current_document
       join public.policy_acceptances as acceptance
         on acceptance.policy_document_id = current_document.id
       join public.user_accounts as acceptor
         on acceptor.id = acceptance.user_account_id
      where current_document.policy_type = p_policy_type
        and current_document.market_code = p_market_code
        and current_document.policy_code = document.policy_code
        and public.policy_document_is_effective_at(
          current_document.effective_from,
          current_document.effective_to,
          current_document.status,
          p_reference_time
        )
        and acceptance.person_id = p_participant_person_id
        and acceptance.accepted_at <= p_reference_time
        and public.has_verified_guardian_relationship_at(
          acceptor.person_id,
          p_participant_person_id,
          p_reference_time
        )
   )
   order by document.policy_code
   limit 1;

  return missing_code is null;
end;
$$;

comment on function public.has_participant_accepted_required_policy(uuid, text, text, timestamptz, boolean) is
  'Policy acceptance for the participant PERSON. Guardian-own and staff-own acceptances never substitute. For a minor, the accepting ACCOUNT must belong to a VERIFIED guardian effective at the activity time. Not executable by PUBLIC, anon or authenticated.';

revoke all on function public.has_participant_accepted_required_policy(uuid, text, text, timestamptz, boolean)
  from public, anon, authenticated;

create function public.snapshot_required_policy_acceptances(
  p_participant_person_id uuid,
  p_market_code text,
  p_reference_time timestamptz,
  p_require_guardian_acceptor boolean
)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select jsonb_build_object(
    'documents',
    coalesce(
      (
        select jsonb_agg(accepted.document order by
          accepted.document ->> 'policy_type',
          accepted.document ->> 'policy_code',
          accepted.document ->> 'locale',
          accepted.document ->> 'version',
          accepted.document ->> 'document_id',
          accepted.document ->> 'acceptance_id'
        )
          from (
            select jsonb_build_object(
              'document_id', document.id,
              'policy_code', document.policy_code,
              'policy_type', document.policy_type,
              'locale', document.locale,
              'version', document.version,
              'acceptance_id', acceptance.id
            ) as document
              from public.policy_documents as document
              join public.policy_acceptances as acceptance
                on acceptance.policy_document_id = document.id
              join public.user_accounts as acceptor
                on acceptor.id = acceptance.user_account_id
             where document.market_code = p_market_code
               and document.policy_type in (
                 'TERMS_OF_SERVICE',
                 'PRIVACY_POLICY',
                 'RIDER_POLICY',
                 'ACTIVITY_POLICY'
               )
               and public.policy_document_is_effective_at(
                 document.effective_from,
                 document.effective_to,
                 document.status,
                 p_reference_time
               )
               and acceptance.person_id = p_participant_person_id
               and acceptance.accepted_at <= p_reference_time
               and (
                 not p_require_guardian_acceptor
                 or public.has_verified_guardian_relationship_at(
                   acceptor.person_id,
                   p_participant_person_id,
                   p_reference_time
                 )
               )
          ) as accepted
      ),
      '[]'::jsonb
    )
  );
$$;

comment on function public.snapshot_required_policy_acceptances(uuid, text, timestamptz, boolean) is
  'Deterministic JSON object of the exact current documents/acceptances used for the participant. Includes document id, policy code/type, locale, version and acceptance id. Not executable by PUBLIC, anon or authenticated.';

revoke all on function public.snapshot_required_policy_acceptances(uuid, text, timestamptz, boolean)
  from public, anon, authenticated;

create function public.rider_satisfies_min_qualification(
  p_rider_person_id uuid,
  p_required_level_id uuid,
  p_discipline_id uuid,
  p_reference_time timestamptz
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1
      from public.rider_qualifications as held
      join public.qualification_levels as held_level
        on held_level.id = held.qualification_level_id
      join public.qualification_levels as required_level
        on required_level.id = p_required_level_id
     where held.rider_person_id = p_rider_person_id
       and held.verification_status = 'VERIFIED'
       and (
         held.expires_at is null
         or held.expires_at > p_reference_time
       )
       and held_level.qualification_system_id = required_level.qualification_system_id
       and held_level.level_order >= required_level.level_order
       and (
         p_discipline_id is null
         or held_level.discipline_id is not distinct from p_discipline_id
       )
  );
$$;

comment on function public.rider_satisfies_min_qualification(uuid, uuid, uuid, timestamptz) is
  'Current VERIFIED rider qualification in the required system, respecting level_order inside that system only, expiry and optional discipline scope. No international equivalences. Not executable by PUBLIC, anon or authenticated.';

revoke all on function public.rider_satisfies_min_qualification(uuid, uuid, uuid, timestamptz)
  from public, anon, authenticated;

create function public.rider_satisfies_min_experience(
  p_rider_person_id uuid,
  p_required_years numeric,
  p_reference_time timestamptz
)
returns boolean
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  start_year smallint;
  activity_year integer;
begin
  if p_rider_person_id is null
     or p_required_years is null
     or p_reference_time is null then
    return false;
  end if;

  select profile.experience_start_year
    into start_year
    from public.rider_profiles as profile
   where profile.person_id = p_rider_person_id;

  if start_year is null then
    return false;
  end if;

  activity_year := extract(year from (timezone('utc', p_reference_time))::date);
  return (activity_year - start_year) >= p_required_years;
end;
$$;

comment on function public.rider_satisfies_min_experience(uuid, numeric, timestamptz) is
  'Evaluates rider_profiles.experience_start_year at the activity date against the stored numeric MIN_EXPERIENCE requirement. Does not store a derived age or experience column. Not executable by PUBLIC, anon or authenticated.';

revoke all on function public.rider_satisfies_min_experience(uuid, numeric, timestamptz)
  from public, anon, authenticated;

create function public.has_current_valid_rider_assessment(
  p_rider_person_id uuid,
  p_center_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1
      from public.rider_assessments as assessment
     where assessment.rider_person_id = p_rider_person_id
       and assessment.center_id = p_center_id
       and assessment.status = 'VALID'
       and (
         assessment.valid_until is null
         or assessment.valid_until > now()
       )
  );
$$;

comment on function public.has_current_valid_rider_assessment(uuid, uuid) is
  'Server-internal current VALID rider assessment at that Center. Stored EXPIRED is not clock-computed; a VALID row whose valid_until is in the past is not currently effective. Not executable by PUBLIC, anon or authenticated.';

revoke all on function public.has_current_valid_rider_assessment(uuid, uuid)
  from public, anon, authenticated;

create function public.has_current_equestrian_activity_consent(
  p_minor_person_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select public.has_equestrian_activity_consent_at(
    p_minor_person_id,
    now()
  );
$$;

comment on function public.has_current_equestrian_activity_consent(uuid) is
  'now() wrapper around has_equestrian_activity_consent_at. Booking eligibility uses the activity-time successor. Not executable by PUBLIC, anon or authenticated.';

revoke all on function public.has_current_equestrian_activity_consent(uuid)
  from public, anon, authenticated;

create function public.has_active_equine_boolean_requirement(
  p_equine_id uuid,
  p_requirement_type text
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1
      from public.equine_requirements as requirement
     where requirement.equine_id = p_equine_id
       and requirement.requirement_type = p_requirement_type
       and requirement.status = 'ACTIVE'
       and requirement.boolean_value is true
  );
$$;

comment on function public.has_active_equine_boolean_requirement(uuid, text) is
  'Server-internal ACTIVE equine boolean requirement that is currently in force. Not executable by PUBLIC, anon or authenticated.';

revoke all on function public.has_active_equine_boolean_requirement(uuid, text)
  from public, anon, authenticated;

create function public.worse_booking_eligibility_token(
  p_left text,
  p_right text
)
returns text
language sql
immutable
set search_path = pg_catalog, public
as $$
  select case
    when p_left = 'NOT_ELIGIBLE' or p_right = 'NOT_ELIGIBLE' then
      'NOT_ELIGIBLE'
    when p_left = 'QUALIFICATION_NOT_VERIFIED'
         or p_right = 'QUALIFICATION_NOT_VERIFIED' then
      'QUALIFICATION_NOT_VERIFIED'
    when p_left = 'REQUIRES_GUARDIAN_CONSENT'
         or p_right = 'REQUIRES_GUARDIAN_CONSENT' then
      'REQUIRES_GUARDIAN_CONSENT'
    when p_left = 'REQUIRES_OWNER_APPROVAL'
         or p_right = 'REQUIRES_OWNER_APPROVAL' then
      'REQUIRES_OWNER_APPROVAL'
    when p_left = 'REQUIRES_ZERO_SESSION'
         or p_right = 'REQUIRES_ZERO_SESSION' then
      'REQUIRES_ZERO_SESSION'
    when p_left = 'REQUIRES_CENTER_ASSESSMENT'
         or p_right = 'REQUIRES_CENTER_ASSESSMENT' then
      'REQUIRES_CENTER_ASSESSMENT'
    when p_left = 'ELIGIBLE_WITH_SUPERVISION'
         or p_right = 'ELIGIBLE_WITH_SUPERVISION' then
      'ELIGIBLE_WITH_SUPERVISION'
    else
      'ELIGIBLE'
  end;
$$;

comment on function public.worse_booking_eligibility_token(text, text) is
  'Picks the more blocking frozen eligibility token. Not executable by PUBLIC, anon or authenticated.';

revoke all on function public.worse_booking_eligibility_token(text, text)
  from public, anon, authenticated;

create function public.caller_has_booking_manage_authority(
  p_person_id uuid,
  p_equine_id uuid,
  p_center_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select
    p_person_id is not null
    and public.has_active_equine_center_permission(
      p_equine_id,
      p_center_id,
      'MANAGE_BOOKINGS'
    )
    and (
      public.has_active_center_role(p_person_id, p_center_id, 'ADMIN')
      or public.has_active_center_role(p_person_id, p_center_id, 'MANAGER')
    );
$$;

comment on function public.caller_has_booking_manage_authority(uuid, uuid, uuid) is
  'Server-internal confirm/inspect staff path. Effective MANAGE_BOOKINGS is a Center-over-equine capability; the caller must also be an active ADMIN or MANAGER at that Center. INSTRUCTOR, ASSESSOR, membership alone and booker-alone are not enough. Not executable by PUBLIC, anon or authenticated.';

revoke all on function public.caller_has_booking_manage_authority(uuid, uuid, uuid)
  from public, anon, authenticated;

create function public.booking_caller_can_inspect_eligibility(
  p_participant_person_id uuid,
  p_equine_id uuid,
  p_center_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  current_auth_user_id uuid := auth.uid();
  caller_person uuid;
begin
  if current_auth_user_id is null then
    return false;
  end if;

  select account.person_id
    into caller_person
    from public.user_accounts as account
   where account.auth_user_id = current_auth_user_id;

  if caller_person is null then
    return false;
  end if;

  if caller_person = p_participant_person_id then
    return true;
  end if;

  if public.has_current_verified_guardian_relationship(
    caller_person,
    p_participant_person_id
  ) then
    return true;
  end if;

  return public.caller_has_booking_manage_authority(
    caller_person,
    p_equine_id,
    p_center_id
  );
end;
$$;

comment on function public.booking_caller_can_inspect_eligibility(uuid, uuid, uuid) is
  'True when auth.uid() is the participant, a current VERIFIED guardian, or a Center ADMIN/MANAGER with effective MANAGE_BOOKINGS for that equine+Center. Not executable by PUBLIC, anon or authenticated.';

revoke all on function public.booking_caller_can_inspect_eligibility(uuid, uuid, uuid)
  from public, anon, authenticated;

create function public.collect_booking_eligibility(
  p_participant_person_id uuid,
  p_equine_id uuid,
  p_center_id uuid,
  p_starts_at timestamptz,
  p_ends_at timestamptz,
  p_service_id uuid,
  p_policy_person_id uuid
)
returns table (
  overall_status text,
  requirement_type text,
  source_type text,
  source_id uuid,
  is_met boolean,
  detail text
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
#variable_conflict use_variable
declare
  overall text := 'ELIGIBLE';
  center_market_code text;
  birth_date date;
  minority_row record;
  service_center uuid;
  service_status text;
  service_link public.service_equines%rowtype;
  requested_minutes numeric;
  required_policy_type text;
  requirement_row public.equine_requirements%rowtype;
  age_years integer;
  guardian_required boolean := false;
  policy_ok boolean;
  qualification_ok boolean;
  experience_ok boolean;
begin
  -- p_policy_person_id is retained for signature stability. Policy
  -- acceptance subject is always the participant PERSON.
  if p_policy_person_id is null then
    null;
  end if;

  if p_participant_person_id is null
     or p_equine_id is null
     or p_center_id is null
     or p_starts_at is null
     or p_ends_at is null then
    raise exception using
      errcode = '22023',
      message = 'Participant, equine, Center and time range are required';
  end if;

  if p_ends_at <= p_starts_at then
    raise exception using
      errcode = '22023',
      message = 'Booking ends_at must be after starts_at';
  end if;

  select center.country_code
    into center_market_code
    from public.equestrian_centers as center
   where center.id = p_center_id;

  if center_market_code is null then
    raise exception using
      errcode = 'P0002',
      message = 'Center not found';
  end if;

  if p_service_id is not null then
    select service.center_id, service.status
      into service_center, service_status
      from public.center_services as service
     where service.id = p_service_id;

    if service_center is null then
      overall := public.worse_booking_eligibility_token(overall, 'NOT_ELIGIBLE');
      overall_status := overall;
      requirement_type := null;
      source_type := 'SERVICE';
      source_id := p_service_id;
      is_met := false;
      detail := 'Service does not exist';
      return next;
    elsif service_center is distinct from p_center_id then
      overall := public.worse_booking_eligibility_token(overall, 'NOT_ELIGIBLE');
      overall_status := overall;
      requirement_type := null;
      source_type := 'SERVICE';
      source_id := p_service_id;
      is_met := false;
      detail := 'Service does not belong to the booking Center';
      return next;
    elsif service_status is distinct from 'ACTIVE' then
      overall := public.worse_booking_eligibility_token(overall, 'NOT_ELIGIBLE');
      overall_status := overall;
      requirement_type := null;
      source_type := 'SERVICE';
      source_id := p_service_id;
      is_met := false;
      detail := 'Service is not ACTIVE';
      return next;
    else
      select *
        into service_link
        from public.service_equines as link
       where link.service_id = p_service_id
         and link.equine_id = p_equine_id;

      if service_link.id is null then
        overall := public.worse_booking_eligibility_token(overall, 'NOT_ELIGIBLE');
        overall_status := overall;
        requirement_type := null;
        source_type := 'SERVICE';
        source_id := p_service_id;
        is_met := false;
        detail := 'No matching service_equines link';
        return next;
      elsif service_link.status is distinct from 'ACTIVE'
            or service_link.enabled is not true then
        overall := public.worse_booking_eligibility_token(overall, 'NOT_ELIGIBLE');
        overall_status := overall;
        requirement_type := null;
        source_type := 'SERVICE';
        source_id := service_link.id;
        is_met := false;
        detail := 'Service-equine link is not ACTIVE and enabled';
        return next;
      else
        if service_link.duration_limit_minutes is not null then
          requested_minutes :=
            extract(epoch from (p_ends_at - p_starts_at)) / 60.0;
          if requested_minutes > service_link.duration_limit_minutes then
            overall := public.worse_booking_eligibility_token(
              overall,
              'NOT_ELIGIBLE'
            );
            overall_status := overall;
            requirement_type := null;
            source_type := 'SERVICE';
            source_id := service_link.id;
            is_met := false;
            detail := 'Requested interval exceeds duration_limit_minutes';
            return next;
          end if;
        end if;

        if service_link.supervision_required then
          overall := public.worse_booking_eligibility_token(
            overall,
            'ELIGIBLE_WITH_SUPERVISION'
          );
          overall_status := overall;
          requirement_type := 'SUPERVISION_REQUIRED';
          source_type := 'SERVICE';
          source_id := service_link.id;
          is_met := true;
          detail := 'Service-equine link requires supervision';
          return next;
        end if;
      end if;
    end if;
  end if;

  if not public.has_effective_equine_availability(
    p_equine_id,
    p_center_id,
    p_starts_at,
    p_ends_at
  ) then
    overall := public.worse_booking_eligibility_token(overall, 'NOT_ELIGIBLE');
    overall_status := overall;
    requirement_type := null;
    source_type := 'CENTER';
    source_id := p_center_id;
    is_met := false;
    detail := 'No ACTIVE availability rule covers the requested range';
    return next;
  end if;

  if public.has_active_equine_calendar_overlap(
    p_equine_id,
    p_starts_at,
    p_ends_at
  ) then
    overall := public.worse_booking_eligibility_token(overall, 'NOT_ELIGIBLE');
    overall_status := overall;
    requirement_type := null;
    source_type := 'EQUINE';
    source_id := p_equine_id;
    is_met := false;
    detail := 'An ACTIVE calendar block already occupies this equine';
    return next;
  end if;

  select person.date_of_birth
    into birth_date
    from public.persons as person
   where person.id = p_participant_person_id;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'Participant person not found';
  end if;

  if birth_date is null then
    overall := public.worse_booking_eligibility_token(
      overall,
      'QUALIFICATION_NOT_VERIFIED'
    );
    overall_status := overall;
    requirement_type := null;
    source_type := 'MARKET';
    source_id := p_participant_person_id;
    is_met := false;
    detail := 'date_of_birth is required to evaluate minority';
    return next;
  else
    begin
      select *
        into minority_row
        from public.evaluate_person_minority(
          p_participant_person_id,
          center_market_code,
          (timezone('utc', p_starts_at))::date
        );

      age_years := minority_row.age_years;
      guardian_required := minority_row.guardian_consent_required;

      if guardian_required then
        if not public.has_any_verified_guardian_at(
          p_participant_person_id,
          p_starts_at
        ) then
          overall := public.worse_booking_eligibility_token(
            overall,
            'REQUIRES_GUARDIAN_CONSENT'
          );
          overall_status := overall;
          requirement_type := 'GUARDIAN_CONSENT';
          source_type := 'GUARDIAN';
          source_id := p_participant_person_id;
          is_met := false;
          detail := 'No VERIFIED guardian relationship at activity time';
          return next;
        elsif not public.has_equestrian_activity_consent_at(
          p_participant_person_id,
          p_starts_at
        ) then
          overall := public.worse_booking_eligibility_token(
            overall,
            'REQUIRES_GUARDIAN_CONSENT'
          );
          overall_status := overall;
          requirement_type := 'GUARDIAN_CONSENT';
          source_type := 'GUARDIAN';
          source_id := p_participant_person_id;
          is_met := false;
          detail := 'No EQUESTRIAN_ACTIVITY consent valid at activity time';
          return next;
        else
          overall_status := overall;
          requirement_type := 'GUARDIAN_CONSENT';
          source_type := 'GUARDIAN';
          source_id := p_participant_person_id;
          is_met := true;
          detail := 'EQUESTRIAN_ACTIVITY consent is valid at activity time';
          return next;
        end if;
      end if;
    exception
      when others then
        if sqlstate in ('P0001', 'P0002', '22023') then
          overall := public.worse_booking_eligibility_token(
            overall,
            'QUALIFICATION_NOT_VERIFIED'
          );
          overall_status := overall;
          requirement_type := null;
          source_type := 'MARKET';
          source_id := p_participant_person_id;
          is_met := false;
          detail := 'Minority could not be evaluated';
          return next;
        else
          raise;
        end if;
    end;
  end if;

  foreach required_policy_type in array array[
    'TERMS_OF_SERVICE',
    'PRIVACY_POLICY',
    'RIDER_POLICY',
    'ACTIVITY_POLICY'
  ]
  loop
    if exists (
      select 1
        from public.policy_documents as document
       where document.policy_type = required_policy_type
         and document.market_code = center_market_code
         and public.policy_document_is_effective_at(
           document.effective_from,
           document.effective_to,
           document.status,
           p_starts_at
         )
    ) then
      if public.has_ambiguous_current_policy_versions(
        required_policy_type,
        center_market_code,
        p_starts_at
      ) then
        overall := public.worse_booking_eligibility_token(
          overall,
          'NOT_ELIGIBLE'
        );
        overall_status := overall;
        requirement_type := 'POLICY_ACCEPTANCE';
        source_type := 'POLICY';
        source_id := null;
        is_met := false;
        detail := format(
          'Ambiguous current versions for %s; locales of one version are not a conflict',
          required_policy_type
        );
        return next;
      else
      policy_ok := public.has_participant_accepted_required_policy(
        p_participant_person_id,
        required_policy_type,
        center_market_code,
        p_starts_at,
        guardian_required
      );
      if not policy_ok then
        overall := public.worse_booking_eligibility_token(
          overall,
          'NOT_ELIGIBLE'
        );
        overall_status := overall;
        requirement_type := 'POLICY_ACCEPTANCE';
        source_type := 'POLICY';
        source_id := null;
        is_met := false;
        detail := format(
          'Required %s is not accepted for the participant',
          required_policy_type
        );
        return next;
      else
        overall_status := overall;
        requirement_type := 'POLICY_ACCEPTANCE';
        source_type := 'POLICY';
        source_id := null;
        is_met := true;
        detail := format(
          'Required %s is accepted for the participant',
          required_policy_type
        );
        return next;
      end if;
      end if;
    end if;
  end loop;

  for requirement_row in
    select *
      from public.equine_requirements as requirement
     where requirement.equine_id = p_equine_id
       and requirement.status = 'ACTIVE'
       and requirement.boolean_value is true
       and requirement.requirement_type in (
         'CENTER_ASSESSMENT_REQUIRED',
         'ZERO_SESSION_REQUIRED',
         'OWNER_APPROVAL_REQUIRED',
         'SUPERVISION_REQUIRED'
       )
     order by requirement.requirement_type, requirement.id
  loop
    if requirement_row.requirement_type = 'CENTER_ASSESSMENT_REQUIRED' then
      if public.has_current_valid_rider_assessment(
        p_participant_person_id,
        p_center_id
      ) then
        overall_status := overall;
        requirement_type := 'CENTER_ASSESSMENT_REQUIRED';
        source_type := requirement_row.source_type;
        source_id := requirement_row.id;
        is_met := true;
        detail := 'Current VALID assessment at this Center';
        return next;
      else
        overall := public.worse_booking_eligibility_token(
          overall,
          'REQUIRES_CENTER_ASSESSMENT'
        );
        overall_status := overall;
        requirement_type := 'CENTER_ASSESSMENT_REQUIRED';
        source_type := requirement_row.source_type;
        source_id := requirement_row.id;
        is_met := false;
        detail := 'No current VALID assessment at this Center';
        return next;
      end if;
    elsif requirement_row.requirement_type = 'ZERO_SESSION_REQUIRED' then
      if public.has_effective_rider_equine_authorization(
        p_participant_person_id,
        p_equine_id,
        'ZERO_SESSION'
      ) then
        overall_status := overall;
        requirement_type := 'ZERO_SESSION_REQUIRED';
        source_type := requirement_row.source_type;
        source_id := requirement_row.id;
        is_met := true;
        detail := 'Currently effective ZERO_SESSION authorization';
        return next;
      else
        overall := public.worse_booking_eligibility_token(
          overall,
          'REQUIRES_ZERO_SESSION'
        );
        overall_status := overall;
        requirement_type := 'ZERO_SESSION_REQUIRED';
        source_type := requirement_row.source_type;
        source_id := requirement_row.id;
        is_met := false;
        detail := 'Currently effective ZERO_SESSION authorization is required';
        return next;
      end if;
    elsif requirement_row.requirement_type = 'OWNER_APPROVAL_REQUIRED' then
      if public.has_effective_rider_equine_authorization(
        p_participant_person_id,
        p_equine_id,
        'OWNER_APPROVAL'
      ) then
        overall_status := overall;
        requirement_type := 'OWNER_APPROVAL_REQUIRED';
        source_type := requirement_row.source_type;
        source_id := requirement_row.id;
        is_met := true;
        detail := 'Currently effective OWNER_APPROVAL authorization';
        return next;
      else
        overall := public.worse_booking_eligibility_token(
          overall,
          'REQUIRES_OWNER_APPROVAL'
        );
        overall_status := overall;
        requirement_type := 'OWNER_APPROVAL_REQUIRED';
        source_type := requirement_row.source_type;
        source_id := requirement_row.id;
        is_met := false;
        detail := 'Currently effective OWNER_APPROVAL authorization is required';
        return next;
      end if;
    elsif requirement_row.requirement_type = 'SUPERVISION_REQUIRED' then
      overall := public.worse_booking_eligibility_token(
        overall,
        'ELIGIBLE_WITH_SUPERVISION'
      );
      overall_status := overall;
      requirement_type := 'SUPERVISION_REQUIRED';
      source_type := requirement_row.source_type;
      source_id := requirement_row.id;
      is_met := true;
      detail := 'Equine SUPERVISION_REQUIRED is in force';
      return next;
    end if;
  end loop;

  for requirement_row in
    select *
      from public.equine_requirements as requirement
     where requirement.equine_id = p_equine_id
       and requirement.status = 'ACTIVE'
       and requirement.requirement_type in (
         'MIN_QUALIFICATION',
         'MIN_EXPERIENCE'
       )
     order by requirement.requirement_type, requirement.id
  loop
    if requirement_row.requirement_type = 'MIN_QUALIFICATION' then
      qualification_ok := public.rider_satisfies_min_qualification(
        p_participant_person_id,
        requirement_row.qualification_level_id,
        requirement_row.discipline_id,
        p_starts_at
      );
      if qualification_ok then
        overall_status := overall;
        requirement_type := 'MIN_QUALIFICATION';
        source_type := requirement_row.source_type;
        source_id := requirement_row.id;
        is_met := true;
        detail := 'VERIFIED qualification meets the required system/level';
        return next;
      else
        overall := public.worse_booking_eligibility_token(
          overall,
          'QUALIFICATION_NOT_VERIFIED'
        );
        overall_status := overall;
        requirement_type := 'MIN_QUALIFICATION';
        source_type := requirement_row.source_type;
        source_id := requirement_row.id;
        is_met := false;
        detail := 'MIN_QUALIFICATION is not met by a current VERIFIED qualification in the required system';
        return next;
      end if;
    else
      experience_ok := public.rider_satisfies_min_experience(
        p_participant_person_id,
        requirement_row.numeric_value,
        p_starts_at
      );
      if experience_ok then
        overall_status := overall;
        requirement_type := 'MIN_EXPERIENCE';
        source_type := requirement_row.source_type;
        source_id := requirement_row.id;
        is_met := true;
        detail := 'experience_start_year meets MIN_EXPERIENCE at activity date';
        return next;
      else
        overall := public.worse_booking_eligibility_token(
          overall,
          'QUALIFICATION_NOT_VERIFIED'
        );
        overall_status := overall;
        requirement_type := 'MIN_EXPERIENCE';
        source_type := requirement_row.source_type;
        source_id := requirement_row.id;
        is_met := false;
        detail := 'MIN_EXPERIENCE is not met from rider_profiles.experience_start_year';
        return next;
      end if;
    end if;
  end loop;

  if age_years is not null then
    for requirement_row in
      select *
        from public.equine_requirements as requirement
       where requirement.equine_id = p_equine_id
         and requirement.status = 'ACTIVE'
         and requirement.requirement_type in ('MIN_AGE', 'MAX_AGE')
       order by requirement.requirement_type, requirement.id
    loop
      if requirement_row.requirement_type = 'MIN_AGE'
         and age_years < requirement_row.numeric_value then
        overall := public.worse_booking_eligibility_token(overall, 'NOT_ELIGIBLE');
        overall_status := overall;
        requirement_type := 'MIN_AGE';
        source_type := requirement_row.source_type;
        source_id := requirement_row.id;
        is_met := false;
        detail := 'Participant is younger than MIN_AGE';
        return next;
      elsif requirement_row.requirement_type = 'MAX_AGE'
            and age_years > requirement_row.numeric_value then
        overall := public.worse_booking_eligibility_token(overall, 'NOT_ELIGIBLE');
        overall_status := overall;
        requirement_type := 'MAX_AGE';
        source_type := requirement_row.source_type;
        source_id := requirement_row.id;
        is_met := false;
        detail := 'Participant is older than MAX_AGE';
        return next;
      else
        overall_status := overall;
        requirement_type := requirement_row.requirement_type;
        source_type := requirement_row.source_type;
        source_id := requirement_row.id;
        is_met := true;
        detail := format('%s is satisfied', requirement_row.requirement_type);
        return next;
      end if;
    end loop;
  end if;

  overall_status := overall;
  requirement_type := null;
  source_type := null;
  source_id := null;
  is_met := true;
  detail := null;
  return next;
end;
$$;

comment on function public.collect_booking_eligibility(uuid, uuid, uuid, timestamptz, timestamptz, uuid, uuid) is
  'Server-internal eligibility collector. Emits every applicable evaluated requirement, satisfied or unmet, plus a final overall row. Policy acceptance subject is the participant PERSON. Activity-time consent and current policy documents are used. Not executable by PUBLIC, anon or authenticated.';

revoke all on function public.collect_booking_eligibility(uuid, uuid, uuid, timestamptz, timestamptz, uuid, uuid)
  from public, anon, authenticated;

create function public.booking_eligibility_overall(
  p_participant_person_id uuid,
  p_equine_id uuid,
  p_center_id uuid,
  p_starts_at timestamptz,
  p_ends_at timestamptz,
  p_service_id uuid,
  p_policy_person_id uuid
)
returns text
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select eligibility.overall_status
    from public.collect_booking_eligibility(
      p_participant_person_id,
      p_equine_id,
      p_center_id,
      p_starts_at,
      p_ends_at,
      p_service_id,
      p_policy_person_id
    ) as eligibility
   order by case eligibility.overall_status
     when 'NOT_ELIGIBLE' then 7
     when 'QUALIFICATION_NOT_VERIFIED' then 6
     when 'REQUIRES_GUARDIAN_CONSENT' then 5
     when 'REQUIRES_OWNER_APPROVAL' then 4
     when 'REQUIRES_ZERO_SESSION' then 3
     when 'REQUIRES_CENTER_ASSESSMENT' then 2
     when 'ELIGIBLE_WITH_SUPERVISION' then 1
     else 0
   end desc
   limit 1;
$$;

comment on function public.booking_eligibility_overall(uuid, uuid, uuid, timestamptz, timestamptz, uuid, uuid) is
  'Server-internal worst overall eligibility token for one evaluation. Not executable by PUBLIC, anon or authenticated.';

revoke all on function public.booking_eligibility_overall(uuid, uuid, uuid, timestamptz, timestamptz, uuid, uuid)
  from public, anon, authenticated;

create function public.classify_booking_request_status(
  p_overall_status text
)
returns text
language sql
immutable
set search_path = pg_catalog, public
as $$
  select case p_overall_status
    when 'ELIGIBLE' then 'APPROVED'
    when 'ELIGIBLE_WITH_SUPERVISION' then 'APPROVED'
    when 'REQUIRES_CENTER_ASSESSMENT' then 'PENDING_APPROVAL'
    when 'REQUIRES_ZERO_SESSION' then 'PENDING_APPROVAL'
    when 'REQUIRES_OWNER_APPROVAL' then 'PENDING_APPROVAL'
    when 'REQUIRES_GUARDIAN_CONSENT' then 'PENDING_REQUIREMENTS'
    when 'QUALIFICATION_NOT_VERIFIED' then 'PENDING_REQUIREMENTS'
    else 'PENDING_REQUIREMENTS'
  end;
$$;

comment on function public.classify_booking_request_status(text) is
  'Maps a frozen eligibility token onto REQUESTED-family statuses. Never returns CONFIRMED. Not executable by PUBLIC, anon or authenticated.';

revoke all on function public.classify_booking_request_status(text)
  from public, anon, authenticated;

create function public.resolve_eligibility_policy_person(
  p_participant_person_id uuid,
  p_caller_person_id uuid
)
returns uuid
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
begin
  if p_participant_person_id is null then
    raise exception using
      errcode = '22023',
      message = 'Participant person is required';
  end if;

  -- POLICY ACCEPTANCE ≠ GUARDIAN CONSENT. The acceptance subject is
  -- always the participant PERSON. A guardian ACCOUNT may record that
  -- acceptance; guardian-own and staff-own PERSON acceptances never
  -- substitute. p_caller_person_id is the inspector/booker, not the
  -- acceptance subject.
  if p_caller_person_id is null then
    null;
  end if;

  return p_participant_person_id;
end;
$$;

comment on function public.resolve_eligibility_policy_person(uuid, uuid) is
  'Policy acceptance subject is always the participant PERSON. Guardian-own and staff-own acceptances never substitute. Not executable by PUBLIC, anon or authenticated.';

revoke all on function public.resolve_eligibility_policy_person(uuid, uuid)
  from public, anon, authenticated;

create function public.persist_booking_requirement_rows(
  p_booking_id uuid,
  p_participant_person_id uuid,
  p_equine_id uuid,
  p_center_id uuid,
  p_starts_at timestamptz,
  p_ends_at timestamptz,
  p_service_id uuid,
  p_policy_person_id uuid,
  p_resolved_by_account_id uuid
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  eligibility_row record;
  booking_status text;
  market_code text;
  guardian_required boolean := false;
  policy_snapshot jsonb;
begin
  select booking.status
    into booking_status
    from public.bookings as booking
   where booking.id = p_booking_id;

  if booking_status in ('CONFIRMED', 'ACTIVE', 'COMPLETED') then
    raise exception using
      errcode = '42501',
      message = 'Confirmed booking requirements cannot be rewritten';
  end if;

  delete from public.booking_requirements
   where booking_id = p_booking_id;

  select center.country_code
    into market_code
    from public.equestrian_centers as center
   where center.id = p_center_id;

  begin
    select evaluate.guardian_consent_required
      into guardian_required
      from public.evaluate_person_minority(
        p_participant_person_id,
        market_code,
        (timezone('utc', p_starts_at))::date
      ) as evaluate;
  exception
    when others then
      guardian_required := false;
  end;

  policy_snapshot := public.snapshot_required_policy_acceptances(
    p_participant_person_id,
    market_code,
    p_starts_at,
    guardian_required
  );

  for eligibility_row in
    select *
      from public.collect_booking_eligibility(
        p_participant_person_id,
        p_equine_id,
        p_center_id,
        p_starts_at,
        p_ends_at,
        p_service_id,
        p_participant_person_id
      )
     where requirement_type is not null
     order by requirement_type, source_type, source_id
  loop
    insert into public.booking_requirements (
      booking_id,
      requirement_type,
      source_type,
      source_id,
      status,
      resolved_at,
      resolved_by_account_id,
      metadata
    ) values (
      p_booking_id,
      eligibility_row.requirement_type,
      eligibility_row.source_type,
      eligibility_row.source_id,
      case
        when eligibility_row.is_met then 'SATISFIED'
        else 'PENDING'
      end,
      case
        when eligibility_row.is_met then now()
        else null
      end,
      case
        when eligibility_row.is_met then p_resolved_by_account_id
        else null
      end,
      jsonb_strip_nulls(
        jsonb_build_object(
          'detail', eligibility_row.detail,
          'source_id', eligibility_row.source_id,
          'source_type', eligibility_row.source_type,
          'policy_documents',
          case
            when eligibility_row.requirement_type = 'POLICY_ACCEPTANCE'
            then policy_snapshot -> 'documents'
            else null
          end
        )
      )
    );
  end loop;
end;
$$;

comment on function public.persist_booking_requirement_rows(uuid, uuid, uuid, uuid, timestamptz, timestamptz, uuid, uuid, uuid) is
  'Writes every applicable evaluated requirement, SATISFIED or unmet, with source identity and deterministic metadata. Refuses to rewrite CONFIRMED/ACTIVE/COMPLETED bookings. Not executable by PUBLIC, anon or authenticated.';

revoke all on function public.persist_booking_requirement_rows(uuid, uuid, uuid, uuid, timestamptz, timestamptz, uuid, uuid, uuid)
  from public, anon, authenticated;

create function public.persist_booking_requirement_eval_rows(
  p_booking_id uuid,
  p_eval_rows jsonb,
  p_policy_snapshot jsonb,
  p_resolved_by_account_id uuid
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
#variable_conflict use_variable
declare
  booking_status text;
  eligibility_row jsonb;
begin
  if p_booking_id is null or p_eval_rows is null then
    raise exception using
      errcode = '22023',
      message = 'Booking id and eligibility rows are required';
  end if;

  select booking.status
    into booking_status
    from public.bookings as booking
   where booking.id = p_booking_id;

  if booking_status in ('CONFIRMED', 'ACTIVE', 'COMPLETED') then
    raise exception using
      errcode = '42501',
      message = 'Confirmed booking requirements cannot be rewritten';
  end if;

  delete from public.booking_requirements
   where booking_id = p_booking_id;

  for eligibility_row in
    select value
      from jsonb_array_elements(p_eval_rows) as eval(value)
     where eval.value ? 'requirement_type'
       and eval.value ->> 'requirement_type' is not null
     order by
       eval.value ->> 'requirement_type',
       eval.value ->> 'source_type',
       eval.value ->> 'source_id'
  loop
    insert into public.booking_requirements (
      booking_id,
      requirement_type,
      source_type,
      source_id,
      status,
      resolved_at,
      resolved_by_account_id,
      metadata
    ) values (
      p_booking_id,
      eligibility_row ->> 'requirement_type',
      eligibility_row ->> 'source_type',
      nullif(eligibility_row ->> 'source_id', '')::uuid,
      case
        when (eligibility_row ->> 'is_met')::boolean then 'SATISFIED'
        else 'PENDING'
      end,
      case
        when (eligibility_row ->> 'is_met')::boolean then now()
        else null
      end,
      case
        when (eligibility_row ->> 'is_met')::boolean then p_resolved_by_account_id
        else null
      end,
      jsonb_strip_nulls(
        jsonb_build_object(
          'detail', eligibility_row ->> 'detail',
          'source_id', nullif(eligibility_row ->> 'source_id', '')::uuid,
          'source_type', eligibility_row ->> 'source_type',
          'policy_documents',
          case
            when eligibility_row ->> 'requirement_type' = 'POLICY_ACCEPTANCE'
            then coalesce(p_policy_snapshot -> 'documents', '[]'::jsonb)
            else null
          end
        )
      )
    );
  end loop;
end;
$$;

comment on function public.persist_booking_requirement_eval_rows(uuid, jsonb, jsonb, uuid) is
  'Writes booking_requirements from one already-materialized eligibility evaluation. Does not re-run the collector. Not executable by PUBLIC, anon or authenticated.';

revoke all on function public.persist_booking_requirement_eval_rows(uuid, jsonb, jsonb, uuid)
  from public, anon, authenticated;

create function public.materialize_booking_confirm_eval(
  p_participant_person_id uuid,
  p_equine_id uuid,
  p_center_id uuid,
  p_starts_at timestamptz,
  p_ends_at timestamptz,
  p_service_id uuid
)
returns table (
  eval_rows jsonb,
  policy_snapshot jsonb
)
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select
    coalesce(
      (
        select jsonb_agg(
          to_jsonb(eligibility)
          order by
            eligibility.requirement_type nulls last,
            eligibility.source_type,
            eligibility.source_id
        )
          from public.collect_booking_eligibility(
            p_participant_person_id,
            p_equine_id,
            p_center_id,
            p_starts_at,
            p_ends_at,
            p_service_id,
            p_participant_person_id
          ) as eligibility
      ),
      '[]'::jsonb
    ) as eval_rows,
    public.snapshot_required_policy_acceptances(
      p_participant_person_id,
      center.country_code,
      p_starts_at,
      coalesce(minority.guardian_consent_required, false)
    ) as policy_snapshot
    from public.equestrian_centers as center
    left join lateral public.evaluate_person_minority(
      p_participant_person_id,
      center.country_code,
      (timezone('utc', p_starts_at))::date
    ) as minority on true
   where center.id = p_center_id;
$$;

comment on function public.materialize_booking_confirm_eval(uuid, uuid, uuid, timestamptz, timestamptz, uuid) is
  'One SQL statement: eligibility rows and the exact policy snapshot at the same evaluation point. Not executable by PUBLIC, anon or authenticated.';

revoke all on function public.materialize_booking_confirm_eval(uuid, uuid, uuid, timestamptz, timestamptz, uuid)
  from public, anon, authenticated;

create function public.apply_booking_confirm_eval(
  p_booking_id uuid,
  p_eval_rows jsonb,
  p_policy_snapshot jsonb,
  p_caller_account_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
#variable_conflict use_variable
declare
  booking_row public.bookings%rowtype;
  overall text;
  eval_row jsonb;
begin
  if p_booking_id is null or p_eval_rows is null or p_policy_snapshot is null then
    raise exception using
      errcode = '22023',
      message = 'Booking id, eligibility rows and policy snapshot are required';
  end if;

  select *
    into booking_row
    from public.bookings as booking
   where booking.id = p_booking_id;

  if booking_row.id is null then
    raise exception using
      errcode = 'P0002',
      message = 'Booking not found';
  end if;

  overall := 'ELIGIBLE';
  for eval_row in
    select value
      from jsonb_array_elements(p_eval_rows) as eval(value)
  loop
    overall := public.worse_booking_eligibility_token(
      overall,
      eval_row ->> 'overall_status'
    );
  end loop;

  if overall not in ('ELIGIBLE', 'ELIGIBLE_WITH_SUPERVISION')
     or exists (
       select 1
         from jsonb_array_elements(p_eval_rows) as eval(value)
        where (eval.value ->> 'is_met')::boolean is not true
     ) then
    raise exception using
      errcode = '42501',
      message = 'Booking is not currently eligible to confirm';
  end if;

  perform public.persist_booking_requirement_eval_rows(
    booking_row.id,
    p_eval_rows,
    p_policy_snapshot,
    p_caller_account_id
  );

  if exists (
    select 1
      from public.booking_requirements as requirement
     where requirement.booking_id = booking_row.id
       and requirement.status = 'PENDING'
  ) then
    raise exception using
      errcode = '42501',
      message = 'A CONFIRMED booking cannot persist PENDING requirement rows';
  end if;

  begin
    insert into public.equine_calendar_blocks (
      equine_id,
      center_id,
      starts_at,
      ends_at,
      block_type,
      source_type,
      source_id,
      status,
      created_by_account_id
    ) values (
      booking_row.equine_id,
      booking_row.center_id,
      booking_row.starts_at,
      booking_row.ends_at,
      'BOOKING',
      'BOOKING',
      booking_row.id,
      'ACTIVE',
      p_caller_account_id
    );
  exception
    when exclusion_violation then
      raise exception using
        errcode = '23P01',
        message = 'Conflicting ACTIVE calendar occupancy';
  end;

  update public.bookings
     set status = 'CONFIRMED',
         confirmed_at = now(),
         eligibility_status = overall,
         booking_policy_snapshot = p_policy_snapshot,
         updated_at = now()
   where id = booking_row.id;

  return booking_row.id;
end;
$$;

comment on function public.apply_booking_confirm_eval(uuid, jsonb, jsonb, uuid) is
  'Persists and confirms from one already-materialized eligibility evaluation and policy snapshot. Does not re-run the collector or snapshot. Not executable by PUBLIC, anon or authenticated.';

revoke all on function public.apply_booking_confirm_eval(uuid, jsonb, jsonb, uuid)
  from public, anon, authenticated;

create function public.check_booking_eligibility(
  p_participant_person_id uuid,
  p_equine_id uuid,
  p_center_id uuid,
  p_starts_at timestamptz,
  p_ends_at timestamptz,
  p_service_id uuid default null
)
returns table (
  overall_status text,
  requirement_type text,
  source_type text,
  source_id uuid,
  is_met boolean,
  detail text
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  current_auth_user_id uuid := auth.uid();
  caller_account uuid;
  caller_person uuid;
  policy_person uuid;
begin
  if current_auth_user_id is null then
    raise exception using
      errcode = '42501',
      message = 'Authentication required';
  end if;

  select account.id, account.person_id
    into caller_account, caller_person
    from public.user_accounts as account
   where account.auth_user_id = current_auth_user_id;

  if caller_person is null then
    raise exception using
      errcode = 'P0001',
      message = 'Identity could not be resolved';
  end if;

  if not public.booking_caller_can_inspect_eligibility(
    p_participant_person_id,
    p_equine_id,
    p_center_id
  ) then
    raise exception using
      errcode = '42501',
      message = 'Eligibility may be checked by the participant, a current VERIFIED guardian, or effective MANAGE_BOOKINGS';
  end if;

  policy_person := public.resolve_eligibility_policy_person(
    p_participant_person_id,
    caller_person
  );

  return query
    select
      public.booking_eligibility_overall(
        p_participant_person_id,
        p_equine_id,
        p_center_id,
        p_starts_at,
        p_ends_at,
        p_service_id,
        policy_person
      ),
      eligibility.requirement_type,
      eligibility.source_type,
      eligibility.source_id,
      eligibility.is_met,
      eligibility.detail
      from public.collect_booking_eligibility(
        p_participant_person_id,
        p_equine_id,
        p_center_id,
        p_starts_at,
        p_ends_at,
        p_service_id,
        policy_person
      ) as eligibility
     where eligibility.is_met is not true
        or (
          eligibility.requirement_type is null
          and eligibility.is_met
        );
end;
$$;

comment on function public.check_booking_eligibility(uuid, uuid, uuid, timestamptz, timestamptz, uuid) is
  'Authenticated eligibility check. Returns the overall frozen token on every row plus explainable unmet-requirement rows. Staff callers do not use their own policy-acceptance helpers.';

revoke all on function public.check_booking_eligibility(uuid, uuid, uuid, timestamptz, timestamptz, uuid)
  from public, anon, authenticated;
grant execute on function public.check_booking_eligibility(uuid, uuid, uuid, timestamptz, timestamptz, uuid)
  to authenticated;

create function public.create_booking_request(
  p_participant_person_id uuid,
  p_equine_id uuid,
  p_center_id uuid,
  p_service_id uuid,
  p_starts_at timestamptz,
  p_ends_at timestamptz
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  current_auth_user_id uuid := auth.uid();
  caller_account uuid;
  caller_person uuid;
  overall text;
  classified text;
  created_booking_id uuid;
begin
  if current_auth_user_id is null then
    raise exception using
      errcode = '42501',
      message = 'Authentication required';
  end if;

  if p_participant_person_id is null
     or p_equine_id is null
     or p_center_id is null
     or p_service_id is null
     or p_starts_at is null
     or p_ends_at is null then
    raise exception using
      errcode = '22023',
      message = 'Participant, equine, Center, service and time range are required';
  end if;

  select account.id, account.person_id
    into caller_account, caller_person
    from public.user_accounts as account
   where account.auth_user_id = current_auth_user_id;

  if caller_person is null then
    raise exception using
      errcode = 'P0001',
      message = 'Identity could not be resolved';
  end if;

  if caller_person is distinct from p_participant_person_id
     and not public.has_current_verified_guardian_relationship(
       caller_person,
       p_participant_person_id
     ) then
    raise exception using
      errcode = '42501',
      message = 'A booker may request only for their own PERSON or a minor with a current VERIFIED guardian relationship';
  end if;

  overall := public.booking_eligibility_overall(
    p_participant_person_id,
    p_equine_id,
    p_center_id,
    p_starts_at,
    p_ends_at,
    p_service_id,
    public.resolve_eligibility_policy_person(
      p_participant_person_id,
      caller_person
    )
  );
  classified := public.classify_booking_request_status(overall);

  if classified = 'CONFIRMED' then
    raise exception using
      errcode = '42501',
      message = 'create_booking_request cannot confirm a booking';
  end if;

  insert into public.bookings (
    participant_person_id,
    booked_by_account_id,
    equine_id,
    center_id,
    service_id,
    starts_at,
    ends_at,
    status,
    eligibility_status
  ) values (
    p_participant_person_id,
    caller_account,
    p_equine_id,
    p_center_id,
    p_service_id,
    p_starts_at,
    p_ends_at,
    classified,
    overall
  )
  returning id into created_booking_id;

  perform public.persist_booking_requirement_rows(
    created_booking_id,
    p_participant_person_id,
    p_equine_id,
    p_center_id,
    p_starts_at,
    p_ends_at,
    p_service_id,
    public.resolve_eligibility_policy_person(
      p_participant_person_id,
      caller_person
    ),
    caller_account
  );

  return created_booking_id;
end;
$$;

comment on function public.create_booking_request(uuid, uuid, uuid, uuid, timestamptz, timestamptz) is
  'Authenticated booking request. Booker is the caller account. Creates REQUESTED-family rows classified from eligibility. Never sets CONFIRMED.';

revoke all on function public.create_booking_request(uuid, uuid, uuid, uuid, timestamptz, timestamptz)
  from public, anon, authenticated;
grant execute on function public.create_booking_request(uuid, uuid, uuid, uuid, timestamptz, timestamptz)
  to authenticated;

create function public.confirm_booking(
  p_booking_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
#variable_conflict use_variable
declare
  current_auth_user_id uuid := auth.uid();
  caller_account uuid;
  caller_person uuid;
  booking_row public.bookings%rowtype;
  eval_rows jsonb;
  policy_snapshot jsonb;
begin
  if current_auth_user_id is null then
    raise exception using
      errcode = '42501',
      message = 'Authentication required';
  end if;

  if p_booking_id is null then
    raise exception using
      errcode = '22023',
      message = 'Booking id is required';
  end if;

  select account.id, account.person_id
    into caller_account, caller_person
    from public.user_accounts as account
   where account.auth_user_id = current_auth_user_id;

  if caller_person is null then
    raise exception using
      errcode = 'P0001',
      message = 'Identity could not be resolved';
  end if;

  select *
    into booking_row
    from public.bookings as booking
   where booking.id = p_booking_id
   for update;

  if booking_row.id is null then
    raise exception using
      errcode = 'P0002',
      message = 'Booking not found';
  end if;

  if booking_row.status is distinct from 'APPROVED' then
    raise exception using
      errcode = '23514',
      message = 'Only an APPROVED booking can be confirmed';
  end if;

  if caller_person is not distinct from booking_row.participant_person_id
     or caller_account is not distinct from booking_row.booked_by_account_id then
    raise exception using
      errcode = '42501',
      message = 'The rider or booker cannot self-confirm';
  end if;

  if not public.caller_has_booking_manage_authority(
    caller_person,
    booking_row.equine_id,
    booking_row.center_id
  ) then
    raise exception using
      errcode = '42501',
      message = 'Confirming a booking requires a Center ADMIN or MANAGER with effective MANAGE_BOOKINGS for this equine at this Center';
  end if;

  perform set_config('app.confirming_booking', '1', true);

  select
    evaluation.eval_rows,
    evaluation.policy_snapshot
    into eval_rows, policy_snapshot
    from public.materialize_booking_confirm_eval(
      booking_row.participant_person_id,
      booking_row.equine_id,
      booking_row.center_id,
      booking_row.starts_at,
      booking_row.ends_at,
      booking_row.service_id
    ) as evaluation;

  if eval_rows is null or policy_snapshot is null then
    raise exception using
      errcode = 'P0002',
      message = 'Confirm evaluation could not be materialized';
  end if;

  return public.apply_booking_confirm_eval(
    booking_row.id,
    eval_rows,
    policy_snapshot,
    caller_account
  );
end;
$$;

comment on function public.confirm_booking(uuid) is
  'Authenticated confirm. Requires effective MANAGE_BOOKINGS. Accepts only APPROVED. Materializes eligibility rows and the policy snapshot in one SQL statement, then persists and confirms only from that materialization. No caller-controlled pause GUC. The 020 gist exclusion remains the occupancy guard. Confirmed bookings cannot retain PENDING requirement rows. Rolls back on any failure.';

revoke all on function public.confirm_booking(uuid)
  from public, anon, authenticated;
grant execute on function public.confirm_booking(uuid)
  to authenticated;
