-- Equal App Database Setup Script
-- Execute this in your Supabase SQL Editor

-- Enable necessary extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_stat_statements";

-- Enable Row Level Security
-- Note: JWT secret is managed by Supabase automatically

-- Users table (extends auth.users)
CREATE TABLE IF NOT EXISTS public.users (
  id UUID REFERENCES auth.users(id) PRIMARY KEY,
  username VARCHAR(30) UNIQUE NOT NULL,
  display_name VARCHAR(50),
  bio TEXT,
  avatar_url TEXT,
  cover_url TEXT,
  email VARCHAR(255),
  phone VARCHAR(20),
  website VARCHAR(255),
  location VARCHAR(100),
  birth_date DATE,
  gender VARCHAR(20),
  is_verified BOOLEAN DEFAULT FALSE,
  is_private BOOLEAN DEFAULT FALSE,
  followers_count INTEGER DEFAULT 0,
  following_count INTEGER DEFAULT 0,
  posts_count INTEGER DEFAULT 0,
  likes_count INTEGER DEFAULT 0,
  language VARCHAR(10) DEFAULT 'en',
  theme VARCHAR(10) DEFAULT 'system',
  notifications_enabled BOOLEAN DEFAULT TRUE,
  push_notifications_enabled BOOLEAN DEFAULT TRUE,
  email_notifications_enabled BOOLEAN DEFAULT TRUE,
  fcm_token TEXT, -- Firebase Cloud Messaging token for push notifications
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Posts table
CREATE TABLE IF NOT EXISTS public.posts (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
  type VARCHAR(20) NOT NULL, -- video, photo, text, audio, live, ai_generated
  caption TEXT,
  media_url TEXT,
  thumbnail_url TEXT,
  duration INTEGER, -- for video/audio in seconds
  width INTEGER,
  height INTEGER,
  file_size BIGINT,
  mime_type VARCHAR(100),
  is_ai_generated BOOLEAN DEFAULT FALSE,
  ai_prompt TEXT,
  ai_model VARCHAR(50),
  location VARCHAR(255),
  hashtags TEXT[], -- array of hashtag strings
  mentions TEXT[], -- array of mentioned usernames
  is_public BOOLEAN DEFAULT TRUE,
  allow_comments BOOLEAN DEFAULT TRUE,
  allow_duets BOOLEAN DEFAULT TRUE,
  allow_downloads BOOLEAN DEFAULT FALSE,
  views_count INTEGER DEFAULT 0,
  likes_count INTEGER DEFAULT 0,
  comments_count INTEGER DEFAULT 0,
  shares_count INTEGER DEFAULT 0,
  saves_count INTEGER DEFAULT 0,
  reports_count INTEGER DEFAULT 0,
  engagement_score FLOAT DEFAULT 0.0,
  is_featured BOOLEAN DEFAULT FALSE,
  is_trending BOOLEAN DEFAULT FALSE,
  status VARCHAR(20) DEFAULT 'active', -- active, archived, deleted, reported
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Comments table
CREATE TABLE IF NOT EXISTS public.comments (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  post_id UUID REFERENCES public.posts(id) ON DELETE CASCADE,
  user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
  parent_id UUID REFERENCES public.comments(id) ON DELETE CASCADE, -- for replies
  content TEXT NOT NULL,
  mentions TEXT[], -- array of mentioned usernames
  likes_count INTEGER DEFAULT 0,
  replies_count INTEGER DEFAULT 0,
  is_pinned BOOLEAN DEFAULT FALSE,
  is_edited BOOLEAN DEFAULT FALSE,
  status VARCHAR(20) DEFAULT 'active',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Likes table
CREATE TABLE IF NOT EXISTS public.likes (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
  post_id UUID REFERENCES public.posts(id) ON DELETE CASCADE,
  comment_id UUID REFERENCES public.comments(id) ON DELETE CASCADE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(user_id, post_id),
  UNIQUE(user_id, comment_id),
  CHECK ((post_id IS NOT NULL AND comment_id IS NULL) OR (post_id IS NULL AND comment_id IS NOT NULL))
);

-- Follows table
CREATE TABLE IF NOT EXISTS public.follows (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  follower_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
  following_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(follower_id, following_id),
  CHECK (follower_id != following_id)
);

-- Notifications table
CREATE TABLE IF NOT EXISTS public.notifications (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
  sender_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
  type VARCHAR(50) NOT NULL, -- like, comment, follow, mention, etc.
  title VARCHAR(255) NOT NULL,
  message TEXT,
  data JSONB, -- additional notification data
  post_id UUID REFERENCES public.posts(id) ON DELETE CASCADE,
  comment_id UUID REFERENCES public.comments(id) ON DELETE CASCADE,
  is_read BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Hashtags table
CREATE TABLE IF NOT EXISTS public.hashtags (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  name VARCHAR(100) UNIQUE NOT NULL,
  posts_count INTEGER DEFAULT 0,
  trending_score FLOAT DEFAULT 0.0,
  is_trending BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Ensure columns exist when table already exists
ALTER TABLE public.hashtags ADD COLUMN IF NOT EXISTS trending_score FLOAT DEFAULT 0.0;
ALTER TABLE public.hashtags ADD COLUMN IF NOT EXISTS is_trending BOOLEAN DEFAULT FALSE;

-- Post hashtags junction table
CREATE TABLE IF NOT EXISTS public.post_hashtags (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  post_id UUID REFERENCES public.posts(id) ON DELETE CASCADE,
  hashtag_id UUID REFERENCES public.hashtags(id) ON DELETE CASCADE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(post_id, hashtag_id)
);

-- Reports table
CREATE TABLE IF NOT EXISTS public.reports (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  reporter_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
  reported_user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
  post_id UUID REFERENCES public.posts(id) ON DELETE CASCADE,
  comment_id UUID REFERENCES public.comments(id) ON DELETE CASCADE,
  reason VARCHAR(50) NOT NULL,
  description TEXT,
  status VARCHAR(20) DEFAULT 'pending',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Blocks table
CREATE TABLE IF NOT EXISTS public.blocks (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  blocker_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
  blocked_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(blocker_id, blocked_id)
);

-- Saves table
CREATE TABLE IF NOT EXISTS public.saves (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
  post_id UUID REFERENCES public.posts(id) ON DELETE CASCADE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(user_id, post_id)
);

-- Shares table
CREATE TABLE IF NOT EXISTS public.shares (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
  post_id UUID REFERENCES public.posts(id) ON DELETE CASCADE,
  platform VARCHAR(50), -- internal, instagram, tiktok, twitter, etc.
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Analytics events table
CREATE TABLE IF NOT EXISTS public.analytics_events (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  event_name VARCHAR(100) NOT NULL,
  user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
  session_id VARCHAR(255),
  properties JSONB,
  platform VARCHAR(50),
  app_version VARCHAR(20),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Conversations table
CREATE TABLE IF NOT EXISTS public.conversations (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  participant_1_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
  participant_2_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
  last_message_id UUID,
  last_message_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(participant_1_id, participant_2_id)
);

-- Messages table
CREATE TABLE IF NOT EXISTS public.messages (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  conversation_id UUID REFERENCES public.conversations(id) ON DELETE CASCADE,
  sender_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
  content TEXT NOT NULL,
  message_type VARCHAR(20) DEFAULT 'text', -- text, image, video, audio, file
  media_url TEXT,
  is_read BOOLEAN DEFAULT FALSE,
  is_deleted BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_users_username ON public.users(username);
CREATE INDEX IF NOT EXISTS idx_users_email ON public.users(email);
CREATE INDEX IF NOT EXISTS idx_posts_user_id ON public.posts(user_id);
CREATE INDEX IF NOT EXISTS idx_posts_created_at ON public.posts(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_posts_type ON public.posts(type);
CREATE INDEX IF NOT EXISTS idx_posts_hashtags ON public.posts USING GIN(hashtags);
CREATE INDEX IF NOT EXISTS idx_comments_post_id ON public.comments(post_id);
CREATE INDEX IF NOT EXISTS idx_comments_user_id ON public.comments(user_id);
CREATE INDEX IF NOT EXISTS idx_comments_parent_id ON public.comments(parent_id);
CREATE INDEX IF NOT EXISTS idx_likes_user_id ON public.likes(user_id);
CREATE INDEX IF NOT EXISTS idx_likes_post_id ON public.likes(post_id);
CREATE INDEX IF NOT EXISTS idx_follows_follower_id ON public.follows(follower_id);
CREATE INDEX IF NOT EXISTS idx_follows_following_id ON public.follows(following_id);
CREATE INDEX IF NOT EXISTS idx_notifications_user_id ON public.notifications(user_id);
CREATE INDEX IF NOT EXISTS idx_notifications_created_at ON public.notifications(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_hashtags_name ON public.hashtags(name);
CREATE INDEX IF NOT EXISTS idx_hashtags_trending ON public.hashtags(is_trending, trending_score DESC);
CREATE INDEX IF NOT EXISTS idx_analytics_events_user_id ON public.analytics_events(user_id);
CREATE INDEX IF NOT EXISTS idx_analytics_events_created_at ON public.analytics_events(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_conversations_participant_1 ON public.conversations(participant_1_id);
CREATE INDEX IF NOT EXISTS idx_conversations_participant_2 ON public.conversations(participant_2_id);
CREATE INDEX IF NOT EXISTS idx_conversations_last_message_at ON public.conversations(last_message_at DESC);
CREATE INDEX IF NOT EXISTS idx_messages_conversation_id ON public.messages(conversation_id);
CREATE INDEX IF NOT EXISTS idx_messages_sender_id ON public.messages(sender_id);
CREATE INDEX IF NOT EXISTS idx_messages_created_at ON public.messages(created_at DESC);

-- Enable Row Level Security on all tables
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.posts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.comments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.likes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.follows ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hashtags ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.post_hashtags ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.blocks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.saves ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.shares ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.analytics_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

-- Basic RLS policies (you may need to customize these based on your app's requirements)

-- Cleanup: Drop existing policies to allow idempotent re-runs
DROP POLICY IF EXISTS "Users can view public profiles" ON public.users;
DROP POLICY IF EXISTS "Users can update own profile" ON public.users;
DROP POLICY IF EXISTS "Users can insert own profile" ON public.users;

DROP POLICY IF EXISTS "Users can view public posts" ON public.posts;
DROP POLICY IF EXISTS "Users can insert own posts" ON public.posts;
DROP POLICY IF EXISTS "Users can update own posts" ON public.posts;
DROP POLICY IF EXISTS "Users can delete own posts" ON public.posts;

DROP POLICY IF EXISTS "Users can view comments on visible posts" ON public.comments;
DROP POLICY IF EXISTS "Users can insert comments" ON public.comments;
DROP POLICY IF EXISTS "Users can update own comments" ON public.comments;
DROP POLICY IF EXISTS "Users can delete own comments" ON public.comments;

DROP POLICY IF EXISTS "Users can view likes" ON public.likes;
DROP POLICY IF EXISTS "Users can insert own likes" ON public.likes;
DROP POLICY IF EXISTS "Users can delete own likes" ON public.likes;

DROP POLICY IF EXISTS "Users can view follows" ON public.follows;
DROP POLICY IF EXISTS "Users can insert own follows" ON public.follows;
DROP POLICY IF EXISTS "Users can delete own follows" ON public.follows;

DROP POLICY IF EXISTS "Users can view own notifications" ON public.notifications;
DROP POLICY IF EXISTS "Users can update own notifications" ON public.notifications;

DROP POLICY IF EXISTS "Anyone can view hashtags" ON public.hashtags;

DROP POLICY IF EXISTS "Users can view post hashtags" ON public.post_hashtags;

DROP POLICY IF EXISTS "Users can insert reports" ON public.reports;
DROP POLICY IF EXISTS "Users can view own reports" ON public.reports;

DROP POLICY IF EXISTS "Users can manage own blocks" ON public.blocks;

DROP POLICY IF EXISTS "Users can manage own saves" ON public.saves;

DROP POLICY IF EXISTS "Users can insert own shares" ON public.shares;
DROP POLICY IF EXISTS "Users can view own shares" ON public.shares;

DROP POLICY IF EXISTS "Users can insert own analytics" ON public.analytics_events;

DROP POLICY IF EXISTS "Users can view own conversations" ON public.conversations;
DROP POLICY IF EXISTS "Users can insert conversations" ON public.conversations;
DROP POLICY IF EXISTS "Users can update own conversations" ON public.conversations;

DROP POLICY IF EXISTS "Users can view messages in their conversations" ON public.messages;
DROP POLICY IF EXISTS "Users can insert messages in their conversations" ON public.messages;
DROP POLICY IF EXISTS "Users can update own messages" ON public.messages;
DROP POLICY IF EXISTS "Recipients can mark messages as read" ON public.messages;

-- End cleanup

-- Users policies
CREATE POLICY "Users can view public profiles" ON public.users
  FOR SELECT USING (is_private = false OR auth.uid() = id);

CREATE POLICY "Users can update own profile" ON public.users
  FOR UPDATE USING (auth.uid() = id);

CREATE POLICY "Users can insert own profile" ON public.users
  FOR INSERT WITH CHECK (auth.uid() = id);

-- Posts policies
CREATE POLICY "Users can view public posts" ON public.posts
  FOR SELECT USING (is_public = true OR user_id = auth.uid());

CREATE POLICY "Users can insert own posts" ON public.posts
  FOR INSERT WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users can update own posts" ON public.posts
  FOR UPDATE USING (user_id = auth.uid());

CREATE POLICY "Users can delete own posts" ON public.posts
  FOR DELETE USING (user_id = auth.uid());

-- Comments policies
CREATE POLICY "Users can view comments on visible posts" ON public.comments
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.posts 
      WHERE posts.id = comments.post_id 
      AND (posts.is_public = true OR posts.user_id = auth.uid())
    )
  );

CREATE POLICY "Users can insert comments" ON public.comments
  FOR INSERT WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users can update own comments" ON public.comments
  FOR UPDATE USING (user_id = auth.uid());

CREATE POLICY "Users can delete own comments" ON public.comments
  FOR DELETE USING (user_id = auth.uid());

-- Likes policies
CREATE POLICY "Users can view likes" ON public.likes
  FOR SELECT USING (true);

CREATE POLICY "Users can insert own likes" ON public.likes
  FOR INSERT WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users can delete own likes" ON public.likes
  FOR DELETE USING (user_id = auth.uid());

-- Follows policies
CREATE POLICY "Users can view follows" ON public.follows
  FOR SELECT USING (true);

CREATE POLICY "Users can insert own follows" ON public.follows
  FOR INSERT WITH CHECK (follower_id = auth.uid());

CREATE POLICY "Users can delete own follows" ON public.follows
  FOR DELETE USING (follower_id = auth.uid());

-- Notifications policies
CREATE POLICY "Users can view own notifications" ON public.notifications
  FOR SELECT USING (user_id = auth.uid());

CREATE POLICY "Users can update own notifications" ON public.notifications
  FOR UPDATE USING (user_id = auth.uid());

-- Hashtags policies (public read, system managed)
CREATE POLICY "Anyone can view hashtags" ON public.hashtags
  FOR SELECT USING (true);

-- Post hashtags policies
CREATE POLICY "Users can view post hashtags" ON public.post_hashtags
  FOR SELECT USING (true);

-- Reports policies
CREATE POLICY "Users can insert reports" ON public.reports
  FOR INSERT WITH CHECK (reporter_id = auth.uid());

CREATE POLICY "Users can view own reports" ON public.reports
  FOR SELECT USING (reporter_id = auth.uid());

-- Blocks policies
CREATE POLICY "Users can manage own blocks" ON public.blocks
  FOR ALL USING (blocker_id = auth.uid());

-- Saves policies
CREATE POLICY "Users can manage own saves" ON public.saves
  FOR ALL USING (user_id = auth.uid());

-- Shares policies
CREATE POLICY "Users can insert own shares" ON public.shares
  FOR INSERT WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users can view own shares" ON public.shares
  FOR SELECT USING (user_id = auth.uid());

-- Analytics policies
CREATE POLICY "Users can insert own analytics" ON public.analytics_events
  FOR INSERT WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users can view own analytics" ON public.analytics_events
  FOR SELECT USING (
    -- Allow reading events created by the authenticated user
    user_id = auth.uid() 
    OR 
    -- Allow post owners to read analytics events associated with their posts (safe UUID check)
    (
      properties ? 'post_id' AND
      (analytics_events.properties->>'post_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' AND
      EXISTS (
        SELECT 1 FROM public.posts 
        WHERE posts.id = (analytics_events.properties->>'post_id')::uuid 
          AND posts.user_id = auth.uid()
      )
    )
  );

-- Conversations policies
CREATE POLICY "Users can view own conversations" ON public.conversations
  FOR SELECT USING (participant_1_id = auth.uid() OR participant_2_id = auth.uid());

CREATE POLICY "Users can insert conversations" ON public.conversations
  FOR INSERT WITH CHECK (participant_1_id = auth.uid() OR participant_2_id = auth.uid());

CREATE POLICY "Users can update own conversations" ON public.conversations
  FOR UPDATE USING (participant_1_id = auth.uid() OR participant_2_id = auth.uid());

-- Messages policies
CREATE POLICY "Users can view messages in their conversations" ON public.messages
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.conversations 
      WHERE conversations.id = messages.conversation_id 
      AND (conversations.participant_1_id = auth.uid() OR conversations.participant_2_id = auth.uid())
    )
  );

CREATE POLICY "Users can insert messages in their conversations" ON public.messages
  FOR INSERT WITH CHECK (
    sender_id = auth.uid() AND
    EXISTS (
      SELECT 1 FROM public.conversations 
      WHERE conversations.id = conversation_id 
      AND (conversations.participant_1_id = auth.uid() OR conversations.participant_2_id = auth.uid())
    )
  );

CREATE POLICY "Users can update own messages" ON public.messages
  FOR UPDATE USING (sender_id = auth.uid());

CREATE POLICY "Recipients can mark messages as read" ON public.messages
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM public.conversations 
      WHERE conversations.id = messages.conversation_id 
      AND (conversations.participant_1_id = auth.uid() OR conversations.participant_2_id = auth.uid())
    )
    AND messages.sender_id <> auth.uid()
  )
  WITH CHECK (
    is_read = true AND
    EXISTS (
      SELECT 1 FROM public.conversations 
      WHERE conversations.id = messages.conversation_id 
      AND (conversations.participant_1_id = auth.uid() OR conversations.participant_2_id = auth.uid())
    )
    AND messages.sender_id <> auth.uid()
  );

-- Database functions for updating counts
CREATE OR REPLACE FUNCTION increment_user_followers_count(user_id UUID)
RETURNS void AS $$
BEGIN
  UPDATE public.users SET followers_count = followers_count + 1 WHERE id = user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION decrement_user_followers_count(user_id UUID)
RETURNS void AS $$
BEGIN
  UPDATE public.users SET followers_count = GREATEST(0, followers_count - 1) WHERE id = user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION increment_user_following_count(user_id UUID)
RETURNS void AS $$
BEGIN
  UPDATE public.users SET following_count = following_count + 1 WHERE id = user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION decrement_user_following_count(user_id UUID)
RETURNS void AS $$
BEGIN
  UPDATE public.users SET following_count = GREATEST(0, following_count - 1) WHERE id = user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION increment_post_likes_count(post_id UUID)
RETURNS void AS $$
BEGIN
  UPDATE public.posts SET likes_count = likes_count + 1 WHERE id = post_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION decrement_post_likes_count(post_id UUID)
RETURNS void AS $$
BEGIN
  UPDATE public.posts SET likes_count = GREATEST(0, likes_count - 1) WHERE id = post_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger to automatically create user profile when auth user is created
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.users (id, email, username, display_name)
  VALUES (
    new.id,
    new.email,
    COALESCE(new.raw_user_meta_data->>'username', split_part(new.email, '@', 1)),
    COALESCE(new.raw_user_meta_data->>'display_name', split_part(new.email, '@', 1))
  );
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger on auth.users table
CREATE OR REPLACE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();

-- Storage buckets setup (run these in Supabase Storage)
-- You'll need to create these buckets manually in Supabase Dashboard > Storage
-- Bucket names: profile-images, post-images, post-videos, post-audio, thumbnails

-- Storage policies (run after creating buckets)
-- Profile images bucket policies
-- INSERT INTO storage.policies (bucket_id, name, definition) VALUES 
-- ('profile-images', 'Users can upload own profile images', 'bucket_id = ''profile-images'' AND auth.uid()::text = (storage.foldername(name))[1]');

-- Post images bucket policies  
-- INSERT INTO storage.policies (bucket_id, name, definition) VALUES
-- ('post-images', 'Users can upload post images', 'bucket_id = ''post-images'' AND auth.uid()::text = (storage.foldername(name))[1]');

-- Post videos bucket policies
-- INSERT INTO storage.policies (bucket_id, name, definition) VALUES
-- ('post-videos', 'Users can upload post videos', 'bucket_id = ''post-videos'' AND auth.uid()::text = (storage.foldername(name))[1]');

-- Post audio bucket policies
-- INSERT INTO storage.policies (bucket_id, name, definition) VALUES
-- ('post-audio', 'Users can upload post audio', 'bucket_id = ''post-audio'' AND auth.uid()::text = (storage.foldername(name))[1]');

-- Thumbnails bucket policies
-- INSERT INTO storage.policies (bucket_id, name, definition) VALUES
-- ('thumbnails', 'Users can upload thumbnails', 'bucket_id = ''thumbnails'' AND auth.uid()::text = (storage.foldername(name))[1]');

COMMIT;

-- Success message
SELECT 'Database setup completed successfully! All tables, indexes, RLS policies, and functions have been created.' AS message;