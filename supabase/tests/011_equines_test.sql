-- Phase 3F local equines foundation tests.
-- Assumes migrations 001-011 are applied and auth.uid() reads
-- request.jwt.claim.sub. Runnable without psql meta-commands.

begin;

do $$
declare
  fixture_auth uuid[] := array[
    '70000000-0000-0000-0000-000000000001'::uuid
  ];
  linked_person_ids uuid[];
  fixture_equine_ids uuid[];
  fixture_center_ids uuid[];
begin
  select coalesce(array_agg(id), '{}')
    into fixture_equine_ids
    from public.equines
   where name like 'phase3f-%'
      or name in (
        'Pilot Horse',
        'Pilot Pony',
        'Archived Equine',
        'Deceased Equine',
        'Public Intent Horse',
        'Boundary Birth',
        'Null Birth',
        'Utc Boundary Birth'
      );

  delete from public.equine_media
   where equine_id = any(fixture_equine_ids);

  delete from public.equines
   where id = any(fixture_equine_ids);

  select coalesce(array_agg(id), '{}')
    into fixture_center_ids
    from public.equestrian_centers
   where slug like 'phase3f-%';

  delete from public.center_memberships
   where center_id = any(fixture_center_ids)
      or person_id in (
        select person_id from public.user_accounts where auth_user_id = any(fixture_auth)
      );

  delete from public.center_languages
   where center_id = any(fixture_center_ids);

  delete from public.equestrian_centers
   where id = any(fixture_center_ids);

  delete from public.rider_profiles
   where person_id in (
     select person_id from public.user_accounts where auth_user_id = any(fixture_auth)
   );

  delete from public.policy_acceptances
   where user_account_id in (
     select id from public.user_accounts where auth_user_id = any(fixture_auth)
   );

  delete from public.guardian_consents
   where granted_by_account_id in (
     select id from public.user_accounts where auth_user_id = any(fixture_auth)
   );

  select coalesce(array_agg(person_id), '{}')
    into linked_person_ids
    from public.user_accounts
   where auth_user_id = any(fixture_auth);

  delete from public.user_accounts
   where auth_user_id = any(fixture_auth);

  delete from public.persons
   where id = any(linked_person_ids);

  delete from public.market_age_rules
   where country_code = 'ZE';

  delete from public.markets
   where country_code = 'ZE';

  delete from auth.users
   where id = any(fixture_auth);
end;
$$;

insert into public.markets (country_code, status)
values ('ZE', 'ACTIVE');

insert into auth.users (id)
values ('70000000-0000-0000-0000-000000000001');

do $$
declare
  caller_person_id uuid;
  equine_id uuid;
  pony_id uuid;
  archived_id uuid;
  deceased_id uuid;
  public_intent_id uuid;
  media_id uuid;
  second_media_id uuid;
  center_id uuid;
  membership_id uuid;
