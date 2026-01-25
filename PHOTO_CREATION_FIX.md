# Photo Creation Screen Fix - Storage Policy Issue

## Issue Summary
The "Failed to publish photo" error in the PhotoCreationScreen is caused by missing Supabase storage policies. The storage buckets exist, but Row Level Security (RLS) policies are not configured, preventing authenticated users from uploading images.

## Root Cause
The error "new row violates row-level security policy" indicates that:
1. ✅ Storage buckets exist (`post-images`, `profile-images`, etc.)
2. ✅ Authentication is working
3. ❌ Storage policies are not applied to allow authenticated uploads

## Solution
You need to manually apply the storage policies in your Supabase dashboard.

### Step 1: Access Supabase SQL Editor
1. Go to your Supabase Dashboard: https://jzougxfpnlyfhudcrlnz.supabase.co
2. Navigate to **SQL Editor** in the left sidebar
3. Click **New Query**

### Step 2: Apply Storage Policies
1. Copy the entire contents of `supabase_storage_policies.sql`
2. Paste it into the SQL Editor
3. Click **Run** to execute all policies

### Step 3: Verify Policy Application
After running the SQL, you should see policies created for:
- `profile-images` bucket (4 policies)
- `post-images` bucket (4 policies)
- `post-videos` bucket (4 policies)
- `post-audio` bucket (4 policies)
- `thumbnails` bucket (4 policies)

## What the Policies Do

Each bucket gets 4 policies:

1. **INSERT Policy**: Allows authenticated users to upload files to their own folder
   ```sql
   FOR INSERT WITH CHECK (
     bucket_id = 'post-images' AND 
     auth.role() = 'authenticated' AND
     auth.uid()::text = (storage.foldername(name))[1]
   )
   ```

2. **SELECT Policy**: Allows public access to view images
   ```sql
   FOR SELECT USING (bucket_id = 'post-images')
   ```

3. **UPDATE Policy**: Allows users to update their own files
   ```sql
   FOR UPDATE USING (
     bucket_id = 'post-images' AND 
     auth.uid()::text = (storage.foldername(name))[1]
   )
   ```

4. **DELETE Policy**: Allows users to delete their own files
   ```sql
   FOR DELETE USING (
     bucket_id = 'post-images' AND 
     auth.uid()::text = (storage.foldername(name))[1]
   )
   ```

## Security Model

- **File Organization**: Files are stored in folders named with the user's ID
- **Authentication Required**: Only authenticated users can upload
- **User Isolation**: Users can only access their own files
- **Public Read**: Anyone can view uploaded images (for social media functionality)

## Testing the Fix

1. Apply the storage policies as described above
2. Open the Flutter app
3. Generate an AI image or take a photo
4. Try to publish the photo
5. The upload should now succeed

## Troubleshooting

If the issue persists after applying policies:

1. **Check Policy Creation**: Go to Supabase Dashboard → Storage → Policies to verify policies exist
2. **Verify Authentication**: Ensure the user is properly logged in
3. **Check Bucket Names**: Confirm bucket names match between app config and Supabase
4. **Review Error Messages**: The app now provides more specific error messages for policy issues

## Files Modified

- `photo_creation_screen.dart` - Added better error handling for storage policy issues
- `PHOTO_CREATION_FIX.md` - This documentation file

## Alternative Solutions

If manual policy application doesn't work:

1. **Recreate Buckets**: Delete and recreate storage buckets with proper settings
2. **Check RLS**: Ensure Row Level Security is enabled on `storage.objects` table
3. **Use Service Key**: Apply policies using Supabase service key with admin privileges

## Success Indicators

After applying the fix:
- ✅ Photo uploads complete successfully
- ✅ No "row-level security policy" errors
- ✅ Images appear in posts feed
- ✅ Generated AI images can be published

The PhotoCreationScreen now provides clearer error messages to help diagnose any remaining issues.