-- Phase 14B consolidated P0 security / RLS regression covering 001–029.
-- Tests only: no 030_security_hardening.sql unless a defect is reproduced.
-- Runnable without psql meta-commands. Entire file is one rolled-back transaction.

begin;

-- ---------------------------------------------------------------------------
-- A. Catalog: RLS, privileges, SECURITY DEFINER search_path, Storage, races
-- ---------------------------------------------------------------------------

do $$
#variable_conflict use_variable
declare
  leaked text;
  missing_rls text;
  missing_path text;
  public_exec text;
  anon_exec text;
begin
  select string_agg(format('%I.%I', namespace.nspname, rel.relname), ', ' order by rel.relname)
    into missing_rls
    from pg_catalog.pg_class as rel
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = rel.relnamespace
   where namespace.nspname = 'public'
     and rel.relkind = 'r'
     and not rel.relrowsecurity;

  if missing_rls is not null then
    raise exception 'Public tables without RLS enabled: %', missing_rls;
  end if;

  -- FORCE RLS is not required: SECURITY DEFINER owners must write.
  -- Client roles are not table owners, so ENABLE is the client boundary.

  select string_agg(
           format('%I.%I %s', namespace.nspname, rel.relname, privilege.privilege_type),
           ', '
           order by rel.relname, privilege.privilege_type
         )
    into leaked
    from pg_catalog.pg_class as rel
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = rel.relnamespace
    cross join lateral aclexplode(coalesce(rel.relacl, acldefault('r', rel.relowner))) as privilege
   where namespace.nspname = 'public'
     and rel.relkind = 'r'
     and privilege.privilege_type in (
       'SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE'
     )
     and (
       privilege.grantee = 0
       or privilege.grantee in (
         select oid from pg_catalog.pg_roles
          where rolname in ('anon', 'authenticated')
       )
     );

  if leaked is not null then
    raise exception 'Client or PUBLIC DML grants on public tables: %', leaked;
  end if;

  select string_agg(
           format(
             '%s(%s)',
             procedure.proname,
             pg_catalog.pg_get_function_identity_arguments(procedure.oid)
           ),
           ', '
           order by procedure.proname
         )
    into missing_path
    from pg_catalog.pg_proc as procedure
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = procedure.pronamespace
    left join pg_catalog.pg_depend as depend
      on depend.objid = procedure.oid
     and depend.deptype = 'e'
   where namespace.nspname = 'public'
     and procedure.prosecdef
     and depend.objid is null
     and not coalesce(procedure.proconfig, array[]::text[])
       @> array['search_path=pg_catalog, public'];

  if missing_path is not null then
    raise exception 'SECURITY DEFINER functions missing fixed search_path: %', missing_path;
  end if;

  select string_agg(
           format(
             '%s(%s)',
             procedure.proname,
             pg_catalog.pg_get_function_identity_arguments(procedure.oid)
           ),
           ', '
           order by procedure.proname
         )
    into public_exec
    from pg_catalog.pg_proc as procedure
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = procedure.pronamespace
    left join pg_catalog.pg_depend as depend
      on depend.objid = procedure.oid
     and depend.deptype = 'e'
    cross join lateral aclexplode(
      coalesce(procedure.proacl, acldefault('f', procedure.proowner))
    ) as privilege
   where namespace.nspname = 'public'
     and procedure.prosecdef
     and depend.objid is null
     and privilege.privilege_type = 'EXECUTE'
     and privilege.grantee = 0;

  if public_exec is not null then
    raise exception 'SECURITY DEFINER functions executable by PUBLIC: %', public_exec;
  end if;

  select string_agg(
           format(
             '%s(%s)',
             procedure.proname,
             pg_catalog.pg_get_function_identity_arguments(procedure.oid)
           ),
           ', '
           order by procedure.proname
         )
    into anon_exec
    from pg_catalog.pg_proc as procedure
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = procedure.pronamespace
    left join pg_catalog.pg_depend as depend
      on depend.objid = procedure.oid
     and depend.deptype = 'e'
   where namespace.nspname = 'public'
     and procedure.prosecdef
     and depend.objid is null
     and has_function_privilege('anon', procedure.oid, 'EXECUTE');

  if anon_exec is not null then
    raise exception 'SECURITY DEFINER functions executable by anon: %', anon_exec;
  end if;

  if has_function_privilege(
       'authenticated',
       'public.record_audit_event(text,text,uuid,jsonb)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'public.set_audit_write(boolean)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'public.record_authenticated_audit_event(text,text,uuid,jsonb)',
       'EXECUTE'
     )
  then
    raise exception 'Audit writers must stay revoked from authenticated';
  end if;

  if not (
    select relrowsecurity
      from pg_catalog.pg_class
     where oid = 'storage.objects'::regclass
  ) then
    raise exception 'storage.objects RLS is not enabled';
  end if;

  if (
    select count(*) from storage.buckets
     where id in (
       'avatars',
       'equine-media',
       'qualification-documents',
       'session-evidence',
       'assessment-documents'
     )
       and public is distinct from false
  ) <> 0 then
    raise exception '027 target buckets must stay private';
  end if;

  if exists (
    select 1 from pg_catalog.pg_policy
     where polrelid = 'storage.objects'::regclass
       and (
         polname ilike '%avatar%'
         or polname ilike '%equine-media%'
         or pg_catalog.pg_get_expr(polqual, polrelid) ilike '%avatars%'
         or pg_catalog.pg_get_expr(polwithcheck, polrelid) ilike '%avatars%'
         or pg_catalog.pg_get_expr(polqual, polrelid) ilike '%equine-media%'
         or pg_catalog.pg_get_expr(polwithcheck, polrelid) ilike '%equine-media%'
       )
  ) then
    raise exception 'avatars and equine-media must stay deny-by-default';
  end if;

  if exists (
    select 1 from pg_catalog.pg_policy
     where polrelid = 'storage.objects'::regclass
       and polcmd in ('u', 'd', '*')
       and (
         polname like 'storage_027_%'
         or pg_catalog.pg_get_expr(polqual, polrelid) ilike '%session-evidence%'
         or pg_catalog.pg_get_expr(polwithcheck, polrelid) ilike '%session-evidence%'
         or pg_catalog.pg_get_expr(polqual, polrelid) ilike '%qualification-documents%'
         or pg_catalog.pg_get_expr(polwithcheck, polrelid) ilike '%assessment-documents%'
       )
  ) then
    raise exception '027 must not allow Storage upsert, move or delete';
  end if;

  if exists (
    select 1 from pg_catalog.pg_proc as procedure
      join pg_catalog.pg_namespace as namespace
        on namespace.oid = procedure.pronamespace
     where procedure.proname ~* '(signed_url|create_signed|service_role)'
       and namespace.nspname in ('public', 'storage')
  ) then
    raise exception 'Must not add a signed-URL or service_role helper';
  end if;

  if not exists (
    select 1 from pg_catalog.pg_constraint
     where conname = 'equine_calendar_blocks_active_overlap_excl'
       and contype = 'x'
  ) then
    raise exception '020 gist occupancy exclusion is missing';
  end if;

  if not exists (
    select 1
      from pg_catalog.pg_constraint as constraint_row
      join pg_catalog.pg_class as rel
        on rel.oid = constraint_row.conrelid
     where rel.relname = 'sessions'
       and constraint_row.contype = 'u'
       and pg_catalog.pg_get_constraintdef(constraint_row.oid) ilike '%booking_id%'
  ) then
    raise exception '023 one-session-per-booking unique is missing';
  end if;

  if not exists (
    select 1
      from pg_catalog.pg_constraint as constraint_row
      join pg_catalog.pg_class as rel
        on rel.oid = constraint_row.conrelid
     where rel.relname = 'reviews'
       and constraint_row.conname = 'reviews_booking_reviewer_subject_key'
  ) then
    raise exception '025 review uniqueness is missing';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- B. Compact domain fixture (market XA)
