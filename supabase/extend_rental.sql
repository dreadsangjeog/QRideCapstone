-- Rider can extend an active rental. Minimum +15 minutes.
-- Run in Supabase SQL Editor after rental_v2_migration.sql.

CREATE OR REPLACE FUNCTION public.extend_rental(
  p_rental_id uuid,
  p_extra_mins integer
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  IF p_extra_mins IS NULL OR p_extra_mins < 15 THEN
    RAISE EXCEPTION 'extra_mins_must_be_at_least_15';
  END IF;

  UPDATE public.rentals
  SET
    planned_minutes = planned_minutes + p_extra_mins,
    estimated_cost = round(
      ((planned_minutes + p_extra_mins)::numeric / 60.0) * rate_per_hour,
      0
    )
  WHERE id = p_rental_id
    AND user_id = auth.uid()
    AND status = 'active';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'rental_not_active_or_not_owner';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.extend_rental(uuid, integer) FROM public;
GRANT EXECUTE ON FUNCTION public.extend_rental(uuid, integer) TO authenticated;
