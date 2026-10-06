-- Riders create and change rentals only through the rental functions
-- (request, cancel, extend), which check ID verification, the stored fee,
-- and staff approval. Riders can no longer insert or update rental rows
-- directly. Staff keep direct updates for billing fixes.
-- Run after 039_keep_rider_history_on_delete.sql. Safe to re-run.

drop policy if exists "rentals_insert_own" on public.rentals;

drop policy if exists "rentals_update_own_or_admin" on public.rentals;

drop policy if exists "rentals_update_admin" on public.rentals;
create policy "rentals_update_admin"
  on public.rentals for update
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- Check afterwards:
--   select policyname, cmd from pg_policies where tablename = 'rentals';
-- Expect only rentals_select_own_or_admin (SELECT) and rentals_update_admin (UPDATE).
