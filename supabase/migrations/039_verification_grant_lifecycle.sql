-- Stage 4B.2. Technical lifecycle for one fictional MARKET / ES review grant.
--
-- The projection stays verification_review_grants. Only ACTIVE matches
-- verification_review_grant_matches, which this migration does not replace.
-- SUSPENDED stops matching immediately. ENDED is a final close.
-- Reactivation is not implemented.
--
-- audit_events cannot record this bootstrap. record_audit_event resolves a
-- product PERSON from auth.uid(), and a database-owner session has none.
-- Forging that claim would pretend the owner is a person. Grant events are
-- a separate append-only history. A TECHNICAL actor stores the PostgreSQL
-- principal. A PRODUCT actor is reserved for a later authenticated
-- administrator and is not written here.
--
-- Refused attempts are not stored. Raising an error rolls the transaction
-- back, so an event inserted before the error would disappear. Denial audit
-- waits for a later server path that can return a result without raising.
--
-- These functions are not an API. Expo, anon, authenticated, and
-- service_role cannot execute them. A superuser still bypasses GRANT;
-- the body accepts only current_user postgres or supabase_admin.

alter table public.verification_review_grants
  drop constraint verification_review_grants_status_check;

alter table public.verification_review_grants
  add constraint verification_review_grants_status_check
    check (status in ('ACTIVE', 'SUSPENDED', 'ENDED'));

alter table public.verification_review_grants
  drop constraint verification_review_grants_window_check;

alter table public.verification_review_grants
  add constraint verification_review_grants_window_check
    check (
      (
        status in ('ACTIVE', 'SUSPENDED')
        and valid_until is null
      )
      or (
        status = 'ENDED'
        and valid_until is not null
        and valid_until >= valid_from
      )
    );

comment on table public.verification_review_grants is
  'Current review-grant projection. ACTIVE is the only matching status. SUSPENDED stops review immediately and is not a close. ENDED is final. No grant is seeded. Clients cannot write this table.';

create unique index verification_review_grants_one_open_idx
  on public.verification_review_grants (
    reviewer_person_id,
    scope_type,
    coalesce(market_country_code, '')
  )
  where status in ('ACTIVE', 'SUSPENDED');

create table public.verification_review_grant_events (
  id uuid primary key default gen_random_uuid(),
  grant_id uuid not null references public.verification_review_grants (id),
  event_type text not null,
  reviewer_person_id uuid not null references public.persons (id),
  scope_type text not null,
  market_country_code text,
  previous_status text,
  new_status text not null,
  actor_kind text not null,
  technical_principal text,
  actor_account_id uuid,
  actor_person_id uuid,
  reason_code text not null,
  occurred_at timestamptz not null default clock_timestamp(),
  constraint verification_review_grant_events_type_check
    check (event_type in ('GRANTED', 'SUSPENDED', 'CLOSED')),
  constraint verification_review_grant_events_scope_check
    check (scope_type in ('PLATFORM_IDENTITY', 'PLATFORM_EQUINE', 'MARKET')),
  constraint verification_review_grant_events_market_check
    check (
      (
        scope_type = 'MARKET'
        and market_country_code is not null
      )
      or (
        scope_type in ('PLATFORM_IDENTITY', 'PLATFORM_EQUINE')
        and market_country_code is null
      )
    ),
  constraint verification_review_grant_events_previous_check
    check (
      previous_status is null
      or previous_status in ('ACTIVE', 'SUSPENDED', 'ENDED')
    ),
  constraint verification_review_grant_events_new_check
    check (new_status in ('ACTIVE', 'SUSPENDED', 'ENDED')),
  constraint verification_review_grant_events_granted_check
    check (
      event_type <> 'GRANTED'
      or (
        previous_status is null
        and new_status = 'ACTIVE'
      )
    ),
  constraint verification_review_grant_events_suspended_check
    check (
      event_type <> 'SUSPENDED'
      or (
        previous_status = 'ACTIVE'
        and new_status = 'SUSPENDED'
      )
    ),
  constraint verification_review_grant_events_closed_check
    check (
      event_type <> 'CLOSED'
      or (
        previous_status = 'ACTIVE'
        and new_status = 'ENDED'
      )
    ),
  constraint verification_review_grant_events_actor_check
    check (actor_kind in ('TECHNICAL', 'PRODUCT')),
  constraint verification_review_grant_events_actor_exclusive_check
    check (
      (
        actor_kind = 'TECHNICAL'
        and technical_principal is not null
        and actor_account_id is null
        and actor_person_id is null
      )
      or (
        actor_kind = 'PRODUCT'
        and technical_principal is null
        and actor_account_id is not null
        and actor_person_id is not null
      )
    ),
  constraint verification_review_grant_events_reason_check
    check (reason_code ~ '^[A-Z0-9_]{1,80}$')
);

comment on table public.verification_review_grant_events is
  'Append-only review-grant history. TECHNICAL stores a PostgreSQL principal, not a product PERSON. PRODUCT is reserved for a later authenticated administrator and is not written by migration 039. Refused attempts are not rows in this table.';

create index verification_review_grant_events_grant_idx
  on public.verification_review_grant_events (grant_id, occurred_at);

create function public.enforce_verification_grant_event_immutability()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
begin
  if tg_op = 'UPDATE' or tg_op = 'DELETE' then
    raise exception using
      errcode = '42501',
      message = 'Verification grant history cannot be rewritten';
  end if;

  new.occurred_at := clock_timestamp();
  return new;
end;
$$;

comment on function public.enforce_verification_grant_event_immutability() is
  'SECURITY INVOKER. Update and delete are refused. occurred_at is the server clock. Not granted to clients.';

