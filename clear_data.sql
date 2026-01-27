-- SQL Script to clear mock data and reset content
-- Run this in your Supabase SQL Editor

-- 1. Clear all live streams
DELETE FROM live_streams;

-- 2. Clear all posts (as requested "no posts at all for now")
DELETE FROM posts;

-- 3. Delete mock users (optional, but good for cleanup)
-- Deletes from public.users. If you have foreign key constraints with ON DELETE CASCADE,
-- this might automatically clean up related data.
DELETE FROM users WHERE username LIKE 'mock_%';

-- Note: To delete users from the Authentication system (auth.users), 
-- you would need to use the Supabase Dashboard > Authentication > Users,
-- or use the Admin API (provided in scripts/clear_mock_data.js).
