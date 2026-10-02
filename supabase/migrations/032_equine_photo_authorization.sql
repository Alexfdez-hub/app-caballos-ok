-- Issue #41 stage 032. Photo metadata authorization only.
-- PostgreSQL decides whether the caller is the effective PERSON
-- PRIMARY_MANAGER and stores the canonical path. It does not sign,
-- inspect or delete a Storage object, and it does not accept a path
-- or a person, account, owner, manager or center id.
-- equine-media stays private. This file does not deploy.

alter table public.equine_media
  add column retired_at timestamptz;

comment on column public.equine_media.retired_at is
  'Null while the photo metadata is current. A timestamp marks the row historical. now() is not used in a CHECK. Retirement does not delete a Storage object.';

drop index public.equine_media_one_primary_per_equine_key;

create unique index equine_media_one_primary_per_equine_key
  on public.equine_media (equine_id)
  where is_primary and retired_at is null;

comment on index public.equine_media_one_primary_per_equine_key is
  'At most one current primary photo per equine. Retired rows do not occupy the primary slot.';

create function public.equine_photo_caller_can_manage(p_equine_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  caller_person_id uuid;
begin
  select caller.person_id
    into caller_person_id
    from public.resolve_session_caller() as caller;

  return exists (
    select 1
      from public.equine_management_assignments as assignment
     where assignment.equine_id = p_equine_id
       and assignment.manager_type = 'PERSON'
       and assignment.manager_person_id = caller_person_id
       and assignment.management_role = 'PRIMARY_MANAGER'
       and assignment.status = 'ACTIVE'
       and assignment.valid_until is null
       and assignment.valid_from <= clock_timestamp()
  );
end;
$$;

comment on function public.equine_photo_caller_can_manage(uuid) is
  'True only for the caller PERSON who is the effective PERSON PRIMARY_MANAGER. Ownership, other roles, center membership and guardianship are not enough. Not granted to clients.';

revoke all on function public.equine_photo_caller_can_manage(uuid)
  from public, anon, authenticated;

create function public.equine_photo_require_current(p_media_id uuid)
returns table (
  equine_id uuid,
  storage_path text
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  found_equine_id uuid;
  found_path text;
  found_retired_at timestamptz;
begin
  if p_media_id is null then
    raise exception using
      errcode = '22023',
      message = 'Equine photo is not available';
  end if;

  select media.equine_id, media.storage_path, media.retired_at
    into found_equine_id, found_path, found_retired_at
    from public.equine_media as media
   where media.id = p_media_id;

  if found_equine_id is null
     or found_retired_at is not null
     or found_path is distinct from (found_equine_id::text || '/' || p_media_id::text)
     or not public.storage_object_name_is_safe(found_path)
     or not public.equine_photo_caller_can_manage(found_equine_id) then
    raise exception using
      errcode = '42501',
      message = 'Equine photo is not available';
  end if;

  return query
  select found_equine_id, found_path;
end;
$$;

comment on function public.equine_photo_require_current(uuid) is
  'Returns the canonical path of one current photo the caller manages. A missing, retired, foreign or non-canonical row raises the same unavailable error. Does not sign or touch Storage. Not granted to clients.';

revoke all on function public.equine_photo_require_current(uuid)
  from public, anon, authenticated;

create function public.authorize_my_equine_photo_prepare(
  p_equine_id uuid,
  p_is_primary boolean
)
returns table (
  media_id uuid,
  storage_path text
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  created_media_id uuid := gen_random_uuid();
  created_path text;
begin
  if p_equine_id is null or p_is_primary is null then
    raise exception using
      errcode = '22023',
      message = 'Equine photo is not available';
  end if;

  if not public.equine_photo_caller_can_manage(p_equine_id) then
    raise exception using
      errcode = '42501',
      message = 'Equine photo is not available';
  end if;

  created_path := p_equine_id::text || '/' || created_media_id::text;

  if created_path is distinct from (p_equine_id::text || '/' || created_media_id::text)
     or not public.storage_object_name_is_safe(created_path) then
    raise exception using
      errcode = '22023',
      message = 'Equine photo is not available';
  end if;

  insert into public.equine_media (
    id,
    equine_id,
    storage_path,
    media_type,
    sort_order,
    is_primary
  ) values (
    created_media_id,
    p_equine_id,
    created_path,
    'PHOTO',
    0,
    p_is_primary
  );

  return query
  select created_media_id, created_path;
end;
$$;

comment on function public.authorize_my_equine_photo_prepare(uuid, boolean) is
  'Inserts PHOTO metadata for the caller effective PERSON PRIMARY_MANAGER and returns the canonical path {equine_id}/{media_id}. Does not accept a path and does not sign a URL.';

revoke all on function public.authorize_my_equine_photo_prepare(uuid, boolean)
  from public, anon, authenticated;
grant execute on function public.authorize_my_equine_photo_prepare(uuid, boolean)
  to authenticated;

create function public.abandon_my_equine_photo(p_media_id uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  current_equine_id uuid;
begin
  select current_photo.equine_id
    into current_equine_id
    from public.equine_photo_require_current(p_media_id) as current_photo;

  delete from public.equine_media
   where id = p_media_id;

  perform public.record_audit_event(
    'equine_photo_abandoned',
    'equine_media',
    p_media_id,
    jsonb_build_object('equine_id', current_equine_id)
  );
end;
$$;

comment on function public.abandon_my_equine_photo(uuid) is
  'Removes current photo metadata the caller manages and audits equine_photo_abandoned. Does not inspect or delete a Storage object.';

revoke all on function public.abandon_my_equine_photo(uuid)
  from public, anon, authenticated;
grant execute on function public.abandon_my_equine_photo(uuid)
  to authenticated;

create function public.authorize_my_equine_photo_finalize(p_media_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  current_path text;
begin
  select current_photo.storage_path
    into current_path
    from public.equine_photo_require_current(p_media_id) as current_photo;

  return current_path;
end;
$$;

comment on function public.authorize_my_equine_photo_finalize(uuid) is
  'Returns the canonical path for a current photo the caller manages. Does not mutate metadata and does not inspect Storage.';

revoke all on function public.authorize_my_equine_photo_finalize(uuid)
  from public, anon, authenticated;
grant execute on function public.authorize_my_equine_photo_finalize(uuid)
  to authenticated;

create function public.record_my_equine_photo_finalized(p_media_id uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  current_equine_id uuid;
begin
  select current_photo.equine_id
    into current_equine_id
    from public.equine_photo_require_current(p_media_id) as current_photo;

  perform public.record_audit_event(
    'equine_photo_finalized',
    'equine_media',
    p_media_id,
    jsonb_build_object('equine_id', current_equine_id)
  );
end;
$$;

comment on function public.record_my_equine_photo_finalized(uuid) is
  'Audits equine_photo_finalized for a current photo the caller manages. Leaves the row in place and does not inspect Storage.';

revoke all on function public.record_my_equine_photo_finalized(uuid)
  from public, anon, authenticated;
grant execute on function public.record_my_equine_photo_finalized(uuid)
  to authenticated;

create function public.list_my_equine_photos(p_equine_id uuid)
returns table (
  media_id uuid,
  storage_path text,
  sort_order integer,
  is_primary boolean,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
begin
  if p_equine_id is null
     or not public.equine_photo_caller_can_manage(p_equine_id) then
    raise exception using
      errcode = '42501',
      message = 'Equine photo is not available';
  end if;

  return query
  select
    media.id,
    media.storage_path,
    media.sort_order,
    media.is_primary,
    media.created_at
  from public.equine_media as media
  where media.equine_id = p_equine_id
    and media.retired_at is null
    and media.storage_path = (media.equine_id::text || '/' || media.id::text)
  order by media.sort_order, media.created_at, media.id;
end;
$$;

comment on function public.list_my_equine_photos(uuid) is
  'Lists current canonical photo metadata for one equine the caller manages. No signed URL and no retired row.';

revoke all on function public.list_my_equine_photos(uuid)
  from public, anon, authenticated;
grant execute on function public.list_my_equine_photos(uuid)
  to authenticated;

create function public.authorize_my_equine_photo_read(p_media_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  current_path text;
begin
  select current_photo.storage_path
    into current_path
    from public.equine_photo_require_current(p_media_id) as current_photo;

  return current_path;
end;
$$;

comment on function public.authorize_my_equine_photo_read(uuid) is
  'Returns the canonical path for a current photo the caller manages. A retired row is refused. Does not sign a URL.';

revoke all on function public.authorize_my_equine_photo_read(uuid)
  from public, anon, authenticated;
grant execute on function public.authorize_my_equine_photo_read(uuid)
  to authenticated;

create function public.authorize_my_equine_photo_retire(p_media_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  current_path text;
begin
  select current_photo.storage_path
    into current_path
    from public.equine_photo_require_current(p_media_id) as current_photo;

  return current_path;
end;
$$;

comment on function public.authorize_my_equine_photo_retire(uuid) is
  'Returns the canonical path for a current photo the caller manages. Does not set retired_at and does not delete a Storage object.';

revoke all on function public.authorize_my_equine_photo_retire(uuid)
  from public, anon, authenticated;
grant execute on function public.authorize_my_equine_photo_retire(uuid)
  to authenticated;

create function public.retire_my_equine_photo_metadata(p_media_id uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  current_equine_id uuid;
begin
  select current_photo.equine_id
    into current_equine_id
    from public.equine_photo_require_current(p_media_id) as current_photo;

  update public.equine_media
     set retired_at = clock_timestamp(),
         is_primary = false
   where id = p_media_id
     and retired_at is null;

  if not found then
    raise exception using
      errcode = '42501',
      message = 'Equine photo is not available';
  end if;

  perform public.record_audit_event(
    'equine_photo_retired',
    'equine_media',
    p_media_id,
    jsonb_build_object('equine_id', current_equine_id)
  );
end;
$$;

comment on function public.retire_my_equine_photo_metadata(uuid) is
  'Marks current photo metadata historical, clears is_primary and audits equine_photo_retired. Does not delete a Storage object.';

revoke all on function public.retire_my_equine_photo_metadata(uuid)
  from public, anon, authenticated;
grant execute on function public.retire_my_equine_photo_metadata(uuid)
  to authenticated;
