# Phase 3A — Identity integration report

**Project:** app-caballos-ok
**Phase:** 3A — Identity integration
**Date:** 2026-08-29
**Architecture:** Data Architecture 2.1
**Local and remote migrations:** 001–006 applied and synchronized
**Phase status:** INCOMPLETE — frontend ready; remote email E2E blocked by test SMTP
**Phase 3B / guardians:** not started
**New migration:** none. 006 remains unchanged.

Code for identity + Auth UX is implemented. Android/Expo Go reaches remote
Auth. The phase stays **INCOMPLETE** until Resend/SMTP can send to real
inboxes and one Expo Go confirmation/recovery deep-link test succeeds.

## Objective

Implement the first functional Architecture 2.1 identity flow:

- create a Supabase Auth account;
- create or link the corresponding `persons` and `user_accounts` rows;
- restore an authenticated session;
- detect whether the authenticated account has completed its basic identity;
- complete first name, last name, and date of birth;
- sign out;
- show navigation from authentication and onboarding state.

This phase does not implement rider, owner, center, or guardian business flows.

## Files created

- `supabase/migrations/006_identity_integration.sql`
- `supabase/tests/006_identity_integration_test.sql`
- `supabase/tests/local_auth_stub.sql`
- `src/app/navigation/types.ts`
- `src/features/auth/authService.ts`
- `src/features/auth/authErrors.ts`
- `src/features/auth/authCallback.ts`
- `src/features/auth/authLinks.ts`
- `src/features/auth/signUpOutcome.ts`
- `src/features/identity/types.ts`
- `src/features/identity/validation.ts`
- `src/features/identity/identityService.ts`
- `src/features/identity/IdentityContext.ts`
- `src/features/identity/IdentityProvider.tsx`
- `src/features/identity/useIdentity.ts`
- `src/features/identity/DateOfBirthField.tsx`
- `src/screens/AuthScreen.tsx`
- `src/screens/ForgotPasswordScreen.tsx`
- `src/screens/UpdatePasswordScreen.tsx`
- `src/screens/AuthLinkErrorScreen.tsx`
- `src/screens/IdentityOnboardingScreen.tsx`
- `src/screens/IdentityErrorScreen.tsx`
- `src/screens/AuthenticatedHomeScreen.tsx`
- `src/screens/EditIdentityScreen.tsx`
- `.env.supabase.local.example`
- `.env.supabase.remote.example`
- `docs/PHASE_3A_IDENTITY_INTEGRATION_REPORT.md`

## Files modified

- `App.tsx`
- `package.json`
- `.gitignore`
- `src/app/navigation/RootNavigator.tsx`
- `src/app/providers/AuthProvider.tsx`
- `src/config/env.ts`
- `.env.example`
- `supabase/config.toml` (local Auth redirect allow-list; SMTP still commented)
- `docs/MIGRATION_STATUS.md`
- `docs/CURRENT_ARCHITECTURE_REPORT.md`
- `docs/MIGRATION_PLAN.md`

## Files removed

- `src/screens/BaselineScreen.tsx`

## Database changes

Migration `006_identity_integration.sql` reuses the Phase 2B tables. It does
not recreate `persons` or `user_accounts`, add a `role` column, or restore
`public.users`.

Added:

- `public.handle_new_identity_account()` — `SECURITY DEFINER`, explicit
  `search_path = pg_catalog, public`, not executable by `anon` or
  `authenticated`.
- trigger `auth.users.on_auth_user_identity_created` — after insert, distinct
  from the retired legacy `on_auth_user_created`.
- `public.ensure_my_identity()` — authenticated RPC that resolves or creates
  the caller’s `user_accounts` → `persons` link from `auth.uid()`.
- `public.complete_my_identity(first_name, last_name, date_of_birth)` —
  authenticated RPC that updates only the caller’s person.

Provisioning inserts an empty `persons` row. It does not fabricate
`first_name`, `last_name`, or `date_of_birth`. Completeness is derived from
those fields; there is no `onboarding_complete` boolean.

