-- Admin can permanently remove a bike that is beyond repair.
-- Open rentals still block delete. Ended history keeps billing rows;
-- bike_id is cleared so the bike row can be removed.

alter table public.rentals
  alter column bike_id drop not null;

alter table public.rentals
  drop constraint if exists rentals_bike_id_fkey;

alter table public.rentals
  add constraint rentals_bike_id_fkey
  foreign key (bike_id) references public.bikes(id) on delete set null;

create or replace function public.admin_delete_bike(p_bike_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'Only administrators can delete bikes';
  end if;

  if not exists (select 1 from public.bikes where id = p_bike_id) then
    raise exception 'Bike not found';
  end if;

  if exists (
    select 1
    from public.rentals
    where bike_id = p_bike_id
      and status in ('pending', 'active')
  ) then
    raise exception
      'Cannot delete this bike while a rental is pending or active. End or reject that rental first.';
  end if;

  -- Detach closed history, then remove the bike (photo path goes with the row).
  update public.rentals
  set bike_id = null
  where bike_id = p_bike_id;

  delete from public.bikes
  where id = p_bike_id;
end;
$$;

revoke all on function public.admin_delete_bike(uuid) from public;
grant execute on function public.admin_delete_bike(uuid) to authenticated;
