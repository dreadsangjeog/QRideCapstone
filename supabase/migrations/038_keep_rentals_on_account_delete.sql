-- Settled rentals stay after the rider deletes their account so reports and
-- history keep the ride. The rider's login is removed and rentals.user_id
-- becomes null. History shows that as a deleted account. Ride locations,
-- notifications, and verification files are still removed.
-- Run after 037_rate_history.sql.

alter table public.rentals
  alter column user_id drop not null;

do $$
declare
  c name;
begin
  select con.conname into c
  from pg_constraint con
  join pg_class rel on rel.oid = con.conrelid
  join pg_namespace nsp on nsp.oid = rel.relnamespace
  where nsp.nspname = 'public'
    and rel.relname = 'rentals'
    and con.contype = 'f'
    and pg_get_constraintdef(con.oid) ilike '%auth.users%';
  if c is not null then
    execute format('alter table public.rentals drop constraint %I', c);
  end if;
end $$;

alter table public.rentals
  drop constraint if exists rentals_user_id_fkey;

alter table public.rentals
  add constraint rentals_user_id_fkey
  foreign key (user_id) references auth.users(id) on delete set null;

create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_email text;
  v_role text;
begin
  if v_uid is null then
    raise exception 'not_signed_in';
  end if;

  perform pg_advisory_xact_lock(hashtext('qride_acct'), hashtext(v_uid::text));

  select p.role into v_role
  from public.profiles p
  where p.id = v_uid;

  if v_role = 'admin' then
    raise exception 'admin_cannot_self_delete';
  end if;

  perform 1
  from public.rentals r
  where r.user_id = v_uid
  for update;

  if exists (
    select 1
    from public.rentals r
    where r.user_id = v_uid
      and r.status in ('pending', 'active')
  ) then
    raise exception 'open_rental';
  end if;

  select u.email into v_email
  from auth.users u
  where u.id = v_uid;

  perform public.delete_kyc_files_for_user(v_uid);

  delete from public.notifications
  where user_id = v_uid;

  -- Drop the rider's GPS trail. The rental row itself stays for reports.
  delete from public.rental_locations
  where user_id = v_uid;

  delete from public.rental_last_location
  where user_id = v_uid;

  if exists (
    select 1
    from public.rentals r
    where r.user_id = v_uid
      and r.status in ('pending', 'active')
  ) then
    raise exception 'open_rental';
  end if;

  if v_email is not null then
    delete from public.pending_signups
    where lower(email) = lower(v_email);
  end if;

  delete from public.profiles
  where id = v_uid;

  -- Settled rentals remain. user_id is cleared by ON DELETE SET NULL.
  delete from auth.users
  where id = v_uid;
end;
$$;

revoke all on function public.delete_my_account() from public;
grant execute on function public.delete_my_account() to authenticated;
