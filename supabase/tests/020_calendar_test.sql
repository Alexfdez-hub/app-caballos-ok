-- Phase 10A local availability and calendar occupancy foundation tests.
-- Assumes migrations 001-020. Bookings, eligibility and sessions remain deferred.
-- ACTIVE same-equine overlapping tstzranges are incompatible.
-- MANAGE_AVAILABILITY is required; membership/assignment/ownership are not.
-- Runnable without psql meta-commands.

begin;

do $$
declare
  fixture_auth uuid[] := array[
    '97000000-0000-0000-0000-000000000001'::uuid,
    '97000000-0000-0000-0000-000000000002'::uuid,
    '97000000-0000-0000-0000-000000000003'::uuid
  ];
  linked_person_ids uuid[];
  fixture_center_ids uuid[];
  fixture_equine_ids uuid[];
begin
  select coalesce(array_agg(id), '{}') into fixture_center_ids
    from public.equestrian_centers where slug like 'phase10a-%';
  select coalesce(array_agg(id), '{}') into fixture_equine_ids
    from public.equines where name like 'phase10a-%';

  delete from public.equine_calendar_blocks
   where equine_id = any(fixture_equine_ids);
  delete from public.equine_availability_rules
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
  delete from public.market_age_rules where country_code = 'ZN';
  delete from public.markets where country_code = 'ZN';
  delete from auth.users where id = any(fixture_auth);
end;
$$;

insert into public.markets (country_code, status) values ('ZN', 'ACTIVE');
insert into auth.users (id) values
  ('97000000-0000-0000-0000-000000000001'),
  ('97000000-0000-0000-0000-000000000002'),
  ('97000000-0000-0000-0000-000000000003');

do $$
#variable_conflict use_variable
declare
  staff_person_id uuid;
  member_person_id uuid;
  owner_person_id uuid;
  staff_account_id uuid;
  member_account_id uuid;
  center_a_id uuid;
  center_b_id uuid;
  school_equine_id uuid;
  other_equine_id uuid;
  rule_id uuid;
  block_id uuid;
  window_start timestamptz := timestamptz '2026-10-01 10:00:00+00';
  window_end timestamptz := timestamptz '2026-10-01 12:00:00+00';
