-- Rider "Extend time" was returning success without changing the booking.
-- The check ran as a read the rider is allowed to do, then the write was
-- filtered by the admin-only update policy and the function still returned.
-- Run after 041_rental_and_alert_guards.sql. Safe to re-run.

create or replace function public.extend_rental(
  p_rental_id uuid,
  p_extra_mins integer
)
returns void
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
declare
  v_approved_at timestamptz;
  v_planned integer;
  v_rate numeric;
  v_new_mins integer;
  v_cost numeric;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated';
  end if;

  if p_extra_mins is null or p_extra_mins < 15 then
    raise exception 'extra_mins_must_be_at_least_15';
  end if;

  if p_extra_mins > 1440 then
    raise exception 'extra_mins_too_large';
  end if;

  select approved_at, planned_minutes, rate_per_hour
  into v_approved_at, v_planned, v_rate
  from public.rentals
  where id = p_rental_id
    and user_id = auth.uid()
    and status = 'active'
  for update;

  if not found then
    raise exception 'rental_not_active_or_not_owner';
  end if;

  if v_planned is null or v_planned < 1 then
    v_planned := 60;
  end if;
  if v_rate is null or v_rate <= 0 then
    v_rate := 50;
  end if;

  -- Extending after the booked time would bill overtime at the normal rate.
  -- The extra minute covers a slow network or a phone clock that runs late.
  if v_approved_at is not null
     and now() > v_approved_at + ((v_planned + 1) * interval '1 minute') then
    raise exception 'rental_in_overtime';
  end if;

  v_new_mins := v_planned + p_extra_mins;

  if v_approved_at is null then
    v_cost := round((v_new_mins::numeric / 60.0) * v_rate, 0);
  else
    begin
      v_cost := round(
        public.slot_charge(
          v_approved_at,
          v_approved_at + (v_new_mins * interval '1 minute'),
          v_rate
        ),
        0
      );
    exception
      when undefined_function then
        v_cost := round((v_new_mins::numeric / 60.0) * v_rate, 0);
    end;
  end if;

  update public.rentals
  set
    planned_minutes = v_new_mins,
    estimated_cost = v_cost
  where id = p_rental_id
    and user_id = auth.uid()
    and status = 'active';

  if not found then
    raise exception 'extension_not_saved';
  end if;
end;
$$;

revoke all on function public.extend_rental(uuid, integer) from public, anon;
grant execute on function public.extend_rental(uuid, integer) to authenticated;
