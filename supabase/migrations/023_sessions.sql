-- Phase 12A: verified sessions foundation.
--
-- Adds public.sessions, public.session_events, public.session_evidence
-- and public.session_permits, plus start_session() / end_session() and
-- the server-issued confirmed-booking permit used for Architecture 2.1
-- offline start. Does not create Storage buckets, upload policies,
-- equine_activities, reviews, incidents or audit_events.
--
-- Does not edit migrations 001–022. CREATE OR REPLACE replaces the
-- 022 booking authority function so start_session / end_session can
-- move a CONFIRMED booking to ACTIVE and an ACTIVE booking to
-- COMPLETED when transaction-local app.session_transition = '1'.
--
-- Architecture 2.1 Frozen:
--   session is linked to one booking (booking_id UNIQUE);
--   participant remains PERSON; booker remains ACCOUNT;
--   session statuses READY | ACTIVE | ENDING | COMPLETED |
--     PENDING_SYNC | REQUIRES_REVIEW | INVALIDATED;
--   event types CHECK_IN | START | PHOTO_START | END_REQUESTED |
--     PHOTO_END | CHECK_OUT | SYNC;
--   evidence types START_PHOTO | END_PHOTO | INCIDENT_PHOTO;
--   official timestamps are server-authoritative;
--   client/device time and UI timers are display inputs only;
--   offline only for a previously CONFIRMED booking with a
--     server-issued permit bound to booking, participant, equine and
--     the booking time window;
--   evidence metadata is private; inconsistent evidence is not deleted.
--
-- Caller authority derived from existing primitives only:
--   participant ACCOUNT, booked_by ACCOUNT, or the frozen 022 Center
--   ADMIN/MANAGER + effective MANAGE_BOOKINGS path
--   (caller_has_booking_manage_authority). INSTRUCTOR, ASSESSOR,
--   VIEW_ACTIVITY, membership-alone and an unrelated guardian are not
--   enough. A current VERIFIED guardian may operate only when that
--   guardian's ACCOUNT is the booking booker.
--
-- now() is not used in a table CHECK. Official started_at, ended_at
-- and received_at_server use clock_timestamp() (wall clock), not
-- transaction-start now(), so ended_at > started_at holds when start
-- and end run in one SQL transaction. Session RPCs clear
-- app.session_transition before returning so a later statement cannot
-- reuse the GUC.
--
-- Access model follows migrations 006–022:
--   - RLS enabled, deny-by-default, no client table policies.
--   - No table INSERT/UPDATE/DELETE/SELECT for anon or authenticated.
--   - Public RPCs are executable by authenticated only.
--   - Internal helpers stay revoked from PUBLIC, anon and authenticated.

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
  session_transition boolean := current_setting('app.session_transition', true) = '1';
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
      if confirming
         and old.status = 'APPROVED'
         and new.status = 'CONFIRMED' then
        null;
      elsif session_transition
         and old.status = 'CONFIRMED'
         and new.status = 'ACTIVE' then
        null;
      elsif session_transition
         and old.status = 'ACTIVE'
         and new.status = 'COMPLETED' then
        null;
      else
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
  'BEFORE INSERT OR UPDATE OR DELETE: booker is own PERSON or current VERIFIED guardian. Service must belong to center_id. Identity cannot be retargeted. CONFIRMED is allowed only from APPROVED when confirm_booking sets app.confirming_booking=1. ACTIVE is allowed only from CONFIRMED and COMPLETED only from ACTIVE when start_session/end_session set app.session_transition=1. Confirmed history cannot be rewritten. Not executable by anon or authenticated.';

create table public.sessions (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null unique references public.bookings (id),
  equine_id uuid not null references public.equines (id),
  participant_person_id uuid not null references public.persons (id),
  center_id uuid not null references public.equestrian_centers (id),
  status text not null,
  started_at timestamptz,
  ended_at timestamptz,
  start_latitude double precision,
  start_longitude double precision,
  end_latitude double precision,
  end_longitude double precision,
  started_offline boolean not null default false,
  ended_offline boolean not null default false,
  sync_status text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint sessions_status_check
    check (
      status in (
        'READY',
        'ACTIVE',
        'ENDING',
        'COMPLETED',
        'PENDING_SYNC',
        'REQUIRES_REVIEW',
        'INVALIDATED'
      )
    ),
  constraint sessions_range_check
    check (
      ended_at is null
      or (
        started_at is not null
        and ended_at > started_at
      )
    )
);

