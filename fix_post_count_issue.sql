-- Fix for post count issue: Add missing decrement_user_posts_count function
-- This function is called when posts are deleted but was missing from the database

CREATE OR REPLACE FUNCTION public.decrement_user_posts_count(user_id UUID)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $f$
  UPDATE public.users
  SET posts_count = GREATEST(0, COALESCE(posts_count, 0) - 1)
  WHERE id = user_id;
$f$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION public.decrement_user_posts_count(UUID) TO authenticated;

-- Fix existing post counts by recalculating them based on actual posts
-- This will correct any users who have inflated post counts due to the missing function
UPDATE public.users 
SET posts_count = (
  SELECT COUNT(*) 
  FROM public.posts 
  WHERE posts.user_id = users.id 
    AND posts.is_public = true
);

COMMIT;

-- Success message
SELECT 'Post count issue fixed! Added decrement function and recalculated all user post counts.' AS message;