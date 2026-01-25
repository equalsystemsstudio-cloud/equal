import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import '../firebase_options.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import './supabase_service.dart';
import '../screens/messaging/enhanced_chat_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/live_stream_viewer_screen.dart';
import '../screens/calling/calling_screen.dart';
import 'calling_service.dart';
import '../config/supabase_config.dart';
import '../config/feature_flags.dart';

// Top-level function for background message handling
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Ensure Firebase is initialized in background isolate using explicit options
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  if (kDebugMode) {
    debugPrint('Handling a background message: ${message.messageId}');
  }

  // For data-only messages, explicitly show a local notification using default system sound
  try {
    if (kIsWeb) {
      return;
    }

    final FlutterLocalNotificationsPlugin localNotifications =
        FlutterLocalNotificationsPlugin();

    const InitializationSettings initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      ),
    );
    await localNotifications.initialize(initSettings);

    if (defaultTargetPlatform == TargetPlatform.android) {
      const channels = [
        AndroidNotificationChannel(
          'high_importance_channel',
          'High Importance Notifications',
          description: 'This channel is used for important notifications.',
          importance: Importance.high,
        ),
        AndroidNotificationChannel(
          'social_channel',
          'Social Notifications',
          description: 'Notifications for likes, comments, tracking, etc.',
          importance: Importance.defaultImportance,
        ),
        AndroidNotificationChannel(
          'messages_channel',
          'Message Notifications',
          description: 'Notifications for direct messages.',
          importance: Importance.high,
        ),
        // New: Calls channel for incoming calls (max importance + full-screen intent)
        AndroidNotificationChannel(
          'calls_channel',
          'Incoming Calls',
          description: 'Incoming call notifications with full-screen intent.',
          importance: Importance.max,
        ),
      ];

      for (final channel in channels) {
        await localNotifications
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.createNotificationChannel(channel);
      }
    }

    // If the notification payload is absent, compose from data and show a local notification
    if (message.notification == null) {
      final data = Map<String, dynamic>.from(message.data);
      final String title = (data['title'] ?? 'Equal').toString();
      final String body = (data['body'] ?? '').toString();
      final String type = (data['type'] ?? '').toString();

      final String channelId = type == 'message'
          ? 'messages_channel'
          : (type == 'like' || type == 'comment' || type == 'follow')
              ? 'social_channel'
              : (type == 'incoming_call' ? 'calls_channel' : 'high_importance_channel');
      final String channelName = channelId == 'messages_channel'
          ? 'Message Notifications'
          : channelId == 'social_channel'
              ? 'Social Notifications'
              : 'High Importance Notifications';
      final String channelDescription = channelId == 'messages_channel'
          ? 'Notifications for direct messages.'
          : channelId == 'social_channel'
              ? 'Notifications for likes, comments, tracking, etc.'
              : 'This channel is used for important notifications.';

      await localNotifications.show(
        message.hashCode,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            channelName,
            channelDescription: channelDescription,
            importance: channelId == 'calls_channel' ? Importance.max : Importance.high,
            priority: channelId == 'calls_channel' ? Priority.max : Priority.high,
            playSound: true, // use default system sound
            icon: '@mipmap/ic_launcher',
            // New: enable full-screen intent for incoming calls
            fullScreenIntent: channelId == 'calls_channel',
            category: channelId == 'calls_channel' ? AndroidNotificationCategory.call : null,
            // New: actions for answering/declining on Android
            actions: channelId == 'calls_channel'
                ? const [
                    AndroidNotificationAction('answer', 'Answer'),
                    AndroidNotificationAction('decline', 'Decline'),
                  ]
                : null,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true, // use default system sound
          ),
        ),
        payload: jsonEncode(data),
      );
    }
  } catch (e) {
    if (kDebugMode) {
      debugPrint('Background notification handling failed: $e');
    }
  }
}

class PushNotificationService {
  static final PushNotificationService _instance =
      PushNotificationService._internal();
  factory PushNotificationService() => _instance;
  PushNotificationService._internal();

  FirebaseMessaging? _firebaseMessaging;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  final SupabaseClient _supabase = Supabase.instance.client;

