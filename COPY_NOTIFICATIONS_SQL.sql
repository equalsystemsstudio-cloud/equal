-- Copy-Paste SQL: Fix notifications inserts with schema-aware policies
-- Usage: Paste into Supabase SQL Editor and click Run

BEGIN;

-- 1) Clean up existing policies to avoid duplicates
DROP POLICY IF EXISTS "Users can insert notifications as actor" ON public.notifications;
DROP POLICY IF EXISTS "Users can insert own notifications" ON public.notifications;

-- 2) Create INSERT policy based on existing column names
-- Prefer actor_id if present; fallback to sender_id.
DO $$
DECLARE
  has_actor boolean;
  has_sender boolean;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'notifications'
      AND column_name = 'actor_id'
  ) INTO has_actor;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'notifications'
      AND column_name = 'sender_id'
  ) INTO has_sender;

  IF has_actor THEN
    EXECUTE 'CREATE POLICY "Users can insert notifications as actor" ON public.notifications FOR INSERT WITH CHECK (actor_id = auth.uid())';
  ELSIF has_sender THEN
    EXECUTE 'CREATE POLICY "Users can insert notifications as actor" ON public.notifications FOR INSERT WITH CHECK (sender_id = auth.uid())';
  ELSE
    -- Neither column exists; create actor_id and use it
    EXECUTE 'ALTER TABLE public.notifications ADD COLUMN actor_id uuid';
    EXECUTE 'CREATE INDEX IF NOT EXISTS idx_notifications_actor_id ON public.notifications(actor_id)';
    EXECUTE 'CREATE POLICY "Users can insert notifications as actor" ON public.notifications FOR INSERT WITH CHECK (actor_id = auth.uid())';
  END IF;
END $$;

-- 3) Allow recipients to insert their own notifications
CREATE POLICY "Users can insert own notifications" ON public.notifications
  FOR INSERT
  WITH CHECK (user_id = auth.uid());

-- 4) Ensure realtime includes notifications (safe on duplicates)
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE notifications;
EXCEPTION
  WHEN duplicate_object THEN
    NULL;
END $$;

COMMIT;

-- After running:
-- - If your table uses sender_id, the policy will use sender_id.
-- - If your table uses actor_id, the policy will use actor_id.
-- - If neither exists, actor_id will be created and used.