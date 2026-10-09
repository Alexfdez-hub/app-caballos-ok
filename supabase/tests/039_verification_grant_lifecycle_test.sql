-- Stage 4B.2. Grant lifecycle. One transaction, then rollback.
-- Does not call the remote project and does not leave a grant behind.

begin;

insert into public.markets (country_code, status)
values ('ZZ', 'ACTIVE')
on conflict (country_code) do nothing;

insert into auth.users (id) values
  ('03910000-0000-4000-8000-000000000001'),
  ('03910000-0000-4000-8000-000000000002'),
  ('03910000-0000-4000-8000-000000000003'),
  ('03910000-0000-4000-8000-000000000004'),
  ('03910000-0000-4000-8000-000000000005');

insert into public.equestrian_centers (id, name, slug, country_code, status)
values (
  '03910000-0000-4000-8000-0000000000c1',
  'Grant Center',
  'grant-center-039',
  'ES',
  'ACTIVE'
);

do $$
declare
  function_name text;
  signature text;
  reviewer_person uuid;
  inactive_person uuid;
  suspended_person uuid;
  hipica_person uuid;
  close_person uuid;
  reviewer_account uuid;
  hipica_account uuid;
  created_grant_id uuid;
  replaced_grant_id uuid;
  second_grant_id uuid;
  platform_grant_id uuid;
  other_market_grant_id uuid;
  event_count integer;
