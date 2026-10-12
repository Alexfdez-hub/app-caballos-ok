-- Stage 1 cohort boundary. One transaction, then rollback.
-- Does not call a remote project and does not leave a grant behind.

begin;

insert into auth.users (id) values
  ('04110000-0000-4000-8000-000000000001'),
  ('04110000-0000-4000-8000-000000000002'),
  ('04110000-0000-4000-8000-000000000003');

insert into public.equines (id, name, equine_type)
values ('04110000-0000-4000-8000-0000000000e1', 'Cohort Horse', 'HORSE');

do $$
declare
  requester_person uuid;
  function_name text;
begin
  foreach function_name in array array[
    'create_verification_review_cohort(text)',
    'add_verification_review_cohort_case(text,text,uuid)',
    'close_verification_review_cohort_composition(text)',
    'bootstrap_verification_review_grant(uuid,text)'
  ]
  loop
    if has_function_privilege('anon', format('public.%s', function_name), 'EXECUTE')
       or has_function_privilege('authenticated', format('public.%s', function_name), 'EXECUTE')
       or has_function_privilege('service_role', format('public.%s', function_name), 'EXECUTE') then
      raise exception '% is executable by an application role', function_name;
    end if;
  end loop;

  foreach function_name in array array[
    'public.verification_review_cohorts',
    'public.verification_review_cohort_cases',
    'public.verification_review_cohort_events'
  ]
  loop
    if has_table_privilege('anon', function_name, 'INSERT')
       or has_table_privilege('authenticated', function_name, 'INSERT')
       or has_table_privilege('authenticated', function_name, 'UPDATE')
       or has_table_privilege('authenticated', function_name, 'DELETE')
       or has_table_privilege('service_role', function_name, 'INSERT')
       or has_table_privilege('service_role', function_name, 'UPDATE')
       or has_table_privilege('service_role', function_name, 'DELETE') then
      raise exception '% accepts an application mutation', function_name;
    end if;

    if not (
      select relrowsecurity
        from pg_catalog.pg_class
       where oid = function_name::regclass
    ) then
      raise exception '% does not enable row level security', function_name;
    end if;
  end loop;

  select account.person_id
    into requester_person
    from public.user_accounts as account
   where account.auth_user_id = '04110000-0000-4000-8000-000000000001';

  update public.persons
     set display_name = 'Cohort Subject'
   where id = requester_person;

  insert into public.equine_ownerships (
    id, equine_id, owner_type, owner_person_id, ownership_percentage,
    status, started_at
  ) values (
    '04110000-0000-4000-8000-0000000000a1',
    '04110000-0000-4000-8000-0000000000e1',
    'PERSON',
    requester_person,
    100,
    'ACTIVE',
    timestamptz '2020-01-01 00:00:00+00'
  );

  insert into public.equine_ownerships (
    id, equine_id, owner_type, owner_person_id, ownership_percentage,
    status, started_at, ended_at
  ) values (
    '04110000-0000-4000-8000-0000000000a2',
    '04110000-0000-4000-8000-0000000000e1',
    'PERSON',
    requester_person,
    100,
    'ENDED',
    timestamptz '2019-01-01 00:00:00+00',
    timestamptz '2019-06-01 00:00:00+00'
  );

  insert into public.equine_management_assignments (
    id, equine_id, manager_type, manager_person_id, management_role,
    status, valid_from, granted_by_person_id
  ) values (
    '04110000-0000-4000-8000-0000000000b1',
    '04110000-0000-4000-8000-0000000000e1',
    'PERSON',
    requester_person,
    'PRIMARY_MANAGER',
    'ACTIVE',
    timestamptz '2020-01-01 00:00:00+00',
    requester_person
  );

  insert into public.equine_management_assignments (
    id, equine_id, manager_type, manager_person_id, management_role,
    status, valid_from, granted_by_person_id
  ) values (
    '04110000-0000-4000-8000-0000000000b2',
    '04110000-0000-4000-8000-0000000000e1',
    'PERSON',
    requester_person,
    'CO_MANAGER',
    'ACTIVE',
    pg_catalog.now() + interval '2 days',
    requester_person
  );
end;
$$;

