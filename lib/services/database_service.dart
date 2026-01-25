import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import '../config/supabase_config.dart';
import 'media_upload_service.dart';
import 'enhanced_notification_service.dart';
import 'localization_service.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  final SupabaseClient _client = SupabaseConfig.client;
  final MediaUploadService _mediaService = MediaUploadService();

  // Stream controllers for real-time updates
  final _postsController =
      StreamController<List<Map<String, dynamic>>>.broadcast();
  final _commentsController =
      StreamController<List<Map<String, dynamic>>>.broadcast();
  final _notificationsController =
      StreamController<List<Map<String, dynamic>>>.broadcast();
  final _likesController = StreamController<Map<String, dynamic>>.broadcast();

  // Getters for streams
  Stream<List<Map<String, dynamic>>> get postsStream => _postsController.stream;
  Stream<List<Map<String, dynamic>>> get commentsStream =>
      _commentsController.stream;
  Stream<List<Map<String, dynamic>>> get notificationsStream =>
      _notificationsController.stream;
  Stream<Map<String, dynamic>> get likesStream => _likesController.stream;

  // Real-time subscriptions
  RealtimeChannel? _postsSubscription;
  RealtimeChannel? _commentsSubscription;
  RealtimeChannel? _notificationsSubscription;
  RealtimeChannel? _likesSubscription;

  // Initialize real-time subscriptions
  Future<void> initializeRealtime(String userId) async {
    await _subscribeToPostsUpdates();
    await _subscribeToCommentsUpdates();
    await _subscribeToNotificationsUpdates(userId);
    await _subscribeToLikesUpdates();
  }

  // Clean up subscriptions
  Future<void> dispose() async {
    await _postsSubscription?.unsubscribe();
    await _commentsSubscription?.unsubscribe();
    await _notificationsSubscription?.unsubscribe();
    await _likesSubscription?.unsubscribe();

    _postsController.close();
    _commentsController.close();
    _notificationsController.close();
    _likesController.close();
  }

  // Posts operations
  Future<Map<String, dynamic>> createPost({
    required String userId,
    required String type,
    String? caption,
    String? mediaUrl,
    String? thumbnailUrl,
    bool? isPublic,
    bool allowComments = true,
    String? location,
    List<String>? hashtags,
    Map<String, dynamic>? aiMetadata,
    String? musicId,
  }) async {
    // Determine effective visibility from profile privacy when not explicitly provided
    bool effectiveIsPublic = true;
    try {
      final profile = await _client
          .from('users')
          .select('is_private')
          .eq('id', userId)
          .maybeSingle();
      final isPrivate = profile != null && profile['is_private'] == true;
      effectiveIsPublic = isPublic ?? !isPrivate;
    } catch (_) {
      effectiveIsPublic = isPublic ?? true;
    }

    // Extract mentions from caption
    List<String>? mentions;
    if (caption != null && caption.isNotEmpty) {
      final regex = RegExp(r'@[a-zA-Z0-9_]+');
      final matches = regex.allMatches(caption);
      final set = <String>{};
      for (final m in matches) {
        final mention = m.group(0) ?? '';
        set.add(mention.substring(1));
      }
      mentions = set.isEmpty ? [] : set.toList();
    }

    final insertPayload = {
      'user_id': userId,
      'type': type,
      'caption': caption,
      'content': caption ?? '',
      'media_url': mediaUrl,
      'thumbnail_url': thumbnailUrl,
      'is_public': effectiveIsPublic,
      'allow_comments': allowComments,
      'location': location,
      'hashtags': hashtags ?? [],
      'mentions': mentions ?? [],
    };
    if (aiMetadata != null) insertPayload['ai_metadata'] = aiMetadata;
    if (musicId != null && musicId.isNotEmpty)
      insertPayload['music_id'] = musicId;

    dynamic response;
    try {
      response = await _client
          .from(SupabaseConfig.postsTable)
          .insert(insertPayload)
          .select()
          .single();
    } catch (e) {
      final errStr = e.toString();
      final err = errStr.toLowerCase();
      bool retried = false;

      // Extract missing column if present
      String? missingColumn;
      final colMatch = RegExp(
        r"could not find the '([^']+)' column",
        caseSensitive: false,
      ).firstMatch(errStr);
      if (colMatch != null && colMatch.groupCount >= 1) {
        missingColumn = colMatch.group(1);
      }

      // Optional/extra fields that may not exist in current posts schema
      final optionalColumns = <String>{
        'thumbnail_url',
        'hashtags',
        'mentions',
        'ai_metadata',
        'music_id',
        'location',
      };

      if (err.contains('pgrst204') || err.contains('schema cache')) {
        // Remove ALL known optional columns to avoid iterative failures
        for (final c in optionalColumns) {
          if (insertPayload.containsKey(c)) {
            insertPayload.remove(c);
            retried = true;
          }
        }

        if (retried) {
          response = await _client
              .from(SupabaseConfig.postsTable)
              .insert(insertPayload)
              .select()
              .single();
        } else if (missingColumn != null &&
            insertPayload.containsKey(missingColumn)) {
          insertPayload.remove(missingColumn);
          response = await _client
              .from(SupabaseConfig.postsTable)
              .insert(insertPayload)
              .select()
              .single();
        } else {
          rethrow;
        }
      } else {
        rethrow;
      }
    }

    // Send mention notifications to mentioned users
    try {
      if (mentions != null && mentions.isNotEmpty) {
        // Resolve mentioner name
        String mentionerName = 'Someone';
        try {
          final profile = await _client
              .from('users')
              .select('display_name,username')
              .eq('id', userId)
              .maybeSingle();
          if (profile != null) {
            mentionerName =
                (profile['display_name'] as String?)?.trim().isNotEmpty == true
                ? profile['display_name'] as String
                : (profile['username'] as String? ?? 'Someone');
          }
        } catch (_) {}

        final notifier = EnhancedNotificationService();
        for (final uname in mentions) {
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
    } catch (_) {}

    return response;
  }

  Future<List<Map<String, dynamic>>> getFeedPosts({
    String? userId,
    int limit = 20,
    int offset = 0,
  }) async {
    dynamic query;

    if (userId != null) {
      // Get posts from followed users + own posts (include private posts for these users)
      final followingIdsString = await _getFollowingIds(userId);
      final followingIds = followingIdsString
          .split(',')
          .where((id) => id.isNotEmpty)
          .toList();
      final userIds = [userId, ...followingIds];

      query = _client
          .from('posts')
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
    } else {
      query = _client
          .from('posts')
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
          .range(offset, offset + limit - 1);
    }

    try {
      final response = await query;

      if (response is List) {
        return List<Map<String, dynamic>>.from(response);
      } else {
        return [];
      }
    } catch (e) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getUserPosts({
    required String userId,
    int limit = 20,
    int offset = 0,
  }) async {
    final response = await _client
        .from(SupabaseConfig.postsTable)
        .select('''
          *,
          user:users!posts_user_id_fkey(
            id, username, display_name, avatar_url, is_verified
          ),
          is_liked:likes!left(user_id),
          is_saved:saves!left(user_id)
        ''')
        .eq('user_id', userId)
        .eq('is_public', true)
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);

    return List<Map<String, dynamic>>.from(response);
  }

  Future<void> deletePost(String postId, String userId) async {
    // Delete the post
    await _client
        .from(SupabaseConfig.postsTable)
        .delete()
        .eq('id', postId)
        .eq('user_id', userId);

    // Decrement user's posts count
    // Removed manual decrement; rely on posts DELETE trigger to adjust posts_count
    // await _client.rpc('decrement_user_posts_count', params: {'user_id': userId});
  }

  // Comments operations
  Future<Map<String, dynamic>> addComment({
    required String postId,
    required String userId,
    String? text,
    String? parentId,
    String? audioUrl,
    String? mediaUrl,
  }) async {
    final insertData = {
      'post_id': postId,
      'user_id': userId,
      'parent_id': parentId,
    };

    // Add content if text is provided
    if (text != null && text.isNotEmpty) {
      insertData['content'] = text;
      // Note: We extract mentions for notifications below, but do not store to comments.mentions unless schema supports it
    }

    // Add audio URL if provided
    if (audioUrl != null && audioUrl.isNotEmpty) {
      insertData['audio_url'] = audioUrl;
    }

    // Add media URL if provided
    if (mediaUrl != null && mediaUrl.isNotEmpty) {
      insertData['media_url'] = mediaUrl;
    }

    final response = await _client
        .from(SupabaseConfig.commentsTable)
        .insert(insertData)
        .select('''
          *,
          user:users!comments_user_id_fkey(
            id, username, display_name, avatar_url, is_verified
          )
        ''')
        .single();

    // Send mention notifications if text contained mentions
    try {
      if (text != null && text.trim().isNotEmpty) {
        final regex = RegExp(r'@[a-zA-Z0-9_]+');
        final matches = regex.allMatches(text);
        final mentionedUsernames = <String>{};
        for (final m in matches) {
          mentionedUsernames.add((m.group(0) ?? '').substring(1));
        }
        if (mentionedUsernames.isNotEmpty) {
          // Resolve mentioner name
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
                  postId: postId,
                );
              }
            } catch (_) {}
          }
        }
      }
    } catch (_) {}

    // Increment post's comments count via RPC; fallback to manual update
    try {
      await _client.rpc(
        'increment_post_comments_count',
        params: {'post_id': postId},
      );
    } catch (e) {
      try {
        final postResponse = await _client
            .from('posts')
            .select('comments_count')
            .eq('id', postId)
            .single();
        final currentCount = postResponse['comments_count'] ?? 0;
        await _client
            .from('posts')
            .update({
              'comments_count': currentCount + 1,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', postId);
      } catch (inner) {
        debugPrint('Error updating comment count: ${inner.toString()}');
      }
    }

    // New: create comment notification for post owner
    try {
      final postOwnerRow = await _client
          .from('posts')
          .select('user_id')
          .eq('id', postId)
          .single();
      final String? postOwnerId = postOwnerRow['user_id'] as String?;
      if (postOwnerId != null && postOwnerId != userId) {
        String commenterName = 'Someone';
        try {
          final userJson = response['user'] as Map<String, dynamic>?;
          if (userJson != null) {
            final dn = (userJson['display_name'] as String?)?.trim();
            final un = (userJson['username'] as String?)?.trim();
            commenterName = (dn != null && dn.isNotEmpty)
                ? dn
                : (un ?? 'Someone');
          } else {
            final profile = await _client
                .from('users')
                .select('display_name,username')
                .eq('id', userId)
                .maybeSingle();
            if (profile != null) {
              final dn = (profile['display_name'] as String?)?.trim();
              final un = (profile['username'] as String?)?.trim();
              commenterName = (dn != null && dn.isNotEmpty)
                  ? dn
                  : (un ?? 'Someone');
            }
          }
        } catch (_) {}
        final String commentId = (response['id'] as String).toString();
        await EnhancedNotificationService().createCommentNotification(
          postOwnerId: postOwnerId,
          commenterName: commenterName,
          postId: postId,
          commentId: commentId,
        );
      }
    } catch (_) {}

    return response;
  }

  Future<List<Map<String, dynamic>>> getComments({
    required String postId,
    int limit = 50,
    int offset = 0,
  }) async {
    final response = await _client
        .from(SupabaseConfig.commentsTable)
        .select('''
          *,
          user:users!comments_user_id_fkey(
            id, username, display_name, avatar_url, is_verified
          ),
          is_liked:likes!left(user_id)
        ''')
        .eq('post_id', postId)
        .isFilter('parent_id', null)
        .order('created_at', ascending: true)
        .range(offset, offset + limit - 1);

    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> getReplies({
    required String commentId,
    int limit = 50,
    int offset = 0,
  }) async {
    final response = await _client
        .from(SupabaseConfig.commentsTable)
        .select('''
          *,
          user:users!comments_user_id_fkey(
            id, username, display_name, avatar_url, is_verified
          ),
          is_liked:likes!left(user_id)
        ''')
        .eq('parent_id', commentId)
        .order('created_at', ascending: true)
        .range(offset, offset + limit - 1);

    return List<Map<String, dynamic>>.from(response);
  }

  Future<int> getTotalCommentCount(String postId) async {
    try {
      final res = await _client
          .from(SupabaseConfig.commentsTable)
          .select('count')
          .eq('post_id', postId)
          .count(CountOption.exact);
      return res.count;
    } catch (_) {
      try {
        final response = await _client
            .from(SupabaseConfig.commentsTable)
            .select('id')
            .eq('post_id', postId);
        return response.length;
      } catch (_) {
        return 0;
      }
    }
  }

  Future<void> deleteComment(String commentId, String userId) async {
    // Get the comment to find the post_id
    final comment = await _client
        .from(SupabaseConfig.commentsTable)
        .select('post_id')
        .eq('id', commentId)
        .eq('user_id', userId)
        .single();

    // Delete the comment
    await _client
        .from(SupabaseConfig.commentsTable)
        .delete()
        .eq('id', commentId)
        .eq('user_id', userId);

    // Decrement post's comments count via RPC; fallback to manual update
    try {
      await _client.rpc(
        'decrement_post_comments_count',
        params: {'post_id': comment['post_id']},
      );
    } catch (e) {
      try {
        final postResponse = await _client
            .from('posts')
            .select('comments_count')
            .eq('id', comment['post_id'])
            .single();
        final currentCount = postResponse['comments_count'] ?? 0;
        await _client
            .from('posts')
            .update({
              'comments_count': currentCount > 0 ? currentCount - 1 : 0,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', comment['post_id']);
      } catch (inner) {
        debugPrint(('Error updating comment count: $inner').toString());
      }
    }
  }

  // Likes operations
  Future<void> likePost(String postId, String userId) async {
    await _client.from(SupabaseConfig.likesTable).insert({
      'post_id': postId,
      'user_id': userId,
    });

    // Increment post's likes count
    try {
      await _client.rpc(
        'increment_post_likes_count',
        params: {'post_id': postId},
      );
    } catch (e) {
      debugPrint(
        ('RPC increment_post_likes_count failed, applying fallback: $e')
            .toString(),
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
        debugPrint(
          ('Fallback increment likes_count failed: $inner').toString(),
        );
      }
    }

    // New: create like notification for post owner
    try {
      final postOwnerRow = await _client
          .from('posts')
          .select('user_id')
          .eq('id', postId)
          .single();
      final String? postOwnerId = postOwnerRow['user_id'] as String?;
      if (postOwnerId != null) {
        String likerName = 'Someone';
        try {
          final profile = await _client
              .from('users')
              .select('display_name,username')
              .eq('id', userId)
              .maybeSingle();
          if (profile != null) {
            final dn = (profile['display_name'] as String?)?.trim();
            final un = (profile['username'] as String?)?.trim();
            likerName = (dn != null && dn.isNotEmpty) ? dn : (un ?? 'Someone');
          }
        } catch (_) {}
        await EnhancedNotificationService().createLikeNotification(
          postOwnerId: postOwnerId,
          likerName: likerName,
          postId: postId,
        );
        debugPrint(
          ('database_service.likePost: createLikeNotification called for postId=$postId, postOwnerId=$postOwnerId, actorId=$userId')
              .toString(),
        );
      }
    } catch (_) {}
  }

  Future<void> unlikePost(String postId, String userId) async {
    await _client
        .from(SupabaseConfig.likesTable)
        .delete()
        .eq('post_id', postId)
        .eq('user_id', userId);

    // Decrement post's likes count
    try {
      await _client.rpc(
        'decrement_post_likes_count',
        params: {'post_id': postId},
      );
    } catch (e) {
      debugPrint(
        ('RPC decrement_post_likes_count failed, applying fallback: $e')
            .toString(),
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
        debugPrint(
          ('Fallback decrement likes_count failed: $inner').toString(),
        );
      }
    }

    // New: create like notification for post owner
    try {
      final postOwnerRow = await _client
          .from('posts')
          .select('user_id')
          .eq('id', postId)
          .single();
      final String? postOwnerId = postOwnerRow['user_id'] as String?;
      if (postOwnerId != null) {
        String likerName = 'Someone';
        try {
          final profile = await _client
              .from('users')
              .select('display_name,username')
              .eq('id', userId)
              .maybeSingle();
          if (profile != null) {
            final dn = (profile['display_name'] as String?)?.trim();
            final un = (profile['username'] as String?)?.trim();
            likerName = (dn != null && dn.isNotEmpty) ? dn : (un ?? 'Someone');
          }
        } catch (_) {}
        await EnhancedNotificationService().createLikeNotification(
          postOwnerId: postOwnerId,
          likerName: likerName,
          postId: postId,
        );
        debugPrint(
          ('database_service.likePost: createLikeNotification called for postId=$postId, postOwnerId=$postOwnerId, actorId=$userId')
              .toString(),
        );
      }
    } catch (_) {}
  }

  Future<void> likeComment(String commentId, String userId) async {
    await _client.from(SupabaseConfig.likesTable).insert({
      'comment_id': commentId,
      'user_id': userId,
    });

    // Increment comment's likes count
    await _client.rpc(
      'increment_comment_likes_count',
      params: {'comment_id': commentId},
    );
  }

  Future<void> unlikeComment(String commentId, String userId) async {
    await _client
        .from(SupabaseConfig.likesTable)
        .delete()
        .eq('comment_id', commentId)
        .eq('user_id', userId);

    // Decrement comment's likes count
    await _client.rpc(
      'decrement_comment_likes_count',
      params: {'comment_id': commentId},
    );
  }

  // Track operations
  Future<void> trackUser(String trackerId, String trackingId) async {
    await _client.from(SupabaseConfig.followsTable).insert({
      'follower_id': trackerId,
      'following_id': trackingId,
    });

    // Update counts
    await Future.wait([
      _client.rpc(
        'increment_user_followers_count',
        params: {'user_id': trackingId},
      ),
      _client.rpc(
        'increment_user_following_count',
        params: {'user_id': trackerId},
      ),
    ]);
  }

  Future<void> untrackUser(String trackerId, String trackingId) async {
    await _client
        .from(SupabaseConfig.followsTable)
        .delete()
        .eq('follower_id', trackerId)
        .eq('following_id', trackingId);

    // Update counts
    await Future.wait([
      _client.rpc(
        'decrement_user_followers_count',
        params: {'user_id': trackingId},
      ),
      _client.rpc(
        'decrement_user_following_count',
        params: {'user_id': trackerId},
      ),
    ]);
  }

  Future<List<Map<String, dynamic>>> getTrackers(String userId) async {
    final response = await _client
        .from(SupabaseConfig.followsTable)
        .select('''
          follower:users!follows_follower_id_fkey(
            id, username, display_name, avatar_url, bio, is_verified,
            followers_count, following_count, posts_count
          )
        ''')
        .eq('following_id', userId)
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(
      response.map((item) => item['follower']),
    );
  }

  Future<List<Map<String, dynamic>>> getTracking(String userId) async {
    final response = await _client
        .from(SupabaseConfig.followsTable)
        .select('''
          following:users!follows_following_id_fkey(
            id, username, display_name, avatar_url, bio, is_verified,
            followers_count, following_count, posts_count
          )
        ''')
        .eq('follower_id', userId)
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(
      response.map((item) => item['following']),
    );
  }

  Future<bool> isTracking(String trackerId, String trackingId) async {
    final response = await _client
        .from(SupabaseConfig.followsTable)
        .select('id')
        .eq('follower_id', trackerId)
        .eq('following_id', trackingId)
        .maybeSingle();

    return response != null;
  }

  // File upload operations - Now using Cloudflare R2
  Future<String> uploadFile({
    required String bucket,
    required String fileName,
    required Uint8List fileBytes,
    String? contentType,
    String? userId,
    String? postId,
  }) async {
    // For backward compatibility, we need to determine the upload type
    // based on the bucket and route to appropriate MediaUploadService method

    if (userId == null) {
      throw Exception('userId is required for R2 uploads');
    }

    switch (bucket) {
      case SupabaseConfig.profileImagesBucket:
        return await _mediaService.uploadProfileImage(
          userId: userId,
          imageBytes: fileBytes,
          originalFileName: fileName,
        );
      case SupabaseConfig.postImagesBucket:
        return await _mediaService.uploadPostImage(
          userId: userId,
          postId: postId ?? 'unknown',
          imageBytes: fileBytes,
          originalFileName: fileName,
        );
      case SupabaseConfig.postVideosBucket:
        return await _mediaService.uploadPostVideo(
          userId: userId,
          postId: postId ?? 'unknown',
          videoBytes: fileBytes,
          originalFileName: fileName,
        );
      case SupabaseConfig.postAudioBucket:
        return await _mediaService.uploadPostAudio(
          userId: userId,
          postId: postId ?? 'unknown',
          audioBytes: fileBytes,
          originalFileName: fileName,
        );
      case SupabaseConfig.thumbnailsBucket:
        return await _mediaService.uploadVideoThumbnail(
          userId: userId,
          postId: postId ?? 'unknown',
          thumbnailBytes: fileBytes,
        );
      default:
        throw Exception('Unsupported bucket for R2 upload: $bucket');
    }
  }

  Future<void> deleteFile(String bucket, String fileName) async {
    await _client.storage.from(bucket).remove([fileName]);
  }

  // Search operations
  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    final response = await _client
        .from(SupabaseConfig.usersTable)
        .select(
          'id, username, display_name, avatar_url, bio, is_verified, followers_count',
        )
        .or('username.ilike.%$query%,display_name.ilike.%$query%')
        .limit(20);

    return List<Map<String, dynamic>>.from(response);
  }

  @Deprecated('Use SocialService.searchPosts for privacy-aware post search')
  Future<List<Map<String, dynamic>>> searchPosts(String query) async {
    throw UnimplementedError(
      'DatabaseService.searchPosts is deprecated. Use SocialService.searchPosts.',
    );
  }

  // Notification operations
  Future<void> createNotification({
    required String userId,
    required String actorId,
    required String type,
    String? postId,
    String? commentId,
    String? message,
  }) async {
    try {
      // Delegate to EnhancedNotificationService with unified schema
      final Map<String, dynamic> data = {
        if (postId != null) 'post_id': postId,
        if (commentId != null) 'comment_id': commentId,
        'actor_id': actorId,
        'action_type': type,
      };

      final String title =
          {
            'like': LocalizationService.t('new_like_title'),
            'comment': LocalizationService.t('new_comment_title'),
            // If specific tracker title key is missing, keep a reasonable default
            'follow': LocalizationService.t('new_message_title'),
            'mention': LocalizationService.t('new_message_title'),
            'message': LocalizationService.t('new_message_title'),
          }[type] ??
          LocalizationService.t('message');

      final String msg =
          message ??
          {
            'like': LocalizationService.t('liked_your_post'),
            'comment': LocalizationService.t('commented_on_your_post'),
            'message': LocalizationService.t('sent_you_a_message'),
            // Fallbacks if we don't have dedicated keys
            'mention': LocalizationService.t('message'),
            'follow': LocalizationService.t('message'),
          }[type] ??
          LocalizationService.t('message');

      await EnhancedNotificationService().createNotification(
        userId: userId,
        type: type,
        title: title,
        message: msg,
        data: data,
      );
    } catch (e) {
      debugPrint(('Error creating notification: $e').toString());
    }
  }

  Future<List<Map<String, dynamic>>> getNotifications(String userId) async {
    final response = await _client
        .from(SupabaseConfig.notificationsTable)
        .select(
          'id,user_id,type,title,message,data,is_read,created_at,actor_id',
        )
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(50);

    return List<Map<String, dynamic>>.from(response);
  }

  Future<void> markNotificationAsRead(String notificationId) async {
    await _client
        .from(SupabaseConfig.notificationsTable)
        .update({'is_read': true})
        .eq('id', notificationId);
  }

  Future<void> markAllNotificationsAsRead(String userId) async {
    await _client
        .from(SupabaseConfig.notificationsTable)
        .update({'is_read': true})
        .eq('user_id', userId)
        .eq('is_read', false);
  }

  // Real-time subscription methods
  Future<void> _subscribeToPostsUpdates() async {
    _postsSubscription = _client
        .channel(SupabaseConfig.postsChannel)
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: SupabaseConfig.postsTable,
          callback: (payload) {
            // Handle real-time post updates
            _handlePostsUpdate(payload);
          },
        )
        .subscribe();
  }

  Future<void> _subscribeToCommentsUpdates() async {
    _commentsSubscription = _client
        .channel(SupabaseConfig.commentsChannel)
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: SupabaseConfig.commentsTable,
          callback: (payload) {
            // Handle real-time comment updates
            _handleCommentsUpdate(payload);
          },
        )
        .subscribe();
  }

  Future<void> _subscribeToNotificationsUpdates(String userId) async {
    _notificationsSubscription = _client
        .channel(SupabaseConfig.notificationsChannel)
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: SupabaseConfig.notificationsTable,
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) {
            // Handle real-time notification updates
            _handleNotificationsUpdate(payload);
          },
        )
        .subscribe();
  }

  Future<void> _subscribeToLikesUpdates() async {
    _likesSubscription = _client
        .channel(SupabaseConfig.likesChannel)
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: SupabaseConfig.likesTable,
          callback: (payload) {
            // Handle real-time likes updates
            _handleLikesUpdate(payload);
          },
        )
        .subscribe();
  }

  // Real-time update handlers
  void _handlePostsUpdate(PostgresChangePayload payload) {
    // Implement posts update logic
    debugPrint(('Posts update: ${payload.eventType}').toString());
  }

  void _handleCommentsUpdate(PostgresChangePayload payload) {
    // Implement comments update logic
    debugPrint(('Comments update: ${payload.eventType}').toString());
  }

  void _handleNotificationsUpdate(PostgresChangePayload payload) {
    // Implement notifications update logic
    debugPrint(('Notifications update: ${payload.eventType}').toString());
  }

  void _handleLikesUpdate(PostgresChangePayload payload) {
    // Implement likes update logic
    debugPrint(('Likes update: ${payload.eventType}').toString());
  }

  // Helper methods
  Future<String> _getFollowingIds(String userId) async {
    final response = await _client
        .from(SupabaseConfig.followsTable)
        .select('following_id')
        .eq('follower_id', userId);

    final ids = response.map((item) => item['following_id']).join(',');
    return ids.isEmpty ? '00000000-0000-0000-0000-000000000000' : ids;
  }

  // Views operations
  Future<void> incrementPostViewsCount(String postId) async {
    try {
      await _client.rpc(
        'increment_post_views_count',
        params: {'post_id': postId},
      );
    } catch (e) {
      debugPrint(
        ('RPC increment_post_views_count failed, applying fallback: $e')
            .toString(),
      );
      try {
        final postRow = await _client
            .from(SupabaseConfig.postsTable)
            .select('views_count')
            .eq('id', postId)
            .maybeSingle();
        final current = (postRow?['views_count'] as int?) ?? 0;
        await _client
            .from(SupabaseConfig.postsTable)
            .update({'views_count': current + 1})
            .eq('id', postId);
      } catch (inner) {
        debugPrint(
          ('Fallback increment views_count failed: $inner').toString(),
        );
      }
    }
  }
}
