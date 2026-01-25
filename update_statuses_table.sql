-- Update existing statuses table to add AI-related columns
-- Execute this in your Supabase SQL Editor: https://jzougxfpnlyfhudcrlnz.supabase.co

-- Add new columns to existing statuses table
ALTER TABLE public.statuses 
ADD COLUMN IF NOT EXISTS is_ai_generated boolean DEFAULT false,
ADD COLUMN IF NOT EXISTS ai_prompt text,
ADD COLUMN IF NOT EXISTS ai_model text;

-- Update the type constraint to include 'audio'
ALTER TABLE public.statuses 
DROP CONSTRAINT IF EXISTS statuses_type_check;

ALTER TABLE public.statuses 
ADD CONSTRAINT statuses_type_check 
CHECK (type IN ('text','image','video','audio','ai_generated'));

-- Add effects column
ALTER TABLE public.statuses 
ADD COLUMN IF NOT EXISTS effects jsonb;

-- Add indexes for better performance
CREATE INDEX IF NOT EXISTS idx_statuses_type ON public.statuses(type);
CREATE INDEX IF NOT EXISTS idx_statuses_is_ai_generated ON public.statuses(is_ai_generated);

-- Success message
SELECT 'Statuses table updated successfully with AI columns!' AS message;