create index sessions_participant_person_id_idx
  on public.sessions (participant_person_id);

create index sessions_center_id_idx
  on public.sessions (center_id);

create index sessions_equine_id_idx
  on public.sessions (equine_id);

comment on table public.sessions is
  'Verifiable session for one CONFIRMED booking. Participant is PERSON. Official start/end timestamps are server-authoritative. Not a calendar block and not an equine activity row.';
comment on column public.sessions.booking_id is
  'One session per booking. Architecture 2.1 UNIQUE.';
comment on column public.sessions.participant_person_id is
  'Copied from the booking participant PERSON. Never an Auth UUID and never a user_accounts.id.';
comment on column public.sessions.started_at is
  'Server time when start_session succeeds. Client/device clocks are not authority.';
comment on column public.sessions.ended_at is
  'Server time when end_session succeeds. Must be after started_at.';
comment on column public.sessions.sync_status is
  'Optional sync label. Vocabulary is not frozen in Architecture 2.1; no CHECK catalog is invented.';
comment on column public.sessions.started_offline is
  'True only when start used a server-issued confirmed-booking permit. Not a client-signed trust flag.';

create table public.session_events (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.sessions (id),
  event_type text not null,
  occurred_at_device timestamptz,
  received_at_server timestamptz not null default now(),
  latitude double precision,
  longitude double precision,
  device_id text,
  offline boolean not null default false,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint session_events_type_check
    check (
      event_type in (
        'CHECK_IN',
        'START',
        'PHOTO_START',
        'END_REQUESTED',
        'PHOTO_END',
        'CHECK_OUT',
        'SYNC'
      )
    ),
  constraint session_events_metadata_check
    check (jsonb_typeof(metadata) = 'object'),
  constraint session_events_device_id_check
    check (device_id is null or length(btrim(device_id)) > 0)
);

create index session_events_session_id_idx
  on public.session_events (session_id);

comment on table public.session_events is
  'Append-only session event log. received_at_server is the official receipt time. occurred_at_device is a display/sync input only.';

create table public.session_evidence (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.sessions (id),
  evidence_type text not null,
  storage_path text not null,
  captured_at_device timestamptz,
  received_at_server timestamptz not null default now(),
  latitude double precision,
  longitude double precision,
  status text,
  created_at timestamptz not null default now(),
  constraint session_evidence_type_check
    check (
      evidence_type in (
        'START_PHOTO',
        'END_PHOTO',
        'INCIDENT_PHOTO'
      )
    ),
  constraint session_evidence_storage_path_check
    check (length(btrim(storage_path)) > 0),
  constraint session_evidence_storage_path_key unique (storage_path)
);

create index session_evidence_session_id_idx
  on public.session_evidence (session_id);

comment on table public.session_evidence is
  'Private session evidence metadata only. 023 does not create a Storage bucket or upload policy. Historical rows cannot be rewritten.';
comment on column public.session_evidence.status is
  'Optional stored label. Evidence workflow tokens are not frozen; no CHECK catalog is invented.';

create table public.session_permits (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null unique references public.bookings (id),
  participant_person_id uuid not null references public.persons (id),
  equine_id uuid not null references public.equines (id),
  center_id uuid not null references public.equestrian_centers (id),
  valid_from timestamptz not null,
  valid_until timestamptz not null,
  issued_at timestamptz not null default now(),
  issued_by_account_id uuid not null references public.user_accounts (id),
  used_at timestamptz,
  constraint session_permits_window_check
    check (valid_until > valid_from)
);

create index session_permits_participant_person_id_idx
  on public.session_permits (participant_person_id);

comment on table public.session_permits is
  'Server-issued temporary session permit for a previously CONFIRMED booking. Bound to booking, participant, equine and the booking time window. Not a client-signed token and not a new authorization type.';

