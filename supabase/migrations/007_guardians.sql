-- Phase 3B: Guardians and minors foundation.
--
-- Adds market-aware age rules (missing from migration 002), guardian
-- relationships, guardian consents, and server-authoritative RPCs.
-- Does not implement bookings, equines, centers, verification authority,
-- or canonical audit_events.
--
-- Access model follows migration 006:
--   - RLS enabled, deny-by-default, no client table policies.
--   - No table INSERT/UPDATE/DELETE/SELECT for anon or authenticated.
--   - Authenticated reads/writes go through SECURITY DEFINER RPCs.
--   - Actor identity is derived from auth.uid() only.
--
-- Architecture 2.1 requires market_age_rules. Migration 002 created only
-- public.markets. The table is added here as the smallest forward-compatible
-- correction. No legal adult-age values are seeded.

-- ---------------------------------------------------------------------------
-- Market age rules
-- ---------------------------------------------------------------------------

create table public.market_age_rules (
  id uuid primary key default gen_random_uuid(),
  country_code text not null references public.markets (country_code),
  legal_adult_age integer not null,
  guardian_consent_required boolean not null,
  effective_from date not null,
  effective_to date,
  config jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint market_age_rules_adult_age_check
    check (legal_adult_age > 0 and legal_adult_age <= 25),
  constraint market_age_rules_effective_period_check
    check (effective_to is null or effective_to > effective_from)
);

comment on table public.market_age_rules is
  'Effective-dated market rules for minority and guardian-consent evaluation. Concrete legal values require Product Owner validation and are not seeded here.';
comment on column public.market_age_rules.legal_adult_age is
  'Market-specific adult age in whole years. Not a universal hardcoded constant.';

create index market_age_rules_market_effective_idx
  on public.market_age_rules (country_code, effective_from);

create function public.market_age_rules_reject_overlap()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  if exists (
    select 1
      from public.market_age_rules as existing
     where existing.country_code = new.country_code
       and existing.id is distinct from new.id
       and daterange(
             existing.effective_from,
             existing.effective_to,
             '[)'
           ) && daterange(new.effective_from, new.effective_to, '[)')
  ) then
    raise exception using
      errcode = '23P01',
      message = 'Overlapping market age rules are not allowed';
  end if;

  return new;
end;
$$;

create trigger market_age_rules_no_overlap
before insert or update on public.market_age_rules
for each row execute function public.market_age_rules_reject_overlap();

alter table public.market_age_rules enable row level security;
revoke all on table public.market_age_rules from anon, authenticated;
revoke all on function public.market_age_rules_reject_overlap()
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Guardian relationships
-- ---------------------------------------------------------------------------

create table public.guardian_relationships (
  id uuid primary key default gen_random_uuid(),
  guardian_person_id uuid not null references public.persons (id),
  minor_person_id uuid not null references public.persons (id),
  relationship_type text not null,
  verification_status text not null default 'PENDING',
  verified_at timestamptz,
  expires_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint guardian_relationships_distinct_persons_check
    check (guardian_person_id <> minor_person_id),
  constraint guardian_relationships_type_check
    check (
      relationship_type in ('PARENT', 'LEGAL_GUARDIAN', 'OTHER')
    ),
  constraint guardian_relationships_status_check
    check (
      verification_status in (
        'PENDING',
        'VERIFIED',
        'REJECTED',
        'REVOKED',
        'EXPIRED'
      )
    ),
  constraint guardian_relationships_lifecycle_check
    check (
      (
        verification_status = 'PENDING'
        and verified_at is null
        and revoked_at is null
      )
      or (
        verification_status = 'VERIFIED'
        and verified_at is not null
        and revoked_at is null
      )
      or (
        verification_status = 'REJECTED'
        and verified_at is null
        and revoked_at is null
      )
      or (
        verification_status = 'REVOKED'
        and revoked_at is not null
      )
      or (
        verification_status = 'EXPIRED'
        and verified_at is not null
        and expires_at is not null
        and revoked_at is null
      )
    )
);

