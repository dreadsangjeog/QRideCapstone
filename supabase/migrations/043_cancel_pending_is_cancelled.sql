-- A rider who cancels a pending request was stored as rejected, so admin
-- history showed it as a staff decline. Cancelled is its own status.
-- Run after 042_extend_rental_applies.sql. Safe to re-run.

alter table public.rentals
  drop constraint if exists rentals_status_check;

alter table public.rentals
  add constraint rentals_status_check
  check (status in ('pending', 'active', 'ended', 'rejected', 'cancelled'));

create or replace function public.cancel_rental_by_user(p_rental_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_bike_id uuid;
begin
  -- Checking and cancelling in one statement means an approval that lands at
  -- the same moment is not overwritten.
  update public.rentals
  set status = 'cancelled'
  where id = p_rental_id
    and user_id = auth.uid()
    and status = 'pending'
  returning bike_id into v_bike_id;

  if not found then
    raise exception 'rental_not_found_or_not_pending';
  end if;

  update public.bikes
  set status = 'available'
  where id = v_bike_id and status = 'rented';
end;
$$;

revoke all on function public.cancel_rental_by_user(uuid) from public, anon;
grant execute on function public.cancel_rental_by_user(uuid) to authenticated;
