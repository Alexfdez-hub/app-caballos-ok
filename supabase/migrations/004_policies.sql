-- Phase 2B: versioned policy documents and historical acceptances.
-- Policy acceptance is deliberately separate from guardian consent.

create table public.policy_documents (
  id uuid primary key default gen_random_uuid(),
  policy_code text not null,
  policy_type text not null,
  role_code text,
  market_code text not null references public.markets (country_code),
  locale text not null,
  version text not null,
  title text not null,
  summary text,
  content text not null,
  effective_from timestamptz not null,
  effective_to timestamptz,
  status text not null,
  requires_reacceptance boolean not null,
  created_at timestamptz not null default now(),
  constraint policy_documents_identity_key
    unique (policy_code, market_code, locale, version),
  constraint policy_documents_effective_period_check
    check (effective_to is null or effective_to > effective_from),
  constraint policy_documents_type_check
    check (
      policy_type in (
        'TERMS_OF_SERVICE',
        'PRIVACY_POLICY',
        'RIDER_POLICY',
        'OWNER_POLICY',
        'CENTER_POLICY',
        'ASSESSOR_POLICY',
        'GUARDIAN_POLICY',
        'ACTIVITY_POLICY',
        'CENTER_RULES'
      )
    )
);

create index policy_documents_current_lookup_idx
  on public.policy_documents (policy_code, market_code, locale, status, effective_from);

create table public.policy_acceptances (
  id uuid primary key default gen_random_uuid(),
  policy_document_id uuid not null references public.policy_documents (id),
  -- MVP0 requires both the domain subject and authenticated accepting account.
  -- Guardian consent remains a separate future mechanism.
  person_id uuid not null references public.persons (id),
  user_account_id uuid not null references public.user_accounts (id),
  accepted_at timestamptz not null,
  acceptance_context text,
  role_code text,
  center_id uuid,
  booking_id uuid,
  metadata jsonb,
  created_at timestamptz not null default now()
);

comment on table public.policy_acceptances is
  'Historical evidence of policy acceptance; records must be retained and are distinct from guardian consent.';
comment on column public.policy_acceptances.center_id is
  'FK deferred until the frozen centers table is introduced in a later phase.';
comment on column public.policy_acceptances.booking_id is
  'FK deferred until the legacy bookings table is migrated to the frozen model in a later phase.';

create index policy_acceptances_person_document_idx
  on public.policy_acceptances (person_id, policy_document_id, accepted_at desc);
create index policy_acceptances_account_idx
  on public.policy_acceptances (user_account_id, accepted_at desc);
create index policy_acceptances_center_idx
  on public.policy_acceptances (center_id)
  where center_id is not null;
create index policy_acceptances_booking_idx
  on public.policy_acceptances (booking_id)
  where booking_id is not null;

alter table public.policy_documents enable row level security;
alter table public.policy_acceptances enable row level security;

-- Deny by default. Documents and acceptances remain inaccessible to clients
-- until reviewed read/RPC paths are introduced. No broad policy is added.
-- Later client-facing RLS policies must be paired with explicit grants.
revoke all on table public.policy_documents from anon, authenticated;
revoke all on table public.policy_acceptances from anon, authenticated;
