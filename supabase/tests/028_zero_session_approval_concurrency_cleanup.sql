set session_replication_role = replica;
delete from public.rider_equine_authorizations
 where source_zero_session_id = '98100000-0000-0000-0000-00000000a001';
delete from public.zero_sessions
 where id = '98100000-0000-0000-0000-00000000a001';
delete from public.equine_center_permissions
 where equine_id = '98100000-0000-0000-0000-00000000e001';
delete from public.center_memberships
 where center_id = '98100000-0000-0000-0000-00000000c001';
delete from public.equines
 where id = '98100000-0000-0000-0000-00000000e001';
delete from public.equestrian_centers
 where id = '98100000-0000-0000-0000-00000000c001';
delete from public.user_accounts
 where auth_user_id in (
   '98100000-0000-0000-0000-000000000001',
   '98100000-0000-0000-0000-000000000002',
   '98100000-0000-0000-0000-000000000003',
   '98100000-0000-0000-0000-000000000004'
 );
delete from public.persons where first_name = 'Conc9B';
delete from public.market_age_rules where country_code = 'Z9';
delete from public.markets where country_code = 'Z9';
delete from auth.users
 where id in (
   '98100000-0000-0000-0000-000000000001',
   '98100000-0000-0000-0000-000000000002',
   '98100000-0000-0000-0000-000000000003',
   '98100000-0000-0000-0000-000000000004'
 );
set session_replication_role = origin;
