do $$
declare
  target_equine_id uuid;
  current_count integer;
  primary_count integer;
begin
  select equine.id
    into target_equine_id
    from public.equines as equine
   where equine.name = 'Photo Race';

  select count(*) into current_count
    from public.equine_media as media
   where media.equine_id = target_equine_id
     and media.retired_at is null;
  if current_count <> 1 then
    raise exception 'Concurrent primary prepares left % current rows', current_count;
  end if;

  select count(*) into primary_count
    from public.equine_media as media
   where media.equine_id = target_equine_id
     and media.is_primary
     and media.retired_at is null
     and media.storage_path = (media.equine_id::text || '/' || media.id::text);
  if primary_count <> 1 then
    raise exception 'Concurrent prepares did not leave one canonical primary, got %', primary_count;
  end if;
end;
$$;