-- ---------------------------------------------------------------------------

insert into public.markets (country_code, status) values ('XA', 'ACTIVE');
insert into public.market_age_rules (
  country_code, legal_adult_age, guardian_consent_required, effective_from
) values ('XA', 18, true, date '2000-01-01');

insert into auth.users (id) values
  ('a3000000-0000-0000-0000-000000000001'),
  ('a3000000-0000-0000-0000-000000000002'),
  ('a3000000-0000-0000-0000-000000000003'),
  ('a3000000-0000-0000-0000-000000000004'),
  ('a3000000-0000-0000-0000-000000000005'),
  ('a3000000-0000-0000-0000-000000000006');

do $$
#variable_conflict use_variable
declare
  rider_id uuid;
  rider_account uuid;
  evaluator_id uuid;
  evaluator_account uuid;
  intruder_id uuid;
  intruder_account uuid;
  minor_id uuid;
  minor_account uuid;
  guardian_id uuid;
  guardian_account uuid;
  manager_id uuid;
  manager_account uuid;
  center_id constant uuid := 'a3000000-0000-0000-0000-00000000c001';
  equine_id constant uuid := 'a3000000-0000-0000-0000-00000000e001';
  service_id uuid;
  window_start timestamptz := timestamptz '2026-12-20 10:00:00+00';
