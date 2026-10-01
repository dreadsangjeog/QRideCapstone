-- Hourly fee changes take effect from the moment they are saved.
-- Completed rentals keep actual_cost and penalty_fee already recorded.
-- A ride still open uses the previous fee up to this moment and the new
-- fee after it. Pending requests, which have not started, use the new fee
-- for the whole booking.
-- Run after 036_round_peso.sql.

create table if not exists public.rental_rate_history (
  id bigint generated always as identity primary key,
  rate_per_hour numeric(10,2) not null,
  effective_at timestamptz not null default now(),
  constraint rental_rate_history_rate_positive check (
    rate_per_hour > 0 and rate_per_hour <= 10000
  )
);

create index if not exists rental_rate_history_effective_at_idx
  on public.rental_rate_history (effective_at);

insert into public.rental_rate_history (rate_per_hour, effective_at)
select s.rate_per_hour, s.updated_at
from public.rental_settings s
where s.id = 1
  and not exists (select 1 from public.rental_rate_history);

alter table public.rental_rate_history enable row level security;

drop policy if exists "rental_rate_history_select_authenticated"
  on public.rental_rate_history;
create policy "rental_rate_history_select_authenticated"
  on public.rental_rate_history for select
  to authenticated
  using (true);

grant select on public.rental_rate_history to authenticated;

create or replace function public.rate_at(p_at timestamptz, p_quoted numeric)
returns numeric
language sql
stable
set search_path = public
as $$
  select coalesce(
    (
      select h.rate_per_hour
      from public.rental_rate_history h
      where h.effective_at <= p_at
      order by h.effective_at desc
      limit 1
    ),
    p_quoted
  );
$$;

create or replace function public.slot_charge(
  p_start timestamptz,
  p_end timestamptz,
  p_quoted numeric
)
returns numeric
language plpgsql
stable
set search_path = public
as $$
declare
  v_sum numeric := 0;
  v_from timestamptz;
  v_to timestamptz;
  rec record;
begin
  if p_start is null or p_end is null or p_end <= p_start then
    return 0;
  end if;

  v_from := p_start;
  for rec in
    select effective_at
    from public.rental_rate_history
    where effective_at > p_start and effective_at < p_end
    order by effective_at
  loop
    v_to := rec.effective_at;
    v_sum := v_sum
      + (extract(epoch from (v_to - v_from)) / 3600.0)
      * public.rate_at(v_from, p_quoted);
    v_from := v_to;
  end loop;

  v_sum := v_sum
    + (extract(epoch from (p_end - v_from)) / 3600.0)
    * public.rate_at(v_from, p_quoted);
  return v_sum;
end;
$$;

create or replace function public.rental_settings_apply_rate()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'UPDATE'
     and new.rate_per_hour is not distinct from old.rate_per_hour then
    return new;
  end if;

  insert into public.rental_rate_history (rate_per_hour, effective_at)
  values (new.rate_per_hour, now());

  update public.rentals
  set rate_per_hour = new.rate_per_hour,
      estimated_cost = round(
        (planned_minutes::numeric / 60.0) * new.rate_per_hour,
        0
      )
  where status = 'pending';

  update public.rentals r
  set estimated_cost = round(
    public.slot_charge(
      r.approved_at,
      r.approved_at + (r.planned_minutes * interval '1 minute'),
      r.rate_per_hour
    ),
    0
  )
  where r.status = 'active'
    and r.approved_at is not null;

  return new;
end;
$$;

drop trigger if exists rental_settings_apply_rate on public.rental_settings;
create trigger rental_settings_apply_rate
  after insert or update of rate_per_hour on public.rental_settings
  for each row
  execute function public.rental_settings_apply_rate();

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
  where id = p_rental_id
    and user_id = auth.uid()
    and status = 'active';

  if not found then
    raise exception 'rental_not_active_or_not_owner';
  end if;
end;
$$;
