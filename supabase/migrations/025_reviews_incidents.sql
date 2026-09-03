-- Phase 13A: reviews and incidents foundation.
--
-- Adds public.reviews and public.incidents plus submit_review() and
-- report_incident(). Does not edit migrations 001–024. Does not create
-- Storage buckets, audit_events, moderation workflow, star aggregation,
-- compensation, penalties, insurance conclusions or legal classifications.
--
-- Architecture 2.1 Frozen:
--   reviews.rating CHECK 1..5;
--   reviewer is PERSON; booker remains ACCOUNT;
--   review content (comment/rating) is public-classified data;
--   incident/safety rows are private.
-- Architecture 2.1 does not freeze review status, subject_type,
-- incident_type, severity or incident status catalogs. Those columns
-- are stored without invented CHECK vocabularies.
--
-- A review requires a COMPLETED booking. Subject id must be the
-- booking's center, equine or participant. Replay of the same reviewer
-- + booking + subject is idempotent.
--
-- An incident requires a started session. Session, booking, equine and
-- center must match. Multiple incidents per session are allowed.
--
-- now() is not used in a table CHECK.
--
-- Access model follows migrations 006–024:
--   - RLS enabled, deny-by-default, no client table policies.
--   - No table INSERT/UPDATE/DELETE/SELECT for anon or authenticated.
--   - Public RPCs are executable by authenticated only.
--   - Internal helpers stay revoked from PUBLIC, anon and authenticated.

create table public.reviews (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.bookings (id),
  reviewer_person_id uuid not null references public.persons (id),
  subject_type text,
  subject_id uuid not null,
  rating smallint not null,
  comment text,
  status text,
  created_at timestamptz not null default now(),
  constraint reviews_rating_check check (rating >= 1 and rating <= 5),
  constraint reviews_booking_reviewer_subject_key
    unique (booking_id, reviewer_person_id, subject_id)
);

create index reviews_booking_id_idx on public.reviews (booking_id);
create index reviews_reviewer_person_id_idx on public.reviews (reviewer_person_id);
create index reviews_subject_id_idx on public.reviews (subject_id);

comment on table public.reviews is
  'Public-classified review of a COMPLETED booking subject. Rating is frozen 1..5. Not moderation, aggregation, compensation or a public SELECT feed.';
comment on column public.reviews.reviewer_person_id is
  'Reviewer PERSON copied from the caller identity. Never an Auth UUID and never a user_accounts.id.';
comment on column public.reviews.subject_id is
  'Must be the booking center, equine or participant. Cross-context subjects are rejected.';
comment on column public.reviews.subject_type is
  'Optional label. Vocabulary is not frozen in Architecture 2.1; no CHECK catalog is invented.';
comment on column public.reviews.rating is
  'Frozen Architecture 2.1 CHECK 1..5.';
comment on column public.reviews.status is
  'Optional label. Vocabulary is not frozen; no moderation workflow is invented.';
comment on column public.reviews.comment is
  'Public-classified review text. Not incident evidence and not a Storage path.';

create table public.incidents (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.bookings (id),
  session_id uuid not null references public.sessions (id),
  equine_id uuid not null references public.equines (id),
  reported_by_person_id uuid not null references public.persons (id),
  center_id uuid not null references public.equestrian_centers (id),
  incident_type text,
  severity text,
  description text,
  status text,
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  constraint incidents_resolved_range_check
    check (resolved_at is null or resolved_at >= created_at)
);

create index incidents_booking_id_idx on public.incidents (booking_id);
create index incidents_session_id_idx on public.incidents (session_id);
create index incidents_equine_id_idx on public.incidents (equine_id);
create index incidents_center_id_idx on public.incidents (center_id);

comment on table public.incidents is
  'Private safety incident linked to a started session. Not a review, diagnosis, insurance conclusion or public evidence blob.';
comment on column public.incidents.reported_by_person_id is
  'Reporter PERSON copied from the caller identity. Never a caller-supplied actor id.';
comment on column public.incidents.incident_type is
  'Optional label. Vocabulary is not frozen in Architecture 2.1; no CHECK catalog is invented.';
comment on column public.incidents.severity is
  'Optional label. Vocabulary is not frozen; no legal classification is invented.';
comment on column public.incidents.status is
  'Optional label. Vocabulary is not frozen; no resolution workflow is invented.';
