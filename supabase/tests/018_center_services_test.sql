-- Phase 8B local center-services foundation tests.
-- Assumes migrations 001-018. Zero Session records remain deferred.
-- Runnable without psql meta-commands.

begin;

do $$
declare
  fixture_auth uuid[] := array[
    '95000000-0000-0000-0000-000000000001'::uuid,
    '95000000-0000-0000-0000-000000000002'::uuid
  ];
  linked_person_ids uuid[];
  fixture_center_ids uuid[];
  fixture_equine_ids uuid[];
  fixture_service_ids uuid[];
begin
  select coalesce(array_agg(id), '{}') into fixture_center_ids
    from public.equestrian_centers where slug like 'phase8b-%';
  select coalesce(array_agg(id), '{}') into fixture_equine_ids
    from public.equines where name like 'phase8b-%';
  select coalesce(array_agg(id), '{}') into fixture_service_ids
    from public.center_services where center_id = any(fixture_center_ids);

  delete from public.service_equines
   where service_id = any(fixture_service_ids)
      or equine_id = any(fixture_equine_ids);
  delete from public.center_services
   where id = any(fixture_service_ids);
  delete from public.equine_requirements
   where equine_id = any(fixture_equine_ids);
  delete from public.equine_center_permissions
   where equine_id = any(fixture_equine_ids);
  delete from public.equine_center_assignments
   where equine_id = any(fixture_equine_ids);
  delete from public.equine_management_assignments
   where equine_id = any(fixture_equine_ids);
  delete from public.equine_ownerships
   where equine_id = any(fixture_equine_ids);
  delete from public.equine_media where equine_id = any(fixture_equine_ids);
  delete from public.equines where id = any(fixture_equine_ids);
  delete from public.center_memberships
   where center_id = any(fixture_center_ids);
  delete from public.center_languages
   where center_id = any(fixture_center_ids);
  delete from public.equestrian_centers
   where id = any(fixture_center_ids);
  delete from public.policy_acceptances
   where user_account_id in (
     select id from public.user_accounts where auth_user_id = any(fixture_auth)
   );
  select coalesce(array_agg(person_id), '{}') into linked_person_ids
    from public.user_accounts where auth_user_id = any(fixture_auth);
  delete from public.user_accounts where auth_user_id = any(fixture_auth);
  delete from public.persons where id = any(linked_person_ids);
  delete from public.market_age_rules where country_code = 'ZL';
  delete from public.markets where country_code = 'ZL';
  delete from auth.users where id = any(fixture_auth);
end;
$$;

insert into public.markets (country_code, status) values ('ZL', 'ACTIVE');
insert into auth.users (id) values
  ('95000000-0000-0000-0000-000000000001'),
  ('95000000-0000-0000-0000-000000000002');

do $$
declare
  grantor_person_id uuid;
  member_person_id uuid;
  center_a_id uuid;
  center_b_id uuid;
  fixture_equine_id uuid;
  other_equine_id uuid;
  service_a_id uuid;
  service_b_id uuid;
  zero_service_id uuid;
  inactive_service_id uuid;
  kept_link_id uuid;
  cascade_link_id uuid;
  remaining_id uuid;
  remaining_count integer;
