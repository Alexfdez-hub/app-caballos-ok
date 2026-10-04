-- Stage 2. Submit, read, and review RPCs. One transaction, then rollback.

begin;

insert into public.markets (country_code, status)
values ('ZZ', 'ACTIVE');

insert into auth.users (id) values
  ('03710000-0000-4000-8000-000000000001'),
  ('03710000-0000-4000-8000-000000000002'),
  ('03710000-0000-4000-8000-000000000003'),
  ('03710000-0000-4000-8000-000000000004'),
  ('03710000-0000-4000-8000-000000000005'),
  ('03710000-0000-4000-8000-000000000006');

insert into public.equines (id, name, equine_type)
values ('03710000-0000-4000-8000-0000000000e1', 'Review Horse', 'HORSE');

insert into public.equestrian_centers (id, name, slug, country_code, status)
values (
  '03710000-0000-4000-8000-0000000000c1',
  'Claim Center',
  'claim-center',
  'ES',
  'ACTIVE'
);

do $$
declare
  claimant_person uuid;
  claimant_account uuid;
  identity_reviewer_person uuid;
  equine_reviewer_person uuid;
  center_reviewer_person uuid;
  center_reviewer_account uuid;
  blocked_person uuid;
  suspended_account uuid;
begin
  select account.person_id, account.id
    into claimant_person, claimant_account
    from public.user_accounts as account
   where account.auth_user_id = '03710000-0000-4000-8000-000000000001';

  select account.person_id
    into identity_reviewer_person
    from public.user_accounts as account
   where account.auth_user_id = '03710000-0000-4000-8000-000000000002';

  select account.person_id
    into blocked_person
    from public.user_accounts as account
   where account.auth_user_id = '03710000-0000-4000-8000-000000000003';

  select account.person_id, account.id
    into center_reviewer_person, center_reviewer_account
    from public.user_accounts as account
   where account.auth_user_id = '03710000-0000-4000-8000-000000000004';

  select account.id
    into suspended_account
    from public.user_accounts as account
   where account.auth_user_id = '03710000-0000-4000-8000-000000000005';

  select account.person_id
    into equine_reviewer_person
    from public.user_accounts as account
   where account.auth_user_id = '03710000-0000-4000-8000-000000000006';

  update public.user_accounts
     set status = 'SUSPENDED'
   where id = suspended_account;

  insert into public.center_memberships (center_id, person_id, role_code)
  values (
    '03710000-0000-4000-8000-0000000000c1',
    center_reviewer_person,
    'ADMIN'
  );

  insert into public.verification_review_grants (reviewer_person_id, scope_type)
  values
    (claimant_person, 'PLATFORM_IDENTITY'),
    (identity_reviewer_person, 'PLATFORM_IDENTITY'),
    (center_reviewer_person, 'PLATFORM_EQUINE'),
    (equine_reviewer_person, 'PLATFORM_EQUINE');

  insert into public.verification_review_grants (
    reviewer_person_id,
    scope_type,
    market_country_code
  ) values (blocked_person, 'MARKET', 'ZZ');

  insert into public.verification_review_grants (
    reviewer_person_id,
    scope_type,
    valid_from
  ) values (
    blocked_person,
    'PLATFORM_IDENTITY',
    now() + interval '1 day'
  );

  perform set_config('verification.claimant_person', claimant_person::text, true);
  perform set_config('verification.claimant_account', claimant_account::text, true);
  perform set_config('verification.identity_reviewer_person', identity_reviewer_person::text, true);
  perform set_config('verification.equine_reviewer_person', equine_reviewer_person::text, true);
  perform set_config('verification.center_reviewer_account', center_reviewer_account::text, true);
  perform set_config(
    'verification.ownership_count',
    (select count(*)::text from public.equine_ownerships),
    true
  );
  perform set_config(
    'verification.assignment_count',
    (select count(*)::text from public.equine_management_assignments),
    true
  );
