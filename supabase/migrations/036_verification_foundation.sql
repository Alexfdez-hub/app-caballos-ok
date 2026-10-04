-- Stage 1. Verification foundation schema.
--
-- Cases, claims, append-only decisions, referenced evidence and review
-- grants. Does not add client RPCs, a KYC vendor, biometric columns,
-- document bytes, calendar changes, insurance gates, or migration 037.
-- Does not deploy. audit_events emission waits for the Stage 2 RPC that
-- resolves the caller from auth.uid().

alter table public.user_accounts
  add constraint user_accounts_id_person_key unique (id, person_id);

create function public.enforce_verification_decision_immutability()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  if tg_op = 'INSERT' then
    if tg_table_name = 'identity_verification_decisions' then
      if exists (
        select 1
          from public.identity_verification_cases as subject_case
         where subject_case.id = new.case_id
           and (
             subject_case.subject_person_id = new.reviewer_person_id
             or subject_case.submitted_by_account_id = new.reviewer_account_id
           )
      ) then
        raise exception using
          errcode = '42501',
          message = 'Verification review is not available';
      end if;
    elsif tg_table_name = 'equine_relationship_decisions' then
      if new.ownership_claim_id is not null and exists (
        select 1
          from public.equine_ownership_claims as claim
         where claim.id = new.ownership_claim_id
           and (
             claim.owner_person_id is not distinct from new.reviewer_person_id
             or claim.submitted_by_account_id = new.reviewer_account_id
           )
      ) then
        raise exception using
          errcode = '42501',
          message = 'Verification review is not available';
      end if;

      if new.management_claim_id is not null and exists (
        select 1
          from public.equine_management_authority_claims as claim
         where claim.id = new.management_claim_id
           and (
             claim.manager_person_id is not distinct from new.reviewer_person_id
             or claim.submitted_by_account_id = new.reviewer_account_id
           )
      ) then
        raise exception using
          errcode = '42501',
          message = 'Verification review is not available';
      end if;
    end if;

    return new;
  end if;

  raise exception using
    errcode = '42501',
    message = 'Verification decisions are append-only';
end;
$$;

comment on function public.enforce_verification_decision_immutability() is
  'SECURITY INVOKER. Insert refuses a reviewer who is the subject PERSON, the claimant PERSON, or the submitter ACCOUNT. It does not resolve center affiliation or serialize competing reviews. Update and delete are refused. Not granted to clients.';

revoke all on function public.enforce_verification_decision_immutability()
  from public, anon, authenticated;

