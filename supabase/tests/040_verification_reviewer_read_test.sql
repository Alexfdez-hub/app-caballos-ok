-- Stage 4B.3. Read-only reviewer queue and detail. One transaction, then rollback.

begin;

insert into public.markets (country_code, status)
values ('ZZ', 'ACTIVE')
on conflict (country_code) do nothing;

insert into auth.users (id) values
  ('04010000-0000-4000-8000-000000000001'),
  ('04010000-0000-4000-8000-000000000002'),
  ('04010000-0000-4000-8000-000000000003'),
  ('04010000-0000-4000-8000-000000000004'),
  ('04010000-0000-4000-8000-000000000005');

insert into public.equines (id, name, equine_type)
values ('04010000-0000-4000-8000-0000000000e1', 'Pilot Horse', 'HORSE');

insert into public.equestrian_centers (id, name, slug, country_code, status)
values (
  '04010000-0000-4000-8000-0000000000c1',
  'Pilot Center',
  'pilot-center-040',
  'ES',
  'ACTIVE'
);

do $$
declare
  reviewer_person uuid;
  reviewer_account uuid;
  subject_person uuid;
  subject_account uuid;
  hipica_person uuid;
  platform_person uuid;
  member_only_person uuid;
  queue_ids uuid[];
  detail_row record;
  audit_count integer;