begin
  if exists (
    select 1 from information_schema.tables
     where table_schema = 'public'
       and table_name in (
         'sessions'
       )
  ) then
    raise exception 'Later domains must remain deferred';
  end if;

  if exists (
    select 1 from pg_catalog.pg_proc as procedure
      join pg_catalog.pg_namespace as namespace
        on namespace.oid = procedure.pronamespace
     where namespace.nspname = 'public'
       and procedure.proname in (
         'approve_zero_session'
       )
  ) then
    raise exception '020 must not add approve_zero_session';
  end if;

  if (
    select count(*) from pg_catalog.pg_class
     where oid in (
       'public.equine_availability_rules'::regclass,
       'public.equine_calendar_blocks'::regclass
     ) and relrowsecurity
  ) <> 2 then
    raise exception '020 RLS is not enabled';
  end if;

  if exists (
    select 1 from pg_catalog.pg_policy
     where polrelid in (
       'public.equine_availability_rules'::regclass,
       'public.equine_calendar_blocks'::regclass
     )
  ) then
    raise exception '020 tables unexpectedly gained client RLS policies';
  end if;

  if exists (
    select 1
      from information_schema.check_constraints as constraint_row
      join information_schema.constraint_column_usage as usage
        on usage.constraint_schema = constraint_row.constraint_schema
       and usage.constraint_name = constraint_row.constraint_name
     where constraint_row.constraint_schema = 'public'
       and usage.table_name in (
         'equine_availability_rules',
         'equine_calendar_blocks'
       )
       and constraint_row.check_clause ilike '%now()%'
  ) then
    raise exception '020 table CHECKs must not use now()';
  end if;

  select person_id, id into staff_person_id, staff_account_id
    from public.user_accounts
   where auth_user_id = '97000000-0000-0000-0000-000000000001';
  select person_id, id into member_person_id, member_account_id
    from public.user_accounts
   where auth_user_id = '97000000-0000-0000-0000-000000000002';
  select person_id into owner_person_id
    from public.user_accounts
   where auth_user_id = '97000000-0000-0000-0000-000000000003';

  insert into public.equestrian_centers (name, slug, country_code, status)
  values ('Phase10A Alpha', 'phase10a-alpha', 'ZN', 'ACTIVE')
  returning id into center_a_id;
  insert into public.equestrian_centers (name, slug, country_code, status)
  values ('Phase10A Beta', 'phase10a-beta', 'ZN', 'ACTIVE')
  returning id into center_b_id;

  insert into public.equines (name, equine_type)
  values ('phase10a-school', 'HORSE')
  returning id into school_equine_id;
  insert into public.equines (name, equine_type)
  values ('phase10a-other', 'HORSE')
  returning id into other_equine_id;

  insert into public.center_memberships (center_id, person_id, role_code)
  values (center_a_id, member_person_id, 'MANAGER');

  insert into public.equine_center_assignments (
    equine_id, center_id, assignment_type
  ) values (
    school_equine_id, center_a_id, 'SCHOOL'
  );

  insert into public.equine_ownerships (
    equine_id, owner_type, owner_person_id, ownership_percentage
  ) values (
    school_equine_id, 'PERSON', owner_person_id, 100
  );

  begin
    insert into public.equine_availability_rules (
      equine_id, center_id, starts_at, ends_at, created_by_account_id
    ) values (
      school_equine_id, center_a_id, window_start, window_end, member_account_id
    );
    raise exception 'MANAGER membership was treated as MANAGE_AVAILABILITY';
  exception
    when insufficient_privilege then null;
  end;

  begin
    insert into public.equine_calendar_blocks (
      equine_id, center_id, starts_at, ends_at, block_type, source_type,
      created_by_account_id
    ) values (
      school_equine_id, center_a_id, window_start, window_end,
      'VET', 'MANUAL', owner_person_id
    );
    raise exception 'PERSON ownership was treated as calendar authority';
  exception
    when foreign_key_violation then null;
    when insufficient_privilege then null;
  end;

  begin
    insert into public.equine_calendar_blocks (
      equine_id, center_id, starts_at, ends_at, block_type, source_type,
      created_by_account_id
    ) values (
      school_equine_id, center_a_id, window_start, window_end,
      'VET', 'MANUAL', member_account_id
    );
    raise exception 'Assignment or membership created occupancy';
  exception
    when insufficient_privilege then null;
  end;

  insert into public.equine_center_permissions (
    equine_id, center_id, granted_by_person_id, permission_code
  ) values (
    school_equine_id, center_a_id, staff_person_id, 'MANAGE_AVAILABILITY'
  );

  begin
    insert into public.equine_availability_rules (
      equine_id, center_id, starts_at, ends_at, created_by_account_id,
      recurrence_rule
    ) values (
      school_equine_id, center_a_id, window_start, window_end, staff_account_id,
      ' weekly '
    );
    raise exception 'Untrimmed recurrence_rule was allowed';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.equine_availability_rules (
      equine_id, center_id, starts_at, ends_at, created_by_account_id
    ) values (
      school_equine_id, center_a_id, window_end, window_start, staff_account_id
    );
    raise exception 'Availability ends_at <= starts_at was allowed';
  exception
    when check_violation then null;
  end;

  insert into public.equine_availability_rules (
    equine_id, center_id, starts_at, ends_at, created_by_account_id,
    recurrence_rule
  ) values (
    school_equine_id, center_a_id, window_start, window_end, staff_account_id,
    'FREQ=WEEKLY'
  ) returning id into rule_id;

  if not public.has_effective_equine_availability(
    school_equine_id, center_a_id,
    window_start + interval '30 minutes',
    window_end - interval '30 minutes'
  ) then
    raise exception 'Covered availability window was not effective';
  end if;

  if public.has_effective_equine_availability(
    school_equine_id, center_a_id,
    window_start - interval '1 hour',
    window_end
  ) then
    raise exception 'Rule was treated as covering time before starts_at';
  end if;

  begin
    insert into public.equine_calendar_blocks (
      equine_id, center_id, starts_at, ends_at, block_type, source_type,
      created_by_account_id
    ) values (
      school_equine_id, center_a_id, window_start, window_start,
      'VET', 'MANUAL', staff_account_id
    );
    raise exception 'Calendar ends_at = starts_at was allowed';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.equine_calendar_blocks (
      equine_id, center_id, starts_at, ends_at, block_type, source_type,
      created_by_account_id
    ) values (
      school_equine_id, center_a_id, window_start, window_end,
      'VET', 'BOOKING_REQUEST', staff_account_id
    );
    raise exception 'Unnamed calendar source_type was allowed';
  exception
    when check_violation then null;
  end;

  insert into public.equine_calendar_blocks (
    equine_id, center_id, starts_at, ends_at, block_type, source_type,
    source_id, created_by_account_id
  ) values (
    school_equine_id, center_a_id, window_start,
    window_start + interval '1 hour',
    'VET', 'MANUAL', '97000000-0000-4000-8000-0000000000aa',
    staff_account_id
  ) returning id into block_id;

  if not public.has_active_equine_calendar_overlap(
    school_equine_id,
    window_start + interval '15 minutes',
    window_start + interval '45 minutes'
  ) then
    raise exception 'Active VET block was not treated as occupancy';
  end if;

  begin
    insert into public.equine_calendar_blocks (
      equine_id, center_id, starts_at, ends_at, block_type, source_type,
      created_by_account_id
    ) values (
      school_equine_id, center_a_id,
      window_start + interval '30 minutes',
      window_start + interval '90 minutes',
      'LESSON', 'ACTIVITY', staff_account_id
    );
    raise exception 'Overlapping ACTIVE calendar blocks were allowed';
  exception
    when exclusion_violation then null;
  end;

  insert into public.equine_calendar_blocks (
    equine_id, center_id, starts_at, ends_at, block_type, source_type,
    created_by_account_id
  ) values (
    school_equine_id, center_a_id,
    window_start + interval '1 hour',
    window_start + interval '2 hours',
    'REST', 'MANUAL', staff_account_id
  );

  begin
    insert into public.equine_calendar_blocks (
      equine_id, center_id, starts_at, ends_at, block_type, source_type,
      created_by_account_id
    ) values (
      other_equine_id, center_a_id, window_start,
      window_start + interval '1 hour',
      'VET', 'MANUAL', staff_account_id
    );
    raise exception 'Calendar block without MANAGE_AVAILABILITY on other equine was allowed';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

