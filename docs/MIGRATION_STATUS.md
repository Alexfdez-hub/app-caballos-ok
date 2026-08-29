# MIGRATION STATUS

PHASE: 2A — Remote schema inventory (read-only)  
STATUS: COMPLETE — PENDING PRODUCT OWNER REVIEW  
DATE: 2026-08-29

FILES CREATED:
- `docs/REMOTE_DATABASE_INVENTORY.md`

FILES MODIFIED:
- `docs/MIGRATION_STATUS.md`

FILES MOVED/REMOVED:
- None

DEPENDENCIES:
- None

MIGRATIONS:
- None created.
- None applied.

DATABASE CHANGES:
- None.
- No `db push`, `db reset`, migration up, seed, or other write to the remote project.
- Analysis used only the local dump file `supabase_remote_schema.sql`.

REMOTE INVENTORY (summary):
- Public tables in dump: `users`, `horses`, `bookings`.
- Function: `handle_new_user()` (trigger attachment not in dump).
- RLS enabled on all three tables; eight policies.
- `owner_id` / `rider_id` FK to `public.users`, which FK to `auth.users`.
- No views, enums, extra indexes, or triggers in the dump.
- Storage, Auth config, and non-public schemas: **UNVERIFIED** (see inventory).

TESTS/CHECKS:
- Read-only document comparison against `docs/CURRENT_ARCHITECTURE_REPORT.md` and frozen `docs/DATA_ARCHITECTURE.md`.
- No TypeScript/Expo rerun required (no application code changes).

KNOWN ISSUES/WARNINGS:
- `public.users` + mutually exclusive `role` is not in the Phase 0 client report and collides with frozen person/account separation.
- `bookings` has no interval, no calendar exclusion, Spanish statuses, and CASCADE deletes.
- `persons.date_of_birth` / names cannot be backfilled from this schema without a Product Owner rule.
- Trigger on `auth.users` for `handle_new_user` is not present in the dump.
- Dump does not cover Storage (`horse-images` is client-only evidence).

MANUAL STEPS:
- Product Owner: review `docs/REMOTE_DATABASE_INVENTORY.md` classifications, especially UNKNOWN columns (`galope_level`, Stripe/tax/KYC, pricing, discipline, DOB backfill).
- Do not apply migrations until Phase 2B is authorized.

NEXT PHASE:
- Phase 2B (identity/policies **implementation**) is **not** started and is **not** authorized by this inventory.
- Migration Plan Phase 2 still means: create `supabase/migrations` and 001–004 only when explicitly authorized.
- Do not create centers/equines/bookings tables yet.
- Do not drop or rename live `users` / `horses` / `bookings`.

---

## Prior phase (unchanged work)

PHASE: 1 — Technical Foundation  
STATUS: COMPLETE — PENDING PRODUCT OWNER REVIEW  
DATE: 2026-08-29

See git history and the Phase 1 report for file lists, TypeScript/env/auth work, and checks. Phase 1 made no database changes.
