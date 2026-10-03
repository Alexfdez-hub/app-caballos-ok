-- Issue #41 stage 031. Adult self-create for Option A.
-- One transaction creates the equine, 100 percent PERSON ownership and
-- the same PERSON as active PRIMARY_MANAGER. No media, no Storage policy,
-- no center or guardian create path. Not deployed by this migration file.

create function public.create_my_equine(
  p_name text,
  p_equine_type text,
  p_birth_date date default null,
  p_sex text default null,
  p_breed text default null,
  p_height_cm numeric default null,
  p_description text default null,
  p_temperament_description text default null
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller_person_id uuid;
  caller_dob date;
  caller_market text;
  adult_age integer;
  rule_count integer;
  equine_id uuid;
  established_at timestamptz := now();
begin
  select caller.person_id
    into caller_person_id
    from public.resolve_session_caller() as caller;

  if p_name is null or btrim(p_name) = '' then
    raise exception using
      errcode = '22023',
      message = 'Equine name is required';
  end if;

  if p_equine_type is distinct from 'HORSE'
     and p_equine_type is distinct from 'PONY' then
    raise exception using
      errcode = '22023',
      message = 'Equine type is not allowed';
  end if;

  select person.date_of_birth, person.country_code
    into caller_dob, caller_market
    from public.persons as person
   where person.id = caller_person_id;

  select count(*)
    into rule_count
    from public.market_age_rules as rule
   where rule.country_code = caller_market
     and rule.effective_from <= current_date
     and (rule.effective_to is null or current_date < rule.effective_to);

  if caller_dob is null
     or caller_market is null
     or btrim(caller_market) = ''
     or rule_count is distinct from 1 then
    raise exception using
      errcode = 'P0001',
      message = 'Equine creation is not available';
  end if;

  select rule.legal_adult_age
    into adult_age
    from public.market_age_rules as rule
   where rule.country_code = caller_market
     and rule.effective_from <= current_date
     and (rule.effective_to is null or current_date < rule.effective_to);

  if extract(year from age(current_date, caller_dob))::integer < adult_age then
    raise exception using
      errcode = 'P0001',
      message = 'Equine creation is not available';
  end if;

  insert into public.equines (
    name,
    equine_type,
    birth_date,
    sex,
    breed,
    height_cm,
    description,
    temperament_description,
    status,
    visibility_status
  ) values (
    btrim(p_name),
    p_equine_type,
    p_birth_date,
    nullif(btrim(p_sex), ''),
    nullif(btrim(p_breed), ''),
    p_height_cm,
    nullif(btrim(p_description), ''),
    nullif(btrim(p_temperament_description), ''),
    'ACTIVE',
    'PRIVATE'
  ) returning id into equine_id;

  insert into public.equine_ownerships (
    equine_id,
    owner_type,
    owner_person_id,
    ownership_percentage,
    status,
    started_at,
    ended_at
  ) values (
    equine_id,
    'PERSON',
    caller_person_id,
    100,
    'ACTIVE',
    established_at,
    null
  );

  insert into public.equine_management_assignments (
    equine_id,
    manager_type,
    manager_person_id,
    management_role,
    status,
    valid_from,
    valid_until,
    granted_by_person_id
  ) values (
    equine_id,
    'PERSON',
    caller_person_id,
    'PRIMARY_MANAGER',
    'ACTIVE',
    established_at,
    null,
    caller_person_id
  );

  perform public.record_audit_event(
    'equine_created',
    'equines',
    equine_id,
    jsonb_build_object(
      'equine_type', p_equine_type,
      'visibility_status', 'PRIVATE'
    )
  );

  return equine_id;
end;
$$;

comment on function public.create_my_equine(text, text, date, text, text, numeric, text, text) is
  'Authenticated adult creates one PRIVATE ACTIVE equine for their own PERSON, with 100 percent PERSON ownership and an active PERSON PRIMARY_MANAGER in the same transaction. Identity and market come from auth.uid(). No person, account, owner, manager or center argument. Not a media or Storage operation.';

revoke all on function public.create_my_equine(text, text, date, text, text, numeric, text, text)
  from public, anon, authenticated;
grant execute on function public.create_my_equine(text, text, date, text, text, numeric, text, text)
  to authenticated;

create function public.list_my_equines()
returns table (
  equine_id uuid,
  equine_name text,
  equine_type text,
  status text,
  visibility_status text,
  is_owner boolean,
  is_primary_manager boolean
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  caller_person_id uuid;
begin
  select caller.person_id
    into caller_person_id
    from public.resolve_session_caller() as caller;

  return query
  select
    equine.id,
    equine.name,
    equine.equine_type,
    equine.status,
    equine.visibility_status,
    public.has_effective_equine_person_ownership(
      caller_person_id,
      equine.id
    ) as is_owner,
    public.has_active_equine_management_role(
      caller_person_id,
      equine.id,
      'PRIMARY_MANAGER'
    ) as is_primary_manager
  from public.equines as equine
  where public.has_effective_equine_person_ownership(
          caller_person_id,
          equine.id
        )
     or public.has_active_equine_management_role(
          caller_person_id,
          equine.id,
          'PRIMARY_MANAGER'
        )
     or public.has_active_equine_management_role(
          caller_person_id,
          equine.id,
          'CO_MANAGER'
        )
     or public.has_active_equine_management_role(
          caller_person_id,
          equine.id,
          'AUTHORIZED_MANAGER'
        )
  order by equine.created_at desc, equine.id;
end;
$$;

comment on function public.list_my_equines() is
  'Lists equines the caller PERSON currently owns or manages. Ownership is effective only when ACTIVE, ended_at is null and started_at <= now(). Management is effective only when ACTIVE, valid_until is null and valid_from <= now(). Ended, expired and future rows do not authorize. Does not accept an identity argument and does not return other people, centers or media.';

revoke all on function public.list_my_equines() from public, anon, authenticated;
grant execute on function public.list_my_equines() to authenticated;

create function public.get_my_equine(p_equine_id uuid)
returns table (
  equine_id uuid,
  equine_name text,
  equine_type text,
  birth_date date,
  sex text,
  breed text,
  height_cm numeric,
  description text,
  temperament_description text,
  status text,
  visibility_status text,
  is_owner boolean,
  is_primary_manager boolean
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  caller_person_id uuid;
begin
  if p_equine_id is null then
    raise exception using
      errcode = '22023',
      message = 'Equine is not available';
  end if;

  select caller.person_id
    into caller_person_id
    from public.resolve_session_caller() as caller;

  return query
  select
    equine.id,
    equine.name,
    equine.equine_type,
    equine.birth_date,
    equine.sex,
    equine.breed,
    equine.height_cm,
    equine.description,
    equine.temperament_description,
    equine.status,
    equine.visibility_status,
    public.has_effective_equine_person_ownership(
      caller_person_id,
      equine.id
    ),
    public.has_active_equine_management_role(
      caller_person_id,
      equine.id,
      'PRIMARY_MANAGER'
    )
  from public.equines as equine
  where equine.id = p_equine_id
    and (
      public.has_effective_equine_person_ownership(
        caller_person_id,
        equine.id
      )
      or public.has_active_equine_management_role(
        caller_person_id,
        equine.id,
        'PRIMARY_MANAGER'
      )
      or public.has_active_equine_management_role(
        caller_person_id,
        equine.id,
        'CO_MANAGER'
      )
      or public.has_active_equine_management_role(
        caller_person_id,
        equine.id,
        'AUTHORIZED_MANAGER'
      )
    );

  if not found then
    raise exception using
      errcode = '42501',
      message = 'Equine is not available';
  end if;
end;
$$;

comment on function public.get_my_equine(uuid) is
  'Returns one equine the caller PERSON currently owns or manages. Uses the same effective ownership and management predicates as list_my_equines. A missing, foreign, ended, expired or future relationship raises the same unavailable error. No media and no other person.';

revoke all on function public.get_my_equine(uuid) from public, anon, authenticated;
grant execute on function public.get_my_equine(uuid) to authenticated;
