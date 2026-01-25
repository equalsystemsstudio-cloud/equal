import 'package:timeago/timeago.dart' as timeago;
import '../services/localization_service.dart';

class NotificationModel {
  final String id;
  final String userId;
  final String type;
  final String title;
  final String message;
  final Map<String, dynamic>? data;
  final bool isRead;
  final DateTime createdAt;
  final String? actorId;

  NotificationModel({
    required this.id,
    required this.userId,
    required this.type,
    required this.title,
    required this.message,
    this.data,
    required this.isRead,
    required this.createdAt,
    this.actorId,
  });

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    return NotificationModel(
      id: json['id'] ?? '',
      userId: json['user_id'] ?? '',
      type: json['type'] ?? '',
      title: json['title'] ?? '',
      message: json['message'] ?? '',
      data: json['data'] as Map<String, dynamic>?,
      isRead: json['is_read'] ?? false,
      createdAt: DateTime.parse(
        json['created_at'] ?? DateTime.now().toIso8601String(),
      ),
      actorId: json['actor_id'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'type': type,
      'title': title,
      'message': message,
      'data': data,
      'is_read': isRead,
      'created_at': createdAt.toIso8601String(),
      'actor_id': actorId,
    };
  }

  // Get notification icon based on type (TikTok style)
  String get icon {
    switch (type) {
      case 'like':
        return '❤️';
      case 'comment':
        return '💬';
      case 'follow':
        return '👤';
      case 'unfollow':
        return '🚫';
      case 'mention':
        return '📢';
      case 'message':
        return '💌';
      case 'share':
        return '🔄';
      case 'live':
        return '🔴';
      default:
        return '🔔';
    }
  }

  // Get notification color based on type
  String get colorHex {
    switch (type) {
      case 'like':
        return '#FF3040'; // TikTok red
      case 'comment':
        return '#25D366'; // WhatsApp green
      case 'follow':
        return '#1DA1F2'; // Twitter blue
      case 'unfollow':
        return '#6C7B7F'; // Gray
      case 'mention':
        return '#FF6B35'; // Orange
      case 'message':
        return '#8A2BE2'; // Purple
      case 'live':
        return '#FF3040'; // Red for live
      default:
        return '#6C7B7F'; // Gray
    }
  }

  // Get time ago string (TikTok style)
  String get timeAgo {
    // Use timeago with the currently selected app language for proper localization
    try {
      return timeago.format(
        createdAt,
        locale: LocalizationService.resolveTimeagoLocale(
          LocalizationService.currentLanguage,
        ),
      );
    } catch (_) {
      // Fallback to abbreviated English style
      final now = DateTime.now();
      final difference = now.difference(createdAt);
      if (difference.inDays > 7) {
        return '${(difference.inDays / 7).floor()}w';
      } else if (difference.inDays > 0) {
        return '${difference.inDays}d';
      } else if (difference.inHours > 0) {
        return '${difference.inHours}h';
      } else if (difference.inMinutes > 0) {
        return '${difference.inMinutes}m';
      } else {
        return 'now';
      }
    }
  }

  // Check if notification is recent (for highlighting)
  bool get isRecent {
    final now = DateTime.now();
    final difference = now.difference(createdAt);
    return difference.inMinutes < 5;
  }

  // Get action user ID from data
  String? get actionUserId {
    return data?['sender_id'] ??
        data?['liker_id'] ??
        data?['commenter_id'] ??
        data?['follower_id'] ??
        data?['unfollower_id'] ??
        data?['mentioner_id'] ??
        actorId;
  }

  // Get post ID from data
  String? get postId {
    return data?['post_id'];
  }

  // Get comment ID from data
  String? get commentId {
    return data?['comment_id'];
  }

  // Copy with method for updating properties
  NotificationModel copyWith({
    String? id,
    String? userId,
    String? type,
    String? title,
    String? message,
    Map<String, dynamic>? data,
    bool? isRead,
    DateTime? createdAt,
    String? actorId,
  }) {
    return NotificationModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      type: type ?? this.type,
      title: title ?? this.title,
      message: message ?? this.message,
      data: data ?? this.data,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt ?? this.createdAt,
      actorId: actorId ?? this.actorId,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is NotificationModel && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'NotificationModel(id: $id, type: $type, title: $title, isRead: $isRead)';
  }
}
