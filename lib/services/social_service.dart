import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'database_service.dart';
import 'push_notification_service.dart';
import 'enhanced_notification_service.dart';
import 'preferences_service.dart';
import 'localization_service.dart';
import 'analytics_service.dart';
import 'storage_service.dart';
import 'dart:typed_data';
import 'dart:io';

class SocialService {
  final _supabase = Supabase.instance.client;
  final PushNotificationService _pushNotificationService =
      PushNotificationService();
  final AnalyticsService _analyticsService = AnalyticsService();

  // Follow/Unfollow functionality
  Future<bool> followUser(String userId) async {
    try {
      final currentUser = _supabase.auth.currentUser;
      if (currentUser == null) throw Exception('User not authenticated');

      await _supabase.from('follows').insert({
        'follower_id': currentUser.id,
        'following_id': userId,
        'created_at': DateTime.now().toIso8601String(),
      });

      // Update follower/following counts
      await _updateFollowCounts(currentUser.id, userId, true);

      // Create immediate notification for the followed (tracked) user
      try {
        final followerUsername =
            currentUser.userMetadata?['username'] ?? 'Someone';
        await EnhancedNotificationService().createFollowNotification(
          followedUserId: userId,
          followerName: followerUsername,
        );
      } catch (e) {
        debugPrint('Failed to create follow notification: $e');
      }

      // Track analytics
      try {
        await _analyticsService.trackUserTrack(userId);
      } catch (e) {
        debugPrint('followUser: failed to track analytics: $e');
      }

      return true;
    } catch (e) {
      debugPrint('Error following user: $e');
      return false;
    }
  }

  Future<bool> unfollowUser(String userId) async {
    try {
      final currentUser = _supabase.auth.currentUser;
      if (currentUser == null) throw Exception('User not authenticated');

      await _supabase
          .from('follows')
          .delete()
          .eq('follower_id', currentUser.id)
          .eq('following_id', userId);

      // Update follower/following counts
      await _updateFollowCounts(currentUser.id, userId, false);

      // Track analytics
      try {
        await _analyticsService.trackUserUntrack(userId);
      } catch (e) {
        debugPrint('unfollowUser: failed to track analytics: $e');
      }

      return true;
    } catch (e) {
      debugPrint('Error unfollowing user: $e');
      return false;
    }
  }

