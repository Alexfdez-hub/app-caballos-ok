-- Phase 4B local equine–center relation tests.
-- Assumes migrations 001-013. Qualifications remain deferred.

begin;

do $$
declare
  fixture_auth uuid[] := array[
    '90000000-0000-0000-0000-000000000001'::uuid
  ];
  linked_person_ids uuid[];
  fixture_equine_ids uuid[];
  fixture_center_ids uuid[];
begin
  select coalesce(array_agg(id), '{}') into fixture_equine_ids
    from public.equines where name like 'phase4b-%';
  select coalesce(array_agg(id), '{}') into fixture_center_ids
    from public.equestrian_centers where slug like 'phase4b-%';

  delete from public.equine_center_permissions
   where equine_id = any(fixture_equine_ids) or center_id = any(fixture_center_ids);
  delete from public.equine_center_assignments
   where equine_id = any(fixture_equine_ids) or center_id = any(fixture_center_ids);
  delete from public.equine_management_assignments
   where equine_id = any(fixture_equine_ids);
  delete from public.equine_ownerships
   where equine_id = any(fixture_equine_ids);
  delete from public.equine_media where equine_id = any(fixture_equine_ids);
  delete from public.equines where id = any(fixture_equine_ids);
  delete from public.center_memberships
   where center_id = any(fixture_center_ids)
      or person_id in (select person_id from public.user_accounts where auth_user_id = any(fixture_auth));
  delete from public.center_languages where center_id = any(fixture_center_ids);
  delete from public.equestrian_centers where id = any(fixture_center_ids);
  delete from public.policy_acceptances
   where user_account_id in (select id from public.user_accounts where auth_user_id = any(fixture_auth));
  select coalesce(array_agg(person_id), '{}') into linked_person_ids
    from public.user_accounts where auth_user_id = any(fixture_auth);
  delete from public.user_accounts where auth_user_id = any(fixture_auth);
  delete from public.persons where id = any(linked_person_ids);
  delete from public.market_age_rules where country_code = 'ZG';
  delete from public.markets where country_code = 'ZG';
  delete from auth.users where id = any(fixture_auth);
end;
$$;

insert into public.markets (country_code, status) values ('ZG', 'ACTIVE');
insert into auth.users (id) values ('90000000-0000-0000-0000-000000000001');

do $$
declare
  caller_person_id uuid;
  fixture_equine_id uuid;
  second_equine_id uuid;
  fixture_center_id uuid;
  second_center_id uuid;
  permission_count integer;
