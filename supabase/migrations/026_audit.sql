-- Phase 13B: append-only audit foundation.
--
-- Adds public.audit_events and server-side integration for 023–025
-- critical transitions only: session started/completed, equine activity
-- recorded, review submitted, incident reported. Does not edit
-- migrations 001–025. Does not retrofit policy acceptance, guardian
-- consent, assessments, equine permissions, zero-session approval or
-- booking confirm/cancel. Does not create Storage buckets.
--
-- Architecture 2.1 lists audit_events columns and names those key
-- events. It does not freeze event_type / entity_type catalogs, so
-- those columns are stored without invented CHECK vocabularies.
--
-- Integration is trigger-based so 023–025 RPC bodies stay unchanged.
-- Replay paths that do not INSERT/UPDATE do not write a second event.
-- Failed RPCs roll back the audit row with the parent transaction.
--
-- Metadata is bounded and must not contain secrets, JWTs, policy
-- bodies, evidence blobs or service-role material. Actor identity is
-- overwritten from auth.uid() via resolve_session_caller(). occurred_at
-- is clock_timestamp().
--
-- Access model follows migrations 006–025:
--   - RLS enabled, deny-by-default, no client table policies.
--   - No table INSERT/UPDATE/DELETE/SELECT for anon or authenticated.
--   - No public audit RPC. Clients cannot enumerate global history.
--   - Internal helpers stay revoked from PUBLIC, anon and authenticated.

create table public.audit_events (
  id uuid primary key default gen_random_uuid(),
  actor_account_id uuid,
  actor_person_id uuid,
  event_type text not null,
  entity_type text not null,
  entity_id uuid not null,
  metadata jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default now()
);

create index audit_events_entity_idx
  on public.audit_events (entity_type, entity_id);

create index audit_events_occurred_at_idx
  on public.audit_events (occurred_at);

create index audit_events_actor_account_id_idx
  on public.audit_events (actor_account_id);

comment on table public.audit_events is
  'Append-only server audit of selected 023–025 transitions. Not a global event dump, evidence store or client-readable feed.';
comment on column public.audit_events.actor_account_id is
  'Caller ACCOUNT copied from resolve_session_caller. Never a caller-supplied actor id. No FK so history can outlive fixture cleanup.';
comment on column public.audit_events.actor_person_id is
  'Caller PERSON copied from resolve_session_caller. Never an Auth UUID.';
comment on column public.audit_events.event_type is
  'Stable label for the transition. Vocabulary is not frozen as a CHECK catalog.';
comment on column public.audit_events.entity_type is
  'Stable label for the subject kind. Vocabulary is not frozen as a CHECK catalog.';
comment on column public.audit_events.entity_id is
  'Subject row id. Polymorphic; no FK.';
comment on column public.audit_events.metadata is
  'Bounded ids and public-safe fields only. No secrets, JWTs, policy bodies, evidence blobs or service-role material.';
comment on column public.audit_events.occurred_at is
  'Server wall-clock time. Forced to clock_timestamp() on insert.';

create function public.set_audit_write(p_enabled boolean)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  perform set_config(
    'app.audit_write',
    case when p_enabled then '1' else '' end,
    true
  );
end;
$$;

comment on function public.set_audit_write(boolean) is
  'Internal transaction-local GUC for audit_events triggers. Callers must clear it before returning. Not executable by PUBLIC, anon or authenticated.';

revoke all on function public.set_audit_write(boolean)
  from public, anon, authenticated;

create function public.audit_metadata_is_safe(p_metadata jsonb)
returns boolean
language plpgsql
immutable
security definer
set search_path = pg_catalog, public
as $$
begin
  if p_metadata is null then
    return true;
  end if;

  if jsonb_typeof(p_metadata) is distinct from 'object' then
    return false;
  end if;

  if octet_length(p_metadata::text) > 4096 then
    return false;
  end if;

  if exists (
    select 1
      from jsonb_object_keys(p_metadata) as key
     where key ~* '(jwt|token|secret|password|passwd|service_role|authorization|cookie|evidence|policy|document|blob|private_key)'
  ) then
    return false;
  end if;

  if exists (
    select 1
      from jsonb_each_text(p_metadata) as item
     where item.value ~ 'eyJ[A-Za-z0-9_-]{10,}'
  ) then
    return false;
  end if;

  return true;
end;
$$;

comment on function public.audit_metadata_is_safe(jsonb) is
  'True when metadata is a small JSON object without secret/JWT/policy/evidence keys or JWT-shaped values. Not executable by PUBLIC, anon or authenticated.';

revoke all on function public.audit_metadata_is_safe(jsonb)
  from public, anon, authenticated;

create function public.enforce_audit_immutability()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller_account uuid;
  caller_person uuid;
