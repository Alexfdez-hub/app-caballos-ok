-- Issue #41 stage 032. One transaction, then ROLLBACK.
-- Direct SQL provisions people. Client steps call RPCs.
-- Table reads run as the table owner.

begin;

create function pg_temp.photo_jwt(p_auth uuid)
returns void
language plpgsql
as $$
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_auth::text, ''), true);
  if p_auth is null then
    perform set_config('request.jwt.claims', '{}', true);
  else
    perform set_config(
      'request.jwt.claims',
      json_build_object('sub', p_auth::text, 'role', 'authenticated')::text,
      true
    );
  end if;
end;
$$;

create function pg_temp.photo_rebind(
  p_auth uuid,
  p_person uuid,
  p_account uuid,
  p_first text,
  p_last text,
  p_dob date,
  p_market text
)
returns void
language plpgsql
as $$
declare
  old_person uuid;
begin
  select account.person_id
    into old_person
    from public.user_accounts as account
   where account.auth_user_id = p_auth;

  delete from public.user_accounts where auth_user_id = p_auth;
  delete from public.persons where id = old_person;

  insert into public.persons (
    id, first_name, last_name, date_of_birth, country_code
  ) values (p_person, p_first, p_last, p_dob, p_market);

  insert into public.user_accounts (id, auth_user_id, person_id)
  values (p_account, p_auth, p_person);
end;
$$;

insert into auth.users (id) values
  ('03210000-0000-4000-8000-000000000001'),
  ('03210000-0000-4000-8000-000000000002'),
  ('03210000-0000-4000-8000-000000000003'),
  ('03210000-0000-4000-8000-000000000004');

insert into public.markets (country_code, status) values ('QS', 'ACTIVE');
insert into public.market_age_rules (
  country_code, legal_adult_age, guardian_consent_required, effective_from
) values ('QS', 18, true, date '2000-01-01');

do $$
begin
  perform pg_temp.photo_rebind(
    '03210000-0000-4000-8000-000000000001',
    '03210000-0000-4000-8000-000000000011',
    '03210000-0000-4000-8000-000000000021',
    'Avery', 'Photo', date '1990-04-12', 'QS'
  );
  perform pg_temp.photo_rebind(
    '03210000-0000-4000-8000-000000000002',
    '03210000-0000-4000-8000-000000000012',
    '03210000-0000-4000-8000-000000000022',
    'Blair', 'Photo', date '1988-01-02', 'QS'
  );
  perform pg_temp.photo_rebind(
    '03210000-0000-4000-8000-000000000003',
    '03210000-0000-4000-8000-000000000013',
    '03210000-0000-4000-8000-000000000023',
    'Quinn', 'Photo', date '1982-02-02', 'QS'
  );
  perform pg_temp.photo_rebind(
    '03210000-0000-4000-8000-000000000004',
    '03210000-0000-4000-8000-000000000014',
    '03210000-0000-4000-8000-000000000024',
    'Morgan', 'Photo', date '1984-08-08', 'QS'
  );

  insert into public.persons (id, first_name, last_name, date_of_birth, country_code)
  values (
    '03210000-0000-4000-8000-000000000016',
    'Rowan', 'Photo', date '2014-03-03', 'QS'
  );

  insert into public.guardian_relationships (
    id, guardian_person_id, minor_person_id, relationship_type,
    verification_status, verified_at
  ) values (
    '03210000-0000-4000-8000-000000000041',
    '03210000-0000-4000-8000-000000000013',
    '03210000-0000-4000-8000-000000000016',
    'PARENT', 'VERIFIED', clock_timestamp()
  );

  insert into public.equestrian_centers (id, name, slug, country_code, status)
  values (
    '03210000-0000-4000-8000-000000000031',
    'Photo center',
    'photo-center-qs',
    'QS',
    'ACTIVE'
  );

  insert into public.center_memberships (center_id, person_id, role_code, status)
  values (
    '03210000-0000-4000-8000-000000000031',
    '03210000-0000-4000-8000-000000000014',
    'MANAGER',
    'ACTIVE'
  );
