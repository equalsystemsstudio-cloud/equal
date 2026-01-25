import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:typed_data';

class SupabaseConfig {
  // Replace these with your actual Supabase project credentials
  static const String supabaseUrl = 'https://jzougxfpnlyfhudcrlnz.supabase.co';
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imp6b3VneGZwbmx5Zmh1ZGNybG56Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTg1NTg3NzksImV4cCI6MjA3NDEzNDc3OX0.gGRkxyfWlzQC2UrX-QTSB0J4-4w5J_Q9ZezZLCaznPY',
  );

  // Storage bucket names
  static const String profileImagesBucket = 'profile-images';
  static const String postImagesBucket = 'post-images';
  static const String postVideosBucket = 'post-videos';
  static const String postAudioBucket = 'post-audio';
  static const String thumbnailsBucket = 'thumbnails';

  // Additional bucket aliases for compatibility
  static const String videosBucket = postVideosBucket;
  static const String imagesBucket = postImagesBucket;
  static const String audiosBucket = postAudioBucket;
  static const String avatarsBucket = profileImagesBucket;

  // Database table names
  static const String usersTable = 'users';
  static const String postsTable = 'posts';
  static const String commentsTable = 'comments';
  static const String likesTable = 'likes';
  static const String followsTable = 'follows';
  static const String notificationsTable = 'notifications';
  static const String hashtagsTable = 'hashtags';
  static const String postHashtagsTable = 'post_hashtags';
  static const String reportsTable = 'reports';
  static const String blocksTable = 'blocks';
  static const String savesTable = 'saves';
  static const String sharesTable = 'shares';

  // Real-time channels
  static const String postsChannel = 'posts_channel';
  static const String commentsChannel = 'comments_channel';
  static const String notificationsChannel = 'notifications_channel';
  static const String likesChannel = 'likes_channel';

  // File size limits (in bytes)
  static const int maxImageSize = 50 * 1024 * 1024; // 50MB
  static const int maxVideoSize = 100 * 1024 * 1024; // 100MB
  static const int maxAudioSize = 100 * 1024 * 1024; // 100MB
  static const int maxTextSize = 50 * 1024 * 1024; // 50MB

  // Content limits
  static const int maxCaptionLength = 2200;
  static const int maxCommentLength = 500;
  static const int maxBioLength = 150;
  static const int maxUsernameLength = 30;
  static const int maxDisplayNameLength = 50;

  // Pagination
  static const int defaultPageSize = 20;
  static const int maxPageSize = 50;

  // Cache durations (in minutes)
  static const int userCacheDuration = 30;
  static const int postCacheDuration = 15;
  static const int commentCacheDuration = 10;

  // Special account pinning configuration
  // Populate with the user IDs of special accounts that should be pinned at the top of feeds.
  // Example: ['00000000-0000-0000-0000-000000000000']
  static const List<String> specialAccountIds = [];
  // Number of hours posts from special accounts remain pinned at top before reverting to normal order
  static const int specialPinnedHours = 24;

  static SupabaseClient get client => Supabase.instance.client;

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
      debug: true, // Set to false in production
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.implicit,
        detectSessionInUri: true,
        autoRefreshToken: true,
      ),
    );
  }

  // Helper method to get storage URL
  static String getStorageUrl(String bucket, String path) {
    return client.storage.from(bucket).getPublicUrl(path);
  }

  // Helper method to upload file
  static Future<String> uploadFile(
    String bucket,
    String path,
    List<int> fileBytes, {
    Map<String, String>? metadata,
  }) async {
    await client.storage
        .from(bucket)
        .uploadBinary(
          path,
          Uint8List.fromList(fileBytes),
          fileOptions: FileOptions(
            cacheControl: '3600',
            upsert: false,
            contentType: _getContentType(path),
          ),
        );

    return getStorageUrl(bucket, path);
  }

  // Helper method to delete file
  static Future<void> deleteFile(String bucket, String path) async {
    await client.storage.from(bucket).remove([path]);
  }

  // Helper method to get content type from file extension
  static String _getContentType(String path) {
    final extension = path.split('.').last.toLowerCase();
    switch (extension) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'mp4':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'avi':
        return 'video/x-msvideo';
      case 'mp3':
        return 'audio/mpeg';
      case 'wav':
        return 'audio/wav';
      case 'aac':
        return 'audio/aac';
      default:
        return 'application/octet-stream';
    }
  }

  // Helper method to generate unique file name
  static String generateFileName(String userId, String extension) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return '${userId}_$timestamp.$extension';
  }

  // Helper method to get file extension from mime type
  static String getExtensionFromMimeType(String mimeType) {
    switch (mimeType) {
      case 'image/jpeg':
        return 'jpg';
      case 'image/png':
        return 'png';
      case 'image/gif':
        return 'gif';
      case 'image/webp':
        return 'webp';
      case 'video/mp4':
        return 'mp4';
      case 'video/quicktime':
        return 'mov';
      case 'video/x-msvideo':
        return 'avi';
      case 'audio/mpeg':
        return 'mp3';
      case 'audio/wav':
        return 'wav';
      case 'audio/aac':
        return 'aac';
      default:
        return 'bin';
    }
  }
}

