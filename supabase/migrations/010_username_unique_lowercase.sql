-- Run once in Supabase SQL Editor (after base schema.sql).
-- Username login: store usernames normalized to lowercase; enforce uniqueness.

update public.profiles
set username = lower(trim(username))
where username is not null;

create unique index if not exists profiles_username_lower_unique
  on public.profiles (lower(trim(username)))
  where username is not null and trim(username) <> '';

-- Optional: prevent NULL usernames on new rows (existing nulls allowed until backfilled)
-- alter table public.profiles alter column username set not null;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_username text;
begin
  v_username := nullif(trim(lower(coalesce(new.raw_user_meta_data->>'username', ''))), '');
  insert into public.profiles (id, username)
  values (new.id, v_username)
  on conflict (id) do update set username = excluded.username
  where excluded.username is not null;
  return new;
end;
$$;