begin

  if exists (
    select 1 from pg_catalog.pg_proc as procedure
      join pg_catalog.pg_namespace as namespace
        on namespace.oid = procedure.pronamespace
     where namespace.nspname = 'public'
       and procedure.proname in (
         'create_center_service',
         'link_service_equine'
       )
  ) then
    raise exception 'Service mutation RPC must not exist';
  end if;

  if (
    select count(*) from pg_catalog.pg_class
     where oid in (
       'public.center_services'::regclass,
       'public.service_equines'::regclass
     ) and relrowsecurity
  ) <> 2 then
    raise exception '018 RLS is not enabled';
  end if;

  select person_id into grantor_person_id
    from public.user_accounts
   where auth_user_id = '95000000-0000-0000-0000-000000000001';
  select person_id into member_person_id
    from public.user_accounts
   where auth_user_id = '95000000-0000-0000-0000-000000000002';

  insert into public.equestrian_centers (name, slug, country_code, status)
  values ('Phase8B Alpha', 'phase8b-alpha', 'ZL', 'ACTIVE')
  returning id into center_a_id;
  insert into public.equestrian_centers (name, slug, country_code, status)
  values ('Phase8B Beta', 'phase8b-beta', 'ZL', 'ACTIVE')
  returning id into center_b_id;

  insert into public.center_memberships (
    center_id, person_id, role_code
  ) values (
    center_a_id, member_person_id, 'MANAGER'
  );

  insert into public.equines (name, equine_type)
  values ('phase8b-horse', 'HORSE')
  returning id into fixture_equine_id;
  insert into public.equines (name, equine_type)
  values ('phase8b-horse-other', 'HORSE')
  returning id into other_equine_id;

  insert into public.equine_center_assignments (
    equine_id, center_id, assignment_type
  ) values (
    fixture_equine_id, center_a_id, 'BOARDING'
  );

  begin
    insert into public.center_services (
      center_id, service_type, name
    ) values (
      center_a_id, 'TRAIL_RIDE', 'Bad type'
    );
    raise exception 'Invalid service type was allowed';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.center_services (
      center_id, service_type, name
    ) values (
      '95000000-0000-0000-0000-000000000099'::uuid,
      'EQUINE_SESSION',
      'Orphan'
    );
    raise exception 'Service with invalid center FK was allowed';
  exception
    when foreign_key_violation then null;
  end;

  begin
    insert into public.center_services (
      center_id, service_type, name, default_duration_minutes
    ) values (
      center_a_id, 'EQUINE_SESSION', 'Negative duration', 0
    );
    raise exception 'Non-positive service duration was allowed';
  exception
    when check_violation then null;
  end;

  insert into public.center_services (
    center_id, service_type, name, default_duration_minutes
  ) values (
    center_a_id, 'EQUINE_SESSION', 'Phase8B session', 45
  )
  returning id into service_a_id;

  if (
    select service.status
      from public.center_services as service
     where service.id = service_a_id
  ) is distinct from 'ACTIVE' then
    raise exception 'Default center_services status is not ACTIVE';
  end if;

  begin
    insert into public.center_services (
      center_id, service_type, name, status
    ) values (
      center_a_id, 'EQUINE_SESSION', 'Draft service', 'DRAFT'
    );
    raise exception 'Invalid center service status was allowed';
  exception
    when check_violation then null;
  end;

  insert into public.center_services (
    center_id, service_type, name, status
  ) values (
    center_a_id, 'EQUINE_SESSION', 'Phase8B inactive', 'INACTIVE'
  )
  returning id into inactive_service_id;

  insert into public.center_services (
    center_id, service_type, name
  ) values (
    center_b_id, 'RIDER_ASSESSMENT', 'Phase8B assessment'
  )
  returning id into service_b_id;

  insert into public.center_services (
    center_id, service_type, name
  ) values (
    center_a_id, 'ZERO_SESSION', 'Phase8B zero service kind'
  )
  returning id into zero_service_id;

  begin
    insert into public.service_equines (
      service_id, equine_id
    ) values (
      service_a_id, fixture_equine_id
    );
    raise exception 'Link without MANAGE_REQUIREMENTS was allowed';
  exception
    when insufficient_privilege then null;
  end;

  insert into public.equine_center_permissions (
    equine_id, center_id, granted_by_person_id, permission_code
  ) values (
    fixture_equine_id, center_a_id, grantor_person_id, 'ASSESS_RIDERS'
  );

  begin
    insert into public.service_equines (
      service_id, equine_id
    ) values (
      service_a_id, fixture_equine_id
    );
    raise exception 'ASSESS_RIDERS was treated as MANAGE_REQUIREMENTS';
  exception
    when insufficient_privilege then null;
  end;

  insert into public.equine_center_permissions (
    equine_id, center_id, granted_by_person_id, permission_code
  ) values (
    fixture_equine_id, center_b_id, grantor_person_id, 'MANAGE_REQUIREMENTS'
  );

  begin
    insert into public.service_equines (
      service_id, equine_id
    ) values (
      service_a_id, fixture_equine_id
    );
    raise exception 'Cross-center MANAGE_REQUIREMENTS was allowed to link';
  exception
    when insufficient_privilege then null;
  end;

  insert into public.equine_center_permissions (
    equine_id, center_id, granted_by_person_id, permission_code
  ) values (
    fixture_equine_id, center_a_id, grantor_person_id, 'MANAGE_REQUIREMENTS'
  );

  begin
    insert into public.service_equines (
      service_id, equine_id, duration_limit_minutes
    ) values (
      service_a_id, fixture_equine_id, -10
    );
    raise exception 'Non-positive duration_limit_minutes was allowed';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.service_equines (
      service_id, equine_id, requirements
    ) values (
      service_a_id, fixture_equine_id, '[]'::jsonb
    );
    raise exception 'Non-object requirements jsonb was allowed';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.service_equines (
      service_id, equine_id, authorization_policy
    ) values (
      service_a_id, fixture_equine_id, '   '
    );
    raise exception 'Blank authorization_policy was allowed';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.service_equines (
      service_id, equine_id
    ) values (
      '95000000-0000-0000-0000-000000000098'::uuid,
      fixture_equine_id
    );
    raise exception 'Link with invalid service FK was allowed';
  exception
    when foreign_key_violation then null;
    when insufficient_privilege then null;
  end;

  begin
    insert into public.service_equines (
      service_id, equine_id
    ) values (
      service_a_id,
      '95000000-0000-0000-0000-000000000097'::uuid
    );
    raise exception 'Link with invalid equine FK was allowed';
  exception
    when foreign_key_violation then null;
    when insufficient_privilege then null;
  end;

  insert into public.service_equines (
    service_id, equine_id, duration_limit_minutes, authorization_policy
  ) values (
    service_a_id, fixture_equine_id, 30, null
  )
  returning id into kept_link_id;

  if (
    select link.status
      from public.service_equines as link
     where link.id = kept_link_id
  ) is distinct from 'ACTIVE' then
    raise exception 'Default service_equines status is not ACTIVE';
  end if;

  update public.service_equines
     set status = 'INACTIVE'
   where id = kept_link_id;
  update public.service_equines
     set status = 'ACTIVE'
   where id = kept_link_id;

  begin
    update public.service_equines
       set status = 'DRAFT'
     where id = kept_link_id;
    raise exception 'Invalid service-equine status was allowed';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.service_equines (
      service_id, equine_id, status
    ) values (
      inactive_service_id, fixture_equine_id, 'ARCHIVED'
    );
    raise exception 'Invalid service-equine insert status was allowed';
  exception
    when check_violation then null;
  end;

  insert into public.service_equines (
    service_id, equine_id, status
  ) values (
    inactive_service_id, fixture_equine_id, 'INACTIVE'
  );

  update public.service_equines
     set enabled = false
   where id = kept_link_id;
  update public.service_equines
     set enabled = true
   where id = kept_link_id;

  begin
    insert into public.service_equines (
      service_id, equine_id
    ) values (
      service_a_id, fixture_equine_id
    );
    raise exception 'Duplicate service-equine was allowed';
  exception
    when unique_violation then null;
  end;

  begin
    update public.service_equines
       set service_id = service_b_id
     where id = kept_link_id;
    raise exception 'Service-equine service_id rewrite was allowed';
  exception
    when insufficient_privilege then null;
  end;

  begin
    update public.service_equines
       set equine_id = other_equine_id
     where id = kept_link_id;
    raise exception 'Service-equine equine_id rewrite was allowed';
  exception
    when insufficient_privilege then null;
  end;

  insert into public.service_equines (
    service_id, equine_id
  ) values (
    service_b_id, fixture_equine_id
  )
  returning id into cascade_link_id;

  delete from public.center_services
   where id = service_b_id;

  select count(*) into remaining_count
    from public.service_equines
   where id = cascade_link_id;
  if remaining_count <> 0 then
    raise exception 'Service-equine rows did not cascade on service delete';
  end if;

  select id into remaining_id
    from public.service_equines
   where id = kept_link_id;
  if remaining_id is null then
    raise exception 'Kept service-equine was removed by the other service delete';
  end if;

  if not exists (
    select 1 from public.center_services where id = zero_service_id
  ) then
    raise exception 'ZERO_SESSION service kind was not stored';
  end if;

  update public.equine_center_permissions
     set status = 'REVOKED',
         revoked_at = now()
   where equine_id = fixture_equine_id
     and center_id = center_a_id
     and permission_code = 'MANAGE_REQUIREMENTS'
     and status = 'ACTIVE';

  select id into remaining_id
    from public.service_equines
   where id = kept_link_id;
  if remaining_id is null then
    raise exception 'Historical service-equine was removed after permission revoke';
  end if;

  begin
    update public.service_equines
       set enabled = false
     where id = kept_link_id;
    raise exception 'Service-equine mutation after permission revoke was allowed';
  exception
    when insufficient_privilege then null;
  end;

  begin
    delete from public.service_equines
     where id = kept_link_id;
    raise exception 'Service-equine delete after permission revoke was allowed';
  exception
    when insufficient_privilege then null;
  end;

  perform set_config('app.center_id', center_a_id::text, true);
  perform set_config('app.service_id', service_a_id::text, true);
  perform set_config('app.equine_id', fixture_equine_id::text, true);
  perform set_config('app.link_id', kept_link_id::text, true);
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '95000000-0000-0000-0000-000000000002', true);
select set_config('request.jwt.claims', '{"sub":"95000000-0000-0000-0000-000000000002"}', true);