begin
  foreach function_name in array array[
    'verification_grant_technical_principal()',
    'bootstrap_verification_review_grant(uuid)',
    'suspend_verification_review_grant(uuid)',
    'close_verification_review_grant(uuid)',
    'enforce_verification_grant_event_immutability()',
    'enforce_verification_grant_status_transition()'
  ]
  loop
    if has_function_privilege('anon', format('public.%s', function_name), 'EXECUTE')
       or has_function_privilege('authenticated', format('public.%s', function_name), 'EXECUTE')
       or has_function_privilege('service_role', format('public.%s', function_name), 'EXECUTE')
       or exists (
         select 1
           from pg_catalog.pg_proc as procedure
           cross join lateral aclexplode(
             coalesce(procedure.proacl, acldefault('f', procedure.proowner))
           ) as privilege
          where procedure.oid = format('public.%s', function_name)::regprocedure
            and privilege.privilege_type = 'EXECUTE'
            and privilege.grantee = 0
       )
       or exists (
         select 1
           from pg_catalog.pg_roles as role
           join pg_catalog.pg_proc as procedure
             on procedure.oid = format('public.%s', function_name)::regprocedure
          where not role.rolsuper
            and role.oid <> procedure.proowner
            and has_function_privilege(
              role.oid,
              procedure.oid,
              'EXECUTE'
            )
       ) then
      raise exception '% is executable outside the technical owner', function_name;
    end if;

    if exists (
      select 1
        from pg_catalog.pg_proc as procedure
       where procedure.oid = format('public.%s', function_name)::regprocedure
         and procedure.prosecdef
    ) then
      raise exception '% must stay SECURITY INVOKER', function_name;
    end if;
  end loop;

  select pg_catalog.pg_get_function_identity_arguments(procedure.oid)
    into signature
    from pg_catalog.pg_proc as procedure
   where procedure.oid = 'public.bootstrap_verification_review_grant(uuid)'::regprocedure;

  if signature <> 'p_reviewer_person_id uuid' then
    raise exception 'Bootstrap accepts an unexpected argument list';
  end if;

  if pg_catalog.pg_get_function_identity_arguments(
       'public.suspend_verification_review_grant(uuid)'::regprocedure
     ) <> 'p_grant_id uuid'
     or pg_catalog.pg_get_function_identity_arguments(
       'public.close_verification_review_grant(uuid)'::regprocedure
     ) <> 'p_grant_id uuid' then
    raise exception 'Lifecycle functions accept an actor or a scope';
  end if;

  foreach function_name in array array[
    'SELECT',
    'INSERT',
    'UPDATE',
    'DELETE'
  ]
  loop
    if has_table_privilege('anon', 'public.verification_review_grants', function_name)
       or has_table_privilege('authenticated', 'public.verification_review_grants', function_name)
       or has_table_privilege('service_role', 'public.verification_review_grants', function_name)
       or has_table_privilege('anon', 'public.verification_review_grant_events', function_name)
       or has_table_privilege('authenticated', 'public.verification_review_grant_events', function_name)
       or has_table_privilege('service_role', 'public.verification_review_grant_events', function_name) then
      raise exception 'A client role retains % on grant tables', function_name;
    end if;
  end loop;

  if pg_catalog.pg_get_functiondef(
       'public.verification_grant_technical_principal()'::regprocedure
     ) ilike '%supabase_admin%' then
    raise exception 'supabase_admin is still named as a grant operator';
  end if;

  if exists (
    select 1
      from pg_catalog.pg_proc as procedure
      cross join lateral aclexplode(
        coalesce(procedure.proacl, acldefault('f', procedure.proowner))
      ) as privilege
      join pg_catalog.pg_roles as role
        on role.oid = privilege.grantee
     where procedure.pronamespace = 'public'::regnamespace
       and procedure.proname in (
         'verification_grant_technical_principal',
         'bootstrap_verification_review_grant',
         'suspend_verification_review_grant',
         'close_verification_review_grant',
         'enforce_verification_grant_event_immutability',
         'enforce_verification_grant_status_transition'
       )
       and privilege.privilege_type = 'EXECUTE'
       and role.rolname in (
         'anon',
         'authenticated',
         'service_role',
         'supabase_admin'
       )
  ) then
    raise exception 'A non-operator role has an explicit function grant';
  end if;

  if exists (
    select 1
      from pg_catalog.pg_class as relation
      cross join lateral aclexplode(
        coalesce(relation.relacl, acldefault('r', relation.relowner))
      ) as privilege
      left join pg_catalog.pg_roles as role
        on role.oid = privilege.grantee
     where relation.oid in (
         'public.verification_review_grants'::regclass,
         'public.verification_review_grant_events'::regclass
       )
       and (
         privilege.grantee = 0
         or role.rolname in (
           'anon',
           'authenticated',
           'service_role',
           'supabase_admin'
         )
       )
  ) then
    raise exception 'PUBLIC or a non-operator role has an explicit table grant';
  end if;

  if exists (
    select 1
      from pg_catalog.pg_class as relation
     where relation.oid in (
         'public.verification_review_grants'::regclass,
         'public.verification_review_grant_events'::regclass
       )
       and not relation.relrowsecurity
  ) or exists (
    select 1
      from pg_catalog.pg_policy as policy
     where policy.polrelid in (
       'public.verification_review_grants'::regclass,
       'public.verification_review_grant_events'::regclass
     )
  ) then
    raise exception 'Grant tables do not keep client access denied by RLS';
  end if;

  if not exists (
    select 1
      from pg_catalog.pg_constraint as constraint_row
     where constraint_row.conname = 'verification_review_grant_events_actor_fk'
       and constraint_row.confrelid = 'public.user_accounts'::regclass
  ) or not exists (
    select 1
      from pg_catalog.pg_indexes as index_row
     where index_row.indexname = 'verification_review_grant_events_actor_idx'
  ) then
    raise exception 'PRODUCT actor is not tied to user_accounts';
  end if;

  if exists (
       select 1
         from pg_catalog.pg_roles as role
        where role.rolname = 'supabase_admin'
          and not role.rolsuper
     )
     and (
       has_function_privilege(
         'supabase_admin',
         'public.bootstrap_verification_review_grant(uuid)',
         'EXECUTE'
       )
       or has_function_privilege(
         'supabase_admin',
         'public.suspend_verification_review_grant(uuid)',
         'EXECUTE'
       )
       or has_function_privilege(
         'supabase_admin',
         'public.close_verification_review_grant(uuid)',
         'EXECUTE'
       )
     ) then
    raise exception 'supabase_admin has a granted execute path';
  end if;

  select account.id, account.person_id
    into reviewer_account, reviewer_person
    from public.user_accounts as account
   where account.auth_user_id = '03910000-0000-4000-8000-000000000001';

  select account.person_id
    into inactive_person
    from public.user_accounts as account
   where account.auth_user_id = '03910000-0000-4000-8000-000000000002';

  select account.person_id
    into suspended_person
    from public.user_accounts as account
   where account.auth_user_id = '03910000-0000-4000-8000-000000000003';

  select account.id, account.person_id
    into hipica_account, hipica_person
    from public.user_accounts as account
   where account.auth_user_id = '03910000-0000-4000-8000-000000000004';

  select account.person_id
    into close_person
    from public.user_accounts as account
   where account.auth_user_id = '03910000-0000-4000-8000-000000000005';

  update public.persons
     set status = 'INACTIVE'
   where id = inactive_person;

  update public.user_accounts
     set status = 'SUSPENDED'
   where person_id = suspended_person;

  insert into public.center_memberships (center_id, person_id, role_code)
  values (
    '03910000-0000-4000-8000-0000000000c1',
    hipica_person,
    'ADMIN'
  );

  begin
    perform public.bootstrap_verification_review_grant(
      '03910000-0000-4000-8000-000000000099'
    );
    raise exception 'Missing person was granted';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    perform public.bootstrap_verification_review_grant(inactive_person);
    raise exception 'Inactive person was granted';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    perform public.bootstrap_verification_review_grant(suspended_person);
    raise exception 'Person without an active account was granted';
  exception
    when insufficient_privilege then
      null;
  end;

  created_grant_id := public.bootstrap_verification_review_grant(reviewer_person);

  if not exists (
    select 1
      from public.verification_review_grants as grant_row
     where grant_row.id = created_grant_id
       and grant_row.reviewer_person_id = reviewer_person
       and grant_row.scope_type = 'MARKET'
       and grant_row.market_country_code = 'ES'
       and grant_row.status = 'ACTIVE'
       and grant_row.valid_until is null
  ) then
    raise exception 'Bootstrap did not create one MARKET / ES grant';
  end if;

  select count(*)
    into event_count
    from public.verification_review_grant_events as event
   where event.grant_id = created_grant_id
     and event.event_type = 'GRANTED'
     and event.previous_status is null
     and event.new_status = 'ACTIVE'
     and event.actor_kind = 'TECHNICAL'
     and event.technical_principal = session_user
     and event.actor_account_id is null
     and event.actor_person_id is null
     and event.reason_code = 'PILOT_BOOTSTRAP'
     and event.scope_type = 'MARKET'
     and event.market_country_code = 'ES';

  if event_count <> 1 then
    raise exception 'Bootstrap did not write exactly one technical GRANTED event';
  end if;

  if exists (
    select 1
      from public.audit_events as event
     where event.entity_id = created_grant_id
  ) then
    raise exception 'Bootstrap wrote a product audit actor';
  end if;

  if not public.verification_review_grant_matches(reviewer_person, 'IDENTITY', 'ES')
     or not public.verification_review_grant_matches(reviewer_person, 'EQUINE', 'ES') then
    raise exception 'ACTIVE MARKET / ES grant does not match';
  end if;

  begin
    perform public.bootstrap_verification_review_grant(reviewer_person);
    raise exception 'Duplicate bootstrap succeeded';
  exception
    when insufficient_privilege then
      null;
  end;

  if (
    select count(*)
      from public.verification_review_grant_events as event
     where event.grant_id = created_grant_id
  ) <> 1 then
    raise exception 'Duplicate bootstrap wrote a second event';
  end if;

  begin
    perform public.suspend_verification_review_grant(created_grant_id);
  end;

  if public.verification_review_grant_matches(reviewer_person, 'IDENTITY', 'ES')
     or public.verification_review_grant_matches(reviewer_person, 'EQUINE', 'ES') then
    raise exception 'Suspended grant still matches';
  end if;

  begin
    perform public.suspend_verification_review_grant(created_grant_id);
    raise exception 'Suspended grant was suspended again';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    perform public.bootstrap_verification_review_grant(reviewer_person);
    raise exception 'Suspended grant was duplicated';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    update public.verification_review_grants
       set status = 'ACTIVE'
     where id = created_grant_id;
    raise exception 'Suspended grant was reactivated';
  exception
    when insufficient_privilege then
      null;
  end;

  perform public.close_verification_review_grant(created_grant_id);

  if public.verification_review_grant_matches(reviewer_person, 'IDENTITY', 'ES')
     or not exists (
       select 1
         from public.verification_review_grant_events as event
        where event.grant_id = created_grant_id
          and event.event_type = 'CLOSED'
          and event.previous_status = 'SUSPENDED'
          and event.new_status = 'ENDED'
     )
     or exists (
       select 1
         from public.verification_review_grants as grant_row
        where grant_row.id = created_grant_id
          and grant_row.status is distinct from 'ENDED'
     ) then
    raise exception 'Suspended grant did not close with its previous status';
  end if;

  replaced_grant_id := public.bootstrap_verification_review_grant(reviewer_person);

  if replaced_grant_id = created_grant_id
     or exists (
       select 1
         from public.verification_review_grants as grant_row
        where grant_row.id = created_grant_id
          and grant_row.status is distinct from 'ENDED'
     )
     or not exists (
       select 1
         from public.verification_review_grants as grant_row
        where grant_row.id = replaced_grant_id
          and grant_row.status = 'ACTIVE'
     ) then
    raise exception 'A grant after close was not a separate row';
  end if;

  second_grant_id := public.bootstrap_verification_review_grant(close_person);
  perform public.close_verification_review_grant(second_grant_id);

  if public.verification_review_grant_matches(close_person, 'IDENTITY', 'ES')
     or exists (
       select 1
         from public.verification_review_grants as grant_row
        where grant_row.id = second_grant_id
          and (
            grant_row.status is distinct from 'ENDED'
            or grant_row.valid_until is null
          )
     ) then
    raise exception 'Closed grant is still current';
  end if;

  begin
    perform public.close_verification_review_grant(second_grant_id);
    raise exception 'Closed grant was closed again';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    perform public.suspend_verification_review_grant(second_grant_id);
    raise exception 'Closed grant was suspended';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    update public.verification_review_grants
       set status = 'ACTIVE',
           valid_until = null
     where id = second_grant_id;
    raise exception 'Ended grant changed status';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    perform public.bootstrap_verification_review_grant(close_person);
  end;

  if (
    select count(*)
      from public.verification_review_grants as grant_row
     where grant_row.reviewer_person_id = close_person
       and grant_row.status = 'ACTIVE'
  ) <> 1 then
    raise exception 'A new grant after close was not a separate row';
  end if;

  insert into public.verification_review_grants (
    id,
    reviewer_person_id,
    scope_type
  ) values (
    '03910000-0000-4000-8000-0000000000a1',
    hipica_person,
    'PLATFORM_IDENTITY'
  );

  begin
    perform public.suspend_verification_review_grant(
      '03910000-0000-4000-8000-0000000000a1'
    );
    raise exception 'Platform grant was suspended by the pilot function';
  exception
    when insufficient_privilege then
      null;
  end;

  insert into public.verification_review_grants (
    id,
    reviewer_person_id,
    scope_type,
    market_country_code
  ) values (
    '03910000-0000-4000-8000-0000000000a2',
    hipica_person,
    'MARKET',
    'ZZ'
  );

  begin
    perform public.close_verification_review_grant(
      '03910000-0000-4000-8000-0000000000a2'
    );
    raise exception 'Non-ES grant was closed by the pilot function';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    update public.verification_review_grant_events
       set reason_code = 'REWRITTEN'
     where grant_id = created_grant_id;
    raise exception 'Grant event update succeeded';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    delete from public.verification_review_grant_events
     where grant_id = created_grant_id;
    raise exception 'Grant event delete succeeded';
  exception
    when insufficient_privilege then
      null;
  end;

  if not public.verification_review_grant_matches(hipica_person, 'IDENTITY', 'ES') then
    raise exception 'Existing platform grant matching changed';
  end if;

  if public.verification_review_grant_matches(hipica_person, 'EQUINE', 'ES') then
    raise exception 'Center membership matched an equine review';
  end if;

  begin
    insert into public.verification_review_grant_events (
      grant_id,
      event_type,
      reviewer_person_id,
      scope_type,
      market_country_code,
      previous_status,
      new_status,
      actor_kind,
      actor_account_id,
      actor_person_id,
      reason_code
    ) values (
      created_grant_id,
      'CLOSED',
      reviewer_person,
      'MARKET',
      'ES',
      'SUSPENDED',
      'ENDED',
      'PRODUCT',
      hipica_account,
      reviewer_person,
      'PILOT_CLOSE'
    );
    raise exception 'Mismatched product actor was stored';
  exception
    when foreign_key_violation then
      null;
  end;

  begin
    insert into public.verification_review_grant_events (
      grant_id,
      event_type,
      reviewer_person_id,
      scope_type,
      market_country_code,
      new_status,
      actor_kind,
      actor_account_id,
      actor_person_id,
      reason_code
    ) values (
      created_grant_id,
      'GRANTED',
      reviewer_person,
      'MARKET',
      'ES',
      'ACTIVE',
      'PRODUCT',
      '03910000-0000-4000-8000-0000000000f1',
      '03910000-0000-4000-8000-0000000000f2',
      'PILOT_BOOTSTRAP'
    );
    raise exception 'Unrelated product actor was stored';
  exception
    when foreign_key_violation then
      null;
  end;

  insert into public.verification_review_grant_events (
    grant_id,
    event_type,
    reviewer_person_id,
    scope_type,
    market_country_code,
    previous_status,
    new_status,
    actor_kind,
    actor_account_id,
    actor_person_id,
    reason_code
  ) values (
    created_grant_id,
    'CLOSED',
    reviewer_person,
    'MARKET',
    'ES',
    'ACTIVE',
    'ENDED',
    'PRODUCT',
    reviewer_account,
    reviewer_person,
    'PILOT_CLOSE'
  );