`first_name`, `last_name`, and `date_of_birth` remain nullable. That continues
the documented Phase 2B transitional deviation so:

- a new Auth account can exist before the person supplies real identity data;
- a person can exist without a `user_accounts` row (required later for minors).

Age is not stored.

## Auth integration design

`auth.users` remains the credential store. The new trigger uses `NEW.id` only.
It does not read Auth metadata.

Invariant after a normal signup that reaches `auth.users`:

```text
auth.users
  -> user_accounts
    -> persons
```

Every normal application account resolves to one person. A person may exist
without an account.

`ensure_my_identity()` is the catch-up path for an Auth user whose linkage is
missing (for example an account created before the trigger existed). Both the
trigger and the RPC are idempotent for the same `auth.uid()` / `NEW.id`.

The Expo client:

- signs up and signs in with email/password through `authService`;
- treats signup-with-session and signup-without-session as different outcomes;
- does not report an authentication error when signup succeeds but email
  confirmation is required;
- shows pending confirmation + resend, and maps resend/rate-limit errors to UI
  copy without LogBox;
- restores the session through `AuthProvider`;
- handles `PASSWORD_RECOVERY` by opening the new-password screen;
- shows `AuthLinkErrorScreen` when a callback/deep link is invalid, expired,
  or Auth returns an error;
- never sends a client-chosen `person_id` or `auth_user_id`.

Known connectivity failures (`AuthRetryableFetchError`, `status=0`,
`Network request failed`) show a UI message and are not logged with
`console.error`. Unexpected 5xx / unknown failures still log.

Local signup initially failed with the generic UI message because
`EXPO_PUBLIC_SUPABASE_ANON_KEY` in the ignored local environment file was
not a valid local Auth anon/publishable key. The URL already pointed at
local Supabase. Correcting that local key (not a schema change) unblocked
signup. No key, token, or secret is recorded in this report.

Local and remote credentials now live in separate gitignored files
(`.env.supabase.local` and `.env.supabase.remote`). Tracked examples contain
placeholders only. Start scripts copy the chosen file to gitignored
`.env.local` so Expo inlines the public variables into web and Expo Go.

## Redirect URIs generated by the app

`getAuthRedirectUrl()` calls `makeRedirectUri({ scheme: 'app-caballos-ok',
path: 'auth/callback', native: 'app-caballos-ok://auth/callback' })`.

Exact values produced in the current environments:

| Environment | URI |
| --- | --- |
| Native build / dev client (`scheme` `app-caballos-ok`) | `app-caballos-ok://auth/callback` |
| Same scheme, Expo `createURL` default (triple slash) | `app-caballos-ok:///auth/callback` |
| Expo web on Metro 8081 | `http://localhost:8081/auth/callback` and `http://127.0.0.1:8081/auth/callback` |
| Expo Go | `exp://<LAN-IP-or-localhost>:<metro-port>/--/auth/callback` (IP and port vary) |

Minimal remote **Redirect URLs** allow-list (Authentication → URL Configuration):

```text
app-caballos-ok://auth/callback
app-caballos-ok:///auth/callback
http://localhost:8081/auth/callback
http://127.0.0.1:8081/auth/callback
exp://**/--/auth/callback
```

Recommended **Site URL** for this mobile-first app (replaces the default
`http://localhost:3000` fallback that ignored `redirectTo` when the URI was
not allow-listed):

```text
app-caballos-ok://auth/callback
```

Do **not** add `exp://**`. The path-constrained `exp://**/--/auth/callback`
is the narrowest pattern that still covers changing LAN IPs and Metro ports.

If Metro is not on 8081, the Expo Go wildcard still matches; add the exact
web origin only if you use a different web port.

Local `supabase/config.toml` `additional_redirect_urls` mirrors that list.
Applying it locally requires restarting local Supabase. It does **not**
change remote Auth. Do not `supabase config push` the whole file: local
`enable_confirmations = false` would disable remote email confirmation.

## SMTP

Nothing in the Expo client can send mail. Confirmation stays **on** remotely
(`mailer_autoconfirm` must remain false).

