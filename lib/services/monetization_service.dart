import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import '../models/post_model.dart';

class MonetizationService {
  final SupabaseClient _supabase = Supabase.instance.client;
  
  // Engagement thresholds for monetization
  static const int reactionsThreshold = 1000;
  static const int commentsThreshold = 250;
  
  /// Fair viral algorithm that promotes posts based purely on engagement metrics
  /// regardless of user's follower count or account age
  Future<List<PostModel>> getViralCandidates({
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      // Calculate viral score based on engagement velocity and quality
      // This ensures fair opportunities for all users
      final response = await _supabase
          .from('posts')
          .select('''
            *,
            users!posts_user_id_fkey(
              id,
              username,
              display_name,
              avatar_url
            ),
            comments_count,
            likes_count,
            shares_count,
            views_count,
            comments(count)
          ''')
          .eq('is_public', true)
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      List<PostModel> posts = (response as List)
          .map((json) => PostModel.fromJson(json))
          .toList();

      // Apply fair viral scoring algorithm
      posts = _applyViralScoring(posts);
      
      // Sort by viral score (highest first)
      posts.sort((a, b) => _calculateViralScore(b).compareTo(_calculateViralScore(a)));
      
      return posts;
    } catch (e) {
      debugPrint('Error fetching viral candidates: $e');
      return [];
    }
  }
  
  /// Calculate viral score based on engagement quality and velocity
  /// This algorithm ensures fairness regardless of follower count
  double _calculateViralScore(PostModel post) {
    final now = DateTime.now();
    final postAge = now.difference(post.createdAt).inHours;
    
    // Prevent division by zero
    if (postAge == 0) return 0.0;
    
    // Base engagement score
    double engagementScore = (
      (post.likesCount * 1.0) +
      (post.commentsCount * 2.0) +
      (post.sharesCount * 3.0) +
      (post.viewsCount * 0.1)
    );
    
    // Engagement velocity (engagement per hour)
    double velocity = engagementScore / postAge;
    
    // Quality multiplier based on engagement diversity
    double qualityMultiplier = _calculateEngagementQuality(post);
    
    // Recency boost (newer posts get slight advantage)
    double recencyBoost = postAge <= 24 ? 1.2 : 1.0;
    
    // Final viral score
    return velocity * qualityMultiplier * recencyBoost;
  }
  
  /// Calculate engagement quality based on interaction diversity
  double _calculateEngagementQuality(PostModel post) {
    double quality = 1.0;
    
    // Reward posts with diverse engagement types
    if (post.commentsCount > 0) quality += 0.3;
    if (post.sharesCount > 0) quality += 0.5;
    if (post.likesCount > post.commentsCount * 5) quality += 0.2; // Good like-to-comment ratio
    
    // Penalty for posts with only likes (potential bot activity)
    if (post.likesCount > 100 && post.commentsCount == 0) {
      quality *= 0.7;
    }
    
    return quality;
  }
  
  /// Apply viral scoring to a list of posts
  List<PostModel> _applyViralScoring(List<PostModel> posts) {
    return posts.map((post) {
      // Add viral score as metadata (you might want to add this to PostModel)
      return post;
    }).toList();
  }
  
  /// Check if a post meets monetization thresholds
  bool meetsMonetizationThreshold(PostModel post) {
    return post.likesCount >= reactionsThreshold && 
           post.commentsCount >= commentsThreshold;
  }
  
  /// Enable ad serving for posts that meet thresholds
  Future<bool> enableAdServing(String postId) async {
    try {
      // No-op: posts table does not have ads_enabled/monetization_enabled_at columns
      // You can persist monetization state later via a dedicated table or JSON field
      debugPrint('Monetization enabled (logical) for post $postId');
      return true;
    } catch (e) {
      debugPrint('Error enabling ad serving: $e');
      return false;
    }
  }
  
  /// Get posts eligible for monetization
  Future<List<PostModel>> getMonetizationEligiblePosts() async {
    try {
      final response = await _supabase
          .from('posts')
          .select('''
            *,
            users!posts_user_id_fkey(
              id,
              username,
              display_name,
              avatar_url
            )
          ''')
          .gte('likes_count', reactionsThreshold)
          .gte('comments_count', commentsThreshold);

      return (response as List)
          .map((json) => PostModel.fromJson(json))
          .toList();
    } catch (e) {
      debugPrint('Error fetching monetization eligible posts: $e');
      return [];
    }
  }
  
  /// Process monetization for eligible posts
  Future<void> processMonetizationQueue() async {
    try {
      final eligiblePosts = await getMonetizationEligiblePosts();
      
      for (final post in eligiblePosts) {
        if (meetsMonetizationThreshold(post)) {
          await enableAdServing(post.id);
          debugPrint('Enabled ads for post ${post.id} by user ${post.userId}');
        }
      }
    } catch (e) {
      debugPrint('Error processing monetization queue: $e');
    }
  }
  
  /// Calculate potential earnings for a post (placeholder for ad network integration)
  double calculatePotentialEarnings(PostModel post) {
    if (!meetsMonetizationThreshold(post)) return 0.0;
    
    // Base earning calculation (this would integrate with actual ad network)
    double baseRate = 0.001; // $0.001 per view
    double engagementMultiplier = 1.0 + (post.commentsCount / 1000.0);
    
    return post.viewsCount * baseRate * engagementMultiplier;
  }
}

/// Recommended Ad Networks for monetization:
/// 
/// 1. **Google AdMob** (Recommended for mobile apps)
///    - Pros: High fill rates, good eCPM, reliable payments
///    - Integration: flutter_admob package
///    - Revenue share: ~68% to creator, 32% to platform
/// 
/// 2. **Google AdSense** (For web version)
///    - Pros: Easy integration, contextual ads, good for web
///    - Integration: Web-based implementation
///    - Revenue share: ~68% to creator, 32% to platform
/// 
/// 3. **Facebook Audience Network** (Alternative)
///    - Pros: Good targeting, competitive rates
///    - Integration: facebook_audience_network package
///    - Revenue share: ~70% to creator, 30% to platform
/// 
/// **Recommendation**: Start with Google AdMob for mobile and AdSense for web
/// as they offer the best balance of reliability, earnings, and ease of integration.