create function public.enforce_session_immutability()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  transitioning boolean := current_setting('app.session_transition', true) = '1';
begin
  if TG_OP = 'DELETE' then
    raise exception using
      errcode = '42501',
      message = 'Session history cannot be deleted';
  end if;

  if TG_OP = 'INSERT' then
    if not transitioning then
      raise exception using
        errcode = '42501',
        message = 'Sessions can only be created by start_session or issue_session_permit';
    end if;
    return new;
  end if;

  if new.booking_id is distinct from old.booking_id
     or new.equine_id is distinct from old.equine_id
     or new.participant_person_id is distinct from old.participant_person_id
     or new.center_id is distinct from old.center_id
     or new.created_at is distinct from old.created_at then
    raise exception using
      errcode = '42501',
      message = 'Session identity cannot be retargeted';
  end if;

  if old.status in ('COMPLETED', 'INVALIDATED')
     and (
       new.status is distinct from old.status
       or new.started_at is distinct from old.started_at
       or new.ended_at is distinct from old.ended_at
     ) then
    raise exception using
      errcode = '42501',
      message = 'Completed or invalidated session history cannot be rewritten';
  end if;

  if not transitioning then
    raise exception using
      errcode = '42501',
      message = 'Session transitions require start_session or end_session';
  end if;

  return new;
end;
$$;

comment on function public.enforce_session_immutability() is
  'BEFORE INSERT OR UPDATE OR DELETE: identity cannot be retargeted. COMPLETED/INVALIDATED history cannot be rewritten. Ordinary clients cannot mutate rows. Not executable by PUBLIC, anon or authenticated.';

revoke all on function public.enforce_session_immutability()
  from public, anon, authenticated;

create trigger sessions_immutability
before insert or update or delete on public.sessions
for each row execute function public.enforce_session_immutability();

create function public.enforce_session_event_append_only()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if TG_OP = 'DELETE' then
    raise exception using
      errcode = '42501',
      message = 'Session events cannot be deleted';
  end if;

  if TG_OP = 'UPDATE' then
    raise exception using
      errcode = '42501',
      message = 'Session events cannot be rewritten';
  end if;

  if current_setting('app.session_transition', true) is distinct from '1' then
    raise exception using
      errcode = '42501',
      message = 'Session events can only be appended by session RPCs';
  end if;

  return new;
end;
$$;

comment on function public.enforce_session_event_append_only() is
  'BEFORE INSERT OR UPDATE OR DELETE: events are append-only through session RPCs. Not executable by PUBLIC, anon or authenticated.';

revoke all on function public.enforce_session_event_append_only()
  from public, anon, authenticated;

create trigger session_events_append_only
before insert or update or delete on public.session_events
for each row execute function public.enforce_session_event_append_only();

create function public.enforce_session_evidence_immutability()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if TG_OP = 'DELETE' then
    raise exception using
      errcode = '42501',
      message = 'Session evidence cannot be deleted';
  end if;

  if TG_OP = 'UPDATE' then
    raise exception using
      errcode = '42501',
      message = 'Session evidence cannot be rewritten';
  end if;

  if current_setting('app.session_transition', true) is distinct from '1' then
    raise exception using
      errcode = '42501',
      message = 'Session evidence can only be attached by attach_session_evidence';
  end if;

  return new;
end;
$$;

comment on function public.enforce_session_evidence_immutability() is
  'BEFORE INSERT OR UPDATE OR DELETE: evidence metadata is append-only and private. Historical rows cannot be mutated. Not executable by PUBLIC, anon or authenticated.';

revoke all on function public.enforce_session_evidence_immutability()
  from public, anon, authenticated;

create trigger session_evidence_immutability
before insert or update or delete on public.session_evidence
for each row execute function public.enforce_session_evidence_immutability();