begin
  select person_id, id into rider_id, rider_account
    from public.user_accounts
   where auth_user_id = 'a3000000-0000-0000-0000-000000000001';
  select person_id, id into evaluator_id, evaluator_account
    from public.user_accounts
   where auth_user_id = 'a3000000-0000-0000-0000-000000000002';
  select person_id, id into intruder_id, intruder_account
    from public.user_accounts
   where auth_user_id = 'a3000000-0000-0000-0000-000000000003';
  select person_id, id into minor_id, minor_account
    from public.user_accounts
   where auth_user_id = 'a3000000-0000-0000-0000-000000000004';
  select person_id, id into guardian_id, guardian_account
    from public.user_accounts
   where auth_user_id = 'a3000000-0000-0000-0000-000000000005';
  select person_id, id into manager_id, manager_account
    from public.user_accounts
   where auth_user_id = 'a3000000-0000-0000-0000-000000000006';

  update public.persons set
    first_name = 'Phase14B', last_name = 'Adult Rider',
    date_of_birth = date '1990-01-01'
   where id = rider_id;
  update public.persons set
    first_name = 'Phase14B', last_name = 'Evaluator',
    date_of_birth = date '1980-01-01'
   where id = evaluator_id;
  update public.persons set
    first_name = 'Phase14B', last_name = 'Intruder',
    date_of_birth = date '1985-01-01'
   where id = intruder_id;
  update public.persons set
    first_name = 'Phase14B', last_name = 'Minor Rider',
    date_of_birth = (current_date - interval '12 years')::date
   where id = minor_id;
  update public.persons set
    first_name = 'Phase14B', last_name = 'Guardian',
    date_of_birth = date '1980-01-01'
   where id = guardian_id;
  update public.persons set
    first_name = 'Phase14B', last_name = 'Manager',
    date_of_birth = date '1980-01-01'
   where id = manager_id;

  insert into public.equestrian_centers (
    id, name, slug, country_code, status
  ) values (
    center_id, 'Phase14B Center', 'phase14b-center', 'XA', 'ACTIVE'
  );

  insert into public.equines (id, name, equine_type, status)
  values (equine_id, 'phase14b-equine', 'HORSE', 'ACTIVE');

  insert into public.center_memberships (center_id, person_id, role_code)
  values
    (center_id, evaluator_id, 'ASSESSOR'),
    (center_id, manager_id, 'MANAGER');

  insert into public.equine_center_assignments (
    equine_id, center_id, assignment_type
  ) values (equine_id, center_id, 'SCHOOL');

  insert into public.equine_center_permissions (
    equine_id, center_id, granted_by_person_id, permission_code
  ) values
    (equine_id, center_id, manager_id, 'ASSESS_RIDERS'),
    (equine_id, center_id, manager_id, 'MANAGE_BOOKINGS'),
    (equine_id, center_id, manager_id, 'MANAGE_AVAILABILITY'),
    (equine_id, center_id, manager_id, 'MANAGE_REQUIREMENTS');

  insert into public.center_services (center_id, service_type, name)
  values (center_id, 'EQUINE_SESSION', 'Phase14B ride')
  returning id into service_id;

  insert into public.service_equines (service_id, equine_id, enabled, status)
  values (service_id, equine_id, true, 'ACTIVE');

  insert into public.equine_availability_rules (
    equine_id, center_id, starts_at, ends_at, created_by_account_id
  ) values (
    equine_id, center_id,
    timestamptz '2026-01-01 00:00:00+00',
    timestamptz '2028-01-01 00:00:00+00',
    manager_account
  );

  insert into public.policy_documents (
    id, policy_code, policy_type, market_code, locale, version,
    title, content, effective_from, effective_to, status, requires_reacceptance
  ) values
    (
      'a3000000-0000-0000-0000-00000000d001',
      'TERMS_XA', 'TERMS_OF_SERVICE', 'XA', 'es', '1',
      'Expired terms', 'Phase 14B expired terms body',
      now() - interval '30 days', now() - interval '1 day',
      'ACTIVE', false
    ),
    (
      'a3000000-0000-0000-0000-00000000d002',
      'TERMS_XA', 'TERMS_OF_SERVICE', 'XA', 'es', '2',
      'Current terms', 'Phase 14B current terms body',
      now() - interval '12 hours', null,
      'ACTIVE', false
    ),
    (
      'a3000000-0000-0000-0000-00000000d003',
      'GUARDIAN_XA', 'GUARDIAN_POLICY', 'XA', 'es', '1',
      'Guardian policy', 'Phase 14B guardian policy body',
      now() - interval '1 day', null,
      'ACTIVE', false
    ),
    (
      'a3000000-0000-0000-0000-00000000d004',
      'CENTER_XA', 'CENTER_POLICY', 'XA', 'es', '1',
      'Center policy', 'Phase 14B Center policy body',
      now() - interval '1 day', null,
      'ACTIVE', false
    );

  insert into public.policy_acceptances (
    policy_document_id, person_id, user_account_id, accepted_at
  ) values (
    'a3000000-0000-0000-0000-00000000d001',
    rider_id, rider_account, now() - interval '2 days'
  );

  insert into public.zero_sessions (
    id, rider_person_id, equine_id, center_id, requested_by_account_id,
    scheduled_at
  ) values (
    'a3000000-0000-0000-0000-00000000a001',
    rider_id, equine_id, center_id, rider_account,
    now() - interval '1 hour'
  );

  insert into public.guardian_relationships (
    id, guardian_person_id, minor_person_id, relationship_type,
    verification_status, verified_at
  ) values (
    'a3000000-0000-0000-0000-00000000f001',
    guardian_id, minor_id, 'LEGAL_GUARDIAN',
    'VERIFIED', now() - interval '1 day'
  );

  insert into public.bookings (
    id, participant_person_id, booked_by_account_id, equine_id, center_id,
    service_id, starts_at, ends_at, status
  ) values (
    'a3000000-0000-0000-0000-00000000b001',
    rider_id, rider_account, equine_id, center_id, service_id,
    window_start, window_start + interval '1 hour', 'REQUESTED'
  );

  perform set_config('app.rider_person_id', rider_id::text, true);
  perform set_config('app.rider_account_id', rider_account::text, true);
  perform set_config('app.evaluator_person_id', evaluator_id::text, true);
  perform set_config('app.evaluator_account_id', evaluator_account::text, true);
  perform set_config('app.intruder_person_id', intruder_id::text, true);
  perform set_config('app.intruder_account_id', intruder_account::text, true);
  perform set_config('app.minor_person_id', minor_id::text, true);
  perform set_config('app.minor_account_id', minor_account::text, true);
  perform set_config('app.guardian_person_id', guardian_id::text, true);
  perform set_config('app.guardian_account_id', guardian_account::text, true);
  perform set_config('app.manager_person_id', manager_id::text, true);
  perform set_config('app.manager_account_id', manager_account::text, true);
  perform set_config('app.center_id', center_id::text, true);
  perform set_config('app.equine_id', equine_id::text, true);
  perform set_config('app.service_id', service_id::text, true);
  perform set_config('app.window_start', window_start::text, true);
