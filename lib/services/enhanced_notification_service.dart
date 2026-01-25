import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/notification_model.dart';
import '../services/localization_service.dart';
import 'notification_badge_service.dart';

class EnhancedNotificationService {
  static final EnhancedNotificationService _instance =
      EnhancedNotificationService._internal();
  factory EnhancedNotificationService() => _instance;
  EnhancedNotificationService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;
  final StreamController<NotificationModel> _notificationController =
      StreamController<NotificationModel>.broadcast();
  final StreamController<int> _unreadCountController =
      StreamController<int>.broadcast();

  Stream<NotificationModel> get notificationStream =>
      _notificationController.stream;
  Stream<int> get unreadCountStream => _unreadCountController.stream;

  RealtimeChannel? _notificationChannel;
  int _unreadCount = 0;
  final NotificationBadgeService _badgeService = NotificationBadgeService();

  // Initialize real-time notification listening
  Future<void> initialize() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    // Subscribe to real-time notifications
    _notificationChannel = _supabase
        .channel('notifications:$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) {
            _handleNewNotification(payload.newRecord);
          },
        )
        .subscribe();

    // Load initial unread count
    await _loadUnreadCount();
    // Also sync badge service with initial unread count
    try {
      _badgeService.updateNotificationCount(_unreadCount);
    } catch (_) {}
  }

  // Handle new notification with TikTok-style presentation
  void _handleNewNotification(Map<String, dynamic> data) {
    final notification = NotificationModel.fromJson(data);
    _notificationController.add(notification);

    // Update unread count
    _unreadCount++;
    _unreadCountController.add(_unreadCount);
    // Sync badge service
    try {
      _badgeService.updateNotificationCount(_unreadCount);
    } catch (_) {}

    // Play notification sound
    _playNotificationSound(notification.type);

    // Show in-app notification banner (TikTok style)
    _showInAppNotification(notification);
  }

  // Play different sounds based on notification type (TikTok style)
  void _playNotificationSound(String type) {
    try {
      // No-op: rely on OS-level notification tone via push/local notifications
    } catch (e) {
      debugPrint('Error playing notification sound: $e');
    }
  }

  // Show TikTok-style in-app notification banner
  void _showInAppNotification(NotificationModel notification) {
    // This will be called by the main app to show overlay notifications
    // Implementation will be in the main widget tree
  }

  // Create notification (called when user performs actions)
  Future<void> createNotification({
    required String userId,
    required String type,
    required String title,
    required String message,
    Map<String, dynamic>? data,
  }) async {
    try {
      final actorId = _supabase.auth.currentUser?.id;
      if (actorId == null) {
        debugPrint('Error creating notification: no authenticated actor');
        return;
      }

      // Fetch actor profile to enrich notification (avoid users table join)
      String? actorName;
      String? actorAvatar;
      try {
        Map<String, dynamic>? p;
        // Primary: users
        try {
          p = await _supabase
              .from('users')
              .select('display_name,username,avatar_url')
              .eq('id', actorId)
              .maybeSingle();
        } catch (_) {}
        // Fallback: user_profiles
        if (p == null) {
          try {
            // Deprecated table removed in production; keep users-first, then profiles
            // Leave this block as a no-op to avoid PGRST205
            p = null;
          } catch (_) {}
        }
        // Fallback: profiles
        if (p == null) {
          try {
            p = await _supabase
                .from('profiles')
                .select('display_name,full_name,username,avatar_url')
                .eq('id', actorId)
                .maybeSingle();
          } catch (_) {}
        }
        if (p != null) {
          final displayName = (p['display_name'] as String?)?.trim();
          final fullName = (p['full_name'] as String?)?.trim();
          final username = (p['username'] as String?)?.trim();
          actorName = (displayName != null && displayName.isNotEmpty)
              ? displayName
              : (fullName != null && fullName.isNotEmpty)
              ? fullName
              : username;
          final av = (p['avatar_url'] as String?);
          actorAvatar = (av != null && av.isNotEmpty) ? av : null;
        }
      } catch (e) {
        // Ignore enrichment errors; proceed with minimal notification
        debugPrint('Actor profile enrichment failed: $e');
      }

      final insertPayload = {
        'user_id': userId,
        'type': type,
        'title': title,
        'message': message,
        'data': data,
        'is_read': false,
        // Include actor information to satisfy RLS
        'actor_id': actorId,
      };

      // Perform insert and log for diagnostics
      final res = await _supabase.from('notifications').insert(insertPayload);
      debugPrint(
        'Notification inserted: type=$type, user_id=$userId, actor_id=$actorId, data=${data ?? {}}',
      );
      if (res is Map && res['error'] != null) {
        debugPrint('Notification insert error: ${res['error']}');
      }
    } catch (e) {
      debugPrint('Error creating notification: $e');
    }
  }

  // Create like notification
  Future<void> createLikeNotification({
    required String postOwnerId,
    required String likerName,
    required String postId,
  }) async {
    // Suppress notifications for self-likes
    if (postOwnerId == _supabase.auth.currentUser?.id) return;
    await createNotification(
      userId: postOwnerId,
      type: 'like',
      title: '❤️ ${LocalizationService.t('new_like_title')}',
      message: '$likerName ${LocalizationService.t('liked_your_post')}',
      data: {
        'post_id': postId,
        'liker_id': _supabase.auth.currentUser?.id,
        'action_type': 'like',
      },
    );
  }

  // Create comment notification
  Future<void> createCommentNotification({
    required String postOwnerId,
    required String commenterName,
    required String postId,
    required String commentId,
  }) async {
    if (postOwnerId == _supabase.auth.currentUser?.id)
      return; // Don't notify self

    await createNotification(
      userId: postOwnerId,
      type: 'comment',
      title: '💬 ${LocalizationService.t('new_comment_title')}',
      message:
          '$commenterName ${LocalizationService.t('commented_on_your_post')}',
      data: {
        'post_id': postId,
        'comment_id': commentId,
        'commenter_id': _supabase.auth.currentUser?.id,
        'action_type': 'comment',
      },
    );
  }

  // Create follow notification
  Future<void> createFollowNotification({
    required String followedUserId,
    required String followerName,
  }) async {
    await createNotification(
      userId: followedUserId,
      type: 'follow',
      title: LocalizationService.t('new_tracker_title'),
      message: '$followerName ${LocalizationService.t('started_tracking_you')}',
      data: {
        'follower_id': _supabase.auth.currentUser?.id,
        'action_type': 'follow',
      },
    );
  }

  // Create untrack notification
  Future<void> createUnfollowNotification({
    required String unfollowedUserId,
    required String unfollowerName,
  }) async {
    await createNotification(
      userId: unfollowedUserId,
      type: 'unfollow',
      title: LocalizationService.t('untracked_you_title'),
      message:
          '$unfollowerName ${LocalizationService.t('stopped_tracking_you')}',
      data: {
        'unfollower_id': _supabase.auth.currentUser?.id,
        'action_type': 'unfollow',
      },
    );
  }

  // Create mention notification
  Future<void> createMentionNotification({
    required String mentionedUserId,
    required String mentionerName,
    required String postId,
  }) async {
    if (mentionedUserId == _supabase.auth.currentUser?.id)
      return; // Don't notify self

    // Respect receiver's allow_mentions preference if available
    try {
      final prefs = await _supabase
          .from('users')
          .select('allow_mentions')
          .eq('id', mentionedUserId)
          .maybeSingle();
      if (prefs != null) {
        final allow = prefs['allow_mentions'];
        if (allow is bool && allow == false) {
          return; // Receiver disabled mention notifications
        }
      }
    } catch (_) {
      // If the column doesn't exist or any error occurs, proceed by default
    }

    await createNotification(
      userId: mentionedUserId,
      type: 'mention',
      title: '📢 You were mentioned',
      message: '$mentionerName mentioned you in a post',
      data: {
        'post_id': postId,
        'mentioner_id': _supabase.auth.currentUser?.id,
        'action_type': 'mention',
      },
    );
  }

  // Load notifications with pagination
  Future<List<NotificationModel>> loadNotifications({
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return [];

      // Explicitly select columns to avoid client/version response type issues
      final response = await _supabase
          .from('notifications')
          .select(
            'id,user_id,type,title,message,data,is_read,created_at,actor_id',
          )
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      // Supabase Flutter v2 returns a List<dynamic>
      return response.map((json) => NotificationModel.fromJson(json)).toList();
      // debugPrint('Unexpected notifications response: ${response.runtimeType}');
      // return [];
    } catch (e) {
      debugPrint('Error loading notifications: $e');
      return [];
    }
  }

  // Mark notification as read
  Future<void> markAsRead(String notificationId) async {
    try {
      await _supabase
          .from('notifications')
          .update({'is_read': true})
          .eq('id', notificationId);

      // Update unread count
      if (_unreadCount > 0) {
        _unreadCount--;
        _unreadCountController.add(_unreadCount);
        // Sync badge service
        try {
          _badgeService.updateNotificationCount(_unreadCount);
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('Error marking notification as read: $e');
    }
  }

  // Mark all notifications as read
  Future<void> markAllAsRead() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      await _supabase
          .from('notifications')
          .update({'is_read': true})
          .eq('user_id', userId)
          .eq('is_read', false);

      _unreadCount = 0;
      _unreadCountController.add(_unreadCount);
      // Sync badge service
      try {
        _badgeService.updateNotificationCount(0);
      } catch (_) {}
    } catch (e) {
      debugPrint('Error marking all notifications as read: $e');
    }
  }

  // New: Mark all unread notifications of a specific category as read
  Future<void> markCategoryAsRead(String category) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      // First update: notifications with matching top-level type
      final List<dynamic> updatedByType = await _supabase
          .from('notifications')
          .update({'is_read': true})
          .eq('user_id', userId)
          .eq('is_read', false)
          .eq('type', category)
          .select('id');
      final int affectedType = updatedByType.length;

      // Second update: notifications where category is stored in data->>action_type
      final List<dynamic> updatedByDataType = await _supabase
          .from('notifications')
          .update({'is_read': true})
          .eq('user_id', userId)
          .eq('is_read', false)
          .eq('data->>action_type', category)
          .select('id');
      final int affectedDataType = updatedByDataType.length;

      final int affected = affectedType + affectedDataType;
      if (affected == 0) return;

      // Update unread count and sync badge
      if (_unreadCount > 0) {
        _unreadCount = (_unreadCount - affected);
        if (_unreadCount < 0) _unreadCount = 0;
        _unreadCountController.add(_unreadCount);
        try {
          _badgeService.updateNotificationCount(_unreadCount);
        } catch (_) {}
      }
    } catch (e) {
      debugPrint(
        'Error marking notifications for category "$category" as read: $e',
      );
    }
  }

  // Load unread count
  Future<void> _loadUnreadCount() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      // Align with badge service by selecting only IDs and handling response types
      final response = await _supabase
          .from('notifications')
          .select('id')
          .eq('user_id', userId)
          .eq('is_read', false);

      _unreadCount = response.length;
      _unreadCountController.add(_unreadCount);
      // Sync badge service
      try {
        _badgeService.updateNotificationCount(_unreadCount);
      } catch (_) {}
    } catch (e) {
      debugPrint('Error loading unread count: $e');
    }
  }

  // Get current unread count
  int get unreadCount => _unreadCount;

  // Dispose resources
  void dispose() {
    _notificationChannel?.unsubscribe();
    _notificationController.close();
    _unreadCountController.close();
  }
}

void _playNotificationTone() {
  try {
    // Use OS-level default notification sound via posted notifications; no custom tone here
    // Intentionally left blank to avoid overriding system ringtone
  } catch (e) {
    // No fallback; rely on OS notifications
  }
}