comment on table public.guardian_relationships is
  'Guardian-to-minor domain relationship. Distinct from guardian consent and from policy acceptance. Verification authority is not implemented in this phase; client roles cannot set VERIFIED.';

create unique index guardian_relationships_active_pair_uidx
  on public.guardian_relationships (guardian_person_id, minor_person_id)
  where verification_status in ('PENDING', 'VERIFIED');

create index guardian_relationships_guardian_idx
  on public.guardian_relationships (guardian_person_id);

create index guardian_relationships_minor_idx
  on public.guardian_relationships (minor_person_id);

create function public.guardian_relationships_reject_client_verification()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  if current_user in ('anon', 'authenticated')
     and (
       (tg_op = 'INSERT' and new.verification_status = 'VERIFIED')
       or (
         tg_op = 'UPDATE'
         and new.verification_status = 'VERIFIED'
         and old.verification_status is distinct from 'VERIFIED'
       )
     ) then
    raise exception using
      errcode = '42501',
      message = 'Guardian relationship verification is not available to clients';
  end if;

  return new;
end;
$$;

create trigger guardian_relationships_no_client_verification
before insert or update on public.guardian_relationships
for each row execute function public.guardian_relationships_reject_client_verification();

alter table public.guardian_relationships enable row level security;
revoke all on table public.guardian_relationships from anon, authenticated;
revoke all on function public.guardian_relationships_reject_client_verification()
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Guardian consents
-- ---------------------------------------------------------------------------

create table public.guardian_consents (
  id uuid primary key default gen_random_uuid(),
  guardian_relationship_id uuid not null
    references public.guardian_relationships (id),
  guardian_person_id uuid not null references public.persons (id),
  minor_person_id uuid not null references public.persons (id),
  granted_by_account_id uuid not null references public.user_accounts (id),
  consent_type text not null,
  scope_type text not null,
  terms_version text not null,
  status text not null,
  granted_at timestamptz not null default now(),
  expires_at timestamptz,
  revoked_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint guardian_consents_type_check
    check (consent_type in ('EQUESTRIAN_ACTIVITY')),
  constraint guardian_consents_scope_check
    check (scope_type in ('GENERAL')),
  constraint guardian_consents_status_check
    check (status in ('ACTIVE', 'REVOKED', 'EXPIRED')),
  constraint guardian_consents_terms_check
    check (char_length(btrim(terms_version)) > 0),
  constraint guardian_consents_lifecycle_check
    check (
      (
        status = 'ACTIVE'
        and revoked_at is null
      )
      or (
        status = 'REVOKED'
        and revoked_at is not null
      )
      or (
        status = 'EXPIRED'
        and revoked_at is null
        and expires_at is not null
      )
    )
);

comment on table public.guardian_consents is
  'Authoritative guardian consent evidence. Distinct from policy_acceptances. Booking, equine and center scopes are deferred until those domains exist with referential integrity.';
comment on column public.guardian_consents.scope_type is
  'GENERAL is the only scope implemented in 007. Contextual FKs are not added without target tables.';

create unique index guardian_consents_active_scope_uidx
  on public.guardian_consents (
    guardian_relationship_id,
    consent_type,
    scope_type
  )
  where status = 'ACTIVE';

create index guardian_consents_relationship_idx
  on public.guardian_consents (guardian_relationship_id);

create index guardian_consents_minor_idx
  on public.guardian_consents (minor_person_id, status);

create function public.guardian_consents_match_relationship()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
declare
  linked public.guardian_relationships%rowtype;
begin
  select *
    into linked
    from public.guardian_relationships as related
   where related.id = new.guardian_relationship_id;

  if linked.id is null then
    raise exception using
      errcode = '23503',
      message = 'Guardian relationship not found';
  end if;

  if new.guardian_person_id is distinct from linked.guardian_person_id
     or new.minor_person_id is distinct from linked.minor_person_id then
    raise exception using
      errcode = '23514',
      message = 'Consent persons must match the guardian relationship';
  end if;

  return new;
end;
$$;

