-- Phase 3B local guardian/minor tests.
-- Assumes migrations 001-007 are applied and auth.uid() reads
-- request.jwt.claim.sub. Runnable without psql meta-commands.

begin;

do $$
declare
  fixture_auth uuid[] := array[
    '20000000-0000-0000-0000-000000000001'::uuid,
    '20000000-0000-0000-0000-000000000002'::uuid,
    '20000000-0000-0000-0000-000000000003'::uuid
  ];
  linked_person_ids uuid[];
begin
  delete from public.guardian_consents
   where granted_by_account_id in (
     select id from public.user_accounts where auth_user_id = any(fixture_auth)
   )
      or guardian_person_id in (
        select person_id from public.user_accounts where auth_user_id = any(fixture_auth)
      );

  delete from public.guardian_relationships
   where guardian_person_id in (
     select person_id from public.user_accounts where auth_user_id = any(fixture_auth)
   )
      or minor_person_id in (
        select person_id from public.user_accounts where auth_user_id = any(fixture_auth)
      );

  delete from public.policy_acceptances
   where user_account_id in (
     select id from public.user_accounts where auth_user_id = any(fixture_auth)
   );

  delete from public.policy_documents
   where market_code = 'ZZ';

  delete from public.market_age_rules
   where country_code in ('ZZ', 'YY', 'WW');

  delete from public.markets
   where country_code in ('ZZ', 'YY', 'WW');

  select coalesce(array_agg(person_id), '{}')
    into linked_person_ids
    from public.user_accounts
   where auth_user_id = any(fixture_auth);

  delete from public.user_accounts
   where auth_user_id = any(fixture_auth);

  delete from public.persons
   where id = any(linked_person_ids)
      or last_name in (
        'NoAccount',
        'RevokedRel',
        'ExpiredRel',
        'RejectedRel',
        'Boundary'
      );

  delete from auth.users
   where id = any(fixture_auth);
end;
$$;

insert into public.markets (country_code, status)
values ('ZZ', 'ACTIVE'), ('YY', 'ACTIVE'), ('WW', 'ACTIVE');

insert into public.market_age_rules (
  country_code,
  legal_adult_age,
  guardian_consent_required,
  effective_from
)
values ('ZZ', 18, true, date '2000-01-01');

insert into public.market_age_rules (
  country_code,
  legal_adult_age,
  guardian_consent_required,
  effective_from,
  effective_to
)
values
  ('WW', 16, true, date '2000-01-01', date '2020-01-01'),
  ('WW', 21, true, date '2020-01-01', null);

insert into auth.users (id)
values
  ('20000000-0000-0000-0000-000000000001'),
  ('20000000-0000-0000-0000-000000000002'),
  ('20000000-0000-0000-0000-000000000003');

do $$
declare
  guardian_person_id uuid;
  other_guardian_person_id uuid;
  minor_with_account_id uuid;
  minor_without_account_id uuid;
  revoked_rel_minor_id uuid;
  expired_rel_minor_id uuid;
  rejected_rel_minor_id uuid;
  boundary_person_id uuid;
  minority record;
