-- Phase 12B: session-linked equine activity foundation.
--
-- Adds public.equine_activities and record_equine_activity(). Does not
-- edit migrations 001–023. Does not create Storage buckets, reviews,
-- incidents or audit_events. Does not add diagnoses, billing, scores or
-- public activity visibility.
--
-- Architecture 2.1 lists equine_activities columns but does not freeze
-- activity_type, status or source catalogs. Those columns are stored
-- without invented CHECK vocabularies.
--
-- Official starts_at / ends_at are copied from the linked session
-- (already server-authoritative). Cross-context booking/equine/center
-- ids are rejected. One activity row per session. Replay is idempotent.
-- Completed activity (ends_at present) cannot be rewritten.
--
-- now() is not used in a table CHECK.
--
-- Access model follows migrations 006–023:
--   - RLS enabled, deny-by-default, no client table policies.
--   - No table INSERT/UPDATE/DELETE/SELECT for anon or authenticated.
--   - Public RPCs are executable by authenticated only.
--   - Internal helpers stay revoked from PUBLIC, anon and authenticated.

create table public.equine_activities (
  id uuid primary key default gen_random_uuid(),
  equine_id uuid not null references public.equines (id),
  center_id uuid not null references public.equestrian_centers (id),
  activity_type text,
  booking_id uuid not null references public.bookings (id),
  session_id uuid not null references public.sessions (id),
  starts_at timestamptz not null,
  ends_at timestamptz,
  status text,
  source text,
  created_by_account_id uuid not null references public.user_accounts (id),
  created_at timestamptz not null default now(),
  constraint equine_activities_session_id_key unique (session_id),
  constraint equine_activities_range_check
    check (
      ends_at is null
      or ends_at > starts_at
    )
);

create index equine_activities_equine_id_idx
  on public.equine_activities (equine_id);

create index equine_activities_center_id_idx
  on public.equine_activities (center_id);

create index equine_activities_booking_id_idx
  on public.equine_activities (booking_id);

comment on table public.equine_activities is
  'Session-linked equine activity history. Context is copied from the canonical session/booking/equine. Not a diagnosis, invoice, score or public feed.';
comment on column public.equine_activities.session_id is
  'One activity row per session. Architecture 2.1 session link.';
comment on column public.equine_activities.booking_id is
  'Copied from the session booking. Cross-context booking ids are rejected.';
comment on column public.equine_activities.equine_id is
  'Copied from the session equine. Cross-context equine ids are rejected.';
comment on column public.equine_activities.center_id is
  'Copied from the session center. Cross-context center ids are rejected.';
comment on column public.equine_activities.starts_at is
  'Copied from the session official started_at. Not client/device time.';
comment on column public.equine_activities.ends_at is
  'Copied from the session official ended_at when the session has ended. Must be after starts_at.';
comment on column public.equine_activities.activity_type is
  'Optional label. Vocabulary is not frozen in Architecture 2.1; no CHECK catalog is invented.';
comment on column public.equine_activities.status is
  'Optional label. Vocabulary is not frozen in Architecture 2.1; no CHECK catalog is invented.';
comment on column public.equine_activities.source is
  'Optional provenance label. Vocabulary is not frozen in Architecture 2.1; no CHECK catalog is invented.';
comment on column public.equine_activities.created_by_account_id is
  'Authenticated ACCOUNT that recorded the activity. Never a caller-supplied actor id.';