do $$
#variable_conflict use_variable
declare
  staff_person_id uuid;
  staff_account_id uuid;
  center_a_id uuid;
  school_equine_id uuid;
  other_equine_id uuid;
  block_id uuid;
  window_start timestamptz := timestamptz '2026-10-01 10:00:00+00';
begin
  select person_id, id into staff_person_id, staff_account_id
    from public.user_accounts
   where auth_user_id = '97000000-0000-0000-0000-000000000001';
  select id into center_a_id
    from public.equestrian_centers where slug = 'phase10a-alpha';
  select id into school_equine_id
    from public.equines where name = 'phase10a-school';
  select id into other_equine_id
    from public.equines where name = 'phase10a-other';

  insert into public.equine_center_permissions (
    equine_id, center_id, granted_by_person_id, permission_code
  ) values (
    other_equine_id, center_a_id, staff_person_id, 'MANAGE_AVAILABILITY'
  );

  insert into public.equine_calendar_blocks (
    equine_id, center_id, starts_at, ends_at, block_type, source_type,
    created_by_account_id
  ) values (
    other_equine_id, center_a_id, window_start,
    window_start + interval '1 hour',
    'VET', 'SYSTEM', staff_account_id
  );

  if public.has_active_equine_calendar_overlap(
    other_equine_id, window_start, window_start + interval '1 hour'
  ) is not true then
    raise exception 'Other-equine ACTIVE block was not occupancy';
  end if;

  select id into block_id
    from public.equine_calendar_blocks
   where equine_id = school_equine_id
     and block_type = 'VET'
     and status = 'ACTIVE';

  update public.equine_center_permissions
     set status = 'REVOKED', revoked_at = now()
   where equine_id = school_equine_id
     and permission_code = 'MANAGE_AVAILABILITY'
     and status = 'ACTIVE';

  begin
    update public.equine_calendar_blocks
       set block_type = 'REST'
     where id = block_id;
    raise exception 'Calendar mutation after MANAGE_AVAILABILITY revoke was allowed';
  exception
    when insufficient_privilege then null;
  end;

  update public.equine_calendar_blocks
     set status = 'CANCELLED',
         cancelled_at = now()
   where id = block_id;

  if public.has_active_equine_calendar_overlap(
    school_equine_id, window_start, window_start + interval '1 hour'
  ) then
    raise exception 'Cancelled VET block is still occupancy';
  end if;

  insert into public.equine_center_permissions (
    equine_id, center_id, granted_by_person_id, permission_code
  ) values (
    school_equine_id, center_a_id, staff_person_id, 'MANAGE_AVAILABILITY'
  );

  insert into public.equine_calendar_blocks (
    equine_id, center_id, starts_at, ends_at, block_type, source_type,
    created_by_account_id
  ) values (
    school_equine_id, center_a_id, window_start,
    window_start + interval '1 hour',
    'LESSON', 'ACTIVITY', staff_account_id
  );

  begin
    update public.equine_calendar_blocks
       set equine_id = other_equine_id
     where id = block_id;
    raise exception 'Cancelled calendar identity was rewritten';
  exception
    when insufficient_privilege then null;
  end;

  begin
    delete from public.equine_calendar_blocks where id = block_id;
    raise exception 'Calendar block delete was allowed';
  exception
    when insufficient_privilege then null;
  end;

  perform set_config('app.center_a_id', center_a_id::text, true);
  perform set_config('app.school_equine_id', school_equine_id::text, true);
  perform set_config('app.staff_account_id', staff_account_id::text, true);
  perform set_config('app.window_start', window_start::text, true);
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '97000000-0000-0000-0000-000000000001', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"97000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);