end;
$$;

create or replace function pg_temp.set_auth(p_auth_user_id uuid)
returns void
language plpgsql
as $$
begin
  if p_auth_user_id is null then
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claims', '{"role":"anon"}', true);
    return;
  end if;

  perform set_config('request.jwt.claim.sub', p_auth_user_id::text, true);
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', p_auth_user_id::text, 'role', 'authenticated')::text,
    true
  );
end;
$$;

create or replace function pg_temp.insert_storage_object(p_bucket text, p_name text)
returns void
language plpgsql
as $$
begin
  insert into storage.objects (bucket_id, name, owner, owner_id, metadata)
  values (
    p_bucket,
    p_name,
    auth.uid(),
    auth.uid()::text,
    jsonb_build_object('spoof_person', 'ignore-me')
  );
end;
$$;

grant execute on function pg_temp.set_auth(uuid) to authenticated, anon, postgres;
grant execute on function pg_temp.insert_storage_object(text, text)
  to authenticated, anon, postgres;

-- ---------------------------------------------------------------------------
-- C. Forced / illegal transitions and snapshot immutability (server role)
-- ---------------------------------------------------------------------------

do $$
declare
  audit_id uuid;
begin
  begin
    insert into public.bookings (
      participant_person_id, booked_by_account_id, equine_id, center_id,
      service_id, starts_at, ends_at, status, confirmed_at
    ) values (
      current_setting('app.rider_person_id')::uuid,
      current_setting('app.rider_account_id')::uuid,
      current_setting('app.equine_id')::uuid,
      current_setting('app.center_id')::uuid,
      current_setting('app.service_id')::uuid,
      current_setting('app.window_start')::timestamptz + interval '2 hours',
      current_setting('app.window_start')::timestamptz + interval '3 hours',
      'CONFIRMED', now()
    );
    raise exception 'Direct CONFIRMED booking insert was allowed';
  exception
    when insufficient_privilege then null;
  end;

  begin
    update public.bookings
       set status = 'CONFIRMED', confirmed_at = now()
     where id = 'a3000000-0000-0000-0000-00000000b001';
    raise exception 'Forced CONFIRMED update was allowed';
  exception
    when insufficient_privilege then null;
  end;

  begin
    insert into public.rider_assessments (
      rider_person_id, center_id, assessor_person_id, assessment_type
    ) values (
      current_setting('app.evaluator_person_id')::uuid,
      current_setting('app.center_id')::uuid,
      current_setting('app.evaluator_person_id')::uuid,
      'ACCESS_TEST'
    );
    raise exception 'Self-assessment was allowed';
  exception
    when check_violation then null;
  end;

  perform pg_temp.set_auth('a3000000-0000-0000-0000-000000000006');
  audit_id := public.record_audit_event(
    'security_gate',
    'booking',
    'a3000000-0000-0000-0000-00000000b001',
    jsonb_build_object('gate', '030')
  );
  perform pg_temp.set_auth(null);

  if audit_id is null then
    raise exception 'postgres must retain record_audit_event for server integrations';
  end if;

  begin
    update public.audit_events
       set metadata = jsonb_build_object('hack', true)
     where id = audit_id;
    raise exception 'Audit rewrite was allowed';
  exception
    when insufficient_privilege then null;
  end;

  begin
    delete from public.audit_events where id = audit_id;
    raise exception 'Audit delete was allowed';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

