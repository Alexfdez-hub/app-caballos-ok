-- Stage 1. Spain review cohorts.
--
-- A MARKET / ES grant authorizes only dossiers in its closed cohort.
-- Capabilities, queue, detail, and accept/reject all use that boundary.
-- Cohort composition is postgres-only, validated, append-only, and audited.
-- This migration does not grant a reviewer, create a pilot dossier, or
-- deploy. It does not edit migrations 036-040.

create table public.verification_review_cohorts (
  code text primary key,
  market_country_code text not null default 'ES' references public.markets (country_code),
  composition_status text not null,
  created_at timestamptz not null default pg_catalog.clock_timestamp(),
  closed_at timestamptz,
  constraint verification_review_cohorts_market_check
    check (market_country_code = 'ES'),
  constraint verification_review_cohorts_status_check
    check (composition_status in ('OPEN', 'CLOSED')),
  constraint verification_review_cohorts_closed_check
    check (
      (
        composition_status = 'OPEN'
        and closed_at is null
      )
      or (
        composition_status = 'CLOSED'
        and closed_at is not null
      )
    )
);

comment on table public.verification_review_cohorts is
  'Explicit Spain review allow-list. OPEN accepts validated dossiers. CLOSED is frozen for composition. Not a grant and not a client table.';

create table public.verification_review_cohort_cases (
  cohort_code text not null references public.verification_review_cohorts (code),
  case_type text not null,
  case_id uuid not null,
  created_at timestamptz not null default pg_catalog.clock_timestamp(),
  primary key (case_type, case_id),
  constraint verification_review_cohort_cases_type_check
    check (case_type in ('IDENTITY', 'OWNERSHIP', 'MANAGEMENT'))
);

comment on table public.verification_review_cohort_cases is
  'One dossier belongs to one cohort. case_id is validated against the table named by case_type. Rows are not updated or deleted.';

create index verification_review_cohort_cases_cohort_idx
  on public.verification_review_cohort_cases (cohort_code);

create table public.verification_review_cohort_events (
  id uuid primary key default gen_random_uuid(),
  cohort_code text not null,
  event_type text not null,
  case_type text,
  case_id uuid,
  "session_user" text not null,
  occurred_at timestamptz not null default pg_catalog.clock_timestamp(),
  constraint verification_review_cohort_events_type_check
    check (event_type in ('CREATED', 'CASE_ADDED', 'COMPOSITION_CLOSED')),
  constraint verification_review_cohort_events_case_check
    check (
      (
        event_type = 'CASE_ADDED'
        and case_type in ('IDENTITY', 'OWNERSHIP', 'MANAGEMENT')
        and case_id is not null
      )
      or (
        event_type in ('CREATED', 'COMPOSITION_CLOSED')
        and case_type is null
        and case_id is null
      )
    )
);

comment on table public.verification_review_cohort_events is
  'Append-only cohort history. session_user is the PostgreSQL session user. Events are not updated or deleted when a grant is suspended or closed.';

create index verification_review_cohort_events_cohort_idx
  on public.verification_review_cohort_events (cohort_code, occurred_at);

create function public.enforce_verification_cohort_event_immutability()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  raise exception using
    errcode = '42501',
    message = 'Verification cohort history is append-only';
end;
$$;

comment on function public.enforce_verification_cohort_event_immutability() is
  'SECURITY INVOKER. Refuses update and delete of cohort events. Not a client API.';

revoke all on function public.enforce_verification_cohort_event_immutability()
  from public, anon, authenticated, service_role, supabase_admin;

create trigger verification_review_cohort_events_immutable
  before update or delete on public.verification_review_cohort_events
  for each row execute function public.enforce_verification_cohort_event_immutability();

create function public.enforce_verification_cohort_composition()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
declare
  cohort public.verification_review_cohorts%rowtype;
begin
  if tg_table_name = 'verification_review_cohorts' then
    if tg_op = 'DELETE' then
      raise exception using
        errcode = '42501',
        message = 'Verification cohort operation is not available';
    end if;

    if tg_op = 'UPDATE'
       and (
         new.code is distinct from old.code
         or new.market_country_code is distinct from old.market_country_code
         or new.created_at is distinct from old.created_at
         or old.composition_status is distinct from 'OPEN'
         or new.composition_status is distinct from 'CLOSED'
       ) then
      raise exception using
        errcode = '42501',
        message = 'Verification cohort operation is not available';
    end if;

    return new;
  end if;

  if tg_op <> 'INSERT' then
    raise exception using
      errcode = '42501',
      message = 'Verification cohort membership is append-only';
  end if;

  select cohort_row.*
    into cohort
    from public.verification_review_cohorts as cohort_row
   where cohort_row.code = new.cohort_code
   for update;

  if not found or cohort.composition_status is distinct from 'OPEN' then
    raise exception using
      errcode = '42501',
      message = 'Verification cohort operation is not available';
  end if;

  if exists (
    select 1
      from public.verification_review_grants as grant_row
     where grant_row.cohort_code = new.cohort_code
       and grant_row.status in ('ACTIVE', 'SUSPENDED')
  ) then
    raise exception using
      errcode = '42501',
      message = 'Verification cohort operation is not available';
  end if;

  return new;
end;
$$;

comment on function public.enforce_verification_cohort_composition() is
  'SECURITY INVOKER. A closed cohort stays closed. Membership cannot change while a linked grant is ACTIVE or SUSPENDED, and membership rows are not updated or deleted.';

