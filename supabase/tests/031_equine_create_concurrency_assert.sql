do $$
declare
  equine_count integer;
  ownership_count integer;
  manager_count integer;
begin
  if exists (
    select 1 from public.equines as equine where equine.name = 'Race Rollback'
  ) then
    raise exception 'Rolled-back concurrent create remained visible';
  end if;

  select count(*) into equine_count
    from public.equines as equine
   where equine.name in ('Race A', 'Race B')
     and equine.status = 'ACTIVE'
     and equine.visibility_status = 'PRIVATE';
  if equine_count <> 2 then
    raise exception 'Concurrent creates did not both commit, got %', equine_count;
  end if;

  select count(*) into ownership_count
    from public.equine_ownerships as ownership
    join public.equines as equine on equine.id = ownership.equine_id
   where equine.name in ('Race A', 'Race B')
     and ownership.owner_type = 'PERSON'
     and ownership.owner_person_id = '03120000-0000-4000-8000-000000000011'
     and ownership.ownership_percentage = 100
     and ownership.status = 'ACTIVE';
  if ownership_count <> 2 then
    raise exception 'Concurrent creates did not each write ownership, got %', ownership_count;
  end if;

  select count(*) into manager_count
    from public.equine_management_assignments as assignment
    join public.equines as equine on equine.id = assignment.equine_id
   where equine.name in ('Race A', 'Race B')
     and assignment.manager_type = 'PERSON'
     and assignment.manager_person_id = '03120000-0000-4000-8000-000000000011'
     and assignment.management_role = 'PRIMARY_MANAGER'
     and assignment.status = 'ACTIVE'
     and assignment.valid_until is null;
  if manager_count <> 2 then
    raise exception 'Concurrent creates did not each write a primary manager, got %', manager_count;
  end if;
end;
$$;