Prepared without a provider:

- client already sends `emailRedirectTo` / `redirectTo` from `getAuthRedirectUrl()`;
- local Inbucket (`[local_smtp]`) captures local mail;
- `config.toml` documents the custom SMTP field names and remains commented.

Not prepared (needs a human + provider):

| Dashboard field | What to enter |
| --- | --- |
| Host | SMTP hostname from the provider |
| Port | `587` (STARTTLS) or `465` (SSL), as the provider specifies |
| Username | SMTP username (often `apikey` for API-based providers) |
| Password | SMTP password or API key |
| Sender email | From-address the provider authorizes |
| Sender name | `App Caballos` (or the product name you want in the inbox) |

Do not invent credentials. Do not put SMTP secrets in `.env.local`.

Built-in Supabase mail is not a real remote flow (rate limit ~2/hour, often
restricted to team addresses).

## RLS / security design

Migration 003 already enabled RLS and revoked all table privileges from
`anon` and `authenticated`. Migration 006 does not add table grants or client
RLS policies.

Authorized identity reads and writes use `SECURITY DEFINER` RPCs that derive
the target exclusively from `auth.uid()`. Direct table `SELECT` /
`INSERT` / `UPDATE` / `DELETE` remain unavailable to clients.

This is stricter than own-row `SELECT` policies and matches the phase
preference for server-authoritative mutation. The client cannot:

- read an unrelated person;
- update another person;
- create or relink `user_accounts`;
- execute the provisioning trigger function.

`anon` cannot execute the identity RPCs or read identity tables.

No `service_role` credential is present in the application.

## Frontend state flow

```text
index.js
  -> App.tsx
     -> AuthProvider            (session, recovery, callback errors)
        -> IdentityProvider     (Architecture 2.1 person/account)
           -> RootNavigator
              A. restoring session / loading identity
              B. callback/deep-link error -> AuthLinkErrorScreen
              C. PASSWORD_RECOVERY -> UpdatePasswordScreen
              D. no session -> AuthScreen / ForgotPassword
              E. identity load error -> IdentityErrorScreen
              F. session + incomplete identity -> IdentityOnboardingScreen
              G. session + complete identity -> AuthenticatedHomeScreen
                 (optional EditIdentityScreen)
```

Navigation stacks are selected from state. The authenticated home route is
not mounted until identity is complete, so onboarding cannot be skipped by
choosing a route.

Identity loading, completeness, and profile completion live in
`features/identity`.

## Date of birth

Onboarding and edit identity use a native date control
(`DateOfBirthField`: Android/iOS picker, web `input type="date"`). The stored
value remains `YYYY-MM-DD`. This is a small control substitution, not a
redesign.

## Development commands

Usual local development (web or emulator on the same machine as Supabase):

```text
npm run start:local
```

`npm start` is an alias of `start:local`.

Remote Supabase, including a physical Android checkpoint:

```text
npm run start:remote
```

A physical Android device cannot reach `127.0.0.1` on the development PC
without extra network setup. Use `start:remote` for that checkpoint.

Copy the matching `*.example` file to the gitignored name and fill in the
anon or publishable key. Never use `service_role` or secret keys in the
client.

## Tests performed

### Database

Migrations 001–006 are applied on local **and** remote Supabase.

`npm run test:identity` runs `supabase/tests/006_identity_integration_test.sql`
via local `psql` (docker exec into the Supabase database container).
`npx supabase db query` cannot execute a multi-statement transactional file.
The test has no psql `\set` commands and is scoped to fixture Auth user ids so
it can run on a local database that already has other users.

Those tests verify:

- one `user_accounts` row and one linked `persons` row per inserted Auth user;
- no fabricated name/date-of-birth on provisioning;
- a person can exist without an account;
- no duplicate linkage after repeated `ensure_my_identity()` calls;
- completeness derived from required fields;
- `complete_my_identity` trims names, rejects a future date of birth, and
  updates only the caller’s person;
