-- Fix statuses table schema to add missing is_ai_generated column
-- This addresses the PostgreSQL error: Could not find the 'is_ai_generated' column of 'statuses'

BEGIN;

-- Add missing columns to statuses table
ALTER TABLE public.statuses 
ADD COLUMN IF NOT EXISTS is_ai_generated BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS ai_prompt TEXT,
ADD COLUMN IF NOT EXISTS ai_model TEXT;

-- Update the type constraint to include ai_generated
ALTER TABLE public.statuses 
DROP CONSTRAINT IF EXISTS statuses_type_check;

ALTER TABLE public.statuses 
ADD CONSTRAINT statuses_type_check 
CHECK (type IN ('text','image','video','audio','ai_generated'));

-- Add effects column to store audio/video effects
ALTER TABLE public.statuses 
ADD COLUMN IF NOT EXISTS effects jsonb;

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_statuses_is_ai_generated ON public.statuses(is_ai_generated);
CREATE INDEX IF NOT EXISTS idx_statuses_type ON public.statuses(type);

COMMIT;

-- Verify the fix
SELECT 
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns 
WHERE table_schema = 'public' 
  AND table_name = 'statuses'
  AND column_name IN ('is_ai_generated', 'ai_prompt', 'ai_model')
ORDER BY column_name;