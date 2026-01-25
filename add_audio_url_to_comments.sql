-- Add audio_url column to comments table for voice note functionality
ALTER TABLE public.comments 
ADD COLUMN IF NOT EXISTS audio_url TEXT;

-- Update the content column to be nullable since comments can now be voice-only
ALTER TABLE public.comments 
ALTER COLUMN content DROP NOT NULL;

-- Add a check constraint to ensure at least one of content or audio_url is provided
ALTER TABLE public.comments 
ADD CONSTRAINT check_comment_has_content 
CHECK (content IS NOT NULL OR audio_url IS NOT NULL);