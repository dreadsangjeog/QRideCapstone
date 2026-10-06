-- Closes gaps found in review.
-- A bike and a rider can each have only one open rental, even when two
-- requests arrive at the same moment or staff mark a rented bike available.
-- A ride can be extended only before its booked time ends, so overtime stays
-- at 1.5x. Cancelling your own request no longer says "The admin declined".
-- Staff cannot record a negative charge. Riders can no longer send alerts to
-- other people's inboxes, and only the database can prune GPS history.
-- Run after 040_rider_rentals_through_functions.sql. Safe to re-run.

-- The old one-step functions skipped the ID check and staff approval.
-- rental_v2_migration.sql drops them, but schema.sql still creates them.
drop function if exists public.start_rental_for_bike(uuid);
drop function if exists public.end_rental_for_user(uuid);

-- Skipped with a notice if existing rows already break the rule. End or
-- cancel the extra rental, then run this file again.
do $$
begin
  if exists (
    select 1 from public.rentals
    where status in ('pending', 'active') and bike_id is not null
    group by bike_id
    having count(*) > 1
  ) then
    raise notice 'Skipped rentals_one_open_per_bike: a bike has more than one open rental.';
  else
    create unique index if not exists rentals_one_open_per_bike
      on public.rentals (bike_id)
      where status in ('pending', 'active');
  end if;

  if exists (
    select 1 from public.rentals
    where status in ('pending', 'active') and user_id is not null
    group by user_id
    having count(*) > 1
  ) then
    raise notice 'Skipped rentals_one_open_per_rider: a rider has more than one open rental.';
  else
    create unique index if not exists rentals_one_open_per_rider
      on public.rentals (user_id)
      where status in ('pending', 'active');
  end if;
