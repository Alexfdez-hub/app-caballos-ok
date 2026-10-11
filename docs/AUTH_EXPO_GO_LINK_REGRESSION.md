# Expo Go auth link regression

This note records the 11 October 2026 diagnosis and the client fix. It does
not change remote Supabase. The manual email-template step is separate and
has not been applied.

## Confirmed cause

Remote Auth logs for that day showed `POST /recover` returning 200 with
`mail.send` `mail_type=recovery`, then two `GET /verify` calls in the same
second: one `303` and one `403` with “Email link is invalid or has expired”.
Creating an account produced four consecutive `POST /signup` calls.

The app does not call `GET /verify`. `createSessionFromUrl` only exchanges a
PKCE code (`POST /token`), stores implicit tokens, or, after this fix, calls
`verifyOtp` (`POST /verify`). The duplicate `GET /verify` pair is therefore
not produced by the callback handler. It matches a one-time confirmation URL
being opened twice before the app runs. The mail client or a link scanner is
a sufficient explanation. This note does not claim the app issued those GETs.

The four signup requests are an app race. `AuthScreen` set `isSubmitting`
and then awaited the request. React applies that state on a later render, so
further presses still called `signUp` until the button was replaced.
“Crear cuenta” was a second action on the same screen, not its own mode.

`AuthProvider` handled `Linking.getInitialURL` and the `url` listener
independently. The same callback could be exchanged twice. That would be a
`POST /token` or `setSession`, not the observed `GET /verify`.

A recovery callback can arrive as `?code=` without `type`. `@supabase/auth-js`
emits `PASSWORD_RECOVERY` only when the PKCE verifier stored in that app
session was saved with redirect type `recovery`. The URL type stays null.
Guessing recovery from a bare code would also catch signup confirmation, so
the client uses the URL type first and the stored redirect type only when the
URL type is absent.

Opening the link in a different Expo Go process, or after the Metro host or
port changes, still fails for the current `{{ .ConfirmationURL }}` emails:

- the redirect baked into the message is the `exp://` host from the session
  that requested it;
- a PKCE exchange needs the verifier stored in that same app storage;
- Expo Go can show its own connection failure when the old tunnel is gone.
  That screen is outside this app. Inside the app, a callback now stays on
  “Procesando enlace…” or on a recoverable error with “Volver al acceso”.

PR #40 remains the redirect rule: Expo Go uses
`makeRedirectUri({ path: 'auth/callback' })`, which is covered by
`exp://**/--/auth/callback`. The allow-list does not add `exp://**`.

## Client behavior after this fix

- `signIn`, `signUp`, `resend`, and `recover` each take a synchronous
  in-flight lock. One press sends one request. A later press works after the
  first request finishes.
- The same code, token hash, access token, or error URL is claimed once
  until the JavaScript runtime restarts. A fresh Expo Go load can claim it
  again. `getInitialURL` and the linking listener no longer both exchange it.
- If one callback in that runtime already succeeded, a later different error
  URL does not replace it. An error alone still shows the error screen.
- “Iniciar sesión” and “Crear cuenta” are separate modes. Repeated signup of
  an existing address still uses the neutral copy and does not say that a
  new account was created.
- `token_hash` plus `type=recovery` calls `verifyOtp` and opens Nueva
  contraseña. `type=email` or `type=signup` confirms the account and does not
  open Nueva contraseña.

## Manual Dashboard operation — not done here

Do not change remote Auth, do not run `supabase config push`, and do not edit
migrations while applying this. After review, a person can edit the hosted
templates in Authentication → Emails → Templates. Send a new message
afterwards. Messages already sent still use the old one-time `/verify` URL.

Keep a single link. Do not leave `{{ .ConfirmationURL }}` in these two
templates: that URL is `GET /auth/v1/verify` and is consumed by the first
request. Do not point the link at `{{ .SiteURL }}/auth/confirm`; this app has
no server confirm route. `{{ .RedirectTo }}` is the allow-listed callback the
app already passes (`exp://<current-host>/--/auth/callback` in Expo Go).

Confirm signup:

```html
<h2>Confirm your signup</h2>
<p>Follow this link to confirm your email address.</p>
<p><a href="{{ .RedirectTo }}?token_hash={{ .TokenHash }}&type=email">Confirm your email</a></p>
```

Reset password:

```html
<h2>Reset password</h2>
<p>Follow this link to choose a new password.</p>
<p><a href="{{ .RedirectTo }}?token_hash={{ .TokenHash }}&type=recovery">Reset password</a></p>
```

`type=email` is the signup-confirmation type in the current Supabase
password guide. `type=recovery` is the reset type. The app treats those as
different intents.

Prefetch of the `exp://` link does not call Supabase. The app verifies with
`verifyOtp` only after the link opens. That does not require the PKCE
verifier, so a reopened Expo Go session can still verify it when the tunnel
host in the message is the one Expo Go loads. If the tunnel host or port
changed after the message was sent, request a new message from the current
session. The Redirect URL list stays:

```text
app-caballos-ok://auth/callback
app-caballos-ok:///auth/callback
http://localhost:8081/auth/callback
http://127.0.0.1:8081/auth/callback
exp://**/--/auth/callback
```

Do not add `exp://**`.

## Uncertainty

The logs show the duplicate verify calls and the recovery mail type. They do
not identify which process issued the second `GET /verify`. The app code path
cannot emit that request. Whether it was the mail client, a scanner, or two
opens of the same message is not proven here.