begin
  if exists (
    select 1
      from information_schema.columns
     where table_schema = 'public'
       and table_name in ('persons', 'user_accounts')
       and column_name in ('is_minor', 'guardian_id')
  ) then
    raise exception 'Identity-level is_minor or guardian_id must not exist';
  end if;

  if (
    select count(*)
      from pg_catalog.pg_class
     where oid in (
       'public.guardian_relationships'::regclass,
       'public.guardian_consents'::regclass,
       'public.market_age_rules'::regclass
     )
       and relrowsecurity
  ) <> 3 then
    raise exception 'Guardian RLS is not enabled';
  end if;

  if exists (
    select 1
      from pg_catalog.pg_policy
     where polrelid in (
       'public.guardian_relationships'::regclass,
       'public.guardian_consents'::regclass,
       'public.market_age_rules'::regclass
     )
  ) then
    raise exception 'Guardian tables unexpectedly gained client RLS policies';
  end if;

  if exists (
    select 1
      from information_schema.tables
     where table_schema = 'public'
       and table_name = 'audit_events'
  ) then
    raise exception 'Canonical audit_events must remain deferred';
  end if;

  select person_id into guardian_person_id
    from public.user_accounts
   where auth_user_id = '20000000-0000-0000-0000-000000000001';

  select person_id into other_guardian_person_id
    from public.user_accounts
   where auth_user_id = '20000000-0000-0000-0000-000000000002';

  select person_id into minor_with_account_id
    from public.user_accounts
   where auth_user_id = '20000000-0000-0000-0000-000000000003';

  update public.persons
     set first_name = 'Guardian', last_name = 'One', date_of_birth = date '1980-01-01'
   where id = guardian_person_id;

  update public.persons
     set first_name = 'Guardian', last_name = 'Two', date_of_birth = date '1981-01-01'
   where id = other_guardian_person_id;

  update public.persons
     set first_name = 'Minor', last_name = 'Account', date_of_birth = date '2018-06-15'
   where id = minor_with_account_id;

  insert into public.persons (first_name, last_name, date_of_birth)
  values ('Minor', 'NoAccount', date '2012-01-01')
  returning id into minor_without_account_id;

  insert into public.persons (first_name, last_name, date_of_birth)
  values ('Minor', 'RevokedRel', date '2011-01-01')
  returning id into revoked_rel_minor_id;

  insert into public.persons (first_name, last_name, date_of_birth)
  values ('Minor', 'ExpiredRel', date '2011-06-01')
  returning id into expired_rel_minor_id;

  insert into public.persons (first_name, last_name, date_of_birth)
  values ('Minor', 'RejectedRel', date '2013-03-01')
  returning id into rejected_rel_minor_id;

  insert into public.persons (first_name, last_name, date_of_birth)
  values ('Adult', 'Boundary', date '2003-06-15')
  returning id into boundary_person_id;

  if exists (
    select 1 from public.user_accounts where person_id = minor_without_account_id
  ) then
    raise exception 'A minor must be able to exist without an Auth account';
  end if;

  begin
    insert into public.guardian_relationships (
      guardian_person_id, minor_person_id, relationship_type, verification_status
    ) values (guardian_person_id, guardian_person_id, 'PARENT', 'PENDING');
    raise exception 'Guardian and minor were allowed to be the same person';
  exception
    when check_violation then null;
  end;

  insert into public.guardian_relationships (
    guardian_person_id, minor_person_id, relationship_type, verification_status
  ) values (guardian_person_id, minor_without_account_id, 'PARENT', 'PENDING');

  insert into public.guardian_relationships (
    guardian_person_id, minor_person_id, relationship_type,
    verification_status, verified_at
  ) values (
    guardian_person_id, minor_with_account_id, 'PARENT', 'VERIFIED', now()
  );

  begin
    insert into public.guardian_relationships (
      guardian_person_id, minor_person_id, relationship_type,
      verification_status, verified_at
    ) values (
      guardian_person_id, minor_with_account_id, 'LEGAL_GUARDIAN', 'VERIFIED', now()
    );
    raise exception 'Duplicate active guardian relationship was allowed';
  exception
    when unique_violation then null;
  end;

  insert into public.guardian_relationships (
    guardian_person_id, minor_person_id, relationship_type,
    verification_status, verified_at
  ) values (
    other_guardian_person_id, minor_without_account_id, 'PARENT', 'VERIFIED', now()
  );

  insert into public.guardian_relationships (
    guardian_person_id, minor_person_id, relationship_type,
    verification_status, verified_at, revoked_at
  ) values (
    guardian_person_id, revoked_rel_minor_id, 'PARENT', 'REVOKED',
    now() - interval '10 days', now() - interval '1 day'
  );

  insert into public.guardian_relationships (
    guardian_person_id, minor_person_id, relationship_type,
    verification_status, verified_at, expires_at
  ) values (
    guardian_person_id, expired_rel_minor_id, 'PARENT', 'EXPIRED',
    now() - interval '400 days', now() - interval '1 day'
  );

  insert into public.guardian_relationships (
    guardian_person_id, minor_person_id, relationship_type, verification_status
  ) values (
    guardian_person_id, rejected_rel_minor_id, 'PARENT', 'REJECTED'
  );

  select * into minority
    from public.evaluate_person_minority(minor_with_account_id, 'ZZ', date '2036-06-14');
  if minority.age_years <> 17 or not minority.is_minor or not minority.guardian_consent_required then
    raise exception 'Age before birthday was incorrect';
  end if;

  select * into minority
    from public.evaluate_person_minority(minor_with_account_id, 'ZZ', date '2036-06-15');
  if minority.age_years <> 18 or minority.is_minor or minority.guardian_consent_required then
    raise exception 'Age on birthday was incorrect';
  end if;

  select * into minority
    from public.evaluate_person_minority(minor_with_account_id, 'ZZ', date '2036-06-16');
  if minority.age_years <> 18 or minority.is_minor then
    raise exception 'Age after birthday was incorrect';
  end if;

  select * into minority
    from public.evaluate_person_minority(boundary_person_id, 'WW', date '2019-06-15');
  if minority.age_years <> 16 or minority.is_minor then
    raise exception 'Effective market rule before 2020 was not used';
  end if;

  select * into minority
    from public.evaluate_person_minority(boundary_person_id, 'WW', date '2020-06-15');
  if minority.age_years <> 17 or not minority.is_minor then
    raise exception 'Effective market rule from 2020 was not used';
  end if;

  select * into minority
    from public.evaluate_person_minority(minor_with_account_id, 'WW', date '2036-06-15');
  if not minority.is_minor then
    raise exception 'A different market adult age was not applied';
  end if;

  begin
    perform * from public.evaluate_person_minority(minor_with_account_id, 'YY', date '2024-01-01');
    raise exception 'Missing market age rule did not fail closed';
  exception
    when raise_exception then
      if sqlerrm = 'Missing market age rule did not fail closed' then
        raise;
      end if;
  end;