end;
$$;

do $$
declare
  signature text;
  result_type text;
  function_name text;
begin
  foreach function_name in array array[
    'verification_resolve_caller()',
    'verification_review_grant_matches(uuid,text,text)',
    'verification_person_acts_for_center(uuid,uuid)'
  ]
  loop
    if has_function_privilege('anon', format('public.%s', function_name), 'EXECUTE')
       or has_function_privilege('authenticated', format('public.%s', function_name), 'EXECUTE')
       or exists (
         select 1
           from pg_catalog.pg_proc as procedure
           cross join lateral aclexplode(
             coalesce(procedure.proacl, acldefault('f', procedure.proowner))
           ) as privilege
          where procedure.oid = format('public.%s', function_name)::regprocedure
            and privilege.privilege_type = 'EXECUTE'
            and privilege.grantee = 0
       ) then
      raise exception 'Helper % is executable by a client role', function_name;
    end if;
  end loop;

  foreach function_name in array array[
    'submit_my_identity_case(text)',
    'submit_my_equine_ownership_claim(uuid,text,text,uuid,numeric,uuid)',
    'submit_my_equine_management_claim(uuid,text,text,uuid,text,timestamp with time zone,timestamp with time zone,uuid)',
    'list_my_identity_cases()',
    'list_my_equine_ownership_claims()',
    'list_my_equine_management_claims()',
    'review_identity_case(uuid,text,text)',
    'review_equine_ownership_claim(uuid,text,text)',
    'review_equine_management_claim(uuid,text,text)'
  ]
  loop
    if has_function_privilege('anon', format('public.%s', function_name), 'EXECUTE')
       or exists (
         select 1
           from pg_catalog.pg_proc as procedure
           cross join lateral aclexplode(
             coalesce(procedure.proacl, acldefault('f', procedure.proowner))
           ) as privilege
          where procedure.oid = format('public.%s', function_name)::regprocedure
            and privilege.privilege_type = 'EXECUTE'
            and privilege.grantee = 0
       ) then
      raise exception '% is executable by anon or public', function_name;
    end if;
    if not has_function_privilege('authenticated', format('public.%s', function_name), 'EXECUTE') then
      raise exception '% is not executable by authenticated', function_name;
    end if;
  end loop;

  foreach function_name in array array[
    'public.review_identity_case(uuid,text,text)',
    'public.review_equine_ownership_claim(uuid,text,text)',
    'public.review_equine_management_claim(uuid,text,text)',
    'public.submit_my_identity_case(text)'
  ]
  loop
    select pg_catalog.pg_get_function_identity_arguments(procedure.oid)
      into signature
      from pg_catalog.pg_proc as procedure
     where procedure.oid = function_name::regprocedure;

    if signature ~* 'reviewer|subject|submitter|account_id|person_id' then
      raise exception '% accepts a caller identity argument: %', function_name, signature;
    end if;
  end loop;

  foreach function_name in array array[
    'public.list_my_identity_cases()',
    'public.list_my_equine_ownership_claims()',
    'public.list_my_equine_management_claims()',
    'public.review_identity_case(uuid,text,text)'
  ]
  loop
    select pg_catalog.pg_get_function_result(function_name::regprocedure)
      into result_type;
    if result_type ~* 'reviewer|provider_reference|storage_bucket|storage_path|sqlerrm' then
      raise exception '% result exposes a private field: %', function_name, result_type;
    end if;
  end loop;
end;
$$;

select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claims', '{}', true);
set local role authenticated;

do $$
begin
  perform public.submit_my_identity_case('ES');
  raise exception using
    errcode = 'P0002',
    message = 'Anonymous identity submit was accepted';
exception
  when insufficient_privilege then
    if sqlerrm is distinct from 'Authentication required' then
      raise exception 'Unexpected anonymous refusal: %', sqlerrm;
    end if;
end;
$$;

