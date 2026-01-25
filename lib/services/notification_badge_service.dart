import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/notification_model.dart';
import 'push_notification_service.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';

class NotificationBadgeService {
  static final NotificationBadgeService _instance = NotificationBadgeService._internal();
  factory NotificationBadgeService() => _instance;
  NotificationBadgeService._internal();

  final _supabase = Supabase.instance.client;

  final PushNotificationService _pushService = PushNotificationService();
  
  // Stream controllers for badge counts
  final _notificationBadgeController = StreamController<int>.broadcast();
  final _messageBadgeController = StreamController<int>.broadcast();
  final _totalBadgeController = StreamController<int>.broadcast();
  // New: Effective notification badge controller for "new since seen" counts
  final _effectiveNotificationBadgeController = StreamController<int>.broadcast();
  
  // Current badge counts
  int _notificationCount = 0;
  int _messageCount = 0;
  // New: Baseline of notifications seen during current session
  int _seenNotificationCount = 0;
  
  // Track the user that current realtime subscriptions belong to
  String? _subscribedUserId;

  // Auth listener to react to sign-in/sign-out across the app
  StreamSubscription<AuthState>? _authSubscription;

  // Realtime subscriptions
  RealtimeChannel? _notificationChannel;
  RealtimeChannel? _messageChannel;
  
  // Getters for streams
  Stream<int> get notificationBadgeStream => _notificationBadgeController.stream;
  Stream<int> get messageBadgeStream => _messageBadgeController.stream;
  Stream<int> get totalBadgeStream => _totalBadgeController.stream;
  // New: Stream for Activity icon to only show new notifications since last seen
  Stream<int> get effectiveNotificationBadgeStream => _effectiveNotificationBadgeController.stream;
  
  // Getters for current counts
  int get notificationCount => _notificationCount;
  int get messageCount => _messageCount;
  int get totalCount => _notificationCount + _messageCount;
  // New: computed effective count
  int get effectiveNotificationCount => (_notificationCount - _seenNotificationCount).clamp(0, double.infinity).toInt();

  // Initialize the service
  Future<void> initialize() async {
    try {
      await _pushService.initialize();

      // Attach auth listener once so we react to sign-in/sign-out and reinitialize subscriptions accordingly
      _attachAuthListenerIfNeeded();

      // Add debug logs to trace initialization and current user context
      final userId = _supabase.auth.currentUser?.id;
      debugPrint('NotificationBadgeService.initialize: currentUserId=$userId, subscribedUserId=$_subscribedUserId');

      // Handle unauthenticated state: clear and unsubscribe
      if (userId == null) {
        _unsubscribeRealtimeSubscriptions();
        _subscribedUserId = null;
        _notificationCount = 0;
        _messageCount = 0;
        _seenNotificationCount = 0; // Reset baseline when unauthenticated
        _notificationBadgeController.add(_notificationCount);
        _messageBadgeController.add(_messageCount);
        _totalBadgeController.add(totalCount);
        _effectiveNotificationBadgeController.add(effectiveNotificationCount);
        debugPrint('NotificationBadgeService: No authenticated user, badges set to 0 and subscriptions cleared.');
        return;
      }

      // If switching users, unsubscribe previous channels and reset counts to avoid carry-over
      if (_subscribedUserId != null && _subscribedUserId != userId) {
        debugPrint('NotificationBadgeService: Detected user switch from $_subscribedUserId to $userId. Unsubscribing previous channels and resetting counts.');
        _unsubscribeRealtimeSubscriptions();
        _notificationCount = 0;
        _messageCount = 0;
        _seenNotificationCount = 0; // Reset baseline on user switch
        _notificationBadgeController.add(_notificationCount);
        _messageBadgeController.add(_messageCount);
        _totalBadgeController.add(totalCount);
        _effectiveNotificationBadgeController.add(effectiveNotificationCount);
      }

      _subscribedUserId = userId;

      await _loadInitialCounts();
      debugPrint('NotificationBadgeService: Initial counts loaded -> notifications=$_notificationCount, messages=$_messageCount, total=$totalCount');

      // After loading counts on sign-in, set baseline to current unread so Activity shows only fresh new items
      _seenNotificationCount = _notificationCount;
      _effectiveNotificationBadgeController.add(effectiveNotificationCount);

      // Ensure previous channels are cleared before creating new ones
      _unsubscribeRealtimeSubscriptions();

      await _setupRealtimeSubscriptions();
      debugPrint('NotificationBadgeService: Realtime subscriptions set up for user $_subscribedUserId');
      debugPrint('Notification badge service initialized');
    } catch (e) {
      debugPrint('Error initializing notification badge service: $e');
    }
  }

