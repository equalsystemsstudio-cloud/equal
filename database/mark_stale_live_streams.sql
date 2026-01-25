-- Auto-end stale live streams that were never properly closed
-- Requires pg_cron extension on the database

-- Ensure pg_cron is available (on Supabase, pg_cron is typically enabled)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_extension WHERE extname = 'pg_cron'
  ) THEN
    CREATE EXTENSION pg_cron;
  END IF;
END
$$;

-- Function to mark stale live streams as ended
CREATE OR REPLACE FUNCTION public.mark_stale_live_streams()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  UPDATE public.live_streams
  SET
    status = 'ended',
    ended_at = now(),
    updated_at = now(),
    final_duration = GREATEST(
      COALESCE(EXTRACT(EPOCH FROM (now() - started_at))::bigint, 0),
      0
    )
  WHERE status = 'live'
    AND ended_at IS NULL
    AND updated_at < (now() - interval '3 minutes');
END;
$$;

-- Schedule the cleanup to run every minute
SELECT cron.schedule(
  'mark-stale-live-streams-every-minute',
  '*/1 * * * *',
  $$SELECT public.mark_stale_live_streams();$$
);