do $$
begin
  begin
    perform * from public.equine_availability_rules;
    raise exception 'Authenticated role selected availability rules';
  exception
    when insufficient_privilege then null;
  end;

  begin
    insert into public.equine_availability_rules (
      equine_id, center_id, starts_at, ends_at, created_by_account_id
    ) values (
      current_setting('app.school_equine_id', true)::uuid,
      current_setting('app.center_a_id', true)::uuid,
      current_setting('app.window_start', true)::timestamptz,
      current_setting('app.window_start', true)::timestamptz + interval '1 hour',
      current_setting('app.staff_account_id', true)::uuid
    );
    raise exception 'Authenticated role inserted availability';
  exception
    when insufficient_privilege then null;
  end;

  begin
    update public.equine_availability_rules set status = 'INACTIVE';
    raise exception 'Authenticated role updated availability';
  exception
    when insufficient_privilege then null;
  end;

  begin
    delete from public.equine_availability_rules;
    raise exception 'Authenticated role deleted availability';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform * from public.equine_calendar_blocks;
    raise exception 'Authenticated role selected calendar blocks';
  exception
    when insufficient_privilege then null;
  end;

  begin
    insert into public.equine_calendar_blocks (
      equine_id, center_id, starts_at, ends_at, block_type, source_type,
      created_by_account_id
    ) values (
      current_setting('app.school_equine_id', true)::uuid,
      current_setting('app.center_a_id', true)::uuid,
      current_setting('app.window_start', true)::timestamptz,
      current_setting('app.window_start', true)::timestamptz + interval '1 hour',
      'MANUAL_BLOCK', 'MANUAL',
      current_setting('app.staff_account_id', true)::uuid
    );
    raise exception 'Authenticated role manufactured occupancy';
  exception
    when insufficient_privilege then null;
  end;

  begin
    update public.equine_calendar_blocks set status = 'CANCELLED';
    raise exception 'Authenticated role updated calendar blocks';
  exception
    when insufficient_privilege then null;
  end;

  begin
    delete from public.equine_calendar_blocks;
    raise exception 'Authenticated role deleted calendar blocks';
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
    perform * from public.equine_calendar_blocks;
    raise exception 'Anon selected calendar blocks';
  exception
    when insufficient_privilege then null;
  end;

  if has_table_privilege('anon', 'public.equine_availability_rules', 'select')
     or has_table_privilege('authenticated', 'public.equine_availability_rules', 'insert')
     or has_table_privilege('authenticated', 'public.equine_availability_rules', 'update')
     or has_table_privilege('authenticated', 'public.equine_availability_rules', 'delete')
     or has_table_privilege('anon', 'public.equine_calendar_blocks', 'select')
     or has_table_privilege('authenticated', 'public.equine_calendar_blocks', 'insert')
     or has_table_privilege('authenticated', 'public.equine_calendar_blocks', 'update')
     or has_table_privilege('authenticated', 'public.equine_calendar_blocks', 'delete')
  then
    raise exception '020 client table privileges must stay revoked';
  end if;

  if has_function_privilege(
       'anon',
       'public.has_effective_equine_availability(uuid,uuid,timestamptz,timestamptz)',
       'execute'
     )
     or has_function_privilege(
       'authenticated',
       'public.has_active_equine_calendar_overlap(uuid,timestamptz,timestamptz)',
       'execute'
     )
     or has_function_privilege(
       'authenticated',
       'public.enforce_equine_calendar_block_manage_authority()',
       'execute'
     )
  then
    raise exception '020 helpers must not be executable by clients';
  end if;
end;
$$;

reset role;

do $$
declare
  remaining_count integer;
begin
  select count(*) into remaining_count
    from public.equine_calendar_blocks
   where equine_id in (
     select id from public.equines where name like 'phase10a-%'
   );
  if remaining_count < 1 then
    raise exception 'Historical calendar occupancy was lost';
  end if;
end;
$$;

rollback;
