import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:path/path.dart' as path;

class ContentService {
  final _supabase = Supabase.instance.client;

  // Post creation
  Future<Map<String, dynamic>?> createPost({
    required String content,
    String? mediaUrl,
    String? mediaType,
    String? thumbnailUrl,
    Map<String, dynamic>? metadata,
    List<String>? tags,
  }) async {
    try {
      final currentUser = _supabase.auth.currentUser;
      if (currentUser == null) throw Exception('User not authenticated');

      final response = await _supabase
          .from('posts')
          .insert({
            'user_id': currentUser.id,
            'content': content,
            'media_url': mediaUrl,
            'type': mediaType,
            'thumbnail_url': thumbnailUrl,
            'metadata': metadata,
            'tags': tags,
            'likes_count': 0,
            'comments_count': 0,
            'shares_count': 0,
            'created_at': DateTime.now().toIso8601String(),
          })
          .select('''
            id,
            content,
            media_url,
            type,
            thumbnail_url,
            metadata,
            tags,
            likes_count,
            comments_count,
            shares_count,
            created_at,
            users!posts_user_id_fkey(
              id,
              username,
              display_name,
              avatar_url
            )
          ''')
          .single();

      return response;
    } catch (e) {
      debugPrint('Error creating post: $e');
      return null;
    }
  }

  // Media upload
  Future<String?> uploadMedia({
    required File file,
    required String mediaType,
    String? userId,
  }) async {
    try {
      final currentUser = _supabase.auth.currentUser;
      if (currentUser == null) throw Exception('User not authenticated');

      final fileExt = path.extension(file.path);
      final fileName = '${DateTime.now().millisecondsSinceEpoch}_${currentUser.id}$fileExt';
      final filePath = '$mediaType/${currentUser.id}/$fileName';

      await _supabase.storage
          .from('media')
          .upload(filePath, file);

      final publicUrl = _supabase.storage
          .from('media')
          .getPublicUrl(filePath);

      return publicUrl;
    } catch (e) {
      debugPrint('Error uploading media: $e');
      return null;
    }
  }

  Future<String?> uploadMediaBytes({
    required Uint8List bytes,
    required String fileName,
    required String mediaType,
  }) async {
    try {
      final currentUser = _supabase.auth.currentUser;
      if (currentUser == null) throw Exception('User not authenticated');

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filePath = '$mediaType/${currentUser.id}/${timestamp}_$fileName';

      await _supabase.storage
          .from('media')
          .uploadBinary(filePath, bytes);

      final publicUrl = _supabase.storage
          .from('media')
          .getPublicUrl(filePath);

      return publicUrl;
    } catch (e) {
      debugPrint('Error uploading media bytes: $e');
      return null;
    }
  }