end;
$$;

select pg_temp.photo_jwt('03210000-0000-4000-8000-000000000001');
set local role authenticated;

do $$
#variable_conflict use_variable
declare
  equine_id uuid;
  primary_media uuid;
  primary_path text;
  second_media uuid;
  second_path text;
  listed integer;
  authorized_path text;
begin
  equine_id := public.create_my_equine('Foto', 'HORSE');

  select prepared.media_id, prepared.storage_path
    into primary_media, primary_path
    from public.authorize_my_equine_photo_prepare(equine_id, true) as prepared;

  if primary_path is distinct from (equine_id::text || '/' || primary_media::text)
     or primary_path like '%http%'
     or primary_path like '%/%/%' then
    raise exception 'Prepare did not return the canonical path';
  end if;

  begin
    perform public.authorize_my_equine_photo_prepare(equine_id, true);
    raise exception 'A second current primary was accepted';
  exception
    when unique_violation then null;
  end;

  select prepared.media_id, prepared.storage_path
    into second_media, second_path
    from public.authorize_my_equine_photo_prepare(equine_id, false) as prepared;

  if second_path is distinct from (equine_id::text || '/' || second_media::text) then
    raise exception 'Secondary prepare path was not canonical';
  end if;

  select count(*) into listed from public.list_my_equine_photos(equine_id);
  if listed <> 2 then
    raise exception 'Expected two current photos, got %', listed;
  end if;

  authorized_path := public.authorize_my_equine_photo_finalize(primary_media);
  if authorized_path is distinct from primary_path then
    raise exception 'Finalize authorization changed the path';
  end if;

  perform public.record_my_equine_photo_finalized(primary_media);

  authorized_path := public.authorize_my_equine_photo_read(primary_media);
  if authorized_path is distinct from primary_path then
    raise exception 'Read authorization changed the path';
  end if;

  authorized_path := public.authorize_my_equine_photo_retire(primary_media);
  if authorized_path is distinct from primary_path then
    raise exception 'Retire authorization changed the path';
  end if;

  perform set_config('photo.equine_id', equine_id::text, true);
  perform set_config('photo.primary_media', primary_media::text, true);
  perform set_config('photo.primary_path', primary_path, true);
  perform set_config('photo.second_media', second_media::text, true);
end;
$$;

reset role;

do $$
#variable_conflict use_variable
declare
  equine_id uuid := current_setting('photo.equine_id')::uuid;
  primary_media uuid := current_setting('photo.primary_media')::uuid;
  primary_count integer;
  retired_at timestamptz;
  is_primary boolean;
begin
  select count(*) into primary_count
    from public.equine_media as media
   where media.equine_id = equine_id
     and media.is_primary
     and media.retired_at is null;
  if primary_count <> 1 then
    raise exception 'Expected one current primary, got %', primary_count;
  end if;

  if not exists (
    select 1
      from public.audit_events as audit_event
     where audit_event.entity_id = primary_media
       and audit_event.event_type = 'equine_photo_finalized'
       and audit_event.metadata = jsonb_build_object('equine_id', equine_id)
  ) then
    raise exception 'Finalize audit is missing';
  end if;

  select media.retired_at, media.is_primary
    into retired_at, is_primary
    from public.equine_media as media
   where media.id = primary_media;
  if retired_at is not null or is_primary is distinct from true then
    raise exception 'Retire authorization mutated the row';
  end if;
end;
$$;

select pg_temp.photo_jwt('03210000-0000-4000-8000-000000000001');
set local role authenticated;

do $$
#variable_conflict use_variable
declare
  equine_id uuid := current_setting('photo.equine_id')::uuid;
  primary_media uuid := current_setting('photo.primary_media')::uuid;
  second_media uuid := current_setting('photo.second_media')::uuid;
  listed integer;
