-- ============================================================
-- QRide — Diagnostic queries
-- Run these in the Supabase SQL Editor when GPS tracking
-- isn't reaching the admin map. They'll tell you exactly
-- what's missing or stale.
-- ============================================================

-- 1. Are the location tables present?
SELECT
  to_regclass('public.rental_locations')      AS rental_locations_exists,
  to_regclass('public.rental_last_location')  AS rental_last_location_exists;

-- 2. Is the RLS helper function present?
SELECT EXISTS(
  SELECT 1 FROM pg_proc p
  JOIN pg_namespace n ON p.pronamespace = n.oid
  WHERE n.nspname = 'public' AND p.proname = 'user_has_active_rental'
) AS has_active_rental_fn_exists;

-- 3. Are RLS policies in place on the location tables?
SELECT schemaname, tablename, policyname, cmd
FROM pg_policies
WHERE tablename IN ('rental_locations', 'rental_last_location')
ORDER BY tablename, policyname;

-- 4. Show any ACTIVE rentals (these should map to live riders).
SELECT id, user_id, bike_id, status, started_at, approved_at, planned_minutes
FROM public.rentals
WHERE status = 'active'
ORDER BY started_at DESC;

-- 5. Show any STALE active rentals (active but never approved → can't track).
--    These break GPS writes because user_has_active_rental returns true,
--    BUT the rider's app may treat them as not-yet-active.
SELECT id, user_id, bike_id, status, started_at, approved_at
FROM public.rentals
WHERE status = 'active'
  AND approved_at IS NULL;

-- 6. Show recent location rows (last 1 hour).
SELECT rental_id, user_id, lat, lng, accuracy_m, recorded_at
FROM public.rental_last_location
WHERE recorded_at > now() - interval '1 hour'
ORDER BY recorded_at DESC;

-- ============================================================
-- CLEANUP — Run only if step 5 shows stale rentals
-- ============================================================
-- Ends any rentals that are 'active' without an approved_at and frees the bike.
-- Safe to run; only affects orphaned rows.

-- UPDATE public.bikes b
-- SET status = 'available'
-- FROM public.rentals r
-- WHERE r.bike_id = b.id
--   AND r.status = 'active'
--   AND r.approved_at IS NULL;

-- UPDATE public.rentals
-- SET status = 'ended', ended_at = now()
-- WHERE status = 'active' AND approved_at IS NULL;

-- DELETE FROM public.rental_last_location
-- WHERE rental_id IN (
--   SELECT id FROM public.rentals
--   WHERE status = 'ended' AND approved_at IS NULL
-- );
