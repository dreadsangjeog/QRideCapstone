-- True if auth.users already has this email (confirmed or not). Used for deferred signup.

create or replace function public.signup_auth_email_taken(check_email text)
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select exists (
    select 1
    from auth.users u
    where lower(trim(u.email)) = lower(trim(check_email))
  );
$$;

revoke all on function public.signup_auth_email_taken(text) from public;
grant execute on function public.signup_auth_email_taken(text) to anon, authenticated;
