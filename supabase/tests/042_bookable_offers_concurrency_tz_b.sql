set statement_timeout = '20s';
begin;
set local time zone 'Europe/Madrid';
set local role authenticated;
select set_config('request.jwt.claim.sub', '04220000-0000-4000-8000-0000000000b1', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"04220000-0000-4000-8000-0000000000b1","role":"authenticated"}',
  true
);
select outcome as session_tz_b_outcome, booking_id as session_tz_b_booking
from public.request_bookable_slot(
  '04220000-0000-4000-8000-0000000000d6',
  '04210000-0000-4000-8000-0000000000e1',
  '04210000-0000-4000-8000-0000000000c1',
  '04210000-0000-4000-8000-0000000000f1',
  timestamptz '2026-12-02 12:00:00+01',
  timestamptz '2026-12-02 13:00:00+01'
);
commit;
select 'session_tz_b_committed' as marker;
