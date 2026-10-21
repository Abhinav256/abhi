-- Migration: 006_extra_pay.sql
-- Date      : 2026-10-16
-- Purpose   : Adds Extra Pay pricing columns to the rides table.
--             - user_amount  : the driver's base price per seat (same as price_per_seat)
--             - app_amount   : the AbhiShare service charge per seat
--             - total_amount : the passenger-facing price per seat (user_amount + app_amount)
--             Backfills existing rides so user_amount = price_per_seat, app_amount = 0,
--             total_amount = price_per_seat. This is backward-compatible: existing rides
--             keep their original prices with zero platform charge.

BEGIN;

-- Step 1: Add new columns with safe defaults.
ALTER TABLE public.rides
  ADD COLUMN IF NOT EXISTS user_amount  NUMERIC(10,2) NOT NULL DEFAULT 0.00,
  ADD COLUMN IF NOT EXISTS app_amount   NUMERIC(10,2) NOT NULL DEFAULT 0.00,
  ADD COLUMN IF NOT EXISTS total_amount NUMERIC(10,2) NOT NULL DEFAULT 0.00;

-- Step 2: Backfill existing rides from the current price_per_seat.
UPDATE public.rides
SET user_amount  = price_per_seat,
    app_amount   = 0.00,
    total_amount = price_per_seat
WHERE user_amount = 0.00 AND price_per_seat > 0;

-- Step 3: Add constraints.
ALTER TABLE public.rides
  ADD CONSTRAINT rides_user_amount_check  CHECK (user_amount  >= 0),
  ADD CONSTRAINT rides_app_amount_check   CHECK (app_amount   >= 0),
  ADD CONSTRAINT rides_total_amount_check CHECK (total_amount >= 0);

COMMIT;
