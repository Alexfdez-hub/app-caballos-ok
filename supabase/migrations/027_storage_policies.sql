-- Phase 14A: Storage security foundation.
--
-- Inventory (local + documented remote) before this migration:
--   - No prior migration creates storage.buckets or storage.objects
--     policies. 011/015/023 store path metadata only.
--   - Local supabase/config.toml enables Storage with no named buckets.
--   - docs/REMOTE_DATABASE_INVENTORY.md: remote dump has no Storage
--     objects/policies; the retired client used horse-images. This
--     migration does not delete, rename or rewrite horse-images or any
--     existing object.
--
-- Creates the Architecture 2.1 target buckets as private:
--   avatars, equine-media, qualification-documents,
--   session-evidence, assessment-documents.
--
-- Current Supabase Storage rules (access-control guide): object
-- mutation goes through the Storage API; access is RLS on
-- storage.objects. Public buckets bypass read RLS. Upsert needs
-- SELECT+UPDATE in addition to INSERT. This migration therefore:
--   - keeps every target bucket private (public = false);
--   - adds INSERT/SELECT policies only where authority is frozen;
--   - adds no UPDATE/DELETE policies (upsert, move and delete are
--     not frozen and are denied);
--   - never binds a policy to TO authenticated alone;
--   - never trusts owner, owner_id, metadata or user_metadata;
--   - never uses auth.uid() as a domain path (PERSON != ACCOUNT).
--
-- Frozen-private buckets (Architecture 2.1 §22/§25/§29):
--   session-evidence, qualification-documents, assessment-documents.
-- Path segments are existing domain UUIDs so prefix substitution
-- cannot grant another person's, equine's or center's object:
--   session-evidence/{session_id}/{object}
--   qualification-documents/{rider_person_id}/{qualification_id}/{object}
--   assessment-documents/{rider_person_id}/{assessment_id}/{object}
--
-- Session evidence authority matches attach_session_evidence /
-- caller_can_operate_session: participant PERSON, booked_by ACCOUNT,
-- or Center ADMIN/MANAGER with effective MANAGE_BOOKINGS. Unrelated
-- guardians, INSTRUCTOR, ASSESSOR, VIEW_ACTIVITY and ownership are
-- not enough.
--
-- Qualification documents: rider PERSON who holds the qualification,
-- or a current VERIFIED guardian of that PERSON (a minor may have no
-- account). Not a Center, assessor or owner path.
--
-- Assessment documents: write = the assessment's assessor PERSON with
-- a current ASSESSOR membership at that Center. Read = that assessor
-- path, the rider PERSON, or a current VERIFIED guardian of the rider.
-- Self-assessment remains impossible because the assessment row
-- forbids rider = assessor.
--
-- avatars and equine-media: private buckets, no client policies.
-- Public visibility and writable path ownership are not frozen.
-- See docs/ARCHITECTURE_CONFLICT_027_STORAGE_VISIBILITY.md.
--
-- No signed-URL creator, no global listing RPC, no service_role
-- client path, no direct SQL grant that bypasses Storage RLS.
-- Does not edit migrations 001–026. Does not invent MIME/size limits.

do $$
begin
  if to_regnamespace('storage') is null
     or to_regclass('storage.buckets') is null
     or to_regclass('storage.objects') is null then
    raise exception '027 requires storage.buckets and storage.objects';
  end if;
end;
$$;

insert into storage.buckets (id, name, public)
values
  ('avatars', 'avatars', false),
  ('equine-media', 'equine-media', false),
  ('qualification-documents', 'qualification-documents', false),
  ('session-evidence', 'session-evidence', false),
  ('assessment-documents', 'assessment-documents', false)
on conflict (id) do update
set public = false
where storage.buckets.public is distinct from false;

create function public.storage_object_name_is_safe(p_name text)
returns boolean
language sql
immutable
as $$
  select
    p_name is not null
    and length(btrim(p_name)) > 0
    and p_name = btrim(p_name)
    and position('//' in p_name) = 0
    and p_name not like '/%'
    and p_name not like '%/'
    and p_name not like '%/./%'
    and p_name not like '%/../%'
    and p_name not like '../%'
    and p_name not like './%'
    and p_name not like '%/..'
    and p_name not like '%/.';
$$;

comment on function public.storage_object_name_is_safe(text) is
  'Rejects empty, trimmed-unequal, parent-directory and empty-segment Storage object names. Not executable by PUBLIC, anon or authenticated.';

revoke all on function public.storage_object_name_is_safe(text)
  from public, anon, authenticated;

create function public.storage_path_uuid(p_name text, p_ordinal integer)
returns uuid
language plpgsql
immutable
set search_path = pg_catalog, public
as $$
declare
  segment text;
