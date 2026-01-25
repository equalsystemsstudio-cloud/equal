-- Live Streams Database Schema for Supabase with Jitsi Meet Integration
-- Execute this in your Supabase SQL Editor

-- Idempotent pre-patch: ensure columns, constraints, indexes and policies exist even if table predates this schema
BEGIN;

-- Ensure required columns exist on existing live_streams table
ALTER TABLE public.live_streams ADD COLUMN IF NOT EXISTS provider VARCHAR(20);
ALTER TABLE public.live_streams ADD COLUMN IF NOT EXISTS jitsi_room_name VARCHAR(255);
ALTER TABLE public.live_streams ADD COLUMN IF NOT EXISTS jitsi_stream_url TEXT;
ALTER TABLE public.live_streams ADD COLUMN IF NOT EXISTS status VARCHAR(20) DEFAULT 'live';
ALTER TABLE public.live_streams ADD COLUMN IF NOT EXISTS viewer_count INTEGER DEFAULT 0;
ALTER TABLE public.live_streams ADD COLUMN IF NOT EXISTS final_viewer_count INTEGER;
ALTER TABLE public.live_streams ADD COLUMN IF NOT EXISTS started_at TIMESTAMPTZ DEFAULT NOW();
ALTER TABLE public.live_streams ADD COLUMN IF NOT EXISTS ended_at TIMESTAMPTZ;
ALTER TABLE public.live_streams ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT NOW();
ALTER TABLE public.live_streams ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();
ALTER TABLE public.live_streams ADD COLUMN IF NOT EXISTS is_ephemeral BOOLEAN DEFAULT FALSE;
ALTER TABLE public.live_streams ADD COLUMN IF NOT EXISTS saved_locally BOOLEAN DEFAULT FALSE;
ALTER TABLE public.live_streams ADD COLUMN IF NOT EXISTS local_file_path TEXT;
ALTER TABLE public.live_streams ADD COLUMN IF NOT EXISTS final_duration INTEGER;
ALTER TABLE public.live_streams ADD COLUMN IF NOT EXISTS tags TEXT[] DEFAULT '{}';
-- Ensure Mux-specific columns exist for cross-schema compatibility
ALTER TABLE public.live_streams ADD COLUMN IF NOT EXISTS mux_stream_id VARCHAR(255);
ALTER TABLE public.live_streams ADD COLUMN IF NOT EXISTS mux_playback_id VARCHAR(255);
ALTER TABLE public.live_streams ADD COLUMN IF NOT EXISTS stream_key VARCHAR(255);

-- Provider CHECK constraint if missing
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'live_streams_provider_check'
  ) THEN
    ALTER TABLE public.live_streams
      ADD CONSTRAINT live_streams_provider_check
      CHECK (provider IN ('jitsi','livekit'));
  END IF;
END$$;

-- Normalize provider CHECK constraint to ensure 'jitsi' and 'livekit' are allowed
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'live_streams_provider_check'
  ) THEN
    ALTER TABLE public.live_streams DROP CONSTRAINT live_streams_provider_check;
  END IF;
  ALTER TABLE public.live_streams
    ADD CONSTRAINT live_streams_provider_check
    CHECK (provider IN ('jitsi','livekit'));
END$$;
-- Indexes (idempotent)
CREATE INDEX IF NOT EXISTS idx_live_streams_user_id ON public.live_streams(user_id);
CREATE INDEX IF NOT EXISTS idx_live_streams_status ON public.live_streams(status);
CREATE INDEX IF NOT EXISTS idx_live_streams_started_at ON public.live_streams(started_at DESC);
CREATE INDEX IF NOT EXISTS idx_live_streams_tags ON public.live_streams USING GIN(tags);
CREATE INDEX IF NOT EXISTS idx_live_streams_jitsi_room ON public.live_streams(jitsi_room_name);
CREATE INDEX IF NOT EXISTS idx_live_streams_provider ON public.live_streams(provider);

