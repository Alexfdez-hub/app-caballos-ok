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
--   confirm is atomic: revalidate, occupy with a BOOKING calendar
--   block, snapshot, set CONFIRMED; rollback on any failure;
--   concurrent conflicting confirms cannot both succeed (020 gist).
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
    if old.status = any(critical_states) then
      if new.participant_person_id is distinct from old.participant_person_id
         or new.booked_by_account_id is distinct from old.booked_by_account_id
         or new.equine_id is distinct from old.equine_id
         or new.center_id is distinct from old.center_id
         or new.service_id is distinct from old.service_id
         or new.starts_at is distinct from old.starts_at
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
  'BEFORE INSERT OR UPDATE OR DELETE: booker is own PERSON or current VERIFIED guardian. Service must belong to center_id. CONFIRMED is allowed only from APPROVED when confirm_booking sets app.confirming_booking=1. ACTIVE/COMPLETED still cannot be forced. Confirmed history cannot be rewritten. Not executable by anon or authenticated.';

create function public.has_person_accepted_required_policy(
  p_person_id uuid,
  p_policy_type text,
  p_market_code text
)
returns boolean
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  document_count integer;
  required_document_id uuid;
begin
  if p_person_id is null or p_policy_type is null or p_market_code is null then
    return false;
  end if;

  select count(*)
    into document_count
    from public.policy_documents as document
   where document.policy_type = p_policy_type
     and document.market_code = p_market_code
     and document.status = 'ACTIVE'
     and document.effective_from <= now()
     and (
       document.effective_to is null
       or document.effective_to > now()
     );

  if document_count = 0 then
    return true;
  end if;

  if document_count > 1 then
    return false;
  end if;

  select document.id
    into required_document_id
    from public.policy_documents as document
   where document.policy_type = p_policy_type
     and document.market_code = p_market_code
     and document.status = 'ACTIVE'
     and document.effective_from <= now()
     and (
       document.effective_to is null
       or document.effective_to > now()
     );

  return exists (
    select 1
      from public.policy_acceptances as acceptance
     where acceptance.policy_document_id = required_document_id
       and acceptance.person_id = p_person_id
  );
end;
$$;

comment on function public.has_person_accepted_required_policy(uuid, text, text) is
  'Server-internal policy acceptance for a named PERSON, not auth.uid(). True when no current document of that type exists for the market, or when that person accepted the single current document. Ambiguous current documents fail closed. Not executable by PUBLIC, anon or authenticated.';

revoke all on function public.has_person_accepted_required_policy(uuid, text, text)
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
  select exists (
    select 1
      from public.guardian_consents as consent
      join public.guardian_relationships as relationship
        on relationship.id = consent.guardian_relationship_id
     where consent.minor_person_id = p_minor_person_id
       and consent.consent_type = 'EQUESTRIAN_ACTIVITY'
       and consent.status = 'ACTIVE'
       and consent.revoked_at is null
       and (
         consent.expires_at is null
         or consent.expires_at > now()
       )
       and relationship.verification_status = 'VERIFIED'
       and relationship.revoked_at is null
       and (
         relationship.expires_at is null
         or relationship.expires_at > now()
       )
       and relationship.guardian_person_id = consent.guardian_person_id
       and relationship.minor_person_id = consent.minor_person_id
  );
$$;

comment on function public.has_current_equestrian_activity_consent(uuid) is
  'Server-internal current EQUESTRIAN_ACTIVITY consent granted by a current VERIFIED guardian. Stored EXPIRED is not clock-computed; expires_at in the past is not currently effective. Not executable by PUBLIC, anon or authenticated.';

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

  return public.has_active_equine_center_permission(
    p_equine_id,
    p_center_id,
    'MANAGE_BOOKINGS'
  );
end;
$$;

comment on function public.booking_caller_can_inspect_eligibility(uuid, uuid, uuid) is
  'True when auth.uid() is the participant, a current VERIFIED guardian, or holds effective MANAGE_BOOKINGS for that equine+Center. Not executable by PUBLIC, anon or authenticated.';

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
declare
  overall text := 'ELIGIBLE';
  market_code text;
  birth_date date;
  minority_row record;
  service_center uuid;
  service_status text;
  policy_type text;
  requirement_row public.equine_requirements%rowtype;
  age_years integer;
