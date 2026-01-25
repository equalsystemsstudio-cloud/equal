-- Cleanup script to null out invalid (non-UUID) post_id values in analytics_events
-- Run this in Supabase SQL Editor (as service role / admin)

BEGIN;

UPDATE public.analytics_events
SET properties = jsonb_set(properties, '{post_id}', 'null'::jsonb, true)
WHERE properties ? 'post_id'
  AND (properties->>'post_id') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';

COMMIT;