  // Get posts
  Future<List<Map<String, dynamic>>> getFeedPosts({
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final currentUser = _supabase.auth.currentUser;
      if (currentUser == null) throw Exception('User not authenticated');

      // Get posts from followed users and own posts
      final response = await _supabase
          .from('posts')
          .select('''
            id,
            content,
            media_url,
            type,
            thumbnail_url,
            metadata,
            tags,
            likes_count,
            comments_count,
            shares_count,
            created_at,
            users!posts_user_id_fkey(
              id,
              username,
              display_name,
              avatar_url
            )
          ''')
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Error getting feed posts: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getUserPosts(String userId, {
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final response = await _supabase
          .from('posts')
          .select('''
            id,
            content,
            media_url,
            type,
            thumbnail_url,
            metadata,
            tags,
            likes_count,
            comments_count,
            shares_count,
            created_at,
            users!posts_user_id_fkey(
              id,
              username,
              display_name,
              avatar_url
            )
          ''')
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Error getting user posts: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>?> getPost(String postId) async {
    try {
      final response = await _supabase
          .from('posts')
          .select('''
            id,
            user_id,
            content,
            media_url,
            type,
            thumbnail_url,
            // Removed: metadata (column does not exist)
            // Removed: tags (column does not exist); use hashtags if needed
            hashtags,
            likes_count,
            comments_count,
            shares_count,
            created_at,
            users!posts_user_id_fkey(
              id,
              username,
              display_name,
              avatar_url
            )
          ''')
          .eq('id', postId)
          .single();

      return response;
    } catch (e) {
      debugPrint('Error getting post: $e');
      return null;
    }
  }

  // Update post
  Future<bool> updatePost(String postId, {
    String? content,
    List<String>? tags,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final currentUser = _supabase.auth.currentUser;
      if (currentUser == null) throw Exception('User not authenticated');

      final updateData = <String, dynamic>{};
      if (content != null) updateData['content'] = content;
      if (tags != null) updateData['tags'] = tags;
      if (metadata != null) updateData['metadata'] = metadata;
      updateData['updated_at'] = DateTime.now().toIso8601String();

      await _supabase
          .from('posts')
          .update(updateData)
          .eq('id', postId)
          .eq('user_id', currentUser.id);

      return true;
    } catch (e) {
      debugPrint(('Error updating post: $e').toString());
      return false;
    }
  }

  // Delete post
  Future<bool> deletePost(String postId) async {
    try {
      final currentUser = _supabase.auth.currentUser;
      if (currentUser == null) throw Exception('User not authenticated');

      // Get post details to delete associated media
      final post = await _supabase
          .from('posts')
          .select('media_url, thumbnail_url')
          .eq('id', postId)
          .eq('user_id', currentUser.id)
          .single();

      // Delete associated media files
      if (post['media_url'] != null) {
        await _deleteMediaFromUrl(post['media_url']);
      }
      if (post['thumbnail_url'] != null) {
        await _deleteMediaFromUrl(post['thumbnail_url']);
      }

      // Delete post from database
      await _supabase
          .from('posts')
          .delete()
          .eq('id', postId)
          .eq('user_id', currentUser.id);

      // Note: posts_count is updated by DB trigger on posts; no manual decrement here

      return true;
    } catch (e) {
      debugPrint(('Error deleting post: $e').toString());
      return false;
    }
  }

  Future<void> _deleteMediaFromUrl(String url) async {
    try {
      // Extract file path from public URL
      final uri = Uri.parse(url);
      final pathSegments = uri.pathSegments;
      if (pathSegments.length >= 3) {
        final filePath = pathSegments.sublist(2).join('/');
        await _supabase.storage.from('media').remove([filePath]);
      }
    } catch (e) {
      debugPrint(('Error deleting media file: $e').toString());
    }
  }

  // Get liked posts
  Future<List<Map<String, dynamic>>> getLikedPosts(String userId, {
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      // Step 1: fetch liked post IDs for the target user
      final likesResponse = await _supabase
          .from('likes')
          .select('post_id, created_at')
          .not('post_id', 'is', null)
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      final likes = List<Map<String, dynamic>>.from(likesResponse);
      debugPrint(('[ContentService.getLikedPosts] likes count: ${likes.length}').toString());
      final postIds = likes
          .map((l) => l['post_id'])
          .where((id) => id != null)
          .toList();
      debugPrint(('[ContentService.getLikedPosts] liked post IDs: $postIds').toString());

      if (postIds.isEmpty) {
        return [];
      }

      // Step 2: fetch posts for those IDs (respecting RLS for public/own posts)
      final orFilter = postIds.map((id) => 'id.eq.$id').join(',');
      final postsResponse = await _supabase
          .from('posts')
          .select('''
            id,
            user_id,
            content,
            media_url,
            type,
            thumbnail_url,
            hashtags,
            likes_count,
            comments_count,
            shares_count,
            created_at,
            users!posts_user_id_fkey(
              id,
              username,
              display_name,
              avatar_url
            )
          ''')
          .or(orFilter);

      final posts = List<Map<String, dynamic>>.from(postsResponse);
      debugPrint(('[ContentService.getLikedPosts] posts fetched: ${posts.length}').toString());
      final byId = <String, Map<String, dynamic>>{};
      for (final p in posts) {
        final id = p['id']?.toString();
        if (id != null) {
          byId[id] = p;
        }
      }
      // Step 3: preserve likes ordering and filter out any non-visible posts (RLS)
      final ordered = <Map<String, dynamic>>[];
      final missing = <dynamic>[];
      for (final like in likes) {
        final pid = like['post_id']?.toString();
        final post = pid != null ? byId[pid] : null;
        if (post != null) {
          ordered.add(post);
        } else {
          missing.add(pid);
        }
      }
      if (missing.isNotEmpty) {
        debugPrint(('[ContentService.getLikedPosts] Missing posts due to RLS or deletion: $missing').toString());
      }

      return ordered;
    } catch (e) {
      debugPrint(('Error getting liked posts: $e').toString());
      return [];
    }
  }

  // Content moderation
  Future<bool> reportPost(String postId, String reason, {String? description}) async {
    try {
      final currentUser = _supabase.auth.currentUser;
      if (currentUser == null) throw Exception('User not authenticated');

      await _supabase.from('reports').insert({
        'reporter_id': currentUser.id,
        'content_id': postId,
        'content_type': 'post',
        'reason': reason,
        'description': description,
        'status': 'pending',
        'created_at': DateTime.now().toIso8601String(),
      });

      return true;
    } catch (e) {
      debugPrint(('Error reporting post: $e').toString());
      return false;
    }
  }

  // Analytics
  Future<Map<String, dynamic>> getPostAnalytics(String postId) async {
    try {
      final currentUser = _supabase.auth.currentUser;
      if (currentUser == null) throw Exception('User not authenticated');

      // Get basic post stats
      final post = await _supabase
          .from('posts')
          .select('likes_count, comments_count, shares_count, views_count, created_at')
          .eq('id', postId)
          .eq('user_id', currentUser.id)
          .single();

      // Get engagement over time (simplified)
      final likesOverTime = await _supabase
          .from('likes')
          .select('created_at')
          .eq('post_id', postId)
          .order('created_at', ascending: true);

      final commentsOverTime = await _supabase
          .from('comments')
          .select('created_at')
          .eq('post_id', postId)
          .order('created_at', ascending: true);

      return {
        'post': post,
        'likes_over_time': likesOverTime,
        'comments_over_time': commentsOverTime,
        'total_engagement': post['likes_count'] + post['comments_count'] + post['shares_count'],
      };
    } catch (e) {
      debugPrint(('Error getting post analytics: $e').toString());
      return {};
    }
  }

  Future<Map<String, dynamic>> getUserAnalytics() async {
    try {
      final currentUser = _supabase.auth.currentUser;
      if (currentUser == null) throw Exception('User not authenticated');

      // Get user's total stats
      final posts = await _supabase
          .from('posts')
          .select('likes_count, comments_count, shares_count, views_count')
          .eq('user_id', currentUser.id);

      int totalLikes = 0;
      int totalComments = 0;
      int totalShares = 0;
      int totalPosts = posts.length;

      for (final post in posts) {
        totalLikes += (post['likes_count'] as int? ?? 0);
        totalComments += (post['comments_count'] as int? ?? 0);
        totalShares += (post['shares_count'] as int? ?? 0);
      }

      // Get follower count
      final profile = await _supabase
          .from('users')
          .select('followers_count, following_count')
          .eq('id', currentUser.id)
          .single();

      return {
        'total_posts': totalPosts,
        'total_likes': totalLikes,
        'total_comments': totalComments,
        'total_shares': totalShares,
        'total_engagement': totalLikes + totalComments + totalShares,
        'followers_count': profile['followers_count'] ?? 0,
        'following_count': profile['following_count'] ?? 0,
        'average_engagement_per_post': totalPosts > 0 ? (totalLikes + totalComments + totalShares) / totalPosts : 0,
      };
    } catch (e) {
      debugPrint('Error getting user analytics: $e');
      return {};
    }
  }

  // Hashtag functionality
  Future<List<String>> extractHashtags(String content) async {
    final hashtagRegex = RegExp(r'#\w+');
    final matches = hashtagRegex.allMatches(content);
    return matches.map((match) => match.group(0)?.toLowerCase() ?? '').toList();
  }

  Future<List<Map<String, dynamic>>> getPostsByHashtag(String hashtag, {
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final response = await _supabase
          .from('posts')
          .select('''
            id,
            content,
            media_url,
            type,
            thumbnail_url,
            hashtags,
            likes_count,
            comments_count,
            shares_count,
            created_at,
            users!posts_user_id_fkey(
              id,
              username,
              display_name,
              avatar_url
            )
          ''')
          .contains('hashtags', [hashtag.toLowerCase()])
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint(('Error getting posts by hashtag: $e').toString());
      return [];
    }
  }

  Future<List<String>> getTrendingHashtags({int limit = 10}) async {
    try {
      // Get posts with hashtags from the last 7 days
      final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7)).toIso8601String();
      
      final response = await _supabase
          .from('posts')
          .select('content')
          .gte('created_at', sevenDaysAgo)
          .not('content', 'is', null)
          .limit(500); // Get recent posts to analyze hashtags

      // Extract and count hashtags
      final hashtagCounts = <String, int>{};
      final posts = List<Map<String, dynamic>>.from(response);
      
      for (final post in posts) {
        final content = post['content'] as String? ?? '';
        final hashtags = RegExp(r'#\w+').allMatches(content);
        
        for (final match in hashtags) {
          final hashtag = match.group(0)?.toLowerCase() ?? '';
          hashtagCounts[hashtag] = (hashtagCounts[hashtag] ?? 0) + 1;
        }
      }

      // Sort by count and return top hashtags
      final sortedHashtags = hashtagCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      
      final trendingHashtags = sortedHashtags
          .take(limit)
          .map((entry) => entry.key)
          .toList();
      
      // If no hashtags found, return some default ones
      if (trendingHashtags.isEmpty) {
        return [
          '#equal',
          '#creative',
          '#art',
          '#music',
          '#dance',
        ].take(limit).toList();
      }
      
      return trendingHashtags;
    } catch (e) {
      debugPrint(('Error getting trending hashtags: $e').toString());
      // Return fallback hashtags on error
      return [
        '#equal',
        '#creative',
        '#art',
        '#music',
        '#dance',
      ].take(limit).toList();
    }
  }

  // Save/Bookmark functionality
  Future<bool> savePost(String postId) async {
    try {
      final currentUser = _supabase.auth.currentUser;
      if (currentUser == null) throw Exception('User not authenticated');

      await _supabase.from('saved_posts').insert({
        'user_id': currentUser.id,
        'post_id': postId,
        'created_at': DateTime.now().toIso8601String(),
      });

      return true;
    } catch (e) {
      debugPrint(('Error saving post: $e').toString());
      return false;
    }
  }

  Future<bool> unsavePost(String postId) async {
    try {
      final currentUser = _supabase.auth.currentUser;
      if (currentUser == null) throw Exception('User not authenticated');

      await _supabase
          .from('saved_posts')
          .delete()
          .eq('user_id', currentUser.id)
          .eq('post_id', postId);

      return true;
    } catch (e) {
      debugPrint(('Error unsaving post: $e').toString());
      return false;
    }
  }

  Future<bool> isPostSaved(String postId) async {
    try {
      final currentUser = _supabase.auth.currentUser;
      if (currentUser == null) return false;

      final response = await _supabase
          .from('saved_posts')
          .select('id')
          .eq('user_id', currentUser.id)
          .eq('post_id', postId)
          .maybeSingle();

      return response != null;
    } catch (e) {
      debugPrint(('Error checking if post is saved: $e').toString());
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getSavedPosts({
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final currentUser = _supabase.auth.currentUser;
      if (currentUser == null) throw Exception('User not authenticated');

      final response = await _supabase
          .from('saved_posts')
          .select('''
            created_at,
            posts!saved_posts_post_id_fkey(
              id,
              content,
              media_url,
              type,
              thumbnail_url,
              hashtags,
              likes_count,
              comments_count,
              shares_count,
              created_at,
              users!posts_user_id_fkey(
                id,
                username,
                display_name,
                avatar_url
              )
            )
          ''')
          .eq('user_id', currentUser.id)
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      return List<Map<String, dynamic>>.from(response)
          .map((item) => item['posts'])
          .where((post) => post != null)
          .cast<Map<String, dynamic>>()
          .toList();
    } catch (e) {
      debugPrint(('Error getting saved posts: $e').toString());
      return [];
    }
  }
}
