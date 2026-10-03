-- Issue #47. Explicit PERSON market capture.
--
-- Identity stays incomplete until the caller selects a country that is an
-- ACTIVE market with exactly one effective age rule. The country is never
-- inferred, and existing null country_code values are not backfilled.
-- Spain is the versioned pilot baseline. A contradictory Spanish row stops
-- the migration instead of being overwritten or deleted.
-- This file does not deploy and does not start migration 036.

create function public.apply_spanish_identity_market_baseline()
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  market_row public.markets%rowtype;
  current_rule public.market_age_rules%rowtype;
  current_rule_count integer;
begin
  if not exists (
    select 1
      from public.markets as market
     where market.country_code = 'ES'
  ) then
    insert into public.markets (
      country_code,
      default_currency,
      default_locale,
      timezone,
      status,
      config
    ) values (
      'ES',
      'EUR',
      'es-ES',
      'Europe/Madrid',
      'ACTIVE',
      jsonb_build_object(
        'legal_reference', 'BOE-A-1978-31229',
        'legal_article', '12'
      )
    );
  else
    select market.*
      into market_row
      from public.markets as market
     where market.country_code = 'ES';

    if market_row.default_currency is distinct from 'EUR'
       or market_row.default_locale is distinct from 'es-ES'
       or market_row.timezone is distinct from 'Europe/Madrid'
       or market_row.status is distinct from 'ACTIVE' then
      raise exception using
        errcode = '23514',
        message = 'Spanish market configuration conflicts with the approved pilot baseline';
    end if;
  end if;

  select count(*)
    into current_rule_count
    from public.market_age_rules as rule
   where rule.country_code = 'ES'
     and rule.effective_from <= current_date
     and (
       rule.effective_to is null
       or current_date < rule.effective_to
     );

  if current_rule_count > 1 then
    raise exception using
      errcode = '23514',
      message = 'Spanish market configuration conflicts with the approved pilot baseline';
  elsif current_rule_count = 1 then
    select rule.*
      into current_rule
      from public.market_age_rules as rule
     where rule.country_code = 'ES'
       and rule.effective_from <= current_date
       and (
         rule.effective_to is null
         or current_date < rule.effective_to
       );

    if current_rule.legal_adult_age is distinct from 18
       or current_rule.guardian_consent_required is distinct from true
       or (
         current_rule.config ? 'legal_reference'
         and current_rule.config ->> 'legal_reference'
           is distinct from 'BOE-A-1978-31229'
       )
       or (
         current_rule.config ? 'legal_article'
         and current_rule.config ->> 'legal_article' is distinct from '12'
       ) then
      raise exception using
        errcode = '23514',
        message = 'Spanish market configuration conflicts with the approved pilot baseline';
    end if;
  else
    if exists (
      select 1
        from public.market_age_rules as rule
       where rule.country_code = 'ES'
         and daterange(rule.effective_from, rule.effective_to, '[)')
             && daterange(date '1978-12-29', null, '[)')
    ) then
      raise exception using
        errcode = '23514',
        message = 'Spanish market configuration conflicts with the approved pilot baseline';
    end if;

    insert into public.market_age_rules (
      country_code,
      legal_adult_age,
      guardian_consent_required,
      effective_from,
      effective_to,
      config
    ) values (
      'ES',
      18,
      true,
      date '1978-12-29',
      null,
      jsonb_build_object(
        'legal_reference', 'BOE-A-1978-31229',
        'legal_article', '12'
      )
    );
  end if;
end;
$$;

comment on function public.apply_spanish_identity_market_baseline() is
  'Inserts the approved Spain pilot market and majority-age rule when absent. Leaves a matching current rule in place. Raises when the stored Spain configuration conflicts. Does not update persons and does not delete age-rule history.';

revoke all on function public.apply_spanish_identity_market_baseline()
  from public, anon, authenticated, service_role;

select public.apply_spanish_identity_market_baseline();

create function public.identity_market_is_selectable(p_country_code text)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1
      from public.markets as market
     where market.country_code = p_country_code
       and market.status = 'ACTIVE'
       and (
         select count(*)
           from public.market_age_rules as rule
          where rule.country_code = market.country_code
            and rule.effective_from <= current_date
            and (
              rule.effective_to is null
              or current_date < rule.effective_to
            )
       ) = 1
  );
