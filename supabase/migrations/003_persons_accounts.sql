-- Phase 2B: person/account separation.
--
-- Transitional deviation from the frozen target:
-- first_name, last_name, and date_of_birth are temporarily nullable because
-- the verified legacy schema does not contain deterministic source data for
-- these required person attributes. No values are fabricated and no legacy
-- rows are backfilled in this phase.

create table public.persons (
  id uuid primary key default gen_random_uuid(),
  first_name text,
  last_name text,
  display_name text,
  date_of_birth date,
  country_code text,
  status text not null default 'ACTIVE',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.persons is
  'Domain identity, independent from authentication. A person may exist without a user account.';
comment on column public.persons.first_name is
  'Temporarily nullable during expand/migrate; frozen target requires NOT NULL after verified data collection.';
comment on column public.persons.last_name is
  'Temporarily nullable during expand/migrate; frozen target requires NOT NULL after verified data collection.';
comment on column public.persons.date_of_birth is
  'Temporarily nullable during expand/migrate; frozen target requires NOT NULL after verified data collection.';

create table public.user_accounts (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid not null unique references auth.users (id),
  person_id uuid not null unique references public.persons (id),
  preferred_locale text,
  timezone text,
  status text not null default 'ACTIVE',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.user_accounts is
  'Authentication account mapped one-to-one to a person for MVP0; separate from legacy public.users.';

alter table public.persons enable row level security;
alter table public.user_accounts enable row level security;

-- Deny by default. Identity creation/linking remains inaccessible to clients
-- until a reviewed server-authoritative workflow is introduced.
revoke all on table public.persons from anon, authenticated;
revoke all on table public.user_accounts from anon, authenticated;
