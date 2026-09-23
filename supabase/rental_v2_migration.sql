-- ============================================================
-- QRide — Rental v2 migration
-- Run this ONCE in the Supabase SQL Editor (after base schema.sql).
-- Adds: pending/rejected status, duration, pricing, penalty, realtime.
-- ============================================================

-- -------------------------------------------------------
-- 1. Extend rentals status constraint
-- -------------------------------------------------------
ALTER TABLE public.rentals
  DROP CONSTRAINT IF EXISTS rentals_status_check;

ALTER TABLE public.rentals
  ADD CONSTRAINT rentals_status_check
  CHECK (status IN ('pending', 'active', 'ended', 'rejected'));

-- Default is now 'pending' — admins approve before tracking starts.
ALTER TABLE public.rentals
  ALTER COLUMN status SET DEFAULT 'pending';

-- -------------------------------------------------------
-- 2. New columns
-- -------------------------------------------------------
ALTER TABLE public.rentals
  ADD COLUMN IF NOT EXISTS planned_minutes  integer        NOT NULL DEFAULT 60,
  ADD COLUMN IF NOT EXISTS rate_per_hour    numeric(10,2)  NOT NULL DEFAULT 50.00,
  ADD COLUMN IF NOT EXISTS estimated_cost   numeric(10,2),
  ADD COLUMN IF NOT EXISTS actual_cost      numeric(10,2),
  ADD COLUMN IF NOT EXISTS penalty_fee      numeric(10,2)  NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS approved_at      timestamptz;

-- -------------------------------------------------------
-- 3. Drop old single-step RPCs
-- -------------------------------------------------------
DROP FUNCTION IF EXISTS public.start_rental_for_bike(uuid);
DROP FUNCTION IF EXISTS public.end_rental_for_user(uuid);

-- -------------------------------------------------------
-- 4. request_rental_for_bike  (user → creates pending row)
-- -------------------------------------------------------
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
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.profiles
    WHERE id = auth.uid() AND verification_status = 'verified'
  ) THEN
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

  -- Mark bike reserved immediately so no other user can request it.
  UPDATE public.bikes SET status = 'rented' WHERE id = p_bike_id;

  RETURN v_rental_id;
END;
$$;

REVOKE ALL ON FUNCTION public.request_rental_for_bike(uuid, integer, numeric) FROM public;
GRANT EXECUTE ON FUNCTION public.request_rental_for_bike(uuid, integer, numeric) TO authenticated;

-- -------------------------------------------------------
-- 5. cancel_rental_by_user  (user cancels before admin approves)
-- -------------------------------------------------------
CREATE OR REPLACE FUNCTION public.cancel_rental_by_user(p_rental_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.rentals
    WHERE id = p_rental_id AND user_id = auth.uid() AND status = 'pending'
  ) THEN
    RAISE EXCEPTION 'rental_not_found_or_not_pending';
  END IF;

  UPDATE public.bikes b
  SET status = 'available'
  FROM public.rentals r
  WHERE r.id = p_rental_id AND r.bike_id = b.id;

  UPDATE public.rentals SET status = 'rejected' WHERE id = p_rental_id;
END;
$$;

REVOKE ALL ON FUNCTION public.cancel_rental_by_user(uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.cancel_rental_by_user(uuid) TO authenticated;

-- -------------------------------------------------------
-- 6. approve_rental  (admin confirms request → starts rental)
-- -------------------------------------------------------
CREATE OR REPLACE FUNCTION public.approve_rental(p_rental_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'not_admin';
  END IF;

  UPDATE public.rentals
  SET status = 'active', approved_at = now()
  WHERE id = p_rental_id AND status = 'pending';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'rental_not_found_or_not_pending';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.approve_rental(uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.approve_rental(uuid) TO authenticated;

-- -------------------------------------------------------
-- 7. reject_rental  (admin declines request)
-- -------------------------------------------------------
CREATE OR REPLACE FUNCTION public.reject_rental(p_rental_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'not_admin';
  END IF;

  UPDATE public.bikes b
  SET status = 'available'
  FROM public.rentals r
  WHERE r.id = p_rental_id AND r.bike_id = b.id AND r.status = 'pending';

  UPDATE public.rentals
  SET status = 'rejected'
  WHERE id = p_rental_id AND status = 'pending';
END;
$$;

REVOKE ALL ON FUNCTION public.reject_rental(uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.reject_rental(uuid) TO authenticated;

-- -------------------------------------------------------
-- 8. end_rental_by_admin  (admin ends active rental with cost + penalty)
-- -------------------------------------------------------
CREATE OR REPLACE FUNCTION public.end_rental_by_admin(
  p_rental_id   uuid,
  p_actual_cost numeric,
  p_penalty_fee numeric
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'not_admin';
  END IF;

  UPDATE public.bikes b
  SET status = 'available'
  FROM public.rentals r
  WHERE r.id = p_rental_id AND r.bike_id = b.id;

  UPDATE public.rentals
  SET
    status      = 'ended',
    ended_at    = now(),
    actual_cost = p_actual_cost,
    penalty_fee = p_penalty_fee
  WHERE id = p_rental_id AND status = 'active';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'rental_not_active';
  END IF;

  -- Remove last-known location so the bike disappears from the live map.
  DELETE FROM public.rental_last_location WHERE rental_id = p_rental_id;
END;
$$;

REVOKE ALL ON FUNCTION public.end_rental_by_admin(uuid, numeric, numeric) FROM public;
GRANT EXECUTE ON FUNCTION public.end_rental_by_admin(uuid, numeric, numeric) TO authenticated;

-- -------------------------------------------------------
-- 9. Enable Supabase Realtime for the rentals table
--    (also enable via Dashboard → Database → Replication if needed)
-- -------------------------------------------------------
ALTER PUBLICATION supabase_realtime ADD TABLE public.rentals;

-- -------------------------------------------------------
-- Done. Verify with:
--   SELECT column_name FROM information_schema.columns
--   WHERE table_name = 'rentals' ORDER BY ordinal_position;
-- -------------------------------------------------------