  bool _isInitialized = false;
  String? _fcmToken;

  // Initialize push notifications
  Future<void> initialize() async {
    if (_isInitialized) return;

    // Disable push notifications initialization on web to avoid unsupported Platform operations
    if (kIsWeb) {
      _isInitialized = true;
      if (kDebugMode) {
        debugPrint('PushNotificationService: Skipping initialization on web');
      }
      return;
    }

    try {
      // Check if Firebase is already initialized, if not try to initialize
      try {
        if (Firebase.apps.isEmpty) {
          // Initialize Firebase with explicit options to avoid [core/no-app]
          await Firebase.initializeApp(
            options: DefaultFirebaseOptions.currentPlatform,
          );
        }
      } catch (firebaseError) {
        if (kDebugMode) {
          debugPrint('Firebase initialization failed in PushNotificationService: $firebaseError');
        }
        // Continue without Firebase - local notifications can still work
      }

      // Initialize local notifications (works without Firebase)
      await _initializeLocalNotifications();

      // Only proceed with Firebase-dependent features if Firebase is available
      if (Firebase.apps.isNotEmpty) {
        try {
          // Lazily get messaging instance only after Firebase is initialized
          _firebaseMessaging = FirebaseMessaging.instance;

          // Request permission for notifications
          await _requestPermission();

          // Ensure iOS shows notifications in foreground with default system sound
          try {
            await _firebaseMessaging!.setForegroundNotificationPresentationOptions(
              alert: true,
              badge: true,
              sound: true,
            );
          } catch (_) {}

          // Set up background message handler
          // Removed registration here; it will be registered early in main.dart to comply with best practices
          // FirebaseMessaging.onBackgroundMessage(
          //   firebaseMessagingBackgroundHandler,
          // );

          // Get FCM token
          await _getFCMToken();

          // Set up message handlers
          _setupMessageHandlers();
        } catch (fcmError) {
          if (kDebugMode) {
            debugPrint('FCM features failed to initialize: $fcmError');
          }
          // Continue with local notifications only
        }
      } else {
        if (kDebugMode) {
          debugPrint('Firebase not available - push notifications will use local notifications only');
        }
      }

      _isInitialized = true;
      if (kDebugMode) {
        debugPrint('Push notifications initialized successfully (Firebase available: ${Firebase.apps.isNotEmpty})');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error initializing push notifications: $e');
      }
      // Mark as initialized even if some features failed to prevent repeated attempts
      _isInitialized = true;
    }
  }

  // Request notification permissions
  Future<void> _requestPermission() async {
    // If messaging isn't available, skip permission request
    if (_firebaseMessaging == null) return;
    final settings = await _firebaseMessaging!.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    if (kDebugMode) {
      debugPrint('User granted permission: ${settings.authorizationStatus}');
    }
  }

  // Initialize local notifications
  Future<void> _initializeLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initializationSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // If the app was launched via a notification tap, process the payload
    try {
      final launchDetails = await _localNotifications.getNotificationAppLaunchDetails();
      if (launchDetails?.didNotificationLaunchApp ?? false) {
        final payload = launchDetails?.notificationResponse?.payload;
        if (payload != null && payload.isNotEmpty) {
          final decoded = jsonDecode(payload);
          final data = _asMap(decoded);
          if (data != null) {
            // Navigation may not be ready yet; queue if necessary
            if (navigatorKey.currentState == null) {
              _pendingTapData = data;
            } else {
              // ignore: discarded_futures
              _handleNotificationTap(data);
            }
          }
        }
      }
    } catch (_) {}