reset role;
select set_config(
  'request.jwt.claim.sub',
  '03710000-0000-4000-8000-000000000099',
  true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"03710000-0000-4000-8000-000000000099","role":"authenticated"}',
  true
);
set local role authenticated;

do $$
begin
  perform public.submit_my_identity_case('ES');
  raise exception using
    errcode = 'P0002',
    message = 'Missing account submit was accepted';
exception
  when insufficient_privilege then
    if sqlerrm is distinct from 'Verification request is not available' then
      raise exception 'Unexpected missing-account refusal: %', sqlerrm;
    end if;
end;
$$;

reset role;
select set_config(
  'request.jwt.claim.sub',
  '03710000-0000-4000-8000-000000000005',
  true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"03710000-0000-4000-8000-000000000005","role":"authenticated"}',
  true
);
set local role authenticated;

do $$
begin
  perform public.submit_my_identity_case('ES');
  raise exception using
    errcode = 'P0002',
    message = 'Suspended account submit was accepted';
exception
  when insufficient_privilege then
    if sqlerrm is distinct from 'Verification request is not available' then
      raise exception 'Unexpected suspended refusal: %', sqlerrm;
    end if;
end;
$$;

reset role;
select set_config(
  'request.jwt.claim.sub',
  '03710000-0000-4000-8000-000000000001',
  true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"03710000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
set local role authenticated;

do $$
declare
  refusal text;
begin
  begin
    perform public.submit_my_identity_case('ZZ');
    raise exception using
      errcode = 'P0002',
      message = 'Unselectable market was accepted';
  exception
    when insufficient_privilege then
      refusal := sqlerrm;
  end;

  if refusal is distinct from 'Verification request is not available'
     or refusal like '%ZZ%' then
    raise exception 'Market refusal leaked detail: %', refusal;
  end if;

  begin
    perform public.submit_my_equine_ownership_claim(
      '03710000-0000-4000-8000-0000000000e1',
      'ES',
      'PERSON',
      null,
      0,
      null
    );
    raise exception using
      errcode = 'P0002',
      message = 'Zero percentage was accepted';
  exception
    when insufficient_privilege then
      refusal := sqlerrm;
  end;

  if refusal is distinct from 'Verification request is not available'
     or refusal ~* 'check|constraint|percentage' then
    raise exception 'Percentage refusal leaked SQL detail: %', refusal;
  end if;
end;
$$;

do $$
declare
  identity_case uuid;
  ownership_claim uuid;
  center_claim uuid;
  management_claim uuid;
begin
  select submitted.case_id
    into identity_case
    from public.submit_my_identity_case('ES') as submitted;

  select submitted.claim_id
    into ownership_claim
    from public.submit_my_equine_ownership_claim(
      '03710000-0000-4000-8000-0000000000e1',
      'ES',
      'PERSON',
      null,
      100,
      null
    ) as submitted;

  select submitted.claim_id
    into center_claim
    from public.submit_my_equine_ownership_claim(
      '03710000-0000-4000-8000-0000000000e1',
      'ES',
      'CENTER',
      '03710000-0000-4000-8000-0000000000c1',
      100,
      null
    ) as submitted;

  select submitted.claim_id
    into management_claim
    from public.submit_my_equine_management_claim(
      '03710000-0000-4000-8000-0000000000e1',
      'ES',
      'PERSON',
      null,
      'PRIMARY_MANAGER',
      now(),
      null,
      null
    ) as submitted;

  if (select count(*) from public.list_my_identity_cases()) <> 1 then
    raise exception 'Claimant cannot read the submitted identity case';
  end if;

  perform set_config('verification.identity_case', identity_case::text, true);
  perform set_config('verification.ownership_claim', ownership_claim::text, true);
  perform set_config('verification.center_claim', center_claim::text, true);
  perform set_config('verification.management_claim', management_claim::text, true);
end;
$$;

reset role;
insert into public.verification_evidence (
  parent_type,
  identity_case_id,
  category,
  provider_reference,
  submitted_by_account_id
) values (
  'IDENTITY_CASE',
  current_setting('verification.identity_case')::uuid,
  'IDENTITY_PROVIDER_REFERENCE',
  'provider-secret-037',
  current_setting('verification.claimant_account')::uuid
);

set local role authenticated;

do $$
declare
  listed_text text;
begin
  select string_agg(listed::text, ' ')
    into listed_text
    from public.list_my_identity_cases() as listed;

  if listed_text like '%provider-secret-037%'
     or listed_text like '%03710000-0000-4000-8000-000000000002%' then
    raise exception 'Claimant list exposed private review data';
  end if;
end;
$$;

reset role;
select set_config(
  'request.jwt.claim.sub',
  '03710000-0000-4000-8000-000000000006',
  true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"03710000-0000-4000-8000-000000000006","role":"authenticated"}',
  true
);
set local role authenticated;

