# Database Setup Guide

This guide explains how to set up the database schema for the Enhanced Social Media App with TikTok-style notifications and Facebook-style messaging.

## Prerequisites

- Supabase project set up
- Database access via Supabase Dashboard or SQL Editor

## Schema Overview

The database schema includes the following main tables:

### Core Tables
- `user_profiles` - User profile information
- `posts` - User posts and content
- `comments` - Comments on posts
- `likes` - Likes on posts and comments
- `follows` - User follow relationships

### Notification System (TikTok-style)
- `notifications` - All user notifications with rich metadata

### Messaging System (Facebook-style)
- `conversations` - Chat conversations between users
- `messages` - Individual messages with support for text, voice, image, and video

## Setup Instructions

### 1. Run the Schema

1. Open your Supabase project dashboard
2. Navigate to the SQL Editor
3. Copy the contents of `schema.sql`
4. Execute the SQL script

### 2. Verify Tables

After running the schema, verify these tables exist:
```sql
SELECT table_name 
FROM information_schema.tables 
WHERE table_schema = 'public' 
AND table_name IN (
    'notifications', 
    'conversations', 
    'messages', 
    'user_profiles', 
    'posts', 
    'comments', 
    'likes', 
    'follows'
);
```

### 3. Enable Realtime (Optional)

For real-time notifications and messaging, enable realtime on key tables:

```sql
-- Enable realtime for notifications
ALTER PUBLICATION supabase_realtime ADD TABLE notifications;

-- Enable realtime for conversations
ALTER PUBLICATION supabase_realtime ADD TABLE conversations;

-- Enable realtime for messages
ALTER PUBLICATION supabase_realtime ADD TABLE messages;
```

## Table Details

### Notifications Table

Stores all user notifications with support for:
- Like notifications
- Comment notifications
- Follow notifications
- Mention notifications
- Post notifications
- Message notifications

**Key Features:**
- Rich metadata with actor information
- Target references (posts, comments, users)
- Read/unread status
- Automatic timestamps

### Conversations Table

Manages chat conversations between two users:
- Unique constraint ensures one conversation per user pair
- Tracks last message for sorting
- Automatic timestamp updates

### Messages Table

Stores individual messages with support for:
- Text messages
- Voice notes
- Images
- Videos
- Read receipts

## Security

The schema includes comprehensive Row Level Security (RLS) policies:

- Users can only see their own notifications
- Users can only access conversations they participate in
- Users can only send messages in their conversations
- Public posts are visible to all, private posts only to owners
- Standard social media privacy controls

## Indexes

Optimized indexes are included for:
- Fast notification queries by user and date
- Efficient conversation loading
- Quick message retrieval
- Social media feed performance

## Triggers

Automatic triggers handle:
- Timestamp updates on record changes
- Conversation last message tracking
- Data consistency maintenance

## Sample Data (Optional)

To test the system, you can insert sample data:

```sql
-- Insert sample user profile
INSERT INTO user_profiles (id, username, display_name, bio, avatar_url)
VALUES (
    auth.uid(),
    'testuser',
    'Test User',
    'This is a test user profile',
    'https://example.com/avatar.jpg'
);

-- Insert sample notification
INSERT INTO notifications (user_id, type, title, message, actor_name)
VALUES (
    auth.uid(),
    'like',
    'New Like',
    'Someone liked your post',
    'John Doe'
);
```

## Troubleshooting

### Common Issues

1. **RLS Policies**: If you can't access data, check RLS policies are correctly set
2. **UUID Extension**: Ensure `uuid-ossp` extension is enabled
3. **Auth Context**: Make sure `auth.uid()` returns the correct user ID

### Useful Queries

```sql
-- Check notification count by type
SELECT type, COUNT(*) 
FROM notifications 
WHERE user_id = auth.uid() 
GROUP BY type;

-- Get recent conversations
SELECT * 
FROM conversations 
WHERE participant1_id = auth.uid() OR participant2_id = auth.uid()
ORDER BY last_message_at DESC;

-- Count unread messages
SELECT COUNT(*) 
FROM messages m
JOIN conversations c ON m.conversation_id = c.id
WHERE (c.participant1_id = auth.uid() OR c.participant2_id = auth.uid())
AND m.sender_id != auth.uid()
AND m.is_read = false;
```

## Next Steps

After setting up the database:

1. Test the Flutter app with real data
2. Configure push notifications
3. Set up media storage for voice notes and images
4. Implement analytics and monitoring
5. Add data backup and recovery procedures