end;
$$;

do $$
begin
  begin
    insert into public.market_age_rules (
      country_code, legal_adult_age, guardian_consent_required,
      effective_from, effective_to
    ) values ('ZZ', 16, true, date '2010-01-01', date '2030-01-01');
    raise exception 'Overlapping market age rules were allowed';
  exception
    when others then
      if sqlerrm = 'Overlapping market age rules were allowed' then
        raise;
      end if;
  end;
end;
$$;

insert into public.policy_documents (
  policy_code, policy_type, market_code, locale, version, title, content,
  effective_from, status, requires_reacceptance
) values (
  'GUARDIAN_POLICY', 'GUARDIAN_POLICY', 'ZZ', 'es', '1',
  'Guardian policy', 'Test guardian policy', now() - interval '1 day', 'ACTIVE', true
);

do $$
declare
  v_guardian_person_id uuid;
  v_minor_person_id uuid;
begin
  select account.person_id into v_guardian_person_id
    from public.user_accounts as account
   where account.auth_user_id = '20000000-0000-0000-0000-000000000001';

  select account.person_id into v_minor_person_id
    from public.user_accounts as account
   where account.auth_user_id = '20000000-0000-0000-0000-000000000003';

  perform set_config('app.guardian_person', v_guardian_person_id::text, true);
  perform set_config('app.minor_account', v_minor_person_id::text, true);
  perform set_config(
    'app.verified_rel',
    (
      select relationship.id::text
        from public.guardian_relationships as relationship
       where relationship.guardian_person_id = v_guardian_person_id
         and relationship.minor_person_id = v_minor_person_id
         and relationship.verification_status = 'VERIFIED'
    ),
    true
  );
  perform set_config(
    'app.pending_rel',
    (
      select relationship.id::text
        from public.guardian_relationships as relationship
       where relationship.guardian_person_id = v_guardian_person_id
         and relationship.verification_status = 'PENDING'
    ),
    true
  );
  perform set_config(
    'app.other_rel',
    (
      select relationship.id::text
        from public.guardian_relationships as relationship
       where relationship.verification_status = 'VERIFIED'
         and relationship.guardian_person_id <> v_guardian_person_id
       limit 1
    ),
    true
  );
  perform set_config(
    'app.revoked_rel',
    (
      select relationship.id::text
        from public.guardian_relationships as relationship
       where relationship.guardian_person_id = v_guardian_person_id
         and relationship.verification_status = 'REVOKED'
    ),
    true
  );
  perform set_config(
    'app.expired_rel',
    (
      select relationship.id::text
        from public.guardian_relationships as relationship
       where relationship.guardian_person_id = v_guardian_person_id
         and relationship.verification_status = 'EXPIRED'
    ),
    true
  );
  perform set_config(
    'app.rejected_rel',
    (
      select relationship.id::text
        from public.guardian_relationships as relationship
       where relationship.guardian_person_id = v_guardian_person_id
         and relationship.verification_status = 'REJECTED'
    ),
    true
  );
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '20000000-0000-0000-0000-000000000001', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"20000000-0000-0000-0000-000000000001"}',
  true
);