begin
  if p_ordinal is null or p_ordinal < 1 then
    return null;
  end if;

  if not public.storage_object_name_is_safe(p_name) then
    return null;
  end if;

  segment := split_part(p_name, '/', p_ordinal);
  if segment is null
     or segment = ''
     or segment !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return null;
  end if;

  return segment::uuid;
exception
  when invalid_text_representation then
    return null;
end;
$$;

comment on function public.storage_path_uuid(text, integer) is
  'Exact UUID path segment. Prefix-similar text does not match. Not executable by PUBLIC, anon or authenticated.';

revoke all on function public.storage_path_uuid(text, integer)
  from public, anon, authenticated;

create function public.storage_path_has_leaf(p_name text, p_folder_count integer)
returns boolean
language sql
immutable
set search_path = pg_catalog, public
as $$
  select
    public.storage_object_name_is_safe(p_name)
    and p_folder_count is not null
    and p_folder_count > 0
    and length(p_name) - length(replace(p_name, '/', '')) >= p_folder_count
    and nullif(split_part(p_name, '/', p_folder_count + 1), '') is not null;
$$;

comment on function public.storage_path_has_leaf(text, integer) is
  'True when a non-empty object name follows the required UUID folders. Not executable by PUBLIC, anon or authenticated.';

revoke all on function public.storage_path_has_leaf(text, integer)
  from public, anon, authenticated;

create function public.storage_current_account_id()
returns uuid
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  current_auth_user_id uuid := auth.uid();
  caller_account uuid;
begin
  if current_auth_user_id is null then
    return null;
  end if;

  select account.id
    into caller_account
    from public.user_accounts as account
   where account.auth_user_id = current_auth_user_id;

  return caller_account;
end;
$$;

comment on function public.storage_current_account_id() is
  'Resolves the authenticated ACCOUNT from auth.uid(). Returns null when missing. Not executable by PUBLIC, anon or authenticated.';

revoke all on function public.storage_current_account_id()
  from public, anon, authenticated;

create function public.storage_current_person_id()
returns uuid
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
    return null;
  end if;

  select account.person_id
    into caller_person
    from public.user_accounts as account
   where account.auth_user_id = current_auth_user_id;

  return caller_person;
end;
$$;

comment on function public.storage_current_person_id() is
  'Resolves the authenticated PERSON from auth.uid() via user_accounts. Never uses user_metadata. Not executable by PUBLIC, anon or authenticated.';

revoke all on function public.storage_current_person_id()
  from public, anon, authenticated;

create function public.storage_session_evidence_allowed(p_name text)
returns boolean
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  session_id uuid;
  session_row public.sessions%rowtype;
  booking_row public.bookings%rowtype;
  caller_account uuid;
  caller_person uuid;
begin
  session_id := public.storage_path_uuid(p_name, 1);
  if session_id is null
     or not public.storage_path_has_leaf(p_name, 1) then
    return false;
  end if;

  caller_account := public.storage_current_account_id();
  caller_person := public.storage_current_person_id();
  if caller_person is null then
    return false;
  end if;

  select *
    into session_row
    from public.sessions as session
   where session.id = session_id;

  if session_row.id is null then
    return false;
  end if;

  select *
    into booking_row
    from public.bookings as booking
   where booking.id = session_row.booking_id;

  if booking_row.id is null then
    return false;
  end if;

  if caller_person is not distinct from booking_row.participant_person_id then
    return true;
  end if;

  if caller_account is not distinct from booking_row.booked_by_account_id then
    return true;
  end if;

  return public.caller_has_booking_manage_authority(
    caller_person,
    booking_row.equine_id,
    booking_row.center_id
  );
end;
$$;

comment on function public.storage_session_evidence_allowed(text) is
  'True when the caller may INSERT/SELECT a private session-evidence object under {session_id}/. Same authority as attach_session_evidence. Executable by authenticated for Storage RLS only.';

revoke all on function public.storage_session_evidence_allowed(text)
  from public, anon, authenticated;
grant execute on function public.storage_session_evidence_allowed(text)
  to authenticated;

create function public.storage_qualification_document_allowed(p_name text)
returns boolean
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  rider_person_id uuid;
  qualification_id uuid;
  caller_person uuid;
begin
  rider_person_id := public.storage_path_uuid(p_name, 1);
  qualification_id := public.storage_path_uuid(p_name, 2);
  if rider_person_id is null
     or qualification_id is null
     or not public.storage_path_has_leaf(p_name, 2) then
    return false;
  end if;

  caller_person := public.storage_current_person_id();
  if caller_person is null then
    return false;
  end if;

  if not exists (
    select 1
      from public.rider_qualifications as qualification
     where qualification.id = qualification_id
       and qualification.rider_person_id = rider_person_id
  ) then
    return false;
  end if;

  if caller_person is not distinct from rider_person_id then
    return true;
  end if;

  return public.has_current_verified_guardian_relationship(
    caller_person,
    rider_person_id
  );
