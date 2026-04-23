-- Expose whether a Gmail is already tied to a confirmed auth account (signup guard).
-- Call from the app via RPC before sending signup OTP. Allows unconfirmed duplicates
-- to still use resend/signup flows.

create or replace function public.signup_email_already_confirmed(check_email text)
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
      and u.email_confirmed_at is not null
  );
$$;

revoke all on function public.signup_email_already_confirmed(text) from public;
grant execute on function public.signup_email_already_confirmed(text) to anon, authenticated;