select set_config('request.jwt.claim.sub', '04110000-0000-4000-8000-000000000001', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"04110000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
set local role authenticated;

do $$
declare
  identity_case uuid;
  ownership_claim uuid;
  management_claim uuid;
begin
  select submitted.case_id
    into identity_case
    from public.submit_my_identity_case('ES') as submitted;

  begin
    perform public.submit_my_equine_ownership_claim(
      '04110000-0000-4000-8000-0000000000e1',
      'ES', 'PERSON', null, 50,
      '04110000-0000-4000-8000-0000000000a1'
    );
    raise exception using errcode = 'P0002', message = 'Mismatched ownership percentage was claimable';
  exception
    when insufficient_privilege then
      if sqlerrm is distinct from 'Verification request is not available' then
        raise exception 'Unexpected percentage refusal: %', sqlerrm;
      end if;
  end;

  begin
    perform public.submit_my_equine_management_claim(
      '04110000-0000-4000-8000-0000000000e1',
      'ES', 'PERSON', null, 'CO_MANAGER',
      timestamptz '2020-01-01 00:00:00+00',
      null,
      '04110000-0000-4000-8000-0000000000b1'
    );
    raise exception using errcode = 'P0002', message = 'Mismatched management role was claimable';
  exception
    when insufficient_privilege then
      if sqlerrm is distinct from 'Verification request is not available' then
        raise exception 'Unexpected role refusal: %', sqlerrm;
      end if;
  end;

  select submitted.claim_id
    into ownership_claim
    from public.submit_my_equine_ownership_claim(
      '04110000-0000-4000-8000-0000000000e1',
      'ES', 'PERSON', null, 100,
      '04110000-0000-4000-8000-0000000000a1'
    ) as submitted;
  select submitted.claim_id
    into management_claim
    from public.submit_my_equine_management_claim(
      '04110000-0000-4000-8000-0000000000e1',
      'ES', 'PERSON', null, 'PRIMARY_MANAGER',
      timestamptz '2020-01-01 00:00:00+00',
      null,
      '04110000-0000-4000-8000-0000000000b1'
    ) as submitted;

  perform set_config('verification.cohort_identity', identity_case::text, true);
  perform set_config('verification.cohort_ownership', ownership_claim::text, true);
  perform set_config('verification.cohort_management', management_claim::text, true);

  begin
    perform public.submit_my_identity_case('ES');
    raise exception using errcode = 'P0002', message = 'Second identity case was accepted';
  exception
    when insufficient_privilege then
      if sqlerrm is distinct from 'Verification request is not available' then
        raise exception 'Unexpected second identity refusal: %', sqlerrm;
      end if;
  end;

  begin
    perform public.submit_my_equine_ownership_claim(
      '04110000-0000-4000-8000-0000000000e1',
      'ES', 'PERSON', null, 100,
      '04110000-0000-4000-8000-0000000000a2'
    );
    raise exception using errcode = 'P0002', message = 'Ended ownership was claimable';
  exception
    when insufficient_privilege then
      if sqlerrm is distinct from 'Verification request is not available' then
        raise exception 'Unexpected ended ownership refusal: %', sqlerrm;
      end if;
  end;

  begin
    perform public.submit_my_equine_management_claim(
      '04110000-0000-4000-8000-0000000000e1',
      'ES', 'PERSON', null, 'CO_MANAGER',
      pg_catalog.now() + interval '2 days',
      null,
      '04110000-0000-4000-8000-0000000000b2'
    );
    raise exception using errcode = 'P0002', message = 'Future management was claimable';
  exception
    when insufficient_privilege then
      if sqlerrm is distinct from 'Verification request is not available' then
        raise exception 'Unexpected future management refusal: %', sqlerrm;
      end if;
  end;

  begin
    perform public.submit_my_equine_management_claim(
      '04110000-0000-4000-8000-0000000000e1',
      'ES', 'PERSON', null, 'PRIMARY_MANAGER',
      timestamptz '2021-01-01 00:00:00+00',
      null,
      '04110000-0000-4000-8000-0000000000b1'
    );
    raise exception using errcode = 'P0002', message = 'Mismatched management window was claimable';
  exception
    when insufficient_privilege then
      if sqlerrm is distinct from 'Verification request is not available' then
        raise exception 'Unexpected window refusal: %', sqlerrm;
      end if;
  end;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '04110000-0000-4000-8000-000000000003', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"04110000-0000-4000-8000-000000000003","role":"authenticated"}',
  true
);
set local role authenticated;

