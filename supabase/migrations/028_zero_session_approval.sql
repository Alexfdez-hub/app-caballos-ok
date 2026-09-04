-- Phase 9B: server-authoritative Zero Session approval.
--
-- Approval remains distinct from assessment and rider-equine authorization.
-- This RPC does not create an authorization. It serializes on the target
-- Zero Session, derives evaluator/time from the authenticated call, and
-- fails closed on authority, policy, minority or consent uncertainty.

create or replace function public.enforce_zero_session_evaluator_authority()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if TG_OP = 'UPDATE' then
    if new.rider_person_id is distinct from old.rider_person_id
       or new.equine_id is distinct from old.equine_id
       or new.center_id is distinct from old.center_id
       or new.requested_by_account_id is distinct from old.requested_by_account_id then
      raise exception using
        errcode = '42501',
        message = 'Historical Zero Session identity cannot be rewritten';
    end if;

    if old.result <> 'PENDING'
       and (
         new.evaluator_person_id is distinct from old.evaluator_person_id
         or new.result is distinct from old.result
         or new.performed_at is distinct from old.performed_at
         or new.notes is distinct from old.notes
       ) then
      raise exception using
        errcode = '42501',
        message = 'Finalized Zero Session facts cannot be rewritten';
    end if;

    if old.evaluator_person_id is not null
       and new.evaluator_person_id is distinct from old.evaluator_person_id then
      raise exception using
        errcode = '42501',
        message = 'Historical Zero Session evaluator cannot be rewritten';
    end if;
  end if;

  if new.evaluator_person_id is not null then
    if new.evaluator_person_id = new.rider_person_id then
      raise exception using
        errcode = '23514',
        message = 'A Zero Session evaluator cannot be the rider';
    end if;

    if not public.has_active_center_role(
      new.evaluator_person_id,
      new.center_id,
      'ASSESSOR'
    ) then
      raise exception using
        errcode = '42501',
        message = 'Zero Session evaluation requires an active ASSESSOR membership at this Center';
    end if;

    if not public.has_active_equine_center_permission(
      new.equine_id,
      new.center_id,
      'ASSESS_RIDERS'
    ) then
      raise exception using
        errcode = '42501',
        message = 'Zero Session evaluation requires effective ASSESS_RIDERS for this equine at this Center';
    end if;
  end if;

  return new;
end;
$$;

comment on function public.enforce_zero_session_evaluator_authority() is
  'BEFORE INSERT OR UPDATE: enforces evaluator authority, immutable participant identity and immutable finalized result/evaluator/time/notes. ASSESSOR alone is insufficient; effective ASSESS_RIDERS is also required. Not executable by anon or authenticated.';

revoke all on function public.enforce_zero_session_evaluator_authority()
  from public, anon, authenticated;

