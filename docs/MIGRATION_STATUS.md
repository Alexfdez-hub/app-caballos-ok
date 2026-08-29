# MIGRATION STATUS

PHASE: 2C — Clean Baseline / Legacy Retirement
STATUS: COMPLETE — PENDING PRODUCT OWNER REVIEW AND REMOTE DEPLOYMENT
DATE: 2026-08-29

## Approved starting state

- Phase 2A/2B merged and deployed.
- Remote migration history synchronized through `004_policies.sql`.
- Architecture 2.1 tables from migrations 001–004 post-deployment verified.
- Product decision: prototype compatibility and data retention are no longer
  requirements.

## Files created

- `supabase/migrations/005_legacy_retirement.sql`
- `src/screens/BaselineScreen.tsx`
- `docs/PHASE_2C_CLEAN_BASELINE_REPORT.md`

## Files modified

- `AI_INSTRUCTIONS.md`
- `app.json`
- `package.json`
- `package-lock.json`
- `src/app/navigation/RootNavigator.tsx`
- `docs/DATA_ARCHITECTURE.md` (migration numbering only)
- `docs/MIGRATION_PLAN.md`
- `docs/CURRENT_ARCHITECTURE_REPORT.md`
- `docs/MIGRATION_STATUS.md`

## Files removed

- `src/screens/BookingsScreen.js`
- `src/screens/HomeScreen.js`
- `src/screens/HorseDetailScreen.js`
- `src/screens/LoginScreen.js`
- `src/screens/OwnerEditHorseScreen.js`
- `src/screens/OwnerHorsesScreen.js`
- `src/screens/OwnerRegisterHorseScreen.js`
- `src/screens/ProfileScreen.js`
- `src/screens/SearchScreen.js`
- `ESTRUCTURA.md`
- root duplicate `CURRENT_ARCHITECTURE_REPORT.md`

## Dependencies removed

- `@react-native-community/datetimepicker`
- `@react-navigation/bottom-tabs`
- `expo-image-picker`

The datetime-picker Expo plugin was removed from `app.json`.

## Migration created

`005_legacy_retirement.sql` removes, without `CASCADE`:

1. `auth.users.on_auth_user_created`
2. `public.handle_new_user()`
3. `public.bookings`
4. `public.horses`
5. `public.users`

Dependency analysis found only the known legacy trigger and FK chain. No
Architecture 2.1 table from migrations 001–004 references a legacy table.
`auth.users` is not dropped or modified.

## Application state

- Legacy horse, booking, owner, profile, login, and registration paths removed.
- Sole route is the TypeScript `BaselineScreen`.
- Supabase client, AuthProvider, persisted session restoration, navigation, and
  sign-out plumbing retained.
- No new registration, identity provisioning, onboarding, or product domain
  flow implemented.
- Production source has no direct dependency on retired tables or role values.

## Local database validation

- Clean local migration chain 001→005: passed.
- Same clean chain repeated in a second fresh local container: passed.
- Reconstructed legacy schema + verified trigger + 001→005: passed.
- Legacy trigger/function/tables absent after 005: verified.
- `auth.users` remains: verified.
- `markets`, `persons`, `user_accounts`, `policy_documents`, and
  `policy_acceptances` remain: verified.
- 16 Architecture 2.1 constraints remain: verified.
- RLS remains enabled on all five Architecture 2.1 tables: verified.

Execution used disposable local Supabase PostgreSQL 17.6 containers. No linked
remote command or connection was used.

## Application checks

- `npm run typecheck` — passed.
- `npx expo-doctor` — passed 18/18.
- `npx expo config --type public` — passed.
- Expo web server — reached ready state.
- Browser smoke test — clean shell rendered.
- Production-source legacy reference search — zero matches.
- `git diff --check` — passed after documentation whitespace correction.

## Known issues / unresolved risks

- Prototype data is intentionally discarded when migration 005 is deployed.
- The unverified `horse-images` Storage bucket is not changed by this migration;
  no production app path references it.
- Remote legacy objects remain until separately authorized deployment.
- The ignored root `.env` UTF-8 BOM still prevents normal `supabase start`;
  local database testing used direct containers.
- npm reports 16 existing audit findings (7 moderate, 9 high).

## Remote database

- **NOT MODIFIED during Phase 2C implementation/testing.**
- No remote push, reset, repair, seed, migration apply, or SQL.

## Architecture conflicts

- None.

## Next phase

- Phase 3A Identity Integration is planned as migration
  `006_identity_integration.sql`.
- Guardians move to `007_guardians.sql`.
- Phase 3A was **not started** and requires separate authorization.
