-- Create test conversations and messages to demonstrate messaging functionality
-- This script creates sample data for testing the enhanced messaging system

-- First, let's create some test users (if they don't exist)
-- Note: In a real app, users would be created through authentication
-- For testing purposes, we'll insert directly into auth.users if needed

-- Insert test conversations
-- Assuming we have at least 2 users in the system
INSERT INTO public.conversations (id, participant_1_id, participant_2_id, last_message_at, created_at, updated_at)
SELECT 
  gen_random_uuid(),
  u1.id,
  u2.id,
  NOW() - INTERVAL '1 hour',
  NOW() - INTERVAL '2 hours',
  NOW() - INTERVAL '1 hour'
FROM 
  (SELECT id FROM auth.users LIMIT 1 OFFSET 0) u1,
  (SELECT id FROM auth.users LIMIT 1 OFFSET 1) u2
WHERE u1.id != u2.id
ON CONFLICT (participant_1_id, participant_2_id) DO NOTHING;

-- Insert another test conversation
INSERT INTO public.conversations (id, participant_1_id, participant_2_id, last_message_at, created_at, updated_at)
SELECT 
  gen_random_uuid(),
  u1.id,
  u2.id,
  NOW() - INTERVAL '30 minutes',
  NOW() - INTERVAL '1 day',
  NOW() - INTERVAL '30 minutes'
FROM 
  (SELECT id FROM auth.users LIMIT 1 OFFSET 0) u1,
  (SELECT id FROM auth.users LIMIT 1 OFFSET 2) u2
WHERE u1.id != u2.id AND EXISTS (SELECT 1 FROM auth.users LIMIT 1 OFFSET 2)
ON CONFLICT (participant_1_id, participant_2_id) DO NOTHING;

-- Insert test messages for the conversations
WITH conversation_data AS (
  SELECT id as conversation_id, participant_1_id, participant_2_id 
  FROM public.conversations 
  LIMIT 2
)
INSERT INTO public.messages (id, conversation_id, sender_id, content, media_type, created_at)
SELECT 
  gen_random_uuid(),
  cd.conversation_id,
  cd.participant_1_id,
  'Hey there! How are you doing?',
  'text',
  NOW() - INTERVAL '2 hours'
FROM conversation_data cd
LIMIT 1;

-- Add reply message
WITH conversation_data AS (
  SELECT id as conversation_id, participant_1_id, participant_2_id 
  FROM public.conversations 
  LIMIT 1
)
INSERT INTO public.messages (id, conversation_id, sender_id, content, media_type, created_at)
SELECT 
  gen_random_uuid(),
  cd.conversation_id,
  cd.participant_2_id,
  'Hi! I\'m doing great, thanks for asking! How about you?',
  'text',
  NOW() - INTERVAL '1 hour 30 minutes'
FROM conversation_data cd;

-- Add more recent message
WITH conversation_data AS (
  SELECT id as conversation_id, participant_1_id, participant_2_id 
  FROM public.conversations 
  LIMIT 1
)
INSERT INTO public.messages (id, conversation_id, sender_id, content, media_type, created_at)
SELECT 
  gen_random_uuid(),
  cd.conversation_id,
  cd.participant_1_id,
  'That\'s awesome! I\'m doing well too. Want to grab coffee sometime?',
  'text',
  NOW() - INTERVAL '1 hour'
FROM conversation_data cd;

-- Update conversations with last message info
UPDATE public.conversations 
SET 
  last_message_id = (
    SELECT m.id 
    FROM public.messages m 
    WHERE m.conversation_id = conversations.id 
    ORDER BY m.created_at DESC 
    LIMIT 1
  ),
  last_message_at = (
    SELECT m.created_at 
    FROM public.messages m 
    WHERE m.conversation_id = conversations.id 
    ORDER BY m.created_at DESC 
    LIMIT 1
  ),
  updated_at = NOW()
WHERE EXISTS (
  SELECT 1 FROM public.messages m 
  WHERE m.conversation_id = conversations.id
);

-- Display results
SELECT 'Test conversations created successfully!' as result;

-- Show created conversations
SELECT 
  c.id,
  c.participant_1_id,
  c.participant_2_id,
  c.last_message_at,
  COUNT(m.id) as message_count
FROM public.conversations c
LEFT JOIN public.messages m ON c.id = m.conversation_id
GROUP BY c.id, c.participant_1_id, c.participant_2_id, c.last_message_at
ORDER BY c.last_message_at DESC;