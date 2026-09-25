alter table public.profiles
  add column if not exists birthdate date;

alter table public.pending_signups
  add column if not exists birthdate date;

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
  v_birth date;
begin
  v_username := nullif(trim(lower(coalesce(new.raw_user_meta_data->>'username', ''))), '');
  v_first := nullif(trim(coalesce(new.raw_user_meta_data->>'first_name', '')), '');
  v_middle := nullif(trim(coalesce(new.raw_user_meta_data->>'middle_name', '')), '');
  v_last := nullif(trim(coalesce(new.raw_user_meta_data->>'last_name', '')), '');
  v_full := nullif(trim(concat_ws(' ', v_first, v_middle, v_last)), '');
  begin
    v_birth := nullif(trim(coalesce(new.raw_user_meta_data->>'birthdate', '')), '')::date;
  exception when others then
    v_birth := null;
  end;

  if v_username is not null or v_full is not null then
    update auth.users
    set raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb)
      || jsonb_build_object(
        'name', coalesce(v_full, v_username),
        'full_name', coalesce(v_full, v_username)
      )
    where id = new.id;
  end if;

  insert into public.profiles (id, username, first_name, middle_name, last_name, birthdate)
  values (new.id, v_username, v_first, v_middle, v_last, v_birth)
  on conflict (id) do update set
    username = coalesce(excluded.username, public.profiles.username),
    first_name = coalesce(excluded.first_name, public.profiles.first_name),
    middle_name = coalesce(excluded.middle_name, public.profiles.middle_name),
    last_name = coalesce(excluded.last_name, public.profiles.last_name),
    birthdate = coalesce(excluded.birthdate, public.profiles.birthdate);
  return new;
end;
$$;

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
    new.birthdate := old.birthdate;
  end if;
  return new;
end;
$$;