    // Create notification channels for Android
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      await _createNotificationChannels();
    }
  }

  // Create notification channels for Android
  Future<void> _createNotificationChannels() async {
    const channels = [
      AndroidNotificationChannel(
        'high_importance_channel',
        'High Importance Notifications',
        description: 'This channel is used for important notifications.',
        importance: Importance.high,
      ),
      AndroidNotificationChannel(
        'social_channel',
        'Social Notifications',
        description: 'Notifications for likes, comments, tracking, etc.',
        importance: Importance.defaultImportance,
      ),
      AndroidNotificationChannel(
        'messages_channel',
        'Message Notifications',
        description: 'Notifications for direct messages.',
        importance: Importance.high,
      ),
      AndroidNotificationChannel(
        'calls_channel',
        'Incoming Calls',
        description: 'Incoming call notifications with full-screen intent.',
        importance: Importance.max,
      ),
    ];

    for (final channel in channels) {
      await _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(channel);
    }
  }

  // Get FCM token
  Future<void> _getFCMToken() async {
    if (_firebaseMessaging == null) return;
    try {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        // Wait for APNs token to be available
        final apnsToken = await _firebaseMessaging!.getAPNSToken();
        if (apnsToken == null) {
          if (kDebugMode) {
            debugPrint('APNs token not yet available, waiting...');
          }
          await Future.delayed(const Duration(seconds: 3));
        }
      }

      _fcmToken = await _firebaseMessaging!.getToken();
      if (kDebugMode) {
        debugPrint('FCM Token: $_fcmToken');
      }

      // Save token to Supabase for the current user
      await _saveFCMTokenToDatabase();

      // Listen for token refresh
      _firebaseMessaging!.onTokenRefresh.listen((token) {
        _fcmToken = token;
        _saveFCMTokenToDatabase();
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error getting FCM token: $e');
      }
    }
  }

  // Save FCM token to database
  Future<void> _saveFCMTokenToDatabase() async {
    try {
      final currentUser = _supabase.auth.currentUser;
      if (currentUser != null && _fcmToken != null) {
        await _supabase
            .from('users')
            .update({
              'fcm_token': _fcmToken,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', currentUser.id);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error saving FCM token to database: $e');
      }
    }
  }

  // Set up message handlers
  void _setupMessageHandlers() {
    // Handle messages when app is in foreground
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (kDebugMode) {
        debugPrint('Got a message whilst in the foreground!');
        debugPrint('Message data: ${message.data}');
      }

      if (message.notification != null) {
        _showLocalNotification(message);
      } else {
        // Show a local notification for data-only messages in foreground
        final data = Map<String, dynamic>.from(message.data);
        if (data.isNotEmpty) {
          _showLocalNotificationFromData(data);
        }
      }
    });

    // Handle notification taps when app is in background
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      if (kDebugMode) {
        debugPrint('A new onMessageOpenedApp event was published!');
      }
      try {
        final dataSafe = Map<String, dynamic>.from(message.data);
        if (dataSafe.isEmpty) {
          if (kDebugMode) debugPrint('onMessageOpenedApp: empty data payload, ignoring');
          return;
        }
        _handleNotificationTap(dataSafe);
      } catch (e) {
        if (kDebugMode) {
          debugPrint('onMessageOpenedApp: failed to parse payload as Map<String, dynamic>: $e');
        }
      }
    });

    // Handle notification tap when app is terminated
    _firebaseMessaging!.getInitialMessage().then((RemoteMessage? message) {
      if (message != null) {
        try {
          final dataSafe = Map<String, dynamic>.from(message.data);
          if (dataSafe.isEmpty) {
            if (kDebugMode) debugPrint('getInitialMessage: empty data payload, ignoring');
            return;
          }
          _handleNotificationTap(dataSafe);
        } catch (e) {
          if (kDebugMode) debugPrint('getInitialMessage: failed to parse payload as Map<String, dynamic>: $e');
        }
      }
    });
  }

  // Show local notification
  Future<void> _showLocalNotification(RemoteMessage message) async {
    final notification = message.notification;
    final android = message.notification?.android;

    if (notification != null) {
      final channelId = _getChannelId(message.data['type']);

      await _localNotifications.show(
        notification.hashCode,
        notification.title,
        notification.body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            _getChannelName(channelId),
            channelDescription: _getChannelDescription(channelId),
            importance: Importance.high,
            priority: Priority.high,
            playSound: true, // use default system sound
            icon: android?.smallIcon ?? '@mipmap/ic_launcher',
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true, // use default system sound
          ),
        ),
        payload: jsonEncode(message.data),
      );
    }
  }

  // Show local notification built from data-only payload
  Future<void> _showLocalNotificationFromData(Map<String, dynamic> data) async {
    final String title = (data['title'] ?? 'Equal').toString();
    final String body = (data['body'] ?? '').toString();
    final String channelId = _getChannelId(data['type']?.toString());

    await _localNotifications.show(
      data.hashCode,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          _getChannelName(channelId),
          channelDescription: _getChannelDescription(channelId),
          importance: channelId == 'calls_channel' ? Importance.max : Importance.high,
          priority: channelId == 'calls_channel' ? Priority.max : Priority.high,
          playSound: true, // use default system sound
          icon: '@mipmap/ic_launcher',
          fullScreenIntent: channelId == 'calls_channel',
          category: channelId == 'calls_channel' ? AndroidNotificationCategory.call : null,
          actions: channelId == 'calls_channel'
              ? const [
                  AndroidNotificationAction('answer', 'Answer'),
                  AndroidNotificationAction('decline', 'Decline'),
                ]
              : null,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true, // use default system sound
        ),
      ),
      payload: jsonEncode(data),
    );
  }

  // Get notification channel ID based on type
  String _getChannelId(String? type) {
    switch (type) {
      case 'message':
        return 'messages_channel';
      case 'like':
      case 'comment':
      case 'follow':
        return 'social_channel';
      case 'live':
        // Live stream notifications are high importance to encourage real-time engagement
        return 'high_importance_channel';
      case 'incoming_call':
        return 'calls_channel';
      default:
        return 'high_importance_channel';
    }
  }

  // Get channel name
  String _getChannelName(String channelId) {
    switch (channelId) {
      case 'messages_channel':
        return 'Message Notifications';
      case 'social_channel':
        return 'Social Notifications';
      case 'calls_channel':
        return 'Incoming Calls';
      default:
        return 'High Importance Notifications';
    }
  }

  // Get channel description
  String _getChannelDescription(String channelId) {
    switch (channelId) {
      case 'messages_channel':
        return 'Notifications for direct messages.';
      case 'social_channel':
        return 'Notifications for likes, comments, tracking, etc.';
      case 'calls_channel':
        return 'Incoming call notifications with full-screen intent.';
      default:
        return 'This channel is used for important notifications.';
    }
  }

  // Global navigator key to allow navigation from service without BuildContext
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  // Store a pending notification tap payload if navigation isn't ready yet
  Map<String, dynamic>? _pendingTapData;

  // Safe parsing helpers
  static Map<String, dynamic>? _asMap(dynamic v) {
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

  static String? _asString(dynamic v) {
    if (v == null) return null;
    if (v is String) return v;
    try {
      return v.toString();
    } catch (_) {
      return null;
    }
  }

  // Handle notification tap
  Future<void> _handleNotificationTap(Map<String, dynamic> data) async {
    // If navigator is not yet attached (e.g., app not built), queue the navigation
    if (navigatorKey.currentState == null) {
      if (kDebugMode) {
        debugPrint('Navigator not ready, queuing pending navigation');
      }
      _pendingTapData = data;
      return;
    }

    // Extract type and IDs from either top-level or nested 'data' payload
    final Map<String, dynamic>? nested = _asMap(data['data']);
    final type = _asString(data['type']) ?? _asString(nested?['type']);
    final postId = _asString(data['post_id']) ?? _asString(nested?['post_id']);
    final commentId = _asString(data['comment_id']) ?? _asString(nested?['comment_id']);
    final conversationId = _asString(data['conversation_id']) ?? _asString(nested?['conversation_id']);
    final senderId = _asString(data['sender_id']) ?? _asString(nested?['sender_id']);
    final senderUsername = _asString(data['sender_username']) ?? _asString(nested?['sender_username']);
    final followerId = _asString(data['follower_id']) ?? _asString(nested?['follower_id']);
    final streamId = _asString(data['stream_id']) ?? _asString(nested?['stream_id']);
    final streamTitle = _asString(data['title']) ?? _asString(nested?['title']);

    if (kDebugMode) {
      debugPrint('Notification tapped: type=${type?.toString() ?? 'null'}, postId=${postId?.toString() ?? 'null'}, commentId=${commentId?.toString() ?? 'null'}, conversationId=${conversationId?.toString() ?? 'null'}, senderId=${senderId?.toString() ?? 'null'}, followerId=${followerId?.toString() ?? 'null'}');
    }

    if (type == null) {
      if (kDebugMode) debugPrint('Notification tap ignored: missing type');
      return;
    }

    try {
      switch (type) {
        case 'message':
          if (conversationId != null && senderId != null) {
            // Resolve display name and avatar if needed
            String resolvedName = senderUsername ?? 'Unknown User';
            String resolvedAvatar = 'unknown';
            final normalized = resolvedName.toLowerCase();
            if (resolvedName.isEmpty || normalized == 'unknown user' || normalized == 'unknown') {
              try {
                final profile = await SupabaseService.getProfile(senderId);
                if (profile != null) {
                  resolvedName = (profile['display_name'] ?? profile['username'] ?? 'Unknown User') as String;
                  resolvedAvatar = (profile['avatar_url'] ?? 'unknown') as String;
                }
              } catch (e) {
                if (kDebugMode) {
                  debugPrint('Failed to hydrate sender profile for chat navigation: $e');
                }
              }
            }
            navigatorKey.currentState?.push(
              MaterialPageRoute(
                builder: (context) => EnhancedChatScreen(
                  conversationId: conversationId,
                  otherUserId: senderId,
                  otherUserName: resolvedName,
                  otherUserAvatar: resolvedAvatar,
                ),
              ),
            );
          }
          break;
        case 'like':
        case 'comment':
        case 'mention':
        case 'share':
          if (postId != null) {
            navigatorKey.currentState?.pushNamed('/post_detail', arguments: postId);
          }
          break;
        case 'follow':
          if (followerId != null) {
            navigatorKey.currentState?.push(
              MaterialPageRoute(
                builder: (context) => ProfileScreen(userId: followerId),
              ),
            );
          }
          break;
        case 'live':
          if (streamId != null) {
            navigatorKey.currentState?.push(
              MaterialPageRoute(
                builder: (context) => LiveStreamViewerScreen(
                  streamId: streamId,
                  title: streamTitle,
                ),
              ),
            );
          }
          break;
        default:
          // No-op for unrecognized types
          if (kDebugMode) {
            debugPrint('Unhandled notification type: $type');
          }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error handling notification tap: $e');
      }
    }
  }

  // Process any pending navigation once navigator becomes available
  void processPendingNavigation() {
    if (navigatorKey.currentState == null) return;
    if (_pendingTapData != null) {
      final data = _pendingTapData!;
      _pendingTapData = null;
      // Fire and forget; navigation will be handled inside
      _handleNotificationTap(data);
    }
  }
  // Handle local notification tap
  void _onNotificationTapped(NotificationResponse response) {
    if (response.payload != null) {
      try {
        final decoded = jsonDecode(response.payload!);
        final data = _asMap(decoded);
        if (data == null || data.isEmpty) {
          if (kDebugMode) debugPrint('Local notification tap: payload not a Map, ignoring');
          return;
        }
        // New: handle Android action buttons for incoming calls
        final actionId = response.actionId;
        final Map<String, dynamic>? nested = _asMap(data['data']);
        final type = _asString(data['type']) ?? _asString(nested?['type']);
        final callId = _asString(data['call_id']) ?? _asString(nested?['call_id']);
        // Respect feature flag: ignore call-type taps when calls are disabled
        if (!FeatureFlags.callsEnabled && type == 'incoming_call') {
          if (kDebugMode) debugPrint('Calls disabled: ignoring incoming_call tap');
          return;
        }
        if (type == 'incoming_call' && callId != null && actionId != null) {
          final callingService = CallingService();
          if (actionId == 'answer') {
            // ignore: discarded_futures
            callingService.answerCall(callId).then((ok) async {
              if (ok) {
                await _navigateToIncomingCall(data);
              }
            });
            return;
          } else if (actionId == 'decline') {
            // ignore: discarded_futures
            callingService.declineCall(callId);
            return;
          }
        }
        _handleNotificationTap(data);
      } catch (e) {
        if (kDebugMode) debugPrint('Local notification tap: failed to decode payload: $e');
      }
    }
  }

  // Send push notification to specific user
  Future<bool> sendNotificationToUser({
    required String userId,
    required String title,
    required String body,
    required String type,
    Map<String, dynamic>? data,
  }) async {
    try {
      // Get user's FCM token from database
      final userResponse = await _supabase
          .from('users')
          .select('fcm_token')
          .eq('id', userId)
          .single();

      final fcmToken = userResponse['fcm_token'] as String?;
      if (fcmToken == null) {
        if (kDebugMode) {
          debugPrint('No FCM token found for user: $userId');
        }
        return false;
      }

      // Invoke Supabase Edge Function to send push
      final response = await SupabaseConfig.client.functions.invoke(
        'send_push',
        body: {
          'token': fcmToken,
          'title': title,
          'body': body,
          'type': type,
          'data': data ?? {},
        },
      );

      final payload = response.data;
      if (payload is Map && payload['success'] == true) {
        if (kDebugMode) {
          debugPrint('Push sent via Edge Function to $userId');
        }
        return true;
      }

      if (kDebugMode) {
        debugPrint('Edge Function send_push response: ${response.data}');
      }
      return false;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error sending notification: $e');
      }
      return false;
    }
  }

  // Subscribe to topic
  Future<void> subscribeToTopic(String topic) async {
    try {
      await _firebaseMessaging?.subscribeToTopic(topic);
      if (kDebugMode) {
        debugPrint('Subscribed to topic: $topic');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error subscribing to topic: $e');
      }
    }
  }

  // Unsubscribe from topic
  Future<void> unsubscribeFromTopic(String topic) async {
    try {
      await _firebaseMessaging?.unsubscribeFromTopic(topic);
      if (kDebugMode) {
        debugPrint('Unsubscribed from topic: $topic');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error unsubscribing from topic: $e');
      }
    }
  }

  // Clear all notifications
  Future<void> clearAllNotifications() async {
    await _localNotifications.cancelAll();
  }

  // Get FCM token
  String? get fcmToken => _fcmToken;

  // Check if notifications are enabled
  Future<bool> areNotificationsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('notifications_enabled') ?? true;
  }

  // Enable/disable notifications
  Future<void> setNotificationsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notifications_enabled', enabled);

    if (enabled) {
      await _getFCMToken();
    } else {
      // Remove FCM token from database
      try {
        final currentUser = _supabase.auth.currentUser;
        if (currentUser != null) {
          await _supabase
              .from('users')
              .update({
                'fcm_token': null,
                'updated_at': DateTime.now().toIso8601String(),
              })
              .eq('id', currentUser.id);
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('Error removing FCM token: $e');
        }
      }
    }
  }
}

