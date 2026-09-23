-- Server-side KYC gate for rentals.
-- Safe to re-run in Supabase SQL Editor.
-- Requires profiles.verification_status from kyc_verification.sql.

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