do $$
declare
  verified_relationship_id uuid := current_setting('app.verified_rel', true)::uuid;
  pending_relationship_id uuid := current_setting('app.pending_rel', true)::uuid;
  other_verified_relationship_id uuid := current_setting('app.other_rel', true)::uuid;
  revoked_relationship_id uuid := current_setting('app.revoked_rel', true)::uuid;
  expired_relationship_id uuid := current_setting('app.expired_rel', true)::uuid;
  rejected_relationship_id uuid := current_setting('app.rejected_rel', true)::uuid;
begin
  begin
    update public.guardian_relationships
       set verification_status = 'VERIFIED', verified_at = now()
     where id = pending_relationship_id;
    raise exception 'Authenticated role self-verified a relationship';
  exception
    when insufficient_privilege then null;
  end;

  begin
    insert into public.guardian_consents (
      guardian_relationship_id, guardian_person_id, minor_person_id,
      granted_by_account_id, consent_type, scope_type, terms_version, status
    ) values (
      verified_relationship_id,
      current_setting('app.guardian_person', true)::uuid,
      current_setting('app.minor_account', true)::uuid,
      '20000000-0000-0000-0000-000000000001',
      'EQUESTRIAN_ACTIVITY', 'GENERAL', 'forged', 'ACTIVE'
    );
    raise exception 'Authenticated role forged consent by direct insert';
  exception
    when insufficient_privilege then null;
  end;

  begin
    update public.guardian_consents set status = 'ACTIVE', revoked_at = null;
    raise exception 'Authenticated role forged consent by direct update';
  exception
    when insufficient_privilege then null;
  end;

  begin
    delete from public.guardian_consents;
    raise exception 'Authenticated role deleted historical consents';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform * from public.guardian_relationships;
    raise exception 'Authenticated role selected guardian relationships directly';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform * from public.grant_guardian_consent(
      pending_relationship_id, 'EQUESTRIAN_ACTIVITY', 'GENERAL', 'v1', 'ZZ', null
    );
    raise exception 'Pending relationship authorized consent';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform * from public.grant_guardian_consent(
      revoked_relationship_id, 'EQUESTRIAN_ACTIVITY', 'GENERAL', 'v1', 'ZZ', null
    );
    raise exception 'Revoked relationship authorized consent';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform * from public.grant_guardian_consent(
      expired_relationship_id, 'EQUESTRIAN_ACTIVITY', 'GENERAL', 'v1', 'ZZ', null
    );
    raise exception 'Expired relationship authorized consent';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform * from public.grant_guardian_consent(
      rejected_relationship_id, 'EQUESTRIAN_ACTIVITY', 'GENERAL', 'v1', 'ZZ', null
    );
    raise exception 'Rejected relationship authorized consent';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform * from public.grant_guardian_consent(
      other_verified_relationship_id, 'EQUESTRIAN_ACTIVITY', 'GENERAL', 'v1', 'ZZ', null
    );
    raise exception 'Caller granted consent as another guardian';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform * from public.grant_guardian_consent(
      verified_relationship_id, 'EQUESTRIAN_ACTIVITY', 'GENERAL', 'v1', 'ZZ', null
    );
    raise exception 'Grant succeeded without required guardian policy acceptance';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

reset role;

insert into public.policy_acceptances (
  policy_document_id, person_id, user_account_id, accepted_at
)
select document.id, account.person_id, account.id, now()
from public.policy_documents as document
join public.user_accounts as account
  on account.auth_user_id = '20000000-0000-0000-0000-000000000001'
where document.market_code = 'ZZ'
  and document.policy_type = 'GUARDIAN_POLICY';

set local role authenticated;
select set_config('request.jwt.claim.sub', '20000000-0000-0000-0000-000000000001', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"20000000-0000-0000-0000-000000000001"}',
  true
);

do $$
declare
  verified_relationship_id uuid := current_setting('app.verified_rel', true)::uuid;
  minor_with_account_id uuid := current_setting('app.minor_account', true)::uuid;
  grant_row record;
  revoke_row record;
  check_result record;
  listed_count integer;
  consent_count integer;
