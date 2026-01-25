-- Add missing database functions for comment functionality

-- Function to increment post comments count
CREATE OR REPLACE FUNCTION public.increment_post_comments_count(post_id UUID)
RETURNS void AS $$
BEGIN
  UPDATE public.posts 
  SET comments_count = COALESCE(comments_count, 0) + 1,
      updated_at = NOW()
  WHERE id = post_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to decrement post comments count
CREATE OR REPLACE FUNCTION public.decrement_post_comments_count(post_id UUID)
RETURNS void AS $$
BEGIN
  UPDATE public.posts 
  SET comments_count = GREATEST(COALESCE(comments_count, 0) - 1, 0),
      updated_at = NOW()
  WHERE id = post_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to increment post views count
CREATE OR REPLACE FUNCTION public.increment_post_views_count(post_id UUID)
RETURNS void AS $$
BEGIN
  UPDATE public.posts 
  SET views_count = COALESCE(views_count, 0) + 1,
      updated_at = NOW()
  WHERE id = post_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permissions for views function
GRANT EXECUTE ON FUNCTION public.increment_post_views_count(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.increment_post_comments_count(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.decrement_post_comments_count(UUID) TO authenticated;