do $$
declare
  outside_identity uuid;
  outside_ownership uuid;
  outside_management uuid;
begin
  select submitted.case_id
    into outside_identity
    from public.submit_my_identity_case('ES') as submitted;
  select submitted.claim_id
    into outside_ownership
    from public.submit_my_equine_ownership_claim(
      '04110000-0000-4000-8000-0000000000e1',
      'ES', 'PERSON', null, 100, null
    ) as submitted;
  select submitted.claim_id
    into outside_management
    from public.submit_my_equine_management_claim(
      '04110000-0000-4000-8000-0000000000e1',
      'ES', 'PERSON', null, 'AUTHORIZED_MANAGER',
      pg_catalog.now(),
      null,
      null
    ) as submitted;
  perform set_config('verification.outside_identity', outside_identity::text, true);
  perform set_config('verification.outside_ownership', outside_ownership::text, true);
  perform set_config('verification.outside_management', outside_management::text, true);
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '04110000-0000-4000-8000-000000000002', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"04110000-0000-4000-8000-000000000002","role":"authenticated"}',
  true
);
set local role authenticated;

do $$
declare
  self_case uuid;
begin
  select submitted.case_id
    into self_case
    from public.submit_my_identity_case('ES') as submitted;
  perform set_config('verification.self_identity', self_case::text, true);
end;
$$;

reset role;

do $$
declare
  reviewer_person uuid;
  event_count integer;
  outcome text;
begin
  perform public.create_verification_review_cohort('ES-041-OPEN');
  begin
    perform public.bootstrap_verification_review_grant(
      (
        select account.person_id
          from public.user_accounts as account
         where account.auth_user_id = '04110000-0000-4000-8000-000000000002'
      ),
      'ES-041-OPEN'
    );
    raise exception using errcode = 'P0002', message = 'Open cohort was bootstrapped';
  exception
    when insufficient_privilege then
      null;
  end;

  perform public.create_verification_review_cohort('ES-041');
  perform public.create_verification_review_cohort('ES-041-OTHER');
  perform public.add_verification_review_cohort_case(
    'ES-041', 'IDENTITY', current_setting('verification.cohort_identity')::uuid
  );
  perform public.add_verification_review_cohort_case(
    'ES-041', 'OWNERSHIP', current_setting('verification.cohort_ownership')::uuid
  );
  perform public.add_verification_review_cohort_case(
    'ES-041', 'MANAGEMENT', current_setting('verification.cohort_management')::uuid
  );
  perform public.add_verification_review_cohort_case(
    'ES-041', 'IDENTITY', current_setting('verification.self_identity')::uuid
  );

  begin
    perform public.add_verification_review_cohort_case(
      'ES-041', 'IDENTITY', '04110000-0000-4000-8000-000000000099'
    );
    raise exception using errcode = 'P0002', message = 'Missing dossier was added';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    perform public.add_verification_review_cohort_case(
      'ES-041', 'OWNERSHIP', current_setting('verification.cohort_identity')::uuid
    );
    raise exception using errcode = 'P0002', message = 'Wrong case type was added';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    perform public.add_verification_review_cohort_case(
      'ES-041-OTHER', 'IDENTITY', current_setting('verification.cohort_identity')::uuid
    );
    raise exception using errcode = 'P0002', message = 'Dossier joined a second cohort';
  exception
    when insufficient_privilege then
      null;
  end;

  perform public.close_verification_review_cohort_composition('ES-041');

  begin
    perform public.add_verification_review_cohort_case(
      'ES-041', 'IDENTITY', current_setting('verification.outside_identity')::uuid
    );
    raise exception using errcode = 'P0002', message = 'Closed cohort accepted a dossier';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    perform public.close_verification_review_cohort_composition('ES-041');
    raise exception using errcode = 'P0002', message = 'Closed cohort reopened';
  exception
    when insufficient_privilege then
      null;
  end;

  select account.person_id
    into reviewer_person
    from public.user_accounts as account
   where account.auth_user_id = '04110000-0000-4000-8000-000000000002';

  perform public.bootstrap_verification_review_grant(reviewer_person, 'ES-041');

  insert into public.verification_review_grants (
    reviewer_person_id,
    scope_type,
    market_country_code
  )
  select account.person_id, 'MARKET', 'ES'
    from public.user_accounts as account
   where account.auth_user_id = '04110000-0000-4000-8000-000000000003';

  begin
    delete from public.verification_review_cohort_cases
     where case_id = current_setting('verification.cohort_identity')::uuid;
    raise exception using errcode = 'P0002', message = 'Cohort membership was deleted';
  exception
    when insufficient_privilege then
      null;
  end;

  select count(*)
    into event_count
    from public.verification_review_cohort_events
   where cohort_code = 'ES-041';

  if event_count <> 6 then
    raise exception 'Cohort history count was %', event_count;
  end if;
