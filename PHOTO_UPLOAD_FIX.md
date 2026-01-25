# Photo Upload Fix - Storage Policies Update

## Issue
User profile photos are not being uploaded successfully. The issue is related to Supabase storage policies that restrict image uploads.

## Root Cause
The original `supabase_storage_policies.sql` file was empty, meaning no storage policies were applied to the Supabase storage buckets. Without proper policies, authenticated users cannot upload images to the storage buckets.

## Solution
I've updated the `supabase_storage_policies.sql` file with comprehensive storage policies that:

1. **Allow any image type** - The policies don't restrict MIME types at the policy level
2. **Support authenticated uploads** - Users can upload their own profile images
3. **Enable public access** - Profile images can be viewed by anyone
4. **Allow user management** - Users can update/delete their own images

## Updated Policies

The new policies support these buckets:
- `profile-images` - For user avatars and profile photos
- `post-images` - For post attachments
- `post-videos` - For video content
- `post-audio` - For audio content
- `thumbnails` - For video thumbnails

## Supported Image Types

The Flutter app already supports these image formats:
- JPEG (.jpg, .jpeg)
- PNG (.png)
- GIF (.gif)
- WebP (.webp)
- SVG (.svg)

## How to Apply the Fix

### Step 1: Apply Storage Policies
1. Open your Supabase Dashboard
2. Go to the SQL Editor
3. Copy the contents of `supabase_storage_policies.sql`
4. Run the SQL commands in your Supabase project

**Note**: The SQL file now includes `DROP POLICY IF EXISTS` statements to safely remove any existing policies before creating new ones, preventing "policy already exists" errors.

### Step 2: Verify Bucket Configuration
Ensure these buckets exist in your Supabase Storage with these settings:

**profile-images bucket:**
- Public: Yes
- Size limit: 50MB
- Allowed MIME types: `image/jpeg,image/png,image/webp,image/gif,image/svg+xml`

**post-images bucket:**
- Public: Yes
- Size limit: 50MB
- Allowed MIME types: `image/jpeg,image/png,image/webp,image/gif,image/svg+xml`

### Step 3: Enable Row Level Security
Make sure Row Level Security (RLS) is enabled on the `storage.objects` table.

## Testing the Fix

1. Navigate to the user profile screen
2. Tap on the profile photo
3. Select "Gallery" or "Camera"
4. Choose any supported image format
5. The image should upload successfully

## Technical Details

### Policy Structure
Each bucket has four policies:
1. **INSERT** - Allows authenticated users to upload to their own folder
2. **SELECT** - Allows public access to view images
3. **UPDATE** - Allows users to update their own images
4. **DELETE** - Allows users to delete their own images

### Security
- Users can only upload to folders named with their user ID
- Authentication is required for uploads
- Public read access for viewing images
- Users can only modify their own content

### Bucket Mapping
The app uses these bucket configurations:
- `avatarsBucket` → `profile-images`
- `imagesBucket` → `post-images`
- `videosBucket` → `post-videos`
- `audiosBucket` → `post-audio`
- `thumbnailsBucket` → `thumbnails`

## Troubleshooting

If photo uploads still don't work after applying the policies:

1. **Check Authentication**: Ensure the user is properly logged in
2. **Verify Bucket Names**: Make sure bucket names match between the app config and Supabase
3. **Check Network**: Ensure there are no network connectivity issues
4. **Review Logs**: Check browser console and Supabase logs for specific errors
5. **Test Permissions**: Try uploading directly through Supabase Dashboard

## Files Modified
- `supabase_storage_policies.sql` - Added comprehensive storage policies
- `PHOTO_UPLOAD_FIX.md` - This documentation file

The Flutter code already supports all common image formats and doesn't need modification.