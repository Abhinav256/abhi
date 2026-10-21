-- Migration 009: Add 'location' to chat_messages message_type check constraint
-- Applied live in Supabase project uqubmnnesyvvdeiwjnag

ALTER TABLE public.chat_messages DROP CONSTRAINT IF EXISTS chat_messages_message_type_check;

ALTER TABLE public.chat_messages ADD CONSTRAINT chat_messages_message_type_check 
    CHECK (message_type IN ('text', 'system', 'quick_reply', 'location'));