begin
  perform public.retire_my_equine_photo_metadata(primary_media);

  begin
    perform public.authorize_my_equine_photo_read(primary_media);
    raise exception 'Retired photo remained readable';
  exception
    when insufficient_privilege then null;
  end;

  select count(*) into listed from public.list_my_equine_photos(equine_id);
  if listed <> 1 then
    raise exception 'Retired photo remained in the list, got %', listed;
  end if;

  perform public.authorize_my_equine_photo_prepare(equine_id, true);
  perform public.abandon_my_equine_photo(second_media);
end;
$$;

reset role;

do $$
#variable_conflict use_variable
declare
  equine_id uuid := current_setting('photo.equine_id')::uuid;
  primary_media uuid := current_setting('photo.primary_media')::uuid;
  second_media uuid := current_setting('photo.second_media')::uuid;
  primary_count integer;
  retired_ok boolean;
  bad_media uuid;
begin
  select media.retired_at is not null and media.is_primary = false
    into retired_ok
    from public.equine_media as media
   where media.id = primary_media;
  if retired_ok is distinct from true then
    raise exception 'Retired metadata did not clear the primary flag';
  end if;

  if exists (
    select 1 from public.equine_media as media where media.id = second_media
  ) then
    raise exception 'Abandoned photo metadata remained';
  end if;

  if not exists (
    select 1
      from public.audit_events as audit_event
     where audit_event.entity_id = primary_media
       and audit_event.event_type = 'equine_photo_retired'
       and audit_event.metadata = jsonb_build_object('equine_id', equine_id)
  ) or not exists (
    select 1
      from public.audit_events as audit_event
     where audit_event.entity_id = second_media
       and audit_event.event_type = 'equine_photo_abandoned'
       and audit_event.metadata = jsonb_build_object('equine_id', equine_id)
  ) then
    raise exception 'Photo lifecycle audit is missing';
  end if;

  select count(*) into primary_count
    from public.equine_media as media
   where media.equine_id = equine_id
     and media.is_primary
     and media.retired_at is null;
  if primary_count <> 1 then
    raise exception 'A new primary was not allowed after retirement, got %', primary_count;
  end if;

  update public.equine_media
     set storage_path = 'not/canonical'
   where equine_id = equine_id
     and retired_at is null
     and is_primary
   returning id into bad_media;
  perform set_config('photo.bad_media', bad_media::text, true);
end;
$$;

select pg_temp.photo_jwt('03210000-0000-4000-8000-000000000001');
set local role authenticated;

do $$
#variable_conflict use_variable
declare
  equine_id uuid := current_setting('photo.equine_id')::uuid;
  listed integer;
begin
  begin
    perform public.authorize_my_equine_photo_read(
      current_setting('photo.bad_media')::uuid
    );
    raise exception 'Non-canonical path was authorized';
  exception
    when insufficient_privilege then null;
  end;

  select count(*) into listed
    from public.list_my_equine_photos(equine_id);
  if listed <> 0 then
    raise exception 'Non-canonical path remained listed';
  end if;

  begin
    insert into public.equine_media (equine_id, storage_path, media_type)
    values (equine_id, equine_id::text || '/direct', 'PHOTO');
    raise exception 'Authenticated inserted equine_media directly';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

reset role;

insert into public.equine_ownerships (
  equine_id, owner_type, owner_person_id, ownership_percentage, status, started_at
) values (
  current_setting('photo.equine_id')::uuid,
  'PERSON',
  '03210000-0000-4000-8000-000000000012',
  100,
  'ACTIVE',
  clock_timestamp()
);

insert into public.equine_management_assignments (
  equine_id, manager_type, manager_person_id, management_role, status,
  valid_from, granted_by_person_id
) values (
  current_setting('photo.equine_id')::uuid,
  'PERSON',
  '03210000-0000-4000-8000-000000000012',
  'CO_MANAGER',
  'ACTIVE',
  clock_timestamp(),
  '03210000-0000-4000-8000-000000000011'
);