end;
$$;

select set_config('request.jwt.claim.sub', '04110000-0000-4000-8000-000000000002', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"04110000-0000-4000-8000-000000000002","role":"authenticated"}',
  true
);
set local role authenticated;

do $$
declare
  queue_ids uuid[];
  detail_name text;
  outcome text;
begin
  if (
    select count(*)
      from public.get_my_review_capabilities() as capability
     where capability.scope_type = 'MARKET'
       and capability.market_country_code = 'ES'
  ) <> 1 then
    raise exception 'Cohort grant did not expose MARKET / ES';
  end if;

  select array_agg(queued.case_id)
    into queue_ids
    from public.list_my_review_queue() as queued;

  if not queue_ids @> array[
    current_setting('verification.cohort_identity')::uuid,
    current_setting('verification.cohort_ownership')::uuid,
    current_setting('verification.cohort_management')::uuid
  ]::uuid[]
     or queue_ids && array[
       current_setting('verification.outside_identity')::uuid,
       current_setting('verification.outside_ownership')::uuid,
       current_setting('verification.outside_management')::uuid,
       current_setting('verification.self_identity')::uuid
     ]::uuid[] then
    raise exception 'Queue membership was %', queue_ids;
  end if;

  select detail.subject_name
    into detail_name
    from public.get_my_review_case(
      'IDENTITY',
      current_setting('verification.cohort_identity')::uuid
    ) as detail;

  if detail_name is distinct from 'Cohort Subject' then
    raise exception 'In-cohort detail omitted the subject';
  end if;

  foreach outcome in array array['ACCEPTED', 'REJECTED']
  loop
    begin
      perform public.get_my_review_case(
        'IDENTITY',
        current_setting('verification.outside_identity')::uuid
      );
      raise exception using errcode = 'P0002', message = 'Outside identity was readable';
    exception
      when insufficient_privilege then
        if sqlerrm is distinct from 'Verification request is not available' then
          raise exception 'Outside read leaked %', sqlerrm;
        end if;
    end;

    begin
      perform public.review_identity_case(
        current_setting('verification.outside_identity')::uuid,
        outcome,
        'outside'
      );
      raise exception using errcode = 'P0002', message = 'Outside identity was decided';
    exception
      when insufficient_privilege then
        if sqlerrm is distinct from 'Verification request is not available' then
          raise exception 'Outside identity decision leaked %', sqlerrm;
        end if;
    end;

    begin
      perform public.review_equine_ownership_claim(
        current_setting('verification.outside_ownership')::uuid,
        outcome,
        'outside'
      );
      raise exception using errcode = 'P0002', message = 'Outside ownership was decided';
    exception
      when insufficient_privilege then
        if sqlerrm is distinct from 'Verification request is not available' then
          raise exception 'Outside ownership decision leaked %', sqlerrm;
        end if;
    end;

    begin
      perform public.review_equine_management_claim(
        current_setting('verification.outside_management')::uuid,
        outcome,
        'outside'
      );
      raise exception using errcode = 'P0002', message = 'Outside management was decided';
    exception
      when insufficient_privilege then
        if sqlerrm is distinct from 'Verification request is not available' then
          raise exception 'Outside management decision leaked %', sqlerrm;
        end if;
    end;
  end loop;

  begin
    perform public.review_identity_case(
      current_setting('verification.self_identity')::uuid,
      'ACCEPTED',
      'self'
    );
    raise exception using errcode = 'P0002', message = 'Self-review inside the cohort was accepted';
  exception
    when insufficient_privilege then
      if sqlerrm is distinct from 'Verification request is not available' then
        raise exception 'Self-review leaked %', sqlerrm;
      end if;
  end;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '04110000-0000-4000-8000-000000000003', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"04110000-0000-4000-8000-000000000003","role":"authenticated"}',
  true
);
set local role authenticated;

