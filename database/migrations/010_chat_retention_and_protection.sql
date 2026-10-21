-- Migration: 010_chat_retention_and_protection.sql
-- Date      : 2026-10-17
-- Purpose   : Implement chat lifecycle, retention, and protection rules:
--             1. Add completed_at timestamp to rides table.
--             2. Add protection metadata (is_protected, protection_reason, protected_at) to chat_conversations.
--             3. Allow 'completed' status on chat_conversations.
--             4. Provide atomic cleanup_expired_chat_conversations() function preserving reported/blocked chats.

-- 1. Add completed_at to rides table
ALTER TABLE public.rides 
ADD COLUMN IF NOT EXISTS completed_at TIMESTAMPTZ;

-- Backfill completed_at for existing completed rides
UPDATE public.rides 
SET completed_at = updated_at 
WHERE status = 'completed' AND completed_at IS NULL;

-- 2. Add protection columns to chat_conversations
ALTER TABLE public.chat_conversations 
ADD COLUMN IF NOT EXISTS is_protected BOOLEAN NOT NULL DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS protection_reason TEXT,
ADD COLUMN IF NOT EXISTS protected_at TIMESTAMPTZ;

-- Update status check constraint to permit 'completed'
ALTER TABLE public.chat_conversations 
DROP CONSTRAINT IF EXISTS chat_conversations_status_check;

ALTER TABLE public.chat_conversations 
ADD CONSTRAINT chat_conversations_status_check 
CHECK (status IN ('active', 'archived', 'read_only', 'completed'));

-- 3. Backfill protection for existing reports and blocks
UPDATE public.chat_conversations c
SET is_protected = TRUE,
    protection_reason = 'reported',
    protected_at = NOW(),
    updated_at = NOW()
WHERE is_protected = FALSE
  AND EXISTS (
      SELECT 1 FROM public.user_reports ur
      WHERE ur.conversation_id = c.id
         OR ur.ride_id = c.ride_id
         OR (ur.reporter_id = c.driver_id AND ur.reported_id = c.passenger_id)
         OR (ur.reporter_id = c.passenger_id AND ur.reported_id = c.driver_id)
  );

UPDATE public.chat_conversations c
SET is_protected = TRUE,
    protection_reason = CASE 
        WHEN protection_reason IS NULL OR protection_reason = '' THEN 'blocked'
        ELSE protection_reason || ',blocked'
    END,
    protected_at = COALESCE(protected_at, NOW()),
    updated_at = NOW()
WHERE EXISTS (
      SELECT 1 FROM public.user_blocks ub
      WHERE (ub.blocker_id = c.driver_id AND ub.blocked_id = c.passenger_id)
         OR (ub.blocker_id = c.passenger_id AND ub.blocked_id = c.driver_id)
  );

-- 4. Create performance indexes
CREATE INDEX IF NOT EXISTS idx_rides_completed_at ON public.rides (status, completed_at);
CREATE INDEX IF NOT EXISTS idx_chat_conversations_cleanup ON public.chat_conversations (status, is_protected, ride_id);

-- 5. Stored function for scheduled cleanup of expired, unprotected chat conversations
CREATE OR REPLACE FUNCTION public.cleanup_expired_chat_conversations()
RETURNS TABLE(deleted_count INT) AS $$
DECLARE
    count_deleted INT;
BEGIN
    -- Step A: Atomically protect any conversations involving reports or blocks before cleanup
    UPDATE public.chat_conversations c
    SET is_protected = TRUE,
        protection_reason = CASE
            WHEN EXISTS (
                SELECT 1 FROM public.user_reports ur 
                WHERE ur.conversation_id = c.id 
                   OR ur.ride_id = c.ride_id 
                   OR (ur.reporter_id = c.driver_id AND ur.reported_id = c.passenger_id) 
                   OR (ur.reporter_id = c.passenger_id AND ur.reported_id = c.driver_id)
            ) AND EXISTS (
                SELECT 1 FROM public.user_blocks ub 
                WHERE (ub.blocker_id = c.driver_id AND ub.blocked_id = c.passenger_id) 
                   OR (ub.blocker_id = c.passenger_id AND ub.blocked_id = c.driver_id)
            ) THEN 'reported_and_blocked'
            WHEN EXISTS (
                SELECT 1 FROM public.user_reports ur 
                WHERE ur.conversation_id = c.id 
                   OR ur.ride_id = c.ride_id 
                   OR (ur.reporter_id = c.driver_id AND ur.reported_id = c.passenger_id) 
                   OR (ur.reporter_id = c.passenger_id AND ur.reported_id = c.driver_id)
            ) THEN 'reported'
            ELSE 'blocked'
        END,
        protected_at = COALESCE(protected_at, NOW()),
        updated_at = NOW()
    WHERE c.is_protected = FALSE
      AND (
          EXISTS (
              SELECT 1 FROM public.user_reports ur
              WHERE ur.conversation_id = c.id
                 OR ur.ride_id = c.ride_id
                 OR (ur.reporter_id = c.driver_id AND ur.reported_id = c.passenger_id)
                 OR (ur.reporter_id = c.passenger_id AND ur.reported_id = c.driver_id)
          )
          OR EXISTS (
              SELECT 1 FROM public.user_blocks ub
              WHERE (ub.blocker_id = c.driver_id AND ub.blocked_id = c.passenger_id)
                 OR (ub.blocker_id = c.passenger_id AND ub.blocked_id = c.driver_id)
          )
      );

    -- Step B: Delete conversations belonging to completed rides whose verified completion timestamp
    -- is older than 7 days, excluding any protected conversations.
    WITH to_delete AS (
        SELECT c.id
        FROM public.chat_conversations c
        JOIN public.rides r ON r.id = c.ride_id
        WHERE r.status = 'completed'
          AND r.completed_at IS NOT NULL
          AND r.completed_at < NOW() - INTERVAL '7 days'
          AND c.is_protected = FALSE
          AND NOT EXISTS (
              SELECT 1 FROM public.user_reports ur
              WHERE ur.conversation_id = c.id
                 OR ur.ride_id = c.ride_id
                 OR (ur.reporter_id = c.driver_id AND ur.reported_id = c.passenger_id)
                 OR (ur.reporter_id = c.passenger_id AND ur.reported_id = c.driver_id)
          )
          AND NOT EXISTS (
              SELECT 1 FROM public.user_blocks ub
              WHERE (ub.blocker_id = c.driver_id AND ub.blocked_id = c.passenger_id)
                 OR (ub.blocker_id = c.passenger_id AND ub.blocked_id = c.driver_id)
          )
        FOR UPDATE OF c SKIP LOCKED
    ),
    deleted AS (
        DELETE FROM public.chat_conversations
        WHERE id IN (SELECT id FROM to_delete)
        RETURNING id
    )
    SELECT COUNT(*)::INT INTO count_deleted FROM deleted;

    RETURN QUERY SELECT count_deleted;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