begin
  if to_regclass('public.horses') is not null then
    raise exception 'Legacy public.horses must not be reintroduced';
  end if;

  if exists (
    select 1
      from information_schema.columns
     where table_schema = 'public'
       and table_name = 'equines'
       and column_name in (
         'owner_id',
         'manager_id',
         'center_id',
         'auth_user_id',
         'user_account_id',
         'person_id',
         'owner_person_id',
         'manager_person_id'
       )
  ) then
    raise exception 'Equines must not carry person, account, owner, manager or center authority shortcuts';
  end if;

  if exists (
    select 1
      from information_schema.columns
     where table_schema = 'public'
       and table_name = 'equines'
       and column_name in ('age', 'age_years', 'age_months')
  ) then
    raise exception 'Equines must not store age';
  end if;

  if exists (
    select 1
      from information_schema.columns
     where table_schema = 'public'
       and table_name in ('persons', 'user_accounts')
       and column_name in ('role', 'is_owner', 'is_manager')
  ) then
    raise exception 'Account-level equine role shortcuts must not exist';
  end if;

  if exists (
    select 1
      from information_schema.tables
     where table_schema = 'public'
       and table_name in (
         'bookings'
       )
  ) then
    raise exception 'Later equine domains must remain deferred';
  end if;

  if exists (
    select 1
      from pg_catalog.pg_proc as procedure
      join pg_catalog.pg_namespace as namespace
        on namespace.oid = procedure.pronamespace
     where namespace.nspname = 'public'
       and procedure.proname in (
         'list_my_equines',
         'get_my_equines',
         'create_equine',
         'upsert_equine',
         'update_equine',
         'delete_equine',
         'create_equine_media',
         'list_public_equines'
       )
  ) then
    raise exception 'Client equine mutation or my-equines RPC must not exist';
  end if;

  if (
    select count(*)
      from pg_catalog.pg_class
     where oid in (
       'public.equines'::regclass,
       'public.equine_media'::regclass
     )
       and relrowsecurity
  ) <> 2 then
    raise exception 'Equine RLS is not enabled';
  end if;

  if exists (
    select 1
      from pg_catalog.pg_policy
     where polrelid in (
       'public.equines'::regclass,
       'public.equine_media'::regclass
     )
  ) then
    raise exception 'Equine tables unexpectedly gained client RLS policies';
  end if;

  if not exists (
    select 1
      from pg_catalog.pg_constraint
     where conrelid = 'public.equine_media'::regclass
       and conname = 'equine_media_storage_path_key'
       and contype = 'u'
  ) then
    raise exception 'equine_media.storage_path unique constraint is missing';
  end if;

  select person_id into caller_person_id
    from public.user_accounts
   where auth_user_id = '70000000-0000-0000-0000-000000000001';

  update public.persons
     set first_name = 'Rider', last_name = 'Caller', date_of_birth = date '1987-01-01'
   where id = caller_person_id;

  insert into public.rider_profiles (person_id, profile_visibility)
  values (caller_person_id, 'PUBLIC');

  insert into public.equestrian_centers (name, slug, country_code, status)
  values ('Phase 3F Yard', 'phase3f-yard', 'ZE', 'ACTIVE')
  returning id into center_id;

  insert into public.center_memberships (center_id, person_id, role_code)
  values (center_id, caller_person_id, 'MANAGER')
  returning id into membership_id;

  insert into public.equines (name, equine_type, height_cm)
  values ('Pilot Horse', 'HORSE', 165)
  returning id into equine_id;

  if pg_typeof(equine_id) is distinct from 'uuid'::regtype then
    raise exception 'Equine primary key is not uuid';
  end if;

  if equine_id = '70000000-0000-0000-0000-000000000001' then
    raise exception 'Equine identity used an Auth UUID';
  end if;

  if (
    select status || ',' || visibility_status
      from public.equines
     where id = equine_id
  ) is distinct from 'ACTIVE,PRIVATE' then
    raise exception 'Equine defaults were not ACTIVE and PRIVATE';
  end if;

  if (
    select birth_date
      from public.equines
     where id = equine_id
  ) is not null then
    raise exception 'Null birth_date was not accepted';
  end if;

  insert into public.equines (
    name, equine_type, birth_date
  ) values (
    'Null Birth', 'HORSE', null
  );

  insert into public.equines (
    name, equine_type, birth_date, created_at
  ) values (
    'Boundary Birth',
    'HORSE',
    date '2018-06-01',
    timestamptz '2018-06-01 23:59:59+00'
  );

  insert into public.equines (
    name, equine_type, status, visibility_status
  ) values (
    'Pilot Pony', 'PONY', 'INACTIVE', 'PRIVATE'
  ) returning id into pony_id;

  insert into public.equines (
    name, equine_type, status
  ) values (
    'Archived Equine', 'HORSE', 'ARCHIVED'
  ) returning id into archived_id;

  insert into public.equines (
    name, equine_type, status
  ) values (
    'Deceased Equine', 'HORSE', 'DECEASED'
  ) returning id into deceased_id;

  if deceased_id is not distinct from archived_id then
    raise exception 'DECEASED must be a distinct row from ARCHIVED';
  end if;

  if (
    select status
      from public.equines
     where id = deceased_id
  ) is distinct from 'DECEASED' then
    raise exception 'DECEASED status was not stored';
  end if;

  if (
    select status
      from public.equines
     where id = archived_id
  ) is distinct from 'ARCHIVED' then
    raise exception 'ARCHIVED status was not stored';
  end if;

  insert into public.equines (
    name, equine_type, visibility_status
  ) values (
    'Public Intent Horse', 'HORSE', 'PUBLIC'
  ) returning id into public_intent_id;

  begin
    insert into public.equines (name, equine_type)
    values ('', 'HORSE');
    raise exception 'Empty equine name was allowed';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.equines (name, equine_type)
    values ('   ', 'HORSE');
    raise exception 'Whitespace-only equine name was allowed';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.equines (name, equine_type)
    values ('  Luna  ', 'HORSE');
    raise exception 'Untrimmed equine name was allowed';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.equines (name, equine_type)
    values ('Mule', 'MULE');
    raise exception 'Non-frozen equine type was allowed';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.equines (name, equine_type)
    values ('Lower horse', 'horse');
    raise exception 'Lowercase equine type was allowed';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.equines (name, equine_type, height_cm)
    values ('Zero height', 'HORSE', 0);
    raise exception 'Zero height_cm was allowed';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.equines (name, equine_type, height_cm)
    values ('Negative height', 'HORSE', -1);
    raise exception 'Negative height_cm was allowed';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.equines (name, equine_type, status)
    values ('Draft equine', 'HORSE', 'DRAFT');
    raise exception 'Center DRAFT lifecycle was copied onto equines';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.equines (name, equine_type, status)
    values ('Retired equine', 'HORSE', 'RETIRED');
    raise exception 'RETIRED equine status was allowed';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.equines (name, equine_type, status)
    values ('Suspended equine', 'HORSE', 'SUSPENDED');
    raise exception 'Invalid equine lifecycle status was allowed';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.equines (
      name, equine_type, birth_date, created_at
    ) values (
      'Future Birth',
      'HORSE',
      date '2020-01-02',
      timestamptz '2020-01-01 12:00:00+00'
    );
    raise exception 'birth_date after UTC created_at date was allowed';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.equines (name, equine_type, birth_date)
    values ('Tomorrow Birth', 'HORSE', (current_date + 1));
    raise exception 'Future birth_date was allowed';
  exception
    when check_violation then null;
  end;

  perform set_config('TimeZone', 'Etc/GMT-14', true);

  if current_setting('TimeZone') is distinct from 'Etc/GMT-14' then
    raise exception 'Could not set transaction timezone for UTC birth_date test';
  end if;

  if (timestamptz '2020-01-01 22:00:00+00')::date is distinct from date '2020-01-02' then
    raise exception 'Timezone fixture did not move created_at::date to the next local day';
  end if;

  if (
    (timestamptz '2020-01-01 22:00:00+00' at time zone 'UTC')::date
  ) is distinct from date '2020-01-01' then
    raise exception 'UTC calendar date fixture is wrong';
  end if;

  insert into public.equines (
    name, equine_type, birth_date, created_at
  ) values (
    'Utc Boundary Birth',
    'HORSE',
    date '2020-01-01',
    timestamptz '2020-01-01 22:00:00+00'
  );

  begin
    insert into public.equines (
      name, equine_type, birth_date, created_at
    ) values (
      'Kiritimati Future Birth',
      'HORSE',
      date '2020-01-02',
      timestamptz '2020-01-01 22:00:00+00'
    );
    raise exception 'Session-timezone next-day birth_date was allowed';
  exception
    when check_violation then null;
  end;

  perform set_config('TimeZone', 'UTC', true);

  begin
    insert into public.equines (name, equine_type, visibility_status)
    values ('Listed equine', 'HORSE', 'UNLISTED');
    raise exception 'Invalid equine visibility was allowed';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.equines (name, equine_type, sex)
    values ('Blank sex', 'HORSE', '  ');
    raise exception 'Whitespace-only sex was allowed';
  exception
    when check_violation then null;
  end;

  insert into public.equine_media (
    equine_id, storage_path, media_type, sort_order, is_primary
  ) values (
    equine_id, 'equine-media/pilot-horse/front.jpg', 'PHOTO', 0, true
  ) returning id into media_id;

  if pg_typeof(media_id) is distinct from 'uuid'::regtype then
    raise exception 'Equine media primary key is not uuid';
  end if;

  insert into public.equine_media (
    equine_id, storage_path, media_type, sort_order, is_primary
  ) values (
    equine_id, 'equine-media/pilot-horse/side.jpg', 'PHOTO', 1, false
  ) returning id into second_media_id;

  begin
    insert into public.equine_media (
      equine_id, storage_path, media_type, is_primary
    ) values (
      equine_id, 'equine-media/pilot-horse/other.jpg', 'PHOTO', true
    );
    raise exception 'Second primary media row was allowed';
  exception
    when unique_violation then null;
  end;

  begin
    insert into public.equine_media (
      equine_id, storage_path, media_type
    ) values (
      pony_id, 'equine-media/pilot-horse/front.jpg', 'PHOTO'
    );
    raise exception 'Duplicate storage_path was allowed';
  exception
    when unique_violation then null;
  end;

  begin
    insert into public.equine_media (
      equine_id, storage_path, media_type
    ) values (
      '00000000-0000-0000-0000-000000000000',
      'equine-media/missing.jpg',
      'PHOTO'
    );
    raise exception 'Media without a valid equine was allowed';
  exception
    when foreign_key_violation then null;
  end;

  begin
    insert into public.equine_media (
      equine_id, storage_path, media_type
    ) values (
      equine_id, '', 'PHOTO'
    );
    raise exception 'Empty storage_path was allowed';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.equine_media (
      equine_id, storage_path, media_type
    ) values (
      equine_id, '  padded/path.jpg  ', 'PHOTO'
    );
    raise exception 'Untrimmed storage_path was allowed';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.equine_media (
      equine_id, storage_path, media_type
    ) values (
      equine_id, 'equine-media/video.mp4', 'VIDEO'
    );
    raise exception 'VIDEO media_type was allowed';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.equine_media (
      equine_id, storage_path, media_type, sort_order
    ) values (
      equine_id, 'equine-media/negative.jpg', 'PHOTO', -1
    );
    raise exception 'Negative sort_order was allowed';
  exception
    when check_violation then null;
  end;

  if exists (
    select 1
      from public.policy_acceptances
     where person_id = caller_person_id
  ) then
    raise exception 'Creating an equine created policy acceptance';
  end if;

  if exists (
    select 1
      from public.guardian_consents
     where granted_by_account_id in (
       select id from public.user_accounts
        where auth_user_id = '70000000-0000-0000-0000-000000000001'
     )
  ) then
    raise exception 'Creating an equine created guardian consent';
  end if;

  if not exists (
    select 1 from public.center_memberships where id = membership_id
  ) then
    raise exception 'Equine fixture lost the caller Center membership';
  end if;

  perform set_config('app.equine_id', equine_id::text, true);
  perform set_config('app.pony_id', pony_id::text, true);
  perform set_config('app.archived_id', archived_id::text, true);
  perform set_config('app.deceased_id', deceased_id::text, true);
  perform set_config('app.public_intent_id', public_intent_id::text, true);
  perform set_config('app.media_id', media_id::text, true);
  perform set_config('app.second_media_id', second_media_id::text, true);
  perform set_config('app.center_id', center_id::text, true);
  perform set_config('app.caller_person', caller_person_id::text, true);
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '70000000-0000-0000-0000-000000000001', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"70000000-0000-0000-0000-000000000001"}',
  true
);

