select set_config('app.vertical_fixture_local', '1', false);
select public.vertical_fixture_retire();

do $$
declare
  fixture_center uuid := '04210000-0000-4000-8000-0000000000c1';
  fixture_equines uuid[] := array[
    '04210000-0000-4000-8000-0000000000e1',
    '04210000-0000-4000-8000-0000000000e2'
  ];
  fixture_pilot_id uuid;
  fixture_person_ids uuid[];
begin
  select pilot.id
    into fixture_pilot_id
    from public.bookable_pilots as pilot
   where pilot.pilot_code = 'VERTICAL_MVP_042';

  delete from public.sessions as session
   where session.booking_id in (
     select booking.id
       from public.bookings as booking
      where booking.center_id = fixture_center
        and booking.equine_id = any (fixture_equines)
   );

  delete from public.booking_requirements as requirement
   where requirement.booking_id in (
     select booking.id
       from public.bookings as booking
      where booking.center_id = fixture_center
        and booking.equine_id = any (fixture_equines)
   );

  delete from public.booking_request_keys as key
   where key.center_id = fixture_center
     and key.equine_id = any (fixture_equines);

  delete from public.bookings as booking
   where booking.center_id = fixture_center
     and booking.equine_id = any (fixture_equines);

  delete from public.equine_calendar_blocks as block
   where block.center_id = fixture_center
     and block.equine_id = any (fixture_equines);

  if fixture_pilot_id is not null then
    alter table public.bookable_pilot_events
      disable trigger bookable_pilot_events_immutable;
    delete from public.bookable_pilot_events as event
     where event.pilot_id = fixture_pilot_id;
    delete from public.bookable_pilot_subjects as subject
     where subject.pilot_id = fixture_pilot_id;
    delete from public.bookable_pilots as pilot
     where pilot.id = fixture_pilot_id;
    alter table public.bookable_pilot_events
      enable trigger bookable_pilot_events_immutable;
  end if;

  alter table public.equine_availability_rules
    disable trigger equine_availability_rules_manage_authority;
  delete from public.equine_availability_rules as rule
   where rule.center_id = fixture_center
      or rule.equine_id = any (fixture_equines);
  alter table public.equine_availability_rules
    enable trigger equine_availability_rules_manage_authority;

  delete from public.service_equines as link
   where link.equine_id = any (fixture_equines)
      or link.service_id in (
        select service.id
          from public.center_services as service
         where service.center_id = fixture_center
      );
  delete from public.center_services as service
   where service.center_id = fixture_center;
  delete from public.equine_center_permissions as permission
   where permission.center_id = fixture_center
      or permission.equine_id = any (fixture_equines);
  delete from public.equine_ownerships as ownership
   where ownership.equine_id = any (fixture_equines);
  delete from public.equine_center_assignments as assignment
   where assignment.center_id = fixture_center
      or assignment.equine_id = any (fixture_equines);
  delete from public.center_memberships as membership
   where membership.center_id = fixture_center;
  delete from public.equines as equine
   where equine.id = any (fixture_equines);
  delete from public.equestrian_centers as center
   where center.id = fixture_center
     and center.name = 'TEST_ONLY Vertical Center';

  select array_agg(account.person_id)
    into fixture_person_ids
    from public.user_accounts as account
   where account.auth_user_id in (
     '04220000-0000-4000-8000-0000000000b1',
     '04220000-0000-4000-8000-0000000000b2'
   );
  delete from public.user_accounts as account
   where account.auth_user_id in (
     '04220000-0000-4000-8000-0000000000b1',
     '04220000-0000-4000-8000-0000000000b2'
   );
  delete from public.persons as person
   where person.id = any (fixture_person_ids);
  delete from auth.users
   where id in (
     '04220000-0000-4000-8000-0000000000b1',
     '04220000-0000-4000-8000-0000000000b2'
   );
end;
$$;
