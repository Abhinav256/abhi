-- Migration: 008_chat_system.sql
-- Date      : 2026-10-17
-- Purpose   : Production-ready In-App Chat between ride creators and passengers.
--             - 1-to-1 conversation per confirmed booking
--             - Persistent message ledger with read receipts and idempotency
--             - User blocking and reporting support
--             - RLS policies and performance indexes

CREATE TABLE IF NOT EXISTS public.chat_conversations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ride_id UUID NOT NULL REFERENCES public.rides(id) ON DELETE CASCADE,
    booking_id UUID NOT NULL REFERENCES public.bookings(id) ON DELETE CASCADE,
    driver_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    passenger_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    status VARCHAR(20) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'archived', 'read_only')),
    last_message_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_chat_conversations_booking UNIQUE (booking_id),
    CONSTRAINT chk_chat_participants_distinct CHECK (driver_id != passenger_id)
);

CREATE INDEX IF NOT EXISTS idx_chat_conv_driver ON public.chat_conversations(driver_id, last_message_at DESC);
CREATE INDEX IF NOT EXISTS idx_chat_conv_passenger ON public.chat_conversations(passenger_id, last_message_at DESC);
CREATE INDEX IF NOT EXISTS idx_chat_conv_ride ON public.chat_conversations(ride_id);

CREATE TABLE IF NOT EXISTS public.chat_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID NOT NULL REFERENCES public.chat_conversations(id) ON DELETE CASCADE,
    sender_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
    sender_role VARCHAR(20) NOT NULL CHECK (sender_role IN ('driver', 'passenger', 'system')),
    message_type VARCHAR(20) NOT NULL DEFAULT 'text' CHECK (message_type IN ('text', 'system', 'quick_reply')),
    content TEXT NOT NULL,
    client_message_id VARCHAR(100),
    is_read BOOLEAN NOT NULL DEFAULT false,
    read_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_chat_msgs_conv_created ON public.chat_messages(conversation_id, created_at ASC);
CREATE INDEX IF NOT EXISTS idx_chat_msgs_conv_unread ON public.chat_messages(conversation_id, is_read) WHERE is_read = false;
CREATE INDEX IF NOT EXISTS idx_chat_msgs_client_id ON public.chat_messages(conversation_id, client_message_id) WHERE client_message_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS public.user_blocks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    blocker_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    blocked_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    reason TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_user_blocks UNIQUE (blocker_id, blocked_id),
    CONSTRAINT chk_user_blocks_distinct CHECK (blocker_id != blocked_id)
);

CREATE INDEX IF NOT EXISTS idx_user_blocks_blocker ON public.user_blocks(blocker_id);
CREATE INDEX IF NOT EXISTS idx_user_blocks_blocked ON public.user_blocks(blocked_id);

CREATE TABLE IF NOT EXISTS public.user_reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reporter_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    reported_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    ride_id UUID REFERENCES public.rides(id) ON DELETE SET NULL,
    conversation_id UUID REFERENCES public.chat_conversations(id) ON DELETE SET NULL,
    reason VARCHAR(100) NOT NULL,
    description TEXT,
    status VARCHAR(20) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'reviewed', 'dismissed', 'actioned')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_user_reports_distinct CHECK (reporter_id != reported_id)
);

CREATE INDEX IF NOT EXISTS idx_user_reports_reporter ON public.user_reports(reporter_id);
CREATE INDEX IF NOT EXISTS idx_user_reports_reported ON public.user_reports(reported_id);

-- Enable Row Level Security
ALTER TABLE public.chat_conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_blocks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_reports ENABLE ROW LEVEL SECURITY;

-- Conversations RLS: participants can view
DO $$ BEGIN
    DROP POLICY IF EXISTS chat_conversations_select_policy ON public.chat_conversations;
    CREATE POLICY chat_conversations_select_policy ON public.chat_conversations
        FOR SELECT USING (auth.uid() = driver_id OR auth.uid() = passenger_id);
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

-- Messages RLS: participants can view
DO $$ BEGIN
    DROP POLICY IF EXISTS chat_messages_select_policy ON public.chat_messages;
    CREATE POLICY chat_messages_select_policy ON public.chat_messages
        FOR SELECT USING (
            EXISTS (
                SELECT 1 FROM public.chat_conversations c
                WHERE c.id = chat_messages.conversation_id
                  AND (c.driver_id = auth.uid() OR c.passenger_id = auth.uid())
            )
        );
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

-- User blocks RLS
DO $$ BEGIN
    DROP POLICY IF EXISTS user_blocks_select_policy ON public.user_blocks;
    CREATE POLICY user_blocks_select_policy ON public.user_blocks
        FOR SELECT USING (auth.uid() = blocker_id);
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

-- User reports RLS
DO $$ BEGIN
    DROP POLICY IF EXISTS user_reports_select_policy ON public.user_reports;
    CREATE POLICY user_reports_select_policy ON public.user_reports
        FOR SELECT USING (auth.uid() = reporter_id);
EXCEPTION WHEN OTHERS THEN NULL;
END $$;
