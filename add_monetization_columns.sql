-- Add monetization columns to posts table
-- This script adds the necessary columns for the fair viral algorithm and ad serving

-- Add monetization-related columns
ALTER TABLE posts 
ADD COLUMN IF NOT EXISTS ads_enabled BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS monetization_enabled_at TIMESTAMP WITH TIME ZONE,
ADD COLUMN IF NOT EXISTS viral_score DECIMAL(10,4);

-- Create index for monetization queries
CREATE INDEX IF NOT EXISTS idx_posts_ads_enabled ON posts(ads_enabled);
CREATE INDEX IF NOT EXISTS idx_posts_monetization_enabled_at ON posts(monetization_enabled_at);
CREATE INDEX IF NOT EXISTS idx_posts_viral_score ON posts(viral_score);

-- Create index for engagement-based queries (for viral algorithm)
CREATE INDEX IF NOT EXISTS idx_posts_engagement ON posts(likes_count, comments_count, shares_count, created_at);

-- Create function to automatically check and enable monetization
CREATE OR REPLACE FUNCTION check_monetization_eligibility()
RETURNS TRIGGER AS $$
BEGIN
    -- Check if post meets monetization thresholds (1K likes, 250 comments)
    IF NEW.likes_count >= 1000 AND NEW.comments_count >= 250 AND OLD.ads_enabled = FALSE THEN
        NEW.ads_enabled = TRUE;
        NEW.monetization_enabled_at = NOW();
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger to automatically enable monetization when thresholds are met
DROP TRIGGER IF EXISTS trigger_check_monetization ON posts;
CREATE TRIGGER trigger_check_monetization
    BEFORE UPDATE ON posts
    FOR EACH ROW
    EXECUTE FUNCTION check_monetization_eligibility();

-- Create function to calculate viral score
CREATE OR REPLACE FUNCTION calculate_viral_score(post_id UUID)
RETURNS DECIMAL(10,4) AS $$
DECLARE
    post_record RECORD;
    age_hours DECIMAL;
    engagement_score DECIMAL;
    velocity DECIMAL;
    quality_multiplier DECIMAL;
    recency_boost DECIMAL;
    viral_score DECIMAL;
BEGIN
    -- Get post data
    SELECT likes_count, comments_count, shares_count, views_count, created_at
    INTO post_record
    FROM posts
    WHERE id = post_id;
    
    -- Calculate age in hours
    age_hours := EXTRACT(EPOCH FROM (NOW() - post_record.created_at)) / 3600;
    
    -- Prevent division by zero
    IF age_hours <= 0 THEN
        RETURN 0;
    END IF;
    
    -- Calculate base engagement score
    engagement_score := (
        (post_record.likes_count * 1.0) +
        (post_record.comments_count * 2.0) +
        (post_record.shares_count * 3.0) +
        (post_record.views_count * 0.1)
    );
    
    -- Calculate velocity (engagement per hour)
    velocity := engagement_score / age_hours;
    
    -- Calculate quality multiplier
    quality_multiplier := 1.0;
    IF post_record.comments_count > 0 THEN
        quality_multiplier := quality_multiplier + 0.3;
    END IF;
    IF post_record.shares_count > 0 THEN
        quality_multiplier := quality_multiplier + 0.5;
    END IF;
    IF post_record.likes_count > post_record.comments_count * 5 THEN
        quality_multiplier := quality_multiplier + 0.2;
    END IF;
    
    -- Penalty for posts with only likes (potential bot activity)
    IF post_record.likes_count > 100 AND post_record.comments_count = 0 THEN
        quality_multiplier := quality_multiplier * 0.7;
    END IF;
    
    -- Recency boost (posts within 24 hours)
    recency_boost := CASE WHEN age_hours <= 24 THEN 1.2 ELSE 1.0 END;
    
    -- Calculate final viral score
    viral_score := velocity * quality_multiplier * recency_boost;
    
    RETURN viral_score;
END;
$$ LANGUAGE plpgsql;

-- Create function to update viral scores for all posts
CREATE OR REPLACE FUNCTION update_all_viral_scores()
RETURNS INTEGER AS $$
DECLARE
    post_record RECORD;
    updated_count INTEGER := 0;
BEGIN
    -- Update viral scores for posts from the last 7 days
    FOR post_record IN 
        SELECT id FROM posts 
        WHERE created_at >= NOW() - INTERVAL '7 days'
        AND is_public = TRUE
    LOOP
        UPDATE posts 
        SET viral_score = calculate_viral_score(post_record.id)
        WHERE id = post_record.id;
        
        updated_count := updated_count + 1;
    END LOOP;
    
    RETURN updated_count;
END;
$$ LANGUAGE plpgsql;

-- Create a scheduled job to update viral scores (run this manually or set up a cron job)
-- This should be run every hour to keep viral scores fresh
-- SELECT update_all_viral_scores();

-- Grant necessary permissions
GRANT EXECUTE ON FUNCTION check_monetization_eligibility() TO authenticated;
GRANT EXECUTE ON FUNCTION calculate_viral_score(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION update_all_viral_scores() TO authenticated;

-- Add RLS policies for monetization data
CREATE POLICY "Users can view monetization status" ON posts
    FOR SELECT USING (true);

CREATE POLICY "Only system can update monetization status" ON posts
    FOR UPDATE USING (auth.role() = 'service_role');

-- Insert initial viral scores for existing posts
-- This may take a while for large datasets
-- SELECT update_all_viral_scores();

COMMIT;