-- Phase 9B approve_zero_session security and business regressions.
-- Assumes migrations 001-028. Runnable without psql meta-commands.

begin;

insert into public.markets (country_code, status)
values ('Z8', 'ACTIVE');

insert into public.market_age_rules (
  country_code, legal_adult_age, guardian_consent_required, effective_from
) values ('Z8', 18, true, date '2000-01-01');

insert into auth.users (id) values
  ('98000000-0000-0000-0000-000000000001'),
  ('98000000-0000-0000-0000-000000000002'),
  ('98000000-0000-0000-0000-000000000003'),
  ('98000000-0000-0000-0000-000000000004'),
  ('98000000-0000-0000-0000-000000000005'),
  ('98000000-0000-0000-0000-000000000006');

do $$
#variable_conflict use_variable
declare
  rider_id uuid;
  evaluator_id uuid;
  intruder_id uuid;
  minor_id uuid;
  guardian_id uuid;
  manager_id uuid;
  rider_account_id uuid;
  minor_account_id uuid;
  center_id constant uuid := '98000000-0000-0000-0000-00000000c001';
  equine_id constant uuid := '98000000-0000-0000-0000-00000000e001';
begin
  select person_id, id into rider_id, rider_account_id
    from public.user_accounts
   where auth_user_id = '98000000-0000-0000-0000-000000000001';
  select person_id into evaluator_id
    from public.user_accounts
   where auth_user_id = '98000000-0000-0000-0000-000000000002';
  select person_id into intruder_id
    from public.user_accounts
   where auth_user_id = '98000000-0000-0000-0000-000000000003';
  select person_id, id into minor_id, minor_account_id
    from public.user_accounts
   where auth_user_id = '98000000-0000-0000-0000-000000000004';
  select person_id into guardian_id
    from public.user_accounts
   where auth_user_id = '98000000-0000-0000-0000-000000000005';
  select person_id into manager_id
    from public.user_accounts
   where auth_user_id = '98000000-0000-0000-0000-000000000006';

  update public.persons set
    first_name = 'Phase9B', last_name = 'Adult Rider',
    date_of_birth = date '1990-01-01'
   where id = rider_id;
  update public.persons set
    first_name = 'Phase9B', last_name = 'Evaluator',
    date_of_birth = date '1980-01-01'
   where id = evaluator_id;
  update public.persons set
    first_name = 'Phase9B', last_name = 'Intruder',
    date_of_birth = date '1985-01-01'
   where id = intruder_id;
  update public.persons set
    first_name = 'Phase9B', last_name = 'Minor Rider',
    date_of_birth = (current_date - interval '12 years')::date
   where id = minor_id;
  update public.persons set
    first_name = 'Phase9B', last_name = 'Guardian',
    date_of_birth = date '1980-01-01'
   where id = guardian_id;
  update public.persons set
    first_name = 'Phase9B', last_name = 'Manager',
    date_of_birth = date '1980-01-01'
   where id = manager_id;

  insert into public.equestrian_centers (
    id, name, slug, country_code, status
  ) values (
    center_id, 'Phase9B Center', 'phase9b-center', 'Z8', 'ACTIVE'
  );

  insert into public.equines (id, name, equine_type, status)
  values (equine_id, 'phase9b-equine', 'HORSE', 'ACTIVE');

  insert into public.center_memberships (center_id, person_id, role_code)
  values
    (center_id, evaluator_id, 'ASSESSOR'),
    (center_id, manager_id, 'MANAGER');

  insert into public.equine_center_permissions (
    equine_id, center_id, granted_by_person_id, permission_code
  ) values (equine_id, center_id, manager_id, 'ASSESS_RIDERS');

  insert into public.zero_sessions (
    id, rider_person_id, equine_id, center_id, requested_by_account_id,
    scheduled_at
  ) values
    (
      '98000000-0000-0000-0000-00000000a001', rider_id, equine_id,
      center_id, rider_account_id, now() - interval '1 hour'
    ),
    (
      '98000000-0000-0000-0000-00000000a002', minor_id, equine_id,
      center_id, minor_account_id, now() - interval '1 hour'
    ),
    (
      '98000000-0000-0000-0000-00000000a003', rider_id, equine_id,
      center_id, rider_account_id, now() + interval '1 day'
    ),
    (
      '98000000-0000-0000-0000-00000000a004', rider_id, equine_id,
      center_id, rider_account_id, now() - interval '1 hour'
    );

  insert into public.policy_documents (
    id, policy_code, policy_type, market_code, locale, version,
    title, content, effective_from, status, requires_reacceptance
  ) values (
    '98000000-0000-0000-0000-00000000d001',
    'CENTER_Z8', 'CENTER_POLICY', 'Z8', 'es', '1',
    'Center policy', 'Phase 9B Center policy',
    now() - interval '1 day', 'ACTIVE', false
  );

  if guardian_id is null then
    raise exception 'Guardian fixture was not provisioned';
  end if;
