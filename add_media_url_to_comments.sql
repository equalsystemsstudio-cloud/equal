-- Add audio_url and media_url columns to comments table (idempotent)
ALTER TABLE public.comments 
ADD COLUMN IF NOT EXISTS audio_url TEXT;

ALTER TABLE public.comments 
ADD COLUMN IF NOT EXISTS media_url TEXT;

-- Make content nullable to allow audio-only or image-only comments
ALTER TABLE public.comments 
ALTER COLUMN content DROP NOT NULL;

-- Update the check constraint to allow text-only, audio-only, or image-only comments
ALTER TABLE public.comments 
DROP CONSTRAINT IF EXISTS check_comment_has_content;

ALTER TABLE public.comments 
ADD CONSTRAINT check_comment_has_content 
CHECK (content IS NOT NULL OR audio_url IS NOT NULL OR media_url IS NOT NULL);