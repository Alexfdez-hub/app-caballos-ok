-- Local test-operator surface for the operable Android MVP.
--
-- Authenticated callers can prepare TEST_ONLY centers, relations,
-- permissions, services, availability and an administered pilot only
-- while public.test_operator_gate.enabled is true. The migration
-- inserts that row as false. supabase/seed.sql enables it on a local
-- reset and is not applied to a hosted project.
--
-- The gate is not service_role and it is not a production backdoor.
-- Names and pilot codes must start with TEST_ONLY. A caller cannot
-- attach themselves to a center or equine they do not already
-- administer. Ownership, management and center affiliation stay
-- separate rows. Verification, payment, insurance and a numeric
-- welfare cap are not invented.
--
-- Remote application of this migration is not authorized by the
-- train that added the file.

create table public.test_operator_gate (
  singleton boolean primary key default true,
  enabled boolean not null default false,
  constraint test_operator_gate_singleton_check check (singleton)
);

insert into public.test_operator_gate (singleton, enabled) values (true, false);

comment on table public.test_operator_gate is
  'Single local switch. Migration leaves it false. Only a local seed turns it on. Not a client-writable role.';

alter table public.test_operator_gate enable row level security;
revoke all on table public.test_operator_gate from public, anon, authenticated, service_role;

create table public.test_operator_records (
  id uuid primary key default gen_random_uuid(),
  entity_type text not null,
  entity_id uuid not null,
  created_by_account_id uuid not null references public.user_accounts (id),
  created_at timestamptz not null default now(),
  constraint test_operator_records_type_check
    check (entity_type in ('CENTER', 'EQUINE', 'SERVICE', 'PILOT')),
  constraint test_operator_records_entity_key
    unique (entity_type, entity_id)
);

comment on table public.test_operator_records is
  'Registry of TEST_ONLY rows created through the local test-operator RPCs. Not a role, not a permission and not a client-readable roster. Retire keeps the row.';

alter table public.test_operator_records enable row level security;
revoke all on table public.test_operator_records from public, anon, authenticated, service_role;

create function public.assert_test_operator()
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
  resolved_account uuid;
  resolved_person uuid;
begin
  if not exists (
    select 1
      from public.test_operator_gate as gate
     where gate.enabled
  ) then
    raise exception using
      errcode = '42501',
      message = 'Test operator is local-only';
  end if;

  select caller.account_id, caller.person_id
    into resolved_account, resolved_person
    from public.resolve_session_caller() as caller;

  if not exists (
    select 1
      from public.user_accounts as account
      join public.persons as person
        on person.id = account.person_id
     where account.id = resolved_account
       and account.status = 'ACTIVE'
       and person.id = resolved_person
       and person.status = 'ACTIVE'
  ) then
    raise exception using
      errcode = '42501',
      message = 'Test operator is local-only';
  end if;

  account_id := resolved_account;
  person_id := resolved_person;
  return next;
end;
$$;

comment on function public.assert_test_operator() is
  'Local gate. Requires test_operator_gate.enabled plus an ACTIVE account and ACTIVE person. Not executable by clients.';

revoke all on function public.assert_test_operator()
  from public, anon, authenticated, service_role;

create function public.test_only_name(p_name text)
returns boolean
language sql
immutable
set search_path = pg_catalog
as $$
  select p_name is not null
    and p_name = btrim(p_name)
    and p_name ~ '^TEST_ONLY .+';
$$;

revoke all on function public.test_only_name(text)
  from public, anon, authenticated, service_role;

create function public.test_operator_slug(p_name text)
returns text
language sql
immutable
set search_path = pg_catalog
as $$
  select regexp_replace(
    regexp_replace(lower(btrim(p_name)), '[^a-z0-9]+', '-', 'g'),
    '(^-+|-+$)',
    '',
    'g'
  );
$$;

revoke all on function public.test_operator_slug(text)
  from public, anon, authenticated, service_role;

