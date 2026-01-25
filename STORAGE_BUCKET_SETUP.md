# Storage Buckets Setup Guide

🎉 **Database setup completed successfully!** Now let's set up the storage buckets.

## Required Storage Buckets

You need to create these 5 buckets in your Supabase Dashboard:

### 1. Go to Storage in Supabase Dashboard
- Open your Supabase project dashboard
- Click **Storage** in the left sidebar
- Click **New bucket** button

### 2. Create These Buckets:

#### Bucket 1: `profile-images`
- **Name**: `profile-images`
- **Public bucket**: ✅ Yes
- **File size limit**: 5MB
- **Allowed MIME types**: `image/jpeg,image/png,image/webp`

#### Bucket 2: `post-images`
- **Name**: `post-images`
- **Public bucket**: ✅ Yes
- **File size limit**: 10MB
- **Allowed MIME types**: `image/jpeg,image/png,image/webp,image/gif`

#### Bucket 3: `post-videos`
- **Name**: `post-videos`
- **Public bucket**: ✅ Yes
- **File size limit**: 50MB
- **Allowed MIME types**: `video/mp4,video/webm,video/quicktime`

#### Bucket 4: `post-audio`
- **Name**: `post-audio`
- **Public bucket**: ✅ Yes
- **File size limit**: 25MB
- **Allowed MIME types**: `audio/mpeg,audio/wav,audio/mp4,audio/aac`

#### Bucket 5: `thumbnails`
- **Name**: `thumbnails`
- **Public bucket**: ✅ Yes
- **File size limit**: 2MB
- **Allowed MIME types**: `image/jpeg,image/png,image/webp`

## Storage Policies (Auto-Applied)

Once you create the buckets, you'll need to set up storage policies. Here's the SQL to run in your Supabase SQL Editor:

```sql
-- Profile images policies
CREATE POLICY "Allow authenticated uploads to profile-images" ON storage.objects
FOR INSERT WITH CHECK (
  bucket_id = 'profile-images' AND 
  auth.role() = 'authenticated' AND
  auth.uid()::text = (storage.foldername(name))[1]
);

CREATE POLICY "Allow public access to profile-images" ON storage.objects
FOR SELECT USING (bucket_id = 'profile-images');

CREATE POLICY "Allow users to update own profile-images" ON storage.objects
FOR UPDATE USING (
  bucket_id = 'profile-images' AND 
  auth.uid()::text = (storage.foldername(name))[1]
);

CREATE POLICY "Allow users to delete own profile-images" ON storage.objects
FOR DELETE USING (
  bucket_id = 'profile-images' AND 
  auth.uid()::text = (storage.foldername(name))[1]
);

-- Post images policies
CREATE POLICY "Allow authenticated uploads to post-images" ON storage.objects
FOR INSERT WITH CHECK (
  bucket_id = 'post-images' AND 
  auth.role() = 'authenticated' AND
  auth.uid()::text = (storage.foldername(name))[1]
);

CREATE POLICY "Allow public access to post-images" ON storage.objects
FOR SELECT USING (bucket_id = 'post-images');

CREATE POLICY "Allow users to update own post-images" ON storage.objects
FOR UPDATE USING (
  bucket_id = 'post-images' AND 
  auth.uid()::text = (storage.foldername(name))[1]
);

CREATE POLICY "Allow users to delete own post-images" ON storage.objects
FOR DELETE USING (
  bucket_id = 'post-images' AND 
  auth.uid()::text = (storage.foldername(name))[1]
);

-- Post videos policies
CREATE POLICY "Allow authenticated uploads to post-videos" ON storage.objects
FOR INSERT WITH CHECK (
  bucket_id = 'post-videos' AND 
  auth.role() = 'authenticated' AND
  auth.uid()::text = (storage.foldername(name))[1]
);

CREATE POLICY "Allow public access to post-videos" ON storage.objects
FOR SELECT USING (bucket_id = 'post-videos');

CREATE POLICY "Allow users to update own post-videos" ON storage.objects
FOR UPDATE USING (
  bucket_id = 'post-videos' AND 
  auth.uid()::text = (storage.foldername(name))[1]
);

CREATE POLICY "Allow users to delete own post-videos" ON storage.objects
FOR DELETE USING (
  bucket_id = 'post-videos' AND 
  auth.uid()::text = (storage.foldername(name))[1]
);

-- Post audio policies
CREATE POLICY "Allow authenticated uploads to post-audio" ON storage.objects
FOR INSERT WITH CHECK (
  bucket_id = 'post-audio' AND 
  auth.role() = 'authenticated' AND
  auth.uid()::text = (storage.foldername(name))[1]
);

CREATE POLICY "Allow public access to post-audio" ON storage.objects
FOR SELECT USING (bucket_id = 'post-audio');

CREATE POLICY "Allow users to update own post-audio" ON storage.objects
FOR UPDATE USING (
  bucket_id = 'post-audio' AND 
  auth.uid()::text = (storage.foldername(name))[1]
);

CREATE POLICY "Allow users to delete own post-audio" ON storage.objects
FOR DELETE USING (
  bucket_id = 'post-audio' AND 
  auth.uid()::text = (storage.foldername(name))[1]
);

-- Thumbnails policies
CREATE POLICY "Allow authenticated uploads to thumbnails" ON storage.objects
FOR INSERT WITH CHECK (
  bucket_id = 'thumbnails' AND 
  auth.role() = 'authenticated' AND
  auth.uid()::text = (storage.foldername(name))[1]
);

CREATE POLICY "Allow public access to thumbnails" ON storage.objects
FOR SELECT USING (bucket_id = 'thumbnails');

CREATE POLICY "Allow users to update own thumbnails" ON storage.objects
FOR UPDATE USING (
  bucket_id = 'thumbnails' AND 
  auth.uid()::text = (storage.foldername(name))[1]
);

CREATE POLICY "Allow users to delete own thumbnails" ON storage.objects
FOR DELETE USING (
  bucket_id = 'thumbnails' AND 
  auth.uid()::text = (storage.foldername(name))[1]
);
```

## File Organization Structure

Files will be organized like this:
```
profile-images/
  └── {user_id}/
      └── avatar.jpg
      └── cover.jpg

post-images/
  └── {user_id}/
      └── {post_id}.jpg

post-videos/
  └── {user_id}/
      └── {post_id}.mp4

post-audio/
  └── {user_id}/
      └── {post_id}.mp3

thumbnails/
  └── {user_id}/
      └── {post_id}_thumb.jpg
```

## Next Steps

1. ✅ Database setup completed
2. 🔄 Create the 5 storage buckets (you're doing this now)
3. 🔄 Run the storage policies SQL script
4. 🎯 Test your app's sign-up and file upload functionality

## Testing

Once everything is set up:
- Go to http://localhost:3000
- Try signing up with a new account
- Test uploading a profile picture
- Test creating a post with media

Your Equal app should now be fully functional! 🚀