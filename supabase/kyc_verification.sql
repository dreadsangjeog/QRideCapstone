-- QRide identity verification (ID + live selfie)
-- Run in Supabase SQL Editor after the base schema.

alter table public.profiles
  add column if not exists verification_status text not null default 'unverified'
    check (verification_status in ('unverified', 'pending', 'verified', 'rejected'));

alter table public.profiles
  add column if not exists id_image_path text;

alter table public.profiles
  add column if not exists selfie_image_path text;

alter table public.profiles
  add column if not exists selfie_left_image_path text;

alter table public.profiles
  add column if not exists selfie_right_image_path text;

alter table public.profiles
  add column if not exists liveness_passed_at timestamptz;

alter table public.profiles
  add column if not exists verified_at timestamptz;

alter table public.profiles
  add column if not exists verification_note text;

-- Keep existing riders able to rent; new signups stay unverified.
update public.profiles
set verification_status = 'verified'
where verification_status = 'unverified';

-- Storage: private KYC images (path: {user_id}/id.jpg, selfie.jpg, selfie_left.jpg, selfie_right.jpg)
insert into storage.buckets (id, name, public)
values ('kyc-documents', 'kyc-documents', false)
on conflict (id) do nothing;

drop policy if exists "kyc_select_own_or_admin" on storage.objects;
create policy "kyc_select_own_or_admin"
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'kyc-documents'
    and (
      public.is_admin()
      or split_part(name, '/', 1) = auth.uid()::text
    )
  );

drop policy if exists "kyc_insert_own" on storage.objects;
create policy "kyc_insert_own"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'kyc-documents'
    and split_part(name, '/', 1) = auth.uid()::text
  );

drop policy if exists "kyc_update_own" on storage.objects;
create policy "kyc_update_own"
  on storage.objects for update
  to authenticated
  using (
    bucket_id = 'kyc-documents'
    and split_part(name, '/', 1) = auth.uid()::text
  )
  with check (
    bucket_id = 'kyc-documents'
    and split_part(name, '/', 1) = auth.uid()::text
  );

drop policy if exists "profiles_update_admin" on public.profiles;
create policy "profiles_update_admin"
  on public.profiles for update
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- Riders may not mark themselves verified or change role.
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
  return new;
end;
$$;

drop trigger if exists profiles_kyc_guard_trg on public.profiles;
create trigger profiles_kyc_guard_trg
  before update on public.profiles
  for each row
  execute function public.profiles_kyc_guard();

-- Block rental requests unless the rider is KYC-verified (server-side).
CREATE OR REPLACE FUNCTION public.request_rental_for_bike(
  p_bike_id       uuid,
  p_planned_mins  integer,
  p_rate_per_hour numeric
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rental_id uuid;
  v_status text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  SELECT verification_status INTO v_status
  FROM public.profiles
  WHERE id = auth.uid();

  IF v_status IS DISTINCT FROM 'verified' THEN
    RAISE EXCEPTION 'kyc_not_verified';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.bikes WHERE id = p_bike_id AND status = 'available'
  ) THEN
    RAISE EXCEPTION 'bike_not_available';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.rentals
    WHERE user_id = auth.uid() AND status IN ('pending', 'active')
  ) THEN
    RAISE EXCEPTION 'already_has_active_rental';
  END IF;

  INSERT INTO public.rentals (
    bike_id, user_id, status,
    planned_minutes, rate_per_hour, estimated_cost, started_at
  ) VALUES (
    p_bike_id, auth.uid(), 'pending',
    p_planned_mins, p_rate_per_hour,
    round((p_planned_mins::numeric / 60.0) * p_rate_per_hour, 2),
    now()
  )
  RETURNING id INTO v_rental_id;

  UPDATE public.bikes SET status = 'rented' WHERE id = p_bike_id;

  RETURN v_rental_id;
END;
$$;

REVOKE ALL ON FUNCTION public.request_rental_for_bike(uuid, integer, numeric) FROM public;
GRANT EXECUTE ON FUNCTION public.request_rental_for_bike(uuid, integer, numeric) TO authenticated;
