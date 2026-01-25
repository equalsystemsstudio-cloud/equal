-- Add moderation fields to posts to support content safety

-- Create enum types if they do not exist
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_type WHERE typname = 'content_rating'
  ) THEN
    CREATE TYPE content_rating AS ENUM ('safe', 'sensitive', 'adult', 'banned');
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_type WHERE typname = 'moderation_status'
  ) THEN
    CREATE TYPE moderation_status AS ENUM ('pending', 'approved', 'rejected', 'blocked');
  END IF;
END
$$;

-- Alter posts table with moderation fields
ALTER TABLE public.posts
  ADD COLUMN IF NOT EXISTS content_rating content_rating DEFAULT 'safe' NOT NULL,
  ADD COLUMN IF NOT EXISTS moderation_status moderation_status DEFAULT 'pending' NOT NULL,
  ADD COLUMN IF NOT EXISTS moderation_labels jsonb DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS moderation_score numeric,
  ADD COLUMN IF NOT EXISTS moderated_at timestamptz,
  ADD COLUMN IF NOT EXISTS requires_age_verification boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS blur_preview boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS hidden boolean DEFAULT false;

-- Helpful indexes
CREATE INDEX IF NOT EXISTS idx_posts_content_rating ON public.posts (content_rating);
CREATE INDEX IF NOT EXISTS idx_posts_moderation_status ON public.posts (moderation_status);
CREATE INDEX IF NOT EXISTS idx_posts_hidden ON public.posts (hidden);

-- Optional policy example (adjust as needed for your app):
-- Hide adult/banned posts from non-age-verified users
-- Requires RLS enabled and users table with age_verified boolean
-- Commented out to avoid breaking environments that haven't set RLS yet.
--
-- ALTER TABLE public.posts ENABLE ROW LEVEL SECURITY;
-- CREATE POLICY posts_view_safe ON public.posts FOR SELECT
--   USING (
--     hidden = false AND (
--       content_rating IN ('safe','sensitive') OR (
--         content_rating IN ('adult') AND EXISTS (
--           SELECT 1 FROM public.users u WHERE u.id = auth.uid() AND COALESCE(u.age_verified, false) = true
--         )
--       )
--     )
--   );

