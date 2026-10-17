# Expo Go auth link regression

This note records the 11 October 2026 smoke and the client fixes on this
branch. It does not change remote Supabase. Do not edit the hosted email
templates from this work.

## Confirmed cause

Expo Go was running on an Android phone. The recovery message was opened on
a PC.

1. The PC followed the one-time `{{ .ConfirmationURL }}`.
2. Supabase accepted that request (`GET /verify` 303) and consumed the link.
3. Supabase then redirected to an `exp://…/--/auth/callback` URL that belongs
   to the phone’s Expo Go session and tunnel.
4. The PC does not have that phone’s Expo Go instance, its storage, or its
   PKCE verifier, so it cannot finish the callback. The PC shows an
   unhandled or black window.
5. A second request to the already consumed link matches the `403`
   “Email link is invalid or has expired” seen in the same second.

`POST /recover` had already returned 200 with `mail_type=recovery`. The app
does not call `GET /verify`. This was not a network failure inside the app.

Creating an account also produced four consecutive `POST /signup` calls.
That part is separate: `AuthScreen` set `isSubmitting` and then awaited the
request, so more presses ran before React replaced the button.

## What this incident is not

Prefetch, or opening the same message twice, can also consume a one-time
`/verify` link. That remains possible for other messages. It is not the
confirmed cause of this smoke. The confirmed cause is the PC opening a link
that only the Android Expo Go session can finish.

Releasing an in-flight callback claim after a network error, a 5xx response,
or a recoverable exception is a separate preventive fix. It lets the same
phone retry a link that Supabase has not consumed. It does not explain the
PC → phone smoke, and it does not make a link opened on a PC succeed on the
phone afterwards.

## Opening the link

During Expo Go, request a new message and open it for the first time on the
same Android phone that is running this project, with the same Metro tunnel
still active. Do not open or preview the link on a PC first.

Both of these still have to be opened on that phone:

- the current `{{ .ConfirmationURL }}`, which Supabase verifies and then
  redirects to `exp://`;
- a direct `{{ .RedirectTo }}?token_hash=…` link, because `RedirectTo` in
  Expo Go is itself an `exp://…/--/auth/callback` URL.

Changing the template avoids a prefetch of Supabase `/verify`. It does not
make a PC → phone flow work. The `exp://` URL still has to open in the Expo
Go session that is running on the phone. Do not apply remote template
changes for that reason.

If the product later needs someone to read the mail on a PC and finish on
the phone, that is a separate flow: show a one-time code in the message and
let the app collect the address and the code, then call `verifyOtp` with
`type=email` or `type=recovery`. Design and test that flow on its own. It
is not part of this branch.

A different Expo Go process, or a Metro host or port that changed after the
message was sent, still cannot use that message. Request a new one from the
current phone session. The allow-list stays path-constrained:

```text
app-caballos-ok://auth/callback
app-caballos-ok:///auth/callback
http://localhost:8081/auth/callback
http://127.0.0.1:8081/auth/callback
exp://**/--/auth/callback
```

Do not add `exp://**`. The parser accepts only those environments and only
the exact path `/auth/callback`, or `/--/auth/callback` for an `exp://` URL.
A URL that merely contains that text in another path, query, prefix, or
suffix is ignored.

## Client behavior on this branch

- `signIn`, `signUp`, `resend`, and `recover` share one synchronous
  in-flight lock. One press sends one request, including a rapid switch
  between Crear cuenta and Iniciar sesión.
- A callback is in-flight while it is exchanged, finalized after success or
  a definitive Auth error, and released after a network failure, a 5xx, or
  a recoverable exception. A duplicate delivery does not clear an error or
  recovery screen that is already showing.
- A released failure says the connection could not be completed and that the
  link can be opened again. A consumed, invalid, or expired token still says
  the link is not valid. Those are not the same message.
- “Iniciar sesión” and “Crear cuenta” are separate modes. Repeated signup of
  an existing address still uses the neutral copy.
- `token_hash` with `type=recovery` calls `verifyOtp` and opens Nueva
  contraseña when that callback actually reaches the phone.
  `type=email` or `type=signup` does not open Nueva contraseña.

## Android smoke, Expo Go SDK 54

Not run on a device in this note. Request every message from the phone and
open it there for the first time. Do not open it on a PC.

1. Start the current Metro session and open this project in Expo Go on the
   Android phone. Keep that tunnel active.
2. On **Iniciar sesión**, press several times quickly. One sign-in request.
3. Switch to **Crear cuenta** and, without waiting, switch back and press.
   Only the first operation is sent.
4. On **Crear cuenta**, press several times with an unused address. One
   `POST /signup`.
5. Request a new recovery message from the phone and press **Enviar enlace**
   several times. One `POST /recover`. On the same phone, open that message
   for the first time. **Procesando enlace…**, then **Nueva contraseña**.
6. As an extra check, not as the diagnosis of the PC incident: interrupt the
   network, open a new message once, restore the network, choose **Volver al
   acceso**, and open that same message again. The copy must offer a retry,
   not say the link expired, when the failure was only the connection.
7. Open a consumed message again on the phone. **Enlace no válido** and
   **Volver al acceso**.
8. Confirm a new signup from a message opened first on the same phone. The
   app returns without **Nueva contraseña**.
9. Repeat signup with an address that already has an account. The copy stays
   “Si ya tenías cuenta, inicia sesión o restablece la contraseña.”
10. If the tunnel host or port changes, request another message from the
    phone. Do not reuse a link that was opened on a PC.
