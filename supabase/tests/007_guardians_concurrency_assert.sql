-- Final row assertions after both sessions have finished.
do $$
declare
  active_count integer;
  expired_count integer;
  fixture_status text;
  fixture_terms text;
  active_terms text;
  deadlock_waiters integer;
begin
  select count(*)
    into active_count
    from public.guardian_consents
   where guardian_relationship_id = '30000000-0000-0000-0000-0000000000aa'
     and status = 'ACTIVE';

  select count(*)
    into expired_count
    from public.guardian_consents
   where guardian_relationship_id = '30000000-0000-0000-0000-0000000000aa'
     and status = 'EXPIRED';

  select consent.status, consent.terms_version
    into fixture_status, fixture_terms
    from public.guardian_consents as consent
   where consent.id = '30000000-0000-0000-0000-0000000000ee';

  select consent.terms_version
    into active_terms
    from public.guardian_consents as consent
   where consent.guardian_relationship_id = '30000000-0000-0000-0000-0000000000aa'
     and consent.status = 'ACTIVE';

  if active_count <> 1 then
    raise exception 'Expected exactly one ACTIVE consent, found %', active_count;
  end if;

  if expired_count < 1 then
    raise exception 'Expected preserved EXPIRED historical consent, found %', expired_count;
  end if;

  if fixture_status is distinct from 'EXPIRED'
     or fixture_terms is distinct from 'expired-fixture' then
    raise exception
      'Historical fixture was not preserved as EXPIRED expired-fixture (status=%, terms=%)',
      fixture_status,
      fixture_terms;
  end if;

  if active_terms not in ('v-race-a', 'v-race-b') then
    raise exception 'Unexpected winning terms_version %', active_terms;
  end if;

  select count(*)
    into deadlock_waiters
    from pg_catalog.pg_stat_activity
   where wait_event_type = 'Lock'
     and query ilike '%grant_guardian_consent%';

  if deadlock_waiters <> 0 then
    raise exception 'Lock waiters remained after both sessions finished';
  end if;

  raise notice 'concurrency_final active=% expired=% winner_terms=% fixture=%',
    active_count, expired_count, active_terms, fixture_status;
end;
$$;

select
  id,
  terms_version,
  status,
  granted_at,
  expires_at,
  revoked_at
from public.guardian_consents
where guardian_relationship_id = '30000000-0000-0000-0000-0000000000aa'
order by granted_at, id;