-- Overlapping ACTIVE occupancy must fail closed (double-booking race).
insert into public.equine_calendar_blocks (
  equine_id, center_id, starts_at, ends_at, block_type, source_type,
  source_id, created_by_account_id
) values (
  'a3000000-0000-0000-0000-00000000e001',
  'a3000000-0000-0000-0000-00000000c001',
  timestamptz '2026-12-20 10:00:00+00',
  timestamptz '2026-12-20 12:00:00+00',
  'MANUAL_BLOCK', 'MANUAL',
  'a3000000-0000-0000-0000-00000000b001',
  current_setting('app.manager_account_id')::uuid
);

do $$
begin
  begin
    insert into public.equine_calendar_blocks (
      equine_id, center_id, starts_at, ends_at, block_type, source_type,
      source_id, created_by_account_id
    ) values (
      'a3000000-0000-0000-0000-00000000e001',
      'a3000000-0000-0000-0000-00000000c001',
      timestamptz '2026-12-20 11:00:00+00',
      timestamptz '2026-12-20 13:00:00+00',
      'BOOKING', 'BOOKING',
      'a3000000-0000-0000-0000-00000000b001',
      current_setting('app.manager_account_id')::uuid
    );
    raise exception 'Overlapping ACTIVE calendar blocks were allowed';
  exception
    when exclusion_violation then null;
  end;
end;
$$;

-- Expired TERMS v1 acceptance must not satisfy current TERMS v2.
do $$
declare
  overall text;
begin
  select eligibility.overall_status
    into overall
    from public.collect_booking_eligibility(
      current_setting('app.rider_person_id')::uuid,
      current_setting('app.equine_id')::uuid,
      current_setting('app.center_id')::uuid,
      current_setting('app.window_start')::timestamptz,
      current_setting('app.window_start')::timestamptz + interval '1 hour',
      current_setting('app.service_id')::uuid,
      current_setting('app.rider_person_id')::uuid
    ) as eligibility
   where eligibility.requirement_type = 'POLICY_ACCEPTANCE'
   limit 1;

  if overall is distinct from 'NOT_ELIGIBLE' then
    raise exception 'Expired/non-current policy acceptance satisfied eligibility, got %', overall;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- D. Client table denials, audit CRUD, Storage deny-by-default
