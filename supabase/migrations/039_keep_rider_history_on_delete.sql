-- Settled rentals and their charges stay after the rider deletes their
-- account. Every foreign key on rentals.user_id is dropped first so deleting
-- the profile or the login cannot cascade-delete history or sales.
-- The rider's name is copied onto the rental before the profile is removed.
-- Run after 038_keep_rentals_on_account_delete.sql.

alter table public.rentals
  add column if not exists rider_name text;

alter table public.rentals
  alter column user_id drop not null;

do $$
declare
  r record;
begin
  for r in
    select con.conname
    from pg_constraint con
    join pg_class rel on rel.oid = con.conrelid
    join pg_namespace nsp on nsp.oid = rel.relnamespace
    join lateral unnest(con.conkey) as cols(attnum) on true
    join pg_attribute att
      on att.attrelid = rel.oid
     and att.attnum = cols.attnum
    where nsp.nspname = 'public'
      and rel.relname = 'rentals'
      and con.contype = 'f'
      and att.attname = 'user_id'
  loop
    execute format('alter table public.rentals drop constraint %I', r.conname);
  end loop;
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

  -- Keep the name on each settled ride so history and sales stay tied to
  -- that person after the login is gone.
  update public.rentals r
  set rider_name = coalesce(
    nullif(
      trim(concat_ws(
        ' ',
        nullif(trim(p.first_name), ''),
        nullif(trim(p.middle_name), ''),
        nullif(trim(p.last_name), '')
      )),
      ''
    ),
    nullif(trim(p.username), ''),
    'Deleted account'
  )
  from public.profiles p
  where r.user_id = v_uid
    and p.id = v_uid
    and (r.rider_name is null or btrim(r.rider_name) = '');

  perform public.delete_kyc_files_for_user(v_uid);

  delete from public.notifications
  where user_id = v_uid;

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
  -- Do not delete from public.rentals.
  delete from auth.users
  where id = v_uid;
end;
$$;

revoke all on function public.delete_my_account() from public;
grant execute on function public.delete_my_account() to authenticated;