create function public.approve_zero_session(
  p_zero_session_id uuid,
  p_result text,
  p_notes text default null
)
returns table (
  zero_session_id uuid,
  result text,
  evaluator_person_id uuid,
  performed_at timestamptz,
  notes text
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
#variable_conflict use_variable
declare
  current_auth_user_id uuid := auth.uid();
  caller_account public.user_accounts%rowtype;
  target_session public.zero_sessions%rowtype;
  center_market_code text;
  approval_time timestamptz := statement_timestamp();
  activity_time timestamptz;
  minority_row record;
  guardian_required boolean := false;
  required_policy_type text;
begin
  if current_auth_user_id is null then
    raise exception using
      errcode = '42501',
      message = 'Authentication required';
  end if;

  if p_zero_session_id is null or p_result is null then
    raise exception using
      errcode = '22023',
      message = 'Zero Session id and approval result are required';
  end if;

  if p_result not in ('APPROVED', 'APPROVED_WITH_RESTRICTIONS') then
    raise exception using
      errcode = '22023',
      message = 'approve_zero_session only accepts approved results';
  end if;

  if p_notes is not null
     and (p_notes <> btrim(p_notes) or char_length(p_notes) = 0) then
    raise exception using
      errcode = '22023',
      message = 'Notes must be non-empty and trimmed when supplied';
  end if;

  select account.*
    into caller_account
    from public.user_accounts as account
    join public.persons as person on person.id = account.person_id
   where account.auth_user_id = current_auth_user_id
     and account.status = 'ACTIVE'
     and person.status = 'ACTIVE';

  if caller_account.id is null then
    raise exception using
      errcode = '42501',
      message = 'Active caller identity could not be resolved';
  end if;

  select zero_session.*
    into target_session
    from public.zero_sessions as zero_session
   where zero_session.id = p_zero_session_id
   for update;

  if target_session.id is null then
    raise exception using
      errcode = 'P0002',
      message = 'Zero Session not found';
  end if;

  -- An exact replay by the original evaluator is read-only and remains
  -- idempotent even if that evaluator later loses operational authority.
  if target_session.result in ('APPROVED', 'APPROVED_WITH_RESTRICTIONS') then
    if target_session.evaluator_person_id is not distinct from caller_account.person_id
       and target_session.result = p_result
       and target_session.notes is not distinct from p_notes then
      zero_session_id := target_session.id;
      result := target_session.result;
      evaluator_person_id := target_session.evaluator_person_id;
      performed_at := target_session.performed_at;
      notes := target_session.notes;
      return next;
      return;
    end if;

    raise exception using
      errcode = '40001',
      message = 'Zero Session was already approved with different facts';
  end if;

  if target_session.result <> 'PENDING' then
    raise exception using
      errcode = '55000',
      message = 'Only a PENDING Zero Session can be approved';
  end if;

  if target_session.scheduled_at is not null
     and target_session.scheduled_at > approval_time then
    raise exception using
      errcode = '55000',
      message = 'A future Zero Session cannot be approved';
  end if;

  -- Minority and guardian authority are activity-time facts. Using approval
  -- time would let a rider who turned adult after the session bypass the
  -- consent that was required when the equestrian activity occurred.
  activity_time := coalesce(target_session.scheduled_at, approval_time);

  if target_session.rider_person_id = caller_account.person_id then
    raise exception using
      errcode = '42501',
      message = 'A rider cannot approve their own Zero Session';
  end if;

  select center.country_code
    into center_market_code
    from public.equestrian_centers as center
   where center.id = target_session.center_id
     and center.status = 'ACTIVE';

  if center_market_code is null then
    raise exception using
      errcode = '42501',
      message = 'Zero Session Center is not active or has no market';
  end if;

  if not exists (
    select 1
      from public.persons as rider
     where rider.id = target_session.rider_person_id
       and rider.status = 'ACTIVE'
  ) then
    raise exception using
      errcode = '42501',
      message = 'Zero Session rider is not active';
  end if;

  if not exists (
    select 1
      from public.equines as equine
     where equine.id = target_session.equine_id
       and equine.status = 'ACTIVE'
  ) then
    raise exception using
      errcode = '42501',
      message = 'Zero Session equine is not active';
  end if;

  if not public.has_active_center_role(
    caller_account.person_id,
    target_session.center_id,
    'ASSESSOR'
  ) then
    raise exception using
      errcode = '42501',
      message = 'Zero Session approval requires an active ASSESSOR membership';
  end if;

  if not public.has_active_equine_center_permission(
    target_session.equine_id,
    target_session.center_id,
    'ASSESS_RIDERS'
  ) then
    raise exception using
      errcode = '42501',
      message = 'Zero Session approval requires effective ASSESS_RIDERS';
  end if;

  foreach required_policy_type in array array['CENTER_POLICY', 'ASSESSOR_POLICY']
  loop
    if not public.has_person_accepted_required_policy(
      caller_account.person_id,
      required_policy_type,
      center_market_code,
      approval_time
    ) then
      raise exception using
        errcode = '42501',
        message = format('Caller has not accepted required %s', required_policy_type);
    end if;
  end loop;

  select *
    into minority_row
    from public.evaluate_person_minority(
      target_session.rider_person_id,
      center_market_code,
      (timezone('utc', activity_time))::date
    );

  guardian_required := minority_row.guardian_consent_required;

  if guardian_required then
    if not public.has_any_verified_guardian_at(
      target_session.rider_person_id,
      activity_time
    ) then
      raise exception using
        errcode = '42501',
        message = 'Minor rider had no verified guardian at activity time';
    end if;

    if not public.has_equestrian_activity_consent_at(
      target_session.rider_person_id,
      activity_time
    ) then
      raise exception using
        errcode = '42501',
        message = 'Minor rider lacked valid equestrian activity consent at activity time';
    end if;
  end if;

  foreach required_policy_type in array array[
    'TERMS_OF_SERVICE',
    'PRIVACY_POLICY',
    'RIDER_POLICY',
    'ACTIVITY_POLICY'
  ]
  loop
    if not public.has_participant_accepted_required_policy(
      target_session.rider_person_id,
      required_policy_type,
      center_market_code,
      approval_time,
      guardian_required
    ) then
      raise exception using
        errcode = '42501',
        message = format('Rider has not accepted required %s', required_policy_type);
    end if;
  end loop;

  update public.zero_sessions as zero_session
     set evaluator_person_id = caller_account.person_id,
         result = p_result,
         performed_at = approval_time,
         notes = p_notes
   where zero_session.id = target_session.id
     and zero_session.result = 'PENDING'
  returning zero_session.id,
            zero_session.result,
            zero_session.evaluator_person_id,
            zero_session.performed_at,
            zero_session.notes
       into zero_session_id, result, evaluator_person_id, performed_at, notes;

  if zero_session_id is null then
    raise exception using
      errcode = '40001',
      message = 'Zero Session approval lost its serialized update';
  end if;

  return next;
end;
$$;

comment on function public.approve_zero_session(uuid, text, text) is
  'Approves one PENDING Zero Session under a row lock. Actor and performed_at are server-derived; active ASSESSOR, ASSESS_RIDERS and required policies are enforced at approval, while minority and guardian consent are evaluated at scheduled activity time. Exact replay is idempotent. Does not create a rider-equine authorization.';

revoke all on function public.approve_zero_session(uuid, text, text)
  from public, anon, authenticated;
grant execute on function public.approve_zero_session(uuid, text, text)
  to authenticated;
