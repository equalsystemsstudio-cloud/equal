-- Supabase Storage Policies for Equal App
-- Run this after creating the storage buckets in Supabase Dashboard

-- =============================================
-- DROP EXISTING POLICIES (IF ANY)
-- =============================================

-- Drop existing policies to avoid conflicts
DROP POLICY IF EXISTS "Allow authenticated uploads to profile-images" ON storage.objects;
DROP POLICY IF EXISTS "Allow public access to profile-images" ON storage.objects;
DROP POLICY IF EXISTS "Allow users to update own profile-images" ON storage.objects;
DROP POLICY IF EXISTS "Allow users to delete own profile-images" ON storage.objects;

DROP POLICY IF EXISTS "Allow authenticated uploads to post-images" ON storage.objects;
DROP POLICY IF EXISTS "Allow public access to post-images" ON storage.objects;
DROP POLICY IF EXISTS "Allow users to update own post-images" ON storage.objects;
DROP POLICY IF EXISTS "Allow users to delete own post-images" ON storage.objects;

DROP POLICY IF EXISTS "Allow authenticated uploads to post-videos" ON storage.objects;
DROP POLICY IF EXISTS "Allow public access to post-videos" ON storage.objects;
DROP POLICY IF EXISTS "Allow users to update own post-videos" ON storage.objects;
DROP POLICY IF EXISTS "Allow users to delete own post-videos" ON storage.objects;

DROP POLICY IF EXISTS "Allow authenticated uploads to post-audio" ON storage.objects;
DROP POLICY IF EXISTS "Allow public access to post-audio" ON storage.objects;
DROP POLICY IF EXISTS "Allow users to update own post-audio" ON storage.objects;
DROP POLICY IF EXISTS "Allow users to delete own post-audio" ON storage.objects;

DROP POLICY IF EXISTS "Allow authenticated uploads to thumbnails" ON storage.objects;
DROP POLICY IF EXISTS "Allow public access to thumbnails" ON storage.objects;
DROP POLICY IF EXISTS "Allow users to update own thumbnails" ON storage.objects;
DROP POLICY IF EXISTS "Allow users to delete own thumbnails" ON storage.objects;

-- =============================================
-- PROFILE IMAGES POLICIES
-- =============================================

-- Allow authenticated users to upload their own profile images
CREATE POLICY "Allow authenticated uploads to profile-images" ON storage.objects
FOR INSERT WITH CHECK (
  bucket_id = 'profile-images' AND 
  auth.role() = 'authenticated' AND
  auth.uid()::text = (storage.foldername(name))[1]
);

-- Allow users to view all profile images
CREATE POLICY "Allow public access to profile-images" ON storage.objects
FOR SELECT USING (bucket_id = 'profile-images');

-- Allow users to update their own profile images
CREATE POLICY "Allow users to update own profile-images" ON storage.objects
FOR UPDATE USING (
  bucket_id = 'profile-images' AND 
  auth.uid()::text = (storage.foldername(name))[1]
);

-- Allow users to delete their own profile images
CREATE POLICY "Allow users to delete own profile-images" ON storage.objects
FOR DELETE USING (
  bucket_id = 'profile-images' AND 
  auth.uid()::text = (storage.foldername(name))[1]
);

-- =============================================
-- POST IMAGES POLICIES
-- =============================================

-- Allow authenticated users to upload post images
CREATE POLICY "Allow authenticated uploads to post-images" ON storage.objects
FOR INSERT WITH CHECK (
  bucket_id = 'post-images' AND 
  auth.role() = 'authenticated' AND
  auth.uid()::text = (storage.foldername(name))[1]
);

-- Allow anyone to view post images
CREATE POLICY "Allow public access to post-images" ON storage.objects
FOR SELECT USING (bucket_id = 'post-images');

-- Allow users to update their own post images
CREATE POLICY "Allow users to update own post-images" ON storage.objects
FOR UPDATE USING (
  bucket_id = 'post-images' AND 
  auth.uid()::text = (storage.foldername(name))[1]
);

-- Allow users to delete their own post images
CREATE POLICY "Allow users to delete own post-images" ON storage.objects
FOR DELETE USING (
  bucket_id = 'post-images' AND 
  auth.uid()::text = (storage.foldername(name))[1]
);

