-- Add explicit role-based access control to profiles.
-- Migrates from legacy boolean `is_admin` to `role` enum-like text.

alter table public.profiles
  add column if not exists role text;

update public.profiles
set role = case when coalesce(is_admin, false) then 'admin' else 'user' end
where role is null or role = '';

alter table public.profiles
  alter column role set not null;

alter table public.profiles
  alter column role set default 'user';

alter table public.profiles
  add constraint if not exists profiles_role_check
  check (role in ('user','admin'));

-- Drop legacy column if it exists.
alter table public.profiles
  drop column if exists is_admin;

-- Update admin helper to use role.
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select (p.role = 'admin') from public.profiles p where p.id = auth.uid()),
    false
  );
$$;