create function public.enforce_session_permit_rules()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if TG_OP = 'DELETE' then
    raise exception using
      errcode = '42501',
      message = 'Session permits cannot be deleted';
  end if;

  if TG_OP = 'UPDATE' then
    if new.booking_id is distinct from old.booking_id
       or new.participant_person_id is distinct from old.participant_person_id
       or new.equine_id is distinct from old.equine_id
       or new.center_id is distinct from old.center_id
       or new.valid_from is distinct from old.valid_from
       or new.valid_until is distinct from old.valid_until
       or new.issued_at is distinct from old.issued_at
       or new.issued_by_account_id is distinct from old.issued_by_account_id then
      raise exception using
        errcode = '42501',
        message = 'Session permit identity cannot be rewritten';
    end if;

    if old.used_at is not null
       and new.used_at is distinct from old.used_at then
      raise exception using
        errcode = '42501',
        message = 'A used session permit cannot be reused';
    end if;

    if current_setting('app.session_transition', true) is distinct from '1' then
      raise exception using
        errcode = '42501',
        message = 'Session permits can only be consumed by start_session';
    end if;

    return new;
  end if;

  if current_setting('app.session_transition', true) is distinct from '1' then
    raise exception using
      errcode = '42501',
      message = 'Session permits can only be issued by issue_session_permit';
  end if;

  return new;
end;
$$;

comment on function public.enforce_session_permit_rules() is
  'BEFORE INSERT OR UPDATE OR DELETE: permits are server-issued and single-use. Not executable by PUBLIC, anon or authenticated.';

revoke all on function public.enforce_session_permit_rules()
  from public, anon, authenticated;

create trigger session_permits_rules
before insert or update or delete on public.session_permits
for each row execute function public.enforce_session_permit_rules();

