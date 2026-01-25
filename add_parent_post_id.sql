-- Add parent_post_id field to posts table for harmony/duet relationships
ALTER TABLE public.posts 
ADD COLUMN IF NOT EXISTS parent_post_id UUID REFERENCES public.posts(id) ON DELETE CASCADE;

-- Create index for better performance when querying harmonies
CREATE INDEX IF NOT EXISTS idx_posts_parent_post_id ON public.posts(parent_post_id);

-- Verify the column was added
SELECT column_name, data_type, is_nullable
FROM information_schema.columns 
WHERE table_schema = 'public' 
  AND table_name = 'posts'
  AND column_name = 'parent_post_id';