begin
  if exists (
    select 1 from information_schema.tables
     where table_schema = 'public' and table_name in ('bookings')
  ) then
    raise exception 'Later domains must remain deferred';
  end if;

  if exists (
    select 1 from pg_catalog.pg_proc as procedure
      join pg_catalog.pg_namespace as namespace on namespace.oid = procedure.pronamespace
     where namespace.nspname = 'public'
       and procedure.proname in (
         'assign_equine_center',
         'grant_equine_center_permission',
         'revoke_equine_center_permission'
       )
  ) then
    raise exception 'Center relation mutation RPC must not exist';
  end if;

  if (
    select count(*) from pg_catalog.pg_class
     where oid in (
       'public.equine_center_assignments'::regclass,
       'public.equine_center_permissions'::regclass
     ) and relrowsecurity
  ) <> 2 then
    raise exception '013 RLS is not enabled';
  end if;

  if exists (
    select 1 from pg_catalog.pg_policy
     where polrelid in (
       'public.equine_center_assignments'::regclass,
       'public.equine_center_permissions'::regclass
     )
  ) then
    raise exception '013 tables unexpectedly gained client RLS policies';
  end if;

  select person_id into caller_person_id
    from public.user_accounts
   where auth_user_id = '90000000-0000-0000-0000-000000000001';

  insert into public.equestrian_centers (name, slug, country_code)
  values ('Phase4B Yard', 'phase4b-yard', 'ZG')
  returning id into fixture_center_id;

  insert into public.center_memberships (center_id, person_id, role_code)
  values (fixture_center_id, caller_person_id, 'ADMIN');

  insert into public.equestrian_centers (name, slug, country_code)
  values ('Phase4B Other Yard', 'phase4b-other-yard', 'ZG')
  returning id into second_center_id;

  insert into public.equines (name, equine_type)
  values ('phase4b-horse', 'HORSE')
  returning id into fixture_equine_id;

  insert into public.equines (name, equine_type)
  values ('phase4b-other', 'PONY')
  returning id into second_equine_id;

  insert into public.equine_ownerships (
    equine_id, owner_type, owner_person_id, ownership_percentage
  ) values (fixture_equine_id, 'PERSON', caller_person_id, 100);

  begin
    insert into public.equine_center_assignments (
      equine_id, center_id, assignment_type
    ) values (fixture_equine_id, fixture_center_id, 'PASTURE');
    raise exception 'Invalid assignment type was allowed';
  exception
    when check_violation then null;
  end;

  insert into public.equine_center_assignments (
    equine_id, center_id, assignment_type
  ) values (fixture_equine_id, fixture_center_id, 'BOARDING');

  insert into public.equine_center_assignments (
    equine_id, center_id, assignment_type
  ) values (fixture_equine_id, fixture_center_id, 'SCHOOL');

  begin
    insert into public.equine_center_assignments (
      equine_id, center_id, assignment_type
    ) values (fixture_equine_id, fixture_center_id, 'BOARDING');
    raise exception 'Duplicate active exact assignment was allowed';
  exception
    when unique_violation then null;
  end;

  select count(*) into permission_count
    from public.equine_center_permissions as permission
   where permission.equine_id = fixture_equine_id;

  if permission_count <> 0 then
    raise exception 'Assignment/membership/ownership created a permission';
  end if;

  begin
    insert into public.equine_center_permissions (
      equine_id, center_id, granted_by_person_id, permission_code
    ) values (fixture_equine_id, fixture_center_id, caller_person_id, 'PUBLISH');
    raise exception 'Invalid permission code was allowed';
  exception
    when check_violation then null;
  end;

  insert into public.equine_center_permissions (
    equine_id, center_id, granted_by_person_id, permission_code
  ) values (fixture_equine_id, fixture_center_id, caller_person_id, 'VIEW_ACTIVITY');

  begin
    insert into public.equine_center_permissions (
      equine_id, center_id, granted_by_person_id, permission_code
    ) values (fixture_equine_id, fixture_center_id, caller_person_id, 'VIEW_ACTIVITY');
    raise exception 'Duplicate active permission code was allowed';
  exception
    when unique_violation then null;
  end;

  if not public.has_active_equine_center_permission(
    fixture_equine_id, fixture_center_id, 'VIEW_ACTIVITY'
  ) then
    raise exception 'Explicit permission was not active';
  end if;

  if public.has_active_equine_center_permission(
    fixture_equine_id, fixture_center_id, 'MANAGE_BOOKINGS'
  ) then
    raise exception 'Ungranted permission was treated as active';
  end if;

  if public.has_active_equine_center_permission(
    second_equine_id, fixture_center_id, 'VIEW_ACTIVITY'
  ) then
    raise exception 'Permission applied to another equine';
  end if;

  if public.has_active_equine_center_permission(
    fixture_equine_id, second_center_id, 'VIEW_ACTIVITY'
  ) then
    raise exception 'Permission applied to another Center';
  end if;

  begin
    insert into public.equine_center_assignments (
      equine_id, center_id, assignment_type, status, started_at, ended_at
    ) values (
      second_equine_id, fixture_center_id, 'TEMPORARY', 'ENDED',
      timestamptz '2026-01-02 00:00:00+00',
      timestamptz '2026-01-01 00:00:00+00'
    );
    raise exception 'Assignment with ended_at before started_at was allowed';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.equine_center_permissions (
      equine_id, center_id, granted_by_person_id, permission_code,
      status, granted_at, revoked_at
    ) values (
      second_equine_id, fixture_center_id, caller_person_id, 'MANAGE_BOOKINGS',
      'REVOKED',
      timestamptz '2026-01-02 00:00:00+00',
      timestamptz '2026-01-01 00:00:00+00'
    );
    raise exception 'Permission with revoked_at before granted_at was allowed';
  exception
    when check_violation then null;
  end;

  insert into public.equine_center_assignments (
    equine_id, center_id, assignment_type, status, started_at, ended_at
  ) values (
    second_equine_id, fixture_center_id, 'TEMPORARY', 'ENDED',
    timestamptz '2025-01-01 00:00:00+00',
    timestamptz '2025-06-01 00:00:00+00'
  );

  if not exists (
    select 1
      from public.equine_center_assignments as assignment
     where assignment.equine_id = second_equine_id
       and assignment.center_id = fixture_center_id
       and assignment.assignment_type = 'TEMPORARY'
       and assignment.status = 'ENDED'
       and assignment.ended_at is not null
  ) then
    raise exception 'Valid historical ENDED assignment was not preserved';
  end if;

  insert into public.equine_center_permissions (
    equine_id, center_id, granted_by_person_id, permission_code,
    status, granted_at, revoked_at
  ) values (
    second_equine_id, fixture_center_id, caller_person_id, 'MANAGE_BOOKINGS',
    'REVOKED',
    timestamptz '2025-01-01 00:00:00+00',
    timestamptz '2025-06-01 00:00:00+00'
  );

  if not exists (
    select 1
      from public.equine_center_permissions as permission
     where permission.equine_id = second_equine_id
       and permission.center_id = fixture_center_id
       and permission.permission_code = 'MANAGE_BOOKINGS'
       and permission.status = 'REVOKED'
       and permission.revoked_at is not null
  ) then
    raise exception 'Valid historical REVOKED permission was not preserved';
  end if;

  if public.has_active_equine_center_permission(
    second_equine_id, fixture_center_id, 'MANAGE_BOOKINGS'
  ) then
    raise exception 'Revoked permission was treated as effective';
  end if;

  insert into public.equine_center_permissions (
    equine_id, center_id, granted_by_person_id, permission_code, granted_at
  ) values (
    second_equine_id, second_center_id, caller_person_id, 'VIEW_ACTIVITY',
    now() + interval '7 days'
  );

  if public.has_active_equine_center_permission(
    second_equine_id, second_center_id, 'VIEW_ACTIVITY'
  ) then
    raise exception 'Future permission was treated as effective';
  end if;

  if exists (
    select 1
      from pg_catalog.pg_constraint as constraint_row
     where constraint_row.conrelid in (
       'public.equine_center_assignments'::regclass,
       'public.equine_center_permissions'::regclass
     )
       and pg_catalog.pg_get_constraintdef(constraint_row.oid) ~* 'now\s*\('
  ) then
    raise exception 'Center-relation CHECK used now()';
  end if;

  update public.equine_center_assignments as assignment
     set status = 'ENDED',
         ended_at = now()
   where assignment.equine_id = fixture_equine_id
     and assignment.center_id = fixture_center_id
     and assignment.assignment_type = 'BOARDING';

  if not public.has_active_equine_center_permission(
    fixture_equine_id, fixture_center_id, 'VIEW_ACTIVITY'
  ) then
    raise exception 'Ending an assignment revoked an explicit permission';
  end if;

  perform set_config('app.caller_person', caller_person_id::text, true);
  perform set_config('app.equine_id', fixture_equine_id::text, true);
  perform set_config('app.center_id', fixture_center_id::text, true);
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claims', '{"sub":"90000000-0000-0000-0000-000000000001"}', true);

