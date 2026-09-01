# MIGRATION STATUS

PHASE: 3A — Identity Integration
STATUS: INCOMPLETE — FRONTEND READY; REMOTE EMAIL E2E BLOCKED BY TEST SMTP
DATE: 2026-08-29

Phase 3A application and database work is implemented. No new migration is
needed. The phase is **not COMPLETE** until a production SMTP/Resend sender
can deliver confirmation and recovery emails and one Expo Go deep-link test
succeeds.

## Approved starting state

- Phase 2C merged.
- Architecture 2.1 tables from migrations 001–004 remain in place.
- Migration `005_legacy_retirement.sql` retires the prototype trigger,
  `handle_new_user()`, `public.bookings`, `public.horses`, and `public.users`.
- Product decision: the original prototype is not a compatibility target.

## Files created

- `supabase/migrations/006_identity_integration.sql`
- `supabase/tests/006_identity_integration_test.sql`
- `supabase/tests/local_auth_stub.sql`
- `src/app/navigation/types.ts`
- `src/features/auth/` (service, errors, callback parsing, links, context)
- `src/features/identity/` (types, validation, service, context, provider, hook, date field)
- `src/screens/AuthScreen.tsx`
- `src/screens/ForgotPasswordScreen.tsx`
- `src/screens/UpdatePasswordScreen.tsx`
- `src/screens/AuthLinkErrorScreen.tsx`
- `src/screens/IdentityOnboardingScreen.tsx`
- `src/screens/IdentityErrorScreen.tsx`
- `src/screens/EditIdentityScreen.tsx`
- `src/screens/HomeScreen.tsx`
- `src/screens/ExploreScreen.tsx`
- `src/screens/ActivityScreen.tsx`
- `src/screens/EquestrianPassportScreen.tsx`
- `src/screens/ProfileScreen.tsx`
- `src/app/navigation/AuthenticatedTabs.tsx`
- `src/app/ui/` (`ScreenScaffold`, `ScreenHeader`, `SectionCard`, `EmptyStateCard`, `MenuRow`, `theme`)
- `docs/PHASE_3A_IDENTITY_INTEGRATION_REPORT.md`

## Files modified

- `App.tsx`
- `src/app/navigation/RootNavigator.tsx`
- `src/config/env.ts`
- `.env.example`
- `.env.supabase.local.example`
- `.env.supabase.remote.example`
- `package.json`
- `.gitignore`
- `supabase/config.toml` (local redirect allow-list only; SMTP remains commented)
- `docs/CURRENT_ARCHITECTURE_REPORT.md`
- `docs/MIGRATION_PLAN.md`
- `docs/MIGRATION_STATUS.md`

## Files removed

- `src/screens/BaselineScreen.tsx`
- `src/screens/AuthenticatedHomeScreen.tsx`

## Migration created

`006_identity_integration.sql` adds Auth → account → person provisioning and
server-authoritative identity completion on top of the existing 003 tables:

- trigger `on_auth_user_identity_created` on `auth.users`;
- `handle_new_identity_account()`;
- `ensure_my_identity()`;
- `complete_my_identity(text, text, date)`.

No new identity tables. No `role` column. No `onboarding_complete` flag.
No recreation of `public.users`.

## Application state

- Unauthenticated users see email/password sign-in and sign-up, pending
  confirmation with resend, and forgot-password.
- Invalid, expired, or Auth-error deep links show `AuthLinkErrorScreen`.
- `PASSWORD_RECOVERY` opens `UpdatePasswordScreen`.
- Known Auth connectivity failures show a UI message and do not LogBox.
- Authenticated users with incomplete person fields see identity onboarding.
- Authenticated users with first name, last name, and date of birth enter a
  single application shell with five tabs: Inicio, Explorar, Actividad,
  Pasaporte, and Perfil. Domain screens are empty states / coming soon.
  Basic identity editing and sign-out live under Perfil. Incomplete identity
  cannot reach the shell.
- `AuthProvider` remains session-only, plus recovery and callback-error state.
- Identity state lives in `IdentityProvider` / `identityService`.
- Navigation is selected from session + identity completeness.

Usual development: `npm run start:local` (also `npm start`). Remote /
physical Android checkpoint: `npm run start:remote`. A physical Android
device cannot reach `127.0.0.1` on the PC without extra network setup.
Real credentials stay in gitignored `.env.supabase.local` and
`.env.supabase.remote`; tracked examples are placeholders only.

## Local database validation

- Migrations 001–006 are applied on local Supabase.
- `npx supabase start` works normally.
- Clean local migration chain 001→006: passed.
- SQL identity/RLS/provisioning tests: `npm run test:identity` (no psql `\set`).
- End-to-end app flow against local Auth + Postgres: passed (local
  autoconfirm is on).

## Application checks

- `npm run typecheck`
- `npx expo-doctor`
- `git diff --check`
- `npm run test:auth` (callback + network error handling)
- `npm run check:env`

## Remote Android / Expo Go checkpoint

- Android/Expo Go **connects** to remote Supabase after the placeholder URL
  fix.
- Remote **signup works**. A 200 without session is expected while email
  confirmation is enabled.
- Remote **login `invalid_credentials`** on the test account was
  `user_repeated_signup`: the email already existed; the new password was
  not the existing account’s password.
- Remote **email confirmation is enabled**. Do not disable it.
- Remote **password reset reaches Auth**. The 500 is external: Resend/SMTP
  is still in test mode and cannot send to arbitrary recipients. This is
  not a client network failure.
- Pre-006 Auth users may lack `persons` / `user_accounts`.
  `ensure_my_identity()` covers that catch-up. No new migration.

## Known issues / unresolved risks

- Password reset and confirmation **email delivery** remain blocked by
  the remote test SMTP/Resend restriction. Frontend is ready.
- Expo Go confirmation/recovery deep-link E2E is still unproven until a
  real email arrives.
- Person name and date-of-birth columns remain nullable at the table level.
- npm reports 16 existing audit findings (7 moderate, 9 high).

## Remote database

- Migration 006 **is applied** to the linked remote project.
- Local and remote schemas are synchronized through 001–006.
- Schema sync is not the same as phase completion. Email delivery and
  deep-link redirects remain open.

## Architecture conflicts

- None. The continued nullability of required person fields is the documented
  Phase 2B transitional deviation, now also required for incomplete onboarding
  and future persons without accounts.

## Application shell

Frontend-only navigation skeleton on top of Phase 3A. No SQL. No migration
007. `AuthenticatedHomeScreen` was replaced by `HomeScreen` plus the tab
shell. `@react-navigation/bottom-tabs` and `@expo/vector-icons` were added
because Expo already ships vector icons and bottom tabs are required for
the authenticated product chrome.

## Next phase

- Phase 3B / guardians is planned as `007_guardians.sql`.
- Phase 3B must **not** start until Phase 3A is actually complete (SMTP +
  redirect/deep-link E2E), not merely because migration 006 is applied.
