import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import '../config/supabase_config.dart';
import '../models/post_model.dart';
import 'auth_service.dart';
import 'monetization_service.dart';
import 'enhanced_notification_service.dart';
import 'analytics_service.dart';
import 'package:http/http.dart' as http;
import 'musicbrainz_service.dart';
import 'audio_fingerprinting_service.dart';
import 'video_audio_extractor.dart';

class PostsService {
  static final PostsService _instance = PostsService._internal();
  factory PostsService() => _instance;
  PostsService._internal();

  final SupabaseClient _client = SupabaseConfig.client;
  final AuthService _authService = AuthService();
  final MonetizationService _monetizationService = MonetizationService();
  final AnalyticsService _analyticsService = AnalyticsService();
  static const Duration _networkTimeout = Duration(seconds: 10);

  // Stream controllers for real-time updates
  final _postsController = StreamController<List<PostModel>>.broadcast();
  final _likesController = StreamController<Map<String, dynamic>>.broadcast();

  // Getters for streams
  Stream<List<PostModel>> get postsStream => _postsController.stream;
  Stream<Map<String, dynamic>> get likesStream => _likesController.stream;

  // Real-time subscriptions
  RealtimeChannel? _postsSubscription;
  RealtimeChannel? _likesSubscription;

  // Initialize real-time subscriptions
  Future<void> initializeRealtime() async {
    await _subscribeToPostsUpdates();
    await _subscribeToLikesUpdates();
  }

  // Clean up subscriptions
  Future<void> dispose() async {
    await _postsSubscription?.unsubscribe();
    await _likesSubscription?.unsubscribe();

    _postsController.close();
    _likesController.close();
  }

  // Get posts (alias for getFeedPosts for backward compatibility)
  Future<List<PostModel>> getPosts({
    int limit = 20,
    int offset = 0,
    String? userId,
  }) async {
    return getFeedPosts(limit: limit, offset: offset, userId: userId);
  }

  // Get personalized For You posts with 70% global, 20% local, 5% niche, 5% following
  Future<List<PostModel>> getPersonalizedForYouPosts({
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final currentUserId = _authService.currentUser?.id;

      // Targets per category based on requested limit
      int globalTarget = ((limit * 70) / 100).ceil();
      int localTarget = ((limit * 20) / 100).ceil();
      int nicheTarget = ((limit * 5) / 100).ceil();
      int followTarget = ((limit * 5) / 100).ceil();

      // Small buffers to help avoid duplicates and ensure enough items
      int bufferMultiplier = 2;

      // 1) Global (public) posts
      final globalQuery = _client
          .from(SupabaseConfig.postsTable)
          .select('''
            *,
            user:users!posts_user_id_fkey(
              id, username, display_name, avatar_url, is_verified
            ),
            comments_count,
            likes_count,
            shares_count,
            views_count,
            comments(count)
          ''')
          .eq('is_public', true)
          .order('created_at', ascending: false)
          .range(offset, offset + (globalTarget * bufferMultiplier) - 1);
      final globalResponse = await globalQuery;
      final globalPostsRaw = (globalResponse is List)
          ? globalResponse
          : <dynamic>[];
      final globalPosts = globalPostsRaw
          .map((json) => PostModel.fromJson(json as Map<String, dynamic>))
          .toList();

      // Track IDs to avoid duplicates across categories
      final takenIds = <String>{...globalPosts.map((p) => p.id)};

      // 2) Local posts by user country (if available) — try RPC first
      String? userCountry;
      if (currentUserId != null) {
        try {
          final userRow = await _client
              .from('users')
              .select('country')
              .eq('id', currentUserId)
              .maybeSingle();
          if (userRow != null) {
            final dyn = userRow['country'];
            if (dyn is String && dyn.trim().isNotEmpty) {
              userCountry = dyn.trim();
            }
          }
        } catch (_) {}
      }

      List<PostModel> localPosts = [];
      if (userCountry != null && userCountry!.isNotEmpty) {
        try {
          final rpcResp = await _client.rpc(
            'get_local_posts',
            params: {
              'country': userCountry,
              'limit_count': localTarget * bufferMultiplier,
              'offset_count': 0,
            },
          );
          final localRaw = (rpcResp is List) ? rpcResp : <dynamic>[];
          localPosts = localRaw
              .map((json) => PostModel.fromJson(json as Map<String, dynamic>))
              .toList();
        } catch (_) {
          var localQuery = _client
              .from(SupabaseConfig.postsTable)
              .select('''
                *,
                user:users!posts_user_id_fkey(
                  id, username, display_name, avatar_url, is_verified
                ),
                comments_count,
                likes_count,
                shares_count,
                views_count,
                comments(count)
              ''')
              .eq('is_public', true)
              .ilike('location', '%$userCountry%');
          if (takenIds.isNotEmpty) {
            final idsClause = '(${takenIds.join(',')})';
            localQuery = localQuery.not('id', 'in', idsClause);
          }
          final localResponse = await localQuery
              .order('created_at', ascending: false)
              .range(0, (localTarget * bufferMultiplier) - 1);
          final localRaw = (localResponse is List)
              ? localResponse
              : <dynamic>[];
          localPosts = localRaw
              .map((json) => PostModel.fromJson(json as Map<String, dynamic>))
              .toList();
        }
        takenIds.addAll(localPosts.map((p) => p.id));
      }

      // 3) Niche posts based on user favorite hashtags from liked posts
      List<String> favoriteTags = [];
      if (currentUserId != null) {
        try {
          final likesResp = await _client
              .from(SupabaseConfig.likesTable)
              .select('post_id, created_at')
              .eq('user_id', currentUserId)
              .order('created_at', ascending: false)
              .limit(200);
          final likedIds = (likesResp is List)
              ? likesResp
                    .map(
                      (e) => (e as Map<String, dynamic>)['post_id'] as String,
                    )
                    .toList()
              : <String>[];
          if (likedIds.isNotEmpty) {
            final postsResp = await _client
                .from(SupabaseConfig.postsTable)
                .select('id, hashtags')
                .inFilter('id', likedIds);
            final tagFreq = <String, int>{};
            for (final row in (postsResp as List? ?? const [])) {
              final map = row as Map<String, dynamic>;
              final tags = map['hashtags'];
              if (tags is List) {
                for (final t in tags) {
                  if (t is String && t.isNotEmpty) {
                    tagFreq[t] = (tagFreq[t] ?? 0) + 1;
                  }
                }
              }
            }
            final sorted = tagFreq.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value));
            favoriteTags = sorted.take(10).map((e) => e.key).toList();
          }
        } catch (_) {}
      }

      List<PostModel> nichePosts = [];
      if (favoriteTags.isNotEmpty) {
        try {
          final rpcResp = await _client.rpc(
            'get_niche_posts_by_tags',
            params: {
              'tags': favoriteTags,
              'limit_count': nicheTarget * bufferMultiplier,
              'offset_count': 0,
            },
          );
          final nicheRaw = (rpcResp is List) ? rpcResp : <dynamic>[];
          nichePosts = nicheRaw
              .map((json) => PostModel.fromJson(json as Map<String, dynamic>))
              .toList();
        } catch (_) {
          // Fallback: caption-based OR clause
          final orParts = favoriteTags
              .map((t) => 'caption.ilike.%#${t.replaceAll(',', '')}%')
              .toList();
          var nicheQuery = _client
              .from(SupabaseConfig.postsTable)
              .select('''
                *,
                user:users!posts_user_id_fkey(
                  id, username, display_name, avatar_url, is_verified
                ),
                comments_count,
                likes_count,
                shares_count,
                views_count,
                comments(count)
              ''')
              .eq('is_public', true)
              .or(orParts.join(','));
          if (takenIds.isNotEmpty) {
            final idsClause = '(${takenIds.join(',')})';
            nicheQuery = nicheQuery.not('id', 'in', idsClause);
          }
          final nicheResp = await nicheQuery
              .order('created_at', ascending: false)
              .range(0, (nicheTarget * bufferMultiplier) - 1);
          final nicheRaw = (nicheResp is List) ? nicheResp : <dynamic>[];
          nichePosts = nicheRaw
              .map((json) => PostModel.fromJson(json as Map<String, dynamic>))
              .toList();
        }
        takenIds.addAll(nichePosts.map((p) => p.id));
      }

