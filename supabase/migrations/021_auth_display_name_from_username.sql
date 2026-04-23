-- Sync usernames into auth.users user metadata so it appears in
-- Authentication → Users list (Display name / name fields).

create or replace function public.sync_auth_user_metadata_from_profile()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update auth.users
  set raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb)
    || jsonb_build_object('name', new.username, 'full_name', new.username)
  where id = new.id
    and new.username is not null
    and trim(new.username) <> '';
  return new;
end;
$$;

drop trigger if exists profiles_sync_auth_display_name on public.profiles;
drop trigger if exists profiles_sync_auth_user_metadata on public.profiles;
create trigger profiles_sync_auth_user_metadata
  after insert or update of username on public.profiles
  for each row
  execute function public.sync_auth_user_metadata_from_profile();

