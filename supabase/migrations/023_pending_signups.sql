-- Holds signup intent (hashed password + OTP) until the user completes registration.
-- Auth user is created only by Edge Function `complete-signup`, not by GoTrue signUp.

create table if not exists public.pending_signups (
  email text primary key,
  username text not null,
  password_hash text not null,
  otp_hash text not null,
  expires_at timestamptz not null,
  created_at timestamptz not null default now()
);

create index if not exists pending_signups_expires_at_idx
  on public.pending_signups (expires_at);

create index if not exists pending_signups_username_lower_idx
  on public.pending_signups (lower(trim(username)));

alter table public.pending_signups enable row level security;
-- Intentionally no policies: only the service role (Edge Functions) may access this table.
