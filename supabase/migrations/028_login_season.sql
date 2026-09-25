-- Shared login season. Anyone can read it (login is public).
-- Only an admin can change it, and both the website and the app follow it.

create table if not exists public.app_settings (
  key text primary key,
  value text not null,
  updated_at timestamptz not null default now()
);

insert into public.app_settings (key, value)
values ('login_season', 'winter')
on conflict (key) do nothing;

alter table public.app_settings enable row level security;

drop policy if exists app_settings_read on public.app_settings;
create policy app_settings_read
  on public.app_settings
  for select
  to anon, authenticated
  using (true);

drop policy if exists app_settings_admin_update on public.app_settings;
create policy app_settings_admin_update
  on public.app_settings
  for update
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

grant select on public.app_settings to anon, authenticated;
grant update on public.app_settings to authenticated;

do $$
begin
  alter publication supabase_realtime add table public.app_settings;
exception
  when duplicate_object then null;
end $$;
