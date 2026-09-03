drop function if exists public.confirm_booking_concurrency_probe(uuid);

-- Best-effort teardown of committed confirm fixtures. Product triggers
-- forbid deleting CONFIRMED booking_requirements and calendar blocks;
-- replica role is test-only so this suite can drop its own rows.

set session_replication_role = replica;

delete from public.booking_requirements
 where booking_id = '99100000-0000-0000-0000-00000000b001';
delete from public.equine_calendar_blocks
 where source_id = '99100000-0000-0000-0000-00000000b001';
delete from public.bookings
 where id = '99100000-0000-0000-0000-00000000b001';
delete from public.equine_requirements
 where equine_id in (
   select id from public.equines where name = 'phase11b-conc-school'
 );
delete from public.service_equines
 where equine_id in (
   select id from public.equines where name = 'phase11b-conc-school'
 );
delete from public.equine_availability_rules
 where equine_id in (
   select id from public.equines where name = 'phase11b-conc-school'
 );
delete from public.equine_center_permissions
 where equine_id in (
   select id from public.equines where name = 'phase11b-conc-school'
 );
delete from public.equine_center_assignments
 where equine_id in (
   select id from public.equines where name = 'phase11b-conc-school'
 );
delete from public.equine_ownerships
 where equine_id in (
   select id from public.equines where name = 'phase11b-conc-school'
 );
delete from public.equines where name = 'phase11b-conc-school';
delete from public.center_services
 where center_id in (
   select id from public.equestrian_centers where slug = 'phase11b-conc'
 );
delete from public.center_memberships
 where center_id in (
   select id from public.equestrian_centers where slug = 'phase11b-conc'
 );
delete from public.center_languages
 where center_id in (
   select id from public.equestrian_centers where slug = 'phase11b-conc'
 );
delete from public.equestrian_centers where slug = 'phase11b-conc';
delete from public.policy_acceptances
 where user_account_id in (
   select id from public.user_accounts
    where auth_user_id in (
      '99100000-0000-0000-0000-000000000001'::uuid,
      '99100000-0000-0000-0000-000000000005'::uuid
    )
 );
delete from public.policy_documents
 where policy_code = 'TERMS_ZQ' and market_code = 'ZQ';
delete from public.user_accounts
 where auth_user_id in (
   '99100000-0000-0000-0000-000000000001'::uuid,
   '99100000-0000-0000-0000-000000000005'::uuid,
   '99100000-0000-0000-0000-000000000007'::uuid
 );
delete from public.persons
 where first_name = 'Conc'
   and last_name in ('Rider', 'Staff', 'Owner');
delete from public.market_age_rules where country_code = 'ZQ';
delete from public.markets where country_code = 'ZQ';
delete from auth.users
 where id in (
   '99100000-0000-0000-0000-000000000001'::uuid,
   '99100000-0000-0000-0000-000000000005'::uuid,
   '99100000-0000-0000-0000-000000000007'::uuid
 );

set session_replication_role = origin;
select pg_advisory_unlock_all();
select 'concurrency_cleanup_done' as marker;
