# MIGRATION STATUS

PHASE: 2B — Core Infrastructure + Markets + Persons/Accounts + Policies
STATUS: COMPLETE — PENDING PRODUCT OWNER REVIEW AND REMOTE-APPLY AUTHORIZATION
DATE: 2026-08-29

PHASE 2A:
- Reviewed and approved.
- Checkpoint commit: `f088a18`.
- `docs/REMOTE_DATABASE_INVENTORY.md` is authoritative for the legacy public schema.
- Additional verified fact: `auth.users.on_auth_user_created` is an `AFTER INSERT`
  trigger executing `public.handle_new_user()`.

FILES CREATED:
- `supabase/.gitignore`
- `supabase/config.toml`
- `supabase/seed.sql` (intentionally no data)
- `supabase/migrations/001_extensions_and_core.sql`
- `supabase/migrations/002_markets.sql`
- `supabase/migrations/003_persons_accounts.sql`
- `supabase/migrations/004_policies.sql`
- `docs/PHASE_2B_IMPLEMENTATION_REPORT.md`

FILES MODIFIED:
- `docs/REMOTE_DATABASE_INVENTORY.md` (recorded verified Auth trigger)
- `docs/MIGRATION_STATUS.md`

DEPENDENCIES:
- None added or removed.
- Supabase CLI was used through `npx`; it was not added to `package.json`.

MIGRATIONS CREATED:
- `001_extensions_and_core.sql` — records that no extension recreation is
  required; makes no legacy changes.
- `002_markets.sql` — creates `markets`.
- `003_persons_accounts.sql` — creates separate `persons` and `user_accounts`.
- `004_policies.sql` — creates versioned `policy_documents` and historical
  `policy_acceptances`.

NEW DATABASE OBJECTS:
- Tables: `markets`, `persons`, `user_accounts`, `policy_documents`,
  `policy_acceptances`.
- PKs on all new tables.
- Unique constraints on `user_accounts.auth_user_id`,
  `user_accounts.person_id`, and policy document version identity.
- FKs: account→Auth, account→person, policy document→market, and acceptance→
  policy document/person/account.
- Policy type CHECK for all frozen policy types.
- Policy effective-period CHECK requires `effective_to > effective_from` when
  an end timestamp is present.
- `policy_acceptances.person_id` and `user_account_id` remain NOT NULL: MVP0
  acceptance evidence identifies both the domain person and authenticated
  accepting account. Guardian consent remains separate.
- Custom indexes: one current-policy lookup and four acceptance lookup indexes.

RLS / SECURITY:
- RLS enabled on all five new tables.
- Zero client RLS policies introduced: default posture is deny.
- All table privileges revoked from `anon` and `authenticated` intentionally.
- Later client-facing RLS policies will also require explicit table grants.
- No permissive `USING (true)` / `WITH CHECK (true)` policies.
- No client `service_role` usage.
- Legacy RLS, grants, tables, function, and Auth trigger are unchanged.

TRANSITIONAL DEVIATIONS:
- `persons.first_name`, `last_name`, and `date_of_birth` are temporarily
  nullable. The frozen target remains NOT NULL, but real legacy values are
  unavailable and were not fabricated.
- `policy_acceptances.center_id` and `booking_id` have deferred FKs because
  centers are not yet created and current `bookings` is the incompatible
  legacy table.
- No Auth/public-user backfill and no application cutover occurred.
- Legacy `waiver_signed_at` was not interpreted or migrated.

LOCAL VALIDATION:
- `npx supabase init` completed and generated local-only configuration.
- `npx supabase start` did not start because the existing ignored root `.env`
  has an invalid UTF-8 BOM for the CLI parser. The file was not read or changed.
- An isolated local Supabase PostgreSQL 17.6 container was used instead.
- All four migrations executed successfully from a clean local database.
- All four also executed successfully over a local reconstruction of the
  authoritative legacy schema plus verified Auth trigger.
- Verified 5 new tables, 16 constraints, 13 indexes, RLS on every new table,
  zero RLS policies, and no client DML privileges.
- Verified a person can exist without an account.
- Verified Auth insert still invokes `handle_new_user()` and creates the
  legacy `public.users` row.

APPLICATION CHECKS:
- `npm run typecheck` — passed.
- `npx expo-doctor` — passed 18/18 checks.
- `git diff --check` — passed after removing documentation trailing spaces.
- npm continues to report the existing unknown `devdir` environment warning.

REMOTE DATABASE:
- **NOT MODIFIED.**
- No `db push`, remote migration apply, remote reset, remote seed, or remote SQL.
- All SQL execution was against disposable local Docker databases only.

KNOWN ISSUES / MANUAL STEPS:
- Remove the UTF-8 BOM from the ignored root `.env` before using the normal
  local Supabase CLI stack; preserve the existing variable values.
- Product Owner/data collection must resolve real first name, last name, and
  date of birth before enforcing frozen NOT NULL constraints.
- Future phases must add FKs for acceptance `center_id` / frozen `booking_id`
  when their correct target tables exist.
- Do not apply these migrations remotely until separately authorized.

ARCHITECTURE CONFLICTS:
- None unresolved.

NEXT PHASE:
- Not authorized.
- STOP after Product Owner review of Phase 2B.
