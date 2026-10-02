-- Caller-scoped activity read for the personal Activity screen.
--
-- Does not grant table access. Does not list center rosters, unrelated
-- guardians' wards, audit, evidence, coordinates or policy snapshots.
-- Visibility is the personal half of the frozen session-operator rule:
-- the caller PERSON is the participant, or the caller ACCOUNT is the
-- booker. PARTICIPANT != BOOKER, so those are separate matches.
-- MANAGE_BOOKINGS remains an operational authority and is not a license
-- to enumerate other people's bookings. A verified guardian who did not
-- book the row cannot enumerate it; eligibility inspection stays a
-- point check. now() is not used in a table CHECK.

create function public.list_my_activity()
returns table (
  booking_id uuid,
  starts_at timestamptz,
  ends_at timestamptz,
  booking_status text,
  eligibility_status text,
  caller_relation text,
  session_id uuid,
  session_status text,
  session_started_at timestamptz,
  session_ended_at timestamptz
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  current_auth_user_id uuid := auth.uid();
  caller_account uuid;
  caller_person uuid;
begin
  if current_auth_user_id is null then
    raise exception using
      errcode = '42501',
      message = 'Authentication required';
  end if;

  select account.id, account.person_id
    into caller_account, caller_person
    from public.user_accounts as account
   where account.auth_user_id = current_auth_user_id;

  if caller_person is null or caller_account is null then
    raise exception using
      errcode = 'P0001',
      message = 'Identity could not be resolved';
  end if;

  return query
  select
    booking.id,
    booking.starts_at,
    booking.ends_at,
    booking.status,
    booking.eligibility_status,
    case
      when booking.participant_person_id = caller_person then 'PARTICIPANT'
      else 'BOOKER'
    end,
    session.id,
    session.status,
    session.started_at,
    session.ended_at
  from public.bookings as booking
  left join public.sessions as session
    on session.booking_id = booking.id
  where booking.participant_person_id = caller_person
     or booking.booked_by_account_id = caller_account
  order by booking.starts_at desc, booking.id;
end;
$$;

comment on function public.list_my_activity() is
  'Authenticated personal activity. Returns bookings where the caller PERSON is the participant or the caller ACCOUNT is the booker, plus the linked session status and official timestamps. Does not accept a person id. Does not return other people, equine or center names, policy snapshots, coordinates, evidence, reviews, incidents or audit. Staff MANAGE_BOOKINGS and a verified guardian who is not the booker are excluded.';

revoke all on function public.list_my_activity()
  from public, anon, authenticated;
grant execute on function public.list_my_activity() to authenticated;
