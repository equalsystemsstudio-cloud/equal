-- Fix Storage Policies for Messaging
-- This script creates the missing 'media' bucket and applies proper policies

-- First, let's create policies for the existing buckets that messaging uses

-- =============================================
-- MEDIA BUCKET POLICIES (for messaging)
-- =============================================

-- Drop existing policies if they exist
DROP POLICY IF EXISTS "Allow authenticated uploads to media" ON storage.objects;
DROP POLICY IF EXISTS "Allow public access to media" ON storage.objects;
DROP POLICY IF EXISTS "Allow users to update own media" ON storage.objects;
DROP POLICY IF EXISTS "Allow users to delete own media" ON storage.objects;

-- Create policies for post-images bucket (used for chat images)
DROP POLICY IF EXISTS "Allow authenticated chat image uploads" ON storage.objects;
CREATE POLICY "Allow authenticated chat image uploads" ON storage.objects
FOR INSERT WITH CHECK (
  bucket_id = 'post-images' AND 
  auth.role() = 'authenticated'
);

-- Create policies for post-audio bucket (used for voice messages)
DROP POLICY IF EXISTS "Allow authenticated voice uploads" ON storage.objects;
CREATE POLICY "Allow authenticated voice uploads" ON storage.objects
FOR INSERT WITH CHECK (
  bucket_id = 'post-audio' AND 
  auth.role() = 'authenticated'
);

-- Allow public read access for chat media
DROP POLICY IF EXISTS "Allow public access to chat images" ON storage.objects;
CREATE POLICY "Allow public access to chat images" ON storage.objects
FOR SELECT USING (bucket_id = 'post-images');

DROP POLICY IF EXISTS "Allow public access to voice messages" ON storage.objects;
CREATE POLICY "Allow public access to voice messages" ON storage.objects
FOR SELECT USING (bucket_id = 'post-audio');

-- Allow users to delete their own chat media
DROP POLICY IF EXISTS "Allow users to delete own chat images" ON storage.objects;
CREATE POLICY "Allow users to delete own chat images" ON storage.objects
FOR DELETE USING (
  bucket_id = 'post-images' AND 
  auth.role() = 'authenticated'
);

DROP POLICY IF EXISTS "Allow users to delete own voice messages" ON storage.objects;
CREATE POLICY "Allow users to delete own voice messages" ON storage.objects
FOR DELETE USING (
  bucket_id = 'post-audio' AND 
  auth.role() = 'authenticated'
);

-- =============================================
-- SETUP COMPLETE
-- =============================================
-- Storage policies for messaging have been updated!
-- The messaging system now uses:
-- - post-images bucket for chat images
-- - post-audio bucket for voice messages
-- 
-- These policies allow:
-- 1. Authenticated users to upload images and voice messages
-- 2. Public access to view the media
-- 3. Users to delete their own uploads