revoke all on function public.enforce_verification_cohort_composition()
  from public, anon, authenticated, service_role, supabase_admin;

create trigger verification_review_cohorts_composition
  before update or delete on public.verification_review_cohorts
  for each row execute function public.enforce_verification_cohort_composition();

create trigger verification_review_cohort_cases_composition
  before insert or update or delete on public.verification_review_cohort_cases
  for each row execute function public.enforce_verification_cohort_composition();

create function public.create_verification_review_cohort(p_code text)
returns text
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
declare
  normalized_code text := upper(btrim(coalesce(p_code, '')));
  actor_name text := session_user;
begin
  perform public.verification_grant_technical_principal();

  if normalized_code !~ '^[A-Z0-9][A-Z0-9-]{0,63}$' then
    raise exception using
      errcode = '42501',
      message = 'Verification cohort operation is not available';
  end if;

  insert into public.verification_review_cohorts (
    code,
    market_country_code,
    composition_status
  ) values (
    normalized_code,
    'ES',
    'OPEN'
  );

  insert into public.verification_review_cohort_events (
    cohort_code,
    event_type,
    "session_user"
  ) values (
    normalized_code,
    'CREATED',
    actor_name
  );

  return normalized_code;
exception
  when unique_violation then
    raise exception using
      errcode = '42501',
      message = 'Verification cohort operation is not available';
end;
$$;

comment on function public.create_verification_review_cohort(text) is
  'Creates an OPEN MARKET / ES cohort. Postgres only. Does not grant review.';

revoke all on function public.create_verification_review_cohort(text)
  from public, anon, authenticated, service_role, supabase_admin;

create function public.add_verification_review_cohort_case(
  p_code text,
  p_case_type text,
  p_case_id uuid
)
returns void
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
declare
  normalized_code text := upper(btrim(coalesce(p_code, '')));
  normalized_type text := upper(btrim(coalesce(p_case_type, '')));
  cohort public.verification_review_cohorts%rowtype;
  actor_name text := session_user;
begin
  perform public.verification_grant_technical_principal();

  if p_case_id is null
     or normalized_type not in ('IDENTITY', 'OWNERSHIP', 'MANAGEMENT') then
    raise exception using
      errcode = '42501',
      message = 'Verification cohort operation is not available';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    384,
    pg_catalog.hashtext(normalized_type || ':' || p_case_id::text)
  );

  select cohort_row.*
    into cohort
    from public.verification_review_cohorts as cohort_row
   where cohort_row.code = normalized_code
   for update;

  if not found or cohort.composition_status is distinct from 'OPEN' then
    raise exception using
      errcode = '42501',
      message = 'Verification cohort operation is not available';
  end if;

  if normalized_type = 'IDENTITY'
     and not exists (
       select 1
         from public.identity_verification_cases as identity_case
        where identity_case.id = p_case_id
          and identity_case.market_country_code = 'ES'
          and identity_case.state in ('SUBMITTED', 'IN_REVIEW', 'RESUBMITTED')
     ) then
    raise exception using
      errcode = '42501',
      message = 'Verification cohort operation is not available';
  elsif normalized_type = 'OWNERSHIP'
     and not exists (
       select 1
         from public.equine_ownership_claims as claim
        where claim.id = p_case_id
          and claim.market_country_code = 'ES'
          and claim.state in ('SUBMITTED', 'IN_REVIEW', 'RESUBMITTED')
     ) then
    raise exception using
      errcode = '42501',
      message = 'Verification cohort operation is not available';
  elsif normalized_type = 'MANAGEMENT'
     and not exists (
       select 1
         from public.equine_management_authority_claims as claim
        where claim.id = p_case_id
          and claim.market_country_code = 'ES'
          and claim.state in ('SUBMITTED', 'IN_REVIEW', 'RESUBMITTED')
     ) then
    raise exception using
      errcode = '42501',
      message = 'Verification cohort operation is not available';
  end if;

  if exists (
    select 1
      from public.verification_review_cohort_cases as membership
     where membership.case_type = normalized_type
       and membership.case_id = p_case_id
  ) then
    raise exception using
      errcode = '42501',
      message = 'Verification cohort operation is not available';
  end if;

  insert into public.verification_review_cohort_cases (
    cohort_code,
    case_type,
    case_id
  ) values (
    normalized_code,
    normalized_type,
    p_case_id
  );

  insert into public.verification_review_cohort_events (
    cohort_code,
    event_type,
    case_type,
    case_id,
    "session_user"
  ) values (
    normalized_code,
    'CASE_ADDED',
    normalized_type,
    p_case_id,
    actor_name
  );
exception
  when unique_violation then
    raise exception using
      errcode = '42501',
      message = 'Verification cohort operation is not available';
end;
$$;

comment on function public.add_verification_review_cohort_case(text, text, uuid) is
  'Adds one existing open Spain dossier. The type must match the row. A second cohort for the same dossier is refused. Postgres only.';

revoke all on function public.add_verification_review_cohort_case(text, text, uuid)
  from public, anon, authenticated, service_role, supabase_admin;

create function public.close_verification_review_cohort_composition(p_code text)
returns void
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
declare
  normalized_code text := upper(btrim(coalesce(p_code, '')));
  cohort public.verification_review_cohorts%rowtype;
  actor_name text := session_user;