create function public.set_activity_transition(
  p_enabled boolean
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  perform set_config(
    'app.activity_transition',
    case when p_enabled then '1' else '' end,
    true
  );
end;
$$;

comment on function public.set_activity_transition(boolean) is
  'Internal transaction-local GUC for equine_activities triggers. Callers must clear it before returning. Not executable by PUBLIC, anon or authenticated.';

revoke all on function public.set_activity_transition(boolean)
  from public, anon, authenticated;

create function public.enforce_equine_activity_immutability()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  transitioning boolean := current_setting('app.activity_transition', true) = '1';
begin
  if TG_OP = 'DELETE' then
    raise exception using
      errcode = '42501',
      message = 'Equine activity history cannot be deleted';
  end if;

  if TG_OP = 'INSERT' then
    if not transitioning then
      raise exception using
        errcode = '42501',
        message = 'Equine activity can only be created by record_equine_activity';
    end if;
    return new;
  end if;

  if new.session_id is distinct from old.session_id
     or new.booking_id is distinct from old.booking_id
     or new.equine_id is distinct from old.equine_id
     or new.center_id is distinct from old.center_id
     or new.created_by_account_id is distinct from old.created_by_account_id
     or new.created_at is distinct from old.created_at
     or new.starts_at is distinct from old.starts_at then
    raise exception using
      errcode = '42501',
      message = 'Equine activity identity cannot be retargeted';
  end if;

  if old.ends_at is not null then
    raise exception using
      errcode = '42501',
      message = 'Completed equine activity cannot be rewritten';
  end if;

  if not transitioning then
    raise exception using
      errcode = '42501',
      message = 'Equine activity can only be mutated by record_equine_activity';
  end if;

  return new;
end;
$$;

comment on function public.enforce_equine_activity_immutability() is
  'BEFORE INSERT OR UPDATE OR DELETE: activity is append-only through record_equine_activity. Completed rows cannot be rewritten. Not executable by PUBLIC, anon or authenticated.';

revoke all on function public.enforce_equine_activity_immutability()
  from public, anon, authenticated;

create trigger equine_activities_immutability
before insert or update or delete on public.equine_activities
for each row execute function public.enforce_equine_activity_immutability();

create function public.record_equine_activity(
  p_session_id uuid,
  p_booking_id uuid default null,
  p_equine_id uuid default null,
  p_center_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller_account uuid;
  session_row public.sessions%rowtype;
  booking_row public.bookings%rowtype;
  activity_row public.equine_activities%rowtype;
  created_id uuid;
begin
  select caller.account_id
    into caller_account
    from public.resolve_session_caller() as caller;

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
      message = 'Not authorized to record equine activity for this session';
  end if;

  if session_row.status in ('READY', 'INVALIDATED')
     or session_row.started_at is null then
    raise exception using
      errcode = '23514',
      message = 'Equine activity requires a started session';
  end if;

  if p_booking_id is not null
     and p_booking_id is distinct from session_row.booking_id then
    raise exception using
      errcode = '23514',
      message = 'Activity booking does not match the session';
  end if;

  if p_equine_id is not null
     and p_equine_id is distinct from session_row.equine_id then
    raise exception using
      errcode = '23514',
      message = 'Activity equine does not match the session';
  end if;

  if p_center_id is not null
     and p_center_id is distinct from session_row.center_id then
    raise exception using
      errcode = '23514',
      message = 'Activity center does not match the session';
  end if;

  select *
    into activity_row
    from public.equine_activities as activity
   where activity.session_id = session_row.id
   for update;

  if activity_row.id is not null then
    if session_row.ended_at is not null
       and activity_row.ends_at is null then
      perform public.set_activity_transition(true);
      begin
        update public.equine_activities as activity
           set ends_at = session_row.ended_at
         where activity.id = activity_row.id;
        perform public.set_activity_transition(false);
      exception
        when others then
          perform public.set_activity_transition(false);
          raise;
      end;
    end if;
    return activity_row.id;
  end if;

  perform public.set_activity_transition(true);

  begin
    insert into public.equine_activities (
      equine_id,
      center_id,
      booking_id,
      session_id,
      starts_at,
      ends_at,
      created_by_account_id
    ) values (
      session_row.equine_id,
      session_row.center_id,
      session_row.booking_id,
      session_row.id,
      session_row.started_at,
      session_row.ended_at,
      caller_account
    ) returning id into created_id;

    perform public.set_activity_transition(false);
  exception
    when others then
      perform public.set_activity_transition(false);
      raise;
  end;

  return created_id;
end;
$$;

comment on function public.record_equine_activity(uuid, uuid, uuid, uuid) is
  'Authenticated session-linked equine activity record. Context is copied from the session. Optional booking/equine/center ids are accepted only when they match. Replay is idempotent. Completed activity is not rewritten.';

revoke all on function public.record_equine_activity(uuid, uuid, uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.record_equine_activity(uuid, uuid, uuid, uuid)
  to authenticated;

alter table public.equine_activities enable row level security;

revoke all on table public.equine_activities from anon, authenticated;
