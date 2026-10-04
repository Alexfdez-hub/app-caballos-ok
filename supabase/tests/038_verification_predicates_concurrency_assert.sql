do $$
begin
  if not public.verification_identity_is_verified(
    (
      select account.person_id
        from public.user_accounts as account
       where account.auth_user_id = '03820000-0000-4000-8000-000000000001'
    ),
    'ES',
    pg_catalog.clock_timestamp()
  ) then
    raise exception 'Committed acceptance was not visible to the predicate';
  end if;
end;
$$;
