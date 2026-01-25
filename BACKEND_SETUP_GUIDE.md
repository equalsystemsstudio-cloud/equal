# Complete Backend Setup Guide

## New Supabase Project Credentials
- **Project URL**: `https://jzougxfpnlyfhudcrlnz.supabase.co`
- **Anon Key**: `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imp6b3VneGZwbmx5Zmh1ZGNybG56Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTg1NTg3NzksImV4cCI6MjA3NDEzNDc3OX0.gGRkxyfWlzQC2UrX-QTSB0J4-4w5J_Q9ZezZLCaznPY`

## Setup Steps

### 1. Execute SQL Script
1. Go to your Supabase Dashboard: https://jzougxfpnlyfhudcrlnz.supabase.co
2. Navigate to **SQL Editor** in the left sidebar
3. Click **New Query**
4. Copy the entire contents of `complete_backend_setup.sql`
5. Paste it into the SQL Editor
6. Click **Run** to execute the script

### 2. What This Script Creates

#### Database Tables:
- **users** - User profiles and settings
- **posts** - User posts with media support
- **comments** - Post comments with threading
- **likes** - Likes for posts and comments
- **follows** - User follow relationships
- **notifications** - Push and in-app notifications
- **hashtags** - Hashtag management
- **post_hashtags** - Post-hashtag relationships
- **reports** - Content reporting system
- **blocks** - User blocking system
- **saves** - Saved posts
- **shares** - Post sharing analytics
- **conversations** - Direct message conversations
- **messages** - Direct messages
- **analytics_events** - App usage analytics

#### Storage Buckets:
- **profile-images** - User profile pictures
- **post-images** - Post images
- **post-videos** - Post videos
- **post-audio** - Post audio files
- **thumbnails** - Video thumbnails
- **avatars** - User avatars (alias)
- **images** - General images
- **videos** - General videos
- **audio** - General audio files

#### Security Features:
- Row Level Security (RLS) policies for all tables
- Storage policies for secure file uploads
- User-based access control
- Automatic user profile creation on signup

#### Performance Features:
- Database indexes for fast queries
- Automatic count updates (followers, posts, likes)
- Real-time subscriptions for live updates

### 3. Verify Setup
After running the script, you should see:
- All tables created in the **Table Editor**
- All storage buckets in the **Storage** section
- Success message: "Complete backend setup completed successfully!"

### 4. Test Your App
Once the script is executed successfully:
1. Your Flutter app should connect to the new backend
2. User registration should work
3. Profile picture uploads should work
4. Post creation with media should work
5. All social features should be functional

## Troubleshooting

If you encounter any errors:
1. Make sure you're using the correct Supabase project
2. Check that you have admin access to the project
3. Try running the script in smaller chunks if it times out
4. Contact support if you see permission errors

## Next Steps

After successful setup:
1. Test user registration in your app
2. Try uploading a profile picture
3. Create a test post with media
4. Verify all features work as expected

Your Equal app backend is now fully configured with all necessary tables, security policies, and storage buckets!