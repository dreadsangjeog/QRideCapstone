-- Current hourly rental fee. A rental copies this rate when the rider requests it.
-- Changing the fee later does not rewrite rate_per_hour, estimated_cost,
-- actual_cost, or penalty_fee on rentals that already exist.

create table if not exists public.rental_settings (
  id smallint primary key default 1,
  rate_per_hour numeric(10,2) not null default 50.00,
  updated_at timestamptz not null default now(),
  constraint rental_settings_singleton check (id = 1),
  constraint rental_settings_rate_positive check (
    rate_per_hour > 0 and rate_per_hour <= 10000
  )
);

insert into public.rental_settings (id, rate_per_hour)
values (1, 50.00)
on conflict (id) do nothing;

alter table public.rental_settings enable row level security;

drop policy if exists "rental_settings_select_authenticated" on public.rental_settings;
create policy "rental_settings_select_authenticated"
  on public.rental_settings for select
  to authenticated
  using (true);

drop policy if exists "rental_settings_update_admin" on public.rental_settings;
create policy "rental_settings_update_admin"
  on public.rental_settings for update
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- Keep the existing argument list so current app builds still call this.
-- The stored fee is used. The client value is ignored.
create or replace function public.request_rental_for_bike(
  p_bike_id       uuid,
  p_planned_mins  integer,
  p_rate_per_hour numeric
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rental_id uuid;
  v_status text;
  v_rate numeric;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated';
  end if;

  select verification_status into v_status
  from public.profiles
  where id = auth.uid();

  if v_status is distinct from 'verified' then
    raise exception 'kyc_not_verified';
  end if;

  if not exists (
    select 1 from public.bikes where id = p_bike_id and status = 'available'
  ) then
    raise exception 'bike_not_available';
  end if;

  if exists (
    select 1 from public.rentals
    where user_id = auth.uid() and status in ('pending', 'active')
  ) then
    raise exception 'already_has_active_rental';
  end if;

  select rate_per_hour into v_rate
  from public.rental_settings
  where id = 1;

  if v_rate is null or v_rate <= 0 then
    v_rate := 50;
  end if;

  insert into public.rentals (
    bike_id, user_id, status,
    planned_minutes, rate_per_hour, estimated_cost, started_at
  ) values (
    p_bike_id, auth.uid(), 'pending',
    p_planned_mins, v_rate,
    round((p_planned_mins::numeric / 60.0) * v_rate, 0),
    now()
  )
  returning id into v_rental_id;

  update public.bikes set status = 'rented' where id = p_bike_id;

  return v_rental_id;
end;
$$;

revoke all on function public.request_rental_for_bike(uuid, integer, numeric) from public;
grant execute on function public.request_rental_for_bike(uuid, integer, numeric) to authenticated;