// Database schema SQL for reference
// This should be executed in your Supabase SQL editor
const String databaseSchema = '''
-- Enable Row Level Security
ALTER DATABASE postgres SET "app.jwt_secret" TO 'your-jwt-secret';

-- Users table
CREATE TABLE IF NOT EXISTS users (
  id UUID REFERENCES auth.users(id) PRIMARY KEY,
  username VARCHAR(30) UNIQUE NOT NULL,
  display_name VARCHAR(50),
  bio TEXT,
  avatar_url TEXT,
  cover_url TEXT,
  email VARCHAR(255),
  phone VARCHAR(20),
  website VARCHAR(255),
  location VARCHAR(100),
  birth_date DATE,
  gender VARCHAR(20),
  is_verified BOOLEAN DEFAULT FALSE,
  is_private BOOLEAN DEFAULT FALSE,
  followers_count INTEGER DEFAULT 0,
  following_count INTEGER DEFAULT 0,
  posts_count INTEGER DEFAULT 0,
  likes_count INTEGER DEFAULT 0,
  language VARCHAR(10) DEFAULT 'en',
  theme VARCHAR(10) DEFAULT 'system',
  notifications_enabled BOOLEAN DEFAULT TRUE,
  push_notifications_enabled BOOLEAN DEFAULT TRUE,
  email_notifications_enabled BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Posts table
CREATE TABLE IF NOT EXISTS posts (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  type VARCHAR(20) NOT NULL, -- video, photo, text, audio, live, ai_generated
  caption TEXT,
  media_url TEXT,
  thumbnail_url TEXT,
  duration INTEGER, -- for video/audio in seconds
  width INTEGER,
  height INTEGER,
  file_size BIGINT,
  mime_type VARCHAR(100),
  likes_count INTEGER DEFAULT 0,
  comments_count INTEGER DEFAULT 0,
  shares_count INTEGER DEFAULT 0,
  views_count INTEGER DEFAULT 0,
  saves_count INTEGER DEFAULT 0,
  is_public BOOLEAN DEFAULT TRUE,
  allow_comments BOOLEAN DEFAULT TRUE,
  allow_duets BOOLEAN DEFAULT TRUE,
  location VARCHAR(100),
  music_id UUID,
  filter_id VARCHAR(50),
  effects JSONB,
  ai_metadata JSONB,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Comments table
CREATE TABLE IF NOT EXISTS comments (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  post_id UUID REFERENCES posts(id) ON DELETE CASCADE,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  parent_id UUID REFERENCES comments(id) ON DELETE CASCADE,
  text TEXT NOT NULL,
  likes_count INTEGER DEFAULT 0,
  replies_count INTEGER DEFAULT 0,
  is_pinned BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Likes table
CREATE TABLE IF NOT EXISTS likes (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  post_id UUID REFERENCES posts(id) ON DELETE CASCADE,
  comment_id UUID REFERENCES comments(id) ON DELETE CASCADE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(user_id, post_id),
  UNIQUE(user_id, comment_id)
);

-- Follows table
CREATE TABLE IF NOT EXISTS follows (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  follower_id UUID REFERENCES users(id) ON DELETE CASCADE,
  following_id UUID REFERENCES users(id) ON DELETE CASCADE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(follower_id, following_id)
);

-- Notifications table
CREATE TABLE IF NOT EXISTS notifications (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  actor_id UUID REFERENCES users(id) ON DELETE CASCADE,
  type VARCHAR(20) NOT NULL, -- follow, like, comment, mention, share
  post_id UUID REFERENCES posts(id) ON DELETE CASCADE,
  comment_id UUID REFERENCES comments(id) ON DELETE CASCADE,
  message TEXT,
  is_read BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Hashtags table
CREATE TABLE IF NOT EXISTS hashtags (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  name VARCHAR(100) UNIQUE NOT NULL,
  posts_count INTEGER DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Post hashtags junction table
CREATE TABLE IF NOT EXISTS post_hashtags (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  post_id UUID REFERENCES posts(id) ON DELETE CASCADE,
  hashtag_id UUID REFERENCES hashtags(id) ON DELETE CASCADE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(post_id, hashtag_id)
);

-- Reports table
CREATE TABLE IF NOT EXISTS reports (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  reporter_id UUID REFERENCES users(id) ON DELETE CASCADE,
  reported_user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  post_id UUID REFERENCES posts(id) ON DELETE CASCADE,
  comment_id UUID REFERENCES comments(id) ON DELETE CASCADE,
  reason VARCHAR(50) NOT NULL,
  description TEXT,
  status VARCHAR(20) DEFAULT 'pending',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Blocks table
CREATE TABLE IF NOT EXISTS blocks (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  blocker_id UUID REFERENCES users(id) ON DELETE CASCADE,
  blocked_id UUID REFERENCES users(id) ON DELETE CASCADE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(blocker_id, blocked_id)
);

-- Saves table
CREATE TABLE IF NOT EXISTS saves (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  post_id UUID REFERENCES posts(id) ON DELETE CASCADE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(user_id, post_id)
);

-- Shares table
CREATE TABLE IF NOT EXISTS shares (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  post_id UUID REFERENCES posts(id) ON DELETE CASCADE,
  platform VARCHAR(50), -- internal, instagram, tiktok, twitter, etc.
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_posts_user_id ON posts(user_id);
CREATE INDEX IF NOT EXISTS idx_posts_created_at ON posts(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_posts_type ON posts(type);
CREATE INDEX IF NOT EXISTS idx_comments_post_id ON comments(post_id);
CREATE INDEX IF NOT EXISTS idx_comments_user_id ON comments(user_id);
CREATE INDEX IF NOT EXISTS idx_likes_post_id ON likes(post_id);
CREATE INDEX IF NOT EXISTS idx_likes_user_id ON likes(user_id);
CREATE INDEX IF NOT EXISTS idx_follows_follower_id ON follows(follower_id);
CREATE INDEX IF NOT EXISTS idx_follows_following_id ON follows(following_id);
CREATE INDEX IF NOT EXISTS idx_notifications_user_id ON notifications(user_id);
CREATE INDEX IF NOT EXISTS idx_notifications_created_at ON notifications(created_at DESC);

-- Enable Row Level Security
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE posts ENABLE ROW LEVEL SECURITY;
ALTER TABLE comments ENABLE ROW LEVEL SECURITY;
ALTER TABLE likes ENABLE ROW LEVEL SECURITY;
ALTER TABLE follows ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE hashtags ENABLE ROW LEVEL SECURITY;
ALTER TABLE post_hashtags ENABLE ROW LEVEL SECURITY;
ALTER TABLE reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE blocks ENABLE ROW LEVEL SECURITY;
ALTER TABLE saves ENABLE ROW LEVEL SECURITY;
ALTER TABLE shares ENABLE ROW LEVEL SECURITY;
''';