      // 4) Following (tracked users + own posts)
      List<PostModel> followingPosts = [];
      if (currentUserId != null) {
        final trackingIds = await _getFollowingIds(currentUserId);
        final userIds = [currentUserId, ...trackingIds];
        if (userIds.isNotEmpty) {
          var followQuery = _client
              .from(SupabaseConfig.postsTable)
              .select('''
                *,
                user:users!posts_user_id_fkey(
                  id, username, display_name, avatar_url, is_verified
                ),
                comments_count,
                likes_count,
                shares_count,
                views_count,
                comments(count)
              ''')
              .inFilter('user_id', userIds);
          if (takenIds.isNotEmpty) {
            final idsClause = '(${takenIds.join(',')})';
            followQuery = followQuery.not('id', 'in', idsClause);
          }
          final followResp = await followQuery
              .order('created_at', ascending: false)
              .range(0, (followTarget * bufferMultiplier) - 1);
          final followRaw = (followResp is List) ? followResp : <dynamic>[];
          followingPosts = followRaw
              .map((json) => PostModel.fromJson(json as Map<String, dynamic>))
              .toList();
          takenIds.addAll(followingPosts.map((p) => p.id));
        }
      }

      // Interleave according to targets; fill shortfalls with global as fallback
      List<PostModel> pickFrom(List<PostModel> list, int count) {
        return list.take(count).toList();
      }

      final pool = {
        'global': globalPosts,
        'local': localPosts,
        'niche': nichePosts,
        'follow': followingPosts,
      };
      final targets = {
        'global': globalTarget,
        'local': localTarget,
        'niche': nicheTarget,
        'follow': followTarget,
      };

      // Build schedule list based on ratios for the requested limit
      List<String> schedule = [];
      schedule.addAll(List.filled(globalTarget, 'global'));
      schedule.addAll(List.filled(localTarget, 'local'));
      schedule.addAll(List.filled(nicheTarget, 'niche'));
      schedule.addAll(List.filled(followTarget, 'follow'));
      // If rounding misses total, pad with global
      while (schedule.length < limit) {
        schedule.add('global');
      }
      if (schedule.length > limit) {
        schedule = schedule.sublist(0, limit);
      }

      // Index trackers per pool
      final idx = {'global': 0, 'local': 0, 'niche': 0, 'follow': 0};

      List<PostModel> result = [];
      for (final cat in schedule) {
        final list = pool[cat]!;
        final i = idx[cat]!;
        if (i < list.length) {
          result.add(list[i]);
          idx[cat] = i + 1;
        } else {
          // Fallback to first available category with remaining items
          bool placed = false;
          for (final fallbackCat in ['global', 'local', 'niche', 'follow']) {
            final flist = pool[fallbackCat]!;
            final fi = idx[fallbackCat]!;
            if (fi < flist.length) {
              result.add(flist[fi]);
              idx[fallbackCat] = fi + 1;
              placed = true;
              break;
            }
          }
          if (!placed) break; // No more items from any pool
        }
      }

      // Check liked status flag for current user
      if (currentUserId != null) {
        for (final post in result) {
          try {
            final likeCheck = await _client
                .from(SupabaseConfig.likesTable)
                .select('id')
                .eq('user_id', currentUserId)
                .eq('post_id', post.id)
                .maybeSingle();
            post.isLiked = likeCheck != null;
          } catch (_) {
            post.isLiked = false;
          }
        }
      } else {
        for (final post in result) {
          post.isLiked = false;
        }
      }

      // Special account pinning logic reused: keep at top for configured hours
      if (SupabaseConfig.specialAccountIds.isNotEmpty) {
        final pinnedDuration = Duration(
          hours: SupabaseConfig.specialPinnedHours,
        );
        final now = DateTime.now();
        result.sort((a, b) {
          bool aPinned =
              SupabaseConfig.specialAccountIds.contains(a.userId) &&
              now.difference(a.timestamp) <= pinnedDuration;
          bool bPinned =
              SupabaseConfig.specialAccountIds.contains(b.userId) &&
              now.difference(b.timestamp) <= pinnedDuration;
          if (aPinned && !bPinned) return -1;
          if (!aPinned && bPinned) return 1;
          return b.timestamp.compareTo(a.timestamp);
        });
      }

