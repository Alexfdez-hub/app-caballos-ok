-- Cleanup committed concurrency fixtures.
set session_replication_role = replica;

delete from public.audit_events
 where metadata->>'booking_id' = '88700000-0000-0000-0000-00000000b001'
    or entity_id in (
      select id from public.sessions
       where booking_id = '88700000-0000-0000-0000-00000000b001'
    )
    or entity_id in (
      select id from public.incidents
       where booking_id = '88700000-0000-0000-0000-00000000b001'
    );
delete from public.reviews
 where booking_id = '88700000-0000-0000-0000-00000000b001';
delete from public.incidents
 where booking_id = '88700000-0000-0000-0000-00000000b001';
delete from public.equine_activities
 where session_id in (
   select id from public.sessions
    where booking_id = '88700000-0000-0000-0000-00000000b001'
 );
delete from public.session_evidence
 where session_id in (
   select id from public.sessions
    where booking_id = '88700000-0000-0000-0000-00000000b001'
 );
delete from public.session_events
 where session_id in (
   select id from public.sessions
    where booking_id = '88700000-0000-0000-0000-00000000b001'
 );
delete from public.session_permits
 where booking_id = '88700000-0000-0000-0000-00000000b001';
delete from public.sessions
 where booking_id = '88700000-0000-0000-0000-00000000b001';
delete from public.booking_requirements
 where booking_id = '88700000-0000-0000-0000-00000000b001';
delete from public.equine_calendar_blocks
 where source_id = '88700000-0000-0000-0000-00000000b001';
delete from public.bookings
 where id = '88700000-0000-0000-0000-00000000b001';

delete from public.service_equines
 where equine_id in (
   select id from public.equines where name = 'phase13b-conc-school'
 );
delete from public.equine_availability_rules
 where equine_id in (
   select id from public.equines where name = 'phase13b-conc-school'
 );
delete from public.equine_center_permissions
 where equine_id in (
   select id from public.equines where name = 'phase13b-conc-school'
 );
delete from public.equine_center_assignments
 where equine_id in (
   select id from public.equines where name = 'phase13b-conc-school'
 );
delete from public.equine_ownerships
 where equine_id in (
   select id from public.equines where name = 'phase13b-conc-school'
 );
delete from public.equines where name = 'phase13b-conc-school';
delete from public.center_services
 where center_id in (
   select id from public.equestrian_centers where slug = 'phase13b-conc'
 );
delete from public.center_memberships
 where center_id in (
   select id from public.equestrian_centers where slug = 'phase13b-conc'
 );
delete from public.center_languages
 where center_id in (
   select id from public.equestrian_centers where slug = 'phase13b-conc'
 );
delete from public.equestrian_centers where slug = 'phase13b-conc';

delete from public.policy_acceptances
 where user_account_id in (
   select id from public.user_accounts
    where auth_user_id in (
      '88700000-0000-0000-0000-000000000001'::uuid,
      '88700000-0000-0000-0000-000000000005'::uuid
    )
 );
delete from public.policy_documents
 where policy_code = 'TERMS_ZY' and market_code = 'ZY';
delete from public.user_accounts
 where auth_user_id in (
   '88700000-0000-0000-0000-000000000001'::uuid,
   '88700000-0000-0000-0000-000000000005'::uuid,
   '88700000-0000-0000-0000-000000000007'::uuid
 );
delete from public.persons
 where first_name = 'Conc13B'
   and last_name in ('Rider', 'Staff', 'Owner');
delete from public.market_age_rules where country_code = 'ZY';
delete from public.markets where country_code = 'ZY';
delete from auth.users
 where id in (
   '88700000-0000-0000-0000-000000000001'::uuid,
   '88700000-0000-0000-0000-000000000005'::uuid,
   '88700000-0000-0000-0000-000000000007'::uuid
 );

set session_replication_role = origin;
