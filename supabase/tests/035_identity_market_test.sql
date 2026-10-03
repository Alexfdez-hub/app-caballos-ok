-- Issue #47. One transaction, then ROLLBACK.
-- Spain is installed by migration 035. Fixture markets use other codes.

begin;

do $$
declare
  spanish_rules integer;
  adult_years integer;
  minor_years integer;
begin
  perform public.apply_spanish_identity_market_baseline();

  if not exists (
    select 1
      from public.markets as market
     where market.country_code = 'ES'
       and market.default_currency = 'EUR'
       and market.default_locale = 'es-ES'
       and market.timezone = 'Europe/Madrid'
       and market.status = 'ACTIVE'
  ) then
    raise exception 'Spain pilot market baseline is missing';
  end if;

  select count(*)
    into spanish_rules
    from public.market_age_rules as rule
   where rule.country_code = 'ES'
     and rule.legal_adult_age = 18
     and rule.guardian_consent_required
     and rule.effective_from <= current_date
     and (rule.effective_to is null or current_date < rule.effective_to)
     and rule.config ->> 'legal_reference' = 'BOE-A-1978-31229'
     and rule.config ->> 'legal_article' = '12';

  if spanish_rules <> 1 then
    raise exception 'Spain needs exactly one current majority rule, got %', spanish_rules;
  end if;

  if exists (
    select 1
      from public.persons as person
     where person.country_code = 'ES'
  ) then
    raise exception 'Spain baseline assigned a person country';
  end if;

  select extract(year from age(current_date, date '1990-01-01'))::integer
    into adult_years;
  select extract(year from age(current_date, date '2016-01-01'))::integer
    into minor_years;

  if adult_years < 18 or minor_years >= 18 then
    raise exception 'Spain adult and minor fixtures are not on opposite sides of 18';
  end if;

  begin
    update public.market_age_rules
       set legal_adult_age = 16
     where country_code = 'ES'
       and effective_to is null;
    perform public.apply_spanish_identity_market_baseline();
    raise exception using
      errcode = 'P0002',
      message = 'Contradictory Spain rule was accepted';
  exception
    when check_violation then
      if sqlerrm is distinct from
        'Spanish market configuration conflicts with the approved pilot baseline' then
        raise;
      end if;
  end;

  begin
    update public.markets
       set default_currency = 'USD'
     where country_code = 'ES';
    perform public.apply_spanish_identity_market_baseline();
    raise exception using
      errcode = 'P0002',
      message = 'Contradictory Spain market was accepted';
  exception
    when check_violation then
      if sqlerrm is distinct from
        'Spanish market configuration conflicts with the approved pilot baseline' then
        raise;
      end if;
  end;
end;
$$;

insert into public.markets (country_code, default_currency, default_locale, timezone, status)
values
  ('QI', 'EUR', 'es-ES', 'Europe/Madrid', 'INACTIVE'),
  ('QN', 'EUR', 'es-ES', 'Europe/Madrid', 'ACTIVE'),
  ('QF', 'EUR', 'es-ES', 'Europe/Madrid', 'ACTIVE'),
  ('QE', 'EUR', 'es-ES', 'Europe/Madrid', 'ACTIVE'),
  ('QD', 'EUR', 'es-ES', 'Europe/Madrid', 'ACTIVE'),
  ('QB', 'EUR', 'es-ES', 'Europe/Madrid', 'ACTIVE'),
  ('QA', 'EUR', 'es-ES', 'Europe/Madrid', 'ACTIVE'),
  ('QO', 'EUR', 'es-ES', 'Europe/Madrid', 'ACTIVE');

insert into public.market_age_rules (
  country_code, legal_adult_age, guardian_consent_required, effective_from, effective_to
) values
  ('QI', 18, true, date '2000-01-01', null),
  ('QF', 18, true, current_date + 1, null),
  ('QE', 18, true, date '2000-01-01', current_date),
  ('QD', 18, true, current_date, null),
  ('QB', 18, true, date '2000-01-01', date '2010-01-01'),
  ('QB', 18, true, date '2010-01-01', null),
  ('QA', 18, true, date '2000-01-01', null);

set local session_replication_role = replica;

insert into public.market_age_rules (
  country_code, legal_adult_age, guardian_consent_required, effective_from, effective_to
) values (
  'QA', 21, false, date '2015-01-01', null
);

set local session_replication_role = origin;

do $$
begin
  begin
    insert into public.market_age_rules (
      country_code, legal_adult_age, guardian_consent_required, effective_from, effective_to
    ) values (
      'QO', 18, true, date '2000-01-01', date '2010-01-01'
    );
    insert into public.market_age_rules (
      country_code, legal_adult_age, guardian_consent_required, effective_from, effective_to
    ) values (
      'QO', 18, true, date '2009-06-01', date '2011-01-01'
    );
    raise exception using
      errcode = 'P0002',
      message = 'Overlapping age rule was accepted';
  exception
    when exclusion_violation then null;
  end;
end;
$$;

insert into auth.users (id) values
  ('03510000-0000-4000-8000-000000000001'),
  ('03510000-0000-4000-8000-000000000002');

