-- Add missing database functions for comment likes functionality

-- Function to increment comment likes count
CREATE OR REPLACE FUNCTION public.increment_comment_likes_count(comment_id UUID)
RETURNS void AS $$
BEGIN
  UPDATE public.comments 
  SET likes_count = COALESCE(likes_count, 0) + 1,
      updated_at = NOW()
  WHERE id = comment_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to decrement comment likes count
CREATE OR REPLACE FUNCTION public.decrement_comment_likes_count(comment_id UUID)
RETURNS void AS $$
BEGIN
  UPDATE public.comments 
  SET likes_count = GREATEST(COALESCE(likes_count, 0) - 1, 0),
      updated_at = NOW()
  WHERE id = comment_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION public.increment_comment_likes_count(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.decrement_comment_likes_count(UUID) TO authenticated;