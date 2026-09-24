-- Legal name collected at signup and matched to the rider's ID.
-- Locked once verification_status is verified.

alter table public.profiles
  add column if not exists first_name text,
  add column if not exists middle_name text,
  add column if not exists last_name text;

alter table public.pending_signups
  add column if not exists first_name text,
  add column if not exists middle_name text,
  add column if not exists last_name text;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_username text;
  v_first text;
  v_middle text;
  v_last text;
  v_full text;
begin
  v_username := nullif(trim(lower(coalesce(new.raw_user_meta_data->>'username', ''))), '');
  v_first := nullif(trim(coalesce(new.raw_user_meta_data->>'first_name', '')), '');
  v_middle := nullif(trim(coalesce(new.raw_user_meta_data->>'middle_name', '')), '');
  v_last := nullif(trim(coalesce(new.raw_user_meta_data->>'last_name', '')), '');
  v_full := nullif(trim(concat_ws(' ', v_first, v_middle, v_last)), '');

  if v_username is not null or v_full is not null then
    update auth.users
    set raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb)
      || jsonb_build_object(
        'name', coalesce(v_full, v_username),
        'full_name', coalesce(v_full, v_username)
      )
    where id = new.id;
  end if;

  insert into public.profiles (id, username, first_name, middle_name, last_name)
  values (new.id, v_username, v_first, v_middle, v_last)
  on conflict (id) do update set
    username = coalesce(excluded.username, public.profiles.username),
    first_name = coalesce(excluded.first_name, public.profiles.first_name),
    middle_name = coalesce(excluded.middle_name, public.profiles.middle_name),
    last_name = coalesce(excluded.last_name, public.profiles.last_name);
  return new;
end;
$$;

create or replace function public.sync_auth_user_metadata_from_profile()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_full text;
begin
  v_full := nullif(trim(concat_ws(
    ' ',
    nullif(trim(coalesce(new.first_name, '')), ''),
    nullif(trim(coalesce(new.middle_name, '')), ''),
    nullif(trim(coalesce(new.last_name, '')), '')
  )), '');
  update auth.users
  set raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb)
    || jsonb_strip_nulls(jsonb_build_object(
      'name', coalesce(v_full, new.username),
      'full_name', coalesce(v_full, new.username),
      'first_name', new.first_name,
      'middle_name', new.middle_name,
      'last_name', new.last_name
    ))
  where id = new.id;
  return new;
end;
$$;

drop trigger if exists profiles_sync_auth_user_metadata on public.profiles;
create trigger profiles_sync_auth_user_metadata
  after insert or update of username, first_name, middle_name, last_name
  on public.profiles
  for each row
  execute function public.sync_auth_user_metadata_from_profile();

create or replace function public.profiles_kyc_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.is_admin() then
    return new;
  end if;
  new.role := old.role;
  if new.verification_status = 'verified' then
    new.verification_status := old.verification_status;
    new.verified_at := old.verified_at;
  end if;
  if old.verification_status = 'verified' then
    new.first_name := old.first_name;
    new.middle_name := old.middle_name;
    new.last_name := old.last_name;
  end if;
  return new;
end;
$$;