  // Ensure we listen to Supabase auth state changes only once
  void _attachAuthListenerIfNeeded() {
    try {
      if (_authSubscription != null) return;
      _authSubscription = _supabase.auth.onAuthStateChange.listen((authState) {
        final event = authState.event;
        final currId = _supabase.auth.currentUser?.id;
        debugPrint('NotificationBadgeService: Auth state changed -> event=$event currentUserId=$currId subscribedUserId=$_subscribedUserId');
        if (event == AuthChangeEvent.signedIn) {
          // Reinitialize subscriptions and counts for the new user
          initialize();
        } else if (event == AuthChangeEvent.signedOut) {
          // Clear counts and subscriptions on sign-out
          _unsubscribeRealtimeSubscriptions();
          _subscribedUserId = null;
          _notificationCount = 0;
          _messageCount = 0;
          _seenNotificationCount = 0; // Reset baseline on sign-out
          _notificationBadgeController.add(_notificationCount);
          _messageBadgeController.add(_messageCount);
          _totalBadgeController.add(totalCount);
          _effectiveNotificationBadgeController.add(effectiveNotificationCount);
          debugPrint('NotificationBadgeService: Signed out -> cleared counts and unsubscribed channels');
        }
      });
      debugPrint('NotificationBadgeService: Auth listener attached');
    } catch (e) {
      debugPrint('NotificationBadgeService: Failed to attach auth listener: $e');
    }
  }

  // Helper to unsubscribe existing realtime channels
  void _unsubscribeRealtimeSubscriptions() {
    try {
      if (_notificationChannel != null) {
        debugPrint('NotificationBadgeService: Unsubscribing notification channel');
        _notificationChannel?.unsubscribe();
        _notificationChannel = null;
      }
      if (_messageChannel != null) {
        debugPrint('NotificationBadgeService: Unsubscribing message channel');
        _messageChannel?.unsubscribe();
        _messageChannel = null;
      }
    } catch (e) {
      debugPrint('NotificationBadgeService: Error unsubscribing channels: $e');
    }
  }

