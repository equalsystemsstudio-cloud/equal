# Supabase Storage Setup for Equal App

After running the database setup SQL, you need to create storage buckets for file uploads. Follow these steps:

## 1. Create Storage Buckets

Go to your Supabase Dashboard → Storage → Create Bucket and create these buckets:

### Required Buckets:
- **profile-images** - For user profile pictures and cover photos
- **post-images** - For photo posts and image content
- **post-videos** - For video posts and video content
- **post-audio** - For audio posts and voice recordings
- **thumbnails** - For video thumbnails and preview images

### Bucket Settings:
- **Public**: ✅ Enable (so images/videos can be viewed publicly)
- **File size limit**: 50MB (adjust as needed)
- **Allowed MIME types**: 
  - profile-images: `image/jpeg, image/png, image/webp, image/gif`
  - post-images: `image/jpeg, image/png, image/webp, image/gif`
  - post-videos: `video/mp4, video/webm, video/quicktime`
  - post-audio: `audio/mpeg, audio/wav, audio/ogg, audio/mp4`
  - thumbnails: `image/jpeg, image/png, image/webp`

## 2. Set Up Storage Policies

After creating the buckets, go to Storage → Policies and create these policies:

### Profile Images Policies:
```sql
-- Allow users to upload their own profile images
CREATE POLICY "Users can upload own profile images" ON storage.objects
FOR INSERT WITH CHECK (
  bucket_id = 'profile-images' AND 
  auth.uid()::text = (storage.foldername(name))[1]
);

-- Allow users to view all profile images
CREATE POLICY "Anyone can view profile images" ON storage.objects
FOR SELECT USING (bucket_id = 'profile-images');

-- Allow users to update their own profile images
CREATE POLICY "Users can update own profile images" ON storage.objects
FOR UPDATE USING (
  bucket_id = 'profile-images' AND 
  auth.uid()::text = (storage.foldername(name))[1]
);

-- Allow users to delete their own profile images
CREATE POLICY "Users can delete own profile images" ON storage.objects
FOR DELETE USING (
  bucket_id = 'profile-images' AND 
  auth.uid()::text = (storage.foldername(name))[1]
);
```

### Post Images Policies:
```sql
-- Allow users to upload post images
CREATE POLICY "Users can upload post images" ON storage.objects
FOR INSERT WITH CHECK (
  bucket_id = 'post-images' AND 
  auth.uid()::text = (storage.foldername(name))[1]
);

-- Allow anyone to view post images
CREATE POLICY "Anyone can view post images" ON storage.objects
FOR SELECT USING (bucket_id = 'post-images');

-- Allow users to update their own post images
CREATE POLICY "Users can update own post images" ON storage.objects
FOR UPDATE USING (
  bucket_id = 'post-images' AND 
  auth.uid()::text = (storage.foldername(name))[1]
);

-- Allow users to delete their own post images
CREATE POLICY "Users can delete own post images" ON storage.objects
FOR DELETE USING (
  bucket_id = 'post-images' AND 
  auth.uid()::text = (storage.foldername(name))[1]
);
```

### Post Videos Policies:
```sql
-- Allow users to upload post videos
CREATE POLICY "Users can upload post videos" ON storage.objects
FOR INSERT WITH CHECK (
  bucket_id = 'post-videos' AND 
  auth.uid()::text = (storage.foldername(name))[1]
);

-- Allow anyone to view post videos
CREATE POLICY "Anyone can view post videos" ON storage.objects
FOR SELECT USING (bucket_id = 'post-videos');

-- Allow users to update their own post videos
CREATE POLICY "Users can update own post videos" ON storage.objects
FOR UPDATE USING (
  bucket_id = 'post-videos' AND 
  auth.uid()::text = (storage.foldername(name))[1]
);

-- Allow users to delete their own post videos
CREATE POLICY "Users can delete own post videos" ON storage.objects
FOR DELETE USING (
  bucket_id = 'post-videos' AND 
  auth.uid()::text = (storage.foldername(name))[1]
);
```

### Post Audio Policies:
```sql
-- Allow users to upload post audio
CREATE POLICY "Users can upload post audio" ON storage.objects
FOR INSERT WITH CHECK (
  bucket_id = 'post-audio' AND 
  auth.uid()::text = (storage.foldername(name))[1]
);

-- Allow anyone to view post audio
CREATE POLICY "Anyone can view post audio" ON storage.objects
FOR SELECT USING (bucket_id = 'post-audio');

-- Allow users to update their own post audio
CREATE POLICY "Users can update own post audio" ON storage.objects
FOR UPDATE USING (
  bucket_id = 'post-audio' AND 
  auth.uid()::text = (storage.foldername(name))[1]
);

-- Allow users to delete their own post audio
CREATE POLICY "Users can delete own post audio" ON storage.objects
FOR DELETE USING (
  bucket_id = 'post-audio' AND 
  auth.uid()::text = (storage.foldername(name))[1]
);
```

### Thumbnails Policies:
```sql
-- Allow users to upload thumbnails
CREATE POLICY "Users can upload thumbnails" ON storage.objects
FOR INSERT WITH CHECK (
  bucket_id = 'thumbnails' AND 
  auth.uid()::text = (storage.foldername(name))[1]
);

-- Allow anyone to view thumbnails
CREATE POLICY "Anyone can view thumbnails" ON storage.objects
FOR SELECT USING (bucket_id = 'thumbnails');

-- Allow users to update their own thumbnails
CREATE POLICY "Users can update own thumbnails" ON storage.objects
FOR UPDATE USING (
  bucket_id = 'thumbnails' AND 
  auth.uid()::text = (storage.foldername(name))[1]
);

-- Allow users to delete their own thumbnails
CREATE POLICY "Users can delete own thumbnails" ON storage.objects
FOR DELETE USING (
  bucket_id = 'thumbnails' AND 
  auth.uid()::text = (storage.foldername(name))[1]
);
```

## 3. Setup Instructions

1. **Run Database Setup**: First, execute the `database_setup.sql` file in your Supabase SQL Editor
2. **Create Buckets**: Create all 5 storage buckets as listed above
3. **Apply Storage Policies**: Run each policy SQL block in the SQL Editor
4. **Test Upload**: Try uploading a test file to verify everything works

## 4. File Organization Structure

Files will be organized in buckets using this structure:
```
profile-images/
  ├── {user_id}/
      ├── avatar.jpg
      ├── cover.jpg
      └── ...

post-images/
  ├── {user_id}/
      ├── {post_id}.jpg
      └── ...

post-videos/
  ├── {user_id}/
      ├── {post_id}.mp4
      └── ...

post-audio/
  ├── {user_id}/
      ├── {post_id}.mp3
      └── ...

thumbnails/
  ├── {user_id}/
      ├── {post_id}_thumb.jpg
      └── ...
```

## 5. Important Notes

- The storage policies use the folder structure to ensure users can only access their own files
- All buckets are set to public for easy viewing of content
- File size limits can be adjusted in the bucket settings
- Make sure to enable RLS (Row Level Security) on storage.objects table
- Test the upload functionality after setup to ensure everything works correctly

After completing this setup, your Equal app will be ready for file uploads and user registration!