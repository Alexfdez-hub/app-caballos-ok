# Activity read model

Personal Activity screen only. Remote project `efkauegdlmfkonzwyyiv` is
not modified by this branch.

## Determined visibility

`list_my_activity()` returns a booking only when either:

- the caller PERSON is `participant_person_id`, or
- the caller ACCOUNT is `booked_by_account_id`.

Self-booking matches both and is reported as `PARTICIPANT`. A guardian
account that booked for a minor is reported as `BOOKER` and the other
person's name is not returned. This is the personal half of the frozen
session-operator rule. It keeps PARTICIPANT distinct from BOOKER and
does not grant table reads.

## Not granted

These would be a new visibility choice, so they are absent:

- a center manager or instructor inbox (`MANAGE_BOOKINGS` can confirm a
  booking and still sees nothing in this list);
- enumeration of a minor's bookings by a verified guardian who did not
  book them (eligibility remains a point check);
- equine or center names;
- policy snapshots, coordinates, session evidence, reviews, incidents
  and audit;
- equine occupancy or availability (the screen shows the caller's own
  booking times, not the equine calendar);
- Zero Session rows (no caller-scoped Zero Session read exists).

Storage for `avatars` and `equine-media` stays deny-by-default private.
Equine creation is not in this change.