do $$
begin
  if exists (select 1 from public.get_my_review_capabilities()) then
    raise exception 'A legacy grant exposed a capability';
  end if;

  begin
    perform public.list_my_review_queue();
    raise exception using errcode = 'P0002', message = 'A legacy grant listed the queue';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    perform public.review_identity_case(
      current_setting('verification.cohort_identity')::uuid,
      'ACCEPTED',
      'legacy'
    );
    raise exception using errcode = 'P0002', message = 'A legacy grant decided a case';
  exception
    when insufficient_privilege then
      null;
  end;
end;
$$;

reset role;

do $$
declare
  grant_id uuid;
  event_count integer;
begin
  select grant_row.id
    into grant_id
    from public.verification_review_grants as grant_row
    join public.user_accounts as account
      on account.person_id = grant_row.reviewer_person_id
   where account.auth_user_id = '04110000-0000-4000-8000-000000000002'
     and grant_row.cohort_code = 'ES-041';

  perform public.suspend_verification_review_grant(grant_id);
end;
$$;

select set_config('request.jwt.claim.sub', '04110000-0000-4000-8000-000000000002', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"04110000-0000-4000-8000-000000000002","role":"authenticated"}',
  true
);
set local role authenticated;

do $$
begin
  if exists (select 1 from public.get_my_review_capabilities()) then
    raise exception 'A suspended grant still exposed a capability';
  end if;

  begin
    perform public.list_my_review_queue();
    raise exception using errcode = 'P0002', message = 'A suspended grant listed the queue';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    perform public.get_my_review_case(
      'IDENTITY',
      current_setting('verification.cohort_identity')::uuid
    );
    raise exception using errcode = 'P0002', message = 'A suspended grant opened a dossier';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    perform public.review_identity_case(
      current_setting('verification.cohort_identity')::uuid,
      'ACCEPTED',
      'suspended'
    );
    raise exception using errcode = 'P0002', message = 'A suspended grant decided a dossier';
  exception
    when insufficient_privilege then
      null;
  end;
end;
$$;

reset role;

do $$
declare
  grant_id uuid;
  event_count integer;
begin
  select grant_row.id
    into grant_id
    from public.verification_review_grants as grant_row
   where grant_row.cohort_code = 'ES-041'
     and grant_row.status = 'SUSPENDED';

  perform public.close_verification_review_grant(grant_id);

  select count(*)
    into event_count
    from public.verification_review_cohort_events
   where cohort_code = 'ES-041';

  if event_count <> 6 then
    raise exception 'Closing the grant removed cohort history';
  end if;

  begin
    perform public.add_verification_review_cohort_case(
      'ES-041',
      'IDENTITY',
      current_setting('verification.outside_identity')::uuid
    );
    raise exception using errcode = 'P0002', message = 'Suspended-then-closed cohort grew';
  exception
    when insufficient_privilege then
      null;
  end;
end;
$$;

set local role authenticated;

do $$
begin
  perform public.bootstrap_verification_review_grant(
    '04110000-0000-4000-8000-000000000002',
    'ES-041'
  );
  raise exception using errcode = 'P0002', message = 'authenticated bootstrapped a grant';
exception
  when insufficient_privilege then
    null;
end;
$$;

reset role;
set local role service_role;

do $$
begin
  perform public.create_verification_review_cohort('ES-041-SERVICE');
  raise exception using errcode = 'P0002', message = 'service_role created a cohort';
exception
  when insufficient_privilege then
    null;
end;
$$;

rollback;