revoke all on function public.enforce_verification_grant_event_immutability()
  from public, anon, authenticated, service_role;

create trigger verification_review_grant_events_immutable
before insert or update or delete on public.verification_review_grant_events
for each row execute function public.enforce_verification_grant_event_immutability();

create function public.verification_grant_technical_principal()
returns text
language plpgsql
stable
security invoker
set search_path = pg_catalog, public
as $$
begin
  if current_user not in ('postgres', 'supabase_admin') then
    raise exception using
      errcode = '42501',
      message = 'Verification grant operation is not available';
  end if;

  return session_user;
end;
$$;

comment on function public.verification_grant_technical_principal() is
  'Returns the PostgreSQL login principal for postgres or supabase_admin. Does not read auth.uid() and does not invent a PERSON. Not executable by PUBLIC, anon, authenticated, or service_role.';

revoke all on function public.verification_grant_technical_principal()
  from public, anon, authenticated, service_role;

create function public.bootstrap_verification_review_grant(
  p_reviewer_person_id uuid
)
returns uuid
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
declare
  created_grant_id uuid;
  technical_principal text;
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
    status
  ) values (
    p_reviewer_person_id,
    'MARKET',
    'ES',
    'ACTIVE'
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

comment on function public.bootstrap_verification_review_grant(uuid) is
  'Creates one MARKET / ES review grant for an ACTIVE person with an ACTIVE account. Scope and market are fixed. The actor is the PostgreSQL principal, not a client id. Does not grant administration of other grants. Not an Expo or service_role API.';

revoke all on function public.bootstrap_verification_review_grant(uuid)
  from public, anon, authenticated, service_role;

create function public.suspend_verification_review_grant(
  p_grant_id uuid
)
returns void
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
declare
  technical_principal text;
  grant_row public.verification_review_grants%rowtype;
begin
  technical_principal := public.verification_grant_technical_principal();

  if p_grant_id is null then
    raise exception using
      errcode = '42501',
      message = 'Verification grant operation is not available';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    392,
    pg_catalog.hashtext(p_grant_id::text)
  );

  select open_grant.*
    into grant_row
    from public.verification_review_grants as open_grant
   where open_grant.id = p_grant_id
   for update;

  if not found
     or grant_row.scope_type is distinct from 'MARKET'
     or grant_row.market_country_code is distinct from 'ES'
     or grant_row.status is distinct from 'ACTIVE' then
    raise exception using
      errcode = '42501',
      message = 'Verification grant operation is not available';
  end if;

  update public.verification_review_grants as open_grant
     set status = 'SUSPENDED'
   where open_grant.id = p_grant_id
     and open_grant.status = 'ACTIVE'
     and open_grant.scope_type = 'MARKET'
     and open_grant.market_country_code = 'ES';

  if not found then
    raise exception using
      errcode = '42501',
      message = 'Verification grant operation is not available';
  end if;

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
    grant_row.id,
    'SUSPENDED',
    grant_row.reviewer_person_id,
    grant_row.scope_type,
    grant_row.market_country_code,
    'ACTIVE',
    'SUSPENDED',
    'TECHNICAL',
    technical_principal,
    'PILOT_SUSPEND'
  );
end;
$$;

comment on function public.suspend_verification_review_grant(uuid) is
  'Moves one ACTIVE MARKET / ES grant to SUSPENDED and appends one event. Does not reactivate and does not close. A suspended grant no longer matches. Not an Expo or service_role API.';

revoke all on function public.suspend_verification_review_grant(uuid)
  from public, anon, authenticated, service_role;

create function public.close_verification_review_grant(
  p_grant_id uuid
)
returns void
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
declare
  technical_principal text;
  grant_row public.verification_review_grants%rowtype;
  closed_at timestamptz;
begin
  technical_principal := public.verification_grant_technical_principal();

  if p_grant_id is null then
    raise exception using
      errcode = '42501',
      message = 'Verification grant operation is not available';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    392,
    pg_catalog.hashtext(p_grant_id::text)
  );

  select open_grant.*
    into grant_row
    from public.verification_review_grants as open_grant
   where open_grant.id = p_grant_id
   for update;

  if not found
     or grant_row.scope_type is distinct from 'MARKET'
     or grant_row.market_country_code is distinct from 'ES'
     or grant_row.status is distinct from 'ACTIVE' then
    raise exception using
      errcode = '42501',
      message = 'Verification grant operation is not available';
  end if;

  closed_at := clock_timestamp();

  update public.verification_review_grants as open_grant
     set status = 'ENDED',
         valid_until = closed_at
   where open_grant.id = p_grant_id
     and open_grant.status = 'ACTIVE'
     and open_grant.scope_type = 'MARKET'
     and open_grant.market_country_code = 'ES';

  if not found then
    raise exception using
      errcode = '42501',
      message = 'Verification grant operation is not available';
  end if;

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
    grant_row.id,
    'CLOSED',
    grant_row.reviewer_person_id,
    grant_row.scope_type,
    grant_row.market_country_code,
    'ACTIVE',
    'ENDED',
    'TECHNICAL',
    technical_principal,
    'PILOT_CLOSE'
  );
end;
$$;

comment on function public.close_verification_review_grant(uuid) is
  'Closes one ACTIVE MARKET / ES grant. ENDED is final: this function does not close a suspended grant and does not reactivate. Not an Expo or service_role API.';

revoke all on function public.close_verification_review_grant(uuid)
  from public, anon, authenticated, service_role;

alter table public.verification_review_grant_events enable row level security;

revoke all on table public.verification_review_grant_events
  from public, anon, authenticated, service_role;

revoke all on table public.verification_review_grants
  from service_role;
