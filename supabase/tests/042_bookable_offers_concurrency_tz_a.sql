set statement_timeout = '20s';
begin;
set local time zone 'UTC';
set local role authenticated;
select set_config('request.jwt.claim.sub', '04220000-0000-4000-8000-0000000000b1', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"04220000-0000-4000-8000-0000000000b1","role":"authenticated"}',
  true
);
select outcome as session_tz_a_outcome, booking_id as session_tz_a_booking
from public.request_bookable_slot(
  '04220000-0000-4000-8000-0000000000d5',
  '04210000-0000-4000-8000-0000000000e1',
  '04210000-0000-4000-8000-0000000000c1',
  '04210000-0000-4000-8000-0000000000f1',
  timestamptz '2026-12-02 11:00:00+00',
  timestamptz '2026-12-02 12:00:00+00'
);
select 'session_tz_a_holding' as marker;
select pg_sleep(2);
commit;
select 'session_tz_a_committed' as marker;
