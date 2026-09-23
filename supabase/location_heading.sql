-- Add compass heading so maps can show which way the rider is facing.
-- Run in Supabase SQL Editor (safe to re-run).

alter table public.rental_last_location
  add column if not exists heading double precision;

alter table public.rental_locations
  add column if not exists heading double precision;
