-- Simple fix for missing 'type' column in posts table
-- This addresses the specific error: "Could not find the 'type' column of 'posts'"

BEGIN;

-- First, check if posts table exists
CREATE TABLE IF NOT EXISTS public.posts (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  type VARCHAR(20) NOT NULL DEFAULT 'image',
  caption TEXT,
  content TEXT DEFAULT '',
  media_url TEXT,
  thumbnail_url TEXT,
  location TEXT,
  hashtags TEXT[] DEFAULT '{}',
  mentions TEXT[] DEFAULT '{}',
  is_public BOOLEAN DEFAULT TRUE,
  allow_comments BOOLEAN DEFAULT TRUE,
  views_count INTEGER DEFAULT 0,
  likes_count INTEGER DEFAULT 0,
  comments_count INTEGER DEFAULT 0,
  shares_count INTEGER DEFAULT 0,
  saves_count INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ
);

-- Add missing columns if they don't exist
ALTER TABLE public.posts ADD COLUMN IF NOT EXISTS type VARCHAR(20) NOT NULL DEFAULT 'image';
ALTER TABLE public.posts ADD COLUMN IF NOT EXISTS caption TEXT;
ALTER TABLE public.posts ADD COLUMN IF NOT EXISTS content TEXT DEFAULT '';
ALTER TABLE public.posts ADD COLUMN IF NOT EXISTS media_url TEXT;
ALTER TABLE public.posts ADD COLUMN IF NOT EXISTS thumbnail_url TEXT;
ALTER TABLE public.posts ADD COLUMN IF NOT EXISTS location TEXT;
ALTER TABLE public.posts ADD COLUMN IF NOT EXISTS hashtags TEXT[] DEFAULT '{}';
ALTER TABLE public.posts ADD COLUMN IF NOT EXISTS mentions TEXT[] DEFAULT '{}';
ALTER TABLE public.posts ADD COLUMN IF NOT EXISTS is_public BOOLEAN DEFAULT TRUE;
ALTER TABLE public.posts ADD COLUMN IF NOT EXISTS allow_comments BOOLEAN DEFAULT TRUE;
ALTER TABLE public.posts ADD COLUMN IF NOT EXISTS views_count INTEGER DEFAULT 0;
ALTER TABLE public.posts ADD COLUMN IF NOT EXISTS likes_count INTEGER DEFAULT 0;
ALTER TABLE public.posts ADD COLUMN IF NOT EXISTS comments_count INTEGER DEFAULT 0;
ALTER TABLE public.posts ADD COLUMN IF NOT EXISTS shares_count INTEGER DEFAULT 0;
ALTER TABLE public.posts ADD COLUMN IF NOT EXISTS saves_count INTEGER DEFAULT 0;
ALTER TABLE public.posts ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT NOW();
ALTER TABLE public.posts ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ;

-- Ensure NOT NULL constraints
ALTER TABLE public.posts ALTER COLUMN user_id SET NOT NULL;
ALTER TABLE public.posts ALTER COLUMN type SET NOT NULL;
ALTER TABLE public.posts ALTER COLUMN content SET DEFAULT '';

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_posts_user_id ON public.posts(user_id);
CREATE INDEX IF NOT EXISTS idx_posts_created_at ON public.posts(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_posts_type ON public.posts(type);
CREATE INDEX IF NOT EXISTS idx_posts_is_public ON public.posts(is_public);

-- Enable RLS
ALTER TABLE public.posts ENABLE ROW LEVEL SECURITY;

-- Create RLS policies if they don't exist
DO $$
BEGIN
  -- Allow users to view public posts or their own posts
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='posts' AND policyname='Users can view posts') THEN
    CREATE POLICY "Users can view posts" ON public.posts
      FOR SELECT USING (is_public = true OR user_id = auth.uid());
  END IF;

  -- Allow users to insert their own posts
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='posts' AND policyname='Users can insert own posts') THEN
    CREATE POLICY "Users can insert own posts" ON public.posts
      FOR INSERT WITH CHECK (user_id = auth.uid());
  END IF;

  -- Allow users to update their own posts
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='posts' AND policyname='Users can update own posts') THEN
    CREATE POLICY "Users can update own posts" ON public.posts
      FOR UPDATE USING (user_id = auth.uid());
  END IF;

  -- Allow users to delete their own posts
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='posts' AND policyname='Users can delete own posts') THEN
    CREATE POLICY "Users can delete own posts" ON public.posts
      FOR DELETE USING (user_id = auth.uid());
  END IF;
END $$;

-- Create updated_at trigger
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS posts_updated_at ON public.posts;
CREATE TRIGGER posts_updated_at
  BEFORE UPDATE ON public.posts
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

COMMIT;

-- Verify the fix
SELECT 
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns 
WHERE table_schema = 'public' 
  AND table_name = 'posts'
  AND column_name = 'type';