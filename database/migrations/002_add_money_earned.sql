-- =============================================================================
-- AbhiShare — Migration: Add money_earned to users
-- =============================================================================
-- Migration : 002_add_money_earned.sql
-- Created   : 2026-10-08
-- Purpose   : Adds money_earned column to the users table with numeric precision
--             and backfills accumulated earnings from completed rides.
-- =============================================================================

ALTER TABLE public.users
ADD COLUMN IF NOT EXISTS money_earned NUMERIC(10, 2) NOT NULL DEFAULT 0.00;

-- Backfill existing completed ride earnings safely
UPDATE public.users u
SET money_earned = COALESCE((
    SELECT SUM(b.seats_booked * r.price_per_seat)
    FROM public.rides r
    JOIN public.bookings b ON b.ride_id = r.id
    WHERE r.driver_id = u.id
      AND r.status = 'completed'
      AND b.status IN ('confirmed', 'completed')
), 0.00);