begin
  if has_function_privilege('anon', 'public.get_my_review_capabilities()', 'EXECUTE')
     or has_function_privilege('anon', 'public.list_my_review_queue()', 'EXECUTE')
     or has_function_privilege('anon', 'public.get_my_review_case(text, uuid)', 'EXECUTE')
     or has_function_privilege('service_role', 'public.get_my_review_capabilities()', 'EXECUTE')
     or has_function_privilege('service_role', 'public.list_my_review_queue()', 'EXECUTE')
     or has_function_privilege('service_role', 'public.get_my_review_case(text, uuid)', 'EXECUTE')
     or not has_function_privilege('authenticated', 'public.get_my_review_capabilities()', 'EXECUTE')
     or not has_function_privilege('authenticated', 'public.list_my_review_queue()', 'EXECUTE')
     or not has_function_privilege('authenticated', 'public.get_my_review_case(text, uuid)', 'EXECUTE')
     or exists (
       select 1
         from pg_catalog.pg_proc as procedure
         cross join lateral aclexplode(
           coalesce(procedure.proacl, acldefault('f', procedure.proowner))
         ) as privilege
        where procedure.oid in (
          'public.get_my_review_capabilities()'::regprocedure,
          'public.list_my_review_queue()'::regprocedure,
          'public.get_my_review_case(text, uuid)'::regprocedure
        )
          and privilege.privilege_type = 'EXECUTE'
          and privilege.grantee = 0
     ) then
    raise exception 'Review read functions have the wrong execute grants';
  end if;

  if pg_catalog.pg_get_function_identity_arguments(
       'public.get_my_review_capabilities()'::regprocedure
     ) <> ''
     or pg_catalog.pg_get_function_identity_arguments(
       'public.list_my_review_queue()'::regprocedure
     ) <> ''
     or pg_catalog.pg_get_function_identity_arguments(
       'public.get_my_review_case(text, uuid)'::regprocedure
     ) <> 'p_case_type text, p_case_id uuid' then
    raise exception 'Review read functions accept an actor, a scope, or a market';
  end if;

  if pg_catalog.pg_get_functiondef('public.list_my_review_queue()'::regprocedure)
       not like '%limit 50%' then
    raise exception 'Review queue is not capped';
  end if;

  select account.person_id, account.id
    into reviewer_person, reviewer_account
    from public.user_accounts as account
   where account.auth_user_id = '04010000-0000-4000-8000-000000000001';

  select account.person_id, account.id
    into subject_person, subject_account
    from public.user_accounts as account
   where account.auth_user_id = '04010000-0000-4000-8000-000000000002';

  select account.person_id
    into hipica_person
    from public.user_accounts as account
   where account.auth_user_id = '04010000-0000-4000-8000-000000000003';

  select account.person_id
    into platform_person
    from public.user_accounts as account
   where account.auth_user_id = '04010000-0000-4000-8000-000000000004';

  select account.person_id
    into member_only_person
    from public.user_accounts as account
   where account.auth_user_id = '04010000-0000-4000-8000-000000000005';

  update public.persons
     set display_name = 'Visible Subject',
         first_name = 'Visible',
         last_name = 'Subject'
   where id = subject_person;

  insert into public.center_memberships (center_id, person_id, role_code)
  values
    ('04010000-0000-4000-8000-0000000000c1', hipica_person, 'ADMIN'),
    ('04010000-0000-4000-8000-0000000000c1', member_only_person, 'ADMIN');

  insert into public.verification_review_grants (
    reviewer_person_id,
    scope_type,
    market_country_code
  ) values
    (reviewer_person, 'MARKET', 'ES'),
    (hipica_person, 'MARKET', 'ES');

  insert into public.verification_review_grants (reviewer_person_id, scope_type)
  values (platform_person, 'PLATFORM_IDENTITY');

  insert into public.identity_verification_cases (
    id,
    subject_person_id,
    market_country_code,
    state,
    submitted_by_account_id,
    updated_at
  ) values
    (
      '04010000-0000-4000-8000-0000000000a1',
      subject_person,
      'ES',
      'SUBMITTED',
      subject_account,
      now() - interval '2 minutes'
    ),
    (
      '04010000-0000-4000-8000-0000000000a2',
      reviewer_person,
      'ES',
      'IN_REVIEW',
      subject_account,
      now()
    ),
    (
      '04010000-0000-4000-8000-0000000000a3',
      subject_person,
      'ZZ',
      'SUBMITTED',
      subject_account,
      now()
    ),
    (
      '04010000-0000-4000-8000-0000000000a4',
      subject_person,
      'ES',
      'DRAFT',
      subject_account,
      now()
    );

  insert into public.equine_ownership_claims (
    id,
    equine_id,
    market_country_code,
    state,
    owner_type,
    owner_person_id,
    ownership_percentage,
    submitted_by_account_id,
    updated_at
  ) values (
    '04010000-0000-4000-8000-0000000000b1',
    '04010000-0000-4000-8000-0000000000e1',
    'ES',
    'RESUBMITTED',
    'PERSON',
    subject_person,
    100,
    subject_account,
    now() - interval '1 minute'
  );

  insert into public.equine_ownership_claims (
    id,
    equine_id,
    market_country_code,
    state,
    owner_type,
    owner_center_id,
    ownership_percentage,
    submitted_by_account_id,
    updated_at
  ) values (
    '04010000-0000-4000-8000-0000000000b2',
    '04010000-0000-4000-8000-0000000000e1',
    'ES',
    'SUBMITTED',
    'CENTER',
    '04010000-0000-4000-8000-0000000000c1',
    100,
    subject_account,
    now() - interval '3 minutes'
  );

  insert into public.equine_ownership_claims (
    id,
    equine_id,
    market_country_code,
    state,
    owner_type,
    owner_person_id,
    ownership_percentage,
    submitted_by_account_id
  ) values (
    '04010000-0000-4000-8000-0000000000b3',
    '04010000-0000-4000-8000-0000000000e1',
    'ES',
    'ACCEPTED',
    'PERSON',
    subject_person,
    100,
    subject_account
  );

  insert into public.equine_management_authority_claims (
    id,
    equine_id,
    market_country_code,
    state,
    manager_type,
    manager_person_id,
    management_role,
    valid_from,
    submitted_by_account_id,
    updated_at
  ) values (
    '04010000-0000-4000-8000-0000000000c2',
    '04010000-0000-4000-8000-0000000000e1',
    'ES',
    'IN_REVIEW',
    'PERSON',
    subject_person,
    'PRIMARY_MANAGER',
    now() - interval '1 day',
    subject_account,
    now()
  );

  insert into public.verification_evidence (
    parent_type,
    identity_case_id,
    category,
    document_country_code,
    provider_reference,
    submitted_by_account_id
  ) values (
    'IDENTITY_CASE',
    '04010000-0000-4000-8000-0000000000a1',
    'IDENTITY_PROVIDER_REFERENCE',
    'ES',
    'PRIVATE-REF-040',
    subject_account
  );

  insert into public.verification_evidence (
    parent_type,
    identity_case_id,
    category,
    note_text,
    submitted_by_account_id
  ) values (
    'IDENTITY_CASE',
    '04010000-0000-4000-8000-0000000000a1',
    'REVIEWER_NOTE',
    'PRIVATE-NOTE-040',
    subject_account
  );

  insert into public.verification_evidence (
    parent_type,
    ownership_claim_id,
    category,
    document_country_code,
    storage_bucket,
    storage_path,
    submitted_by_account_id
  ) values
    (
      'OWNERSHIP_CLAIM',
      '04010000-0000-4000-8000-0000000000b1',
      'EQUINE_IDENTIFIER_REFERENCE',
      'ES',
      'private-bucket',
      'PRIVATE-PATH-040',
      subject_account
    ),
    (
      'OWNERSHIP_CLAIM',
      '04010000-0000-4000-8000-0000000000b1',
      'OWNERSHIP_ARTIFACT',
      'FR',
      'private-bucket',
      'PRIVATE-PATH-040',
      subject_account
    );

  insert into public.verification_evidence (
    parent_type,
    management_claim_id,
    category,
    storage_bucket,
    storage_path,
    submitted_by_account_id
  ) values (
    'MANAGEMENT_CLAIM',
    '04010000-0000-4000-8000-0000000000c2',
    'CENTER_CORROBORATION',
    'private-bucket',
    'PRIVATE-PATH-040',
    subject_account
  );

  perform set_config('request.jwt.claim.sub', '04010000-0000-4000-8000-000000000001', true);
  perform set_config(
    'request.jwt.claims',
    '{"sub":"04010000-0000-4000-8000-000000000001","role":"authenticated"}',
    true
  );

  if (
    select count(*)
      from public.get_my_review_capabilities() as capability
     where capability.scope_type = 'MARKET'
       and capability.market_country_code = 'ES'
  ) <> 1 then
    raise exception 'Spain reviewer did not receive only MARKET / ES';
  end if;

  select array_agg(queued.case_id order by queued.updated_at desc, queued.case_type, queued.case_id)
    into queue_ids
    from public.list_my_review_queue() as queued;

  if queue_ids is distinct from array[
    '04010000-0000-4000-8000-0000000000c2'::uuid,
    '04010000-0000-4000-8000-0000000000b1'::uuid,
    '04010000-0000-4000-8000-0000000000a1'::uuid,
    '04010000-0000-4000-8000-0000000000b2'::uuid
  ]::uuid[] then
    raise exception 'Review queue order or membership was %', queue_ids;
  end if;

  if exists (
    select 1
      from public.list_my_review_queue() as queued
     where queued::text like '%PRIVATE-%'
        or queued::text like '%Visible Subject%'
        or queued::text like '%Pilot Horse%'
  ) then
    raise exception 'Review queue returned a name or a private evidence field';
  end if;

  select detail.*
    into detail_row
    from public.get_my_review_case(
      'IDENTITY',
      '04010000-0000-4000-8000-0000000000a1'
    ) as detail;

  if detail_row.subject_name is distinct from 'Visible Subject'
     or detail_row.evidence_sufficient is not true
     or detail_row.evidence::text not like '%IDENTITY_PROVIDER_REFERENCE%'
     or detail_row.evidence::text not like '%ES%'
     or detail_row.evidence::text like '%PRIVATE-%'
     or detail_row::text like '%PRIVATE-%' then
    raise exception 'Identity detail leaked private evidence or omitted the subject';
  end if;

  select count(*)
    into audit_count
    from public.audit_events as event
   where event.event_type = 'verification_review_opened'
     and event.entity_type = 'identity_verification_case'
     and event.entity_id = '04010000-0000-4000-8000-0000000000a1'
     and event.actor_account_id = reviewer_account
     and event.actor_person_id = reviewer_person
     and event.metadata = jsonb_build_object(
       'case_type', 'IDENTITY',
       'market_country_code', 'ES',
       'state', 'SUBMITTED'
     );

  if audit_count <> 1 then
    raise exception 'Opening the identity case was not audited safely';
  end if;

  select detail.*
    into detail_row
    from public.get_my_review_case(
      'OWNERSHIP',
      '04010000-0000-4000-8000-0000000000b1'
    ) as detail;

  if detail_row.equine_name is distinct from 'Pilot Horse'
     or detail_row.relation_type is distinct from 'PERSON'
     or detail_row.relation_role is distinct from 'OWNER'
     or detail_row.evidence_sufficient is not true
     or detail_row::text like '%PRIVATE-%' then
    raise exception 'Ownership detail was not the minimum authorized row';
  end if;

  select detail.*
    into detail_row
    from public.get_my_review_case(
      'MANAGEMENT',
      '04010000-0000-4000-8000-0000000000c2'
    ) as detail;

  if detail_row.relation_role is distinct from 'PRIMARY_MANAGER'
     or detail_row.evidence_sufficient is not false
     or detail_row::text like '%PRIVATE-%' then
    raise exception 'Management detail treated corroboration as sufficient or leaked a note';
  end if;

  begin
    perform public.get_my_review_case(
      'IDENTITY',
      '04010000-0000-4000-8000-0000000000a2'
    );
    raise exception 'Reviewer opened their own case';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    perform public.get_my_review_case(
      'IDENTITY',
      '04010000-0000-4000-8000-000000000099'
    );
    raise exception 'Missing case was distinguished from a conflict';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    perform public.get_my_review_case(
      'OWNERSHIP',
      '04010000-0000-4000-8000-0000000000a1'
    );
    raise exception 'Wrong case type was distinguished from a missing case';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    perform public.get_my_review_case(
      'IDENTITY',
      '04010000-0000-4000-8000-0000000000a3'
    );
    raise exception 'Another market was readable';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    perform public.get_my_review_case(
      'IDENTITY',
      '04010000-0000-4000-8000-0000000000a4'
    );
    raise exception 'A draft case was readable';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    perform public.get_my_review_case(
      'OWNERSHIP',
      '04010000-0000-4000-8000-0000000000b3'
    );
    raise exception 'A closed claim was readable';
  exception
    when insufficient_privilege then
      null;
  end;

  if (
    select count(*)
      from public.audit_events as event
     where event.event_type = 'verification_review_opened'
       and event.entity_id in (
         '04010000-0000-4000-8000-0000000000a2',
         '04010000-0000-4000-8000-000000000099',
         '04010000-0000-4000-8000-0000000000a3',
         '04010000-0000-4000-8000-0000000000a4',
         '04010000-0000-4000-8000-0000000000b3'
       )
  ) <> 0 then
    raise exception 'A refused opening wrote an audit event';
  end if;

  perform set_config('request.jwt.claim.sub', '04010000-0000-4000-8000-000000000003', true);
  perform set_config(
    'request.jwt.claims',
    '{"sub":"04010000-0000-4000-8000-000000000003","role":"authenticated"}',
    true
  );

  if exists (
    select 1
      from public.list_my_review_queue() as queued
     where queued.case_id = '04010000-0000-4000-8000-0000000000b2'
  ) then
    raise exception 'Center affiliation did not block the claimant center';
  end if;

  begin
    perform public.get_my_review_case(
      'OWNERSHIP',
      '04010000-0000-4000-8000-0000000000b2'
    );
    raise exception 'Center member opened the claimant-center claim';
  exception
    when insufficient_privilege then
      null;
  end;

  perform set_config('request.jwt.claim.sub', '04010000-0000-4000-8000-000000000004', true);
  perform set_config(
    'request.jwt.claims',
    '{"sub":"04010000-0000-4000-8000-000000000004","role":"authenticated"}',
    true
  );

  if exists (select 1 from public.get_my_review_capabilities()) then
    raise exception 'A platform grant became a Spain pilot capability';
  end if;

  begin
    perform public.list_my_review_queue();
    raise exception 'A platform grant listed the Spain queue';
  exception
    when insufficient_privilege then
      null;
  end;

  perform set_config('request.jwt.claim.sub', '04010000-0000-4000-8000-000000000005', true);
  perform set_config(
    'request.jwt.claims',
    '{"sub":"04010000-0000-4000-8000-000000000005","role":"authenticated"}',
    true
  );

  if exists (select 1 from public.get_my_review_capabilities()) then
    raise exception 'Center membership granted review capability';
  end if;

  begin
    perform public.list_my_review_queue();
    raise exception 'Center membership listed the review queue';
  exception
    when insufficient_privilege then
      null;
  end;

  perform public.suspend_verification_review_grant(
    (
      select grant_row.id
        from public.verification_review_grants as grant_row
       where grant_row.reviewer_person_id = reviewer_person
         and grant_row.status = 'ACTIVE'
    )
  );

  perform set_config('request.jwt.claim.sub', '04010000-0000-4000-8000-000000000001', true);
  perform set_config(
    'request.jwt.claims',
    '{"sub":"04010000-0000-4000-8000-000000000001","role":"authenticated"}',
    true
  );

  if exists (select 1 from public.get_my_review_capabilities()) then
    raise exception 'A suspended grant still reported capability';
  end if;

  begin
    perform public.get_my_review_case(
      'IDENTITY',
      '04010000-0000-4000-8000-0000000000a1'
    );
    raise exception 'A suspended grant still opened a case';
  exception
    when insufficient_privilege then
      null;
  end;

  if (
    select count(*)
      from public.audit_events as event
     where event.event_type = 'verification_review_opened'
       and event.entity_id = '04010000-0000-4000-8000-0000000000a1'
  ) <> 1 then
    raise exception 'A suspended opening changed the audit history';
  end if;
end;
$$;

savepoint client_roles;

select set_config(
  'request.jwt.claim.sub',
  '04010000-0000-4000-8000-000000000005',
  true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"04010000-0000-4000-8000-000000000005","role":"authenticated"}',
  true
);
set local role authenticated;

do $$
begin
  if exists (select 1 from public.get_my_review_capabilities()) then
    raise exception 'authenticated without a grant received a capability';
  end if;

  begin
    perform public.list_my_review_queue();
    raise exception 'authenticated without a grant listed the queue';
  exception
    when insufficient_privilege then
      null;
  end;
end;
$$;

rollback to savepoint client_roles;

set local role anon;

do $$
begin
  perform public.get_my_review_capabilities();
  raise exception 'anon executed a review read';
exception
  when insufficient_privilege then
    null;
end;
$$;

rollback to savepoint client_roles;

set local role service_role;

do $$
begin
  perform public.list_my_review_queue();
  raise exception 'service_role listed the review queue';
exception
  when insufficient_privilege then
    null;
end;
$$;

rollback to savepoint client_roles;

rollback;
