-- Migration 005: Add payment_orders table for Razorpay payment integration

CREATE TABLE IF NOT EXISTS public.payment_orders (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    order_id varchar(100) NOT NULL UNIQUE,
    amount numeric(10,2) NOT NULL,
    currency varchar(10) DEFAULT 'INR' NOT NULL,
    purpose varchar(50) NOT NULL,
    status varchar(30) DEFAULT 'created' NOT NULL,
    payment_id varchar(100),
    signature text,
    metadata jsonb DEFAULT '{}'::jsonb,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz DEFAULT now() NOT NULL,
    CONSTRAINT chk_payment_orders_purpose CHECK (purpose IN ('ride_booking', 'wallet_topup')),
    CONSTRAINT chk_payment_orders_status CHECK (status IN ('created', 'paid', 'failed', 'cancelled'))
);

CREATE INDEX IF NOT EXISTS idx_payment_orders_user_id ON public.payment_orders(user_id);
CREATE INDEX IF NOT EXISTS idx_payment_orders_order_id ON public.payment_orders(order_id);
CREATE INDEX IF NOT EXISTS idx_payment_orders_payment_id ON public.payment_orders(payment_id);
