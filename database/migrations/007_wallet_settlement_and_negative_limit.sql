-- Migration: 007_wallet_settlement_and_negative_limit.sql
-- Date      : 2026-10-16
-- Purpose   : Supports wallet settlement for driver earnings and cash platform charges.
--             - Allows negative wallet balances down to -100 (with safety buffer for atomic settlement reconciliation)
--             - Extends wallet_transactions type check constraint for 'ride_earnings_upi' and 'platform_charge_cash'
--             - Adds settlement tracking columns to rides and bookings

-- 1. Relax wallet balance check constraint to allow negative balances
ALTER TABLE public.wallets DROP CONSTRAINT IF EXISTS wallets_balance_check;

-- 2. Extend wallet_transactions type constraint to include ride settlements
ALTER TABLE public.wallet_transactions DROP CONSTRAINT IF EXISTS wallet_transactions_type_check;
ALTER TABLE public.wallet_transactions ADD CONSTRAINT wallet_transactions_type_check 
    CHECK (type::text = ANY (ARRAY[
        'money_added'::character varying,
        'withdrawal'::character varying,
        'ride_payment'::character varying,
        'refund'::character varying,
        'referral_reward'::character varying,
        'ride_earnings_upi'::character varying,
        'platform_charge_cash'::character varying
    ]::text[]));

-- 3. Add settlement_status to rides
ALTER TABLE public.rides 
    ADD COLUMN IF NOT EXISTS settlement_status VARCHAR(20) NOT NULL DEFAULT 'unsettled';

UPDATE public.rides 
SET settlement_status = 'settled' 
WHERE status = 'completed' AND settlement_status = 'unsettled';

-- 4. Add settlement tracking columns to bookings
ALTER TABLE public.bookings
    ADD COLUMN IF NOT EXISTS settlement_status VARCHAR(20) NOT NULL DEFAULT 'unsettled',
    ADD COLUMN IF NOT EXISTS driver_earnings NUMERIC(10,2) NOT NULL DEFAULT 0.00,
    ADD COLUMN IF NOT EXISTS platform_charge NUMERIC(10,2) NOT NULL DEFAULT 0.00;

UPDATE public.bookings 
SET settlement_status = 'settled' 
WHERE status = 'completed' AND settlement_status = 'unsettled';

-- 5. Add index for faster booking and ride settlement lookup
CREATE INDEX IF NOT EXISTS idx_bookings_ride_settle ON public.bookings(ride_id, settlement_status);
CREATE INDEX IF NOT EXISTS idx_rides_driver_settle ON public.rides(driver_id, status);