// New: navigate to CallingScreen for an incoming call payload
Future<void> _navigateToIncomingCall(Map<String, dynamic> data) async {
  // Respect feature flag: do not navigate when calls are disabled
  if (!FeatureFlags.callsEnabled) {
    if (kDebugMode) debugPrint('Calls disabled: skipping incoming call navigation');
    return;
  }
  final Map<String, dynamic>? nested = PushNotificationService._asMap(data['data']);
  final callId = PushNotificationService._asString(data['call_id']) ?? PushNotificationService._asString(nested?['call_id']);
  final callerName = PushNotificationService._asString(data['caller_name']) ?? PushNotificationService._asString(nested?['caller_name']);
  if (callId == null) {
    if (kDebugMode) debugPrint('Incoming call navigation: missing call_id');
    return;
  }
  try {
    final supabase = Supabase.instance.client;
    final raw = await supabase
        .from('calls')
        .select('*')
        .eq('id', callId)
        .maybeSingle();
    if (raw == null) {
      if (kDebugMode) debugPrint('Incoming call not found: $callId');
      return;
    }
    final call = CallModel.fromMap(Map<String, dynamic>.from(raw));
    PushNotificationService.navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (context) => CallingScreen(
          call: call,
          isIncoming: true,
        ),
        fullscreenDialog: true,
      ),
    );
  } catch (e) {
    if (kDebugMode) debugPrint('Incoming call navigation failed: $e');
  }
}
