-- =============================================================================
-- AbhiShare — Migration: Refer & Earn Feature
-- =============================================================================
-- Migration : 004_refer_and_earn.sql
-- Created   : 2026-10-11
-- Purpose   : Adds referral tracking columns to users, creates referrals table
--             with constraints (self-referral prevention, unique referee),
--             indexes for daily limit tracking in IST, and status management.
-- =============================================================================

-- Step 1: Add referral columns to users table
ALTER TABLE public.users 
ADD COLUMN IF NOT EXISTS referral_code VARCHAR(30) UNIQUE,
ADD COLUMN IF NOT EXISTS referred_by_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
ADD COLUMN IF NOT EXISTS referred_by_code VARCHAR(30);

CREATE INDEX IF NOT EXISTS idx_users_referral_code ON public.users(referral_code);

-- Step 2: Populate referral_code for existing users if null
UPDATE public.users 
SET referral_code = UPPER(SUBSTRING(REGEXP_REPLACE(COALESCE(full_name, 'USER'), '[^a-zA-Z]', '', 'g') FROM 1 FOR 4)) || LPAD((FLOOR(RANDOM() * 9000 + 1000)::int)::text, 4, '0')
WHERE referral_code IS NULL;

-- Step 3: Create referrals table
CREATE TABLE IF NOT EXISTS public.referrals (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    referrer_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    referee_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE UNIQUE,
    referral_code VARCHAR(50) NOT NULL,
    status VARCHAR(30) NOT NULL DEFAULT 'registered' 
        CHECK (status IN ('registered', 'ride_pending', 'eligible', 'reward_credited')),
    reward_amount NUMERIC(10, 2) NOT NULL DEFAULT 50.00,
    referrer_ride_completed BOOLEAN NOT NULL DEFAULT false,
    referee_ride_completed BOOLEAN NOT NULL DEFAULT false,
    reward_credited_at TIMESTAMPTZ,
    reward_transaction_id UUID REFERENCES public.wallet_transactions(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_no_self_referral CHECK (referrer_id <> referee_id)
);

-- Step 4: Indexes for fast lookups and daily limit enforcement (IST timezone)
CREATE INDEX IF NOT EXISTS idx_referrals_referrer_id ON public.referrals(referrer_id);
CREATE INDEX IF NOT EXISTS idx_referrals_referee_id ON public.referrals(referee_id);
CREATE INDEX IF NOT EXISTS idx_referrals_status ON public.referrals(status);
CREATE INDEX IF NOT EXISTS idx_referrals_daily_ist ON public.referrals (referrer_id, ((created_at AT TIME ZONE 'Asia/Kolkata')::date));

-- Step 5: Update wallet_transactions type constraint to include 'referral_reward'
ALTER TABLE public.wallet_transactions
DROP CONSTRAINT IF EXISTS wallet_transactions_type_check;

ALTER TABLE public.wallet_transactions
ADD CONSTRAINT wallet_transactions_type_check
CHECK (type IN ('money_added', 'withdrawal', 'ride_payment', 'refund', 'referral_reward'));