begin
  if not public.has_accepted_required_policy('GUARDIAN_POLICY', 'ZZ') then
    raise exception 'Guardian policy acceptance was not visible to the caller';
  end if;

  select * into check_result
  from public.check_guardian_consent(
    minor_with_account_id, 'EQUESTRIAN_ACTIVITY', 'GENERAL', 'ZZ',
    (timezone('utc', now()))::date
  );
  if check_result.consent_valid then
    raise exception 'Policy acceptance satisfied guardian consent';
  end if;

  select * into grant_row
  from public.grant_guardian_consent(
    verified_relationship_id, 'EQUESTRIAN_ACTIVITY', 'GENERAL', 'v1', 'ZZ', null
  );

  if grant_row.id is null or grant_row.status <> 'ACTIVE' then
    raise exception 'Authorized grant_guardian_consent failed';
  end if;

  if (
    select count(*)
      from public.list_my_guardian_consents()
     where status = 'ACTIVE'
  ) <> 1 then
    raise exception 'Authorized grant did not produce exactly one active consent';
  end if;

  perform set_config('app.granted_consent', grant_row.id::text, true);

  select * into check_result
  from public.check_guardian_consent(
    minor_with_account_id, 'EQUESTRIAN_ACTIVITY', 'GENERAL', 'ZZ',
    (timezone('utc', now()))::date
  );

  if not check_result.consent_required or not check_result.consent_valid then
    raise exception 'Active consent was not valid';
  end if;

  select * into revoke_row from public.revoke_guardian_consent(grant_row.id);
  if revoke_row.status <> 'REVOKED' or revoke_row.revoked_at is null then
    raise exception 'Revocation did not take effect';
  end if;

  select * into revoke_row from public.revoke_guardian_consent(grant_row.id);
  if revoke_row.status <> 'REVOKED' then
    raise exception 'Repeated revocation was not idempotent';
  end if;

  select * into check_result
  from public.check_guardian_consent(
    minor_with_account_id, 'EQUESTRIAN_ACTIVITY', 'GENERAL', 'ZZ',
    (timezone('utc', now()))::date
  );
  if check_result.consent_valid then
    raise exception 'Revoked consent remained valid';
  end if;

  select count(*) into consent_count
    from public.list_my_guardian_consents()
   where id = grant_row.id;
  if consent_count <> 1 then
    raise exception 'Revocation deleted historical consent';
  end if;

  select count(*) into listed_count from public.list_my_guardian_relationships();
  if listed_count < 1 then
    raise exception 'Guardian could not list own relationships';
  end if;
end;
$$;

select set_config('request.jwt.claim.sub', '20000000-0000-0000-0000-000000000002', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"20000000-0000-0000-0000-000000000002"}',
  true
);

do $$
declare
  listed_count integer;
  consent_count integer;
  other_minor uuid := current_setting('app.minor_account', true)::uuid;
begin
  select count(*) into listed_count
    from public.list_my_guardian_relationships() as listed
   where listed.minor_person_id = other_minor;

  if listed_count <> 0 then
    raise exception 'Guardian listed another guardian relationship';
  end if;

  select count(*) into consent_count from public.list_my_guardian_consents();
  if consent_count <> 0 then
    raise exception 'Guardian listed another guardian consents';
  end if;

  begin
    perform * from public.check_guardian_consent(
      other_minor, 'EQUESTRIAN_ACTIVITY', 'GENERAL', 'ZZ',
      (timezone('utc', now()))::date
    );
    raise exception 'Unrelated guardian checked another guardian minor';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

select set_config('request.jwt.claim.sub', '20000000-0000-0000-0000-000000000003', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"20000000-0000-0000-0000-000000000003"}',
  true
);

do $$
declare
  verified_relationship_id uuid := current_setting('app.verified_rel', true)::uuid;
begin
  begin
    perform * from public.grant_guardian_consent(
      verified_relationship_id, 'EQUESTRIAN_ACTIVITY', 'GENERAL', 'v1', 'ZZ', null
    );
    raise exception 'Minor granted their own guardian consent';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

reset role;

do $$
declare
  v_guardian_person_id uuid;
  v_guardian_account_id uuid;
  v_minor_person_id uuid;
  v_verified_relationship_id uuid;
  v_expired_consent_id uuid;