begin
  if TG_OP = 'DELETE' then
    raise exception using
      errcode = '42501',
      message = 'Audit history cannot be deleted';
  end if;

  if TG_OP = 'UPDATE' then
    raise exception using
      errcode = '42501',
      message = 'Audit events cannot be rewritten';
  end if;

  if current_setting('app.audit_write', true) is distinct from '1' then
    raise exception using
      errcode = '42501',
      message = 'Audit events can only be created by server integrations';
  end if;

  if new.event_type is null or btrim(new.event_type) = ''
     or new.entity_type is null or btrim(new.entity_type) = ''
     or new.entity_id is null then
    raise exception using
      errcode = '22023',
      message = 'Audit requires event type, entity type and entity id';
  end if;

  if new.metadata is null then
    new.metadata := '{}'::jsonb;
  end if;

  if not public.audit_metadata_is_safe(new.metadata) then
    raise exception using
      errcode = '23514',
      message = 'Audit metadata is not allowed';
  end if;

  select caller.account_id, caller.person_id
    into caller_account, caller_person
    from public.resolve_session_caller() as caller;

  new.actor_account_id := caller_account;
  new.actor_person_id := caller_person;
  new.event_type := btrim(new.event_type);
  new.entity_type := btrim(new.entity_type);
  new.occurred_at := clock_timestamp();
  return new;
end;
$$;

comment on function public.enforce_audit_immutability() is
  'BEFORE INSERT OR UPDATE OR DELETE: audit is append-only. Actor and occurred_at are server-authoritative. Not executable by PUBLIC, anon or authenticated.';

revoke all on function public.enforce_audit_immutability()
  from public, anon, authenticated;

create trigger audit_events_immutability
before insert or update or delete on public.audit_events
for each row execute function public.enforce_audit_immutability();

create function public.record_audit_event(
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
declare
  created_id uuid;
begin
  perform public.resolve_session_caller();

  perform public.set_audit_write(true);

  begin
    insert into public.audit_events (
      event_type,
      entity_type,
      entity_id,
      metadata
    ) values (
      p_event_type,
      p_entity_type,
      p_entity_id,
      coalesce(p_metadata, '{}'::jsonb)
    ) returning id into created_id;

    perform public.set_audit_write(false);
  exception
    when others then
      perform public.set_audit_write(false);
      raise;
  end;

  return created_id;
end;
$$;

comment on function public.record_audit_event(text, text, uuid, jsonb) is
  'Internal writer for 023–025 audit integrations. Actor comes from auth.uid(). Not executable by PUBLIC, anon or authenticated.';

revoke all on function public.record_audit_event(text, text, uuid, jsonb)
  from public, anon, authenticated;

create function public.emit_session_audit()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if TG_OP = 'INSERT' and new.started_at is not null then
    perform public.record_audit_event(
      'session_started',
      'session',
      new.id,
      jsonb_build_object('booking_id', new.booking_id)
    );
  elsif TG_OP = 'UPDATE'
     and old.started_at is null
     and new.started_at is not null then
    perform public.record_audit_event(
      'session_started',
      'session',
      new.id,
      jsonb_build_object('booking_id', new.booking_id)
    );
  end if;

  if TG_OP = 'UPDATE'
     and old.ended_at is null
     and new.ended_at is not null then
    perform public.record_audit_event(
      'session_completed',
      'session',
      new.id,
      jsonb_build_object('booking_id', new.booking_id)
    );
  end if;

  return new;
end;
$$;

comment on function public.emit_session_audit() is
  'AFTER INSERT OR UPDATE on sessions: records session_started / session_completed. Does not audit READY or replay no-ops. Not executable by PUBLIC, anon or authenticated.';

revoke all on function public.emit_session_audit()
  from public, anon, authenticated;

create trigger sessions_audit_events
after insert or update on public.sessions
for each row execute function public.emit_session_audit();

create function public.emit_activity_audit()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  perform public.record_audit_event(
    'equine_activity_recorded',
    'equine_activity',
    new.id,
    jsonb_build_object(
      'session_id', new.session_id,
      'booking_id', new.booking_id,
      'equine_id', new.equine_id
    )
  );
  return new;
end;
$$;

comment on function public.emit_activity_audit() is
  'AFTER INSERT on equine_activities: records equine_activity_recorded. Updates are not audited. Not executable by PUBLIC, anon or authenticated.';

revoke all on function public.emit_activity_audit()
  from public, anon, authenticated;

create trigger equine_activities_audit_events
after insert on public.equine_activities
for each row execute function public.emit_activity_audit();

create function public.emit_review_audit()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  perform public.record_audit_event(
    'review_submitted',
    'review',
    new.id,
    jsonb_build_object(
      'booking_id', new.booking_id,
      'subject_id', new.subject_id,
      'rating', new.rating
    )
  );
  return new;
end;
$$;

comment on function public.emit_review_audit() is
  'AFTER INSERT on reviews: records review_submitted without comment text. Not executable by PUBLIC, anon or authenticated.';

revoke all on function public.emit_review_audit()
  from public, anon, authenticated;

create trigger reviews_audit_events
after insert on public.reviews
for each row execute function public.emit_review_audit();

create function public.emit_incident_audit()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  perform public.record_audit_event(
    'incident_reported',
    'incident',
    new.id,
    jsonb_build_object(
      'booking_id', new.booking_id,
      'session_id', new.session_id,
      'equine_id', new.equine_id,
      'center_id', new.center_id
    )
  );
  return new;
end;
$$;

comment on function public.emit_incident_audit() is
  'AFTER INSERT on incidents: records incident_reported without description text. Not executable by PUBLIC, anon or authenticated.';

revoke all on function public.emit_incident_audit()
  from public, anon, authenticated;

create trigger incidents_audit_events
after insert on public.incidents
for each row execute function public.emit_incident_audit();

alter table public.audit_events enable row level security;

revoke all on table public.audit_events from anon, authenticated;