do $$
begin
  begin
    perform * from public.equines;
    raise exception 'Authenticated role selected equines directly';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform * from public.equines
     where visibility_status = 'PUBLIC';
    raise exception 'Authenticated role selected PUBLIC equines';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform * from public.equine_media;
    raise exception 'Authenticated role selected equine media directly';
  exception
    when insufficient_privilege then null;
  end;

  begin
    insert into public.equines (name, equine_type)
    values ('Self created', 'HORSE');
    raise exception 'Authenticated role created an equine';
  exception
    when insufficient_privilege then null;
  end;

  begin
    update public.equines
       set name = 'Taken over',
           visibility_status = 'PUBLIC';
    raise exception 'Authenticated role edited an equine';
  exception
    when insufficient_privilege then null;
  end;

  begin
    delete from public.equines;
    raise exception 'Authenticated role deleted equines';
  exception
    when insufficient_privilege then null;
  end;

  begin
    insert into public.equine_media (
      equine_id, storage_path, media_type
    ) values (
      current_setting('app.equine_id', true)::uuid,
      'equine-media/client-upload.jpg',
      'PHOTO'
    );
    raise exception 'Authenticated role inserted equine media';
  exception
    when insufficient_privilege then null;
  end;

  begin
    update public.equine_media
       set is_primary = true;
    raise exception 'Authenticated role updated equine media';
  exception
    when insufficient_privilege then null;
  end;

  begin
    delete from public.equine_media;
    raise exception 'Authenticated role deleted equine media';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