create table public.identity_verification_cases (
  id uuid primary key default gen_random_uuid(),
  subject_person_id uuid not null references public.persons (id),
  market_country_code text not null references public.markets (country_code),
  state text not null default 'DRAFT',
  submitted_by_account_id uuid not null references public.user_accounts (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint identity_verification_cases_state_check
    check (
      state in (
        'DRAFT',
        'SUBMITTED',
        'IN_REVIEW',
        'ACCEPTED',
        'REJECTED',
        'RESUBMITTED',
        'EXPIRED',
        'REVOKED',
        'SUPERSEDED'
      )
    )
);

comment on table public.identity_verification_cases is
  'Identity verification case for one PERSON and one operating market. Not an account, not equine ownership, and not a KYC document store.';
comment on column public.identity_verification_cases.market_country_code is
  'Operating market of the case. Not nationality, residence, KYC document country, or activity jurisdiction.';
comment on column public.identity_verification_cases.subject_person_id is
  'PERSON being verified. Distinct from the submitter ACCOUNT.';

create table public.identity_verification_decisions (
  id uuid primary key default gen_random_uuid(),
  case_id uuid not null references public.identity_verification_cases (id),
  outcome text not null,
  reason_code text not null,
  reviewer_account_id uuid not null,
  reviewer_person_id uuid not null,
  decided_at timestamptz not null default now(),
  expires_at timestamptz,
  constraint identity_verification_decisions_reviewer_fk
    foreign key (reviewer_account_id, reviewer_person_id)
    references public.user_accounts (id, person_id),
  constraint identity_verification_decisions_outcome_check
    check (
      outcome in ('ACCEPTED', 'REJECTED', 'EXPIRED', 'REVOKED', 'SUPERSEDED')
    ),
  constraint identity_verification_decisions_reason_check
    check (
      reason_code = btrim(reason_code)
      and char_length(reason_code) between 1 and 80
    ),
  constraint identity_verification_decisions_expiry_check
    check (expires_at is null or expires_at > decided_at)
);

comment on table public.identity_verification_decisions is
  'Append-only identity review outcome. No retention interval is assumed. expires_at stays null until a later retention decision.';

create trigger identity_verification_decisions_immutable
before insert or update or delete on public.identity_verification_decisions
for each row execute function public.enforce_verification_decision_immutability();

create table public.equine_ownership_claims (
  id uuid primary key default gen_random_uuid(),
  equine_id uuid not null references public.equines (id),
  market_country_code text not null references public.markets (country_code),
  state text not null default 'DECLARED',
  owner_type text not null,
  owner_person_id uuid references public.persons (id),
  owner_center_id uuid references public.equestrian_centers (id),
  ownership_percentage numeric not null,
  effective_ownership_id uuid references public.equine_ownerships (id),
  submitted_by_account_id uuid not null references public.user_accounts (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint equine_ownership_claims_state_check
    check (
      state in (
        'DECLARED',
        'SUBMITTED',
        'IN_REVIEW',
        'ACCEPTED',
        'REJECTED',
        'CONFLICT',
        'RESUBMITTED',
        'EXPIRED',
        'REVOKED',
        'WITHDRAWN'
      )
    ),
  constraint equine_ownership_claims_owner_type_check
    check (owner_type in ('PERSON', 'CENTER')),
  constraint equine_ownership_claims_owner_xor_check
    check (
      (
        owner_type = 'PERSON'
        and owner_person_id is not null
        and owner_center_id is null
      )
      or (
        owner_type = 'CENTER'
        and owner_center_id is not null
        and owner_person_id is null
      )
    ),
  constraint equine_ownership_claims_percentage_check
    check (ownership_percentage > 0 and ownership_percentage <= 100)
);

comment on table public.equine_ownership_claims is
  'Ownership corroboration request. Does not insert or update equine_ownerships and does not transfer rights.';
comment on column public.equine_ownership_claims.effective_ownership_id is
  'Optional link to the effective ownership row being corroborated. Null means the claim does not match an effective row.';

create table public.equine_management_authority_claims (
  id uuid primary key default gen_random_uuid(),
  equine_id uuid not null references public.equines (id),
  market_country_code text not null references public.markets (country_code),
  state text not null default 'DECLARED',
  manager_type text not null,
  manager_person_id uuid references public.persons (id),
  manager_center_id uuid references public.equestrian_centers (id),
  management_role text not null,
  valid_from timestamptz not null,
  valid_until timestamptz,
  effective_assignment_id uuid references public.equine_management_assignments (id),
  submitted_by_account_id uuid not null references public.user_accounts (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint equine_management_authority_claims_state_check
    check (
      state in (
        'DECLARED',
        'SUBMITTED',
        'IN_REVIEW',
        'ACCEPTED',
        'REJECTED',
        'CONFLICT',
        'RESUBMITTED',
        'EXPIRED',
        'REVOKED',
        'WITHDRAWN'
      )
    ),
  constraint equine_management_authority_claims_manager_type_check
    check (manager_type in ('PERSON', 'CENTER')),
  constraint equine_management_authority_claims_manager_xor_check
    check (
      (
        manager_type = 'PERSON'
        and manager_person_id is not null
        and manager_center_id is null
      )
      or (
        manager_type = 'CENTER'
        and manager_center_id is not null
        and manager_person_id is null
      )
    ),
  constraint equine_management_authority_claims_role_check
    check (
      management_role in (
        'PRIMARY_MANAGER',
        'CO_MANAGER',
        'AUTHORIZED_MANAGER'
      )
    ),
  constraint equine_management_authority_claims_window_check
    check (valid_until is null or valid_until >= valid_from)
);

comment on table public.equine_management_authority_claims is
  'Management-authority corroboration request. Does not insert or update equine_management_assignments and does not prove ownership.';

create table public.equine_relationship_decisions (
  id uuid primary key default gen_random_uuid(),
  claim_type text not null,
  ownership_claim_id uuid references public.equine_ownership_claims (id),
  management_claim_id uuid references public.equine_management_authority_claims (id),
  outcome text not null,
  reason_code text not null,
  reviewer_account_id uuid not null,
  reviewer_person_id uuid not null,
  decided_at timestamptz not null default now(),
  expires_at timestamptz,
  constraint equine_relationship_decisions_reviewer_fk
    foreign key (reviewer_account_id, reviewer_person_id)
    references public.user_accounts (id, person_id),
  constraint equine_relationship_decisions_type_check
    check (claim_type in ('OWNERSHIP', 'MANAGEMENT')),
  constraint equine_relationship_decisions_parent_check
    check (
      (
        claim_type = 'OWNERSHIP'
        and ownership_claim_id is not null
        and management_claim_id is null
      )
      or (
        claim_type = 'MANAGEMENT'
        and management_claim_id is not null
        and ownership_claim_id is null
      )
    ),
  constraint equine_relationship_decisions_outcome_check
    check (
      outcome in ('ACCEPTED', 'REJECTED', 'EXPIRED', 'REVOKED', 'SUPERSEDED')
    ),
  constraint equine_relationship_decisions_reason_check
    check (
      reason_code = btrim(reason_code)
      and char_length(reason_code) between 1 and 80
    ),
  constraint equine_relationship_decisions_expiry_check
    check (expires_at is null or expires_at > decided_at)
);

comment on table public.equine_relationship_decisions is
  'Append-only corroboration outcome for an ownership or management claim. It does not rewrite the effective relationship.';

create trigger equine_relationship_decisions_immutable
before insert or update or delete on public.equine_relationship_decisions
for each row execute function public.enforce_verification_decision_immutability();

create table public.verification_evidence (
  id uuid primary key default gen_random_uuid(),
  parent_type text not null,
  identity_case_id uuid references public.identity_verification_cases (id),
  ownership_claim_id uuid references public.equine_ownership_claims (id),
  management_claim_id uuid references public.equine_management_authority_claims (id),
  category text not null,
  document_country_code text,
  provider_reference text,
  provider_outcome text,
  assurance_level text,
  storage_bucket text,
  storage_path text,
  note_text text,
  submitted_by_account_id uuid not null references public.user_accounts (id),
  created_at timestamptz not null default now(),
  constraint verification_evidence_parent_type_check
    check (parent_type in ('IDENTITY_CASE', 'OWNERSHIP_CLAIM', 'MANAGEMENT_CLAIM')),
  constraint verification_evidence_parent_check
    check (
      (
        parent_type = 'IDENTITY_CASE'
        and identity_case_id is not null
        and ownership_claim_id is null
        and management_claim_id is null
      )
      or (
        parent_type = 'OWNERSHIP_CLAIM'
        and ownership_claim_id is not null
        and identity_case_id is null
        and management_claim_id is null
      )
      or (
        parent_type = 'MANAGEMENT_CLAIM'
        and management_claim_id is not null
        and identity_case_id is null
        and ownership_claim_id is null
      )
    ),
  constraint verification_evidence_category_check
    check (
      category in (
        'IDENTITY_PROVIDER_REFERENCE',
        'EQUINE_IDENTIFIER_REFERENCE',
        'OWNERSHIP_ARTIFACT',
        'MANAGEMENT_DELEGATION_ARTIFACT',
        'CENTER_CORROBORATION',
        'INSURANCE_REFERENCE',
        'REVIEWER_NOTE'
      )
    ),
  constraint verification_evidence_document_country_check
    check (
      document_country_code is null
      or document_country_code ~ '^[A-Z]{2}$'
    ),
  constraint verification_evidence_identity_reference_check
    check (
      category <> 'IDENTITY_PROVIDER_REFERENCE'
      or (
        provider_reference is not null
        and char_length(provider_reference) between 1 and 200
        and storage_bucket is null
        and storage_path is null
        and note_text is null
      )
    ),
  constraint verification_evidence_file_check
    check (
      category not in (
        'EQUINE_IDENTIFIER_REFERENCE',
        'OWNERSHIP_ARTIFACT',
        'MANAGEMENT_DELEGATION_ARTIFACT',
        'CENTER_CORROBORATION',
        'INSURANCE_REFERENCE'
      )
      or (
        provider_reference is null
        and storage_bucket is not null
        and storage_path is not null
        and char_length(storage_bucket) between 1 and 80
        and char_length(storage_path) between 1 and 500
        and note_text is null
      )
    ),
  constraint verification_evidence_note_check
    check (
      category <> 'REVIEWER_NOTE'
      or (
        provider_reference is null
        and storage_bucket is null
        and storage_path is null
        and note_text is not null
        and char_length(note_text) between 1 and 500
      )
    ),
  constraint verification_evidence_center_parent_check
    check (
      category <> 'CENTER_CORROBORATION'
      or parent_type in ('OWNERSHIP_CLAIM', 'MANAGEMENT_CLAIM')
    ),
  constraint verification_evidence_identity_parent_check
    check (
      category <> 'IDENTITY_PROVIDER_REFERENCE'
      or parent_type = 'IDENTITY_CASE'
    )
);

comment on table public.verification_evidence is
  'Private evidence reference. Stores an opaque provider reference or a private object path. Does not store document bytes, biometric templates, a vendor name, or a public URL.';
comment on column public.verification_evidence.document_country_code is
  'Country of the referenced document when explicitly supplied. Not nationality, residence, operating market, or activity jurisdiction.';
comment on column public.verification_evidence.category is
  'CENTER_CORROBORATION attests custody, presence, or a physical check. It does not prove or transfer ownership. INSURANCE_REFERENCE does not block private equine creation.';

create table public.verification_review_grants (
  id uuid primary key default gen_random_uuid(),
  reviewer_person_id uuid not null references public.persons (id),
  scope_type text not null,
  market_country_code text references public.markets (country_code),
  status text not null default 'ACTIVE',
  valid_from timestamptz not null default now(),
  valid_until timestamptz,
  created_at timestamptz not null default now(),
  constraint verification_review_grants_scope_check
    check (scope_type in ('PLATFORM_IDENTITY', 'PLATFORM_EQUINE', 'MARKET')),
  constraint verification_review_grants_market_check
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
  constraint verification_review_grants_status_check
    check (status in ('ACTIVE', 'ENDED')),
  constraint verification_review_grants_window_check
    check (
      (
        status = 'ACTIVE'
        and valid_until is null
      )
      or (
        status = 'ENDED'
        and valid_until is not null
        and valid_until >= valid_from
      )
    )
);

comment on table public.verification_review_grants is
  'Separate review authority. Not a center membership, ownership row, or management row. No grant is seeded. REVIEWER-GRANT-AUTHORITY remains open, so clients cannot insert grants.';

create index identity_verification_cases_subject_idx
  on public.identity_verification_cases (subject_person_id);
create index identity_verification_cases_market_idx
  on public.identity_verification_cases (market_country_code);
create index identity_verification_cases_submitter_idx
  on public.identity_verification_cases (submitted_by_account_id);
create index identity_verification_decisions_case_idx
  on public.identity_verification_decisions (case_id, decided_at);
create index identity_verification_decisions_reviewer_account_idx
  on public.identity_verification_decisions (reviewer_account_id);
create index identity_verification_decisions_reviewer_person_idx
  on public.identity_verification_decisions (reviewer_person_id);

create index equine_ownership_claims_equine_idx
  on public.equine_ownership_claims (equine_id);
create index equine_ownership_claims_market_idx
  on public.equine_ownership_claims (market_country_code);
create index equine_ownership_claims_owner_person_idx
  on public.equine_ownership_claims (owner_person_id);
create index equine_ownership_claims_owner_center_idx
  on public.equine_ownership_claims (owner_center_id);
create index equine_ownership_claims_effective_idx
  on public.equine_ownership_claims (effective_ownership_id);
create index equine_ownership_claims_submitter_idx
  on public.equine_ownership_claims (submitted_by_account_id);

create index equine_management_authority_claims_equine_idx
  on public.equine_management_authority_claims (equine_id);
create index equine_management_authority_claims_market_idx
  on public.equine_management_authority_claims (market_country_code);
create index equine_management_authority_claims_manager_person_idx
  on public.equine_management_authority_claims (manager_person_id);
create index equine_management_authority_claims_manager_center_idx
  on public.equine_management_authority_claims (manager_center_id);
create index equine_management_authority_claims_effective_idx
  on public.equine_management_authority_claims (effective_assignment_id);
create index equine_management_authority_claims_submitter_idx
  on public.equine_management_authority_claims (submitted_by_account_id);

create index equine_relationship_decisions_ownership_idx
  on public.equine_relationship_decisions (ownership_claim_id, decided_at);
create index equine_relationship_decisions_management_idx
  on public.equine_relationship_decisions (management_claim_id, decided_at);
create index equine_relationship_decisions_reviewer_account_idx
  on public.equine_relationship_decisions (reviewer_account_id);
create index equine_relationship_decisions_reviewer_person_idx
  on public.equine_relationship_decisions (reviewer_person_id);

create index verification_evidence_identity_case_idx
  on public.verification_evidence (identity_case_id);
create index verification_evidence_ownership_claim_idx
  on public.verification_evidence (ownership_claim_id);
create index verification_evidence_management_claim_idx
  on public.verification_evidence (management_claim_id);
create index verification_evidence_submitter_idx
  on public.verification_evidence (submitted_by_account_id);

create index verification_review_grants_market_idx
  on public.verification_review_grants (market_country_code);
create index verification_review_grants_lookup_idx
  on public.verification_review_grants (
    reviewer_person_id,
    scope_type,
    market_country_code,
    status,
    valid_from,
    valid_until
  );

alter table public.identity_verification_cases enable row level security;
alter table public.identity_verification_decisions enable row level security;
alter table public.equine_ownership_claims enable row level security;
alter table public.equine_management_authority_claims enable row level security;
alter table public.equine_relationship_decisions enable row level security;
alter table public.verification_evidence enable row level security;
alter table public.verification_review_grants enable row level security;

revoke all on table public.identity_verification_cases from public, anon, authenticated;
revoke all on table public.identity_verification_decisions from public, anon, authenticated;
revoke all on table public.equine_ownership_claims from public, anon, authenticated;
revoke all on table public.equine_management_authority_claims from public, anon, authenticated;
revoke all on table public.equine_relationship_decisions from public, anon, authenticated;
revoke all on table public.verification_evidence from public, anon, authenticated;
revoke all on table public.verification_review_grants from public, anon, authenticated;