  // Setup realtime subscriptions for badge updates
  Future<void> _setupRealtimeSubscriptions() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        // No subscriptions when unauthenticated
        debugPrint('NotificationBadgeService: Skipping realtime setup, user unauthenticated');
        return;
      }

      debugPrint('NotificationBadgeService: Subscribing to notifications and messages for user $userId');

      // Subscribe to notifications changes (unique channel per user)
      _notificationChannel = _supabase
          .channel('notification_badges_$userId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'notifications',
            callback: (payload) {
              try {
                final newRec = _asMap(payload.newRecord);
                final oldRec = _asMap(payload.oldRecord);
                final String? newUserId = payload.eventType == PostgresChangeEvent.delete ? null : _asString(newRec?['user_id']);
                final String? oldUserId = payload.eventType == PostgresChangeEvent.insert ? null : _asString(oldRec?['user_id']);
                if (newUserId == userId || oldUserId == userId) {
                  _handleNotificationChange(payload);
                } else {
                  debugPrint('NotificationBadgeService: Ignored notification change for another user');
                }
              } catch (e) {
                debugPrint('NotificationBadgeService: Error in notification callback: $e');
              }
            },
          )
          .subscribe();

      // Subscribe to messages changes (unique channel per user)
      _messageChannel = _supabase
          .channel('message_badges_$userId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'messages',
            callback: (payload) {
              try {
                final newRec = _asMap(payload.newRecord);
                final oldRec = _asMap(payload.oldRecord);
                debugPrint('NotificationBadgeService: Received message change event -> type=${payload.eventType}, new=${newRec?['id']}, old=${oldRec?['id']}');
                _handleMessageChange(payload, userId);
              } catch (e) {
                debugPrint('NotificationBadgeService: Error in message callback: $e');
              }
            },
          )
          .subscribe();

      debugPrint('NotificationBadgeService: Subscriptions active for user $userId.');
    } catch (e) {
      debugPrint('Error setting up realtime subscriptions: $e');
    }
  }

  // Load initial badge counts
  Future<void> _loadInitialCounts() async {
    await loadInitialCounts();
  }

  // Public method to reload badge counts
  Future<void> loadInitialCounts() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        // Ensure zero badge counts when unauthenticated
        _notificationCount = 0;
        _messageCount = 0;
        _notificationBadgeController.add(_notificationCount);
        _messageBadgeController.add(_messageCount);
        _totalBadgeController.add(totalCount);
        _effectiveNotificationBadgeController.add(effectiveNotificationCount);
        return;
      }
  
      // Load unread notifications count
      final notificationResponse = await _supabase
          .from('notifications')
          .select('id')
          .eq('user_id', userId)
          .eq('is_read', false);
      _notificationCount = (notificationResponse as List).length;
      _notificationBadgeController.add(_notificationCount);
  
      // Load unread messages count
      final messageResponse = await _supabase
          .from('messages')
          .select('''
            id,
            conversation:conversation_id(
              participant_1_id,
              participant_2_id
            )
          ''')
          .eq('is_read', false)
          .neq('sender_id', userId);
  
      // Filter messages from conversations where user is a participant
      final userMessages = (messageResponse as List).where((message) {
        final conversation = message['conversation'];
        return conversation != null && (
          conversation['participant_1_id'] == userId ||
          conversation['participant_2_id'] == userId
        );
      }).toList();
  
      _messageCount = userMessages.length;
      _messageBadgeController.add(_messageCount);
      _totalBadgeController.add(totalCount);
    } catch (e) {
      debugPrint('Error loading initial badge counts: $e');
    }
  }

  // Handle message changes
  void _handleMessageChange(PostgresChangePayload payload, String userId) {
    try {
      final eventType = payload.eventType;
      final newRecord = _asMap(payload.newRecord) ?? const {};
      final oldRecord = _asMap(payload.oldRecord) ?? const {};

      // Always use the current auth user if available, fallback to subscription-time userId
      final effectiveUserId = _supabase.auth.currentUser?.id ?? userId;

      switch (eventType) {
        case PostgresChangeEvent.insert:
          final senderId = _asString(newRecord['sender_id']);
          final isRead = _asBool(newRecord['is_read']);
          final conversationId = _asString(newRecord['conversation_id']);
          if (senderId != null && senderId != effectiveUserId && !isRead && conversationId != null) {
            debugPrint('NotificationBadgeService: INSERT message id=${newRecord['id']} conv=$conversationId sender=$senderId is_read=$isRead -> checking conversation ownership');
            _checkMessageInUserConversation(conversationId).then((isUserConversation) {
              debugPrint('NotificationBadgeService: Conversation ownership check for $conversationId -> $isUserConversation');
              if (isUserConversation) {
                _messageCount++;
                try { _messageBadgeController.add(_messageCount); } catch (_) {}
                try { _totalBadgeController.add(totalCount); } catch (_) {}
                debugPrint('NotificationBadgeService: Message badge incremented -> messages=$_messageCount total=$totalCount');
                _showLocalMessageNotification(newRecord);
                _playMessageSound();
                _triggerHapticFeedback();
              } else {
                debugPrint('NotificationBadgeService: Skipping badge increment; message not in user conversation');
              }
            });
          } else {
            debugPrint('NotificationBadgeService: INSERT ignored (missing IDs, sender is current user or already read) -> sender_id=$senderId effectiveUserId=$effectiveUserId is_read=$isRead');
          }
          break;

        case PostgresChangeEvent.update:
          final senderId = _asString(newRecord['sender_id']);
          final conversationId = _asString(newRecord['conversation_id']);
          if (senderId != null && senderId != effectiveUserId && conversationId != null) {
            final wasUnread = !_asBool(oldRecord['is_read']);
            final isUnread = !_asBool(newRecord['is_read']);
            debugPrint('NotificationBadgeService: UPDATE message id=${newRecord['id']} wasUnread=$wasUnread isUnread=$isUnread');
            if (wasUnread && !isUnread) {
              _checkMessageInUserConversation(conversationId).then((isUserConversation) {
                debugPrint('NotificationBadgeService: UPDATE ownership check for $conversationId -> $isUserConversation');
                if (isUserConversation) {
                  _messageCount = (_messageCount - 1).clamp(0, double.infinity).toInt();
                  try { _messageBadgeController.add(_messageCount); } catch (_) {}
                  try { _totalBadgeController.add(totalCount); } catch (_) {}
                  debugPrint('NotificationBadgeService: Message badge decremented -> messages=$_messageCount total=$totalCount');
                } else {
                  debugPrint('NotificationBadgeService: Skipping badge decrement; message not in user conversation');
                }
              });
            }
          }
          break;

        case PostgresChangeEvent.delete:
          final senderId = _asString(oldRecord['sender_id']);
          final isReadOld = _asBool(oldRecord['is_read']);
          final conversationId = _asString(oldRecord['conversation_id']);
          if (senderId != null && senderId != effectiveUserId && !isReadOld && conversationId != null) {
            debugPrint('NotificationBadgeService: DELETE message id=${oldRecord['id']} conv=$conversationId -> checking ownership');
            _checkMessageInUserConversation(conversationId).then((isUserConversation) {
              debugPrint('NotificationBadgeService: DELETE ownership check for $conversationId -> $isUserConversation');
              if (isUserConversation) {
                _messageCount = (_messageCount - 1).clamp(0, double.infinity).toInt();
                try { _messageBadgeController.add(_messageCount); } catch (_) {}
                try { _totalBadgeController.add(totalCount); } catch (_) {}
                debugPrint('NotificationBadgeService: Message badge decremented (delete) -> messages=$_messageCount total=$totalCount');
              } else {
                debugPrint('NotificationBadgeService: Skipping badge decrement (delete); message not in user conversation');
              }
            });
          }
          break;
        default:
          break;
      }
    } catch (e) {
      debugPrint('Error handling message change: $e');
    }
  }

  // Handle notification changes
  void _handleNotificationChange(PostgresChangePayload payload) {
    try {
      final eventType = payload.eventType;
      final newRecord = _asMap(payload.newRecord) ?? const {};
      final oldRecord = _asMap(payload.oldRecord) ?? const {};

      switch (eventType) {
        case PostgresChangeEvent.insert:
          final isUnread = !_asBool(newRecord['is_read']);
          if (isUnread) {
            _notificationCount++;
            _showLocalNotification(newRecord);
            _playNotificationTone();
            _triggerHapticFeedback();
          }
          break;
        case PostgresChangeEvent.update:
          final wasUnread = !_asBool(oldRecord['is_read']);
          final isUnread = !_asBool(newRecord['is_read']);
          if (wasUnread && !isUnread) {
            _notificationCount = (_notificationCount - 1).clamp(0, double.infinity).toInt();
          } else if (!wasUnread && isUnread) {
            _notificationCount++;
          }
          break;
        case PostgresChangeEvent.delete:
          final wasUnread = !_asBool(oldRecord['is_read']);
          if (wasUnread) {
            _notificationCount = (_notificationCount - 1).clamp(0, double.infinity).toInt();
          }
          break;
        default:
          break;
      }
      try { _notificationBadgeController.add(_notificationCount); } catch (_) {}
      try { _effectiveNotificationBadgeController.add(effectiveNotificationCount); } catch (_) {}
      try { _totalBadgeController.add(totalCount); } catch (_) {}
    } catch (e) {
      debugPrint('Error handling notification change: $e');
    }
  }

  // Check if message is in a conversation with the current user
  Future<bool> _checkMessageInUserConversation(String conversationId) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return false;
      debugPrint('NotificationBadgeService: Checking conversation ownership for user=$userId conversationId=$conversationId');
      final response = await _supabase
          .from('conversations')
          .select('id')
          .eq('id', conversationId)
          .or('participant_1_id.eq.$userId,participant_2_id.eq.$userId')
          .maybeSingle();
      final isOwner = response != null;
      debugPrint('NotificationBadgeService: Ownership check result -> $isOwner');
      return isOwner;
    } catch (e) {
      debugPrint('Error checking message conversation: $e');
      return false;
    }
  }

  // Safe parsing helpers to defend against unexpected payload formats
  Map<String, dynamic>? _asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) {
      try {
        return Map<String, dynamic>.from(v);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  String? _asString(dynamic v) {
    if (v == null) return null;
    if (v is String) return v;
    try {
      return v.toString();
    } catch (_) {
      return null;
    }
  }

  bool _asBool(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      final s = v.toLowerCase();
      return s == 'true' || s == '1' || s == 't';
    }
    return false;
  }

  // Show local notification
  void _showLocalNotification(Map<String, dynamic> record) {
    try {
      final notification = NotificationModel.fromJson(record);
      debugPrint('Would show notification: ${notification.title} - ${notification.message}');
    } catch (e) {
      debugPrint('Error showing local notification: $e');
    }
  }

  // Show local message notification
  void _showLocalMessageNotification(Map<String, dynamic> record) {
    try {
      final content = record['content'] as String? ?? 'New message';
      debugPrint('Would show message notification: New Message - $content');
    } catch (e) {
      debugPrint('Error showing local message notification: $e');
    }
  }

  // Play notification sound
  void _playNotificationTone() {
    try {
      // Use OS-level default notification sound via posted notifications; no custom tone here
      // Intentionally left blank to avoid overriding system ringtone
    } catch (e) {
      // No fallback; rely on OS notifications
    }
  }

  // Play message sound
  void _playMessageSound() {
    try {
      // Use OS-level default notification sound via posted notifications; no custom tone here
      // Intentionally left blank to avoid overriding system ringtone
    } catch (e) {
      debugPrint('Error playing notification sound: $e');
    }
  }


  // Trigger haptic feedback
  void _triggerHapticFeedback() {
    try {
      HapticFeedback.lightImpact();
    } catch (e) {
      debugPrint('Error triggering haptic feedback: $e');
    }
  }

  // New: Mark Activity as seen so that badges only show new notifications after this point
  void markActivitySeen() {
    _seenNotificationCount = _notificationCount;
    _effectiveNotificationBadgeController.add(effectiveNotificationCount);
  }

  // Manually update notification count (for when notifications are marked as read)
  void updateNotificationCount(int count) {
    _notificationCount = count.clamp(0, double.infinity).toInt();
    _notificationBadgeController.add(_notificationCount);
    _totalBadgeController.add(totalCount);
    _effectiveNotificationBadgeController.add(effectiveNotificationCount);
  }

  // Manually update message count (for when messages are marked as read)
  void updateMessageCount(int count) {
    _messageCount = count.clamp(0, double.infinity).toInt();
    _messageBadgeController.add(_messageCount);
    _totalBadgeController.add(totalCount);
  }

  // Clear all notification badges
  void clearNotificationBadges() {
    _notificationCount = 0;
    _effectiveNotificationBadgeController.add(effectiveNotificationCount);
    _notificationBadgeController.add(_notificationCount);
    _totalBadgeController.add(totalCount);
  }

  // Clear all message badges
  void clearMessageBadges() {
    _messageCount = 0;
    _messageBadgeController.add(_messageCount);
    _totalBadgeController.add(totalCount);
  }

  // Clear all badges
  void clearAllBadges() {
    _notificationCount = 0;
    _messageCount = 0;
    _seenNotificationCount = 0;
    _effectiveNotificationBadgeController.add(effectiveNotificationCount);
    _notificationBadgeController.add(_notificationCount);
    _messageBadgeController.add(_messageCount);
    _totalBadgeController.add(totalCount);
  }

  // Dispose resources (only unsubscribe to allow re-initialization across auth changes)
  void dispose() {
    _unsubscribeRealtimeSubscriptions();
    // Intentionally do NOT close controllers to keep the singleton reusable across auth cycles
  }
}