do $$
begin
  if (select count(*) from public.list_my_identity_cases()) <> 0 then
    raise exception 'Another caller can read the claimant identity case';
  end if;
end;
$$;

reset role;
select set_config(
  'request.jwt.claim.sub',
  '03710000-0000-4000-8000-000000000001',
  true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"03710000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
set local role authenticated;

do $$
begin
  perform public.review_identity_case(
    current_setting('verification.identity_case')::uuid,
    'ACCEPTED',
    'self-review'
  );
  raise exception using
    errcode = 'P0002',
    message = 'Self-review was accepted';
exception
  when insufficient_privilege then
    if sqlerrm is distinct from 'Verification request is not available' then
      raise exception 'Unexpected self-review refusal: %', sqlerrm;
    end if;
end;
$$;

reset role;
select set_config(
  'request.jwt.claim.sub',
  '03710000-0000-4000-8000-000000000003',
  true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"03710000-0000-4000-8000-000000000003","role":"authenticated"}',
  true
);
set local role authenticated;

do $$
begin
  perform public.review_identity_case(
    current_setting('verification.identity_case')::uuid,
    'ACCEPTED',
    'wrong-grant'
  );
  raise exception using
    errcode = 'P0002',
    message = 'Review without a matching grant was accepted';
exception
  when insufficient_privilege then
    if sqlerrm is distinct from 'Verification request is not available' then
      raise exception 'Unexpected grant refusal: %', sqlerrm;
    end if;
end;
$$;

reset role;
select set_config(
  'request.jwt.claim.sub',
  '03710000-0000-4000-8000-000000000002',
  true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"03710000-0000-4000-8000-000000000002","role":"authenticated"}',
  true
);
set local role authenticated;

do $$
declare
  reviewed_state text;
  claimant_view text;
begin
  perform public.review_equine_ownership_claim(
    current_setting('verification.ownership_claim')::uuid,
    'ACCEPTED',
    'wrong-scope'
  );
  raise exception using
    errcode = 'P0002',
    message = 'Identity grant reviewed an equine claim';
exception
  when insufficient_privilege then
    if sqlerrm is distinct from 'Verification request is not available' then
      raise exception 'Unexpected scope refusal: %', sqlerrm;
    end if;
end;
$$;

do $$
declare
  reviewed_state text;
begin
  select reviewed.state
    into reviewed_state
    from public.review_identity_case(
      current_setting('verification.identity_case')::uuid,
      'ACCEPTED',
      'records-match'
    ) as reviewed;

  if reviewed_state is distinct from 'ACCEPTED' then
    raise exception 'Identity review did not accept the case';
  end if;

  begin
    perform public.review_identity_case(
      current_setting('verification.identity_case')::uuid,
      'REJECTED',
      'second-decision'
    );
    raise exception using
      errcode = 'P0002',
      message = 'A second decision was accepted';
  exception
    when insufficient_privilege then
      if sqlerrm is distinct from 'Verification request is not available' then
        raise exception 'Unexpected second-decision refusal: %', sqlerrm;
      end if;
  end;
