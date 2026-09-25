-- Removing a rider also removes their ID and selfie files from storage.

create or replace function public.delete_kyc_files_for_user(p_uid uuid)
returns void
language plpgsql
security definer
set search_path = public, storage
as $$
begin
  if p_uid is null then
    return;
  end if;
  perform set_config('storage.allow_delete_query', 'true', true);
  delete from storage.objects
  where bucket_id = 'kyc-documents'
    and split_part(name, '/', 1) = p_uid::text;
end;
$$;

revoke all on function public.delete_kyc_files_for_user(uuid) from public;
revoke all on function public.delete_kyc_files_for_user(uuid) from anon, authenticated;

create or replace function public.profiles_delete_kyc_files()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.delete_kyc_files_for_user(old.id);
  return old;
end;
$$;

drop trigger if exists profiles_delete_kyc_files on public.profiles;
create trigger profiles_delete_kyc_files
  before delete on public.profiles
  for each row
  execute function public.profiles_delete_kyc_files();

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
