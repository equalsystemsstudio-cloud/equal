-- Safe RLS policy fix for analytics_events to avoid invalid UUID cast errors
-- Run this in Supabase SQL Editor (as service role / admin)

BEGIN;

-- Ensure RLS is enabled on the table
ALTER TABLE public.analytics_events ENABLE ROW LEVEL SECURITY;

-- Ensure the INSERT policy exists (idempotent)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'analytics_events'
      AND policyname = 'Users can insert own analytics'
  ) THEN
    CREATE POLICY "Users can insert own analytics" ON public.analytics_events
      FOR INSERT
      TO PUBLIC
      WITH CHECK (user_id = auth.uid());
  END IF;
END $$ LANGUAGE plpgsql;

-- Fix or create the SELECT policy with a safe UUID guard before casting
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'analytics_events'
      AND policyname = 'Users can view own analytics'
  ) THEN
    ALTER POLICY "Users can view own analytics" ON public.analytics_events
      USING (
        user_id = auth.uid() OR (
          properties ? 'post_id' AND
          (analytics_events.properties->>'post_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' AND
          EXISTS (
            SELECT 1 FROM public.posts
            WHERE posts.id = (analytics_events.properties->>'post_id')::uuid
              AND posts.user_id = auth.uid()
          )
        )
      );
  ELSE
    CREATE POLICY "Users can view own analytics" ON public.analytics_events
      FOR SELECT
      TO PUBLIC
      USING (
        user_id = auth.uid() OR (
          properties ? 'post_id' AND
          (analytics_events.properties->>'post_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' AND
          EXISTS (
            SELECT 1 FROM public.posts
            WHERE posts.id = (analytics_events.properties->>'post_id')::uuid
              AND posts.user_id = auth.uid()
          )
        )
      );
  END IF;
END $$ LANGUAGE plpgsql;

COMMIT;