end;
$$;

comment on function public.storage_qualification_document_allowed(text) is
  'True when the caller is the qualification rider PERSON or a current VERIFIED guardian. Path is {rider_person_id}/{qualification_id}/. Executable by authenticated for Storage RLS only.';

revoke all on function public.storage_qualification_document_allowed(text)
  from public, anon, authenticated;
grant execute on function public.storage_qualification_document_allowed(text)
  to authenticated;

create function public.storage_assessment_document_write_allowed(p_name text)
returns boolean
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  rider_person_id uuid;
  assessment_id uuid;
  caller_person uuid;
  assessment_row public.rider_assessments%rowtype;
begin
  rider_person_id := public.storage_path_uuid(p_name, 1);
  assessment_id := public.storage_path_uuid(p_name, 2);
  if rider_person_id is null
     or assessment_id is null
     or not public.storage_path_has_leaf(p_name, 2) then
    return false;
  end if;

  caller_person := public.storage_current_person_id();
  if caller_person is null then
    return false;
  end if;

  select *
    into assessment_row
    from public.rider_assessments as assessment
   where assessment.id = assessment_id
     and assessment.rider_person_id = rider_person_id;

  if assessment_row.id is null then
    return false;
  end if;

  if caller_person is not distinct from assessment_row.rider_person_id then
    return false;
  end if;

  if caller_person is distinct from assessment_row.assessor_person_id then
    return false;
  end if;

  return public.has_active_center_role(
    caller_person,
    assessment_row.center_id,
    'ASSESSOR'
  );
end;
$$;

comment on function public.storage_assessment_document_write_allowed(text) is
  'True when the caller is the assessment assessor PERSON with a current ASSESSOR membership. Path is {rider_person_id}/{assessment_id}/. Executable by authenticated for Storage RLS only.';

revoke all on function public.storage_assessment_document_write_allowed(text)
  from public, anon, authenticated;
grant execute on function public.storage_assessment_document_write_allowed(text)
  to authenticated;

create function public.storage_assessment_document_read_allowed(p_name text)
returns boolean
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  rider_person_id uuid;
  assessment_id uuid;
  caller_person uuid;
begin
  if public.storage_assessment_document_write_allowed(p_name) then
    return true;
  end if;

  rider_person_id := public.storage_path_uuid(p_name, 1);
  assessment_id := public.storage_path_uuid(p_name, 2);
  if rider_person_id is null
     or assessment_id is null
     or not public.storage_path_has_leaf(p_name, 2) then
    return false;
  end if;

  caller_person := public.storage_current_person_id();
  if caller_person is null then
    return false;
  end if;

  if not exists (
    select 1
      from public.rider_assessments as assessment
     where assessment.id = assessment_id
       and assessment.rider_person_id = rider_person_id
  ) then
    return false;
  end if;

  if caller_person is not distinct from rider_person_id then
    return true;
  end if;

  return public.has_current_verified_guardian_relationship(
    caller_person,
    rider_person_id
  );
end;
$$;

comment on function public.storage_assessment_document_read_allowed(text) is
  'True for the current assessor write path, the rider PERSON, or a current VERIFIED guardian. Executable by authenticated for Storage RLS only.';

revoke all on function public.storage_assessment_document_read_allowed(text)
  from public, anon, authenticated;
grant execute on function public.storage_assessment_document_read_allowed(text)
  to authenticated;

create policy storage_027_session_evidence_insert
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'session-evidence'
  and public.storage_session_evidence_allowed(name)
);

create policy storage_027_session_evidence_select
on storage.objects
for select
to authenticated
using (
  bucket_id = 'session-evidence'
  and public.storage_session_evidence_allowed(name)
);

create policy storage_027_qualification_documents_insert
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'qualification-documents'
  and public.storage_qualification_document_allowed(name)
);

create policy storage_027_qualification_documents_select
on storage.objects
for select
to authenticated
using (
  bucket_id = 'qualification-documents'
  and public.storage_qualification_document_allowed(name)
);

create policy storage_027_assessment_documents_insert
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'assessment-documents'
  and public.storage_assessment_document_write_allowed(name)
);

create policy storage_027_assessment_documents_select
on storage.objects
for select
to authenticated
using (
  bucket_id = 'assessment-documents'
  and public.storage_assessment_document_read_allowed(name)
);