select set_config('request.jwt.claim.sub', '03510000-0000-4000-8000-000000000001', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"03510000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
set local role authenticated;

do $$
declare
  listed text[];
  resolved record;
  stored_country text;
begin
  select * into resolved from public.ensure_my_identity();
  if resolved.is_complete or resolved.country_code is not null then
    raise exception 'Missing country was treated as a complete identity';
  end if;

  begin
    perform public.complete_my_identity('Ana', 'Example', date '1990-01-01', null);
    raise exception using errcode = 'P0002', message = 'Missing country was accepted';
  exception
    when invalid_parameter_value then
      if sqlerrm is distinct from 'Country is required' then
        raise;
      end if;
  end;

  begin
    perform public.complete_my_identity('Ana', 'Example', date '1990-01-01', 'Spain');
    raise exception using errcode = 'P0002', message = 'Invalid country format was accepted';
  exception
    when invalid_parameter_value then
      if sqlerrm is distinct from 'Country code is not allowed' then
        raise;
      end if;
  end;

  begin
    perform public.complete_my_identity('Ana', 'Example', date '1990-01-01', 'ZZ');
    raise exception using errcode = 'P0002', message = 'Unknown market was accepted';
  exception
    when sqlstate 'P0001' then
      if sqlerrm is distinct from 'Identity market is not available'
         or sqlerrm like '%ZZ%' then
        raise;
      end if;
  end;

  foreach stored_country in array array['QI', 'QN', 'QF', 'QE', 'QA']
  loop
    begin
      perform public.complete_my_identity(
        'Ana', 'Example', date '1990-01-01', stored_country
      );
      raise exception using
        errcode = 'P0002',
        message = 'Unselectable market was accepted';
    exception
      when sqlstate 'P0001' then
        if sqlerrm is distinct from 'Identity market is not available' then
          raise;
        end if;
    end;
  end loop;

  select array_agg(market.country_code order by market.country_code)
    into listed
    from public.list_identity_markets() as market;

  if listed && array['QI', 'QN', 'QF', 'QE', 'QA']
     or not listed @> array['ES', 'QD', 'QB'] then
    raise exception 'Identity market list did not follow the effective rule, got %', listed;
  end if;

  select * into resolved
    from public.complete_my_identity('  Ana  ', '  Example  ', date '1990-01-01', ' es ');

  if resolved.country_code is distinct from 'ES'
     or not resolved.is_complete
     or resolved.first_name is distinct from 'Ana' then
    raise exception 'Selectable Spain market did not complete the caller identity';
  end if;

  select * into resolved
    from public.complete_my_identity('Ana', 'Example', date '2016-01-01', 'ES');

  if not resolved.is_complete or resolved.date_of_birth is distinct from date '2016-01-01' then
    raise exception 'A minor with an explicit market was left incomplete';
  end if;

  perform set_config('identity.person_id', resolved.person_id::text, true);

  begin
    perform * from public.markets;
    raise exception 'Authenticated read markets directly';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform * from public.market_age_rules;
    raise exception 'Authenticated read age rules directly';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

reset role;

do $$
declare
  caller_person uuid := current_setting('identity.person_id')::uuid;
begin
  if exists (
    select 1
      from public.persons as person
     where person.id = caller_person
       and (
         person.country_code is distinct from 'ES'
         or person.date_of_birth is distinct from date '2016-01-01'
       )
  ) then
    raise exception 'Caller market was not stored on that person';
  end if;

  if exists (
    select 1
      from public.persons as person
     where person.id <> caller_person
       and person.country_code is not null
  ) then
    raise exception 'Rejected market attempts wrote a country';
  end if;
end;
$$;

select set_config('request.jwt.claim.sub', '03510000-0000-4000-8000-000000000002', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"03510000-0000-4000-8000-000000000002","role":"authenticated"}',
  true
);
set local role authenticated;

do $$
declare
  other_result record;
  caller_person uuid := current_setting('identity.person_id')::uuid;
begin
  select * into other_result
    from public.complete_my_identity('Blair', 'Other', date '1988-02-02', 'QD');

  if other_result.person_id = caller_person or other_result.country_code is distinct from 'QD' then
    raise exception 'Second adult updated the first person';
  end if;
end;
$$;

reset role;

do $$
declare
  caller_person uuid := current_setting('identity.person_id')::uuid;
  other_country text;
begin
  select person.country_code
    into other_country
    from public.persons as person
   where person.id = caller_person;

  if other_country is distinct from 'ES' then
    raise exception 'Second adult changed the first person market';
  end if;
end;
$$;

set local role anon;

do $$
begin
  begin
    perform * from public.list_identity_markets();
    raise exception 'anon listed identity markets';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform * from public.complete_my_identity('Ana', 'Example', date '1990-01-01', 'ES');
    raise exception 'anon completed identity';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform * from public.ensure_my_identity();
    raise exception 'anon resolved identity';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

reset role;

do $$
begin
  if has_function_privilege('anon', 'public.list_identity_markets()', 'EXECUTE')
     or has_function_privilege('public', 'public.list_identity_markets()', 'EXECUTE')
     or has_function_privilege(
       'anon',
       'public.complete_my_identity(text,text,date,text)',
       'EXECUTE'
     )
     or has_function_privilege(
       'public',
       'public.complete_my_identity(text,text,date,text)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'public.identity_market_is_selectable(text)',
       'EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'public.identity_market_is_selectable(text)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'public.apply_spanish_identity_market_baseline()',
       'EXECUTE'
     )
     or has_table_privilege('authenticated', 'public.markets', 'SELECT')
     or has_table_privilege('authenticated', 'public.market_age_rules', 'SELECT')
     or has_table_privilege('anon', 'public.markets', 'SELECT')
     or has_table_privilege('anon', 'public.market_age_rules', 'SELECT') then
    raise exception 'Identity market privileges are broader than the caller RPCs';
  end if;
end;
$$;

rollback;