-- RLS Policies for live_streams (idempotent)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='live_streams' AND policyname='Users can view all live streams'
  ) THEN
    EXECUTE 'CREATE POLICY "Users can view all live streams" ON public.live_streams FOR SELECT USING (true)';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='live_streams' AND policyname='Users can create their own live streams'
  ) THEN
    EXECUTE 'CREATE POLICY "Users can create their own live streams" ON public.live_streams FOR INSERT WITH CHECK (auth.uid() = user_id)';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='live_streams' AND policyname='Users can update their own live streams'
  ) THEN
    EXECUTE 'CREATE POLICY "Users can update their own live streams" ON public.live_streams FOR UPDATE USING (auth.uid() = user_id)';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='live_streams' AND policyname='Users can delete their own live streams'
  ) THEN
    EXECUTE 'CREATE POLICY "Users can delete their own live streams" ON public.live_streams FOR DELETE USING (auth.uid() = user_id)';
  END IF;
END$$;

-- Enable Row Level Security (safe to repeat)
ALTER TABLE public.live_streams ENABLE ROW LEVEL SECURITY;

COMMIT;

-- Create live_streams table
CREATE TABLE IF NOT EXISTS public.live_streams (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  title VARCHAR(255) NOT NULL,
  description TEXT,
  tags TEXT[] DEFAULT '{}',
  provider VARCHAR(20) NOT NULL DEFAULT 'jitsi' CHECK (provider IN ('jitsi', 'livekit')),
  jitsi_room_name VARCHAR(255),
  jitsi_stream_url TEXT,
  status VARCHAR(20) DEFAULT 'live' CHECK (status IN ('live', 'ended', 'error')),
  viewer_count INTEGER DEFAULT 0,
  final_viewer_count INTEGER,
  started_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  ended_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  -- Ephemeral/local recording metadata
  is_ephemeral BOOLEAN DEFAULT FALSE,
  saved_locally BOOLEAN DEFAULT FALSE,
  local_file_path TEXT,
  final_duration INTEGER
);

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_live_streams_user_id ON public.live_streams(user_id);
CREATE INDEX IF NOT EXISTS idx_live_streams_status ON public.live_streams(status);
CREATE INDEX IF NOT EXISTS idx_live_streams_started_at ON public.live_streams(started_at DESC);
CREATE INDEX IF NOT EXISTS idx_live_streams_tags ON public.live_streams USING GIN(tags);
CREATE INDEX IF NOT EXISTS idx_live_streams_jitsi_room ON public.live_streams(jitsi_room_name);
CREATE INDEX IF NOT EXISTS idx_live_streams_provider ON public.live_streams(provider);

