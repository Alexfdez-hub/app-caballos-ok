-- Committed fixture for two concurrent request_bookable_slot keys.
-- Local database only. Cleanup removes these rows.

do $$
begin
  if not exists (
    select 1
      from public.user_accounts as account
     where account.auth_user_id = '04220000-0000-4000-8000-0000000000b1'
  ) or not exists (
    select 1
      from public.user_accounts as account
     where account.auth_user_id = '04220000-0000-4000-8000-0000000000b2'
  ) then
    delete from auth.users
     where id in (
       '04220000-0000-4000-8000-0000000000b1',
       '04220000-0000-4000-8000-0000000000b2'
     );
    insert into auth.users (id) values
      ('04220000-0000-4000-8000-0000000000b1'),
      ('04220000-0000-4000-8000-0000000000b2');
  end if;
end;
$$;

select set_config('app.vertical_fixture_local', '1', false);
select public.vertical_fixture_install(
  '04220000-0000-4000-8000-0000000000b1',
  '04220000-0000-4000-8000-0000000000b2'
);