begin
  select account.person_id, account.id
    into v_guardian_person_id, v_guardian_account_id
    from public.user_accounts as account
   where account.auth_user_id = '20000000-0000-0000-0000-000000000001';

  select account.person_id into v_minor_person_id
    from public.user_accounts as account
   where account.auth_user_id = '20000000-0000-0000-0000-000000000003';

  select relationship.id into v_verified_relationship_id
    from public.guardian_relationships as relationship
   where relationship.guardian_person_id = v_guardian_person_id
     and relationship.verification_status = 'VERIFIED'
     and relationship.minor_person_id = v_minor_person_id;

  insert into public.guardian_consents (
    guardian_relationship_id, guardian_person_id, minor_person_id,
    granted_by_account_id, consent_type, scope_type, terms_version, status,
    granted_at, expires_at
  ) values (
    v_verified_relationship_id, v_guardian_person_id, v_minor_person_id,
    v_guardian_account_id, 'EQUESTRIAN_ACTIVITY', 'GENERAL', 'expired-fixture',
    'ACTIVE', now() - interval '10 days', now() - interval '1 minute'
  ) returning id into v_expired_consent_id;

  if v_expired_consent_id is null then
    raise exception 'Expired consent fixture was not created';
  end if;

  if (
    select consent.status
      from public.guardian_consents as consent
     where consent.id = v_expired_consent_id
  ) is distinct from 'ACTIVE' then
    raise exception 'Time-expired fixture must remain ACTIVE until grant normalizes it';
  end if;

  perform set_config('app.expired_consent', v_expired_consent_id::text, true);

  if (
    select count(*) from public.policy_acceptances as acceptance
     where acceptance.person_id = v_guardian_person_id
  ) <> 1 then
    raise exception 'Grant created or removed policy acceptances';
  end if;
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '20000000-0000-0000-0000-000000000001', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"20000000-0000-0000-0000-000000000001"}',
  true
);

do $$
declare
  minor_with_account_id uuid := current_setting('app.minor_account', true)::uuid;
  verified_relationship_id uuid := current_setting('app.verified_rel', true)::uuid;
  check_result record;
  grant_row record;
  expired_count integer;
  active_count integer;
begin
  select * into check_result
  from public.check_guardian_consent(
    minor_with_account_id, 'EQUESTRIAN_ACTIVITY', 'GENERAL', 'ZZ',
    (timezone('utc', now()))::date
  );

  if check_result.consent_valid then
    raise exception 'Expired consent remained valid';
  end if;
end;
$$;

reset role;

do $$
declare
  fixture_id uuid := current_setting('app.expired_consent', true)::uuid;
  fixture_status text;
begin
  select consent.status
    into fixture_status
    from public.guardian_consents as consent
   where consent.id = fixture_id;

  if fixture_status is distinct from 'ACTIVE' then
    raise exception
      'check_guardian_consent mutated time-expired ACTIVE status to %',
      fixture_status;
  end if;
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '20000000-0000-0000-0000-000000000001', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"20000000-0000-0000-0000-000000000001"}',
  true
);

do $$
declare
  verified_relationship_id uuid := current_setting('app.verified_rel', true)::uuid;
  grant_row record;
  expired_count integer;
  active_count integer;
begin
  begin
    perform * from public.grant_guardian_consent(
      verified_relationship_id,
      'EQUESTRIAN_ACTIVITY',
      'GENERAL',
      'v-past',
      'ZZ',
      now() - interval '1 hour'
    );
    raise exception 'Grant accepted a past consent expiry';
  exception
    when invalid_parameter_value then null;
  end;

  select * into grant_row
  from public.grant_guardian_consent(
    verified_relationship_id, 'EQUESTRIAN_ACTIVITY', 'GENERAL', 'v-renew', 'ZZ', null
  );

  if grant_row.id is null or grant_row.status <> 'ACTIVE' then
    raise exception 'Time-expired consent blocked a new grant';
  end if;

  select count(*) into expired_count
    from public.list_my_guardian_consents()
   where status = 'EXPIRED';
  select count(*) into active_count
    from public.list_my_guardian_consents()
   where status = 'ACTIVE';

  if expired_count < 1 then
    raise exception 'Time-expired consent was not retained as historical evidence';
  end if;

  if active_count <> 1 then
    raise exception 'Renewal did not leave exactly one active consent';
  end if;
end;
$$;

set local role anon;
select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claims', '', true);

do $$
begin
  begin
    perform * from public.grant_guardian_consent(
      '20000000-0000-0000-0000-000000000099',
      'EQUESTRIAN_ACTIVITY', 'GENERAL', 'v1', 'ZZ', null
    );
    raise exception 'Anonymous role granted consent';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform * from public.list_my_guardian_relationships();
    raise exception 'Anonymous role listed relationships';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform * from public.guardian_consents;
    raise exception 'Anonymous role read consents';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform * from public.evaluate_person_minority(
      '20000000-0000-0000-0000-000000000001', 'ZZ', current_date
    );
    raise exception 'Anonymous role executed minority evaluation';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

