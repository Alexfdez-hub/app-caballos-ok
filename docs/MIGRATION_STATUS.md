# MIGRATION STATUS

PHASE: 14A — Storage security
STATUS: IMPLEMENTADO — stacked PR against live main; 027 NOT deployed
DATE: 2026-09-03

Parent is live `main` `9d58d3605a931fd930520238276215cf17a51a38`
(merge of PR #28). PRs #25–#28 are merged. Migrations `001`–`026`
exist on `main`. Product Owner states remote project
`efkauegdlmfkonzwyyiv` is aligned through exact version `026`. Do not
merge this PR. Do not deploy 027. Do not start 028 until this Quality
Gate is green.

Historical reports that described `023`–`026` as stacked/not deployed
were true at those branch times; they are not rewritten.

## Files created

- `supabase/migrations/027_storage_policies.sql`
- `supabase/tests/027_storage_policies_test.sql`
- `scripts/run-storage-sql-tests.cjs`
- `docs/PHASE_14A_STORAGE_SECURITY_REPORT.md`
- `docs/ARCHITECTURE_CONFLICT_027_STORAGE_VISIBILITY.md`

## Files modified

- `package.json`
- `supabase/tests/011_equines_test.sql` (allow a later private
  `equine-media` bucket; still forbid objects and client policies)
- `docs/MIGRATION_STATUS.md`
- `docs/CURRENT_ARCHITECTURE_REPORT.md`
- `docs/MIGRATION_PLAN.md`

Inherited migrations `001`–`026` are unchanged versus live `main`.

## Next phase

`028` `approve_zero_session` starts only after this PR is Ready and
the complete Quality Gate is green. Do not merge. Do not deploy.
