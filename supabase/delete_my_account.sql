-- Rider self-service account deletion.
-- Run once in the Supabase SQL Editor.
-- Hard block: pending or active rental (bike not returned) cannot be deleted.

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

  -- Serialize delete vs a new rental request from the same rider.
  perform pg_advisory_xact_lock(hashtext('qride_acct'), hashtext(v_uid::text));

  select p.role into v_role
  from public.profiles p
  where p.id = v_uid;

  if v_role = 'admin' then
    raise exception 'admin_cannot_self_delete';
  end if;

  -- Lock this rider's rental rows so status cannot change mid-delete.
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

  delete from storage.objects
  where bucket_id = 'kyc-documents'
    and split_part(name, '/', 1) = v_uid::text;

  delete from public.notifications
  where user_id = v_uid;

  -- Only settled rides may be removed. Open rentals are never deleted.
  delete from public.rental_locations
  where user_id = v_uid
    and rental_id in (
      select id from public.rentals
      where user_id = v_uid and status in ('ended', 'rejected')
    );

  delete from public.rental_last_location
  where user_id = v_uid
    and rental_id in (
      select id from public.rentals
      where user_id = v_uid and status in ('ended', 'rejected')
    );

  delete from public.rentals
  where user_id = v_uid
    and status in ('ended', 'rejected');

  -- Final guard: any leftover rental (including a race insert) aborts everything.
  if exists (
    select 1
    from public.rentals r
    where r.user_id = v_uid
  ) then
    raise exception 'open_rental';
  end if;

  if v_email is not null then
    delete from public.pending_signups
    where lower(email) = lower(v_email);
  end if;

  delete from public.profiles
  where id = v_uid;

  delete from auth.users
  where id = v_uid;
end;
$$;

revoke all on function public.delete_my_account() from public;
grant execute on function public.delete_my_account() to authenticated;
