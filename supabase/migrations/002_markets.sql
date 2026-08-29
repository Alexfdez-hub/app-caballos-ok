-- Phase 2B: market-specific configuration.

create table public.markets (
  country_code text primary key,
  default_currency text,
  default_locale text,
  timezone text,
  status text,
  config jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.markets is
  'Market-specific legal and business configuration. Concrete legal values require Product Owner validation.';

alter table public.markets enable row level security;

-- Deny by default. No client policy is introduced in Phase 2B.
revoke all on table public.markets from anon, authenticated;