  Future<bool> isFollowing(String userId) async {
    try {
      final currentUser = _supabase.auth.currentUser;
      if (currentUser == null) return false;

      final response = await _supabase
          .from('follows')
          .select('id')
          .eq('follower_id', currentUser.id)
          .eq('following_id', userId)
          .maybeSingle();

      return response != null;
    } catch (e) {
      debugPrint('Error checking follow status: $e');
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getFollowers(String userId) async {
    try {
      final response = await _supabase
          .from('follows')
          .select('''
            follower_id,
            created_at,
            profiles!follows_follower_id_fkey(
              id,
              username,
              display_name,  // Fixed: use display_name instead of full_name
              avatar_url,
              bio
            )
          ''')
          .eq('following_id', userId)
          .order('created_at', ascending: false);

      // Flatten nested profiles object to match UI expectations
      final List<dynamic> rows = response as List<dynamic>;
      final users = rows
          .map((row) {
            final profiles = row['profiles'] as Map<String, dynamic>?;
            return {
              'id': profiles?['id'] ?? row['follower_id'],
              'username': profiles?['username'] ?? row['follower_id'],
              'display_name':
                  profiles?['display_name'] ??
                  profiles?['full_name'] ??
                  row['follower_id'],
              'avatar_url': profiles?['avatar_url'],
              'bio': profiles?['bio'],
              'created_at': row['created_at'],
            };
          })
          .where((u) => u['id'] != null)
          .cast<Map<String, dynamic>>()
          .toList();

      return users;
    } catch (e) {
      debugPrint('Error getting followers: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getFollowing(String userId) async {
    try {
      final response = await _supabase
          .from('follows')
          .select('''
            following_id,
            created_at,
            profiles!follows_following_id_fkey(
              id,
              username,
              display_name,  // Fixed: use display_name instead of full_name
              avatar_url,
              bio
            )
          ''')
          .eq('follower_id', userId)
          .order('created_at', ascending: false);

      // Flatten nested profiles object to match UI expectations
      final List<dynamic> rows = response as List<dynamic>;
      final users = rows
          .map((row) {
            final profiles = row['profiles'] as Map<String, dynamic>?;
            return {
              'id': profiles?['id'] ?? row['following_id'],
              'username': profiles?['username'] ?? row['following_id'],
              'display_name':
                  profiles?['display_name'] ??
                  profiles?['full_name'] ??
                  row['following_id'],
              'avatar_url': profiles?['avatar_url'],
              'bio': profiles?['bio'],
              'created_at': row['created_at'],
            };
          })
          .where((u) => u['id'] != null)
          .cast<Map<String, dynamic>>()
          .toList();

      return users;
    } catch (e) {
      debugPrint('Error getting following: $e');
      return [];
    }
  }

  Future<void> _updateFollowCounts(
    String followerId,
    String followingId,
    bool isFollow,
  ) async {
    try {
      if (isFollow) {
        // Increment following count for follower
        await _supabase.rpc(
          'increment_following_count',
          params: {'user_id': followerId},
        );
        // Increment followers count for following
        await _supabase.rpc(
          'increment_followers_count',
          params: {'user_id': followingId},
        );
      } else {
        // Decrement following count for follower
        await _supabase.rpc(
          'decrement_following_count',
          params: {'user_id': followerId},
        );
        // Decrement followers count for following
        await _supabase.rpc(
          'decrement_followers_count',
          params: {'user_id': followingId},
        );
      }
    } catch (e) {
      debugPrint('Error updating follow counts: $e');
    }
  }

  // Like functionality
  Future<bool> likePost(String postId) async {
    try {
      final currentUser = _supabase.auth.currentUser;
      if (currentUser == null) throw Exception('User not authenticated');

      await _supabase.from('likes').insert({
        'user_id': currentUser.id,
        'post_id': postId,
        'created_at': DateTime.now().toIso8601String(),
      });

      // Update like count
      try {
        await _supabase.rpc(
          'increment_post_likes_count',
          params: {'post_id': postId},
        );
      } catch (e) {
        debugPrint(
          'RPC increment_post_likes_count failed, applying fallback: $e',
        );
        try {
          final postRow = await _supabase
              .from('posts')
              .select('likes_count')
              .eq('id', postId)
              .maybeSingle();
          final current = (postRow?['likes_count'] as int?) ?? 0;
          await _supabase
              .from('posts')
              .update({'likes_count': current + 1})
              .eq('id', postId);
        } catch (inner) {
          debugPrint('Fallback increment likes_count failed: $inner');
        }
      }

      // Create like notification for the post owner (if not self-like)
      try {
        final postOwnerRow = await _supabase
            .from('posts')
            .select('user_id')
            .eq('id', postId)
            .maybeSingle();
        final String? postOwnerId = postOwnerRow != null
            ? postOwnerRow['user_id'] as String?
            : null;
        final String userId = _supabase.auth.currentUser!.id;
        if (postOwnerId != null) {
          String likerName = 'Someone';
          try {
            final profile = await _supabase
                .from('users')
                .select('display_name,username')
                .eq('id', userId)
                .maybeSingle();
            if (profile != null) {
              final dp = (profile['display_name'] as String?)?.trim();
              final up = (profile['username'] as String?)?.trim();
              likerName = (dp != null && dp.isNotEmpty)
                  ? dp
                  : (up ?? 'Someone');
            }
          } catch (_) {}

          await EnhancedNotificationService().createLikeNotification(
            postOwnerId: postOwnerId,
            likerName: likerName,
            postId: postId,
          );
        }
      } catch (_) {}
      return true;
    } catch (e) {
      debugPrint('Error liking post: $e');
      return false;
    }
  }

  Future<bool> unlikePost(String postId) async {
    try {
      final currentUser = _supabase.auth.currentUser;
      if (currentUser == null) throw Exception('User not authenticated');

      await _supabase
          .from('likes')
          .delete()
          .eq('user_id', currentUser.id)
          .eq('post_id', postId);

      // Update like count
      try {
        await _supabase.rpc(
          'decrement_post_likes_count',
          params: {'post_id': postId},
        );
      } catch (e) {
        debugPrint(
          'RPC decrement_post_likes_count failed, applying fallback: $e',
        );
        try {
          final postRow = await _supabase
              .from('posts')
              .select('likes_count')
              .eq('id', postId)
              .maybeSingle();
          final current = (postRow?['likes_count'] as int?) ?? 0;
          final newValue = current > 0 ? current - 1 : 0;
          await _supabase
              .from('posts')
              .update({'likes_count': newValue})
              .eq('id', postId);
        } catch (inner) {
          debugPrint('Fallback decrement likes_count failed: $inner');
        }
      }

      return true;
    } catch (e) {
      debugPrint('Error unliking post: $e');
      return false;
    }
  }

  Future<bool> isPostLiked(String postId) async {
    try {
      final currentUser = _supabase.auth.currentUser;
      if (currentUser == null) return false;

      final response = await _supabase
          .from('likes')
          .select('id')
          .eq('user_id', currentUser.id)
          .eq('post_id', postId)
          .maybeSingle();

      return response != null;
    } catch (e) {
      debugPrint('Error checking like status: $e');
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getPostLikes(String postId) async {
    try {
      final response = await _supabase
          .from('likes')
          .select('''
            user_id,
            created_at,
            profiles!likes_user_id_fkey(
              id,
              username,
              display_name,  // Fixed: use display_name instead of full_name
              avatar_url
            )
          ''')
          .eq('post_id', postId)
          .order('created_at', ascending: false);

      // Flatten nested profiles object to match UI expectations
      final List<dynamic> rows = response as List<dynamic>;
      final users = rows
          .map((row) {
            final profiles = row['profiles'] as Map<String, dynamic>?;
            return {
              'id': profiles?['id'] ?? row['user_id'],
              'username': profiles?['username'],
              'display_name':
                  profiles?['display_name'] ?? profiles?['full_name'],
              'avatar_url': profiles?['avatar_url'],
              'created_at': row['created_at'],
            };
          })
          .where((u) => u['id'] != null)
          .cast<Map<String, dynamic>>()
          .toList();

      return users;
    } catch (e) {
      debugPrint('Error getting post likes: $e');
      return [];
    }
  }

  // Comment functionality
  Future<Map<String, dynamic>?> addComment(
    String postId,
    String? text, {
    String? parentId,
    String? audioUrl,
    String? mediaUrl,
  }) async {
    try {
      final currentUser = _supabase.auth.currentUser;
      if (currentUser == null) throw Exception('User not authenticated');

      final response = await DatabaseService().addComment(
        postId: postId,
        userId: currentUser.id,
        text: text,
        parentId: parentId,
        audioUrl: audioUrl,
        mediaUrl: mediaUrl,
      );

      // Track analytics for comment
      try {
        final postRow = await _supabase
            .from('posts')
            .select('media_types')
            .eq('id', postId)
            .maybeSingle();
        String postType = 'unknown';
        final mediaTypes = postRow == null ? null : postRow['media_types'];
        if (mediaTypes is List && mediaTypes.isNotEmpty) {
          postType = mediaTypes.first.toString();
        } else if (mediaTypes is String && mediaTypes.isNotEmpty) {
          postType = mediaTypes;
        } else if (audioUrl != null && audioUrl.isNotEmpty) {
          postType = 'audio';
        } else if (mediaUrl != null && mediaUrl.isNotEmpty) {
          postType = 'image';
        } else if (text != null && text.trim().isNotEmpty) {
          postType = 'text';
        }
        await _analyticsService.trackPostComment(postId, postType);
      } catch (e) {
        debugPrint('addComment: failed to track analytics: $e');
      }

      // Handle mention notifications for comment text
      try {
        final prefs = PreferencesService();
        final allowMentions = await prefs.getAllowMentions();
        if (allowMentions && text != null && text.trim().isNotEmpty) {
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
              final profile = await _supabase
                  .from('users')
                  .select('display_name,username')
                  .eq('id', currentUser.id)
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
                final target = await _supabase
                    .from('users')
                    .select('id')
                    .ilike('username', uname)
                    .maybeSingle();
                final mentionedUserId = target != null
                    ? target['id'] as String?
                    : null;
                if (mentionedUserId != null &&
                    mentionedUserId != currentUser.id) {
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

      return response;
    } catch (e) {
      debugPrint('Error adding comment: $e');
      return null;
    }
  }

  // Send a voice comment from a local audio file path (mobile)
  Future<Map<String, dynamic>?> sendVoiceComment({
    required String postId,
    required String audioPath,
    String? parentId,
    String? text,
  }) async {
    try {
      final currentUser = _supabase.auth.currentUser;
      if (currentUser == null) throw Exception('User not authenticated');

      final file = File(audioPath);
      if (!await file.exists()) {
        throw Exception('Audio file not found at path: ' + audioPath);
      }

      final audioUrl = await StorageService().uploadAudio(
        audioFile: file,
        userId: currentUser.id,
      );

      return await addComment(
        postId,
        text,
        parentId: parentId,
        audioUrl: audioUrl,
      );
    } catch (e) {
      debugPrint('Error sending voice comment: ' + e.toString());
      return null;
    }
  }

  // Send a voice comment from web bytes (web-compatible)
  Future<Map<String, dynamic>?> sendVoiceCommentBytes({
    required String postId,
    required Uint8List audioBytes,
    required String fileName,
    String? parentId,
    String? text,
  }) async {
    try {
      final currentUser = _supabase.auth.currentUser;
      if (currentUser == null) throw Exception('User not authenticated');

      final audioUrl = await StorageService().uploadAudio(
        audioFile: null,
        userId: currentUser.id,
        audioBytes: audioBytes,
        fileName: fileName,
      );

      return await addComment(
        postId,
        text,
        parentId: parentId,
        audioUrl: audioUrl,
      );
    } catch (e) {
      debugPrint('Error sending voice comment (bytes): ' + e.toString());
      return null;
    }
  }

  // Updated API: single-argument deleteComment as used by UI
  Future<bool> deleteComment(String commentId) async {
    try {
      final currentUser = _supabase.auth.currentUser;
      if (currentUser == null) throw Exception('User not authenticated');
      await DatabaseService().deleteComment(commentId, currentUser.id);
      return true;
    } catch (e) {
      debugPrint('Error deleting comment: $e');
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getPostComments(String postId) async {
    try {
      final response = await _supabase
          .from('comments')
          .select('''
            id,
            content,
            created_at,
            profiles!comments_user_id_fkey(
              id,
              username,
              display_name,  // Fixed: use display_name instead of full_name
              avatar_url
            )
          ''')
          .eq('post_id', postId)
          .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Error getting post comments: $e');
      return [];
    }
  }

  // New API expected by UI: getComments(postId)
  Future<List<Map<String, dynamic>>> getComments(String postId) async {
    try {
      return await DatabaseService().getComments(postId: postId);
    } catch (e) {
      debugPrint('Error getting comments: $e');
      return [];
    }
  }

  // New APIs for liking comments
  Future<bool> likeComment(String commentId) async {
    try {
      final currentUser = _supabase.auth.currentUser;
      if (currentUser == null) throw Exception('User not authenticated');
      await DatabaseService().likeComment(commentId, currentUser.id);
      return true;
    } catch (e) {
      debugPrint('Error liking comment: $e');
      return false;
    }
  }

  Future<bool> unlikeComment(String commentId) async {
    try {
      final currentUser = _supabase.auth.currentUser;
      if (currentUser == null) throw Exception('User not authenticated');
      await DatabaseService().unlikeComment(commentId, currentUser.id);
      return true;
    } catch (e) {
      debugPrint('Error unliking comment: $e');
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getReplies(String commentId) async {
    try {
      return await DatabaseService().getReplies(commentId: commentId);
    } catch (e) {
      debugPrint('Error getting replies: $e');
      return [];
    }
  }

  Future<int> getTotalCommentCount(String postId) async {
    try {
      return await DatabaseService().getTotalCommentCount(postId);
    } catch (e) {
      debugPrint('Error getting total comment count: $e');
      return 0;
    }
  }

  // Share functionality
  Future<bool> sharePost(String postId) async {
    try {
      final currentUser = _supabase.auth.currentUser;
      if (currentUser == null) throw Exception('User not authenticated');

      await _supabase.from('shares').insert({
        'user_id': currentUser.id,
        'post_id': postId,
        'created_at': DateTime.now().toIso8601String(),
      });

      return true;
    } catch (e) {
      debugPrint('Error sharing post: $e');
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getPostShares(String postId) async {
    try {
      final response = await _supabase
          .from('shares')
          .select('''
            user_id,
            created_at,
            profiles!shares_user_id_fkey(
              id,
              username,
              display_name,  // Fixed: use display_name instead of full_name
              avatar_url
            )
          ''')
          .eq('post_id', postId)
          .order('created_at', ascending: false);

      // Flatten nested profiles object to match UI expectations
      final List<dynamic> rows = response as List<dynamic>;
      final users = rows
          .map((row) {
            final profiles = row['profiles'] as Map<String, dynamic>?;
            return {
              'id': profiles?['id'] ?? row['user_id'],
              'username': profiles?['username'],
              'display_name':
                  profiles?['display_name'] ?? profiles?['full_name'],
              'avatar_url': profiles?['avatar_url'],
              'created_at': row['created_at'],
            };
          })
          .where((u) => u['id'] != null)
          .cast<Map<String, dynamic>>()
          .toList();

      return users;
    } catch (e) {
      debugPrint('Error getting post shares: $e');
      return [];
    }
  }

  // Notifications
  Future<bool> createNotification(
    String userId,
    String type,
    Map<String, dynamic> data,
  ) async {
    try {
      // Determine actor name for message/title enrichment
      final currentUser = _supabase.auth.currentUser;
      final actorUsername =
          (data['username'] as String?) ??
          currentUser?.userMetadata?['username'] ??
          'Someone';

      // Build title and message consistent with EnhancedNotificationService
      String title = 'Equal';
      String message = 'You have a new notification';
      switch (type) {
        case 'like':
          title = '❤️ ${LocalizationService.t('new_like_title')}';
          message =
              '$actorUsername ${LocalizationService.t('liked_your_post')}';
          break;
        case 'comment':
          title = '💬 ${LocalizationService.t('new_comment_title')}';
          message =
              '$actorUsername ${LocalizationService.t('commented_on_your_post')}';
          break;
        case 'follow':
          title = LocalizationService.t('new_tracker_title');
          message =
              '$actorUsername ${LocalizationService.t('started_tracking_you')}';
          break;
        case 'message':
          title = '✉️ ${LocalizationService.t('new_message_title')}';
          message =
              '$actorUsername ${LocalizationService.t('sent_you_a_message')}';
          break;
        case 'mention':
          title = '📢 You were mentioned';
          message = '$actorUsername mentioned you in a post';
          break;
        case 'share':
          title = '🔗 Post Shared';
          message = '$actorUsername shared your post';
          break;
        case 'live':
          title = '🔴 Live Now';
          message = '$actorUsername went live';
          break;
        default:
          title = 'Equal';
          message = 'You have a new notification';
      }

      // Delegate creation to EnhancedNotificationService to ensure unified schema
      await EnhancedNotificationService().createNotification(
        userId: userId,
        type: type,
        title: title,
        message: message,
        data: data,
      );

      // Send push notification for mobile devices
      await _sendPushNotification(userId, type, {
        ...data,
        'title': title,
        'message': message,
      });

      return true;
    } catch (e) {
      debugPrint('Error creating notification: $e');
      return false;
    }
  }

  // Send push notification based on notification type
  Future<void> _sendPushNotification(
    String userId,
    String type,
    Map<String, dynamic> data,
  ) async {
    try {
      String title = data['title'] ?? 'Equal';
      String body = data['message'] ?? 'You have a new notification';

      // Backward compatibility if title/message not provided
      if (data['title'] == null || data['message'] == null) {
        final username = data['username'] ?? 'Someone';
        switch (type) {
          case 'like':
            title = LocalizationService.t('new_like_title');
            body = '$username ${LocalizationService.t('liked_your_post')}';
            break;
          case 'comment':
            title = LocalizationService.t('new_comment_title');
            body =
                '$username ${LocalizationService.t('commented_on_your_post')}';
            break;
          case 'follow':
            title = LocalizationService.t('new_tracker_title');
            body = '$username ${LocalizationService.t('started_tracking_you')}';
            break;
          case 'message':
            title = LocalizationService.t('new_message_title');
            body = '$username ${LocalizationService.t('sent_you_a_message')}';
            break;
          case 'live':
            title = 'Live Now';
            body = '$username went live';
            break;
          default:
            title = 'Equal';
            body = 'You have a new notification';
        }
      }

      await _pushNotificationService.sendNotificationToUser(
        userId: userId,
        title: title,
        body: body,
        type: type,
        data: data,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error sending push notification: $e');
      }
    }
  }

  Future<List<Map<String, dynamic>>> getNotifications() async {
    try {
      final currentUser = _supabase.auth.currentUser;
      if (currentUser == null) throw Exception('User not authenticated');

      final response = await _supabase
          .from('notifications')
          .select(
            'id,user_id,type,title,message,data,is_read,created_at,actor_id',
          )
          .eq('user_id', currentUser.id)
          .order('created_at', ascending: false)
          .limit(50);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Error getting notifications: $e');
      return [];
    }
  }

  Future<bool> markNotificationAsRead(String notificationId) async {
    try {
      await _supabase
          .from('notifications')
          .update({'is_read': true})
          .eq('id', notificationId);
      return true;
    } catch (e) {
      debugPrint('Error marking notification as read: $e');
      return false;
    }
  }

  Future<bool> markAllNotificationsAsRead() async {
    try {
      final currentUser = _supabase.auth.currentUser;
      if (currentUser == null) throw Exception('User not authenticated');

      await _supabase
          .from('notifications')
          .update({'is_read': true})
          .eq('user_id', currentUser.id)
          .eq('is_read', false);
      return true;
    } catch (e) {
      debugPrint('Error marking all notifications as read: $e');
      return false;
    }
  }

  Future<int> getUnreadNotificationCount() async {
    try {
      final currentUser = _supabase.auth.currentUser;
      if (currentUser == null) throw Exception('User not authenticated');

      final response = await _supabase
          .from('notifications')
          .select('id')
          .eq('user_id', currentUser.id)
          .eq('is_read', false);

      return response.length;
    } catch (e) {
      debugPrint('Error getting unread notification count: $e');
      return 0;
    }
  }

  // Block/Report
  Future<bool> blockUser(String userId) async {
    try {
      final currentUser = _supabase.auth.currentUser;
      if (currentUser == null) throw Exception('User not authenticated');

      await _supabase.from('blocks').insert({
        'blocker_id': currentUser.id,
        'blocked_id': userId,
        'created_at': DateTime.now().toIso8601String(),
      });
      return true;
    } catch (e) {
      debugPrint('Error blocking user: $e');
      return false;
    }
  }

  Future<bool> reportContent(String contentId, String reason) async {
    try {
      final currentUser = _supabase.auth.currentUser;
      if (currentUser == null) throw Exception('User not authenticated');

      await _supabase.from('reports').insert({
        'content_id': contentId,
        'user_id': currentUser.id,
        'reason': reason,
        'created_at': DateTime.now().toIso8601String(),
      });
      return true;
    } catch (e) {
      debugPrint('Error reporting content: $e');
      return false;
    }
  }

  // Search
  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    try {
      final response = await _supabase
          .from('users')
          .select(
            'id, username, display_name, avatar_url',
          ) // Fixed: use display_name instead of full_name
          .ilike('username', '%$query%')
          .limit(20);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Error searching users: $e');
      return [];
    }
  }

  // Resolve a username (without @) to a userId, checking profiles first then users
  Future<String?> getUserIdByUsername(String username) async {
    try {
      // Normalize input (strip leading @, trim whitespace)
      final raw = username;
      final uname = raw.startsWith('@') ? raw.substring(1) : raw;
      final norm = uname.trim();
      if (norm.isEmpty) return null;

      // 1) Exact (case-insensitive) match in users first (primary source)
      final userExact = await _supabase
          .from('users')
          .select('id')
          .ilike('username', norm)
          .maybeSingle();
      if (userExact != null) {
        return userExact['id'] as String?;
      }

      // 2) Exact (case-insensitive) match in profiles
      final profileExact = await _supabase
          .from('profiles')
          .select('id')
          .ilike('username', norm)
          .maybeSingle();
      if (profileExact != null) {
        return profileExact['id'] as String?;
      }

      // 3) Partial (case-insensitive) match in users
      final usersPartial = await _supabase
          .from('users')
          .select('id, username')
          .ilike('username', '%$norm%')
          .limit(5);
      if (usersPartial.isNotEmpty) {
        // Try to pick an exact case-insensitive match first, else fallback to first result
        final exact = usersPartial.firstWhere(
          (e) =>
              (e['username'] as String?)?.toLowerCase() == norm.toLowerCase(),
          orElse: () => usersPartial.first,
        );
        return exact['id'] as String?;
      }

      // 4) Partial (case-insensitive) match in profiles
      final profilesPartial = await _supabase
          .from('profiles')
          .select('id, username')
          .ilike('username', '%$norm%')
          .limit(5);
      if (profilesPartial.isNotEmpty) {
        final exact = profilesPartial.firstWhere(
          (e) =>
              (e['username'] as String?)?.toLowerCase() == norm.toLowerCase(),
          orElse: () => profilesPartial.first,
        );
        return exact['id'] as String?;
      }

      // 5) Final fallback: match by display_name in users (sometimes people are referenced by name)
      final displayFallback = await _supabase
          .from('users')
          .select('id, display_name, username')
          .ilike('display_name', '%$norm%')
          .limit(1);
      if (displayFallback.isNotEmpty) {
        return displayFallback.first['id'] as String?;
      }

      return null;
    } catch (e) {
      debugPrint('Error resolving user by username: $e');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> searchPosts(String query) async {
    try {
      final currentUser = _supabase.auth.currentUser;

      var queryBuilder = _supabase.from('posts').select('''
            id,
            user_id,
            content,
            media_url,
            created_at,
            likes_count,
            comments_count,
            views_count,
            user:users!posts_user_id_fkey(id, username, avatar_url)
          ''');

      if (currentUser != null) {
        final followingIds = await _getFollowingIds(currentUser.id);
        final userIds = [currentUser.id, ...followingIds];
        final idsList = userIds.map((id) => id.replaceAll(',', '')).toList();
        final idsOrClause = idsList.isEmpty
            ? 'is_public.eq.true'
            : 'is_public.eq.true,user_id.in.(${idsList.join(',')})';
        queryBuilder = queryBuilder.or(idsOrClause);
      } else {
        queryBuilder = queryBuilder.eq('is_public', true);
      }

      final response = await queryBuilder
          .ilike('content', '%$query%')
          .order('created_at', ascending: false)
          .limit(20);

      final results = List<Map<String, dynamic>>.from(response as List);

      // Flatten joined user info for PostCard compatibility
      for (final row in results) {
        final user = row['user'] as Map<String, dynamic>?;
        row['username'] = user != null ? user['username'] : row['username'];
        row['user_avatar'] = user != null
            ? user['avatar_url']
            : row['user_avatar'];
      }

      return results;
    } catch (e) {
      debugPrint('Error searching posts: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> searchHashtags(String query) async {
    try {
      final currentUser = _supabase.auth.currentUser;

      var queryBuilder = _supabase.from('posts').select('content');

      if (currentUser != null) {
        final followingIds = await _getFollowingIds(currentUser.id);
        final userIds = [currentUser.id, ...followingIds];
        final idsList = userIds.map((id) => id.replaceAll(',', '')).toList();
        final idsOrClause = idsList.isEmpty
            ? 'is_public.eq.true'
            : 'is_public.eq.true,user_id.in.(${idsList.join(',')})';
        queryBuilder = queryBuilder.or(idsOrClause);
      } else {
        queryBuilder = queryBuilder.eq('is_public', true);
      }

      // Search for hashtags in posts content
      final response = await queryBuilder
          .ilike('content', '%#$query%')
          .limit(50);

      // Extract hashtags from posts and count occurrences
      final hashtagCounts = <String, int>{};
      final posts = List<Map<String, dynamic>>.from(response);

      for (final post in posts) {
        final content = post['content'] as String? ?? '';
        final hashtags = RegExp(r'#\w+').allMatches(content);

        for (final match in hashtags) {
          final hashtag = match.group(0)?.toLowerCase();
          if (hashtag != null && hashtag.contains(query.toLowerCase())) {
            hashtagCounts[hashtag] = (hashtagCounts[hashtag] ?? 0) + 1;
          }
        }
      }

      // Convert to list and sort by count
      final results = hashtagCounts.entries
          .map(
            (entry) => {
              'tag': entry.key,
              'post_count': entry.value,
              'is_trending': entry.value > 5,
            },
          )
          .toList();

      results.sort(
        (a, b) => (b['post_count'] as int).compareTo(a['post_count'] as int),
      );

      return results.take(20).toList();
    } catch (e) {
      debugPrint('Error searching hashtags: $e');
      return [];
    }
  }

  // Trending
  Future<List<Map<String, dynamic>>> getTrendingPosts() async {
    try {
      final currentUser = _supabase.auth.currentUser;

      // Consider posts from the last 7 days for trending
      final sevenDaysAgo = DateTime.now()
          .subtract(const Duration(days: 7))
          .toIso8601String();

      var queryBuilder = _supabase.from('posts').select('''
            id,
            user_id,
            content,
            media_url,
            created_at,
            likes_count,
            comments_count,
            views_count,
            user:users!posts_user_id_fkey(id, username, avatar_url)
          ''');

      if (currentUser != null) {
        final followingIds = await _getFollowingIds(currentUser.id);
        final userIds = [currentUser.id, ...followingIds];
        final idsList = userIds.map((id) => id.replaceAll(',', '')).toList();
        final idsOrClause = idsList.isEmpty
            ? 'is_public.eq.true'
            : 'is_public.eq.true,user_id.in.(${idsList.join(',')})';
        queryBuilder = queryBuilder.or(idsOrClause);
      } else {
        queryBuilder = queryBuilder.eq('is_public', true);
      }

      final response = await queryBuilder
          .gte('created_at', sevenDaysAgo)
          .order('likes_count', ascending: false)
          .limit(20);

      final results = List<Map<String, dynamic>>.from(response as List);

      // Flatten joined user info for PostCard compatibility
      for (final row in results) {
        final user = row['user'] as Map<String, dynamic>?;
        row['username'] = user != null ? user['username'] : row['username'];
        row['user_avatar'] = user != null
            ? user['avatar_url']
            : row['user_avatar'];
      }

      return results;
    } catch (e) {
      debugPrint('Error getting trending posts: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getSuggestedUsers({int limit = 10}) async {
    try {
      final currentUser = _supabase.auth.currentUser;
      if (currentUser == null) throw Exception('User not authenticated');

      final response = await _supabase
          .from('users')
          .select(
            'id, username, display_name, avatar_url, bio, followers_count',
          ) // Fixed: use display_name instead of full_name
          .neq('id', currentUser.id)
          .order('followers_count', ascending: false)
          .limit(limit);

      final users = List<Map<String, dynamic>>.from(response);

      // Check following status
      final followingIds = await _getFollowingIds(currentUser.id);
      for (var user in users) {
        user['is_following'] = followingIds.contains(user['id']);
      }

      return users;
    } catch (e) {
      debugPrint('Error getting suggested users: $e');
      return [];
    }
  }
}

// Helper: Get IDs of users the current user is following
Future<List<String>> _getFollowingIds(String userId) async {
  try {
    final client = Supabase.instance.client;
    final response = await client
        .from('follows')
        .select('following_id')
        .eq('follower_id', userId);

    return List<Map<String, dynamic>>.from(
      response as List,
    ).map((item) => item['following_id'] as String).toList();
  } catch (e) {
    debugPrint('Error fetching following IDs: $e');
    return [];
  }
}