reset role;

do $$
begin
  if has_table_privilege('authenticated', 'public.guardian_relationships', 'select')
     or has_table_privilege('authenticated', 'public.guardian_relationships', 'insert')
     or has_table_privilege('authenticated', 'public.guardian_relationships', 'update')
     or has_table_privilege('authenticated', 'public.guardian_relationships', 'delete')
     or has_table_privilege('authenticated', 'public.guardian_consents', 'select')
     or has_table_privilege('authenticated', 'public.guardian_consents', 'insert')
     or has_table_privilege('authenticated', 'public.guardian_consents', 'update')
     or has_table_privilege('authenticated', 'public.guardian_consents', 'delete')
     or has_table_privilege('authenticated', 'public.market_age_rules', 'select')
     or has_table_privilege('anon', 'public.guardian_relationships', 'select')
     or has_table_privilege('anon', 'public.guardian_consents', 'select') then
    raise exception 'Guardian tables expose forbidden client privileges';
  end if;

  if has_function_privilege(
       'authenticated',
       'public.evaluate_person_minority(uuid,text,date)',
       'execute'
     )
     or has_function_privilege(
       'anon',
       'public.grant_guardian_consent(uuid,text,text,text,text,timestamp with time zone)',
       'execute'
     )
     or not has_function_privilege(
       'authenticated',
       'public.grant_guardian_consent(uuid,text,text,text,text,timestamp with time zone)',
       'execute'
     )
     or not has_function_privilege(
       'authenticated',
       'public.revoke_guardian_consent(uuid)',
       'execute'
     ) then
    raise exception 'Guardian function grants are not least-privilege';
  end if;

  if (
    select count(*)
      from pg_catalog.pg_proc as procedure
      join pg_catalog.pg_namespace as namespace
        on namespace.oid = procedure.pronamespace
     where namespace.nspname = 'public'
       and procedure.proname in (
         'evaluate_person_minority',
         'has_accepted_required_policy',
         'grant_guardian_consent',
         'revoke_guardian_consent',
         'check_guardian_consent',
         'list_my_guardian_relationships',
         'list_my_guardian_consents'
       )
       and procedure.prosecdef
       and procedure.proconfig @> array['search_path=pg_catalog, public']
  ) <> 7 then
    raise exception 'Guardian functions lack required security settings';
  end if;

  if exists (
    select 1
      from pg_catalog.pg_proc as procedure
      join pg_catalog.pg_namespace as namespace
        on namespace.oid = procedure.pronamespace
     where namespace.nspname = 'public'
       and procedure.proname in (
         'verify_guardian_relationship',
         'set_guardian_verification'
       )
  ) then
    raise exception 'Verification RPC must remain deferred';
  end if;

  if position(
       'rule.legal_adult_age' in
       pg_get_functiondef('public.evaluate_person_minority(uuid,text,date)'::regprocedure)
     ) = 0 then
    raise exception 'Minority evaluation does not use the market legal_adult_age';
  end if;

  if position(
       'for update' in
       lower(pg_get_functiondef(
         'public.grant_guardian_consent(uuid,text,text,text,text,timestamp with time zone)'::regprocedure
       ))
     ) = 0 then
    raise exception 'grant_guardian_consent does not lock rows for concurrent renewal';
  end if;

  if not exists (
    select 1
      from pg_catalog.pg_index as idx
      join pg_catalog.pg_class as cls on cls.oid = idx.indexrelid
     where idx.indrelid = 'public.guardian_consents'::regclass
       and cls.relname = 'guardian_consents_active_scope_uidx'
       and idx.indisunique
  ) then
    raise exception 'Unique active consent index is missing';
  end if;

  if (
    select procedure.provolatile
      from pg_catalog.pg_proc as procedure
      join pg_catalog.pg_namespace as namespace
        on namespace.oid = procedure.pronamespace
     where namespace.nspname = 'public'
       and procedure.proname = 'check_guardian_consent'
  ) is distinct from 's' then
    raise exception 'check_guardian_consent must remain STABLE so validation does not mutate rows';
  end if;
end;
$$;

rollback;
