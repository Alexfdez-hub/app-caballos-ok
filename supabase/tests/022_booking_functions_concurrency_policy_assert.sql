do $$
declare
  booking_status text;
  pending_count integer;
  snapshot_acceptance uuid;
  live_acceptance_count integer;
begin
  select booking.status
    into booking_status
    from public.bookings as booking
   where booking.id = '99100000-0000-0000-0000-00000000b001';

  select count(*)
    into pending_count
    from public.booking_requirements as requirement
   where requirement.booking_id = '99100000-0000-0000-0000-00000000b001'
     and requirement.status = 'PENDING';

  if pending_count <> 0 then
    raise exception
      'Confirm persisted PENDING rows from a later policy snapshot, status=% pending=%',
      booking_status,
      pending_count;
  end if;

  if booking_status = 'CONFIRMED' then
    select (document_row.value ->> 'acceptance_id')::uuid
      into snapshot_acceptance
      from public.bookings as booking
      cross join lateral jsonb_array_elements(
        booking.booking_policy_snapshot -> 'documents'
      ) as document_row(value)
     where booking.id = '99100000-0000-0000-0000-00000000b001'
       and document_row.value ->> 'policy_code' = 'TERMS_ZQ'
     order by document_row.value ->> 'acceptance_id'
     limit 1;

    if snapshot_acceptance is null then
      raise exception
        'Confirmed booking stored a policy snapshot that does not match the acceptance used at evaluation';
    end if;

    select count(*)
      into live_acceptance_count
      from public.policy_acceptances as acceptance
     where acceptance.id = snapshot_acceptance;

    if live_acceptance_count <> 0 then
      raise exception
        'Policy handshake did not revoke the acceptance after evaluation';
    end if;
  elsif booking_status is distinct from 'APPROVED' then
    raise exception
      'Unexpected booking status after policy concurrency handshake: %',
      booking_status;
  end if;
end;
$$;

select 'concurrency_policy_assert_ok' as marker;