$$;

comment on function public.identity_market_is_selectable(text) is
  'True only for an ACTIVE market with exactly one age rule effective today. Not granted to clients.';

revoke all on function public.identity_market_is_selectable(text)
  from public, anon, authenticated, service_role;

comment on column public.persons.country_code is
  'Explicit PERSON market. Required for a complete identity. Never inferred from locale, device or address metadata, and never backfilled.';

drop function public.complete_my_identity(text, text, date);
drop function public.ensure_my_identity();

create function public.ensure_my_identity()
returns table (
  user_account_id uuid,
  person_id uuid,
  first_name text,
  last_name text,
  date_of_birth date,
  country_code text,
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
    person.country_code,
    nullif(pg_catalog.btrim(person.first_name), '') is not null
      and nullif(pg_catalog.btrim(person.last_name), '') is not null
      and person.date_of_birth is not null
      and public.identity_market_is_selectable(person.country_code)
  from public.user_accounts as account
  join public.persons as person on person.id = account.person_id
  where account.auth_user_id = current_auth_user_id;
end;
$$;

comment on function public.ensure_my_identity() is
  'Resolves only the caller PERSON from auth.uid(). Identity is incomplete until name, date of birth and a selectable market are present. A null country is not assigned.';

revoke all on function public.ensure_my_identity()
  from public, anon, authenticated;
grant execute on function public.ensure_my_identity() to authenticated;

create function public.complete_my_identity(
  p_first_name text,
  p_last_name text,
  p_date_of_birth date,
  p_country_code text
)
returns table (
  user_account_id uuid,
  person_id uuid,
  first_name text,
  last_name text,
  date_of_birth date,
  country_code text,
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
  normalized_country text := nullif(pg_catalog.upper(pg_catalog.btrim(p_country_code)), '');
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

  if normalized_country is null then
    raise exception using
      errcode = '22023',
      message = 'Country is required';
  end if;

  if normalized_country !~ '^[A-Z]{2}$' then
    raise exception using
      errcode = '22023',
      message = 'Country code is not allowed';
  end if;

  select identity.person_id
    into linked_person_id
    from public.ensure_my_identity() as identity;

  if linked_person_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'Identity could not be resolved';
  end if;

  if not public.identity_market_is_selectable(normalized_country) then
    raise exception using
      errcode = 'P0001',
      message = 'Identity market is not available';
  end if;

  update public.persons
     set first_name = normalized_first_name,
         last_name = normalized_last_name,
         date_of_birth = p_date_of_birth,
         country_code = normalized_country,
         updated_at = now()
   where id = linked_person_id;

  return query
  select
    account.id,
    person.id,
    person.first_name,
    person.last_name,
    person.date_of_birth,
    person.country_code,
    nullif(pg_catalog.btrim(person.first_name), '') is not null
      and nullif(pg_catalog.btrim(person.last_name), '') is not null
      and person.date_of_birth is not null
      and public.identity_market_is_selectable(person.country_code)
  from public.user_accounts as account
  join public.persons as person on person.id = account.person_id
  where account.auth_user_id = current_auth_user_id;
end;
$$;

comment on function public.complete_my_identity(text, text, date, text) is
  'Completes or edits only the caller PERSON. Country is normalized and must be one selectable market. The person is resolved from auth.uid(). No client person id is accepted.';

revoke all on function public.complete_my_identity(text, text, date, text)
  from public, anon, authenticated;
grant execute on function public.complete_my_identity(text, text, date, text)
  to authenticated;

create function public.list_identity_markets()
returns table (
  country_code text,
  default_locale text
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
begin
  if auth.uid() is null then
    raise exception using
      errcode = '42501',
      message = 'Authentication required';
  end if;

  return query
  select
    market.country_code,
    market.default_locale
  from public.markets as market
  where public.identity_market_is_selectable(market.country_code)
  order by market.country_code;
end;
$$;

comment on function public.list_identity_markets() is
  'Returns selectable identity markets for the authenticated caller. Does not grant table reads and does not infer a country.';

revoke all on function public.list_identity_markets()
  from public, anon, authenticated;
grant execute on function public.list_identity_markets() to authenticated;