create function public.resolve_session_caller()
returns table (
  account_id uuid,
  person_id uuid
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  current_auth_user_id uuid := auth.uid();
begin
  if current_auth_user_id is null then
    raise exception using
      errcode = '42501',
      message = 'Authentication required';
  end if;

  select account.id, account.person_id
    into account_id, person_id
    from public.user_accounts as account
   where account.auth_user_id = current_auth_user_id;

  if person_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'Identity could not be resolved';
  end if;

  return next;
end;
$$;

comment on function public.resolve_session_caller() is
  'Resolves the authenticated ACCOUNT and PERSON from auth.uid(). Not executable by PUBLIC, anon or authenticated.';

revoke all on function public.resolve_session_caller()
  from public, anon, authenticated;

create function public.caller_can_operate_session(
  p_participant_person_id uuid,
  p_booked_by_account_id uuid,
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
  caller_account uuid;
  caller_person uuid;
begin
  select caller.account_id, caller.person_id
    into caller_account, caller_person
    from public.resolve_session_caller() as caller;

  if caller_person is not distinct from p_participant_person_id then
    return true;
  end if;

  if caller_account is not distinct from p_booked_by_account_id then
    return true;
  end if;

  return public.caller_has_booking_manage_authority(
    caller_person,
    p_equine_id,
    p_center_id
  );
end;
$$;

comment on function public.caller_can_operate_session(uuid, uuid, uuid, uuid) is
  'True when the caller is the participant ACCOUNT, the booked_by ACCOUNT, or a Center ADMIN/MANAGER with effective MANAGE_BOOKINGS. Unrelated guardians, INSTRUCTOR, ASSESSOR and VIEW_ACTIVITY are not enough. Not executable by PUBLIC, anon or authenticated.';

revoke all on function public.caller_can_operate_session(uuid, uuid, uuid, uuid)
  from public, anon, authenticated;

create function public.append_session_event(
  p_session_id uuid,
  p_event_type text,
  p_occurred_at_device timestamptz,
  p_latitude double precision,
  p_longitude double precision,
  p_device_id text,
  p_offline boolean,
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
  insert into public.session_events (
    session_id,
    event_type,
    occurred_at_device,
    received_at_server,
    latitude,
    longitude,
    device_id,
    offline,
    metadata
  ) values (
    p_session_id,
    p_event_type,
    p_occurred_at_device,
    clock_timestamp(),
    p_latitude,
    p_longitude,
    nullif(btrim(coalesce(p_device_id, '')), ''),
    coalesce(p_offline, false),
    coalesce(p_metadata, '{}'::jsonb)
  ) returning id into created_id;

  return created_id;
end;
$$;

comment on function public.append_session_event(uuid, text, timestamptz, double precision, double precision, text, boolean, jsonb) is
  'Internal append of one session event. received_at_server is clock_timestamp(). Not executable by PUBLIC, anon or authenticated.';

revoke all on function public.append_session_event(uuid, text, timestamptz, double precision, double precision, text, boolean, jsonb)
  from public, anon, authenticated;

create function public.activate_booking_for_session(
  p_booking_id uuid
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  update public.bookings as booking
     set status = 'ACTIVE',
         updated_at = now()
   where booking.id = p_booking_id
     and booking.status = 'CONFIRMED';
end;
$$;

comment on function public.activate_booking_for_session(uuid) is
  'Internal CONFIRMED → ACTIVE booking transition used by start_session. Not executable by PUBLIC, anon or authenticated.';

revoke all on function public.activate_booking_for_session(uuid)
  from public, anon, authenticated;

create function public.complete_booking_for_session(
  p_booking_id uuid
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  update public.bookings as booking
     set status = 'COMPLETED',
         completed_at = now(),
         updated_at = now()
   where booking.id = p_booking_id
     and booking.status = 'ACTIVE';
end;
$$;

comment on function public.complete_booking_for_session(uuid) is
  'Internal ACTIVE → COMPLETED booking transition used by end_session. Not executable by PUBLIC, anon or authenticated.';

revoke all on function public.complete_booking_for_session(uuid)
  from public, anon, authenticated;

create function public.set_session_transition(
  p_enabled boolean
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  perform set_config(
    'app.session_transition',
    case when p_enabled then '1' else '' end,
    true
  );
end;
$$;

comment on function public.set_session_transition(boolean) is
  'Internal transaction-local GUC for session table triggers. Callers must clear it before returning. Not executable by PUBLIC, anon or authenticated.';

revoke all on function public.set_session_transition(boolean)
  from public, anon, authenticated;

create function public.issue_session_permit(
  p_booking_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller_account uuid;
  booking_row public.bookings%rowtype;
  session_row public.sessions%rowtype;
  permit_row public.session_permits%rowtype;
  created_session_id uuid;
  created_permit_id uuid;
begin
  select caller.account_id
    into caller_account
    from public.resolve_session_caller() as caller;

  if p_booking_id is null then
    raise exception using
      errcode = '22023',
      message = 'Booking id is required';
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

  if booking_row.status is distinct from 'CONFIRMED'
     and booking_row.status is distinct from 'ACTIVE' then
    raise exception using
      errcode = '23514',
      message = 'A session permit requires a CONFIRMED booking';
  end if;

  if not public.caller_can_operate_session(
    booking_row.participant_person_id,
    booking_row.booked_by_account_id,
    booking_row.equine_id,
    booking_row.center_id
  ) then
    raise exception using
      errcode = '42501',
      message = 'Not authorized to issue a session permit for this booking';
  end if;

  select *
    into session_row
    from public.sessions as session
   where session.booking_id = booking_row.id;

  if session_row.status in ('ACTIVE', 'ENDING', 'COMPLETED', 'INVALIDATED') then
    raise exception using
      errcode = '23514',
      message = 'A session permit cannot be issued after the session has started';
  end if;

  select *
    into permit_row
    from public.session_permits as permit
   where permit.booking_id = booking_row.id;

  if permit_row.used_at is not null then
    raise exception using
      errcode = '23505',
      message = 'This booking already has a used session permit';
  end if;

  perform public.set_session_transition(true);

  begin
    if session_row.id is null then
      insert into public.sessions (
        booking_id,
        equine_id,
        participant_person_id,
        center_id,
        status
      ) values (
        booking_row.id,
        booking_row.equine_id,
        booking_row.participant_person_id,
        booking_row.center_id,
        'READY'
      ) returning id into created_session_id;
    else
      created_session_id := session_row.id;
    end if;

    if permit_row.id is not null then
      created_permit_id := permit_row.id;
    else
      insert into public.session_permits (
        booking_id,
        participant_person_id,
        equine_id,
        center_id,
        valid_from,
        valid_until,
        issued_by_account_id
      ) values (
        booking_row.id,
        booking_row.participant_person_id,
        booking_row.equine_id,
        booking_row.center_id,
        booking_row.starts_at,
        booking_row.ends_at,
        caller_account
      ) returning id into created_permit_id;

      perform public.append_session_event(
        created_session_id,
        'CHECK_IN',
        null,
        null,
        null,
        null,
        false,
        jsonb_build_object('permit_id', created_permit_id)
      );
    end if;

    perform public.set_session_transition(false);
  exception
    when others then
      perform public.set_session_transition(false);
      raise;
  end;

  return created_permit_id;
end;
$$;

comment on function public.issue_session_permit(uuid) is
  'Authenticated server-issued permit for a CONFIRMED booking. Bound to participant, equine and the booking window. Replay of an unused permit is idempotent. Not a client-signed authorization.';

revoke all on function public.issue_session_permit(uuid)
  from public, anon, authenticated;
grant execute on function public.issue_session_permit(uuid)
  to authenticated;

create function public.start_session(
  p_booking_id uuid,
  p_started_offline boolean default false,
  p_permit_id uuid default null,
  p_latitude double precision default null,
  p_longitude double precision default null,
  p_device_id text default null,
  p_occurred_at_device timestamptz default null
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  booking_row public.bookings%rowtype;
  session_row public.sessions%rowtype;
  permit_row public.session_permits%rowtype;
  created_session_id uuid;
  official_start timestamptz := clock_timestamp();
  offline_start boolean := coalesce(p_started_offline, false);
begin
  perform public.resolve_session_caller();

  if p_booking_id is null then
    raise exception using
      errcode = '22023',
      message = 'Booking id is required';
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

  if booking_row.status not in ('CONFIRMED', 'ACTIVE') then
    raise exception using
      errcode = '23514',
      message = 'A session can start only from a CONFIRMED booking';
  end if;

  if not public.caller_can_operate_session(
    booking_row.participant_person_id,
    booking_row.booked_by_account_id,
    booking_row.equine_id,
    booking_row.center_id
  ) then
    raise exception using
      errcode = '42501',
      message = 'Not authorized to start this session';
  end if;

  select *
    into session_row
    from public.sessions as session
   where session.booking_id = booking_row.id
   for update;

  if session_row.status = 'ACTIVE' then
    return session_row.id;
  end if;

  if session_row.status in ('ENDING', 'COMPLETED', 'INVALIDATED', 'REQUIRES_REVIEW') then
    raise exception using
      errcode = '23514',
      message = 'This booking already has a session that cannot be started again';
  end if;

  if offline_start then
    if p_permit_id is null then
      raise exception using
        errcode = '42501',
        message = 'Offline start requires a server-issued session permit';
    end if;

    select *
      into permit_row
      from public.session_permits as permit
     where permit.id = p_permit_id
     for update;

    if permit_row.id is null
       or permit_row.booking_id is distinct from booking_row.id
       or permit_row.participant_person_id is distinct from booking_row.participant_person_id
       or permit_row.equine_id is distinct from booking_row.equine_id
       or permit_row.center_id is distinct from booking_row.center_id then
      raise exception using
        errcode = '42501',
        message = 'Offline start permit does not match this booking';
    end if;

    if permit_row.used_at is not null then
      raise exception using
        errcode = '23505',
        message = 'Session permit already used';
    end if;

    if official_start < permit_row.valid_from
       or official_start > permit_row.valid_until then
      raise exception using
        errcode = '23514',
        message = 'Session permit is outside its booking window';
    end if;
  elsif p_permit_id is not null then
    raise exception using
      errcode = '22023',
      message = 'A permit is only accepted for an offline start';
  end if;

  perform public.set_session_transition(true);

  begin
    if session_row.id is null then
      insert into public.sessions (
        booking_id,
        equine_id,
        participant_person_id,
        center_id,
        status,
        started_at,
        start_latitude,
        start_longitude,
        started_offline
      ) values (
        booking_row.id,
        booking_row.equine_id,
        booking_row.participant_person_id,
        booking_row.center_id,
        'ACTIVE',
        official_start,
        p_latitude,
        p_longitude,
        offline_start
      ) returning id into created_session_id;
    else
      update public.sessions as session
         set status = 'ACTIVE',
             started_at = official_start,
             start_latitude = p_latitude,
             start_longitude = p_longitude,
             started_offline = offline_start,
             updated_at = official_start
       where session.id = session_row.id
       returning session.id into created_session_id;
    end if;

    if offline_start then
      update public.session_permits as permit
         set used_at = official_start
       where permit.id = permit_row.id;
    end if;

    perform public.activate_booking_for_session(booking_row.id);

    perform public.append_session_event(
      created_session_id,
      'START',
      p_occurred_at_device,
      p_latitude,
      p_longitude,
      p_device_id,
      offline_start,
      '{}'::jsonb
    );

    perform public.set_session_transition(false);
  exception
    when others then
      perform public.set_session_transition(false);
      raise;
  end;

  return created_session_id;
end;
$$;

comment on function public.start_session(uuid, boolean, uuid, double precision, double precision, text, timestamptz) is
  'Authenticated session start. Official started_at is clock_timestamp(). Replay of an ACTIVE session is idempotent. Offline start requires a matching unused server-issued permit. Concurrent starts serialize on the booking row.';

revoke all on function public.start_session(uuid, boolean, uuid, double precision, double precision, text, timestamptz)
  from public, anon, authenticated;
grant execute on function public.start_session(uuid, boolean, uuid, double precision, double precision, text, timestamptz)
  to authenticated;

create function public.end_session(
  p_session_id uuid,
  p_ended_offline boolean default false,
  p_latitude double precision default null,
  p_longitude double precision default null,
  p_device_id text default null,
  p_occurred_at_device timestamptz default null
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  session_row public.sessions%rowtype;
  booking_row public.bookings%rowtype;
  official_end timestamptz := clock_timestamp();
  offline_end boolean := coalesce(p_ended_offline, false);
begin
  perform public.resolve_session_caller();

  if p_session_id is null then
    raise exception using
      errcode = '22023',
      message = 'Session id is required';
  end if;

  select *
    into session_row
    from public.sessions as session
   where session.id = p_session_id
   for update;

  if session_row.id is null then
    raise exception using
      errcode = 'P0002',
      message = 'Session not found';
  end if;

  select *
    into booking_row
    from public.bookings as booking
   where booking.id = session_row.booking_id
   for update;

  if not public.caller_can_operate_session(
    booking_row.participant_person_id,
    booking_row.booked_by_account_id,
    booking_row.equine_id,
    booking_row.center_id
  ) then
    raise exception using
      errcode = '42501',
      message = 'Not authorized to end this session';
  end if;

  if session_row.status = 'COMPLETED' then
    return session_row.id;
  end if;

  if session_row.status not in ('ACTIVE', 'ENDING', 'PENDING_SYNC', 'REQUIRES_REVIEW') then
    raise exception using
      errcode = '23514',
      message = 'Session cannot be ended before it has started';
  end if;

  if session_row.started_at is null
     or official_end <= session_row.started_at then
    raise exception using
      errcode = '23514',
      message = 'Session end must be after the official start';
  end if;

  perform public.set_session_transition(true);

  begin
    update public.sessions as session
       set status = 'COMPLETED',
           ended_at = official_end,
           end_latitude = p_latitude,
           end_longitude = p_longitude,
           ended_offline = offline_end,
           updated_at = official_end
     where session.id = session_row.id;

    perform public.append_session_event(
      session_row.id,
      'END_REQUESTED',
      p_occurred_at_device,
      p_latitude,
      p_longitude,
      p_device_id,
      offline_end,
      '{}'::jsonb
    );

    perform public.append_session_event(
      session_row.id,
      'CHECK_OUT',
      p_occurred_at_device,
      p_latitude,
      p_longitude,
      p_device_id,
      offline_end,
      '{}'::jsonb
    );

    perform public.complete_booking_for_session(booking_row.id);

    perform public.set_session_transition(false);
  exception
    when others then
      perform public.set_session_transition(false);
      raise;
  end;

  return session_row.id;
end;
$$;

comment on function public.end_session(uuid, boolean, double precision, double precision, text, timestamptz) is
  'Authenticated session end. Official ended_at is clock_timestamp() and must be after started_at. Replay of a COMPLETED session is idempotent. Client/device time is stored on events only.';

revoke all on function public.end_session(uuid, boolean, double precision, double precision, text, timestamptz)
  from public, anon, authenticated;
grant execute on function public.end_session(uuid, boolean, double precision, double precision, text, timestamptz)
  to authenticated;

create function public.attach_session_evidence(
  p_session_id uuid,
  p_evidence_type text,
  p_storage_path text,
  p_captured_at_device timestamptz default null,
  p_latitude double precision default null,
  p_longitude double precision default null
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  session_row public.sessions%rowtype;
  booking_row public.bookings%rowtype;
  created_id uuid;
  event_type text;
begin
  perform public.resolve_session_caller();

  if p_session_id is null
     or p_evidence_type is null
     or p_storage_path is null
     or length(btrim(p_storage_path)) = 0 then
    raise exception using
      errcode = '22023',
      message = 'Session evidence requires a session, type and storage path';
  end if;

  select *
    into session_row
    from public.sessions as session
   where session.id = p_session_id
   for update;

  if session_row.id is null then
    raise exception using
      errcode = 'P0002',
      message = 'Session not found';
  end if;

  if session_row.status in ('COMPLETED', 'INVALIDATED', 'READY') then
    raise exception using
      errcode = '42501',
      message = 'Historical session evidence cannot be attached after completion';
  end if;

  select *
    into booking_row
    from public.bookings as booking
   where booking.id = session_row.booking_id;

  if not public.caller_can_operate_session(
    booking_row.participant_person_id,
    booking_row.booked_by_account_id,
    booking_row.equine_id,
    booking_row.center_id
  ) then
    raise exception using
      errcode = '42501',
      message = 'Not authorized to attach evidence to this session';
  end if;

  event_type := case p_evidence_type
    when 'START_PHOTO' then 'PHOTO_START'
    when 'END_PHOTO' then 'PHOTO_END'
    else null
  end;

  perform public.set_session_transition(true);

  begin
    insert into public.session_evidence (
      session_id,
      evidence_type,
      storage_path,
      captured_at_device,
      received_at_server,
      latitude,
      longitude
    ) values (
      session_row.id,
      p_evidence_type,
      btrim(p_storage_path),
      p_captured_at_device,
      clock_timestamp(),
      p_latitude,
      p_longitude
    ) returning id into created_id;

    if event_type is not null then
      perform public.append_session_event(
        session_row.id,
        event_type,
        p_captured_at_device,
        p_latitude,
        p_longitude,
        null,
        session_row.started_offline,
        jsonb_build_object('evidence_id', created_id)
      );
    end if;

    perform public.set_session_transition(false);
  exception
    when others then
      perform public.set_session_transition(false);
      raise;
  end;

  return created_id;
end;
$$;

comment on function public.attach_session_evidence(uuid, text, text, timestamptz, double precision, double precision) is
  'Authenticated private evidence metadata attach. Does not upload bytes or create a Storage bucket. Completed/invalidated evidence cannot be added or rewritten.';

revoke all on function public.attach_session_evidence(uuid, text, text, timestamptz, double precision, double precision)
  from public, anon, authenticated;
grant execute on function public.attach_session_evidence(uuid, text, text, timestamptz, double precision, double precision)
  to authenticated;

alter table public.sessions enable row level security;
alter table public.session_events enable row level security;
alter table public.session_evidence enable row level security;
alter table public.session_permits enable row level security;

revoke all on table public.sessions from anon, authenticated;
revoke all on table public.session_events from anon, authenticated;
revoke all on table public.session_evidence from anon, authenticated;
revoke all on table public.session_permits from anon, authenticated;