set local role anon;
select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claims', '', true);

do $$
begin
  begin
    perform * from public.equines;
    raise exception 'Anonymous role selected equines';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform * from public.equines
     where visibility_status = 'PUBLIC';
    raise exception 'Anonymous role selected PUBLIC equines';
  exception
    when insufficient_privilege then null;
  end;

  begin
    insert into public.equines (name, equine_type)
    values ('Anon equine', 'HORSE');
    raise exception 'Anonymous role created an equine';
  exception
    when insufficient_privilege then null;
  end;

  begin
    update public.equines
       set visibility_status = 'PUBLIC';
    raise exception 'Anonymous role published an equine';
  exception
    when insufficient_privilege then null;
  end;

  begin
    delete from public.equines;
    raise exception 'Anonymous role deleted equines';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform * from public.equine_media;
    raise exception 'Anonymous role selected equine media';
  exception
    when insufficient_privilege then null;
  end;

  begin
    insert into public.equine_media (
      equine_id, storage_path, media_type
    ) values (
      current_setting('app.equine_id', true)::uuid,
      'equine-media/anon.jpg',
      'PHOTO'
    );
    raise exception 'Anonymous role inserted equine media';
  exception
    when insufficient_privilege then null;
  end;

  begin
    update public.equine_media
       set is_primary = true;
    raise exception 'Anonymous role updated equine media';
  exception
    when insufficient_privilege then null;
  end;

  begin
    delete from public.equine_media;
    raise exception 'Anonymous role deleted equine media';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