do $$
begin
  begin
    perform * from public.equine_center_assignments;
    raise exception 'Authenticated role selected assignments';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform * from public.equine_center_permissions;
    raise exception 'Authenticated role selected permissions';
  exception
    when insufficient_privilege then null;
  end;

  begin
    insert into public.equine_center_assignments (
      equine_id, center_id, assignment_type
    ) values (
      current_setting('app.equine_id', true)::uuid,
      current_setting('app.center_id', true)::uuid,
      'TEMPORARY'
    );
    raise exception 'Authenticated role inserted an assignment';
  exception
    when insufficient_privilege then null;
  end;

  begin
    insert into public.equine_center_permissions (
      equine_id, center_id, granted_by_person_id, permission_code
    ) values (
      current_setting('app.equine_id', true)::uuid,
      current_setting('app.center_id', true)::uuid,
      current_setting('app.caller_person', true)::uuid,
      'MANAGE_BOOKINGS'
    );
    raise exception 'Authenticated role inserted a permission';
  exception
    when insufficient_privilege then null;
  end;

  begin
    update public.equine_center_assignments
       set status = 'ENDED',
           ended_at = now();
    raise exception 'Authenticated role updated assignments';
  exception
    when insufficient_privilege then null;
  end;

  begin
    delete from public.equine_center_assignments;
    raise exception 'Authenticated role deleted assignments';
  exception
    when insufficient_privilege then null;
  end;

  begin
    update public.equine_center_permissions
       set status = 'REVOKED',
           revoked_at = now();
    raise exception 'Authenticated role updated permissions';
  exception
    when insufficient_privilege then null;
  end;

  begin
    delete from public.equine_center_permissions;
    raise exception 'Authenticated role deleted permissions';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform public.has_active_equine_center_permission(
      current_setting('app.equine_id', true)::uuid,
      current_setting('app.center_id', true)::uuid,
      'VIEW_ACTIVITY'
    );
    raise exception 'Authenticated role executed internal permission helper';
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
    perform * from public.equine_center_permissions;
    raise exception 'Anonymous role selected permissions';
  exception
    when insufficient_privilege then null;
  end;

  begin
    update public.equine_center_assignments
       set status = 'ENDED',
           ended_at = now();
    raise exception 'Anonymous role updated assignments';
  exception
    when insufficient_privilege then null;
  end;

  begin
    delete from public.equine_center_permissions;
    raise exception 'Anonymous role deleted permissions';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform public.has_active_equine_center_permission(
      current_setting('app.equine_id', true)::uuid,
      current_setting('app.center_id', true)::uuid,
      'VIEW_ACTIVITY'
    );
    raise exception 'Anonymous role executed internal permission helper';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

