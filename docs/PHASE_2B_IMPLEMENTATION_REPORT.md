# Phase 2B implementation report

**Phase:** Core Infrastructure + Markets + Persons/Accounts + Policies  
**Date:** 2026-08-29  
**Strategy:** expand only  
**Remote database modified:** no

## Scope implemented

Four ordered migrations were created:

1. `001_extensions_and_core.sql`
2. `002_markets.sql`
3. `003_persons_accounts.sql`
4. `004_policies.sql`

Local Supabase configuration and an intentionally empty seed file were added
for repeatable local validation. No application cutover or legacy backfill was
implemented.

## Legacy Auth path preserved

The following verified path remains unchanged:

```text
auth.users
  -> on_auth_user_created (AFTER INSERT)
  -> public.handle_new_user()
  -> public.users
```

The migrations do not alter, drop, replace, disable, or rename
`auth.users`, `on_auth_user_created`, `public.handle_new_user()`,
`public.users`, `public.horses`, or `public.bookings`.

Compatibility was tested locally by loading the Phase 2A legacy dump, adding
the verified trigger, applying all Phase 2B migrations, and inserting an Auth
user inside a rolled-back transaction. The trigger still created the expected
`public.users` row with role `jinete`.

## Database objects introduced

### Tables

- `public.markets`
- `public.persons`
- `public.user_accounts`
- `public.policy_documents`
- `public.policy_acceptances`

### Identity constraints

- Primary keys on all five tables.
- `user_accounts.auth_user_id` is unique, not null, and references
  `auth.users(id)`.
- `user_accounts.person_id` is unique, not null, and references
  `persons(id)`.
- A `persons` row can exist without a `user_accounts` row.

### Policy constraints

- `policy_documents.market_code` references `markets.country_code`.
- Policy document identity is unique across
  `(policy_code, market_code, locale, version)`.
- `policy_type` is constrained to the nine frozen policy types.
- A policy effective period must be open-ended or end after it starts.
- Each acceptance must identify both the domain person and the authenticated
  user account that performed the acceptance. Both FKs remain `NOT NULL` as an
  explicit MVP0 implementation decision.
- No uniqueness constraint collapses historical acceptances.

Guardian consent remains a separate future mechanism and is not represented
by a policy acceptance.

### Indexes

- PK and unique-constraint indexes.
- `policy_documents_current_lookup_idx`
- `policy_acceptances_person_document_idx`
- `policy_acceptances_account_idx`
- Partial indexes for non-null future `center_id` and `booking_id`.

The frozen priority lookups on `user_accounts.auth_user_id` and `person_id`
are covered by their unique indexes.

## RLS and security

RLS is enabled on every new table.

Phase 2B introduces **zero client RLS policies**. This is intentional:
unreviewed reads and writes remain denied. Table privileges are explicitly
revoked from `anon` and `authenticated`, protecting against the legacy
`public` schema default privileges that auto-expose new tables.

No broad `USING (true)` or `WITH CHECK (true)` policy was added. No client
code or service-role usage was added. Later client-facing RLS policies will
also require explicit table grants because RLS and SQL privileges are both
required for access.

## Transitional deviations

### Nullable frozen person attributes

Frozen architecture requires `persons.first_name`, `last_name`, and
`date_of_birth` to be not null. The authoritative legacy schema has only an
optional unsplit `full_name` and no date of birth.

Those three fields are temporarily nullable. The deviation is documented in
SQL comments and must be contracted only after verified values are collected
and backfilled. No placeholder personal data was fabricated.

### Deferred future foreign keys

`policy_acceptances.center_id` and `booking_id` are present as UUID columns,
but their FKs are deferred:

- centers are outside Phase 2B;
- the existing `public.bookings` table is the incompatible legacy table and
  must not be used as the frozen booking FK target.

The columns carry SQL comments documenting the deferred constraints.

### No extension recreation

`gen_random_uuid()` is available in the Supabase PostgreSQL environment and is
the only UUID prerequisite used here. Migration 001 intentionally creates no
extension, avoiding recreation or relocation of Supabase-managed extensions.

## Data migration decisions

- No existing Auth or `public.users` records were backfilled.
- No legacy `waiver_signed_at` value was converted into a policy acceptance.
- No market, policy document, or acceptance seed data was invented.
- The application continues to use only the legacy tables.

## Local validation

The generated Supabase CLI configuration targeted local Docker only.
`supabase start` was attempted but stopped before Docker startup because the
existing ignored root `.env` begins with a UTF-8 BOM that the CLI cannot
parse. The `.env` file was not read or modified.

Validation continued in an isolated local container using
`public.ecr.aws/supabase/postgres:17.6.1.165`:

- all four migrations executed successfully against a clean Supabase
  PostgreSQL database;
- all four executed successfully on top of a local reconstruction of the
  authoritative legacy public schema and verified Auth trigger;
- five expected tables and 16 expected constraints were found;
- 13 expected PK/unique/custom indexes were found;
- RLS was enabled on all five new tables;
- each new table had zero RLS policies;
- `anon` and `authenticated` had no SELECT/INSERT/UPDATE/DELETE privileges;
- a person-without-account insert succeeded in a rolled-back transaction;
- the preserved legacy Auth trigger remained operational.

Static review found no migration statement that alters or writes the legacy
tables/function/trigger, no `service_role` usage, and no permissive RLS
expression.

Application checks:

- `npm run typecheck` passed;
- `npx expo-doctor` passed 18/18 checks;
- `git diff --check` passed after documentation whitespace was corrected.

The validation container was local and disposable. No linked-project command
or remote database connection was used.

## Deferred work

No guardians, centers, equines, qualifications, assessments, services, zero
sessions, calendar, frozen booking migration, sessions, reviews, incidents,
Storage migration, legacy contraction, or application cutover was started.

No unresolved architecture conflict was found. The nullable identity fields
and future policy FKs are explicit phased-migration deviations, not silent
changes to the frozen target.
