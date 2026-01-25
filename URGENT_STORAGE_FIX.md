# URGENT: Storage Buckets Missing - Profile Upload Fix

## 🚨 PROBLEM IDENTIFIED

The profile photo upload is failing because **the storage buckets don't exist in your Supabase project**.

Diagnostic results show:
- ❌ profile-images bucket missing
- ❌ post-images bucket missing  
- ❌ post-videos bucket missing
- ❌ post-audio bucket missing (likely)
- ❌ thumbnails bucket missing (likely)

## 🛠️ IMMEDIATE FIX REQUIRED

### Step 1: Create Storage Buckets

1. **Go to your Supabase Dashboard**
   - Open https://supabase.com/dashboard
   - Select your Equal project

2. **Navigate to Storage**
   - Click "Storage" in the left sidebar
   - Click "Create a new bucket"

3. **Create these buckets with these EXACT settings:**

#### Bucket: `profile-images`
- **Name**: `profile-images`
- **Public**: ✅ Yes (checked)
- **File size limit**: 50 MB
- **Allowed MIME types**: `image/jpeg,image/png,image/webp,image/gif,image/svg+xml`

#### Bucket: `post-images`
- **Name**: `post-images`
- **Public**: ✅ Yes (checked)
- **File size limit**: 50 MB
- **Allowed MIME types**: `image/jpeg,image/png,image/webp,image/gif,image/svg+xml`

#### Bucket: `post-videos`
- **Name**: `post-videos`
- **Public**: ✅ Yes (checked)
- **File size limit**: 500 MB
- **Allowed MIME types**: `video/mp4,video/quicktime,video/x-msvideo,video/webm`

#### Bucket: `post-audio`
- **Name**: `post-audio`
- **Public**: ✅ Yes (checked)
- **File size limit**: 100 MB
- **Allowed MIME types**: `audio/mpeg,audio/wav,audio/ogg,audio/mp4,audio/webm`

#### Bucket: `thumbnails`
- **Name**: `thumbnails`
- **Public**: ✅ Yes (checked)
- **File size limit**: 10 MB
- **Allowed MIME types**: `image/jpeg,image/png,image/webp`

### Step 2: Apply Storage Policies

1. **Go to SQL Editor**
   - In Supabase Dashboard, click "SQL Editor"
   - Click "New query"

2. **Copy and paste the entire contents of `supabase_storage_policies.sql`**

3. **Run the SQL**
   - Click "Run" to execute all policies
   - Should see "Success. No rows returned" for each policy

### Step 3: Verify Fix

1. **Run diagnostics again**:
   ```bash
   node test_supabase.js
   ```

2. **Should now show**:
   - ✅ profile-images bucket exists
   - ✅ post-images bucket exists
   - ✅ post-videos bucket exists

3. **Test profile upload**:
   - Go to your app at http://localhost:3004
   - Navigate to profile edit
   - Try uploading a profile photo
   - Should work without "Failed to upload profile" error

## 🎯 WHY THIS HAPPENED

The storage buckets were never created in your Supabase project. The app code was trying to upload to non-existent buckets, causing the upload failures.

## ⚡ PRIORITY

**This is a HIGH PRIORITY fix** - without these buckets, users cannot:
- Upload profile photos
- Upload post images
- Upload videos
- Use any media features

## 📞 NEXT STEPS

1. Create the buckets immediately (5 minutes)
2. Apply the SQL policies (2 minutes)
3. Test the upload (1 minute)
4. **Total fix time: ~8 minutes**

After this fix, profile photo uploads will work perfectly!