do $$
begin
  begin
    perform * from public.center_services;
    raise exception 'Authenticated role selected center services';
  exception
    when insufficient_privilege then null;
  end;

  begin
    insert into public.center_services (
      center_id, service_type, name
    ) values (
      current_setting('app.center_id', true)::uuid,
      'EQUINE_SESSION',
      'Client'
    );
    raise exception 'Authenticated role inserted a center service';
  exception
    when insufficient_privilege then null;
  end;

  begin
    insert into public.service_equines (
      service_id, equine_id
    ) values (
      current_setting('app.service_id', true)::uuid,
      current_setting('app.equine_id', true)::uuid
    );
    raise exception 'Authenticated role inserted a service equine';
  exception
    when insufficient_privilege then null;
  end;

  begin
    update public.service_equines set enabled = false;
    raise exception 'Authenticated role updated service equines';
  exception
    when insufficient_privilege then null;
  end;

  begin
    delete from public.center_services;
    raise exception 'Authenticated role deleted center services';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

reset role;

do $$
begin
  if has_table_privilege('anon', 'public.center_services', 'select')
     or has_table_privilege('authenticated', 'public.center_services', 'insert')
     or has_table_privilege('authenticated', 'public.service_equines', 'insert')
     or has_table_privilege('authenticated', 'public.service_equines', 'update')
     or has_function_privilege(
       'authenticated',
       'public.enforce_service_equine_manage_requirements()',
       'execute'
     )
  then
    raise exception '018 privileges are not deny-by-default';
  end if;
end;
$$;

rollback;