reset role;

do $$
begin
  if has_table_privilege('anon', 'public.equine_center_assignments', 'select')
     or has_table_privilege('anon', 'public.equine_center_assignments', 'insert')
     or has_table_privilege('authenticated', 'public.equine_center_assignments', 'select')
     or has_table_privilege('authenticated', 'public.equine_center_assignments', 'insert')
     or has_table_privilege('authenticated', 'public.equine_center_assignments', 'update')
     or has_table_privilege('authenticated', 'public.equine_center_assignments', 'delete')
     or has_table_privilege('anon', 'public.equine_center_permissions', 'select')
     or has_table_privilege('authenticated', 'public.equine_center_permissions', 'insert')
     or has_table_privilege('authenticated', 'public.equine_center_permissions', 'update')
     or has_table_privilege('authenticated', 'public.equine_center_permissions', 'delete')
     or has_function_privilege(
          'anon',
          'public.has_active_equine_center_permission(uuid,uuid,text)',
          'execute'
        )
     or has_function_privilege(
          'authenticated',
          'public.has_active_equine_center_permission(uuid,uuid,text)',
          'execute'
        )
     or exists (
          select 1
            from pg_catalog.pg_proc as procedure
            join pg_catalog.pg_namespace as namespace
              on namespace.oid = procedure.pronamespace
            cross join lateral aclexplode(
              coalesce(
                procedure.proacl,
                acldefault('f', procedure.proowner)
              )
            ) as grant_row
           where namespace.nspname = 'public'
             and procedure.proname = 'has_active_equine_center_permission'
             and grant_row.grantee = 0
             and grant_row.privilege_type = 'EXECUTE'
        )
  then
    raise exception '013 privileges are not deny-by-default';
  end if;
end;
$$;

rollback;