end;
$$;

savepoint client_roles;

set local role anon;

do $$
begin
  perform public.bootstrap_verification_review_grant(
    '03910000-0000-4000-8000-000000000001'
  );
  raise exception 'anon executed bootstrap';
exception
  when insufficient_privilege then
    null;
end;
$$;

rollback to savepoint client_roles;

set local role service_role;

do $$
begin
  perform public.bootstrap_verification_review_grant(
    '03910000-0000-4000-8000-000000000001'
  );
  raise exception 'service_role executed bootstrap';
exception
  when insufficient_privilege then
    null;
end;
$$;

rollback to savepoint client_roles;

select set_config(
  'request.jwt.claim.sub',
  '03910000-0000-4000-8000-000000000004',
  true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"03910000-0000-4000-8000-000000000004","role":"authenticated"}',
  true
);

set local role authenticated;

do $$
declare
  hipica_person uuid;
begin
  select account.person_id
    into hipica_person
    from public.user_accounts as account
   where account.auth_user_id = '03910000-0000-4000-8000-000000000004';

  perform public.bootstrap_verification_review_grant(hipica_person);
  raise exception 'Reviewer session executed bootstrap';
exception
  when insufficient_privilege then
    null;
end;
$$;

do $$
begin
  perform public.suspend_verification_review_grant(
    '03910000-0000-4000-8000-0000000000a1'
  );
  raise exception 'Reviewer session suspended a grant';