-- =============================================
-- POST VIDEOS POLICIES
-- =============================================

-- Allow authenticated users to upload post videos
CREATE POLICY "Allow authenticated uploads to post-videos" ON storage.objects
FOR INSERT WITH CHECK (
  bucket_id = 'post-videos' AND 
  auth.role() = 'authenticated' AND
  auth.uid()::text = (storage.foldername(name))[1]
);

-- Allow anyone to view post videos
CREATE POLICY "Allow public access to post-videos" ON storage.objects
FOR SELECT USING (bucket_id = 'post-videos');

-- Allow users to update their own post videos
CREATE POLICY "Allow users to update own post-videos" ON storage.objects
FOR UPDATE USING (
  bucket_id = 'post-videos' AND 
  auth.uid()::text = (storage.foldername(name))[1]
);

-- Allow users to delete their own post videos
CREATE POLICY "Allow users to delete own post-videos" ON storage.objects
FOR DELETE USING (
  bucket_id = 'post-videos' AND 
  auth.uid()::text = (storage.foldername(name))[1]
);

-- =============================================
-- POST AUDIO POLICIES
-- =============================================

-- Allow authenticated users to upload post audio
CREATE POLICY "Allow authenticated uploads to post-audio" ON storage.objects
FOR INSERT WITH CHECK (
  bucket_id = 'post-audio' AND 
  auth.role() = 'authenticated' AND
  auth.uid()::text = (storage.foldername(name))[1]
);

-- Allow anyone to view post audio
CREATE POLICY "Allow public access to post-audio" ON storage.objects
FOR SELECT USING (bucket_id = 'post-audio');

-- Allow users to update their own post audio
CREATE POLICY "Allow users to update own post-audio" ON storage.objects
FOR UPDATE USING (
  bucket_id = 'post-audio' AND 
  auth.uid()::text = (storage.foldername(name))[1]
);

-- Allow users to delete their own post audio
CREATE POLICY "Allow users to delete own post-audio" ON storage.objects
FOR DELETE USING (
  bucket_id = 'post-audio' AND 
  auth.uid()::text = (storage.foldername(name))[1]
);

-- =============================================
-- THUMBNAILS POLICIES
-- =============================================

-- Allow authenticated users to upload thumbnails
CREATE POLICY "Allow authenticated uploads to thumbnails" ON storage.objects
FOR INSERT WITH CHECK (
  bucket_id = 'thumbnails' AND 
  auth.role() = 'authenticated' AND
  auth.uid()::text = (storage.foldername(name))[1]
);

-- Allow anyone to view thumbnails
CREATE POLICY "Allow public access to thumbnails" ON storage.objects
FOR SELECT USING (bucket_id = 'thumbnails');

-- Allow users to update their own thumbnails
CREATE POLICY "Allow users to update own thumbnails" ON storage.objects
FOR UPDATE USING (
  bucket_id = 'thumbnails' AND 
  auth.uid()::text = (storage.foldername(name))[1]
);

-- Allow users to delete their own thumbnails
CREATE POLICY "Allow users to delete own thumbnails" ON storage.objects
FOR DELETE USING (
  bucket_id = 'thumbnails' AND 
  auth.uid()::text = (storage.foldername(name))[1]
);

-- =============================================
-- SETUP COMPLETE
-- =============================================
-- All storage policies have been created!
-- Make sure you have created the following buckets in Supabase Dashboard:
-- 1. profile-images (Public: Yes, Size limit: 50MB, MIME types: image/jpeg,image/png,image/webp,image/gif)
-- 2. post-images (Public: Yes, Size limit: 50MB, MIME types: image/jpeg,image/png,image/webp,image/gif)
-- 3. post-videos (Public: Yes, Size limit: 100MB, MIME types: video/mp4,video/webm,video/quicktime)
-- 4. post-audio (Public: Yes, Size limit: 50MB, MIME types: audio/mpeg,audio/wav,audio/mp4,audio/aac)
-- 5. thumbnails (Public: Yes, Size limit: 10MB, MIME types: image/jpeg,image/png,image/webp)
--
-- IMPORTANT: Run these policies in your Supabase SQL Editor after creating the buckets!
-- Also ensure Row Level Security (RLS) is enabled on the storage.objects table.