begin
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
    into market_code
    from public.equestrian_centers as center
   where center.id = p_center_id;

  if market_code is null then
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
          market_code,
          (timezone('utc', p_starts_at))::date
        );

      age_years := minority_row.age_years;

      if minority_row.guardian_consent_required then
        if not public.has_current_verified_guardian_relationship(
             p_policy_person_id,
             p_participant_person_id
           )
           and p_policy_person_id is distinct from p_participant_person_id then
          -- staff/guardian path still requires some current VERIFIED guardian
          null;
        end if;

        if not exists (
          select 1
            from public.guardian_relationships as relationship
           where relationship.minor_person_id = p_participant_person_id
             and relationship.verification_status = 'VERIFIED'
             and relationship.revoked_at is null
             and (
               relationship.expires_at is null
               or relationship.expires_at > now()
             )
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
          detail := 'No current VERIFIED guardian relationship';
          return next;
        elsif not public.has_current_equestrian_activity_consent(
          p_participant_person_id
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
          detail := 'No current EQUESTRIAN_ACTIVITY consent';
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

  foreach policy_type in array array[
    'TERMS_OF_SERVICE',
    'PRIVACY_POLICY',
    'RIDER_POLICY',
    'ACTIVITY_POLICY'
  ]
  loop
    if not public.has_person_accepted_required_policy(
      p_policy_person_id,
      policy_type,
      market_code
    ) then
      overall := public.worse_booking_eligibility_token(overall, 'NOT_ELIGIBLE');
      overall_status := overall;
      requirement_type := 'POLICY_ACCEPTANCE';
      source_type := 'POLICY';
      source_id := null;
      is_met := false;
      detail := format('Required %s is not currently accepted', policy_type);
      return next;
    end if;
  end loop;

  if public.has_active_equine_boolean_requirement(
    p_equine_id,
    'CENTER_ASSESSMENT_REQUIRED'
  ) then
    if not public.has_current_valid_rider_assessment(
      p_participant_person_id,
      p_center_id
    ) then
      overall := public.worse_booking_eligibility_token(
        overall,
        'REQUIRES_CENTER_ASSESSMENT'
      );
      overall_status := overall;
      requirement_type := 'CENTER_ASSESSMENT_REQUIRED';
      source_type := 'EQUINE';
      source_id := p_equine_id;
      is_met := false;
      detail := 'No current VALID assessment at this Center';
      return next;
    end if;
  end if;

  if public.has_active_equine_boolean_requirement(
    p_equine_id,
    'ZERO_SESSION_REQUIRED'
  ) then
    if not public.has_effective_rider_equine_authorization(
      p_participant_person_id,
      p_equine_id,
      'ZERO_SESSION'
    ) then
      overall := public.worse_booking_eligibility_token(
        overall,
        'REQUIRES_ZERO_SESSION'
      );
      overall_status := overall;
      requirement_type := 'ZERO_SESSION_REQUIRED';
      source_type := 'EQUINE';
      source_id := p_equine_id;
      is_met := false;
      detail := 'Currently effective ZERO_SESSION authorization is required';
      return next;
    end if;
  end if;

  if public.has_active_equine_boolean_requirement(
    p_equine_id,
    'OWNER_APPROVAL_REQUIRED'
  ) then
    if not public.has_effective_rider_equine_authorization(
      p_participant_person_id,
      p_equine_id,
      'OWNER_APPROVAL'
    ) then
      overall := public.worse_booking_eligibility_token(
        overall,
        'REQUIRES_OWNER_APPROVAL'
      );
      overall_status := overall;
      requirement_type := 'OWNER_APPROVAL_REQUIRED';
      source_type := 'OWNER';
      source_id := p_equine_id;
      is_met := false;
      detail := 'Currently effective OWNER_APPROVAL authorization is required';
      return next;
    end if;
  end if;

  if public.has_active_equine_boolean_requirement(
    p_equine_id,
    'SUPERVISION_REQUIRED'
  ) then
    overall := public.worse_booking_eligibility_token(
      overall,
      'ELIGIBLE_WITH_SUPERVISION'
    );
  end if;

  for requirement_row in
    select *
      from public.equine_requirements as requirement
     where requirement.equine_id = p_equine_id
       and requirement.status = 'ACTIVE'
       and requirement.requirement_type in (
         'MIN_QUALIFICATION',
         'MIN_EXPERIENCE'
       )
  loop
    overall := public.worse_booking_eligibility_token(
      overall,
      'QUALIFICATION_NOT_VERIFIED'
    );
    overall_status := overall;
    requirement_type := requirement_row.requirement_type;
    source_type := requirement_row.source_type;
    source_id := requirement_row.id;
    is_met := false;
    detail := 'Qualification or experience verification is not implemented';
    return next;
  end loop;

  if age_years is not null then
    for requirement_row in
      select *
        from public.equine_requirements as requirement
       where requirement.equine_id = p_equine_id
         and requirement.status = 'ACTIVE'
         and requirement.requirement_type in ('MIN_AGE', 'MAX_AGE')
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
      end if;
    end loop;
  end if;

  if not found and overall in ('ELIGIBLE', 'ELIGIBLE_WITH_SUPERVISION') then
    -- Ensure a result row exists when every checked requirement is met.
    null;
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
  'Server-internal eligibility collector. Returns unmet requirement rows plus a final overall row. Policy acceptances are evaluated for p_policy_person_id, never blindly auth.uid(). Not executable by PUBLIC, anon or authenticated.';

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
declare
  policy_person uuid;
begin
  if p_caller_person_id = p_participant_person_id then
    return p_participant_person_id;
  end if;

  if public.has_current_verified_guardian_relationship(
    p_caller_person_id,
    p_participant_person_id
  ) then
    return p_caller_person_id;
  end if;

  -- Staff MANAGE_BOOKINGS path: adult uses the participant; minor uses
  -- one current VERIFIED guardian when present.
  select relationship.guardian_person_id
    into policy_person
    from public.guardian_relationships as relationship
   where relationship.minor_person_id = p_participant_person_id
     and relationship.verification_status = 'VERIFIED'
     and relationship.revoked_at is null
     and (
       relationship.expires_at is null
       or relationship.expires_at > now()
     )
   order by relationship.verified_at
   limit 1;

  if policy_person is not null then
    return policy_person;
  end if;

  return p_participant_person_id;
end;
$$;

comment on function public.resolve_eligibility_policy_person(uuid, uuid) is
  'Chooses whose policy acceptances count. Staff callers must not use auth.uid() acceptances. Not executable by PUBLIC, anon or authenticated.';

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
begin
  delete from public.booking_requirements
   where booking_id = p_booking_id;

  for eligibility_row in
    select *
      from public.collect_booking_eligibility(
        p_participant_person_id,
        p_equine_id,
        p_center_id,
        p_starts_at,
        p_ends_at,
        p_service_id,
        p_policy_person_id
      )
     where requirement_type is not null
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
      jsonb_build_object('detail', eligibility_row.detail)
    );
  end loop;
end;
$$;

comment on function public.persist_booking_requirement_rows(uuid, uuid, uuid, uuid, timestamptz, timestamptz, uuid, uuid, uuid) is
  'Writes explainable booking_requirements from the collector. Must run while the booking is not CONFIRMED. Not executable by PUBLIC, anon or authenticated.';

revoke all on function public.persist_booking_requirement_rows(uuid, uuid, uuid, uuid, timestamptz, timestamptz, uuid, uuid, uuid)
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
    caller_person
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
    caller_person,
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
declare
  current_auth_user_id uuid := auth.uid();
  caller_account uuid;
  caller_person uuid;
  booking_row public.bookings%rowtype;
  booker_person uuid;
  policy_person uuid;
  overall text;
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

  if not public.has_active_equine_center_permission(
    booking_row.equine_id,
    booking_row.center_id,
    'MANAGE_BOOKINGS'
  ) then
    raise exception using
      errcode = '42501',
      message = 'Confirming a booking requires effective MANAGE_BOOKINGS for this equine at this Center';
  end if;

  select account.person_id
    into booker_person
    from public.user_accounts as account
   where account.id = booking_row.booked_by_account_id;

  policy_person := public.resolve_eligibility_policy_person(
    booking_row.participant_person_id,
    booker_person
  );

  perform set_config('app.confirming_booking', '1', true);

  overall := public.booking_eligibility_overall(
    booking_row.participant_person_id,
    booking_row.equine_id,
    booking_row.center_id,
    booking_row.starts_at,
    booking_row.ends_at,
    booking_row.service_id,
    policy_person
  );

  if overall not in ('ELIGIBLE', 'ELIGIBLE_WITH_SUPERVISION') then
    raise exception using
      errcode = '42501',
      message = 'Booking is not currently eligible to confirm';
  end if;

  if public.has_active_equine_boolean_requirement(
       booking_row.equine_id,
       'ZERO_SESSION_REQUIRED'
     )
     and not public.has_effective_rider_equine_authorization(
       booking_row.participant_person_id,
       booking_row.equine_id,
       'ZERO_SESSION'
     ) then
    raise exception using
      errcode = '42501',
      message = 'ZERO_SESSION_REQUIRED is not satisfied by a Zero Session result alone';
  end if;

  if public.has_active_equine_boolean_requirement(
       booking_row.equine_id,
       'OWNER_APPROVAL_REQUIRED'
     )
     and not public.has_effective_rider_equine_authorization(
       booking_row.participant_person_id,
       booking_row.equine_id,
       'OWNER_APPROVAL'
     ) then
    raise exception using
      errcode = '42501',
      message = 'OWNER_APPROVAL_REQUIRED needs a currently effective OWNER_APPROVAL authorization';
  end if;

  if public.has_active_equine_boolean_requirement(
       booking_row.equine_id,
       'CENTER_ASSESSMENT_REQUIRED'
     )
     and not public.has_current_valid_rider_assessment(
       booking_row.participant_person_id,
       booking_row.center_id
     ) then
    raise exception using
      errcode = '42501',
      message = 'CENTER_ASSESSMENT_REQUIRED needs a current VALID assessment at this Center';
  end if;

  perform public.persist_booking_requirement_rows(
    booking_row.id,
    booking_row.participant_person_id,
    booking_row.equine_id,
    booking_row.center_id,
    booking_row.starts_at,
    booking_row.ends_at,
    booking_row.service_id,
    policy_person,
    caller_account
  );

  select coalesce(
    jsonb_object_agg(document.policy_type, document.id),
    '{}'::jsonb
  )
    into policy_snapshot
    from public.policy_documents as document
   where document.market_code = (
           select center.country_code
             from public.equestrian_centers as center
            where center.id = booking_row.center_id
         )
     and document.status = 'ACTIVE'
     and document.policy_type in (
       'TERMS_OF_SERVICE',
       'PRIVACY_POLICY',
       'RIDER_POLICY',
       'ACTIVITY_POLICY'
     )
     and document.effective_from <= now()
     and (
       document.effective_to is null
       or document.effective_to > now()
     );

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
      caller_account
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
         booking_policy_snapshot = policy_snapshot,
         updated_at = now()
   where id = booking_row.id;

  return booking_row.id;
end;
$$;

comment on function public.confirm_booking(uuid) is
  'Authenticated confirm. Requires effective MANAGE_BOOKINGS. Accepts only APPROVED. Revalidates eligibility, consent, policies, authorization and availability; inserts a BOOKING calendar block; sets CONFIRMED. Rolls back on any failure. Booker-alone is not enough.';

revoke all on function public.confirm_booking(uuid)
  from public, anon, authenticated;
grant execute on function public.confirm_booking(uuid)
  to authenticated;