- `authenticated` cannot `SELECT`/`INSERT`/`UPDATE` identity tables directly;
- `authenticated` cannot create or relink `user_accounts`;
- `authenticated` cannot resolve another person’s identity through the RPC;
- `anon` cannot execute identity RPCs or read identity tables;
- catch-up provisioning recreates a missing account/person link;
- the legacy `on_auth_user_created` trigger was not recreated.

### Auth unit tests

`npm run test:auth` covers:

- network / `AuthRetryableFetchError` / `status=0` → UI copy, no `console.error`;
- unexpected 5xx still logged;
- invalid/expired callback URLs → error, not ignored;
- `type=recovery` preserved for token callbacks;
- signup classification (session / pending / existing email);
- date-of-birth validation.

### Application E2E against local Supabase

End-to-end against running local Auth + Postgres (autoconfirm on):

- signup creates an Auth user and a session;
- the identity trigger links `user_accounts` → `persons` without fabricating
  personal data;
- incomplete identity opens onboarding;
- completing first name, last name, and date of birth opens authenticated
  Home;
- sign-out returns to Auth;
- a later sign-in of the same account goes to Home and does not repeat
  onboarding.

### Remote Android / Expo Go checkpoint

- Android/Expo Go **connects** to remote Supabase. The earlier
  `Network request failed` from a placeholder host is resolved.
- Remote **signup works**. With confirmation enabled, a successful signup
  returns a user and **no session**. The app does not auto-login and tells
  the user to confirm email. A repeated signup on an existing email is
  `user_repeated_signup` / `identities: []`, not a new ready account.
- Remote **login `invalid_credentials` (400)** on the test account was that
  repeated-signup case: the email already existed; the password typed at
  signup was not the existing password.
- Email confirmation **remains enabled**.
- `resetPasswordForEmail` **reaches** remote Auth. The failure is HTTP 500
  `Error sending recovery email` because Resend/SMTP is still in test mode
  and cannot send to arbitrary recipients. The UI treats that as “could not
  send email”, not as a connection problem.
- Pre-006 users may lack `persons` / `user_accounts`.
  `ensure_my_identity()` is the catch-up path. **No new migration.**
- Password-recovery UI after a valid deep link (`UpdatePasswordScreen`) is
  implemented. Delivery of that email is the remaining external blocker.

### Application checks

- `npm run typecheck`
- `npx expo-doctor`
- `git diff --check`
- `npm run check:env`

## Remote database

Migration 006 was applied to the linked remote Supabase project. Local and
remote are synchronized through 001–006.

Schema sync does **not** make Phase 3A complete.

## Results

Phase 3A identity integration works end-to-end on local Supabase. Migrations
001–006 are applied locally and remotely. Remote Android connects and signup
works. Login of an already-existing test email returns `invalid_credentials`
when the password is not the original one. Password reset is blocked
externally by test-mode SMTP/Resend. No new migration was added.

## Known limitations

- Remote Resend/SMTP is still in test mode. Keep Confirm email enabled.
- Redirect allow-list must match the URIs above before Expo Go email links
  will open the app instead of falling back to Site URL.
- `persons.first_name`, `last_name`, and `date_of_birth` remain nullable at
  the table level. Completeness is enforced by RPC and UI, not by a table
  `NOT NULL` constraint, so future persons without accounts are not blocked.
- Identity table `SELECT` is not granted to the client. Own-identity reads
  go through `ensure_my_identity()`.
- npm reports the same pre-existing 16 audit findings (7 moderate, 9 high).
- Expo logs `Using src/app as the root directory for Expo Router`; the app
  still uses React Navigation, not Expo Router. This is pre-existing.

## Explicit confirmations

- Phase 3B was **not** started.
- `007_guardians.sql` was **not** created.
- Guardian relationships, guardian consents, rider/owner/center flows, equines,
  bookings, assessments, payments, and related domain tables were **not**
  implemented.
- Auth/RLS was **not** weakened.
- Migration 006 SQL was **not** changed.

## Next planned phase

`007_guardians.sql` — guardian relationships and consent. Do not start until
Phase 3A is actually complete.
