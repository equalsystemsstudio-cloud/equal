-- Fix share notifications by updating the CHECK constraint
-- This allows 'share' as a valid notification type

ALTER TABLE notifications DROP CONSTRAINT IF EXISTS notifications_type_check;

ALTER TABLE notifications ADD CONSTRAINT notifications_type_check 
    CHECK (type IN ('like', 'comment', 'follow', 'mention', 'post', 'message', 'share'));

-- Verify the constraint was updated
SELECT conname, pg_get_constraintdef(oid) as constraint_definition
FROM pg_constraint 
WHERE conrelid = 'notifications'::regclass 
AND conname = 'notifications_type_check';

SELECT 'Share notifications constraint updated successfully!' AS message;