-- ---------------------------------------------------------------------------

reset role;
set local role authenticated;
select pg_temp.set_auth('a3000000-0000-0000-0000-000000000003');

do $$
begin
  begin
    perform * from public.persons;
    raise exception 'Authenticated selected persons';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform * from public.user_accounts;
    raise exception 'Authenticated selected user_accounts';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform * from public.equines;
    raise exception 'Authenticated selected equines';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform * from public.bookings;
    raise exception 'Authenticated selected bookings';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform * from public.guardian_relationships;
    raise exception 'Authenticated selected guardian_relationships';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform * from public.audit_events;
    raise exception 'Authenticated selected audit_events';
  exception
    when insufficient_privilege then null;
  end;

  begin
    insert into public.audit_events (
      event_type, entity_type, entity_id, metadata
    ) values (
      'spoofed', 'booking', 'a3000000-0000-0000-0000-00000000b001', '{}'::jsonb
    );
    raise exception 'Authenticated inserted audit_events';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform public.record_audit_event(
      'spoofed', 'booking', 'a3000000-0000-0000-0000-00000000b001', '{}'::jsonb
    );
    raise exception 'Authenticated executed record_audit_event';
  exception
    when insufficient_privilege then null;
  end;

  begin
    update public.zero_sessions
       set result = 'APPROVED'
     where id = 'a3000000-0000-0000-0000-00000000a001';
    raise exception 'Authenticated updated zero_sessions';
  exception
    when insufficient_privilege then null;
  end;

  if (
    select count(*) from public.list_my_guardian_relationships()
  ) <> 0 then
    raise exception 'Intruder listed another person''s guardian relationships';
  end if;

  begin
    perform * from public.grant_guardian_consent(
      'a3000000-0000-0000-0000-00000000f001',
      'EQUESTRIAN_ACTIVITY', 'GENERAL', 'v1', 'XA', null
    );
    raise exception 'Intruder granted consent on a foreign relationship';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform * from public.approve_zero_session(
      'a3000000-0000-0000-0000-00000000a001', 'APPROVED', null
    );
    raise exception 'Intruder approved a Zero Session';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform * from public.check_booking_eligibility(
      current_setting('app.rider_person_id')::uuid,
      current_setting('app.equine_id')::uuid,
      current_setting('app.center_id')::uuid,
      current_setting('app.window_start')::timestamptz,
      current_setting('app.window_start')::timestamptz + interval '1 hour',
      current_setting('app.service_id')::uuid
    );
    raise exception 'Intruder inspected another person''s eligibility';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform public.create_booking_request(
      current_setting('app.rider_person_id')::uuid,
      current_setting('app.equine_id')::uuid,
      current_setting('app.center_id')::uuid,
      current_setting('app.service_id')::uuid,
      current_setting('app.window_start')::timestamptz + interval '4 hours',
      current_setting('app.window_start')::timestamptz + interval '5 hours'
    );
    raise exception 'Intruder created a booking for another PERSON';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform pg_temp.insert_storage_object(
      'avatars',
      current_setting('app.intruder_person_id') || '/me.png'
    );
    raise exception 'Avatar upload was allowed';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform pg_temp.insert_storage_object(
      'equine-media',
      current_setting('app.equine_id') || '/front.jpg'
    );
    raise exception 'Equine-media upload was allowed';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

reset role;
set local role anon;
select pg_temp.set_auth(null);

do $$
begin
  begin
    perform * from public.persons;
    raise exception 'Anon selected persons';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform * from public.audit_events;
    raise exception 'Anon selected audit_events';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform * from public.approve_zero_session(
      'a3000000-0000-0000-0000-00000000a001', 'APPROVED', null
    );
    raise exception 'Anon approved a Zero Session';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform pg_temp.insert_storage_object('avatars', 'anon.png');
    raise exception 'Anon wrote avatars';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

-- Seed private objects as table owner, then prove clients cannot enumerate.
reset role;
select pg_temp.set_auth(null);

