do $$
declare
  equine_id uuid;
begin
  select equine.id
    into equine_id
    from public.equines as equine
   where equine.name = 'Photo Race';
  perform set_config('photo.equine_id', equine_id::text, false);
end;
$$;

begin;

select set_config(
  'request.jwt.claim.sub',
  '03220000-0000-4000-8000-000000000001',
  true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"03220000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);

set local role authenticated;

select public.authorize_my_equine_photo_prepare(
  current_setting('photo.equine_id')::uuid,
  true
) as session_a_photo;

commit;
