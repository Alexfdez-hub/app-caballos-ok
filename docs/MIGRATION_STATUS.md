# MIGRATION STATUS

PHASE: 5B — Qualifications foundation
STATUS: IMPLEMENTADO — stacked PR against `main`; 015 NOT deployed
DATE: 2026-09-02

## Current baseline (verified 2026-09-02)

PRs #11–#14 are merged into `main`. `origin/main` HEAD is
`6f916e7abb6834349cffef173bf307e51131123c` (merge of PR #14).
Migrations `001`–`014` exist on `main`. Migration `015` did not exist
and was not previously started.

Product Owner states remote project `efkauegdlmfkonzwyyiv` is aligned
through `014`. Remote schema/RLS verification passed. Android/Expo Go
smoke PASS. This agent does not deploy and does not modify remote.
Do not rewrite `001`–`014`.

Historical note: Phase 5A `MIGRATION_STATUS.md` / `MIGRATION_PLAN.md` /
`CURRENT_ARCHITECTURE_REPORT.md` / `PHASE_5A_DISCIPLINES_REPORT.md`
described `011`–`014` as stacked and not deployed. Those statements were
true at Phase 5A branch time. They are historical. Current state is the
merge of #11–#14 and remote alignment through `014`.

Phase 5B is a new branch from that SHA. Do not merge this PR. Do not
deploy `015`.

## Files created

- `supabase/migrations/015_qualifications.sql`
- `supabase/tests/015_qualifications_test.sql`
- `scripts/run-qualifications-sql-tests.cjs`
- `docs/PHASE_5B_QUALIFICATIONS_REPORT.md`

## Files modified

- `package.json` (`test:qualifications` appended to `test:sql`)
- `supabase/tests/008_rider_profiles_test.sql` (allow 015 tables; still forbid assessments)
- `supabase/tests/012_equine_ownership_management_test.sql` (allow 015; still forbid assessments/bookings)
- `supabase/tests/013_equine_center_relations_test.sql` (same)
- `supabase/tests/014_disciplines_test.sql` (allow 015; still forbid assessments/bookings)
- `docs/MIGRATION_STATUS.md`
- `docs/CURRENT_ARCHITECTURE_REPORT.md`
- `docs/MIGRATION_PLAN.md`

Inherited migrations `001`–`014` are unchanged versus `main`
`6f916e7abb6834349cffef173bf307e51131123c`.

## Lifecycle

Rider `verification_status` is frozen exactly as
`DECLARED | PENDING | VERIFIED | REJECTED | EXPIRED`.
System/level `status` reuses Product Owner-approved catalog
`ACTIVE | INACTIVE` (2026-09-02). `now()` is not used in a table CHECK.
`level_order` is a non-negative ordering hint; duplicates are allowed.

## Security

RLS on all three tables, no client policies, no catalog/list/declare/verify
RPC. No seed. A rider cannot mark their own qualification `VERIFIED`.
`verified_by_person_id` does not imply Center authority.

## Next phase

`016_rider_assessments` on `refactor/phase-6a-rider-assessments`,
stacked on this branch. Do not merge. Do not deploy. Do not start 019.
