do $$
declare
  equine_ids uuid[];
begin
  select coalesce(array_agg(equine.id), '{}')
    into equine_ids
    from public.equines as equine
   where equine.name in ('Race A', 'Race B', 'Race Rollback');

  delete from public.equine_management_assignments as assignment
   where assignment.equine_id = any (equine_ids);

  delete from public.equine_ownerships as ownership
   where ownership.equine_id = any (equine_ids);

  delete from public.equines as equine
   where equine.id = any (equine_ids);

  delete from public.user_accounts
   where id = '03120000-0000-4000-8000-000000000021';

  delete from public.persons
   where id = '03120000-0000-4000-8000-000000000011';

  delete from auth.users
   where id = '03120000-0000-4000-8000-000000000001';

  delete from public.market_age_rules
   where country_code = 'QR';

  delete from public.markets
   where country_code = 'QR';
end;
$$;