insert into storage.objects (bucket_id, name)
values
  ('avatars', 'a3000000-0000-0000-0000-000000000001/seed.png'),
  ('equine-media', 'a3000000-0000-0000-0000-00000000e001/seed.jpg');

set local role authenticated;
select pg_temp.set_auth('a3000000-0000-0000-0000-000000000001');

do $$
begin
  if exists (
    select 1 from storage.objects
     where bucket_id in ('avatars', 'equine-media')
  ) then
    raise exception 'Authenticated enumerated private avatar or equine-media';
  end if;
end;
$$;

-- Unconfirmed booking cannot start a session.
do $$
begin
  begin
    perform public.start_session('a3000000-0000-0000-0000-00000000b001');
    raise exception 'Unconfirmed booking started a session';
  exception
    when check_violation then null;
    when insufficient_privilege then null;
  end;
end;
$$;

-- ---------------------------------------------------------------------------
-- E. Guardian / minor consent: no substitute, no foreign grant, revoke works
-- ---------------------------------------------------------------------------

reset role;
set local role authenticated;
select pg_temp.set_auth('a3000000-0000-0000-0000-000000000004');

do $$
declare
  seen integer;
begin
  begin
    perform * from public.grant_guardian_consent(
      'a3000000-0000-0000-0000-00000000f001',
      'EQUESTRIAN_ACTIVITY', 'GENERAL', 'v1', 'XA', null
    );
    raise exception 'Minor granted their own guardian consent';
  exception
    when insufficient_privilege then null;
  end;

  select count(*) into seen from public.list_my_guardian_consents();
  if seen <> 0 then
    raise exception 'Minor listed guardian consents without a grant';
  end if;
end;
$$;

reset role;
set local role authenticated;
select pg_temp.set_auth('a3000000-0000-0000-0000-000000000005');

do $$
declare
  consent_row record;
  granted_id uuid;
begin
  select * into consent_row
    from public.check_guardian_consent(
      current_setting('app.minor_person_id')::uuid,
      'EQUESTRIAN_ACTIVITY',
      'GENERAL',
      'XA',
      current_date
    );

  if consent_row.consent_valid is not false then
    raise exception 'Missing consent was treated as valid';
  end if;

  -- Policy still required: grant without GUARDIAN_POLICY must fail.
  begin
    perform * from public.grant_guardian_consent(
      'a3000000-0000-0000-0000-00000000f001',
      'EQUESTRIAN_ACTIVITY', 'GENERAL', 'v1', 'XA', null
    );
    raise exception 'Grant succeeded without guardian policy acceptance';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

reset role;
insert into public.policy_acceptances (
  policy_document_id, person_id, user_account_id, accepted_at
) values (
  'a3000000-0000-0000-0000-00000000d003',
  current_setting('app.guardian_person_id')::uuid,
  current_setting('app.guardian_account_id')::uuid,
  now()
);

set local role authenticated;
select pg_temp.set_auth('a3000000-0000-0000-0000-000000000005');

do $$
declare
  granted_id uuid;
  consent_row record;
begin
  select id into granted_id
    from public.grant_guardian_consent(
      'a3000000-0000-0000-0000-00000000f001',
      'EQUESTRIAN_ACTIVITY', 'GENERAL', 'v1', 'XA', null
    );

  if granted_id is null then
    raise exception 'Authorized guardian grant failed';
  end if;

  perform public.revoke_guardian_consent(granted_id);

  select * into consent_row
    from public.check_guardian_consent(
      current_setting('app.minor_person_id')::uuid,
      'EQUESTRIAN_ACTIVITY',
      'GENERAL',
      'XA',
      current_date
    );

  if consent_row.consent_valid is not false then
    raise exception 'Revoked consent was still valid';
  end if;
end;
$$;

-- Center/assessor membership must never substitute guardian consent.
reset role;
set local role authenticated;
select pg_temp.set_auth('a3000000-0000-0000-0000-000000000002');

do $$
declare
  consent_row record;
begin
  begin
    select * into consent_row
      from public.check_guardian_consent(
        current_setting('app.minor_person_id')::uuid,
        'EQUESTRIAN_ACTIVITY',
        'GENERAL',
        'XA',
        current_date
      );
    if consent_row.consent_valid then
      raise exception 'Assessor check_guardian_consent treated a foreign minor as valid';
    end if;
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

reset role;
rollback;