end;
$$;

do $$
declare
  function_oid oid := 'public.approve_zero_session(uuid,text,text)'::regprocedure;
begin
  if not exists (
    select 1
      from pg_catalog.pg_proc as procedure
     where procedure.oid = function_oid
       and procedure.prosecdef
       and procedure.proconfig @> array['search_path=pg_catalog, public']
  ) then
    raise exception 'approve_zero_session is not hardened SECURITY DEFINER';
  end if;

  if has_function_privilege('anon', function_oid, 'EXECUTE')
     or not has_function_privilege('authenticated', function_oid, 'EXECUTE') then
    raise exception 'approve_zero_session grants are not least privilege';
  end if;

  if has_table_privilege('authenticated', 'public.zero_sessions', 'UPDATE') then
    raise exception 'authenticated unexpectedly has direct Zero Session UPDATE';
  end if;
end;
$$;

set local role anon;
do $$
begin
  perform * from public.approve_zero_session(
    '98000000-0000-0000-0000-00000000a001', 'APPROVED', null
  );
  raise exception 'Anon approval was allowed';
exception
  when insufficient_privilege then null;
end;
$$;
reset role;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"98000000-0000-0000-0000-000000000003","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '98000000-0000-0000-0000-000000000003',
  true
);
do $$
begin
  perform * from public.approve_zero_session(
    '98000000-0000-0000-0000-00000000a001', 'APPROVED', null
  );
  raise exception 'Unrelated caller approved a Zero Session';
exception
  when insufficient_privilege then null;
end;
$$;

select set_config(
  'request.jwt.claims',
  '{"sub":"98000000-0000-0000-0000-000000000002","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '98000000-0000-0000-0000-000000000002',
  true
);

do $$
begin
  perform * from public.approve_zero_session(
    '98000000-0000-0000-0000-00000000a003', 'APPROVED', null
  );
  raise exception 'Future Zero Session approval was allowed';
exception
  when object_not_in_prerequisite_state then null;
end;
$$;

do $$
begin
  perform * from public.approve_zero_session(
    '98000000-0000-0000-0000-00000000a001', 'APPROVED', null
  );
  raise exception 'Approval without required Center policy was allowed';
exception
  when insufficient_privilege then null;
end;
$$;
reset role;

insert into public.policy_acceptances (
  policy_document_id, person_id, user_account_id, accepted_at
)
select
  '98000000-0000-0000-0000-00000000d001', account.person_id,
  account.id, now()
from public.user_accounts as account
where account.auth_user_id = '98000000-0000-0000-0000-000000000002';

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"98000000-0000-0000-0000-000000000002","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '98000000-0000-0000-0000-000000000002',
  true
);

do $$
begin
  perform * from public.approve_zero_session(
    '98000000-0000-0000-0000-00000000a002', 'APPROVED', null
  );
  raise exception 'Minor Zero Session without consent was approved';
exception
  when insufficient_privilege then null;
end;
$$;

do $$
begin
  perform * from public.approve_zero_session(
    '98000000-0000-0000-0000-00000000a001', 'REJECTED', null
  );
  raise exception 'Non-approval result was accepted';
exception
  when invalid_parameter_value then null;