begin
  perform public.verification_grant_technical_principal();

  select cohort_row.*
    into cohort
    from public.verification_review_cohorts as cohort_row
   where cohort_row.code = normalized_code
   for update;

  if not found or cohort.composition_status is distinct from 'OPEN' then
    raise exception using
      errcode = '42501',
      message = 'Verification cohort operation is not available';
  end if;

  update public.verification_review_cohorts as cohort_row
     set composition_status = 'CLOSED',
         closed_at = pg_catalog.clock_timestamp()
   where cohort_row.code = normalized_code
     and cohort_row.composition_status = 'OPEN';

  if not found then
    raise exception using
      errcode = '42501',
      message = 'Verification cohort operation is not available';
  end if;

  insert into public.verification_review_cohort_events (
    cohort_code,
    event_type,
    "session_user"
  ) values (
    normalized_code,
    'COMPOSITION_CLOSED',
    actor_name
  );
end;
$$;

comment on function public.close_verification_review_cohort_composition(text) is
  'Closes composition. A closed cohort does not reopen and does not accept new dossiers. Postgres only.';

revoke all on function public.close_verification_review_cohort_composition(text)
  from public, anon, authenticated, service_role, supabase_admin;

alter table public.verification_review_grants
  add column cohort_code text references public.verification_review_cohorts (code);

comment on column public.verification_review_grants.cohort_code is
  'Closed Spain cohort this grant may review. Null and legacy grants authorize nothing.';

create index verification_review_grants_cohort_idx
  on public.verification_review_grants (cohort_code);

create function public.enforce_verification_grant_cohort_link()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  if tg_op = 'UPDATE' and new.cohort_code is distinct from old.cohort_code then
    raise exception using
      errcode = '42501',
      message = 'Verification grant operation is not available';
  end if;

  if tg_op = 'INSERT'
     and new.cohort_code is not null
     and not exists (
       select 1
         from public.verification_review_cohorts as cohort
        where cohort.code = new.cohort_code
          and cohort.market_country_code = 'ES'
          and cohort.composition_status = 'CLOSED'
     ) then
    raise exception using
      errcode = '42501',
      message = 'Verification grant operation is not available';
  end if;

  return new;
end;
$$;

comment on function public.enforce_verification_grant_cohort_link() is
  'SECURITY INVOKER. cohort_code is immutable. A non-null link must already name a closed Spain cohort.';

revoke all on function public.enforce_verification_grant_cohort_link()
  from public, anon, authenticated, service_role, supabase_admin;

create trigger verification_review_grants_cohort_link
  before insert or update on public.verification_review_grants
  for each row execute function public.enforce_verification_grant_cohort_link();

drop function public.bootstrap_verification_review_grant(uuid);

create function public.bootstrap_verification_review_grant(
  p_reviewer_person_id uuid,
  p_cohort_code text
)
returns uuid
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
declare
  created_grant_id uuid;
  technical_principal text;
  normalized_code text := upper(btrim(coalesce(p_cohort_code, '')));
begin
  technical_principal := public.verification_grant_technical_principal();

  if p_reviewer_person_id is null
     or not exists (
       select 1
         from public.persons as person
        where person.id = p_reviewer_person_id
          and person.status = 'ACTIVE'
     )
     or not exists (
       select 1
         from public.user_accounts as account
        where account.person_id = p_reviewer_person_id
          and account.status = 'ACTIVE'
     )
     or not exists (
       select 1
         from public.verification_review_cohorts as cohort
        where cohort.code = normalized_code
          and cohort.market_country_code = 'ES'
          and cohort.composition_status = 'CLOSED'
     ) then
    raise exception using
      errcode = '42501',
      message = 'Verification grant operation is not available';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    391,
    pg_catalog.hashtext(p_reviewer_person_id::text || ':MARKET:ES')
  );

  if exists (
    select 1
      from public.verification_review_grants as grant_row
     where grant_row.reviewer_person_id = p_reviewer_person_id
       and grant_row.scope_type = 'MARKET'
       and grant_row.market_country_code = 'ES'
       and grant_row.status in ('ACTIVE', 'SUSPENDED')
  ) then
    raise exception using
      errcode = '42501',
      message = 'Verification grant operation is not available';
  end if;

  insert into public.verification_review_grants (
    reviewer_person_id,
    scope_type,
    market_country_code,
    status,
    cohort_code
  ) values (
    p_reviewer_person_id,
    'MARKET',
    'ES',
    'ACTIVE',
    normalized_code
  )
  returning id into created_grant_id;

  insert into public.verification_review_grant_events (
    grant_id,
    event_type,
    reviewer_person_id,
    scope_type,
    market_country_code,
    previous_status,
    new_status,
    actor_kind,
    technical_principal,
    reason_code
  ) values (
    created_grant_id,
    'GRANTED',
    p_reviewer_person_id,
    'MARKET',
    'ES',
    null,
    'ACTIVE',
    'TECHNICAL',
    technical_principal,
    'PILOT_BOOTSTRAP'
  );

  return created_grant_id;
exception
  when unique_violation then
    raise exception using
      errcode = '42501',
      message = 'Verification grant operation is not available';
end;
$$;

comment on function public.bootstrap_verification_review_grant(uuid, text) is
  'Creates one MARKET / ES grant linked to a cohort whose composition is already CLOSED. The link is written in this insert. A null cohort is not created and filled in later. Not an Expo or service_role API.';