-- Create live_stream_viewers table for tracking viewer history
CREATE TABLE IF NOT EXISTS public.live_stream_viewers (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  stream_id UUID REFERENCES public.live_streams(id) ON DELETE CASCADE NOT NULL,
  user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
  username VARCHAR(30),
  avatar_url TEXT,
  joined_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  left_at TIMESTAMP WITH TIME ZONE,
  watch_duration INTEGER, -- in seconds
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create indexes for viewer tracking
CREATE INDEX IF NOT EXISTS idx_live_stream_viewers_stream_id ON public.live_stream_viewers(stream_id);
CREATE INDEX IF NOT EXISTS idx_live_stream_viewers_user_id ON public.live_stream_viewers(user_id);
CREATE INDEX IF NOT EXISTS idx_live_stream_viewers_joined_at ON public.live_stream_viewers(joined_at DESC);

-- Create live_stream_chat table for persistent chat history
CREATE TABLE IF NOT EXISTS public.live_stream_chat (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  stream_id UUID REFERENCES public.live_streams(id) ON DELETE CASCADE NOT NULL,
  user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
  username VARCHAR(30),
  avatar_url TEXT,
  message TEXT NOT NULL,
  message_type VARCHAR(20) DEFAULT 'text' CHECK (message_type IN ('text', 'emoji', 'system')),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create indexes for chat
CREATE INDEX IF NOT EXISTS idx_live_stream_chat_stream_id ON public.live_stream_chat(stream_id);
CREATE INDEX IF NOT EXISTS idx_live_stream_chat_created_at ON public.live_stream_chat(created_at DESC);

-- Create live_stream_reactions table for tracking reactions
CREATE TABLE IF NOT EXISTS public.live_stream_reactions (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  stream_id UUID REFERENCES public.live_streams(id) ON DELETE CASCADE NOT NULL,
  user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
  username VARCHAR(30),
  reaction_type VARCHAR(20) NOT NULL, -- 'heart', 'like', 'fire', 'clap', etc.
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create indexes for reactions
CREATE INDEX IF NOT EXISTS idx_live_stream_reactions_stream_id ON public.live_stream_reactions(stream_id);
CREATE INDEX IF NOT EXISTS idx_live_stream_reactions_type ON public.live_stream_reactions(reaction_type);
CREATE INDEX IF NOT EXISTS idx_live_stream_reactions_created_at ON public.live_stream_reactions(created_at DESC);

-- Enable Row Level Security (RLS)
ALTER TABLE public.live_streams ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.live_stream_viewers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.live_stream_chat ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.live_stream_reactions ENABLE ROW LEVEL SECURITY;

-- RLS Policies for live_streams
-- Allow users to read all live streams
-- Allow users to read all live streams
DROP POLICY IF EXISTS "Users can view all live streams" ON public.live_streams;
CREATE POLICY "Users can view all live streams" ON public.live_streams
  FOR SELECT USING (true);

-- Allow users to create their own live streams
DROP POLICY IF EXISTS "Users can create their own live streams" ON public.live_streams;
CREATE POLICY "Users can create their own live streams" ON public.live_streams
  FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Allow users to update their own live streams
DROP POLICY IF EXISTS "Users can update their own live streams" ON public.live_streams;
CREATE POLICY "Users can update their own live streams" ON public.live_streams
  FOR UPDATE USING (auth.uid() = user_id);

-- Allow users to delete their own live streams
DROP POLICY IF EXISTS "Users can delete their own live streams" ON public.live_streams;
CREATE POLICY "Users can delete their own live streams" ON public.live_streams
  FOR DELETE USING (auth.uid() = user_id);

-- RLS Policies for live_stream_viewers
-- Allow users to view viewers of any stream
DROP POLICY IF EXISTS "Users can view stream viewers" ON public.live_stream_viewers;
CREATE POLICY "Users can view stream viewers" ON public.live_stream_viewers
  FOR SELECT USING (true);

-- Allow users to insert their own viewer records
DROP POLICY IF EXISTS "Users can insert their own viewer records" ON public.live_stream_viewers;
CREATE POLICY "Users can insert their own viewer records" ON public.live_stream_viewers
  FOR INSERT WITH CHECK (auth.uid() = user_id OR user_id IS NULL);

-- Allow users to update their own viewer records
DROP POLICY IF EXISTS "Users can update their own viewer records" ON public.live_stream_viewers;
CREATE POLICY "Users can update their own viewer records" ON public.live_stream_viewers
  FOR UPDATE USING (auth.uid() = user_id OR user_id IS NULL);

-- RLS Policies for live_stream_chat
-- Allow users to view chat messages for any stream
DROP POLICY IF EXISTS "Users can view stream chat" ON public.live_stream_chat;
CREATE POLICY "Users can view stream chat" ON public.live_stream_chat
  FOR SELECT USING (true);

-- Allow users to insert their own chat messages
DROP POLICY IF EXISTS "Users can send chat messages" ON public.live_stream_chat;
CREATE POLICY "Users can send chat messages" ON public.live_stream_chat
  FOR INSERT WITH CHECK (auth.uid() = user_id OR user_id IS NULL);

-- RLS Policies for live_stream_reactions
-- Allow users to view reactions for any stream
DROP POLICY IF EXISTS "Users can view stream reactions" ON public.live_stream_reactions;
CREATE POLICY "Users can view stream reactions" ON public.live_stream_reactions
  FOR SELECT USING (true);

-- Allow users to send reactions
DROP POLICY IF EXISTS "Users can send reactions" ON public.live_stream_reactions;
CREATE POLICY "Users can send reactions" ON public.live_stream_reactions
  FOR INSERT WITH CHECK (auth.uid() = user_id OR user_id IS NULL);

-- Create function to update viewer count
CREATE OR REPLACE FUNCTION update_stream_viewer_count()
RETURNS TRIGGER AS $$
BEGIN
  -- Update the viewer count in live_streams table
  UPDATE public.live_streams 
  SET viewer_count = (
    SELECT COUNT(*) 
    FROM public.live_stream_viewers 
    WHERE stream_id = COALESCE(NEW.stream_id, OLD.stream_id) 
    AND left_at IS NULL
  ),
  updated_at = NOW()
  WHERE id = COALESCE(NEW.stream_id, OLD.stream_id);
  
  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

-- Create triggers to automatically update viewer count
DROP TRIGGER IF EXISTS update_viewer_count_on_join ON public.live_stream_viewers;
CREATE TRIGGER update_viewer_count_on_join
  AFTER INSERT ON public.live_stream_viewers
  FOR EACH ROW EXECUTE FUNCTION update_stream_viewer_count();

DROP TRIGGER IF EXISTS update_viewer_count_on_leave ON public.live_stream_viewers;
CREATE TRIGGER update_viewer_count_on_leave
  AFTER UPDATE ON public.live_stream_viewers
  FOR EACH ROW EXECUTE FUNCTION update_stream_viewer_count();

-- Create function to calculate watch duration when viewer leaves
CREATE OR REPLACE FUNCTION calculate_watch_duration()
RETURNS TRIGGER AS $$
BEGIN
  -- Calculate watch duration when left_at is set
  IF NEW.left_at IS NOT NULL AND OLD.left_at IS NULL THEN
    NEW.watch_duration = EXTRACT(EPOCH FROM (NEW.left_at - NEW.joined_at))::INTEGER;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger to calculate watch duration
DROP TRIGGER IF EXISTS calculate_watch_duration_trigger ON public.live_stream_viewers;
CREATE TRIGGER calculate_watch_duration_trigger
  BEFORE UPDATE ON public.live_stream_viewers
  FOR EACH ROW EXECUTE FUNCTION calculate_watch_duration();

-- Create function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger to update updated_at for live_streams
DROP TRIGGER IF EXISTS update_live_streams_updated_at ON public.live_streams;
CREATE TRIGGER update_live_streams_updated_at
  BEFORE UPDATE ON public.live_streams
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Grant necessary permissions
GRANT ALL ON public.live_streams TO authenticated;
GRANT ALL ON public.live_stream_viewers TO authenticated;
GRANT ALL ON public.live_stream_chat TO authenticated;
GRANT ALL ON public.live_stream_reactions TO authenticated;

-- Grant usage on sequences
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO authenticated;

-- Create view for active live streams with user info
-- Drop and recreate view for active live streams to allow column list changes
DROP VIEW IF EXISTS public.active_live_streams;
CREATE OR REPLACE VIEW public.active_live_streams AS
SELECT 
  ls.*,
  u.username,
  u.display_name,
  u.avatar_url,
  u.is_verified
FROM public.live_streams ls
JOIN public.users u ON ls.user_id = u.id
WHERE ls.status = 'live'
ORDER BY ls.started_at DESC;

-- Grant access to the view
GRANT SELECT ON public.active_live_streams TO authenticated;

-- Create view for stream analytics
-- Drop and recreate analytics view to allow column list changes
DROP VIEW IF EXISTS public.stream_analytics;
CREATE OR REPLACE VIEW public.stream_analytics AS
SELECT 
  ls.id,
  ls.user_id,
  u.username,
  ls.started_at,
  ls.ended_at,
  ls.final_viewer_count,
  EXTRACT(EPOCH FROM (COALESCE(ls.ended_at, NOW()) - ls.started_at))::INTEGER as duration_seconds,
  COUNT(DISTINCT lsv.user_id) as unique_viewers,
  COUNT(lsc.id) as total_chat_messages,
  COUNT(lsr.id) as total_reactions,
  AVG(lsv.watch_duration) as avg_watch_duration
FROM public.live_streams ls
JOIN public.users u ON ls.user_id = u.id
LEFT JOIN public.live_stream_viewers lsv ON ls.id = lsv.stream_id
LEFT JOIN public.live_stream_chat lsc ON ls.id = lsc.stream_id
LEFT JOIN public.live_stream_reactions lsr ON ls.id = lsr.stream_id
GROUP BY ls.id, ls.title, ls.user_id, u.username, ls.started_at, ls.ended_at, ls.final_viewer_count;

-- Grant access to analytics view
GRANT SELECT ON public.stream_analytics TO authenticated;

COMMIT;