end;
$$;

reset role;

do $$
declare
  claimant_view text;
begin
  if (
    select count(*)
      from public.identity_verification_decisions as decision
     where decision.case_id = current_setting('verification.identity_case')::uuid
       and decision.reviewer_person_id = current_setting('verification.identity_reviewer_person')::uuid
       and decision.outcome = 'ACCEPTED'
  ) <> 1 then
    raise exception 'Identity decision was not stored for the resolved reviewer';
  end if;

  if (
    select count(*)
      from public.audit_events as event
     where event.entity_id = current_setting('verification.identity_case')::uuid
       and event.event_type = 'verification_case_reviewed'
       and event.actor_person_id = current_setting('verification.identity_reviewer_person')::uuid
       and event.metadata = jsonb_build_object(
         'outcome', 'ACCEPTED',
         'reason_code', 'records-match'
       )
  ) <> 1 then
    raise exception 'Identity review did not write one matching audit event';
  end if;
end;
$$;

select set_config(
  'request.jwt.claim.sub',
  '03710000-0000-4000-8000-000000000001',
  true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"03710000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
set local role authenticated;

do $$
declare
  claimant_view text;
begin
  select string_agg(listed::text, ' ')
    into claimant_view
    from public.list_my_identity_cases() as listed;

  if claimant_view not like '%ACCEPTED%'
     or claimant_view not like '%records-match%'
     or claimant_view like '%03710000-0000-4000-8000-000000000002%'
     or claimant_view like '%provider-secret-037%' then
    raise exception 'Claimant response leaked reviewer identity or provider data: %', claimant_view;
  end if;
end;
$$;

reset role;
select set_config(
  'request.jwt.claim.sub',
  '03710000-0000-4000-8000-000000000004',
  true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"03710000-0000-4000-8000-000000000004","role":"authenticated"}',
  true
);
set local role authenticated;

do $$
begin
  perform public.review_equine_ownership_claim(
    current_setting('verification.center_claim')::uuid,
    'ACCEPTED',
    'center-member'
  );
  raise exception using
    errcode = 'P0002',
    message = 'Center member reviewed the claimant center';
exception
  when insufficient_privilege then
    if sqlerrm is distinct from 'Verification request is not available' then
      raise exception 'Unexpected center-member refusal: %', sqlerrm;
    end if;
end;
$$;

reset role;
select set_config(
  'request.jwt.claim.sub',
  '03710000-0000-4000-8000-000000000006',
  true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"03710000-0000-4000-8000-000000000006","role":"authenticated"}',
  true
);
set local role authenticated;

do $$
begin
  perform public.review_equine_ownership_claim(
    current_setting('verification.ownership_claim')::uuid,
    'ACCEPTED',
    'ownership-match'
  );
  perform public.review_equine_ownership_claim(
    current_setting('verification.center_claim')::uuid,
    'REJECTED',
    'center-unproven'
  );
  perform public.review_equine_management_claim(
    current_setting('verification.management_claim')::uuid,
    'ACCEPTED',
    'management-match'
  );
end;
$$;

reset role;

do $$
begin
  if (select count(*) from public.equine_ownerships)
     is distinct from current_setting('verification.ownership_count')::integer then
    raise exception 'A claim or review wrote an effective ownership';
  end if;

  if (select count(*) from public.equine_management_assignments)
     is distinct from current_setting('verification.assignment_count')::integer then
    raise exception 'A claim or review wrote an effective management assignment';
  end if;
end;
$$;

reset role;
set local role authenticated;

do $$
begin
  perform count(*) from public.identity_verification_cases;
  raise exception using
    errcode = 'P0002',
    message = 'Authenticated table read was accepted';
exception
  when insufficient_privilege then
    null;
end;
$$;

rollback;