select pg_temp.photo_jwt('03210000-0000-4000-8000-000000000002');
set local role authenticated;

do $$
begin
  begin
    perform public.authorize_my_equine_photo_prepare(
      current_setting('photo.equine_id')::uuid,
      false
    );
    raise exception 'Owner and co-manager prepared a photo';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

reset role;
select pg_temp.photo_jwt('03210000-0000-4000-8000-000000000003');
set local role authenticated;

do $$
begin
  begin
    perform public.list_my_equine_photos(current_setting('photo.equine_id')::uuid);
    raise exception 'Guardian listed a foreign photo';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

reset role;
select pg_temp.photo_jwt('03210000-0000-4000-8000-000000000004');
set local role authenticated;

do $$
begin
  begin
    perform public.authorize_my_equine_photo_read(current_setting('photo.primary_media')::uuid);
    raise exception 'Center member read a foreign photo';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

reset role;

do $$
#variable_conflict use_variable
declare
  function_name text;
begin
  if exists (
    select 1
      from pg_catalog.pg_proc as procedure
      join pg_catalog.pg_namespace as namespace
        on namespace.oid = procedure.pronamespace
     where namespace.nspname = 'public'
       and procedure.proname in (
         'authorize_my_equine_photo_prepare',
         'abandon_my_equine_photo',
         'authorize_my_equine_photo_finalize',
         'record_my_equine_photo_finalized',
         'list_my_equine_photos',
         'authorize_my_equine_photo_read',
         'authorize_my_equine_photo_retire',
         'retire_my_equine_photo_metadata'
       )
       and (
         pg_catalog.pg_get_function_identity_arguments(procedure.oid) ~ 'text'
         or procedure.prosrc ~* 'service_role|signed_url|create_signed|storage\.objects'
       )
  ) then
    raise exception 'Photo authorization accepts a path or touches Storage';
  end if;

  foreach function_name in array array[
    'public.authorize_my_equine_photo_prepare(uuid, boolean)',
    'public.abandon_my_equine_photo(uuid)',
    'public.authorize_my_equine_photo_finalize(uuid)',
    'public.record_my_equine_photo_finalized(uuid)',
    'public.list_my_equine_photos(uuid)',
    'public.authorize_my_equine_photo_read(uuid)',
    'public.authorize_my_equine_photo_retire(uuid)',
    'public.retire_my_equine_photo_metadata(uuid)'
  ]
  loop
    if has_function_privilege('anon', function_name, 'EXECUTE')
       or has_function_privilege('public', function_name, 'EXECUTE') then
      raise exception 'anon or PUBLIC can execute %', function_name;
    end if;
  end loop;

  if has_function_privilege(
       'authenticated',
       'public.equine_photo_caller_can_manage(uuid)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'public.equine_photo_require_current(uuid)',
       'EXECUTE'
     )
     or has_table_privilege('authenticated', 'public.equine_media', 'SELECT')
     or has_table_privilege('authenticated', 'public.equine_media', 'INSERT') then
    raise exception 'Photo internals or equine_media are client-executable';
  end if;

  if (
    select bucket.public
      from storage.buckets as bucket
     where bucket.id = 'equine-media'
  ) is distinct from false then
    raise exception 'equine-media bucket is not private';
  end if;

  if exists (
    select 1
      from pg_catalog.pg_policy as policy
     where policy.polrelid = 'storage.objects'::regclass
       and (
         policy.polname ilike '%equine-media%'
         or pg_catalog.pg_get_expr(policy.polqual, policy.polrelid) ilike '%equine-media%'
         or pg_catalog.pg_get_expr(policy.polwithcheck, policy.polrelid) ilike '%equine-media%'
       )
  ) then
    raise exception 'equine-media must stay deny-by-default';
  end if;
end;
$$;

rollback;
