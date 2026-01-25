# Equal App Database Setup Instructions

## Quick Setup Guide

### Step 1: Access Supabase SQL Editor
1. Go to your Supabase project dashboard
2. Navigate to **SQL Editor** in the left sidebar
3. Click **New Query**

### Step 2: Run the Database Setup
1. Copy the contents of `supabase_setup_simple.sql`
2. Paste it into the SQL Editor
3. Click **Run** to execute the script

### Step 3: Verify Tables Created
After running the script, you should see these tables in your **Table Editor**:
- `users` - User profiles and settings
- `posts` - User posts (images, videos, audio)
- `comments` - Comments on posts
- `likes` - Likes on posts and comments
- `follows` - User follow relationships
- `notifications` - User notifications

### Step 4: Set Up Storage Buckets
1. Go to **Storage** in your Supabase dashboard
2. Create these buckets (click **New bucket**):
   - `profile-images` (Public bucket)
   - `post-images` (Public bucket)
   - `post-videos` (Public bucket)
   - `post-audio` (Public bucket)
   - `thumbnails` (Public bucket)

### Step 5: Configure Storage Policies
For each bucket, set up these policies in **Storage > Policies**:

#### For all buckets:
```sql
-- Allow authenticated users to upload
CREATE POLICY "Allow authenticated uploads" ON storage.objects
FOR INSERT WITH CHECK (auth.role() = 'authenticated');

-- Allow public access to view files
CREATE POLICY "Allow public access" ON storage.objects
FOR SELECT USING (true);

-- Allow users to update their own files
CREATE POLICY "Allow users to update own files" ON storage.objects
FOR UPDATE USING (auth.uid()::text = (storage.foldername(name))[1]);

-- Allow users to delete their own files
CREATE POLICY "Allow users to delete own files" ON storage.objects
FOR DELETE USING (auth.uid()::text = (storage.foldername(name))[1]);
```

### Step 6: Test the Setup
1. Go back to your Flutter app at http://localhost:3000
2. Try to sign up with a new account
3. The sign-up should now work without errors

## Troubleshooting

### If you get permission errors:
- Make sure you're running the SQL in your own Supabase project
- Don't try to modify system settings like JWT secrets
- Use the simplified script instead of the complex one

### If tables don't appear:
- Check the SQL Editor for any error messages
- Make sure all SQL commands completed successfully
- Refresh your browser and check the Table Editor again

### If sign-up still fails:
- Check the browser console for error messages
- Verify your Supabase URL and anon key are correct
- Make sure RLS policies are properly set up

## What's Included

✅ **Database Tables**: All required tables with proper relationships
✅ **Row Level Security**: Secure access policies for all tables
✅ **Auto User Creation**: Automatic profile creation when users sign up
✅ **Proper Indexes**: Optimized for performance
✅ **Storage Setup**: Instructions for file upload buckets

## Next Steps

After completing this setup:
1. Test user registration and login
2. Test creating posts
3. Test following other users
4. Test the notification system

Your Equal app should now be fully functional with a complete backend!