reset role;

do $$
declare
  acceptance_count integer;
  consent_count integer;
  storage_policies_present boolean := false;
begin
  select count(*) into acceptance_count
    from public.policy_acceptances
   where person_id = current_setting('app.caller_person', true)::uuid;

  if acceptance_count <> 0 then
    raise exception 'Equine workflow created policy acceptance';
  end if;

  select count(*) into consent_count
    from public.guardian_consents
   where granted_by_account_id in (
     select id from public.user_accounts
      where person_id = current_setting('app.caller_person', true)::uuid
   );

  if consent_count <> 0 then
    raise exception 'Equine workflow created guardian consent';
  end if;

  if has_table_privilege('anon', 'public.equines', 'select')
     or has_table_privilege('anon', 'public.equines', 'insert')
     or has_table_privilege('anon', 'public.equines', 'update')
     or has_table_privilege('anon', 'public.equines', 'delete')
     or has_table_privilege('authenticated', 'public.equines', 'select')
     or has_table_privilege('authenticated', 'public.equines', 'insert')
     or has_table_privilege('authenticated', 'public.equines', 'update')
     or has_table_privilege('authenticated', 'public.equines', 'delete')
     or has_table_privilege('anon', 'public.equine_media', 'select')
     or has_table_privilege('anon', 'public.equine_media', 'insert')
     or has_table_privilege('anon', 'public.equine_media', 'update')
     or has_table_privilege('anon', 'public.equine_media', 'delete')
     or has_table_privilege('authenticated', 'public.equine_media', 'select')
     or has_table_privilege('authenticated', 'public.equine_media', 'insert')
     or has_table_privilege('authenticated', 'public.equine_media', 'update')
     or has_table_privilege('authenticated', 'public.equine_media', 'delete') then
    raise exception 'Equine tables expose forbidden client privileges';
  end if;

  if to_regnamespace('storage') is not null then
    if to_regclass('storage.buckets') is not null
       and exists (
         select 1
           from storage.buckets
          where id = 'equine-media'
             or name = 'equine-media'
       ) then
      raise exception '011 must not create Storage bucket equine-media';
    end if;

    if to_regclass('storage.objects') is not null
       and exists (
         select 1
           from storage.objects
          where bucket_id = 'equine-media'
       ) then
      raise exception '011 must not create Storage objects in equine-media';
    end if;

    -- storage.policies is absent on current local Supabase (RLS on
    -- storage.objects instead). Do not reference it in a static query:
    -- PostgreSQL still parses FROM storage.policies when it is AND-ed with
    -- to_regclass(...). Look it up via EXECUTE only if the catalog has it.
    if to_regclass('storage.policies') is not null then
      execute $storage_policies$
        select exists (
          select 1
            from storage.policies as policy
           where to_jsonb(policy)->>'bucket_id' = 'equine-media'
              or coalesce(to_jsonb(policy)->>'name', '') ilike '%equine-media%'
              or to_jsonb(policy)::text ilike '%equine-media%'
        )
      $storage_policies$ into storage_policies_present;

      if storage_policies_present then
        raise exception '011 must not create Storage policies for equine-media';
      end if;
    end if;

    if to_regclass('storage.objects') is not null
       and exists (
         select 1
           from pg_catalog.pg_policy
          where polrelid = 'storage.objects'::regclass
            and (
              polname ilike '%equine-media%'
              or pg_catalog.pg_get_expr(polqual, polrelid) ilike '%equine-media%'
              or pg_catalog.pg_get_expr(polwithcheck, polrelid) ilike '%equine-media%'
            )
       ) then
      raise exception '011 must not create Storage RLS policies for equine-media';
    end if;
  end if;

  if exists (
    select 1
      from pg_catalog.pg_proc as procedure
      join pg_catalog.pg_namespace as namespace
        on namespace.oid = procedure.pronamespace
     where namespace.nspname = 'public'
       and procedure.proname like '%equine%'
       and (
         has_function_privilege('anon', procedure.oid, 'execute')
         or (
           has_function_privilege('authenticated', procedure.oid, 'execute')
           and procedure.proname not in (
             'list_my_equine_ownerships',
             'list_my_equine_management_assignments'
           )
         )
       )
  ) then
    raise exception 'Client execute was granted on an equine function';
  end if;
end;
$$;

rollback;
