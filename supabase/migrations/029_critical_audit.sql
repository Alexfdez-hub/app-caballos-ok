-- Phase 13C: critical audit coverage for committed transitions that 026
-- deliberately left unaudited.
--
-- Extends public.audit_events via new AFTER triggers only. Does not edit
-- migrations 001–028. Does not add a client audit feed, table grants or
-- public write RPC. Does not expand product semantics.
--
-- Covered committed transitions:
--   policy accepted;
--   guardian consent granted / revoked;
--   rider assessment validated;
--   equine permission granted / revoked;
--   Zero Session approved;
--   booking confirmed / cancelled.
--
-- Failed calls, rolled-back transactions and exact idempotent replays
-- that do not INSERT/UPDATE create no event. Actor/account/person and
-- occurred_at remain server-authoritative through record_audit_event.
-- Metadata is bounded and allowlisted: ids and public-safe tokens only.
--
-- Unauthenticated fixture DML (no auth.uid()) does not fail and does
-- not write audit. Production RPCs and JWT-backed server writes audit.

create function public.record_authenticated_audit_event(
  p_event_type text,
  p_entity_type text,
  p_entity_id uuid,
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if auth.uid() is null then
    return null;
  end if;

  return public.record_audit_event(
    p_event_type,
    p_entity_type,
    p_entity_id,
    p_metadata
  );
end;
$$;

comment on function public.record_authenticated_audit_event(text, text, uuid, jsonb) is
  '029 wrapper: writes audit only when auth.uid() is present. Unauthenticated fixture DML is skipped. Not executable by PUBLIC, anon or authenticated.';

revoke all on function public.record_authenticated_audit_event(text, text, uuid, jsonb)
  from public, anon, authenticated;

create function public.emit_policy_acceptance_audit()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  perform public.record_authenticated_audit_event(
    'policy_accepted',
    'policy_acceptance',
    new.id,
    jsonb_build_object(
      'policy_document_id', new.policy_document_id,
      'person_id', new.person_id,
      'user_account_id', new.user_account_id
    )
  );
  return new;
end;
$$;

comment on function public.emit_policy_acceptance_audit() is
  'AFTER INSERT on policy_acceptances: records policy_accepted without policy bodies, acceptance_context or row metadata. Not executable by PUBLIC, anon or authenticated.';

revoke all on function public.emit_policy_acceptance_audit()
  from public, anon, authenticated;

create trigger policy_acceptances_audit_events
after insert on public.policy_acceptances
for each row execute function public.emit_policy_acceptance_audit();

create function public.emit_guardian_consent_audit()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if TG_OP = 'INSERT' and new.status = 'ACTIVE' then
    perform public.record_authenticated_audit_event(
      'guardian_consent_granted',
      'guardian_consent',
      new.id,
      jsonb_build_object(
        'guardian_relationship_id', new.guardian_relationship_id,
        'minor_person_id', new.minor_person_id,
        'consent_type', new.consent_type,
        'scope_type', new.scope_type
      )
    );
  elsif TG_OP = 'UPDATE'
     and old.status is distinct from 'REVOKED'
     and new.status = 'REVOKED' then
    perform public.record_authenticated_audit_event(
      'guardian_consent_revoked',
      'guardian_consent',
      new.id,
      jsonb_build_object(
        'guardian_relationship_id', new.guardian_relationship_id,
        'minor_person_id', new.minor_person_id,
        'consent_type', new.consent_type,
        'scope_type', new.scope_type
      )
    );
  end if;

  return new;
end;
$$;

comment on function public.emit_guardian_consent_audit() is
  'AFTER INSERT OR UPDATE on guardian_consents: records granted/revoked. EXPIRED updates and idempotent revoke no-ops are not audited. Not executable by PUBLIC, anon or authenticated.';

revoke all on function public.emit_guardian_consent_audit()
  from public, anon, authenticated;

create trigger guardian_consents_audit_events
after insert or update on public.guardian_consents
for each row execute function public.emit_guardian_consent_audit();

create function public.emit_rider_assessment_audit()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if new.status = 'VALID'
     and (
       TG_OP = 'INSERT'
       or old.status is distinct from 'VALID'
     ) then
    perform public.record_authenticated_audit_event(
      'rider_assessment_validated',
      'rider_assessment',
      new.id,
      jsonb_build_object(
        'rider_person_id', new.rider_person_id,
        'center_id', new.center_id,
        'assessor_person_id', new.assessor_person_id,
        'assessment_type', new.assessment_type
      )
    );
  end if;

  return new;
end;
$$;

comment on function public.emit_rider_assessment_audit() is
  'AFTER INSERT OR UPDATE on rider_assessments: records rider_assessment_validated without notes. DRAFT/PENDING and already-VALID replays are not audited. Not executable by PUBLIC, anon or authenticated.';

revoke all on function public.emit_rider_assessment_audit()
  from public, anon, authenticated;

create trigger rider_assessments_audit_events
after insert or update on public.rider_assessments
for each row execute function public.emit_rider_assessment_audit();

create function public.emit_equine_permission_audit()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if TG_OP = 'INSERT' and new.status = 'ACTIVE' then
    perform public.record_authenticated_audit_event(
      'equine_permission_granted',
      'equine_center_permission',
      new.id,
      jsonb_build_object(
        'equine_id', new.equine_id,
        'center_id', new.center_id,
        'permission_code', new.permission_code
      )
    );
  elsif TG_OP = 'UPDATE'
     and old.status is distinct from 'REVOKED'
     and new.status = 'REVOKED' then
    perform public.record_authenticated_audit_event(
      'equine_permission_revoked',
      'equine_center_permission',
      new.id,
      jsonb_build_object(
        'equine_id', new.equine_id,
        'center_id', new.center_id,
        'permission_code', new.permission_code
      )
    );
  end if;

  return new;
end;
$$;

comment on function public.emit_equine_permission_audit() is
  'AFTER INSERT OR UPDATE on equine_center_permissions: records granted/revoked. Idempotent revoke no-ops are not audited. Not executable by PUBLIC, anon or authenticated.';

revoke all on function public.emit_equine_permission_audit()
  from public, anon, authenticated;

create trigger equine_center_permissions_audit_events
after insert or update on public.equine_center_permissions
for each row execute function public.emit_equine_permission_audit();

create function public.emit_zero_session_audit()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if new.result in ('APPROVED', 'APPROVED_WITH_RESTRICTIONS')
     and (
       TG_OP = 'INSERT'
       or old.result is distinct from new.result
     ) then
    perform public.record_authenticated_audit_event(
      'zero_session_approved',
      'zero_session',
      new.id,
      jsonb_build_object(
        'rider_person_id', new.rider_person_id,
        'equine_id', new.equine_id,
        'center_id', new.center_id,
        'result', new.result
      )
    );
  end if;

  return new;
end;
$$;

comment on function public.emit_zero_session_audit() is
  'AFTER INSERT OR UPDATE on zero_sessions: records zero_session_approved without notes. Exact replay no-ops and REJECTED/CANCELLED are not audited. Not executable by PUBLIC, anon or authenticated.';

revoke all on function public.emit_zero_session_audit()
  from public, anon, authenticated;

create trigger zero_sessions_audit_events
after insert or update on public.zero_sessions
for each row execute function public.emit_zero_session_audit();

create function public.emit_booking_audit()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if new.status = 'CONFIRMED'
     and (
       TG_OP = 'INSERT'
       or old.status is distinct from 'CONFIRMED'
     ) then
    perform public.record_authenticated_audit_event(
      'booking_confirmed',
      'booking',
      new.id,
      jsonb_build_object(
        'participant_person_id', new.participant_person_id,
        'equine_id', new.equine_id,
        'center_id', new.center_id
      )
    );
  end if;

  if new.status = 'CANCELLED'
     and (
       TG_OP = 'INSERT'
       or old.status is distinct from 'CANCELLED'
     ) then
    perform public.record_authenticated_audit_event(
      'booking_cancelled',
      'booking',
      new.id,
      jsonb_build_object(
        'participant_person_id', new.participant_person_id,
        'equine_id', new.equine_id,
        'center_id', new.center_id
      )
    );
  end if;

  return new;
end;
$$;

comment on function public.emit_booking_audit() is
  'AFTER INSERT OR UPDATE on bookings: records booking_confirmed / booking_cancelled without policy snapshots. REQUESTED and exact status replays are not audited. Not executable by PUBLIC, anon or authenticated.';

revoke all on function public.emit_booking_audit()
  from public, anon, authenticated;

create trigger bookings_audit_events
after insert or update on public.bookings
for each row execute function public.emit_booking_audit();