revoke all on function public.bootstrap_verification_review_grant(uuid, text)
  from public, anon, authenticated, service_role, supabase_admin;

create or replace function public.verification_lock_spain_review_grant(p_person_id uuid)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  locked_grant_id uuid;
begin
  select grant_row.id
    into locked_grant_id
    from public.verification_review_grants as grant_row
    join public.verification_review_cohorts as cohort
      on cohort.code = grant_row.cohort_code
   where grant_row.reviewer_person_id = p_person_id
     and grant_row.status = 'ACTIVE'
     and grant_row.valid_from <= pg_catalog.now()
     and grant_row.scope_type = 'MARKET'
     and grant_row.market_country_code = 'ES'
     and grant_row.cohort_code is not null
     and cohort.market_country_code = 'ES'
     and cohort.composition_status = 'CLOSED'
   order by grant_row.id
   limit 1;

  if locked_grant_id is null then
    return null;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    392,
    pg_catalog.hashtext(locked_grant_id::text)
  );

  select grant_row.id
    into locked_grant_id
    from public.verification_review_grants as grant_row
    join public.verification_review_cohorts as cohort
      on cohort.code = grant_row.cohort_code
   where grant_row.id = locked_grant_id
     and grant_row.reviewer_person_id = p_person_id
     and grant_row.status = 'ACTIVE'
     and grant_row.valid_from <= pg_catalog.now()
     and grant_row.scope_type = 'MARKET'
     and grant_row.market_country_code = 'ES'
     and grant_row.cohort_code is not null
     and cohort.composition_status = 'CLOSED'
   for update;

  return locked_grant_id;
end;
$$;

comment on function public.verification_lock_spain_review_grant(uuid) is
  'Locks the current MARKET / ES grant only when it links a closed Spain cohort. A null, legacy, suspended, or closed grant returns null. Not a client API.';

revoke all on function public.verification_lock_spain_review_grant(uuid)
  from public, anon, authenticated, service_role;

