# Vertical MVP smoke

Local procedure for migration `042`. This file does not run the fixture
and does not authorize a remote deploy. Bugbot stays manual. Autofix
stays off. Do not merge from this note.

The hosted project still has the previously deployed schema. Expo Go
against that project cannot call `list_bookable_offers` until a later
authorized deploy of `042`. Do not apply the migration or the fixture
there during this train.

## What the path does

1. An authenticated person with an ACTIVE account and an ACTIVE person
   opens Explorar and sees derived slots for equines that are also an
   ACTIVE subject of an OPEN administered pilot, PUBLIC, ACTIVE, with
   an ACTIVE center assignment, an enabled service, and a stored
   availability window.
2. PRIVATE equines are absent, including by direct UUID. A PUBLIC equine
   outside the open pilot is also absent, including by direct UUID.
3. The person requests one slot. The server rechecks the slot, writes a
   REQUESTED-family booking, and does not confirm it.
4. A center ADMIN or MANAGER with effective `MANAGE_BOOKINGS` sees that
   APPROVED request under Actividad → Puedes confirmar and calls
   `confirm_booking`.
5. The participant sees the booking in Actividad. Iniciar actividad and
   Finalizar actividad call `start_session` and `end_session`.
6. Photos stay pending. The app does not open Storage.

A request can remain `PENDING_REQUIREMENTS` or `PENDING_APPROVAL` when
the existing eligibility rules are not met. That is not a failed write
and it is not a confirmation.

## Local fixture

Use a local database only, after migrations `001`–`042`. The two
arguments must already exist in `auth.users`. The function does not
create them.

```sql
begin;
select set_config('app.vertical_fixture_local', '1', true);
select public.vertical_fixture_install(
  '<existing-auth-user-a>'::uuid,
  '<existing-auth-user-b>'::uuid
);
```

Inspect, then either `rollback` or, on that same local database:

```sql
select public.vertical_fixture_retire();
commit;
```

`vertical_fixture_install` enrolls only `TEST_ONLY Equine` at that
center by calling `open_bookable_pilot('VERTICAL_MVP_042')` and
`add_bookable_pilot_subject`. Those ids live in the fixture function.
The list, exact read, request, and confirm queue do not contain them
and do not match the TEST_ONLY name. A real PUBLIC row stays unbookable.

`vertical_fixture_retire` ends that pilot subject, deactivates the
TEST_ONLY windows, cancels fixture occupancy, and deletes only open
fixture requests. It does not delete `audit_events`,
`bookable_pilot_events`, `auth.users`, or persons. Availability rules
cannot be deleted, so the marked center and equine rows remain inactive
until `vertical_fixture_install` is called again. A second install is
idempotent and admits the same pair again. Closing a pilot is a
separate postgres call and does not reopen it. Do not run this fixture
on a hosted project.

The stored window is `2026-12-02 09:00:00+00` through `12:00:00+00`,
in three 60-minute slots, at `TEST_ONLY Vertical Center` /
`TEST_ONLY Equine`. `TEST_ONLY Private Equine` must not appear.
`duration_limit_minutes` is null on that service.

## Android, after a later authorized deploy

Do not change either existing user's credentials. Do not create a third
Auth user.

1. Install the local fixture only if this build is pointed at a local
   Supabase. For the hosted project, stop: `042` is not deployed.
2. On the rider phone, sign in as the first existing user.
3. Open Explorar. Move forward by seven days until `2026-12-02` is
   inside the shown UTC range.
4. Confirm `TEST_ONLY Equine` is listed and `TEST_ONLY Private Equine`
   is not. Open one 60-minute slot and tap Solicitar reserva once.
   The button stays disabled while the request is in flight.
5. If the device loses the response, tap Reconciliar con el servidor.
   Do not send a second request before that read.
6. Sign out. Sign in as the second existing user. Explorar must not
   show the first user's activity. Actividad → Solicitudes must not
   list the first user's booking.
7. If the second user is the fixture manager, Actividad → Puedes
   confirmar shows the APPROVED request. Tap Confirmar reserva once.
8. Sign back in as the first user. Actividad → Próximas shows the
   confirmed booking. Iniciar actividad, then Finalizar actividad.
   The photo row stays pending.
9. Sign out and back in. The completed session remains under Historial.

Eligibility, center membership, and `MANAGE_BOOKINGS` still come from
the database. A user who lacks them will see an empty confirm queue or
a pending request. Do not grant those roles from the client.
