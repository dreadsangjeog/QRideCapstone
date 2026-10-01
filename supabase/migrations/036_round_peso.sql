-- Round slot charges and extension totals to the nearest peso.
-- Run after 035_hourly_rate.sql. Existing saved totals are left as they are.

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

create or replace function public.extend_rental(
  p_rental_id uuid,
  p_extra_mins integer
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'not_authenticated';
  end if;

  if p_extra_mins is null or p_extra_mins < 15 then
    raise exception 'extra_mins_must_be_at_least_15';
  end if;

  update public.rentals
  set
    planned_minutes = planned_minutes + p_extra_mins,
    estimated_cost = round(
      ((planned_minutes + p_extra_mins)::numeric / 60.0) * rate_per_hour,
      0
    )
  where id = p_rental_id
    and user_id = auth.uid()
    and status = 'active';

  if not found then
    raise exception 'rental_not_active_or_not_owner';
  end if;
end;
$$;