create function public.verification_cohort_authorizes(
  p_person_id uuid,
  p_case_type text,
  p_case_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  grant_id uuid;
begin
  if p_person_id is null or p_case_id is null or p_case_type is null then
    return false;
  end if;

  grant_id := public.verification_lock_spain_review_grant(p_person_id);

  if grant_id is null then
    return false;
  end if;

  return exists (
    select 1
      from public.verification_review_grants as grant_row
      join public.verification_review_cohort_cases as membership
        on membership.cohort_code = grant_row.cohort_code
     where grant_row.id = grant_id
       and membership.case_type = p_case_type
       and membership.case_id = p_case_id
  );
end;
$$;

comment on function public.verification_cohort_authorizes(uuid, text, uuid) is
  'True only when the caller has an active cohort-linked Spain grant and the dossier is in that cohort. Unknown ids are false. Not a client API.';

revoke all on function public.verification_cohort_authorizes(uuid, text, uuid)
  from public, anon, authenticated, service_role;

create function public.enforce_verification_decision_cohort()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller_person uuid;
  decided_type text;
begin
  if tg_op <> 'UPDATE' or new.state is not distinct from old.state then
    return new;
  end if;

  if new.state not in ('ACCEPTED', 'REJECTED') then
    return new;
  end if;

  select resolved.person_id
    into caller_person
    from public.verification_resolve_caller() as resolved;

  decided_type := case tg_table_name
    when 'identity_verification_cases' then 'IDENTITY'
    when 'equine_ownership_claims' then 'OWNERSHIP'
    when 'equine_management_authority_claims' then 'MANAGEMENT'
    else null
  end;

  if decided_type is null
     or not public.verification_cohort_authorizes(caller_person, decided_type, new.id) then
    raise exception using
      errcode = '42501',
      message = 'Verification request is not available';
  end if;

  return new;
end;
$$;

comment on function public.enforce_verification_decision_cohort() is
  'Accept and reject write the new state only when the signed-in reviewer is authorized for that exact dossier. A known UUID outside the cohort fails closed.';

revoke all on function public.enforce_verification_decision_cohort()
  from public, anon, authenticated, service_role, supabase_admin;

create trigger identity_verification_cases_decision_cohort
  before update on public.identity_verification_cases
  for each row execute function public.enforce_verification_decision_cohort();

create trigger equine_ownership_claims_decision_cohort
  before update on public.equine_ownership_claims
  for each row execute function public.enforce_verification_decision_cohort();

create trigger equine_management_claims_decision_cohort
  before update on public.equine_management_authority_claims
  for each row execute function public.enforce_verification_decision_cohort();

create unique index identity_verification_cases_one_open_idx
  on public.identity_verification_cases (subject_person_id, market_country_code)
  where state in ('SUBMITTED', 'IN_REVIEW', 'RESUBMITTED');

create unique index equine_ownership_claims_one_open_idx
  on public.equine_ownership_claims (submitted_by_account_id, equine_id, market_country_code)
  where state in ('SUBMITTED', 'IN_REVIEW', 'RESUBMITTED');

create unique index equine_management_claims_one_open_idx
  on public.equine_management_authority_claims (submitted_by_account_id, equine_id, market_country_code)
  where state in ('SUBMITTED', 'IN_REVIEW', 'RESUBMITTED');

create or replace function public.submit_my_identity_case(
  p_market_country_code text
)
returns table (
  case_id uuid,
  state text,
  market_country_code text
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller_account uuid;
  caller_person uuid;
  normalized_market text := upper(btrim(coalesce(p_market_country_code, '')));
begin
  select resolved.account_id, resolved.person_id
    into caller_account, caller_person
    from public.verification_resolve_caller() as resolved;

  if not public.identity_market_is_selectable(normalized_market) then
    raise exception using
      errcode = '42501',
      message = 'Verification request is not available';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    381,
    pg_catalog.hashtext(caller_person::text || ':' || normalized_market)
  );

  if exists (
    select 1
      from public.identity_verification_cases as identity_case
     where identity_case.subject_person_id = caller_person
       and identity_case.market_country_code = normalized_market
       and identity_case.state in ('SUBMITTED', 'IN_REVIEW', 'RESUBMITTED')
  ) then
    raise exception using
      errcode = '42501',
      message = 'Verification request is not available';
  end if;

  begin
    return query
    insert into public.identity_verification_cases (
      subject_person_id,
      market_country_code,
      state,
      submitted_by_account_id
    ) values (
      caller_person,
      normalized_market,
      'SUBMITTED',
      caller_account
    )
    returning
      identity_verification_cases.id,
      identity_verification_cases.state,
      identity_verification_cases.market_country_code;
  exception
    when unique_violation then
      raise exception using
        errcode = '42501',
        message = 'Verification request is not available';
  end;
end;
$$;

comment on function public.submit_my_identity_case(text) is
  'Submits one open identity case for the caller PERSON and market. A concurrent duplicate leaves a single open case.';

create or replace function public.submit_my_equine_ownership_claim(
  p_equine_id uuid,
  p_market_country_code text,
  p_owner_type text,
  p_owner_center_id uuid,
  p_ownership_percentage numeric,
  p_effective_ownership_id uuid
)
returns table (
  claim_id uuid,
  state text,
  market_country_code text
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller_account uuid;
  caller_person uuid;
  normalized_market text := upper(btrim(coalesce(p_market_country_code, '')));
  owner_person uuid;
begin
  select resolved.account_id, resolved.person_id
    into caller_account, caller_person
    from public.verification_resolve_caller() as resolved;

  if not public.identity_market_is_selectable(normalized_market)
     or p_owner_type not in ('PERSON', 'CENTER') then
    raise exception using
      errcode = '42501',
      message = 'Verification request is not available';
  end if;

  if p_owner_type = 'PERSON' then
    if p_owner_center_id is not null then
      raise exception using
        errcode = '42501',
        message = 'Verification request is not available';
    end if;
    owner_person := caller_person;
  else
    if p_owner_center_id is null
       or not public.verification_person_acts_for_center(
         caller_person,
         p_owner_center_id
       ) then
      raise exception using
        errcode = '42501',
        message = 'Verification request is not available';
    end if;
    owner_person := null;
  end if;

  if p_effective_ownership_id is not null and not exists (
    select 1
      from public.equine_ownerships as ownership
     where ownership.id = p_effective_ownership_id
       and ownership.equine_id = p_equine_id
       and ownership.status = 'ACTIVE'
       and ownership.ended_at is null
       and ownership.started_at <= pg_catalog.now()
       and (
         (
           p_owner_type = 'PERSON'
           and ownership.owner_person_id = owner_person
         )
         or (
           p_owner_type = 'CENTER'
           and ownership.owner_center_id = p_owner_center_id
         )
       )
  ) then
    raise exception using
      errcode = '42501',
      message = 'Verification request is not available';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    382,
    pg_catalog.hashtext(
      caller_account::text || ':' || p_equine_id::text || ':' || normalized_market
    )
  );

  if exists (
    select 1
      from public.equine_ownership_claims as claim
     where claim.submitted_by_account_id = caller_account
       and claim.equine_id = p_equine_id
       and claim.market_country_code = normalized_market
       and claim.state in ('SUBMITTED', 'IN_REVIEW', 'RESUBMITTED')
  ) then
    raise exception using
      errcode = '42501',
      message = 'Verification request is not available';
  end if;

  begin
    return query
    insert into public.equine_ownership_claims (
      equine_id,
      market_country_code,
      state,
      owner_type,
      owner_person_id,
      owner_center_id,
      ownership_percentage,
      effective_ownership_id,
      submitted_by_account_id
    ) values (
      p_equine_id,
      normalized_market,
      'SUBMITTED',
      p_owner_type,
      owner_person,
      case when p_owner_type = 'CENTER' then p_owner_center_id else null end,
      p_ownership_percentage,
      p_effective_ownership_id,
      caller_account
    )
    returning
      equine_ownership_claims.id,
      equine_ownership_claims.state,
      equine_ownership_claims.market_country_code;
  exception
    when check_violation or foreign_key_violation or not_null_violation or unique_violation then
      raise exception using
        errcode = '42501',
        message = 'Verification request is not available';
  end;
end;
$$;

comment on function public.submit_my_equine_ownership_claim(uuid, text, text, uuid, numeric, uuid) is
  'Submits one open ownership claim. An effective row must be that caller, that equine, and current. Does not write equine_ownerships.';

create or replace function public.submit_my_equine_management_claim(
  p_equine_id uuid,
  p_market_country_code text,
  p_manager_type text,
  p_manager_center_id uuid,
  p_management_role text,
  p_valid_from timestamptz,
  p_valid_until timestamptz,
  p_effective_assignment_id uuid
)
returns table (
  claim_id uuid,
  state text,
  market_country_code text
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller_account uuid;
  caller_person uuid;
  normalized_market text := upper(btrim(coalesce(p_market_country_code, '')));
  manager_person uuid;
begin
  select resolved.account_id, resolved.person_id
    into caller_account, caller_person
    from public.verification_resolve_caller() as resolved;

  if not public.identity_market_is_selectable(normalized_market)
     or p_manager_type not in ('PERSON', 'CENTER') then
    raise exception using
      errcode = '42501',
      message = 'Verification request is not available';
  end if;

  if p_manager_type = 'PERSON' then
    if p_manager_center_id is not null then
      raise exception using
        errcode = '42501',
        message = 'Verification request is not available';
    end if;
    manager_person := caller_person;
  else
    if p_manager_center_id is null
       or not public.verification_person_acts_for_center(
         caller_person,
         p_manager_center_id
       ) then
      raise exception using
        errcode = '42501',
        message = 'Verification request is not available';
    end if;
    manager_person := null;
  end if;

  if p_effective_assignment_id is not null and not exists (
    select 1
      from public.equine_management_assignments as assignment
     where assignment.id = p_effective_assignment_id
       and assignment.equine_id = p_equine_id
       and assignment.status = 'ACTIVE'
       and assignment.valid_from <= pg_catalog.now()
       and (
         assignment.valid_until is null
         or assignment.valid_until >= pg_catalog.now()
       )
       and assignment.valid_from is not distinct from p_valid_from
       and assignment.valid_until is not distinct from p_valid_until
       and (
         (
           p_manager_type = 'PERSON'
           and assignment.manager_person_id = manager_person
         )
         or (
           p_manager_type = 'CENTER'
           and assignment.manager_center_id = p_manager_center_id
         )
       )
  ) then
    raise exception using
      errcode = '42501',
      message = 'Verification request is not available';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    383,
    pg_catalog.hashtext(
      caller_account::text || ':' || p_equine_id::text || ':' || normalized_market
    )
  );

  if exists (
    select 1
      from public.equine_management_authority_claims as claim
     where claim.submitted_by_account_id = caller_account
       and claim.equine_id = p_equine_id
       and claim.market_country_code = normalized_market
       and claim.state in ('SUBMITTED', 'IN_REVIEW', 'RESUBMITTED')
  ) then
    raise exception using
      errcode = '42501',
      message = 'Verification request is not available';
  end if;

  begin
    return query
    insert into public.equine_management_authority_claims (
      equine_id,
      market_country_code,
      state,
      manager_type,
      manager_person_id,
      manager_center_id,
      management_role,
      valid_from,
      valid_until,
      effective_assignment_id,
      submitted_by_account_id
    ) values (
      p_equine_id,
      normalized_market,
      'SUBMITTED',
      p_manager_type,
      manager_person,
      case when p_manager_type = 'CENTER' then p_manager_center_id else null end,
      p_management_role,
      p_valid_from,
      p_valid_until,
      p_effective_assignment_id,
      caller_account
    )
    returning
      equine_management_authority_claims.id,
      equine_management_authority_claims.state,
      equine_management_authority_claims.market_country_code;
  exception
    when check_violation or foreign_key_violation or not_null_violation or unique_violation then
      raise exception using
        errcode = '42501',
        message = 'Verification request is not available';
  end;
end;
$$;

comment on function public.submit_my_equine_management_claim(uuid, text, text, uuid, text, timestamptz, timestamptz, uuid) is
  'Submits one open management claim. An effective assignment must be current and the claim window must equal that row. Does not write equine_management_assignments.';

alter table public.verification_review_cohorts enable row level security;
alter table public.verification_review_cohort_cases enable row level security;
alter table public.verification_review_cohort_events enable row level security;

revoke all on table public.verification_review_cohorts
  from public, anon, authenticated, service_role;
revoke all on table public.verification_review_cohort_cases
  from public, anon, authenticated, service_role;
revoke all on table public.verification_review_cohort_events
  from public, anon, authenticated, service_role;

create or replace function public.list_my_review_queue()
returns table (
  case_id uuid,
  case_type text,
  market_country_code text,
  state text,
  updated_at timestamptz,
  evidence_categories text[]
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller_account uuid;
  caller_person uuid;
  grant_id uuid;
begin
  select resolved.account_id, resolved.person_id
    into caller_account, caller_person
    from public.verification_resolve_caller() as resolved;

  grant_id := public.verification_lock_spain_review_grant(caller_person);

  if grant_id is null then
    raise exception using
      errcode = '42501',
      message = 'Verification request is not available';
  end if;

  return query
  select
    queued.case_id,
    queued.case_type,
    queued.market_country_code,
    queued.state,
    queued.updated_at,
    queued.evidence_categories
    from (
      select
        identity_case.id as case_id,
        'IDENTITY'::text as case_type,
        identity_case.market_country_code,
        identity_case.state,
        identity_case.updated_at,
        coalesce(
          (
            select array_agg(distinct evidence.category order by evidence.category)
              from public.verification_evidence as evidence
             where evidence.identity_case_id = identity_case.id
          ),
          '{}'::text[]
        ) as evidence_categories
        from public.identity_verification_cases as identity_case
       where exists (
        select 1
          from public.verification_review_grants as cohort_grant
          join public.verification_review_cohort_cases as membership
            on membership.cohort_code = cohort_grant.cohort_code
         where cohort_grant.id = grant_id
           and membership.case_type = 'IDENTITY'
           and membership.case_id = identity_case.id
      )
         and identity_case.market_country_code = 'ES'
         and identity_case.state in ('SUBMITTED', 'IN_REVIEW', 'RESUBMITTED')
         and identity_case.subject_person_id is distinct from caller_person
         and identity_case.submitted_by_account_id is distinct from caller_account
      union all
      select
        ownership_claim.id,
        'OWNERSHIP'::text,
        ownership_claim.market_country_code,
        ownership_claim.state,
        ownership_claim.updated_at,
        coalesce(
          (
            select array_agg(distinct evidence.category order by evidence.category)
              from public.verification_evidence as evidence
             where evidence.ownership_claim_id = ownership_claim.id
          ),
          '{}'::text[]
        )
        from public.equine_ownership_claims as ownership_claim
       where exists (
        select 1
          from public.verification_review_grants as cohort_grant
          join public.verification_review_cohort_cases as membership
            on membership.cohort_code = cohort_grant.cohort_code
         where cohort_grant.id = grant_id
           and membership.case_type = 'OWNERSHIP'
           and membership.case_id = ownership_claim.id
      )
         and ownership_claim.market_country_code = 'ES'
         and ownership_claim.state in ('SUBMITTED', 'IN_REVIEW', 'RESUBMITTED')
         and ownership_claim.owner_person_id is distinct from caller_person
         and ownership_claim.submitted_by_account_id is distinct from caller_account
         and not public.verification_person_acts_for_center(
           caller_person,
           ownership_claim.owner_center_id
         )
      union all
      select
        management_claim.id,
        'MANAGEMENT'::text,
        management_claim.market_country_code,
        management_claim.state,
        management_claim.updated_at,
        coalesce(
          (
            select array_agg(distinct evidence.category order by evidence.category)
              from public.verification_evidence as evidence
             where evidence.management_claim_id = management_claim.id
          ),
          '{}'::text[]
        )
        from public.equine_management_authority_claims as management_claim
       where exists (
        select 1
          from public.verification_review_grants as cohort_grant
          join public.verification_review_cohort_cases as membership
            on membership.cohort_code = cohort_grant.cohort_code
         where cohort_grant.id = grant_id
           and membership.case_type = 'MANAGEMENT'
           and membership.case_id = management_claim.id
      )
         and management_claim.market_country_code = 'ES'
         and management_claim.state in ('SUBMITTED', 'IN_REVIEW', 'RESUBMITTED')
         and management_claim.manager_person_id is distinct from caller_person
         and management_claim.submitted_by_account_id is distinct from caller_account
         and not public.verification_person_acts_for_center(
           caller_person,
           management_claim.manager_center_id
         )
    ) as queued
   order by queued.updated_at desc, queued.case_type asc, queued.case_id asc
   limit 50;
end;
$$;

comment on function public.list_my_review_queue() is
  'Pseudonymous MARKET / ES queue for dossiers in the caller closed cohort. At most 50 open cases. A dossier outside the cohort is absent. Does not return names.';

revoke all on function public.list_my_review_queue()
  from public, anon, service_role;

grant execute on function public.list_my_review_queue() to authenticated;

create or replace function public.get_my_review_case(
  p_case_type text,
  p_case_id uuid
)
returns table (
  case_id uuid,
  case_type text,
  state text,
  market_country_code text,
  created_at timestamptz,
  updated_at timestamptz,
  subject_name text,
  equine_id uuid,
  equine_name text,
  relation_type text,
  relation_role text,
  evidence jsonb,
  evidence_sufficient boolean
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller_account uuid;
  caller_person uuid;
  grant_id uuid;
  identity_case public.identity_verification_cases%rowtype;
  ownership_claim public.equine_ownership_claims%rowtype;
  management_claim public.equine_management_authority_claims%rowtype;
  opened_subject_name text;
  opened_equine_id uuid;
  opened_equine_name text;
  opened_relation_type text;
  opened_relation_role text;
  opened_evidence jsonb;
  opened_sufficient boolean;
  opened_created_at timestamptz;
  opened_updated_at timestamptz;
  opened_state text;
  audit_entity_type text;
begin
  select resolved.account_id, resolved.person_id
    into caller_account, caller_person
    from public.verification_resolve_caller() as resolved;

  if p_case_id is null
     or p_case_type is null
     or p_case_type not in ('IDENTITY', 'OWNERSHIP', 'MANAGEMENT') then
    raise exception using
      errcode = '42501',
      message = 'Verification request is not available';
  end if;

  grant_id := public.verification_lock_spain_review_grant(caller_person);

  if grant_id is null
     or not public.verification_cohort_authorizes(caller_person, p_case_type, p_case_id) then
    raise exception using
      errcode = '42501',
      message = 'Verification request is not available';
  end if;

  if p_case_type = 'IDENTITY' then
    select identity_row.*
      into identity_case
      from public.identity_verification_cases as identity_row
     where identity_row.id = p_case_id
     for update;

    if not found
       or identity_case.market_country_code is distinct from 'ES'
       or identity_case.state not in ('SUBMITTED', 'IN_REVIEW', 'RESUBMITTED')
       or identity_case.subject_person_id is not distinct from caller_person
       or identity_case.submitted_by_account_id = caller_account then
      raise exception using
        errcode = '42501',
        message = 'Verification request is not available';
    end if;

    opened_subject_name := public.verification_person_minimum_name(
      identity_case.subject_person_id
    );
    opened_created_at := identity_case.created_at;
    opened_updated_at := identity_case.updated_at;
    opened_state := identity_case.state;
    audit_entity_type := 'identity_verification_case';
    opened_sufficient := public.verification_case_evidence_is_sufficient(
      'IDENTITY_CASE',
      identity_case.id
    );
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'category', evidence.category,
          'document_country_code', evidence.document_country_code
        )
        order by evidence.category, evidence.document_country_code, evidence.id
      ),
      '[]'::jsonb
    )
      into opened_evidence
      from public.verification_evidence as evidence
     where evidence.identity_case_id = identity_case.id;
  elsif p_case_type = 'OWNERSHIP' then
    select ownership_row.*
      into ownership_claim
      from public.equine_ownership_claims as ownership_row
     where ownership_row.id = p_case_id
     for update;

    if not found
       or ownership_claim.market_country_code is distinct from 'ES'
       or ownership_claim.state not in ('SUBMITTED', 'IN_REVIEW', 'RESUBMITTED')
       or ownership_claim.owner_person_id is not distinct from caller_person
       or ownership_claim.submitted_by_account_id = caller_account
       or public.verification_person_acts_for_center(
         caller_person,
         ownership_claim.owner_center_id
       ) then
      raise exception using
        errcode = '42501',
        message = 'Verification request is not available';
    end if;

    select equine.name
      into opened_equine_name
      from public.equines as equine
     where equine.id = ownership_claim.equine_id;

    opened_equine_id := ownership_claim.equine_id;
    opened_relation_type := ownership_claim.owner_type;
    opened_relation_role := 'OWNER';
    opened_created_at := ownership_claim.created_at;
    opened_updated_at := ownership_claim.updated_at;
    opened_state := ownership_claim.state;
    audit_entity_type := 'equine_ownership_claim';
    if ownership_claim.owner_type = 'PERSON' then
      opened_subject_name := public.verification_person_minimum_name(
        ownership_claim.owner_person_id
      );
    else
      select center.name
        into opened_subject_name
        from public.equestrian_centers as center
       where center.id = ownership_claim.owner_center_id;
    end if;
    opened_sufficient := public.verification_case_evidence_is_sufficient(
      'OWNERSHIP_CLAIM',
      ownership_claim.id
    );
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'category', evidence.category,
          'document_country_code', evidence.document_country_code
        )
        order by evidence.category, evidence.document_country_code, evidence.id
      ),
      '[]'::jsonb
    )
      into opened_evidence
      from public.verification_evidence as evidence
     where evidence.ownership_claim_id = ownership_claim.id;
  else
    select management_row.*
      into management_claim
      from public.equine_management_authority_claims as management_row
     where management_row.id = p_case_id
     for update;

    if not found
       or management_claim.market_country_code is distinct from 'ES'
       or management_claim.state not in ('SUBMITTED', 'IN_REVIEW', 'RESUBMITTED')
       or management_claim.manager_person_id is not distinct from caller_person
       or management_claim.submitted_by_account_id = caller_account
       or public.verification_person_acts_for_center(
         caller_person,
         management_claim.manager_center_id
       ) then
      raise exception using
        errcode = '42501',
        message = 'Verification request is not available';
    end if;

    select equine.name
      into opened_equine_name
      from public.equines as equine
     where equine.id = management_claim.equine_id;

    opened_equine_id := management_claim.equine_id;
    opened_relation_type := management_claim.manager_type;
    opened_relation_role := management_claim.management_role;
    opened_created_at := management_claim.created_at;
    opened_updated_at := management_claim.updated_at;
    opened_state := management_claim.state;
    audit_entity_type := 'equine_management_authority_claim';
    if management_claim.manager_type = 'PERSON' then
      opened_subject_name := public.verification_person_minimum_name(
        management_claim.manager_person_id
      );
    else
      select center.name
        into opened_subject_name
        from public.equestrian_centers as center
       where center.id = management_claim.manager_center_id;
    end if;
    opened_sufficient := public.verification_case_evidence_is_sufficient(
      'MANAGEMENT_CLAIM',
      management_claim.id
    );
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'category', evidence.category,
          'document_country_code', evidence.document_country_code
        )
        order by evidence.category, evidence.document_country_code, evidence.id
      ),
      '[]'::jsonb
    )
      into opened_evidence
      from public.verification_evidence as evidence
     where evidence.management_claim_id = management_claim.id;
  end if;

  perform public.record_audit_event(
    'verification_review_opened',
    audit_entity_type,
    p_case_id,
    jsonb_build_object(
      'case_type', p_case_type,
      'market_country_code', 'ES',
      'state', opened_state
    )
  );

  return query
  select
    p_case_id,
    p_case_type,
    opened_state,
    'ES'::text,
    opened_created_at,
    opened_updated_at,
    opened_subject_name,
    opened_equine_id,
    opened_equine_name,
    opened_relation_type,
    opened_relation_role,
    opened_evidence,
    opened_sufficient;
end;
$$;

comment on function public.get_my_review_case(text, uuid) is
  'Re-authorizes one open dossier in the caller closed cohort. A known UUID outside that cohort fails as 42501 and is not audited as an open.';

revoke all on function public.get_my_review_case(text, uuid)
  from public, anon, service_role;

grant execute on function public.get_my_review_case(text, uuid) to authenticated;