exception
  when insufficient_privilege then
    null;
end;
$$;

do $$
begin
  perform public.close_verification_review_grant(
    '03910000-0000-4000-8000-0000000000a1'
  );
  raise exception 'Reviewer session closed a grant';
exception
  when insufficient_privilege then
    null;
end;
$$;

do $$
begin
  perform 1 from public.verification_review_grants limit 1;
  raise exception 'authenticated read the grant projection';
exception
  when insufficient_privilege then
    null;
end;
$$;

do $$
begin
  perform 1 from public.verification_review_grant_events limit 1;
  raise exception 'authenticated read grant events';
exception
  when insufficient_privilege then
    null;
end;
$$;

rollback to savepoint client_roles;

do $$
begin
  if (
    select count(*)
      from public.verification_review_grant_events as event
     where event.event_type = 'GRANTED'
       and event.reviewer_person_id in (
         select account.person_id
           from public.user_accounts as account
          where account.auth_user_id in (
            '03910000-0000-4000-8000-000000000001',
            '03910000-0000-4000-8000-000000000005'
          )
       )
  ) <> 4 then
    raise exception 'Client attempts created or removed grant events';
  end if;

  if exists (
    select 1
      from public.verification_review_grants as grant_row
      join public.user_accounts as account
        on account.person_id = grant_row.reviewer_person_id
     where account.auth_user_id = '03910000-0000-4000-8000-000000000004'
       and grant_row.scope_type = 'MARKET'
       and grant_row.market_country_code = 'ES'
  ) then
    raise exception 'A hípica session obtained a pilot grant';
  end if;
end;
$$;

rollback;