      return result;
    } catch (e) {
      debugPrint('Error in personalized feed: $e');
      // Fallback to existing feed
      return getFeedPosts(limit: limit, offset: offset);
    }
  }

  // Get a single post by ID
  Future<PostModel?> getPostById(String postId) async {
    try {
      final currentUserId = _authService.currentUser?.id;

      final response = await _client
          .from(SupabaseConfig.postsTable)
          .select('''
            *,
            user:users!posts_user_id_fkey(
              id, username, display_name, avatar_url, is_verified
            ),
            comments_count,
            likes_count,
            shares_count,
            views_count,
            comments(count)
          ''')
          .eq('id', postId)
          .maybeSingle()
          .timeout(_networkTimeout);

      if (response == null) return null;

      final postData = response;
      // Authorization for private posts
      final isPublic = postData['is_public'] == true;
      if (!isPublic) {
        final ownerId = postData['user_id'] as String?;
        if (currentUserId == null || ownerId == null) {
          return null;
        }
        bool canView = currentUserId == ownerId;
        if (!canView) {
          final followingIds = await _getFollowingIds(currentUserId);
          canView = followingIds.contains(ownerId);
        }
        if (!canView) {
          return null;
        }
      }

      // Check if current user liked this post
      if (currentUserId != null) {
        final likeCheck = await _client
            .from(SupabaseConfig.likesTable)
            .select('id')
            .eq('user_id', currentUserId)
            .eq('post_id', postData['id'])
            .maybeSingle();

        postData['is_liked'] = likeCheck != null;
      } else {
        postData['is_liked'] = false;
      }

      return PostModel.fromJson(postData);
    } catch (e) {
      debugPrint('Error fetching post by ID: $e');
      return null;
    }
  }

  // Get feed posts with user data
  Future<List<PostModel>> getFeedPosts({
    int limit = 20,
    int offset = 0,
    String? userId,
  }) async {
    try {
      final currentUserId = _authService.currentUser?.id;

      var queryBuilder = _client.from(SupabaseConfig.postsTable).select('''
            *,
            user:users!posts_user_id_fkey(
              id, username, display_name, avatar_url, is_verified
            ),
            comments_count,
            likes_count,
            shares_count,
            views_count,
            comments(count)
          ''');

      // If viewing a specific user's posts through this API
      if (userId != null) {
        // Determine if viewer can see private posts
        bool canSeePrivate = false;
        if (currentUserId != null) {
          if (currentUserId == userId) {
            canSeePrivate = true;
          } else {
            final followingIds = await _getFollowingIds(currentUserId);
            canSeePrivate = followingIds.contains(userId);
          }
        }

        queryBuilder = queryBuilder.eq('user_id', userId);
        if (!canSeePrivate) {
          queryBuilder = queryBuilder.eq('is_public', true);
        }
      } else {
        // Main feed: show public posts OR private posts from users you follow (including yourself)
        if (currentUserId != null) {
          final trackingIds = await _getFollowingIds(currentUserId);
          final userIds = [currentUserId, ...trackingIds];
          final idsList = userIds.map((id) => id.replaceAll(',', '')).toList();
          final idsOrClause = idsList.isEmpty
              ? 'is_public.eq.true'
              : 'is_public.eq.true,user_id.in.(${idsList.join(',')})';
          queryBuilder = queryBuilder.or(idsOrClause);
        } else {
          queryBuilder = queryBuilder.eq('is_public', true);
        }
      }

      List<dynamic> response;
      try {
        response =
            await queryBuilder
                    .order('created_at', ascending: false)
                    .range(offset, offset + limit - 1)
                as List<dynamic>;
      } catch (e) {
        // Fallback: unknown relationship for users join, retry without join and enrich profiles
        final msg = e.toString();
        final looksLikeRelError =
            msg.contains('relationship') ||
            msg.contains('users!') ||
            msg.contains('foreign key');
        if (!looksLikeRelError) {
          rethrow;
        }
        if (kDebugMode) {
          debugPrint(
            '[PostsService] users join failed; retrying select without join and enriching profiles',
          );
        }
        var fallback = _client.from(SupabaseConfig.postsTable).select('''
              *,
              comments_count,
              likes_count,
              shares_count,
              views_count,
              comments(count)
            ''');
        if (userId != null) {
          fallback = fallback.eq('user_id', userId);
        }
        if (currentUserId == null) {
          fallback = fallback.eq('is_public', true);
        } else if (userId == null) {
          final trackingIds = await _getFollowingIds(currentUserId);
          final userIds = [currentUserId, ...trackingIds];
          final idsList = userIds.map((id) => id.replaceAll(',', '')).toList();
          final idsOrClause = idsList.isEmpty
              ? 'is_public.eq.true'
              : 'is_public.eq.true,user_id.in.(${idsList.join(',')})';
          fallback = fallback.or(idsOrClause);
        } else {
          // userId != null case handled above; default to public-only if cannot determine
          final followingIds = await _getFollowingIds(currentUserId);
          final canSeePrivate =
              currentUserId == userId || followingIds.contains(userId);
          if (!canSeePrivate) {
            fallback = fallback.eq('is_public', true);
          }
        }
        response =
            await fallback
                    .order('created_at', ascending: false)
                    .range(offset, offset + limit - 1)
                as List<dynamic>;
      }

      final posts = <PostModel>[];
      for (final json in response) {
        final postData = json as Map<String, dynamic>;
        if (currentUserId != null) {
          final likeCheck = await _client
              .from(SupabaseConfig.likesTable)
              .select('id')
              .eq('user_id', currentUserId)
              .eq('post_id', postData['id'])
              .maybeSingle();
          postData['is_liked'] = likeCheck != null;
        } else {
          postData['is_liked'] = false;
        }
        posts.add(PostModel.fromJson(postData));
      }

      // Prioritize special account posts: keep at top for configured hours
      if (SupabaseConfig.specialAccountIds.isNotEmpty) {
        final pinnedDuration = Duration(
          hours: SupabaseConfig.specialPinnedHours,
        );
        final now = DateTime.now();
        posts.sort((a, b) {
          bool aPinned =
              SupabaseConfig.specialAccountIds.contains(a.userId) &&
              now.difference(a.timestamp) <= pinnedDuration;
          bool bPinned =
              SupabaseConfig.specialAccountIds.contains(b.userId) &&
              now.difference(b.timestamp) <= pinnedDuration;
          if (aPinned && !bPinned) return -1;
          if (!aPinned && bPinned) return 1;
          // Fallback to original order (by timestamp desc)
          return b.timestamp.compareTo(a.timestamp);
        });
      }

      return posts;
    } catch (e) {
      debugPrint('Error fetching feed posts: $e');
      return [];
    }
  }

  // Get posts by specific user
  Future<List<PostModel>> getUserPosts({
    required String userId,
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final currentUserId = _authService.currentUser?.id;

      // Determine if viewer can see private posts
      bool canSeePrivate = false;
      if (currentUserId != null) {
        if (currentUserId == userId) {
          canSeePrivate = true;
        } else {
          final followingIds = await _getFollowingIds(currentUserId);
          canSeePrivate = followingIds.contains(userId);
        }
      }

      var query = _client
          .from(SupabaseConfig.postsTable)
          .select('''
            *,
            user:users!posts_user_id_fkey(
              id, username, display_name, avatar_url, is_verified
            ),
            comments_count,
            likes_count,
            shares_count,
            views_count,
            comments(count)
          ''')
          .eq('user_id', userId);

      if (!canSeePrivate) {
        query = query.eq('is_public', true);
      }

      // order applied when executing the query below

      List<dynamic> response;
      try {
        response =
            await query
                    .order('created_at', ascending: false)
                    .range(offset, offset + limit - 1)
                as List<dynamic>;
      } catch (e) {
        final msg = e.toString();
        final looksLikeRelError =
            msg.contains('relationship') ||
            msg.contains('users!') ||
            msg.contains('foreign key');
        if (!looksLikeRelError) {
          rethrow;
        }
        if (kDebugMode) {
          debugPrint(
            '[PostsService] users join failed in getUserPosts; retrying without join and enriching profiles',
          );
        }
        var fallback = _client
            .from(SupabaseConfig.postsTable)
            .select('''
              *,
              comments_count,
              likes_count,
              shares_count,
              views_count,
              comments(count)
            ''')
            .eq('user_id', userId);
        if (!canSeePrivate) {
          fallback = fallback.eq('is_public', true);
        }
        response =
            await fallback
                    .order('created_at', ascending: false)
                    .range(offset, offset + limit - 1)
                as List<dynamic>;
      }

      final posts = <PostModel>[];
      for (final json in response) {
        final postData = json as Map<String, dynamic>;
        if (currentUserId != null) {
          final likeCheck = await _client
              .from(SupabaseConfig.likesTable)
              .select('id')
              .eq('user_id', currentUserId)
              .eq('post_id', postData['id'])
              .maybeSingle();
          postData['is_liked'] = likeCheck != null;
        } else {
          postData['is_liked'] = false;
        }
        posts.add(PostModel.fromJson(postData));
      }
      return posts;
    } catch (e) {
      debugPrint('Error fetching user posts: $e');
      return [];
    }
  }

  // Get fair viral posts - gives equal opportunities to all users
  Future<List<PostModel>> getViralPosts({
    int limit = 20,
    int offset = 0,
  }) async {
    // Fetch viral candidates using existing monetization logic
    final posts = await _monetizationService.getViralCandidates(
      limit: limit,
      offset: offset,
    );

    // Pin special account posts near the top within configured window, preserving order
    if (SupabaseConfig.specialAccountIds.isNotEmpty && posts.isNotEmpty) {
      final pinnedDuration = Duration(hours: SupabaseConfig.specialPinnedHours);
      final now = DateTime.now();
      final pinned = <PostModel>[];
      final regular = <PostModel>[];
      for (final p in posts) {
        final isPinned =
            SupabaseConfig.specialAccountIds.contains(p.userId) &&
            now.difference(p.timestamp) <= pinnedDuration;
        (isPinned ? pinned : regular).add(p);
      }
      return [...pinned, ...regular];
    }

    return posts;
  }

  // Get trending posts with advanced algorithm
  Future<List<PostModel>> getTrendingPosts({
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final currentUserId = _authService.currentUser?.id;

      // Get posts from the last 7 days for trending calculation
      // final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7)).toIso8601String(); // unused
      // User preference: use 3-day window for trending calculations
      final threeDaysAgo = DateTime.now()
          .subtract(const Duration(days: 3))
          .toIso8601String();

      var query = _client.from(SupabaseConfig.postsTable).select('''
            *,
            user:users!posts_user_id_fkey(
              id, username, display_name, avatar_url, is_verified
            ),
            comments_count,
            likes_count,
            shares_count,
            comments(count)
          ''');
      // Preference: only public posts
      query = query.eq('is_public', true);

      // Attempt query; fallback without users join on relationship errors
      List<dynamic> response;
      try {
        response =
            await query
                    .gte('created_at', threeDaysAgo)
                    .order('created_at', ascending: false)
                    .limit(500)
                as List<dynamic>;
      } catch (e) {
        final msg = e.toString();
        final looksLikeRelError =
            msg.contains('relationship') ||
            msg.contains('users!') ||
            msg.contains('foreign key');
        if (!looksLikeRelError) {
          rethrow;
        }
        if (kDebugMode) {
          debugPrint(
            '[PostsService] trending users join failed; retrying select without join and enriching profiles',
          );
        }
        var fallback = _client.from(SupabaseConfig.postsTable).select('''
              *,
              comments_count,
              likes_count,
              shares_count,
              views_count,
              comments(count)
            ''');
        // Preference: only public posts
        fallback = fallback.eq('is_public', true);
        response =
            await fallback
                    .gte('created_at', threeDaysAgo)
                    .order('created_at', ascending: false)
                    .limit(500)
                as List<dynamic>;
      }

      // Calculate trending scores for each post
      final postsWithScores = <Map<String, dynamic>>[];

      for (final json in response) {
        final postData = json as Map<String, dynamic>;
        final trendingScore = _calculateTrendingScore(postData);

        // Do not hard-filter by score; always include and annotate.
        // This prevents empty Trending feeds when engagement is low.
        postData['trending_score'] = trendingScore;
        postsWithScores.add(postData);
      }

      // Minimum-blend strategy: ensure at least N posts by mixing in recent public/followed
      const int minTrendingThreshold = 10;
      if (postsWithScores.length < minTrendingThreshold) {
        final existingIds = postsWithScores
            .map((m) => m['id']?.toString())
            .whereType<String>()
            .toSet();

        var blendQuery = _client.from(SupabaseConfig.postsTable).select('''
               *,
               user:users!posts_user_id_fkey(
                 id, username, display_name, avatar_url, is_verified
               ),
               comments_count,
               likes_count,
               shares_count,
               views_count,
               comments(count)
             ''');
        // User preference: only public posts within the last 3 days
        blendQuery = blendQuery
            .eq('is_public', true)
            .gte('created_at', threeDaysAgo);
        final blendResp =
            await blendQuery.order('created_at', ascending: false).limit(50)
                as List<dynamic>;
        for (final json in blendResp) {
          final postData = json as Map<String, dynamic>;
          final idStr = postData['id']?.toString();
          if (idStr == null || existingIds.contains(idStr)) continue;
          postData['trending_score'] = _calculateTrendingScore(postData);
          postsWithScores.add(postData);
          existingIds.add(idStr);
          if (postsWithScores.length >= minTrendingThreshold) break;
        }
      }

      // Fallback: if no posts matched the 7-day window, broaden to recent posts
      if (postsWithScores.isEmpty) {
        if (kDebugMode) {
          debugPrint(
            '[PostsService] No trending posts in last 7 days; applying fallback to recent public/followed posts',
          );
        }
        var broadened = _client.from(SupabaseConfig.postsTable).select('''
               *,
               user:users!posts_user_id_fkey(
                 id, username, display_name, avatar_url, is_verified
               ),
               comments_count,
               likes_count,
               shares_count,
               views_count,
               comments(count)
             ''');
        // User preference: fallback also uses only public posts within last 3 days
        broadened = broadened
            .eq('is_public', true)
            .gte('created_at', threeDaysAgo);
        final fallbackResp =
            await broadened.order('created_at', ascending: false).limit(100)
                as List<dynamic>;
        for (final json in fallbackResp) {
          final postData = json as Map<String, dynamic>;
          final trendingScore = _calculateTrendingScore(postData);
          postData['trending_score'] = trendingScore;
          postsWithScores.add(postData);
        }
      }

      // Sort by trending score (highest first), then by recency
      postsWithScores.sort((a, b) {
        final int scoreCompare = (b['trending_score'] as double).compareTo(
          a['trending_score'] as double,
        );
        if (scoreCompare != 0) return scoreCompare;
        final DateTime bCreated = DateTime.parse(b['created_at'] as String);
        final DateTime aCreated = DateTime.parse(a['created_at'] as String);
        return bCreated.compareTo(aCreated);
      });

      // Pin special account posts to the top within the configured window, preserving trending order
      List<Map<String, dynamic>> arrangedPosts = postsWithScores;
      if (SupabaseConfig.specialAccountIds.isNotEmpty) {
        final pinnedDuration = Duration(
          hours: SupabaseConfig.specialPinnedHours,
        );
        final now = DateTime.now();
        final pinned = <Map<String, dynamic>>[];
        final regular = <Map<String, dynamic>>[];
        for (final m in postsWithScores) {
          final uid =
              (m['user_id'] ?? (m['user'] != null ? (m['user']['id']) : null))
                  ?.toString();
          final createdAtStr = m['created_at']?.toString();
          final createdAt = createdAtStr != null
              ? DateTime.tryParse(createdAtStr)
              : null;
          final isPinned =
              uid != null &&
              createdAt != null &&
              SupabaseConfig.specialAccountIds.contains(uid) &&
              now.difference(createdAt) <= pinnedDuration;
          (isPinned ? pinned : regular).add(m);
        }
        arrangedPosts = [...pinned, ...regular];
      }

      // Apply pagination
      final paginatedPosts = arrangedPosts.skip(offset).take(limit).toList();

      // Process posts and check likes for current user
      final posts = <PostModel>[];
      for (final postData in paginatedPosts) {
        // Check if current user liked this post
        if (currentUserId != null) {
          final likeCheck = await _client
              .from(SupabaseConfig.likesTable)
              .select('id')
              .eq('user_id', currentUserId)
              .eq('post_id', postData['id'])
              .maybeSingle();

          postData['is_liked'] = likeCheck != null;
        } else {
          postData['is_liked'] = false;
        }

        posts.add(PostModel.fromJson(postData));
      }

      return posts;
    } catch (e) {
      debugPrint('Error fetching trending posts: $e');
      return [];
    }
  }

  // Calculate trending score using advanced algorithm
  double _calculateTrendingScore(Map<String, dynamic> postData) {
    try {
      // Extract engagement metrics
      final likesCount = (postData['likes_count'] ?? 0) as int;
      final commentsCount = (postData['comments_count'] ?? 0) as int;
      final sharesCount = (postData['shares_count'] ?? 0) as int;

      // Parse creation time
      final createdAt = DateTime.parse(postData['created_at'] as String);
      final now = DateTime.now();
      final ageInHours = now.difference(createdAt).inHours.toDouble();

      // Prevent division by zero
      if (ageInHours <= 0) return 0.0;

      // Engagement weights (comments and shares are more valuable than likes)
      const double likeWeight = 1.0;
      const double commentWeight = 3.0;
      const double shareWeight = 5.0;

      // Calculate raw engagement score
      final rawEngagement =
          (likesCount * likeWeight) +
          (commentsCount * commentWeight) +
          (sharesCount * shareWeight);

      // Time decay factor (posts lose trending power over time)
      // Uses exponential decay: newer posts get higher scores
      final timeDecay = _calculateTimeDecay(ageInHours);

      // Velocity factor (engagement rate per hour)
      final velocity = rawEngagement / ageInHours;

      // Viral coefficient (bonus for posts with high engagement relative to age)
      final viralCoefficient = _calculateViralCoefficient(
        rawEngagement,
        ageInHours,
      );

      // Final trending score calculation
      final trendingScore = (velocity * timeDecay * viralCoefficient).clamp(
        0.0,
        1000.0,
      );

      return trendingScore;
    } catch (e) {
      debugPrint('Error calculating trending score: $e');
      return 0.0;
    }
  }

  // Calculate time decay factor (exponential decay)
  double _calculateTimeDecay(double ageInHours) {
    // Posts lose 50% of their trending power every 24 hours
    const double halfLife = 24.0;
    return math.pow(0.5, ageInHours / halfLife).toDouble();
  }

  // Calculate viral coefficient for posts with exceptional engagement
  double _calculateViralCoefficient(double rawEngagement, double ageInHours) {
    // Base coefficient
    double coefficient = 1.0;

    // Bonus for high engagement in short time (viral content)
    final engagementRate = rawEngagement / ageInHours;

    if (engagementRate > 50) {
      coefficient *= 2.0; // 100% bonus for very viral content
    } else if (engagementRate > 20) {
      coefficient *= 1.5; // 50% bonus for viral content
    } else if (engagementRate > 10) {
      coefficient *= 1.2; // 20% bonus for popular content
    }

    // Additional bonus for posts with balanced engagement (not just likes)
    final likesCount =
        rawEngagement * 0.4; // Approximate likes from raw engagement
    final otherEngagement = rawEngagement - likesCount;

    if (otherEngagement > likesCount * 0.3) {
      coefficient *=
          1.3; // Bonus for posts with comments/shares, not just likes
    }

    return coefficient;
  }

  // Search posts
  Future<List<PostModel>> searchPosts(String query) async {
    try {
      final currentUserId = _authService.currentUser?.id;

      var queryBuilder = _client
          .from(SupabaseConfig.postsTable)
          .select('''
            *,
            user:users!posts_user_id_fkey(
              id, username, display_name, avatar_url, is_verified
            ),
            comments_count,
            likes_count,
            shares_count,
            views_count,
            comments(count)
          ''')
          .or('caption.ilike.%$query%,user.username.ilike.%$query%');
      if (currentUserId != null) {
        final trackingIds = await _getFollowingIds(currentUserId);
        final userIds = [currentUserId, ...trackingIds];
        final idsList = userIds.map((id) => id.replaceAll(',', '')).toList();
        final idsOrClause = idsList.isEmpty
            ? 'is_public.eq.true'
            : 'is_public.eq.true,user_id.in.(${idsList.join(',')})';
        queryBuilder = queryBuilder.or(idsOrClause);
      } else {
        queryBuilder = queryBuilder.eq('is_public', true);
      }
      final response = await queryBuilder
          .order('created_at', ascending: false)
          .limit(50);

      // Process posts and check likes for current user
      final posts = <PostModel>[];
      for (final json in response as List) {
        final postData = json as Map<String, dynamic>;

        // Check if current user liked this post
        if (currentUserId != null) {
          final likeCheck = await _client
              .from(SupabaseConfig.likesTable)
              .select('id')
              .eq('user_id', currentUserId)
              .eq('post_id', postData['id'])
              .maybeSingle();

          postData['is_liked'] = likeCheck != null;
        } else {
          postData['is_liked'] = false;
        }

        posts.add(PostModel.fromJson(postData));
      }

      return posts;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error searching posts: $e');
      }
      return [];
    }
  }

  // Create a new post
  Future<PostModel?> createPost({
    required String type,
    String? caption,
    String? mediaUrl,
    String? thumbnailUrl,
    int? duration,
    int? width,
    int? height,
    int? fileSize,
    String? mimeType,
    bool? isPublic,
    bool isAiGenerated = false,
    String? aiPrompt,
    String? aiModel,
    Map<String, dynamic>? effects,
    Map<String, dynamic>? aiMetadata,
    String? musicId,
    String? filterId,
    bool allowComments = true,
    bool allowDuets = true,
    String? location,
    List<String>? hashtags,
    String? parentPostId, // For harmony/duet posts
  }) async {
    try {
      final userId = _authService.currentUser?.id;
      if (userId == null) throw Exception('User not authenticated');

      // Determine visibility default from profile privacy when not explicitly provided
      bool effectiveIsPublic = true;
      try {
        final profile = await _authService.getCurrentUserProfile();
        final isPrivate = profile?['is_private'] == true;
        effectiveIsPublic = isPublic ?? !isPrivate;
      } catch (_) {
        // Fallback to provided value or default true
        effectiveIsPublic = isPublic ?? true;
      }

      // Attempt MusicBrainz detection if audio and not already provided
      Map<String, dynamic>? detectedAiMetadata;
      String? detectedMusicId;
      if (type == 'audio' &&
          mediaUrl != null &&
          (aiMetadata == null || musicId == null)) {
        try {
          // Derive hints from caption when possible (e.g., "Artist - Title" or standalone title)
          String? titleHint;
          String? artistHint;
          if ((caption ?? '').trim().isNotEmpty) {
            final name = caption!.trim();
            if (name.contains(' - ')) {
              final parts = name.split(' - ');
              if (parts.length >= 2) {
                artistHint = parts.first.trim();
                titleHint = parts.sublist(1).join(' - ').trim();
              }
            } else {
              titleHint = name;
            }
          }

          final resp = await http
              .get(Uri.parse(mediaUrl))
              .timeout(_networkTimeout);
          if (resp.statusCode == 200) {
            final detection = await MusicBrainzService().detect(
              bytes: resp.bodyBytes,
              fileName: mediaUrl.split('/').last,
              titleHint: titleHint,
              artistHint: artistHint,
            );
            detectedAiMetadata = {'copyright_detection': detection};
            if (musicId == null &&
                detection != null &&
                detection['match'] == true &&
                detection['recordingId'] is String) {
              detectedMusicId = detection['recordingId'] as String;
            }
            // Fingerprinting fallback when MB detection fails or has low confidence
            final mbConfidence =
                detection != null && detection['confidence'] is num
                ? (detection['confidence'] as num).toDouble()
                : 0.0;
            if (detection == null || mbConfidence < 0.4) {
              final fp = await AudioFingerprintService().detectFromBytes(
                resp.bodyBytes,
                fileName: mediaUrl.split('/').last,
              );
              if (fp != null) {
                detectedAiMetadata = {'copyright_detection': fp};
                if (musicId == null && fp['recordingId'] is String) {
                  detectedMusicId = fp['recordingId'] as String;
                }
              }
            }
          }
        } catch (_) {}
      }

      // Fingerprint detection for videos to avoid labeling copyrighted songs as "Original"
      // Applies only when no explicit AI metadata or musicId provided
      if (type == 'video' &&
          mediaUrl != null &&
          (aiMetadata == null || musicId == null)) {
        try {
          final resp = await http
              .get(Uri.parse(mediaUrl))
              .timeout(_networkTimeout);
          if (resp.statusCode == 200) {
            // Extract short WAV PCM snippet from video bytes, then fingerprint
            final wav = await VideoAudioExtractor.extractWavSnippetFromBytes(
              resp.bodyBytes,
              seconds: 20,
              offsetSeconds: 0,
            );
            final fp = await AudioFingerprintService().detectFromBytes(
              wav,
              fileName: 'video_snippet.wav',
            );
            if (fp != null) {
              detectedAiMetadata = {'copyright_detection': fp};
              if (musicId == null && fp['recordingId'] is String) {
                detectedMusicId = fp['recordingId'] as String;
              }
            }
          }
        } catch (_) {}
      }

      // Build insert payload upfront so we can retry with fallbacks if needed
      final insertData = <String, dynamic>{
        'user_id': userId,
        'type': type,
        'caption': caption,
        'media_url': mediaUrl,
        'thumbnail_url': thumbnailUrl,
        'is_public': effectiveIsPublic,
        'allow_comments': allowComments,
        'allow_duets': allowDuets,
        'location': location,
        'hashtags': hashtags,
      };
      // Add optional fields only when provided to avoid triggering schema-cache errors
      if (duration != null) insertData['duration'] = duration;
      if (width != null) insertData['width'] = width;
      if (height != null) insertData['height'] = height;
      if (fileSize != null) insertData['file_size'] = fileSize;
      if (mimeType != null) insertData['mime_type'] = mimeType;
      // Persist effects/filter metadata compactly when available; remove on schema cache errors
      try {
        if (effects != null && effects.isNotEmpty) {
          insertData['effects_json'] = jsonEncode(effects);
        }
      } catch (_) {}
      if (filterId != null && filterId.isNotEmpty) {
        insertData['filter_id'] = filterId;
      }
      // Avoid inserting fields not present in the current database schema
      // (e.g., ai_metadata, music_id, filter_id, effects, parent_post_id)
      // This aligns with database_setup.sql and prevents unknown column errors.
      // If/when schema adds these fields, we can enable them here safely.
      // Extract mentions from caption
      if (caption != null && caption.isNotEmpty) {
        final regex = RegExp(r'@[a-zA-Z0-9_]+');
        final matches = regex.allMatches(caption);
        final set = <String>{};
        for (final m in matches) {
          final mention = m.group(0) ?? '';
          set.add(mention.substring(1));
        }
        insertData['mentions'] = set.isEmpty ? [] : set.toList();
      } else {
        insertData['mentions'] = [];
      }
      // Effects and harmony metadata are omitted to match the current schema.
      dynamic response;
      try {
        response = await _client
            .from(SupabaseConfig.postsTable)
            .insert(insertData)
            .select('''
              *,
              user:users!posts_user_id_fkey(
                id, username, display_name, avatar_url, is_verified
              )
            ''')
            .single();
      } catch (e) {
        // Gracefully handle missing optional columns reported by PostgREST schema cache (PGRST204)
        // Example: "Could not find the 'duration' column of 'posts' in the schema cache"
        final errStr = e.toString();
        final err = errStr.toLowerCase();
        bool retried = false;

        // Try to extract the missing column name from the error string
        String? missingColumn;
        final colMatch = RegExp(
          r"could not find the '([^']+)' column",
          caseSensitive: false,
        ).firstMatch(errStr);
        if (colMatch != null && colMatch.groupCount >= 1) {
          missingColumn = colMatch.group(1);
        }

        // Known optional columns that might not exist in the current posts schema
        final optionalColumns = <String>{
          'parent_post_id',
          'duration',
          'width',
          'height',
          'file_size',
          'mime_type',
          'effects_json',
          'filter_id',
        };

        if (err.contains('pgrst204') || err.contains('schema cache')) {
          // When the schema cache is missing columns, proactively remove ALL known optional columns
          // to avoid iterative failures (e.g., file_size then duration then width...)
          for (final c in optionalColumns) {
            if (insertData.containsKey(c)) {
              insertData.remove(c);
              retried = true;
            }
          }

          if (retried) {
            response = await _client
                .from(SupabaseConfig.postsTable)
                .insert(insertData)
                .select('''
                  *,
                  user:users!posts_user_id_fkey(
                    id, username, display_name, avatar_url, is_verified
                  )
                ''')
                .single();
          } else {
            rethrow;
          }
        } else if (err.contains('parent_post_id') &&
            insertData.containsKey('parent_post_id')) {
          // Specific parent_post_id handling when error doesn't include PGRST204 text
          insertData.remove('parent_post_id');
          response = await _client
              .from(SupabaseConfig.postsTable)
              .insert(insertData)
              .select('''
                *,
                user:users!posts_user_id_fkey(
                  id, username, display_name, avatar_url, is_verified
                )
              ''')
              .single();
        } else {
          rethrow;
        }
      }

      // Send mention notifications to mentioned users
      try {
        if (caption != null && caption.isNotEmpty) {
          final regex = RegExp(r'@[a-zA-Z0-9_]+');
          final matches = regex.allMatches(caption);
          final mentionedUsernames = <String>{};
          for (final m in matches) {
            mentionedUsernames.add((m.group(0) ?? '').substring(1));
          }
          if (mentionedUsernames.isNotEmpty) {
            // Get mentioner display name
            String mentionerName = 'Someone';
            try {
              final profile = await _client
                  .from('users')
                  .select('display_name,username')
                  .eq('id', userId)
                  .maybeSingle();
              if (profile != null) {
                mentionerName =
                    (profile['display_name'] as String?)?.trim().isNotEmpty ==
                        true
                    ? profile['display_name'] as String
                    : (profile['username'] as String? ?? 'Someone');
              }
            } catch (_) {}

            final notifier = EnhancedNotificationService();
            for (final uname in mentionedUsernames) {
              try {
                final target = await _client
                    .from('users')
                    .select('id')
                    .ilike('username', uname)
                    .maybeSingle();
                final mentionedUserId = target != null
                    ? target['id'] as String?
                    : null;
                if (mentionedUserId != null && mentionedUserId != userId) {
                  await notifier.createMentionNotification(
                    mentionedUserId: mentionedUserId,
                    mentionerName: mentionerName,
                    postId: response['id'] as String,
                  );
                }
              } catch (_) {}
            }
          }
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('Error sending mention notifications: $e');
        }
      }

      // Update user's posts count
      // Removed manual increment to avoid double-counting; database trigger handles this
      // await _client.rpc('increment_user_posts_count', params: {'target_user_id': userId});

      return PostModel.fromJson(response);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Database post creation error: $e');
        debugPrint('Error type: ${e.runtimeType}');
        debugPrint(
          'Post data: type=$type, userId=${_authService.currentUser?.id}, mediaUrl=$mediaUrl',
        );
      }

      // Provide more specific error messages
      final errorString = e.toString().toLowerCase();
      if (errorString.contains('network') ||
          errorString.contains('connection')) {
        throw Exception(
          'Network connection error. Please check your internet connection.',
        );
      } else if (errorString.contains('unauthorized') ||
          errorString.contains('401')) {
        throw Exception('Unauthorized access. Please log in again.');
      } else if (errorString.contains('forbidden') ||
          errorString.contains('403')) {
        throw Exception('Access forbidden. Please check your permissions.');
      } else if (errorString.contains('timeout')) {
        throw Exception('Database timeout. Please try again.');
      } else if (errorString.contains('constraint') ||
          errorString.contains('unique')) {
        throw Exception('Post creation failed due to data constraints.');
      } else if (errorString.contains('foreign key') ||
          errorString.contains('reference')) {
        throw Exception('Invalid user reference. Please log in again.');
      } else if (errorString.contains('null value') ||
          errorString.contains('not-null') ||
          errorString.contains('required field') ||
          errorString.contains('missing required')) {
        throw Exception('Missing required post data. Please try again.');
      } else if (errorString.contains('server') ||
          errorString.contains('500')) {
        throw Exception('Server error. Please try again later.');
      } else {
        throw Exception('Failed to create post: $e');
      }
    }
  }

  // Like/unlike a post
  Future<bool> toggleLike(String postId) async {
    try {
      final userId = _authService.currentUser?.id;
      if (userId == null) throw Exception('User not authenticated');

      // Check if already liked
      final existingLike = await _client
          .from(SupabaseConfig.likesTable)
          .select()
          .eq('user_id', userId)
          .eq('post_id', postId)
          .maybeSingle();

      if (existingLike != null) {
        // Unlike
        await _client
            .from(SupabaseConfig.likesTable)
            .delete()
            .eq('user_id', userId)
            .eq('post_id', postId);

        // Decrement likes count
        try {
          await _client.rpc(
            'decrement_post_likes_count',
            params: {'post_id': postId},
          );
        } catch (e) {
          debugPrint(
            'RPC decrement_post_likes_count failed, applying fallback: $e',
          );
          try {
            final postRow = await _client
                .from(SupabaseConfig.postsTable)
                .select('likes_count')
                .eq('id', postId)
                .maybeSingle();
            final current = (postRow?['likes_count'] as int?) ?? 0;
            final newValue = current > 0 ? current - 1 : 0;
            await _client
                .from(SupabaseConfig.postsTable)
                .update({'likes_count': newValue})
                .eq('id', postId);
          } catch (inner) {
            debugPrint('Fallback decrement likes_count failed: $inner');
          }
        }

        // Track analytics for unlike
        try {
          final postType = await _getPostType(postId);
          await _analyticsService.trackPostUnlike(
            postId,
            postType ?? 'unknown',
          );
        } catch (e) {
          debugPrint('toggleLike: failed to track unlike analytics: $e');
        }

        return false;
      } else {
        // Like
        await _client.from(SupabaseConfig.likesTable).insert({
          'user_id': userId,
          'post_id': postId,
        });

        // Increment likes count
        try {
          await _client.rpc(
            'increment_post_likes_count',
            params: {'post_id': postId},
          );
        } catch (e) {
          debugPrint(
            'RPC increment_post_likes_count failed, applying fallback: $e',
          );
          try {
            final postRow = await _client
                .from(SupabaseConfig.postsTable)
                .select('likes_count')
                .eq('id', postId)
                .maybeSingle();
            final current = (postRow?['likes_count'] as int?) ?? 0;
            await _client
                .from(SupabaseConfig.postsTable)
                .update({'likes_count': current + 1})
                .eq('id', postId);
          } catch (inner) {
            debugPrint('Fallback increment likes_count failed: $inner');
          }
        }

        // Create like notification for the post owner (including self-like)
        try {
          final postOwnerRow = await _client
              .from(SupabaseConfig.postsTable)
              .select('user_id')
              .eq('id', postId)
              .maybeSingle();
          final String? postOwnerId = postOwnerRow != null
              ? postOwnerRow['user_id'] as String?
              : null;
          if (postOwnerId != null) {
            // Determine liker name
            String likerName = 'Someone';
            try {
              final meta = _authService.currentUser?.userMetadata;
              final dnMeta = meta != null
                  ? (meta['display_name'] as String?)
                  : null;
              final unMeta = meta != null
                  ? (meta['username'] as String?)
                  : null;
              final dn = dnMeta?.trim();
              final un = unMeta?.trim();
              if (dn != null && dn.isNotEmpty) {
                likerName = dn;
              } else if (un != null && un.isNotEmpty) {
                likerName = un;
              } else {
                try {
                  final profile = await _client
                      .from('users')
                      .select('display_name,username')
                      .eq('id', userId)
                      .maybeSingle();
                  if (profile != null) {
                    final dp = (profile['display_name'] as String?)?.trim();
                    final up = (profile['username'] as String?)?.trim();
                    likerName = (dp != null && dp.isNotEmpty)
                        ? dp
                        : (up != null && up.isNotEmpty)
                        ? up
                        : 'Someone';
                  }
                } catch (_) {}
              }
            } catch (_) {}

            final notifier = EnhancedNotificationService();
            debugPrint(
              'toggleLike: creating like notification for postOwnerId=$postOwnerId, actorId=$userId',
            );
            await notifier.createLikeNotification(
              postOwnerId: postOwnerId,
              likerName: likerName,
              postId: postId,
            );
            debugPrint(
              'toggleLike: createLikeNotification completed for postId=$postId',
            );
          }
        } catch (_) {}

        // Track analytics for like
        try {
          final postType = await _getPostType(postId);
          await _analyticsService.trackPostLike(postId, postType ?? 'unknown');
        } catch (e) {
          debugPrint('toggleLike: failed to track like analytics: $e');
        }

        return true;
      }
    } catch (e) {
      debugPrint('Error toggling like: $e');
      return false;
    }
  }

  // Get following user IDs
  Future<List<String>> _getFollowingIds(String userId) async {
    try {
      final response = await _client
          .from(SupabaseConfig.followsTable)
          .select('following_id')
          .eq('follower_id', userId);

      return (response as List)
          .map((item) => item['following_id'] as String)
          .toList();
    } catch (e) {
      debugPrint('Error fetching following IDs: $e');
      return [];
    }
  }

  // Get tracking posts (posts from tracked users + own posts)
  Future<List<PostModel>> getTrackingPosts({
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final currentUserId = _authService.currentUser?.id;
      if (currentUserId == null) {
        throw Exception('User not authenticated');
      }

      // Get list of users being tracked
      final trackingIds = await _getFollowingIds(currentUserId);

      // Include current user's own posts
      final userIds = [currentUserId, ...trackingIds];

      if (userIds.isEmpty) {
        return [];
      }

      final response = await _client
          .from(SupabaseConfig.postsTable)
          .select('''
            *,
            user:users!posts_user_id_fkey(
              id, username, display_name, avatar_url, is_verified
            ),
            comments_count,
            likes_count,
            shares_count,
            views_count,
            comments(count)
          ''')
          .inFilter('user_id', userIds)
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      // Process posts and check likes for current user
      final posts = <PostModel>[];
      for (final json in response as List) {
        final postData = json as Map<String, dynamic>;

        // Check if current user liked this post
        final likeCheck = await _client
            .from(SupabaseConfig.likesTable)
            .select('id')
            .eq('user_id', currentUserId)
            .eq('post_id', postData['id'])
            .maybeSingle();

        postData['is_liked'] = likeCheck != null;

        posts.add(PostModel.fromJson(postData));
      }

      // Prioritize special account posts: keep at top for configured hours
      if (SupabaseConfig.specialAccountIds.isNotEmpty) {
        final pinnedDuration = Duration(
          hours: SupabaseConfig.specialPinnedHours,
        );
        final now = DateTime.now();
        posts.sort((a, b) {
          bool aPinned =
              SupabaseConfig.specialAccountIds.contains(a.userId) &&
              now.difference(a.timestamp) <= pinnedDuration;
          bool bPinned =
              SupabaseConfig.specialAccountIds.contains(b.userId) &&
              now.difference(b.timestamp) <= pinnedDuration;
          if (aPinned && !bPinned) return -1;
          if (!aPinned && bPinned) return 1;
          // Fallback to original order (by timestamp desc)
          return b.timestamp.compareTo(a.timestamp);
        });
      }

      return posts;
    } catch (e) {
      debugPrint('Error fetching tracking posts: $e');
      return [];
    }
  }

  // Check and process monetization for posts that reach thresholds
  Future<void> processMonetization() async {
    await _monetizationService.processMonetizationQueue();
  }

  // Check if a post is eligible for monetization
  Future<bool> checkMonetizationEligibility(String postId) async {
    try {
      final post = await getPostById(postId);
      if (post == null) return false;

      return _monetizationService.meetsMonetizationThreshold(post);
    } catch (e) {
      debugPrint('Error checking monetization eligibility: $e');
      return false;
    }
  }

  // Enable ads for a specific post
  Future<bool> enablePostMonetization(String postId) async {
    try {
      final isEligible = await checkMonetizationEligibility(postId);
      if (!isEligible) return false;

      return await _monetizationService.enableAdServing(postId);
    } catch (e) {
      debugPrint('Error enabling post monetization: $e');
      return false;
    }
  }

  // Get posts that are currently monetized
  Future<List<PostModel>> getMonetizedPosts({
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final currentUserId = _authService.currentUser?.id;

      var query = _client
          .from(SupabaseConfig.postsTable)
          .select('''
            *,
            user:users!posts_user_id_fkey(
              id, username, display_name, avatar_url, is_verified
            ),
            comments_count,
            likes_count,
            shares_count
          ''')
          .gte('likes_count', MonetizationService.reactionsThreshold)
          .gte('comments_count', MonetizationService.commentsThreshold);
      if (currentUserId != null) {
        final trackingIds = await _getFollowingIds(currentUserId);
        final userIds = [currentUserId, ...trackingIds];
        final idsList = userIds.map((id) => id.replaceAll(',', '')).toList();
        final idsOrClause = idsList.isEmpty
            ? 'is_public.eq.true'
            : 'is_public.eq.true,user_id.in.(${idsList.join(',')})';
        query = query.or(idsOrClause);
      } else {
        query = query.eq('is_public', true);
      }
      final response = await query
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      // Process posts and check likes for current user
      final posts = <PostModel>[];
      for (final json in response as List) {
        final postData = json as Map<String, dynamic>;

        // Check if current user liked this post
        if (currentUserId != null) {
          final likeCheck = await _client
              .from(SupabaseConfig.likesTable)
              .select('id')
              .eq('user_id', currentUserId)
              .eq('post_id', postData['id'])
              .maybeSingle();

          postData['is_liked'] = likeCheck != null;
        } else {
          postData['is_liked'] = false;
        }

        posts.add(PostModel.fromJson(postData));
      }

      return posts;
    } catch (e) {
      debugPrint('Error fetching monetized posts: $e');
      return [];
    }
  }

  // Subscribe to posts updates
  Future<void> _subscribeToPostsUpdates() async {
    _postsSubscription = _client
        .channel(SupabaseConfig.postsChannel)
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: SupabaseConfig.postsTable,
          callback: (payload) {
            // Refresh posts when changes occur
            _refreshPosts();
          },
        )
        .subscribe();
  }

  // Subscribe to likes updates
  Future<void> _subscribeToLikesUpdates() async {
    _likesSubscription = _client
        .channel(SupabaseConfig.likesChannel)
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: SupabaseConfig.likesTable,
          callback: (payload) {
            _likesController.add(payload.newRecord);
          },
        )
        .subscribe();
  }

  // Refresh posts and emit to stream
  Future<void> _refreshPosts() async {
    final posts = await getFeedPosts();
    _postsController.add(posts);
  }

  // Delete a post
  Future<bool> deletePost(String postId) async {
    try {
      final userId = _authService.currentUser?.id;
      if (userId == null) throw Exception('User not authenticated');

      await _client
          .from(SupabaseConfig.postsTable)
          .delete()
          .eq('id', postId)
          .eq('user_id', userId); // Ensure user can only delete their own posts

      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Database post deletion error: $e');
        debugPrint('Error type: ${e.runtimeType}');
        debugPrint(
          'Post ID: $postId, User ID: ${_authService.currentUser?.id}',
        );
      }

      // Provide more specific error messages
      final errorString = e.toString().toLowerCase();
      if (errorString.contains('network') ||
          errorString.contains('connection')) {
        throw Exception(
          'Network connection error. Please check your internet connection.',
        );
      } else if (errorString.contains('unauthorized') ||
          errorString.contains('401')) {
        throw Exception('Unauthorized access. Please log in again.');
      } else if (errorString.contains('forbidden') ||
          errorString.contains('403')) {
        throw Exception(
          'Access forbidden. You can only delete your own posts.',
        );
      } else if (errorString.contains('not found') ||
          errorString.contains('404')) {
        throw Exception('Post not found or already deleted.');
      } else if (errorString.contains('timeout')) {
        throw Exception('Database timeout. Please try again.');
      } else {
        throw Exception('Failed to delete post: $e');
      }
    }
  }

  // Update post
  Future<PostModel?> updatePost({
    required String postId,
    String? caption,
    String? location,
    List<String>? hashtags,
    bool? isPublic,
    bool? allowComments,
    bool? allowDuets,
  }) async {
    try {
      final userId = _authService.currentUser?.id;
      if (userId == null) throw Exception('User not authenticated');

      final updates = <String, dynamic>{};
      if (caption != null) updates['caption'] = caption;
      if (location != null) updates['location'] = location;
      if (hashtags != null) updates['hashtags'] = hashtags;
      if (isPublic != null) updates['is_public'] = isPublic;
      if (allowComments != null) updates['allow_comments'] = allowComments;
      if (allowDuets != null) updates['allow_duets'] = allowDuets;

      updates['updated_at'] = DateTime.now().toIso8601String();

      final response = await _client
          .from(SupabaseConfig.postsTable)
          .update(updates)
          .eq('id', postId)
          .eq('user_id', userId) // Ensure user can only update their own posts
          .select('''
            *,
            user:users!posts_user_id_fkey(
              id, username, display_name, avatar_url, is_verified
            )
          ''')
          .single();

      return PostModel.fromJson(response);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Database post update error: $e');
        debugPrint('Error type: ${e.runtimeType}');
        debugPrint(
          'Post ID: $postId, User ID: ${_authService.currentUser?.id}',
        );
      }

      // Provide more specific error messages
      final errorString = e.toString().toLowerCase();
      if (errorString.contains('network') ||
          errorString.contains('connection')) {
        throw Exception(
          'Network connection error. Please check your internet connection.',
        );
      } else if (errorString.contains('unauthorized') ||
          errorString.contains('401')) {
        throw Exception('Unauthorized access. Please log in again.');
      } else if (errorString.contains('forbidden') ||
          errorString.contains('403')) {
        throw Exception(
          'Access forbidden. You can only update your own posts.',
        );
      } else if (errorString.contains('not found') ||
          errorString.contains('404')) {
        throw Exception('Post not found or no longer exists.');
      } else if (errorString.contains('timeout')) {
        throw Exception('Database timeout. Please try again.');
      } else if (errorString.contains('constraint') ||
          errorString.contains('validation')) {
        throw Exception('Invalid post data. Please check your input.');
      } else {
        throw Exception('Failed to update post: $e');
      }
    }
  }

  // Get user post count
  Future<int> getUserPostCount(String userId) async {
    try {
      final currentUserId = _authService.currentUser?.id;

      // Determine if viewer can see private posts
      bool canSeePrivate = false;
      if (currentUserId != null) {
        if (currentUserId == userId) {
          canSeePrivate = true;
        } else {
          final followingIds = await _getFollowingIds(currentUserId);
          canSeePrivate = followingIds.contains(userId);
        }
      }

      var query = _client
          .from(SupabaseConfig.postsTable)
          .select('id')
          .eq('user_id', userId);

      if (!canSeePrivate) {
        query = query.eq('is_public', true);
      }

      final response = await query.count(CountOption.exact);
      return response.count;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error getting user post count: $e');
      }
      return 0;
    }
  }

  // Update media_url and/or thumbnail_url for a post
  Future<PostModel?> updatePostMediaFields({
    required String postId,
    String? mediaUrl,
    String? thumbnailUrl,
  }) async {
    try {
      final userId = _authService.currentUser?.id;
      if (userId == null) throw Exception('User not authenticated');

      final updates = <String, dynamic>{};
      if (mediaUrl != null) updates['media_url'] = mediaUrl;
      if (thumbnailUrl != null) updates['thumbnail_url'] = thumbnailUrl;
      updates['updated_at'] = DateTime.now().toIso8601String();

      final response = await _client
          .from(SupabaseConfig.postsTable)
          .update(updates)
          .eq('id', postId)
          .eq('user_id', userId)
          .select('''
            *,
            user:users!posts_user_id_fkey(
              id, username, display_name, avatar_url, is_verified
            )
          ''')
          .single();

      return PostModel.fromJson(response);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Database post media update error: $e');
        debugPrint('Error type: ${e.runtimeType}');
      }
      return null;
    }
  }
}

// Helper to get post type (media_type) for analytics
Future<String?> _getPostType(String postId) async {
  try {
    final row = await SupabaseConfig.client
        .from(SupabaseConfig.postsTable)
        .select('media_type')
        .eq('id', postId)
        .maybeSingle();
    final dynamic mt = row != null ? row['media_type'] : null;
    if (mt is String && mt.isNotEmpty) return mt;
    // Fallback: attempt to read via joined post
    try {
      final post = await PostsService().getPostById(postId);
      return post?.type;
    } catch (_) {}
    return null;
  } catch (e) {
    debugPrint('_getPostType error: $e');
    return null;
  }
}