end $$;

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

  if p_planned_mins is null or p_planned_mins < 15 or p_planned_mins > 1440 then
    raise exception 'invalid_planned_minutes';
  end if;

  -- The row locks make two requests from one rider, or two requests for one
  -- bike, run one after the other, so both cannot pass the checks below.
  select verification_status into v_status
  from public.profiles
  where id = auth.uid()
  for update;

  if v_status is distinct from 'verified' then
    raise exception 'kyc_not_verified';
  end if;

  perform 1
  from public.bikes
  where id = p_bike_id and status = 'available'
  for update;

  if not found then
    raise exception 'bike_not_available';
  end if;

  if exists (
    select 1 from public.rentals
    where bike_id = p_bike_id and status in ('pending', 'active')
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

revoke all on function public.request_rental_for_bike(uuid, integer, numeric) from public, anon;
grant execute on function public.request_rental_for_bike(uuid, integer, numeric) to authenticated;

create or replace function public.extend_rental(
  p_rental_id uuid,
  p_extra_mins integer
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_approved_at timestamptz;
  v_planned integer;
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

  select approved_at, planned_minutes
  into v_approved_at, v_planned
  from public.rentals
  where id = p_rental_id
    and user_id = auth.uid()
    and status = 'active'
  for update;

  if not found then
    raise exception 'rental_not_active_or_not_owner';
  end if;

  -- Extending after the booked time would bill overtime at the normal rate.
  -- The extra minute covers a slow network or a phone clock that runs late.
  if v_approved_at is not null
     and now() > v_approved_at + ((v_planned + 1) * interval '1 minute') then
    raise exception 'rental_in_overtime';
  end if;

  update public.rentals
  set
    planned_minutes = planned_minutes + p_extra_mins,
    estimated_cost = case
      when approved_at is null then round(
        ((planned_minutes + p_extra_mins)::numeric / 60.0) * rate_per_hour,
        0
      )
      else round(
        public.slot_charge(
          approved_at,
          approved_at + ((planned_minutes + p_extra_mins) * interval '1 minute'),
          rate_per_hour
        ),
        0
      )
    end
  where id = p_rental_id;
end;
$$;

revoke all on function public.extend_rental(uuid, integer) from public, anon;
grant execute on function public.extend_rental(uuid, integer) to authenticated;

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
  set status = 'rejected'
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

create or replace function public.end_rental_by_admin(
  p_rental_id   uuid,
  p_actual_cost numeric,
  p_penalty_fee numeric
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'not_admin';
  end if;

  if p_actual_cost is null or p_actual_cost < 0
     or p_penalty_fee is null or p_penalty_fee < 0
     or p_penalty_fee > p_actual_cost then
    raise exception 'invalid_amount';
  end if;

  update public.bikes b
  set status = 'available'
  from public.rentals r
  where r.id = p_rental_id and r.bike_id = b.id;

  update public.rentals
  set
    status      = 'ended',
    ended_at    = now(),
    actual_cost = p_actual_cost,
    penalty_fee = p_penalty_fee
  where id = p_rental_id and status = 'active';

  if not found then
    raise exception 'rental_not_active';
  end if;

  delete from public.rental_last_location where rental_id = p_rental_id;
end;
$$;

revoke all on function public.end_rental_by_admin(uuid, numeric, numeric) from public, anon;
grant execute on function public.end_rental_by_admin(uuid, numeric, numeric) to authenticated;

create or replace function public.notifications_on_rental_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_bike text;
begin
  select coalesce(nullif(trim(b.label), ''), b.code)
  into v_bike
  from public.bikes b
  where b.id = new.bike_id;

  v_bike := coalesce(v_bike, 'your bike');

  if tg_op = 'INSERT' and new.status = 'pending' then
    perform public.notify_all_admins(
      'rental_request',
      'New rental request',
      'A rider requested ' || v_bike || '.',
      jsonb_build_object(
        'rental_id', new.id,
        'bike_id', new.bike_id,
        'user_id', new.user_id
      )
    );
    return new;
  end if;

  if tg_op = 'UPDATE' and old.status is distinct from new.status then
    if new.status = 'active' then
      perform public.notify_user(
        new.user_id,
        'user',
        'rental_approved',
        'Rental approved!',
        'Your ride on ' || v_bike || ' has started. Enjoy!',
        jsonb_build_object('rental_id', new.id, 'bike_id', new.bike_id)
      );
    elsif new.status = 'rejected' and auth.uid() is distinct from new.user_id then
      -- A rider who cancels their own request is not told staff declined it.
      perform public.notify_user(
        new.user_id,
        'user',
        'rental_rejected',
        'Rental request declined',
        'The admin declined your request for ' || v_bike || '. The bike is available again.',
        jsonb_build_object('rental_id', new.id, 'bike_id', new.bike_id)
      );
    elsif new.status = 'ended' then
      perform public.notify_user(
        new.user_id,
        'user',
        'rental_ended',
        'Rental ended',
        case
          when coalesce(new.penalty_fee, 0) > 0 then
            'Total: ₱' || to_char(coalesce(new.actual_cost, 0), 'FM999990.00')
            || ' (includes ₱' || to_char(new.penalty_fee, 'FM999990.00') || ' penalty)'
          else
            'Total: ₱' || to_char(coalesce(new.actual_cost, 0), 'FM999990.00') || '. Thank you!'
        end,
        jsonb_build_object(
          'rental_id', new.id,
          'actual_cost', new.actual_cost,
          'penalty_fee', new.penalty_fee
        )
      );
    end if;
  end if;

  return new;
end;
$$;

-- Only the database's own triggers write to a rider's inbox.
revoke all on function public.notify_user(uuid, text, text, text, text, jsonb)
  from public, anon, authenticated;

create or replace function public.notify_all_admins(
  p_type text,
  p_title text,
  p_body text,
  p_data jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text;
  v_state text;
  v_title text := p_title;
  v_body text := p_body;
  v_data jsonb := coalesce(p_data, '{}'::jsonb);
begin
  -- Triggers and staff can send any alert. The rider app may only report
  -- logging out during its own open rental, and the text is written here.
  if pg_trigger_depth() = 0 and not public.is_admin() then
    if auth.uid() is null or p_type is distinct from 'rider_logout_active' then
      raise exception 'not_allowed';
    end if;

    select case when r.status = 'pending' then 'pending request' else 'active rental' end
    into v_state
    from public.rentals r
    where r.user_id = auth.uid() and r.status in ('pending', 'active')
    limit 1;

    if v_state is null then
      return;
    end if;

    if exists (
      select 1 from public.notifications n
      where n.type = 'rider_logout_active'
        and n.data ->> 'user_id' = auth.uid()::text
        and n.created_at > now() - interval '5 minutes'
    ) then
      return;
    end if;

    select nullif(trim(p.username), '') into v_name
    from public.profiles p
    where p.id = auth.uid();

    v_title := coalesce(
      v_name || ' logged out during a rental',
      'Rider logged out during a rental'
    );
    v_body := coalesce(v_name, 'A rider')
      || ' logged out while a rental was still ' || v_state
      || '. This may be suspicious — check the map and their ID.';
    v_data := jsonb_strip_nulls(
      jsonb_build_object('user_id', auth.uid(), 'username', v_name)
    );
  end if;

  insert into public.notifications (user_id, role_scope, type, title, body, data)
  select p.id, 'admin', p_type, v_title, v_body, v_data
  from public.profiles p
  where p.role = 'admin';
end;
$$;

revoke all on function public.notify_all_admins(text, text, text, jsonb) from public, anon;
grant execute on function public.notify_all_admins(text, text, text, jsonb) to authenticated;

-- Pruning runs from pg_cron or the SQL editor, never from the app.
do $$
begin
  if to_regprocedure('public.prune_rental_locations_older_than_7_days()') is not null then
    revoke all on function public.prune_rental_locations_older_than_7_days()
      from public, anon, authenticated;
  end if;
end $$;

-- Check afterwards:
--   select indexname from pg_indexes
--   where tablename = 'rentals' and indexname like 'rentals_one_open_%';
-- Expect rentals_one_open_per_bike and rentals_one_open_per_rider.