create trigger guardian_consents_persons_match
before insert or update on public.guardian_consents
for each row execute function public.guardian_consents_match_relationship();

alter table public.guardian_consents enable row level security;
revoke all on table public.guardian_consents from anon, authenticated;
revoke all on function public.guardian_consents_match_relationship()
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------------

create function public.evaluate_person_minority(
  p_person_id uuid,
  p_market_code text,
  p_reference_date date
)
returns table (
  person_id uuid,
  reference_date date,
  market_code text,
  age_years integer,
  is_minor boolean,
  guardian_consent_required boolean
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  birth_date date;
  rule public.market_age_rules%rowtype;
  rule_count integer;
  computed_age integer;
begin
  if p_person_id is null or p_market_code is null or p_reference_date is null then
    raise exception using
      errcode = '22023',
      message = 'Person, market and reference date are required';
  end if;

  select person.date_of_birth
    into birth_date
    from public.persons as person
   where person.id = p_person_id;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'Person not found';
  end if;

  if birth_date is null then
    raise exception using
      errcode = 'P0001',
      message = 'Date of birth is required to evaluate minority';
  end if;

  if p_reference_date < birth_date then
    raise exception using
      errcode = '22023',
      message = 'Reference date cannot be before date of birth';
  end if;

  select count(*)
    into rule_count
    from public.market_age_rules as candidate
   where candidate.country_code = p_market_code
     and candidate.effective_from <= p_reference_date
     and (
       candidate.effective_to is null
       or candidate.effective_to > p_reference_date
     );

  if rule_count = 0 then
    raise exception using
      errcode = 'P0001',
      message = 'No effective market age rule';
  end if;

  if rule_count > 1 then
    raise exception using
      errcode = 'P0001',
      message = 'Ambiguous market age rules';
  end if;

  select *
    into rule
    from public.market_age_rules as candidate
   where candidate.country_code = p_market_code
     and candidate.effective_from <= p_reference_date
     and (
       candidate.effective_to is null
       or candidate.effective_to > p_reference_date
     );

  computed_age := extract(
    year from age(p_reference_date, birth_date)
  )::integer;

  person_id := p_person_id;
  reference_date := p_reference_date;
  market_code := p_market_code;
  age_years := computed_age;
  is_minor := computed_age < rule.legal_adult_age;
  guardian_consent_required := is_minor and rule.guardian_consent_required;
  return next;
end;
$$;

comment on function public.evaluate_person_minority(uuid, text, date) is
  'Computes age, minority and consent-requirement from date_of_birth and the market rule effective on the supplied date. Age is never stored. Not granted to clients.';

revoke all on function public.evaluate_person_minority(uuid, text, date)
  from public, anon, authenticated;

create function public.has_accepted_required_policy(
  p_policy_type text,
  p_market_code text
)
returns boolean
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  current_auth_user_id uuid := auth.uid();
  caller_person_id uuid;
  document_count integer;
  required_document_id uuid;
begin
  if current_auth_user_id is null then
    raise exception using
      errcode = '42501',
      message = 'Authentication required';
  end if;

  if p_policy_type is null or p_market_code is null then
    raise exception using
      errcode = '22023',
      message = 'Policy type and market are required';
  end if;

  select account.person_id
    into caller_person_id
    from public.user_accounts as account
   where account.auth_user_id = current_auth_user_id;

  if caller_person_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'Identity could not be resolved';
  end if;

  select count(*)
    into document_count
    from public.policy_documents as document
   where document.policy_type = p_policy_type
     and document.market_code = p_market_code
     and document.status = 'ACTIVE'
     and document.effective_from <= now()
     and (
       document.effective_to is null
       or document.effective_to > now()
     );

  if document_count = 0 then
    return true;
  end if;

  if document_count > 1 then
    raise exception using
      errcode = 'P0001',
      message = 'Ambiguous required policy documents';
  end if;

  select document.id
    into required_document_id
    from public.policy_documents as document
   where document.policy_type = p_policy_type
     and document.market_code = p_market_code
     and document.status = 'ACTIVE'
     and document.effective_from <= now()
     and (
       document.effective_to is null
       or document.effective_to > now()
     );

  return exists (
    select 1
      from public.policy_acceptances as acceptance
     where acceptance.policy_document_id = required_document_id
       and acceptance.person_id = caller_person_id
  );
end;
$$;

comment on function public.has_accepted_required_policy(text, text) is
  'True when no current document of that type exists for the market, or when the caller person has accepted the single current document. Fails closed if current documents are ambiguous.';

revoke all on function public.has_accepted_required_policy(text, text)
  from public, anon, authenticated;
grant execute on function public.has_accepted_required_policy(text, text)
  to authenticated;

-- ---------------------------------------------------------------------------
-- RPCs
-- ---------------------------------------------------------------------------

create function public.list_my_guardian_relationships()
returns table (
  id uuid,
  minor_person_id uuid,
  minor_first_name text,
  minor_last_name text,
  relationship_type text,
  verification_status text,
  verified_at timestamptz,
  expires_at timestamptz,
  revoked_at timestamptz
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  current_auth_user_id uuid := auth.uid();
  caller_person_id uuid;
begin
  if current_auth_user_id is null then
    raise exception using
      errcode = '42501',
      message = 'Authentication required';
  end if;

  select account.person_id
    into caller_person_id
    from public.user_accounts as account
   where account.auth_user_id = current_auth_user_id;

  if caller_person_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'Identity could not be resolved';
  end if;

  return query
  select
    relationship.id,
    relationship.minor_person_id,
    minor.first_name,
    minor.last_name,
    relationship.relationship_type,
    relationship.verification_status,
    relationship.verified_at,
    relationship.expires_at,
    relationship.revoked_at
  from public.guardian_relationships as relationship
  join public.persons as minor on minor.id = relationship.minor_person_id
  where relationship.guardian_person_id = caller_person_id;
end;
$$;

revoke all on function public.list_my_guardian_relationships()
  from public, anon, authenticated;
grant execute on function public.list_my_guardian_relationships()
  to authenticated;

create function public.list_my_guardian_consents()
returns table (
  id uuid,
  guardian_relationship_id uuid,
  minor_person_id uuid,
  consent_type text,
  scope_type text,
  terms_version text,
  status text,
  granted_at timestamptz,
  expires_at timestamptz,
  revoked_at timestamptz
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  current_auth_user_id uuid := auth.uid();
  caller_person_id uuid;
begin
  if current_auth_user_id is null then
    raise exception using
      errcode = '42501',
      message = 'Authentication required';
  end if;

  select account.person_id
    into caller_person_id
    from public.user_accounts as account
   where account.auth_user_id = current_auth_user_id;

  if caller_person_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'Identity could not be resolved';
  end if;

  return query
  select
    consent.id,
    consent.guardian_relationship_id,
    consent.minor_person_id,
    consent.consent_type,
    consent.scope_type,
    consent.terms_version,
    consent.status,
    consent.granted_at,
    consent.expires_at,
    consent.revoked_at
  from public.guardian_consents as consent
  where consent.guardian_person_id = caller_person_id;
end;
$$;

revoke all on function public.list_my_guardian_consents()
  from public, anon, authenticated;
grant execute on function public.list_my_guardian_consents()
  to authenticated;

create function public.grant_guardian_consent(
  p_guardian_relationship_id uuid,
  p_consent_type text,
  p_scope_type text,
  p_terms_version text,
  p_market_code text,
  p_expires_at timestamptz default null
)
returns table (
  id uuid,
  guardian_relationship_id uuid,
  minor_person_id uuid,
  consent_type text,
  scope_type text,
  terms_version text,
  status text,
  granted_at timestamptz,
  expires_at timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  current_auth_user_id uuid := auth.uid();
  caller_account public.user_accounts%rowtype;
  relationship public.guardian_relationships%rowtype;
  minority record;
  created public.guardian_consents%rowtype;
  normalized_terms text := nullif(btrim(p_terms_version), '');
begin
  if current_auth_user_id is null then
    raise exception using
      errcode = '42501',
      message = 'Authentication required';
  end if;

  select *
    into caller_account
    from public.user_accounts as account
   where account.auth_user_id = current_auth_user_id;

  if caller_account.id is null or caller_account.person_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'Identity could not be resolved';
  end if;

  if p_guardian_relationship_id is null
     or p_consent_type is null
     or p_scope_type is null
     or normalized_terms is null
     or p_market_code is null then
    raise exception using
      errcode = '22023',
      message = 'Relationship, consent type, scope, terms version and market are required';
  end if;

  select *
    into relationship
    from public.guardian_relationships as linked
   where linked.id = p_guardian_relationship_id;

  if relationship.id is null then
    raise exception using
      errcode = '42501',
      message = 'Guardian relationship not found';
  end if;

  if relationship.guardian_person_id is distinct from caller_account.person_id then
    raise exception using
      errcode = '42501',
      message = 'Caller is not the guardian for this relationship';
  end if;

  if relationship.verification_status is distinct from 'VERIFIED'
     or relationship.revoked_at is not null
     or (
       relationship.expires_at is not null
       and relationship.expires_at <= now()
     ) then
    raise exception using
      errcode = '42501',
      message = 'Guardian relationship is not verified and active';
  end if;

  select *
    into minority
    from public.evaluate_person_minority(
      relationship.minor_person_id,
      p_market_code,
      (timezone('utc', now()))::date
    );

  if not minority.guardian_consent_required then
    raise exception using
      errcode = '42501',
      message = 'Guardian consent is not required for this person';
  end if;

  if not public.has_accepted_required_policy('GUARDIAN_POLICY', p_market_code) then
    raise exception using
      errcode = '42501',
      message = 'Required guardian policy has not been accepted';
  end if;

  insert into public.guardian_consents (
    guardian_relationship_id,
    guardian_person_id,
    minor_person_id,
    granted_by_account_id,
    consent_type,
    scope_type,
    terms_version,
    status,
    granted_at,
    expires_at
  )
  values (
    relationship.id,
    relationship.guardian_person_id,
    relationship.minor_person_id,
    caller_account.id,
    p_consent_type,
    p_scope_type,
    normalized_terms,
    'ACTIVE',
    now(),
    p_expires_at
  )
  returning * into created;

  id := created.id;
  guardian_relationship_id := created.guardian_relationship_id;
  minor_person_id := created.minor_person_id;
  consent_type := created.consent_type;
  scope_type := created.scope_type;
  terms_version := created.terms_version;
  status := created.status;
  granted_at := created.granted_at;
  expires_at := created.expires_at;
  return next;
end;
$$;

comment on function public.grant_guardian_consent(uuid, text, text, text, text, timestamptz) is
  'Creates authoritative guardian consent for a verified relationship of the caller. Does not verify relationships or create policy acceptances.';

revoke all on function public.grant_guardian_consent(uuid, text, text, text, text, timestamptz)
  from public, anon, authenticated;
grant execute on function public.grant_guardian_consent(uuid, text, text, text, text, timestamptz)
  to authenticated;

create function public.revoke_guardian_consent(p_consent_id uuid)
returns table (
  id uuid,
  status text,
  revoked_at timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  current_auth_user_id uuid := auth.uid();
  caller_person_id uuid;
  consent public.guardian_consents%rowtype;
begin
  if current_auth_user_id is null then
    raise exception using
      errcode = '42501',
      message = 'Authentication required';
  end if;

  select account.person_id
    into caller_person_id
    from public.user_accounts as account
   where account.auth_user_id = current_auth_user_id;

  if caller_person_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'Identity could not be resolved';
  end if;

  if p_consent_id is null then
    raise exception using
      errcode = '22023',
      message = 'Consent id is required';
  end if;

  select *
    into consent
    from public.guardian_consents
   where public.guardian_consents.id = p_consent_id
   for update;

  if consent.id is null then
    raise exception using
      errcode = '42501',
      message = 'Guardian consent not found';
  end if;

  if consent.guardian_person_id is distinct from caller_person_id then
    raise exception using
      errcode = '42501',
      message = 'Caller is not the guardian for this consent';
  end if;

  if consent.status = 'REVOKED' then
    id := consent.id;
    status := consent.status;
    revoked_at := consent.revoked_at;
    return next;
    return;
  end if;

  update public.guardian_consents
     set status = 'REVOKED',
         revoked_at = now(),
         updated_at = now()
   where public.guardian_consents.id = consent.id
  returning
    public.guardian_consents.id,
    public.guardian_consents.status,
    public.guardian_consents.revoked_at
    into id, status, revoked_at;

  return next;
end;
$$;

comment on function public.revoke_guardian_consent(uuid) is
  'Revokes a consent belonging to the caller. Historical row is retained. Repeated revocation is idempotent.';

revoke all on function public.revoke_guardian_consent(uuid)
  from public, anon, authenticated;
grant execute on function public.revoke_guardian_consent(uuid)
  to authenticated;

create function public.check_guardian_consent(
  p_minor_person_id uuid,
  p_consent_type text,
  p_scope_type text,
  p_market_code text,
  p_reference_date date
)
returns table (
  minor_person_id uuid,
  consent_required boolean,
  consent_valid boolean,
  denial_reason text
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  current_auth_user_id uuid := auth.uid();
  caller_person_id uuid;
  minority record;
  active_consent public.guardian_consents%rowtype;
  related boolean := false;
begin
  if current_auth_user_id is null then
    raise exception using
      errcode = '42501',
      message = 'Authentication required';
  end if;

  select account.person_id
    into caller_person_id
    from public.user_accounts as account
   where account.auth_user_id = current_auth_user_id;

  if caller_person_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'Identity could not be resolved';
  end if;

  if p_minor_person_id is null
     or p_consent_type is null
     or p_scope_type is null
     or p_market_code is null
     or p_reference_date is null then
    raise exception using
      errcode = '22023',
      message = 'Minor, consent type, scope, market and reference date are required';
  end if;

  related := exists (
    select 1
      from public.guardian_relationships as relationship
     where relationship.guardian_person_id = caller_person_id
       and relationship.minor_person_id = p_minor_person_id
  );

  if not related then
    raise exception using
      errcode = '42501',
      message = 'Caller is not a guardian of this person';
  end if;

  select *
    into minority
    from public.evaluate_person_minority(
      p_minor_person_id,
      p_market_code,
      p_reference_date
    );

  minor_person_id := p_minor_person_id;
  consent_required := minority.guardian_consent_required;

  if not minority.guardian_consent_required then
    consent_valid := true;
    denial_reason := null;
    return next;
    return;
  end if;

  select consent.*
    into active_consent
    from public.guardian_consents as consent
    join public.guardian_relationships as relationship
      on relationship.id = consent.guardian_relationship_id
   where consent.minor_person_id = p_minor_person_id
     and consent.guardian_person_id = caller_person_id
     and consent.consent_type = p_consent_type
     and consent.scope_type = p_scope_type
     and consent.status = 'ACTIVE'
     and consent.revoked_at is null
     and (
       consent.expires_at is null
       or consent.expires_at > timezone('utc', p_reference_date::timestamp)
     )
     and relationship.verification_status = 'VERIFIED'
     and relationship.revoked_at is null
     and (
       relationship.expires_at is null
       or relationship.expires_at > timezone('utc', p_reference_date::timestamp)
     )
   order by consent.granted_at desc
   limit 1;

  if active_consent.id is null then
    consent_valid := false;
    denial_reason := 'MISSING_OR_INVALID_CONSENT';
  else
    consent_valid := true;
    denial_reason := null;
  end if;

  return next;
end;
$$;

comment on function public.check_guardian_consent(uuid, text, text, text, date) is
  'Reusable consent validity check for a minor of the caller. Fails closed when evaluation data are missing or ambiguous. Does not confirm bookings.';

revoke all on function public.check_guardian_consent(uuid, text, text, text, date)
  from public, anon, authenticated;
grant execute on function public.check_guardian_consent(uuid, text, text, text, date)
  to authenticated;
