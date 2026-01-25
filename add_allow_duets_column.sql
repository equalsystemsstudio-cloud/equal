-- Add missing allow_duets column to posts table
ALTER TABLE public.posts 
ADD COLUMN IF NOT EXISTS allow_duets BOOLEAN DEFAULT TRUE;

-- Update existing posts to have allow_duets = true
UPDATE public.posts 
SET allow_duets = TRUE 
WHERE allow_duets IS NULL;