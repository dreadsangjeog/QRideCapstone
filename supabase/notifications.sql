-- QRide in-app notification inbox (history) for riders and admins.
-- Run in Supabase SQL Editor after the base schema.
-- Then: Database → Replication → enable Realtime for public.notifications

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  role_scope text not null check (role_scope in ('user', 'admin')),
  type text not null,
  title text not null,
  body text not null,
  data jsonb not null default '{}'::jsonb,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists notifications_user_created_idx
  on public.notifications (user_id, created_at desc);

create index if not exists notifications_user_unread_idx
  on public.notifications (user_id)
  where read_at is null;

alter table public.notifications enable row level security;

drop policy if exists "notifications_select_own" on public.notifications;
create policy "notifications_select_own"
  on public.notifications for select
  to authenticated
  using (user_id = auth.uid());

drop policy if exists "notifications_update_own" on public.notifications;
create policy "notifications_update_own"
  on public.notifications for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- Riders may insert their own timer-style rows (5-min / overtime).
drop policy if exists "notifications_insert_own_user" on public.notifications;
create policy "notifications_insert_own_user"
  on public.notifications for insert
  to authenticated
  with check (
    user_id = auth.uid()
    and role_scope = 'user'
  );

-- Helper: insert one inbox row (bypasses RLS via security definer).
create or replace function public.notify_user(
  p_user_id uuid,
  p_role_scope text,
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
begin
  if p_user_id is null then
    return;
  end if;
  insert into public.notifications (user_id, role_scope, type, title, body, data)
  values (p_user_id, p_role_scope, p_type, p_title, p_body, coalesce(p_data, '{}'::jsonb));
end;
$$;

revoke all on function public.notify_user(uuid, text, text, text, text, jsonb) from public;
grant execute on function public.notify_user(uuid, text, text, text, text, jsonb) to authenticated;

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
begin
  insert into public.notifications (user_id, role_scope, type, title, body, data)
  select p.id, 'admin', p_type, p_title, p_body, coalesce(p_data, '{}'::jsonb)
  from public.profiles p
  where p.role = 'admin';
end;
$$;

revoke all on function public.notify_all_admins(text, text, text, jsonb) from public;
grant execute on function public.notify_all_admins(text, text, text, jsonb) to authenticated;

-- Rentals → rider + admin notifications
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
    elsif new.status = 'rejected' then
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

drop trigger if exists notifications_on_rental_trg on public.rentals;
create trigger notifications_on_rental_trg
  after insert or update of status on public.rentals
  for each row
  execute function public.notifications_on_rental_change();

-- KYC status changes
create or replace function public.notifications_on_kyc_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.verification_status is not distinct from new.verification_status then
    return new;
  end if;

  if new.verification_status = 'pending' then
    perform public.notify_all_admins(
      'kyc_pending',
      'KYC to review',
      coalesce(new.username, 'A rider') || ' submitted ID verification.',
      jsonb_build_object('user_id', new.id, 'username', new.username)
    );
  elsif new.verification_status = 'verified' then
    perform public.notify_user(
      new.id,
      'user',
      'kyc_verified',
      'Identity verified',
      'Your ID was approved. You can rent bikes now.',
      '{}'::jsonb
    );
  elsif new.verification_status = 'rejected' then
    perform public.notify_user(
      new.id,
      'user',
      'kyc_rejected',
      'Identity check failed',
      'Your ID verification was rejected. Please submit again.',
      '{}'::jsonb
    );
  end if;

  return new;
end;
$$;

drop trigger if exists notifications_on_kyc_trg on public.profiles;
create trigger notifications_on_kyc_trg
  after update of verification_status on public.profiles
  for each row
  execute function public.notifications_on_kyc_change();

-- Realtime: add to publication if not already present
do $$
begin
  alter publication supabase_realtime add table public.notifications;
exception
  when duplicate_object then null;
  when undefined_object then null;
end $$;
