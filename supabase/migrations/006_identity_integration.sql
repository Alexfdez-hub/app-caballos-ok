-- Phase 3A: Architecture 2.1 identity integration.
--
-- Reuses public.persons and public.user_accounts from migration 003.
-- Auth credentials remain in auth.users. A generated public.user_accounts row
-- links each normal application account to a distinct public.persons row.
-- Required human identity fields remain null until the authenticated person
-- supplies them. No first_name, last_name, or date_of_birth is fabricated.
--
-- Access model:
--   - Table RLS stays enabled and deny-by-default (no client policies).
--   - Migration 003 revoked ALL table privileges from anon/authenticated.
--   - This migration does not grant table INSERT/UPDATE/DELETE/SELECT.
--   - Authenticated reads and writes go through SECURITY DEFINER RPCs that
--     derive the caller exclusively from auth.uid().
--   - The provisioning trigger is not executable by clients.

comment on column public.persons.first_name is
  'Required to complete authenticated identity onboarding; remains nullable so incomplete accounts and future persons without login credentials are not forced to invent values.';
comment on column public.persons.last_name is
  'Required to complete authenticated identity onboarding; remains nullable so incomplete accounts and future persons without login credentials are not forced to invent values.';
comment on column public.persons.date_of_birth is
  'Required to complete authenticated identity onboarding; remains nullable so incomplete accounts and future persons without login credentials are not forced to invent values. Age is not stored.';

create function public.handle_new_identity_account()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  linked_person_id uuid;
begin
  if new.id is null then
    raise exception 'Auth user id is required';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(new.id::text, 0)
  );

  select account.person_id
    into linked_person_id
    from public.user_accounts as account
   where account.auth_user_id = new.id;

  if linked_person_id is not null then
    return new;
  end if;

  begin
    insert into public.persons default values
      returning id into linked_person_id;

    insert into public.user_accounts (auth_user_id, person_id)
    values (new.id, linked_person_id);
  exception
    when unique_violation then
      select account.person_id
        into linked_person_id
        from public.user_accounts as account
       where account.auth_user_id = new.id;

      if linked_person_id is null then
        raise;
      end if;
  end;

  return new;
end;
$$;

comment on function public.handle_new_identity_account() is
  'Creates the minimum person/account linkage for a newly inserted Auth user without fabricating personal data.';

revoke all on function public.handle_new_identity_account()
  from public, anon, authenticated;

create trigger on_auth_user_identity_created
after insert on auth.users
for each row execute function public.handle_new_identity_account();

create function public.ensure_my_identity()
returns table (
  user_account_id uuid,
  person_id uuid,
  first_name text,
  last_name text,
  date_of_birth date,
  is_complete boolean
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  current_auth_user_id uuid := auth.uid();
  linked_person_id uuid;
begin
  if current_auth_user_id is null then
    raise exception using
      errcode = '42501',
      message = 'Authentication required';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(current_auth_user_id::text, 0)
  );

  select account.person_id
    into linked_person_id
    from public.user_accounts as account
   where account.auth_user_id = current_auth_user_id;

  if linked_person_id is null then
    begin
      insert into public.persons default values
        returning id into linked_person_id;

      insert into public.user_accounts (auth_user_id, person_id)
      values (current_auth_user_id, linked_person_id);
    exception
      when unique_violation then
        select account.person_id
          into linked_person_id
          from public.user_accounts as account
         where account.auth_user_id = current_auth_user_id;

        if linked_person_id is null then
          raise;
        end if;
    end;
  end if;

  return query
  select
    account.id,
    person.id,
    person.first_name,
    person.last_name,
    person.date_of_birth,
    nullif(pg_catalog.btrim(person.first_name), '') is not null
      and nullif(pg_catalog.btrim(person.last_name), '') is not null
      and person.date_of_birth is not null
  from public.user_accounts as account
  join public.persons as person on person.id = account.person_id
  where account.auth_user_id = current_auth_user_id;
end;
$$;

comment on function public.ensure_my_identity() is
  'Idempotently resolves or creates the caller''s minimum account/person linkage and returns only that identity. Completeness is derived from required person fields.';

revoke all on function public.ensure_my_identity()
  from public, anon, authenticated;
grant execute on function public.ensure_my_identity() to authenticated;

create function public.complete_my_identity(
  p_first_name text,
  p_last_name text,
  p_date_of_birth date
)
returns table (
  user_account_id uuid,
  person_id uuid,
  first_name text,
  last_name text,
  date_of_birth date,
  is_complete boolean
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  current_auth_user_id uuid := auth.uid();
  linked_person_id uuid;
  normalized_first_name text := nullif(pg_catalog.btrim(p_first_name), '');
  normalized_last_name text := nullif(pg_catalog.btrim(p_last_name), '');
begin
  if current_auth_user_id is null then
    raise exception using
      errcode = '42501',
      message = 'Authentication required';
  end if;

  if normalized_first_name is null
     or normalized_last_name is null
     or pg_catalog.char_length(normalized_first_name) > 100
     or pg_catalog.char_length(normalized_last_name) > 100 then
    raise exception using
      errcode = '22023',
      message = 'First name and last name are required';
  end if;

  if p_date_of_birth is null or p_date_of_birth > current_date then
    raise exception using
      errcode = '22023',
      message = 'A valid date of birth is required';
  end if;

  select identity.person_id
    into linked_person_id
    from public.ensure_my_identity() as identity;

  if linked_person_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'Identity could not be resolved';
  end if;

  update public.persons
     set first_name = normalized_first_name,
         last_name = normalized_last_name,
         date_of_birth = p_date_of_birth,
         updated_at = now()
   where id = linked_person_id;

  return query
  select
    account.id,
    person.id,
    person.first_name,
    person.last_name,
    person.date_of_birth,
    nullif(pg_catalog.btrim(person.first_name), '') is not null
      and nullif(pg_catalog.btrim(person.last_name), '') is not null
      and person.date_of_birth is not null
  from public.user_accounts as account
  join public.persons as person on person.id = account.person_id
  where account.auth_user_id = current_auth_user_id;
end;
$$;

comment on function public.complete_my_identity(text, text, date) is
  'Completes or edits only the authenticated caller''s required basic person fields. The target person is derived from auth.uid(), never from a client-supplied person_id.';

revoke all on function public.complete_my_identity(text, text, date)
  from public, anon, authenticated;
grant execute on function public.complete_my_identity(text, text, date)
  to authenticated;