comment on column public.incidents.resolved_at is
  'Optional timestamp. 025 does not add a resolve RPC or status catalog.';
comment on column public.incidents.description is
  'Private incident text. Not review comment and not a Storage path.';

create function public.set_review_write(p_enabled boolean)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  perform set_config(
    'app.review_write',
    case when p_enabled then '1' else '' end,
    true
  );
end;
$$;

comment on function public.set_review_write(boolean) is
  'Internal transaction-local GUC for reviews triggers. Callers must clear it before returning. Not executable by PUBLIC, anon or authenticated.';

revoke all on function public.set_review_write(boolean)
  from public, anon, authenticated;

create function public.set_incident_write(p_enabled boolean)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  perform set_config(
    'app.incident_write',
    case when p_enabled then '1' else '' end,
    true
  );
end;
$$;

comment on function public.set_incident_write(boolean) is
  'Internal transaction-local GUC for incidents triggers. Callers must clear it before returning. Not executable by PUBLIC, anon or authenticated.';

revoke all on function public.set_incident_write(boolean)
  from public, anon, authenticated;

create function public.enforce_review_immutability()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if TG_OP = 'DELETE' then
    raise exception using
      errcode = '42501',
      message = 'Review history cannot be deleted';
  end if;

  if TG_OP = 'UPDATE' then
    raise exception using
      errcode = '42501',
      message = 'Reviews cannot be rewritten';
  end if;

  if current_setting('app.review_write', true) is distinct from '1' then
    raise exception using
      errcode = '42501',
      message = 'Reviews can only be created by submit_review';
  end if;

  return new;
end;
$$;

comment on function public.enforce_review_immutability() is
  'BEFORE INSERT OR UPDATE OR DELETE: reviews are append-only through submit_review. Not executable by PUBLIC, anon or authenticated.';

revoke all on function public.enforce_review_immutability()
  from public, anon, authenticated;

create trigger reviews_immutability
before insert or update or delete on public.reviews
for each row execute function public.enforce_review_immutability();

create function public.enforce_incident_immutability()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if TG_OP = 'DELETE' then
    raise exception using
      errcode = '42501',
      message = 'Incident history cannot be deleted';
  end if;

  if TG_OP = 'UPDATE' then
    raise exception using
      errcode = '42501',
      message = 'Incidents cannot be rewritten';
  end if;

  if current_setting('app.incident_write', true) is distinct from '1' then
    raise exception using
      errcode = '42501',
      message = 'Incidents can only be created by report_incident';
  end if;

  return new;
end;
$$;

comment on function public.enforce_incident_immutability() is
  'BEFORE INSERT OR UPDATE OR DELETE: incidents are append-only through report_incident. Private safety rows cannot be mutated. Not executable by PUBLIC, anon or authenticated.';

revoke all on function public.enforce_incident_immutability()
  from public, anon, authenticated;

create trigger incidents_immutability
before insert or update or delete on public.incidents
for each row execute function public.enforce_incident_immutability();