create function public.test_operator_remember(
  p_entity_type text,
  p_entity_id uuid,
  p_account_id uuid
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  insert into public.test_operator_records (
    entity_type, entity_id, created_by_account_id
  ) values (
    p_entity_type, p_entity_id, p_account_id
  )
  on conflict (entity_type, entity_id) do nothing;
end;
$$;

revoke all on function public.test_operator_remember(text, uuid, uuid)
  from public, anon, authenticated, service_role;

create function public.test_operator_available()
returns boolean
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  ignored record;
begin
  select *
    into ignored
    from public.assert_test_operator();
  return found;
exception
  when others then
    return false;
end;
$$;

comment on function public.test_operator_available() is
  'True only for an active signed-in caller while the local test gate is enabled. False on a hosted project. Does not grant authority.';

revoke all on function public.test_operator_available()
  from public, anon, authenticated, service_role;
grant execute on function public.test_operator_available() to authenticated;

create function public.create_test_center(
  p_name text,
  p_timezone text
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  actor_account uuid;
  actor_person uuid;
  center_id uuid;
  center_slug text;
begin
  select caller.account_id, caller.person_id
    into actor_account, actor_person
    from public.assert_test_operator() as caller;

  if not public.test_only_name(p_name) then
    raise exception using
      errcode = '22023',
      message = 'A test center name must start with TEST_ONLY';
  end if;

  if p_timezone is null or btrim(p_timezone) = '' then
    raise exception using
      errcode = '22023',
      message = 'A test center timezone is required';
  end if;

  center_slug := public.test_operator_slug(p_name);

  if center_slug is null or center_slug !~ '^[a-z0-9]+(-[a-z0-9]+)*$' then
    raise exception using
      errcode = '22023',
      message = 'A test center name cannot be turned into a slug';
  end if;

  if exists (
    select 1
      from public.equestrian_centers as center
     where center.slug = center_slug
  ) then
    raise exception using
      errcode = '22023',
      message = 'That test center name is already used';
  end if;

  insert into public.equestrian_centers (
    name,
    slug,
    country_code,
    timezone,
    verification_status,
    status
  )
  select
    p_name,
    center_slug,
    person.country_code,
    btrim(p_timezone),
    'UNVERIFIED',
    'ACTIVE'
  from public.persons as person
  where person.id = actor_person
    and person.country_code is not null
  returning id into center_id;

  if center_id is null then
    raise exception using
      errcode = '42501',
      message = 'Test operator is local-only';
  end if;

  insert into public.center_memberships (
    center_id, person_id, role_code, status
  ) values (
    center_id, actor_person, 'ADMIN', 'ACTIVE'
  );

  perform public.test_operator_remember('CENTER', center_id, actor_account);
  perform public.record_audit_event(
    'TEST_OPERATOR_CENTER_CREATED',
    'CENTER',
    center_id,
    jsonb_build_object('name', p_name)
  );

  return center_id;
end;
$$;

comment on function public.create_test_center(text, text) is
  'Creates one UNVERIFIED ACTIVE TEST_ONLY center and an ADMIN membership for the caller. Local gate only. Does not verify the center.';

revoke all on function public.create_test_center(text, text)
  from public, anon, authenticated, service_role;
grant execute on function public.create_test_center(text, text) to authenticated;

create function public.assign_test_center_role(
  p_center_id uuid,
  p_email text,
  p_role_code text
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
declare
  actor_account uuid;
  actor_person uuid;
  target_person uuid;
  membership_id uuid;
begin
  select caller.account_id, caller.person_id
    into actor_account, actor_person
    from public.assert_test_operator() as caller;

  if p_role_code not in ('ADMIN', 'MANAGER', 'INSTRUCTOR', 'ASSESSOR') then
    raise exception using
      errcode = '22023',
      message = 'That center role is not available';
  end if;

  if not exists (
    select 1
      from public.test_operator_records as record
      join public.equestrian_centers as center
        on center.id = record.entity_id
     where record.entity_type = 'CENTER'
       and record.entity_id = p_center_id
       and public.test_only_name(center.name)
  ) or not public.has_active_center_role(actor_person, p_center_id, 'ADMIN') then
    raise exception using
      errcode = '42501',
      message = 'Test operator operation is not available';
  end if;

  select account.person_id
    into target_person
    from auth.users as auth_user
    join public.user_accounts as account
      on account.auth_user_id = auth_user.id
    join public.persons as person
      on person.id = account.person_id
   where lower(auth_user.email) = lower(btrim(coalesce(p_email, '')))
     and account.status = 'ACTIVE'
     and person.status = 'ACTIVE';

  if target_person is null then
    raise exception using
      errcode = '22023',
      message = 'That test account is not available';
  end if;

  select membership.id
    into membership_id
    from public.center_memberships as membership
   where membership.center_id = p_center_id
     and membership.person_id = target_person
     and membership.role_code = p_role_code
     and membership.status = 'ACTIVE'
     and membership.ended_at is null;

  if membership_id is null then
    insert into public.center_memberships (
      center_id, person_id, role_code, status
    ) values (
      p_center_id, target_person, p_role_code, 'ACTIVE'
    )
    returning id into membership_id;
  end if;

  perform public.record_audit_event(
    'TEST_OPERATOR_ROLE_ASSIGNED',
    'CENTER_MEMBERSHIP',
    membership_id,
    jsonb_build_object('center_id', p_center_id, 'role_code', p_role_code)
  );

  return membership_id;
end;
$$;

comment on function public.assign_test_center_role(uuid, text, text) is
  'Adds an existing active person to a TEST_ONLY center the caller already administers. Idempotent for the same active role. Does not verify the person.';

revoke all on function public.assign_test_center_role(uuid, text, text)
  from public, anon, authenticated, service_role;
grant execute on function public.assign_test_center_role(uuid, text, text) to authenticated;

create function public.register_test_equine(p_equine_id uuid)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  actor_account uuid;
  actor_person uuid;
begin
  select caller.account_id, caller.person_id
    into actor_account, actor_person
    from public.assert_test_operator() as caller;

  if not exists (
    select 1
      from public.equines as equine
     where equine.id = p_equine_id
       and public.test_only_name(equine.name)
       and equine.status = 'ACTIVE'
  ) or not public.has_active_equine_management_role(
    actor_person, p_equine_id, 'PRIMARY_MANAGER'
  ) then
    raise exception using
      errcode = '42501',
      message = 'Test operator operation is not available';
  end if;

  perform public.test_operator_remember('EQUINE', p_equine_id, actor_account);
  perform public.record_audit_event(
    'TEST_OPERATOR_EQUINE_REGISTERED',
    'EQUINE',
    p_equine_id,
    '{}'::jsonb
  );

  return p_equine_id;
end;
$$;

comment on function public.register_test_equine(uuid) is
  'Registers an existing TEST_ONLY equine whose caller is already the primary manager. Does not transfer ownership or management.';

revoke all on function public.register_test_equine(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.register_test_equine(uuid) to authenticated;

create function public.assert_test_equine_admin(
  p_equine_id uuid,
  p_center_id uuid,
  p_person_id uuid
)
returns void
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
begin
  if not exists (
    select 1
      from public.test_operator_records as equine_record
      join public.equines as equine
        on equine.id = equine_record.entity_id
      join public.test_operator_records as center_record
        on center_record.entity_type = 'CENTER'
       and center_record.entity_id = p_center_id
      join public.equestrian_centers as center
        on center.id = center_record.entity_id
     where equine_record.entity_type = 'EQUINE'
       and equine_record.entity_id = p_equine_id
       and public.test_only_name(equine.name)
       and public.test_only_name(center.name)
  ) or not public.has_active_equine_management_role(
    p_person_id, p_equine_id, 'PRIMARY_MANAGER'
  ) or not public.has_active_center_role(
    p_person_id, p_center_id, 'ADMIN'
  ) then
    raise exception using
      errcode = '42501',
      message = 'Test operator operation is not available';
  end if;
end;
$$;

revoke all on function public.assert_test_equine_admin(uuid, uuid, uuid)
  from public, anon, authenticated, service_role;

create function public.assign_test_equine_to_center(
  p_equine_id uuid,
  p_center_id uuid,
  p_assignment_type text
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  actor_account uuid;
  actor_person uuid;
  assignment_id uuid;
begin
  select caller.account_id, caller.person_id
    into actor_account, actor_person
    from public.assert_test_operator() as caller;

  if p_assignment_type not in (
    'BOARDING', 'CENTER_OWNED', 'SCHOOL', 'TEMPORARY', 'OTHER'
  ) then
    raise exception using
      errcode = '22023',
      message = 'That assignment type is not available';
  end if;

  perform public.assert_test_equine_admin(p_equine_id, p_center_id, actor_person);

  select assignment.id
    into assignment_id
    from public.equine_center_assignments as assignment
   where assignment.equine_id = p_equine_id
     and assignment.center_id = p_center_id
     and assignment.assignment_type = p_assignment_type
     and assignment.status = 'ACTIVE'
     and assignment.ended_at is null;

  if assignment_id is null then
    insert into public.equine_center_assignments (
      equine_id, center_id, assignment_type, status
    ) values (
      p_equine_id, p_center_id, p_assignment_type, 'ACTIVE'
    )
    returning id into assignment_id;
  end if;

  perform public.record_audit_event(
    'TEST_OPERATOR_ASSIGNMENT',
    'EQUINE_CENTER_ASSIGNMENT',
    assignment_id,
    jsonb_build_object(
      'equine_id', p_equine_id,
      'center_id', p_center_id,
      'assignment_type', p_assignment_type
    )
  );

  return assignment_id;
end;
$$;

comment on function public.assign_test_equine_to_center(uuid, uuid, text) is
  'Center affiliation for a TEST_ONLY equine. Requires the caller to already be primary manager and center admin. Does not create ownership or a permission.';

revoke all on function public.assign_test_equine_to_center(uuid, uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.assign_test_equine_to_center(uuid, uuid, text)
  to authenticated;

create function public.grant_test_equine_permission(
  p_equine_id uuid,
  p_center_id uuid,
  p_permission_code text
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  actor_account uuid;
  actor_person uuid;
  permission_id uuid;
begin
  select caller.account_id, caller.person_id
    into actor_account, actor_person
    from public.assert_test_operator() as caller;

  if p_permission_code not in (
    'MANAGE_AVAILABILITY',
    'MANAGE_BOOKINGS',
    'ASSESS_RIDERS',
    'APPROVE_RIDERS',
    'MANAGE_REQUIREMENTS',
    'VIEW_ACTIVITY'
  ) then
    raise exception using
      errcode = '22023',
      message = 'That permission is not available';
  end if;

  perform public.assert_test_equine_admin(p_equine_id, p_center_id, actor_person);

  select permission.id
    into permission_id
    from public.equine_center_permissions as permission
   where permission.equine_id = p_equine_id
     and permission.center_id = p_center_id
     and permission.permission_code = p_permission_code
     and permission.status = 'ACTIVE'
     and permission.revoked_at is null;

  if permission_id is null then
    insert into public.equine_center_permissions (
      equine_id,
      center_id,
      granted_by_person_id,
      permission_code,
      status
    ) values (
      p_equine_id,
      p_center_id,
      actor_person,
      p_permission_code,
      'ACTIVE'
    )
    returning id into permission_id;
  end if;

  perform public.record_audit_event(
    'TEST_OPERATOR_PERMISSION',
    'EQUINE_CENTER_PERMISSION',
    permission_id,
    jsonb_build_object('permission_code', p_permission_code)
  );

  return permission_id;
end;
$$;

comment on function public.grant_test_equine_permission(uuid, uuid, text) is
  'Grants one frozen center-over-equine permission on a TEST_ONLY pair the caller already administers. Does not verify anyone.';

revoke all on function public.grant_test_equine_permission(uuid, uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.grant_test_equine_permission(uuid, uuid, text)
  to authenticated;

create function public.create_test_service(
  p_center_id uuid,
  p_name text,
  p_duration_minutes integer
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  actor_account uuid;
  actor_person uuid;
  service_id uuid;
begin
  select caller.account_id, caller.person_id
    into actor_account, actor_person
    from public.assert_test_operator() as caller;

  if not public.test_only_name(p_name)
     or p_duration_minutes is null
     or p_duration_minutes <= 0 then
    raise exception using
      errcode = '22023',
      message = 'A test service needs a TEST_ONLY name and a positive duration';
  end if;

  if not exists (
    select 1
      from public.test_operator_records as record
      join public.equestrian_centers as center
        on center.id = record.entity_id
     where record.entity_type = 'CENTER'
       and record.entity_id = p_center_id
       and public.test_only_name(center.name)
  ) or not public.has_active_center_role(actor_person, p_center_id, 'ADMIN') then
    raise exception using
      errcode = '42501',
      message = 'Test operator operation is not available';
  end if;

  insert into public.center_services (
    center_id,
    service_type,
    name,
    default_duration_minutes,
    status
  ) values (
    p_center_id,
    'EQUINE_SESSION',
    p_name,
    p_duration_minutes,
    'ACTIVE'
  )
  returning id into service_id;

  perform public.test_operator_remember('SERVICE', service_id, actor_account);
  perform public.record_audit_event(
    'TEST_OPERATOR_SERVICE',
    'CENTER_SERVICE',
    service_id,
    jsonb_build_object('duration_minutes', p_duration_minutes)
  );

  return service_id;
end;
$$;

comment on function public.create_test_service(uuid, text, integer) is
  'Creates one EQUINE_SESSION on a TEST_ONLY center. Duration slices the stored window. It is not a welfare maximum.';

revoke all on function public.create_test_service(uuid, text, integer)
  from public, anon, authenticated, service_role;
grant execute on function public.create_test_service(uuid, text, integer) to authenticated;

create function public.link_test_service_equine(
  p_service_id uuid,
  p_equine_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  actor_account uuid;
  actor_person uuid;
  center_id uuid;
  link_id uuid;
begin
  select caller.account_id, caller.person_id
    into actor_account, actor_person
    from public.assert_test_operator() as caller;

  select service.center_id
    into center_id
    from public.center_services as service
    join public.test_operator_records as record
      on record.entity_type = 'SERVICE'
     and record.entity_id = service.id
   where service.id = p_service_id
     and public.test_only_name(service.name);

  if center_id is null then
    raise exception using
      errcode = '42501',
      message = 'Test operator operation is not available';
  end if;

  perform public.assert_test_equine_admin(p_equine_id, center_id, actor_person);

  if not public.has_active_equine_center_permission(
    p_equine_id, center_id, 'MANAGE_REQUIREMENTS'
  ) then
    raise exception using
      errcode = '42501',
      message = 'Linking a service equine requires effective MANAGE_REQUIREMENTS at the service Center';
  end if;

  select link.id
    into link_id
    from public.service_equines as link
   where link.service_id = p_service_id
     and link.equine_id = p_equine_id;

  if link_id is null then
    insert into public.service_equines (
      service_id, equine_id, enabled, status, requirements
    ) values (
      p_service_id, p_equine_id, true, 'ACTIVE', '{}'::jsonb
    )
    returning id into link_id;
  end if;

  perform public.record_audit_event(
    'TEST_OPERATOR_SERVICE_LINK',
    'SERVICE_EQUINE',
    link_id,
    jsonb_build_object('service_id', p_service_id, 'equine_id', p_equine_id)
  );

  return link_id;
end;
$$;

comment on function public.link_test_service_equine(uuid, uuid) is
  'Links a TEST_ONLY service and equine. Requirements stay empty. Does not add an assessment, Zero Session or owner-approval rule.';

revoke all on function public.link_test_service_equine(uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.link_test_service_equine(uuid, uuid) to authenticated;

create function public.set_test_availability(
  p_equine_id uuid,
  p_center_id uuid,
  p_starts_at timestamptz,
  p_ends_at timestamptz
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  actor_account uuid;
  actor_person uuid;
  rule_id uuid;
begin
  select caller.account_id, caller.person_id
    into actor_account, actor_person
    from public.assert_test_operator() as caller;

  if p_starts_at is null or p_ends_at is null or p_ends_at <= p_starts_at then
    raise exception using
      errcode = '22023',
      message = 'Availability must end after it starts';
  end if;

  perform public.assert_test_equine_admin(p_equine_id, p_center_id, actor_person);

  if not public.has_active_equine_center_permission(
    p_equine_id, p_center_id, 'MANAGE_AVAILABILITY'
  ) then
    raise exception using
      errcode = '42501',
      message = 'Availability changes require effective MANAGE_AVAILABILITY for this equine at this Center';
  end if;

  insert into public.equine_availability_rules (
    equine_id,
    center_id,
    starts_at,
    ends_at,
    recurrence_rule,
    status,
    created_by_account_id
  ) values (
    p_equine_id,
    p_center_id,
    p_starts_at,
    p_ends_at,
    null,
    'ACTIVE',
    actor_account
  )
  returning id into rule_id;

  perform public.record_audit_event(
    'TEST_OPERATOR_AVAILABILITY',
    'EQUINE_AVAILABILITY_RULE',
    rule_id,
    jsonb_build_object('starts_at', p_starts_at, 'ends_at', p_ends_at)
  );

  return rule_id;
end;
$$;

comment on function public.set_test_availability(uuid, uuid, timestamptz, timestamptz) is
  'Stores one ACTIVE window. Recurrence is not expanded. The duration of a service is not a welfare limit.';

revoke all on function public.set_test_availability(uuid, uuid, timestamptz, timestamptz)
  from public, anon, authenticated, service_role;
grant execute on function public.set_test_availability(uuid, uuid, timestamptz, timestamptz)
  to authenticated;

create function public.add_test_calendar_block(
  p_equine_id uuid,
  p_center_id uuid,
  p_starts_at timestamptz,
  p_ends_at timestamptz,
  p_block_type text
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  actor_account uuid;
  actor_person uuid;
  block_id uuid;
begin
  select caller.account_id, caller.person_id
    into actor_account, actor_person
    from public.assert_test_operator() as caller;

  if p_block_type not in ('REST', 'VET', 'OWNER_USE', 'MANUAL_BLOCK') then
    raise exception using
      errcode = '22023',
      message = 'That block type is not available';
  end if;

  if p_starts_at is null or p_ends_at is null or p_ends_at <= p_starts_at then
    raise exception using
      errcode = '22023',
      message = 'A block must end after it starts';
  end if;

  perform public.assert_test_equine_admin(p_equine_id, p_center_id, actor_person);

  if not public.has_active_equine_center_permission(
    p_equine_id, p_center_id, 'MANAGE_AVAILABILITY'
  ) then
    raise exception using
      errcode = '42501',
      message = 'Calendar occupancy changes require effective MANAGE_AVAILABILITY for this equine at this Center';
  end if;

  insert into public.equine_calendar_blocks (
    equine_id,
    center_id,
    starts_at,
    ends_at,
    block_type,
    source_type,
    status,
    created_by_account_id
  ) values (
    p_equine_id,
    p_center_id,
    p_starts_at,
    p_ends_at,
    p_block_type,
    'MANUAL',
    'ACTIVE',
    actor_account
  )
  returning id into block_id;

  perform public.record_audit_event(
    'TEST_OPERATOR_BLOCK',
    'EQUINE_CALENDAR_BLOCK',
    block_id,
    jsonb_build_object('block_type', p_block_type)
  );

  return block_id;
end;
$$;

comment on function public.add_test_calendar_block(uuid, uuid, timestamptz, timestamptz, text) is
  'Manual occupancy. REST, VET, OWNER_USE and MANUAL_BLOCK are existing types. No numeric welfare maximum is applied.';

revoke all on function public.add_test_calendar_block(uuid, uuid, timestamptz, timestamptz, text)
  from public, anon, authenticated, service_role;
grant execute on function public.add_test_calendar_block(uuid, uuid, timestamptz, timestamptz, text)
  to authenticated;

create function public.mark_test_equine_visibility(
  p_equine_id uuid,
  p_visibility text
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  actor_account uuid;
  actor_person uuid;
begin
  select caller.account_id, caller.person_id
    into actor_account, actor_person
    from public.assert_test_operator() as caller;

  if p_visibility not in ('PRIVATE', 'PUBLIC') then
    raise exception using
      errcode = '22023',
      message = 'That visibility is not available';
  end if;

  if not exists (
    select 1
      from public.test_operator_records as record
      join public.equines as equine
        on equine.id = record.entity_id
     where record.entity_type = 'EQUINE'
       and record.entity_id = p_equine_id
       and public.test_only_name(equine.name)
  ) or not public.has_active_equine_management_role(
    actor_person, p_equine_id, 'PRIMARY_MANAGER'
  ) then
    raise exception using
      errcode = '42501',
      message = 'Test operator operation is not available';
  end if;

  update public.equines as equine
     set visibility_status = p_visibility,
         updated_at = now()
   where equine.id = p_equine_id;

  perform public.record_audit_event(
    'TEST_OPERATOR_VISIBILITY',
    'EQUINE',
    p_equine_id,
    jsonb_build_object('visibility_status', p_visibility)
  );
end;
$$;

comment on function public.mark_test_equine_visibility(uuid, text) is
  'Sets the stored visibility flag the derived offer read already requires. PUBLIC does not open a directory outside an OPEN pilot.';

revoke all on function public.mark_test_equine_visibility(uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.mark_test_equine_visibility(uuid, text) to authenticated;

create function public.open_test_bookable_pilot(
  p_pilot_code text,
  p_center_id uuid,
  p_equine_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  actor_account uuid;
  actor_person uuid;
  normalized_code text := upper(btrim(coalesce(p_pilot_code, '')));
  pilot_id uuid;
begin
  select caller.account_id, caller.person_id
    into actor_account, actor_person
    from public.assert_test_operator() as caller;

  if normalized_code !~ '^TEST_ONLY[A-Z0-9_-]{0,55}$' then
    raise exception using
      errcode = '22023',
      message = 'A test pilot code must start with TEST_ONLY';
  end if;

  perform public.assert_test_equine_admin(p_equine_id, p_center_id, actor_person);

  pilot_id := public.open_bookable_pilot(normalized_code);
  perform public.add_bookable_pilot_subject(pilot_id, p_center_id, p_equine_id);
  perform public.test_operator_remember('PILOT', pilot_id, actor_account);
  perform public.record_audit_event(
    'TEST_OPERATOR_PILOT_OPENED',
    'BOOKABLE_PILOT',
    pilot_id,
    jsonb_build_object(
      'pilot_code', normalized_code,
      'center_id', p_center_id,
      'equine_id', p_equine_id
    )
  );

  return pilot_id;
end;
$$;

comment on function public.open_test_bookable_pilot(text, uuid, uuid) is
  'Opens or reuses a TEST_ONLY administered pilot and admits one pair. A CLOSED code is not reopened. Does not publish outside that pilot.';

revoke all on function public.open_test_bookable_pilot(text, uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.open_test_bookable_pilot(text, uuid, uuid) to authenticated;

create function public.transfer_test_primary_manager(
  p_equine_id uuid,
  p_email text
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
declare
  actor_account uuid;
  actor_person uuid;
  target_person uuid;
  assignment_id uuid;
begin
  select caller.account_id, caller.person_id
    into actor_account, actor_person
    from public.assert_test_operator() as caller;

  if not exists (
    select 1
      from public.test_operator_records as record
      join public.equines as equine
        on equine.id = record.entity_id
     where record.entity_type = 'EQUINE'
       and record.entity_id = p_equine_id
       and public.test_only_name(equine.name)
  ) or not public.has_active_equine_management_role(
    actor_person, p_equine_id, 'PRIMARY_MANAGER'
  ) then
    raise exception using
      errcode = '42501',
      message = 'Test operator operation is not available';
  end if;

  select account.person_id
    into target_person
    from auth.users as auth_user
    join public.user_accounts as account
      on account.auth_user_id = auth_user.id
    join public.persons as person
      on person.id = account.person_id
   where lower(auth_user.email) = lower(btrim(coalesce(p_email, '')))
     and account.status = 'ACTIVE'
     and person.status = 'ACTIVE';

  if target_person is null or target_person = actor_person then
    raise exception using
      errcode = '22023',
      message = 'That test account is not available';
  end if;

  update public.equine_management_assignments as assignment
     set status = 'ENDED',
         valid_until = clock_timestamp()
   where assignment.equine_id = p_equine_id
     and assignment.manager_person_id = actor_person
     and assignment.management_role = 'PRIMARY_MANAGER'
     and assignment.status = 'ACTIVE'
     and assignment.valid_until is null;

  insert into public.equine_management_assignments (
    equine_id,
    manager_type,
    manager_person_id,
    management_role,
    status,
    granted_by_person_id
  ) values (
    p_equine_id,
    'PERSON',
    target_person,
    'PRIMARY_MANAGER',
    'ACTIVE',
    actor_person
  )
  returning id into assignment_id;

  perform public.record_audit_event(
    'TEST_OPERATOR_MANAGEMENT',
    'EQUINE_MANAGEMENT',
    assignment_id,
    jsonb_build_object('equine_id', p_equine_id)
  );

  return assignment_id;
end;
$$;

comment on function public.transfer_test_primary_manager(uuid, text) is
  'The current primary manager transfers that role. Ownership is unchanged. The target cannot call this on an equine they do not already manage.';

revoke all on function public.transfer_test_primary_manager(uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.transfer_test_primary_manager(uuid, text) to authenticated;

create function public.transfer_test_person_ownership(
  p_equine_id uuid,
  p_email text
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
declare
  actor_account uuid;
  actor_person uuid;
  target_person uuid;
  share numeric;
  ownership_id uuid;
begin
  select caller.account_id, caller.person_id
    into actor_account, actor_person
    from public.assert_test_operator() as caller;

  if not exists (
    select 1
      from public.test_operator_records as record
      join public.equines as equine
        on equine.id = record.entity_id
     where record.entity_type = 'EQUINE'
       and record.entity_id = p_equine_id
       and public.test_only_name(equine.name)
  ) then
    raise exception using
      errcode = '42501',
      message = 'Test operator operation is not available';
  end if;

  select ownership.ownership_percentage
    into share
    from public.equine_ownerships as ownership
   where ownership.equine_id = p_equine_id
     and ownership.owner_type = 'PERSON'
     and ownership.owner_person_id = actor_person
     and ownership.status = 'ACTIVE'
     and ownership.ended_at is null
     and ownership.started_at <= now();

  if share is null then
    raise exception using
      errcode = '42501',
      message = 'Test operator operation is not available';
  end if;

  select account.person_id
    into target_person
    from auth.users as auth_user
    join public.user_accounts as account
      on account.auth_user_id = auth_user.id
    join public.persons as person
      on person.id = account.person_id
   where lower(auth_user.email) = lower(btrim(coalesce(p_email, '')))
     and account.status = 'ACTIVE'
     and person.status = 'ACTIVE';

  if target_person is null or target_person = actor_person then
    raise exception using
      errcode = '22023',
      message = 'That test account is not available';
  end if;

  update public.equine_ownerships as ownership
     set status = 'ENDED',
         ended_at = clock_timestamp()
   where ownership.equine_id = p_equine_id
     and ownership.owner_person_id = actor_person
     and ownership.status = 'ACTIVE'
     and ownership.ended_at is null;

  insert into public.equine_ownerships (
    equine_id,
    owner_type,
    owner_person_id,
    ownership_percentage,
    status
  ) values (
    p_equine_id,
    'PERSON',
    target_person,
    share,
    'ACTIVE'
  )
  returning id into ownership_id;

  perform public.record_audit_event(
    'TEST_OPERATOR_OWNERSHIP',
    'EQUINE_OWNERSHIP',
    ownership_id,
    jsonb_build_object('equine_id', p_equine_id, 'ownership_percentage', share)
  );

  return ownership_id;
end;
$$;

comment on function public.transfer_test_person_ownership(uuid, text) is
  'Transfers the caller active PERSON share. It does not take a share the caller does not hold and it does not change management or center affiliation.';

revoke all on function public.transfer_test_person_ownership(uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.transfer_test_person_ownership(uuid, text) to authenticated;

create function public.list_test_operator_workspace()
returns table (
  kind text,
  entity_id uuid,
  label text
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  actor_account uuid;
  actor_person uuid;
begin
  select caller.account_id, caller.person_id
    into actor_account, actor_person
    from public.assert_test_operator() as caller;

  return query
  select
    'CENTER'::text,
    center.id,
    center.name
  from public.test_operator_records as record
  join public.equestrian_centers as center
    on center.id = record.entity_id
  where record.entity_type = 'CENTER'
    and public.has_active_center_role(actor_person, center.id, 'ADMIN')
  union all
  select
    'EQUINE'::text,
    equine.id,
    equine.name
  from public.test_operator_records as record
  join public.equines as equine
    on equine.id = record.entity_id
  where record.entity_type = 'EQUINE'
    and public.has_active_equine_management_role(
      actor_person, equine.id, 'PRIMARY_MANAGER'
    )
  union all
  select
    'SERVICE'::text,
    service.id,
    service.name
  from public.test_operator_records as record
  join public.center_services as service
    on service.id = record.entity_id
  where record.entity_type = 'SERVICE'
    and public.has_active_center_role(actor_person, service.center_id, 'ADMIN')
  order by 1, 3;
end;
$$;

comment on function public.list_test_operator_workspace() is
  'TEST_ONLY centers, equines and services the caller still administers. Empty when the local gate is off.';

revoke all on function public.list_test_operator_workspace()
  from public, anon, authenticated, service_role;
grant execute on function public.list_test_operator_workspace() to authenticated;

create function public.retire_test_operator_data()
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  actor_account uuid;
  actor_person uuid;
  pilot_row record;
  subject_row record;
begin
  select caller.account_id, caller.person_id
    into actor_account, actor_person
    from public.assert_test_operator() as caller;

  if not exists (
    select 1
      from public.test_operator_records as record
     where record.entity_type = 'CENTER'
       and public.has_active_center_role(actor_person, record.entity_id, 'ADMIN')
  ) then
    raise exception using
      errcode = '42501',
      message = 'Test operator operation is not available';
  end if;

  for pilot_row in
    select pilot.id
      from public.test_operator_records as record
      join public.bookable_pilots as pilot
        on pilot.id = record.entity_id
     where record.entity_type = 'PILOT'
       and pilot.pilot_code ~ '^TEST_ONLY'
       and pilot.status = 'OPEN'
  loop
    for subject_row in
      select subject.center_id, subject.equine_id
        from public.bookable_pilot_subjects as subject
       where subject.pilot_id = pilot_row.id
         and subject.status = 'ACTIVE'
         and subject.ended_at is null
    loop
      perform public.end_bookable_pilot_subject(
        pilot_row.id,
        subject_row.center_id,
        subject_row.equine_id
      );
    end loop;

    perform public.close_bookable_pilot(pilot_row.id);
  end loop;

  update public.equine_availability_rules as rule
     set status = 'INACTIVE'
   where rule.status = 'ACTIVE'
     and exists (
       select 1
         from public.test_operator_records as equine_record
         join public.test_operator_records as center_record
           on center_record.entity_type = 'CENTER'
          and center_record.entity_id = rule.center_id
        where equine_record.entity_type = 'EQUINE'
          and equine_record.entity_id = rule.equine_id
     );

  update public.equine_calendar_blocks as block
     set status = 'CANCELLED',
         cancelled_at = clock_timestamp()
   where block.status = 'ACTIVE'
     and block.source_type = 'MANUAL'
     and block.cancelled_at is null
     and exists (
       select 1
         from public.test_operator_records as equine_record
         join public.test_operator_records as center_record
           on center_record.entity_type = 'CENTER'
          and center_record.entity_id = block.center_id
        where equine_record.entity_type = 'EQUINE'
          and equine_record.entity_id = block.equine_id
     );

  update public.service_equines as link
     set status = 'INACTIVE',
         enabled = false
   where link.service_id in (
     select record.entity_id
       from public.test_operator_records as record
      where record.entity_type = 'SERVICE'
   );

  update public.equine_center_permissions as permission
     set status = 'REVOKED',
         revoked_at = clock_timestamp()
   where permission.status = 'ACTIVE'
     and permission.revoked_at is null
     and exists (
       select 1
         from public.test_operator_records as equine_record
         join public.test_operator_records as center_record
           on center_record.entity_type = 'CENTER'
          and center_record.entity_id = permission.center_id
        where equine_record.entity_type = 'EQUINE'
          and equine_record.entity_id = permission.equine_id
     );

  update public.equine_center_assignments as assignment
     set status = 'ENDED',
         ended_at = clock_timestamp()
   where assignment.status = 'ACTIVE'
     and assignment.ended_at is null
     and exists (
       select 1
         from public.test_operator_records as equine_record
         join public.test_operator_records as center_record
           on center_record.entity_type = 'CENTER'
          and center_record.entity_id = assignment.center_id
        where equine_record.entity_type = 'EQUINE'
          and equine_record.entity_id = assignment.equine_id
     );

  update public.center_services as service
     set status = 'INACTIVE',
         updated_at = now()
   where service.id in (
     select record.entity_id
       from public.test_operator_records as record
      where record.entity_type = 'SERVICE'
   );

  update public.equines as equine
     set visibility_status = 'PRIVATE',
         updated_at = now()
   where equine.id in (
     select record.entity_id
       from public.test_operator_records as record
      where record.entity_type = 'EQUINE'
   );

  update public.equestrian_centers as center
     set status = 'INACTIVE',
         updated_at = now()
   where center.id in (
     select record.entity_id
       from public.test_operator_records as record
      where record.entity_type = 'CENTER'
   )
     and public.test_only_name(center.name);

  update public.center_memberships as membership
     set status = 'ENDED',
         ended_at = clock_timestamp()
   where membership.status = 'ACTIVE'
     and membership.ended_at is null
     and membership.center_id in (
       select record.entity_id
         from public.test_operator_records as record
        where record.entity_type = 'CENTER'
     );

  perform public.record_audit_event(
    'TEST_OPERATOR_RETIRED',
    'TEST_OPERATOR',
    actor_account,
    '{}'::jsonb
  );
end;
$$;

comment on function public.retire_test_operator_data() is
  'Closes TEST_ONLY pilots and deactivates the registered rows. Does not delete audit_events, pilot history, persons or auth users. Booking occupancy blocks stay.';

revoke all on function public.retire_test_operator_data()
  from public, anon, authenticated, service_role;
grant execute on function public.retire_test_operator_data() to authenticated;

create function public.list_authorized_activity_results()
returns table (
  booking_id uuid,
  equine_name text,
  center_name text,
  starts_at timestamptz,
  ends_at timestamptz,
  booking_status text,
  session_status text,
  caller_relation text
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  current_auth_user_id uuid := auth.uid();
  caller_account uuid;
  caller_person uuid;
begin
  if current_auth_user_id is null then
    raise exception using
      errcode = '42501',
      message = 'Authentication required';
  end if;

  select account.id, account.person_id
    into caller_account, caller_person
    from public.user_accounts as account
    join public.persons as person
      on person.id = account.person_id
   where account.auth_user_id = current_auth_user_id
     and account.status = 'ACTIVE'
     and person.status = 'ACTIVE';

  if caller_account is null or caller_person is null then
    raise exception using
      errcode = '42501',
      message = 'Authentication required';
  end if;

  return query
  select
    booking.id,
    equine.name,
    center.name,
    booking.starts_at,
    booking.ends_at,
    booking.status,
    session.status,
    case
      when booking.participant_person_id = caller_person then 'PARTICIPANT'
      when booking.booked_by_account_id = caller_account then 'BOOKER'
      else 'VIEW_ACTIVITY'
    end
  from public.bookings as booking
  join public.equines as equine
    on equine.id = booking.equine_id
  join public.equestrian_centers as center
    on center.id = booking.center_id
  left join public.sessions as session
    on session.booking_id = booking.id
  where booking.participant_person_id = caller_person
     or booking.booked_by_account_id = caller_account
     or (
       public.has_active_center_role(caller_person, booking.center_id, 'ADMIN')
       and public.has_active_equine_center_permission(
         booking.equine_id, booking.center_id, 'VIEW_ACTIVITY'
       )
     )
     or (
       public.has_active_center_role(caller_person, booking.center_id, 'MANAGER')
       and public.has_active_equine_center_permission(
         booking.equine_id, booking.center_id, 'VIEW_ACTIVITY'
       )
     )
  order by booking.starts_at desc, booking.id;
end;
$$;

comment on function public.list_authorized_activity_results() is
  'Result read for the participant, the booking account, or a center ADMIN/MANAGER with effective VIEW_ACTIVITY. Does not return the other person, evidence, coordinates or policy snapshots. MANAGE_BOOKINGS alone does not list the row.';

revoke all on function public.list_authorized_activity_results()
  from public, anon, authenticated, service_role;
grant execute on function public.list_authorized_activity_results() to authenticated;
