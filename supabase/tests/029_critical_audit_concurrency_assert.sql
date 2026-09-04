-- Exact audit counts after the concurrent grant race.
do $$
declare
  active_count integer;
  granted_count integer;
  revoked_count integer;
begin
  select count(*)
    into active_count
    from public.guardian_consents
   where guardian_relationship_id = '98800000-0000-0000-0000-00000000aa'
     and status = 'ACTIVE';

  select count(*)
    into granted_count
    from public.audit_events
   where event_type = 'guardian_consent_granted'
     and metadata->>'guardian_relationship_id' = '98800000-0000-0000-0000-00000000aa';

  select count(*)
    into revoked_count
    from public.audit_events
   where event_type = 'guardian_consent_revoked'
     and metadata->>'guardian_relationship_id' = '98800000-0000-0000-0000-00000000aa';

  if active_count <> 1 then
    raise exception 'Expected exactly one ACTIVE consent, found %', active_count;
  end if;

  if granted_count <> 1 then
    raise exception 'Expected exactly one guardian_consent_granted audit, found %', granted_count;
  end if;

  if revoked_count <> 0 then
    raise exception 'Concurrent grant wrote a revoke audit, found %', revoked_count;
  end if;
end;
$$;

select id, terms_version, status
  from public.guardian_consents
 where guardian_relationship_id = '98800000-0000-0000-0000-00000000aa'
 order by granted_at, id;

select event_type, entity_id, actor_account_id, metadata
  from public.audit_events
 where metadata->>'guardian_relationship_id' = '98800000-0000-0000-0000-00000000aa';