create function public.caller_can_submit_review(
  p_participant_person_id uuid,
  p_booked_by_account_id uuid
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

  return false;
end;
$$;

comment on function public.caller_can_submit_review(uuid, uuid) is
  'True when the caller is the booking participant PERSON or the booked_by ACCOUNT. Center staff, INSTRUCTOR and unrelated persons are not enough. Not executable by PUBLIC, anon or authenticated.';

revoke all on function public.caller_can_submit_review(uuid, uuid)
  from public, anon, authenticated;

create function public.submit_review(
  p_booking_id uuid,
  p_subject_id uuid,
  p_rating smallint,
  p_comment text default null,
  p_subject_type text default null
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller_person uuid;
  booking_row public.bookings%rowtype;
  existing_id uuid;
  created_id uuid;
begin
  select caller.person_id
    into caller_person
    from public.resolve_session_caller() as caller;

  if p_booking_id is null or p_subject_id is null or p_rating is null then
    raise exception using
      errcode = '22023',
      message = 'Review requires a booking, subject and rating';
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

  if booking_row.status is distinct from 'COMPLETED' then
    raise exception using
      errcode = '23514',
      message = 'A review requires a COMPLETED booking';
  end if;

  if not public.caller_can_submit_review(
    booking_row.participant_person_id,
    booking_row.booked_by_account_id
  ) then
    raise exception using
      errcode = '42501',
      message = 'Not authorized to review this booking';
  end if;

  if p_subject_id is distinct from booking_row.center_id
     and p_subject_id is distinct from booking_row.equine_id
     and p_subject_id is distinct from booking_row.participant_person_id then
    raise exception using
      errcode = '23514',
      message = 'Review subject is not part of this booking';
  end if;

  select review.id
    into existing_id
    from public.reviews as review
   where review.booking_id = booking_row.id
     and review.reviewer_person_id = caller_person
     and review.subject_id = p_subject_id;

  if existing_id is not null then
    return existing_id;
  end if;

  perform public.set_review_write(true);

  begin
    insert into public.reviews (
      booking_id,
      reviewer_person_id,
      subject_type,
      subject_id,
      rating,
      comment
    ) values (
      booking_row.id,
      caller_person,
      nullif(btrim(coalesce(p_subject_type, '')), ''),
      p_subject_id,
      p_rating,
      p_comment
    ) returning id into created_id;

    perform public.set_review_write(false);
  exception
    when others then
      perform public.set_review_write(false);
      raise;
  end;

  return created_id;
end;
$$;

comment on function public.submit_review(uuid, uuid, smallint, text, text) is
  'Authenticated review of a COMPLETED booking subject. Rating is 1..5. Reviewer is the caller PERSON. Replay of the same reviewer, booking and subject is idempotent.';

revoke all on function public.submit_review(uuid, uuid, smallint, text, text)
  from public, anon, authenticated;
grant execute on function public.submit_review(uuid, uuid, smallint, text, text)
  to authenticated;

create function public.report_incident(
  p_booking_id uuid,
  p_session_id uuid,
  p_description text,
  p_equine_id uuid default null,
  p_center_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller_person uuid;
  session_row public.sessions%rowtype;
  booking_row public.bookings%rowtype;
  created_id uuid;
begin
  select caller.person_id
    into caller_person
    from public.resolve_session_caller() as caller;

  if p_booking_id is null or p_session_id is null then
    raise exception using
      errcode = '22023',
      message = 'Incident requires a booking and session';
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
   where booking.id = p_booking_id
   for update;

  if booking_row.id is null then
    raise exception using
      errcode = 'P0002',
      message = 'Booking not found';
  end if;

  if session_row.booking_id is distinct from booking_row.id then
    raise exception using
      errcode = '23514',
      message = 'Incident session does not match the booking';
  end if;

  if session_row.status in ('READY', 'INVALIDATED')
     or session_row.started_at is null then
    raise exception using
      errcode = '23514',
      message = 'An incident requires a started session';
  end if;

  if not public.caller_can_operate_session(
    booking_row.participant_person_id,
    booking_row.booked_by_account_id,
    booking_row.equine_id,
    booking_row.center_id
  ) then
    raise exception using
      errcode = '42501',
      message = 'Not authorized to report an incident for this session';
  end if;

  if p_equine_id is not null
     and p_equine_id is distinct from session_row.equine_id then
    raise exception using
      errcode = '23514',
      message = 'Incident equine does not match the session';
  end if;

  if p_center_id is not null
     and p_center_id is distinct from session_row.center_id then
    raise exception using
      errcode = '23514',
      message = 'Incident center does not match the session';
  end if;

  perform public.set_incident_write(true);

  begin
    insert into public.incidents (
      booking_id,
      session_id,
      equine_id,
      reported_by_person_id,
      center_id,
      description
    ) values (
      booking_row.id,
      session_row.id,
      session_row.equine_id,
      caller_person,
      session_row.center_id,
      p_description
    ) returning id into created_id;

    perform public.set_incident_write(false);
  exception
    when others then
      perform public.set_incident_write(false);
      raise;
  end;

  return created_id;
end;
$$;

comment on function public.report_incident(uuid, uuid, text, uuid, uuid) is
  'Authenticated private incident for a started session. Context is copied from the session. Optional equine/center ids are accepted only when they match. Not a review and not a Storage upload.';

revoke all on function public.report_incident(uuid, uuid, text, uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.report_incident(uuid, uuid, text, uuid, uuid)
  to authenticated;

alter table public.reviews enable row level security;
alter table public.incidents enable row level security;

revoke all on table public.reviews from anon, authenticated;
revoke all on table public.incidents from anon, authenticated;