end;
$$;

do $$
declare
  approved record;
  replayed record;
  auth_count integer;
begin
  select * into approved
    from public.approve_zero_session(
      '98000000-0000-0000-0000-00000000a001',
      'APPROVED',
      'Safe with evaluator'
    );

  if approved.result <> 'APPROVED'
     or approved.evaluator_person_id is null
     or approved.performed_at is null then
    raise exception 'Server approval facts were not persisted';
  end if;

  select * into replayed
    from public.approve_zero_session(
      '98000000-0000-0000-0000-00000000a001',
      'APPROVED',
      'Safe with evaluator'
    );

  if replayed.performed_at is distinct from approved.performed_at
     or replayed.evaluator_person_id is distinct from approved.evaluator_person_id then
    raise exception 'Exact replay changed historical approval facts';
  end if;

  select count(*) into auth_count
    from public.rider_equine_authorizations
   where source_zero_session_id = approved.zero_session_id;

  if auth_count <> 0 then
    raise exception 'Zero Session approval auto-created an authorization';
  end if;

  begin
    update public.zero_sessions
       set notes = 'Privileged historical rewrite'
     where id = approved.zero_session_id;
    raise exception 'Finalized Zero Session facts were rewritten';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform * from public.approve_zero_session(
      '98000000-0000-0000-0000-00000000a001',
      'APPROVED_WITH_RESTRICTIONS',
      'Safe with evaluator'
    );
    raise exception 'Conflicting approval replay was allowed';
  exception
    when serialization_failure then null;
  end;
end;
$$;
reset role;

do $$
declare
  minor_id uuid;
  guardian_id uuid;
  guardian_account_id uuid;
  relationship_id uuid := '98000000-0000-0000-0000-00000000f001';
begin
  select person_id into minor_id from public.user_accounts
   where auth_user_id = '98000000-0000-0000-0000-000000000004';
  select person_id, id into guardian_id, guardian_account_id
    from public.user_accounts
   where auth_user_id = '98000000-0000-0000-0000-000000000005';

  insert into public.guardian_relationships (
    id, guardian_person_id, minor_person_id, relationship_type,
    verification_status, verified_at
  ) values (
    relationship_id, guardian_id, minor_id, 'LEGAL_GUARDIAN',
    'VERIFIED', now() - interval '1 day'
  );

  insert into public.guardian_consents (
    guardian_relationship_id, guardian_person_id, minor_person_id,
    granted_by_account_id, consent_type, scope_type, terms_version,
    status, granted_at
  ) values (
    relationship_id, guardian_id, minor_id, guardian_account_id,
    'EQUESTRIAN_ACTIVITY', 'GENERAL', 'phase9b-fixture',
    'ACTIVE', now() - interval '1 hour'
  );
end;
$$;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"98000000-0000-0000-0000-000000000002","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '98000000-0000-0000-0000-000000000002',
  true
);
do $$
declare
  approved record;
begin
  select * into approved
    from public.approve_zero_session(
      '98000000-0000-0000-0000-00000000a002',
      'APPROVED_WITH_RESTRICTIONS',
      'Guardian consent verified'
    );

  if approved.result <> 'APPROVED_WITH_RESTRICTIONS' then
    raise exception 'Minor approval with valid consent failed';
  end if;
end;
$$;
reset role;

-- A new approval must fail immediately after authority revocation.
update public.equine_center_permissions
   set status = 'REVOKED', revoked_at = now()
 where equine_id = '98000000-0000-0000-0000-00000000e001'
   and center_id = '98000000-0000-0000-0000-00000000c001'
   and permission_code = 'ASSESS_RIDERS';

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"98000000-0000-0000-0000-000000000002","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '98000000-0000-0000-0000-000000000002',
  true
);
do $$
begin
  perform * from public.approve_zero_session(
    '98000000-0000-0000-0000-00000000a004', 'APPROVED', null
  );
  raise exception 'Revoked ASSESS_RIDERS still allowed a new approval';
exception
  when insufficient_privilege then null;
end;
$$;
reset role;

rollback;
