-- Bike photos for the fleet: staff upload, riders see the bike they scanned.

alter table public.bikes
  add column if not exists photo_path text;

insert into storage.buckets (id, name, public)
values ('bike-photos', 'bike-photos', true)
on conflict (id) do update set public = true;

drop policy if exists "bike_photos_public_read" on storage.objects;
create policy "bike_photos_public_read"
  on storage.objects for select
  using (bucket_id = 'bike-photos');

drop policy if exists "bike_photos_admin_insert" on storage.objects;
create policy "bike_photos_admin_insert"
  on storage.objects for insert
  to authenticated
  with check (bucket_id = 'bike-photos' and public.is_admin());

drop policy if exists "bike_photos_admin_update" on storage.objects;
create policy "bike_photos_admin_update"
  on storage.objects for update
  to authenticated
  using (bucket_id = 'bike-photos' and public.is_admin())
  with check (bucket_id = 'bike-photos' and public.is_admin());

drop policy if exists "bike_photos_admin_delete" on storage.objects;
create policy "bike_photos_admin_delete"
  on storage.objects for delete
  to authenticated
  using (bucket_id = 'bike-photos' and public.is_admin());
