import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import 'cache_service.dart';

enum AnalyticsRange { day, week, month, year, lifetime }


class AnalyticsService {
  static final AnalyticsService _instance = AnalyticsService._internal();
  factory AnalyticsService() => _instance;
  AnalyticsService._internal();

  final SupabaseClient _client = SupabaseConfig.client;
  // ignore: unused_field
final CacheService _cacheService = CacheService();
  
  // Event types
  static const String eventAppOpen = 'app_open';
  static const String eventAppClose = 'app_close';
  static const String eventLogin = 'login';
  static const String eventLogout = 'logout';
  static const String eventSignup = 'signup';
  static const String eventPostView = 'post_view';
  static const String eventPostLike = 'post_like';
  static const String eventPostUnlike = 'post_unlike';
  static const String eventPostComment = 'post_comment';
  static const String eventPostShare = 'post_share';
  static const String eventPostCreate = 'post_create';
  static const String eventPostDelete = 'post_delete';
  static const String eventUserTrack = 'user_track';
  static const String eventUserUntrack = 'user_untrack';
  static const String eventProfileView = 'profile_view';
  static const String eventSearch = 'search';
  static const String eventVideoPlay = 'video_play';
  static const String eventVideoPause = 'video_pause';
  static const String eventVideoComplete = 'video_complete';
  static const String eventScreenView = 'screen_view';
  static const String eventFeatureUsed = 'feature_used';
  static const String eventError = 'error';
  static const String eventPerformance = 'performance';
  
  // Session tracking
  DateTime? _sessionStart;
  String? _sessionId;
  Timer? _sessionTimer;
  final List<Map<String, dynamic>> _pendingEvents = [];
  
  // Performance tracking
  final Map<String, DateTime> _performanceMarkers = {};
  
  // Initialize analytics
  Future<void> initialize() async {
    await _startSession();
    _setupPeriodicFlush();
  }

  // Session management
  Future<void> _startSession() async {
    _sessionStart = DateTime.now();
    _sessionId = '${DateTime.now().millisecondsSinceEpoch}_${DateTime.now().microsecond}';
    
    await trackEvent(
      eventAppOpen,
      properties: {
        'session_id': _sessionId,
        'platform': defaultTargetPlatform.name,
      },
    );
  }

  Future<void> endSession() async {
    if (_sessionStart != null && _sessionId != null) {
      final sessionDuration = DateTime.now().difference(_sessionStart!).inSeconds;
      
      await trackEvent(
        eventAppClose,
        properties: {
          'session_id': _sessionId,
          'session_duration': sessionDuration,
        },
      );
      
      await _flushPendingEvents();
    }
    
    _sessionTimer?.cancel();
  }

  // Event tracking
  Future<void> trackEvent(
    String eventName, {
    Map<String, dynamic>? properties,
    String? userId,
  }) async {
    try {
      final currentUserId = userId ?? _getCurrentUserId();
      
      // Skip analytics if no authenticated user (to avoid RLS violations)
      if (currentUserId == null) {
        if (kDebugMode) {
          debugPrint(('Skipping analytics event $eventName - no authenticated user').toString());
        }
        return;
      }
      
      final event = {
        'event_name': eventName,
        'user_id': currentUserId,
        'session_id': _sessionId,
        'properties': properties ?? {},
        'platform': defaultTargetPlatform.name,
        'app_version': await _getAppVersion(),
        // Note: removed 'timestamp' field - database uses auto-generated 'created_at'
      };
      
      // Add to pending events for batch processing
      _pendingEvents.add(event);
      
      // Flush immediately for critical events
      if (_isCriticalEvent(eventName)) {
        await _flushPendingEvents();
      }
      
      if (kDebugMode) {
        debugPrint(('Analytics Event: $eventName - ${jsonEncode(properties)}').toString());
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint(('Error tracking event: $e').toString());
      }
    }
  }

  // User events
  Future<void> trackLogin(String method) async {
    await trackEvent(eventLogin, properties: {'method': method});
  }

  Future<void> trackLogout() async {
    await trackEvent(eventLogout);
  }

  Future<void> trackSignup(String method) async {
    await trackEvent(eventSignup, properties: {'method': method});
  }

  // Content events
  Future<void> trackPostView(String postId, String postType, {int? duration}) async {
    await trackEvent(
      eventPostView,
      properties: {
        'post_id': postId,
        'post_type': postType,
        if (duration != null) 'view_duration': duration,
      },
    );
  }

  Future<void> trackPostLike(String postId, String postType) async {
    await trackEvent(
      eventPostLike,
      properties: {
        'post_id': postId,
        'post_type': postType,
      },
    );
  }

  Future<void> trackPostUnlike(String postId, String postType) async {
    await trackEvent(
      eventPostUnlike,
      properties: {
        'post_id': postId,
        'post_type': postType,
      },
    );
  }

  Future<void> trackPostComment(String postId, String postType) async {
    await trackEvent(
      eventPostComment,
      properties: {
        'post_id': postId,
        'post_type': postType,
      },
    );
  }

  Future<void> trackPostShare(String postId, String postType, String shareMethod) async {
    await trackEvent(
      eventPostShare,
      properties: {
        'post_id': postId,
        'post_type': postType,
        'share_method': shareMethod,
      },
    );
  }

  Future<void> trackPostCreate(String postType, Map<String, dynamic>? metadata) async {
    await trackEvent(
      eventPostCreate,
      properties: {
        'post_type': postType,
        ...?metadata,
      },
    );
  }

  Future<void> trackPostDelete(String postId, String postType) async {
    await trackEvent(
      eventPostDelete,
      properties: {
        'post_id': postId,
        'post_type': postType,
      },
    );
  }

  // Social events
  Future<void> trackUserTrack(String targetUserId) async {
    await trackEvent(
      eventUserTrack,
      properties: {'target_user_id': targetUserId},
    );
  }

  Future<void> trackUserUntrack(String targetUserId) async {
    await trackEvent(
      eventUserUntrack,
      properties: {'target_user_id': targetUserId},
    );
  }

  Future<void> trackProfileView(String profileUserId) async {
    await trackEvent(
      eventProfileView,
      properties: {'profile_user_id': profileUserId},
    );
  }

  // Search events
  Future<void> trackSearch(String query, String searchType, int resultCount) async {
    await trackEvent(
      eventSearch,
      properties: {
        'query': query,
        'search_type': searchType,
        'result_count': resultCount,
      },
    );
  }

  // Video events
  Future<void> trackVideoPlay(String postId, int position) async {
    await trackEvent(
      eventVideoPlay,
      properties: {
        'post_id': postId,
        'position': position,
      },
    );
  }

  Future<void> trackVideoPause(String postId, int position, int duration) async {
    await trackEvent(
      eventVideoPause,
      properties: {
        'post_id': postId,
        'position': position,
        'watch_duration': duration,
      },
    );
  }

  Future<void> trackVideoComplete(String postId, int duration) async {
    await trackEvent(
      eventVideoComplete,
      properties: {
        'post_id': postId,
        'total_duration': duration,
      },
    );
  }

  // Screen tracking
  Future<void> trackScreenView(String screenName, {Map<String, dynamic>? properties}) async {
    await trackEvent(
      eventScreenView,
      properties: {
        'screen_name': screenName,
        ...?properties,
      },
    );
  }

  // Expose a public flush to push pending events immediately when needed (e.g., before reading analytics)
  Future<void> flushPendingEvents() async {
    await _flushPendingEvents();
  }

  // Seed a handful of sample events for brand-new accounts (to populate Analytics UI)
  // This only runs when the user has no meaningful events yet (excluding screen_view events)
  Future<void> seedSampleEventsIfNeeded({String? userId}) async {
    try {
      final currentUserId = userId ?? _getCurrentUserId();
      if (currentUserId == null) return;

      // Check for any non-screen_view events in the last 30 days
      final recent = await _client
          .from('analytics_events')
          .select('event_name')
          .eq('user_id', currentUserId)
          .gte('created_at', DateTime.now().subtract(const Duration(days: 30)).toIso8601String())
          .neq('event_name', eventScreenView)
          .limit(1);

      if (recent.isNotEmpty) {
        // Already have real events; do not seed
        return;
      }

      // Seed a small variety of events
      await trackEvent(eventFeatureUsed, properties: {'feature_name': 'create_post'});
      await trackEvent(eventFeatureUsed, properties: {'feature_name': 'follow_user'});
      await trackEvent(eventFeatureUsed, properties: {'feature_name': 'search'});
      await trackEvent(eventFeatureUsed, properties: {'feature_name': 'view_feed'});

      await trackEvent(eventSearch, properties: {
        'query': 'demo',
        'search_type': 'posts',
        'result_count': 12,
      });

      await trackEvent(eventProfileView, properties: {
        'profile_user_id': currentUserId,
      });

      // Attempt to use a real post ID for post-related demo events (avoid non-UUID values)
      String? samplePostId;
      String samplePostType = 'image';
      try {
        final samplePost = await _client
            .from('posts')
            .select('id, type')
            .eq('user_id', currentUserId)
            .limit(1);
        if (samplePost is List && samplePost.isNotEmpty) {
          final p = samplePost.first;
          samplePostId = p['id'] as String?;
          samplePostType = (p['type'] as String?) ?? 'image';
        }
      } catch (_) {
        // Ignore lookup errors and skip post-related seeds if none found
      }

      if (samplePostId != null) {
        await trackEvent(eventPostView, properties: {
          'post_id': samplePostId,
          'post_type': samplePostType,
          'view_duration': 12,
        });
        await trackEvent(eventVideoPlay, properties: {
          'post_id': samplePostId,
          'position': 0,
        });
        await trackEvent(eventVideoComplete, properties: {
          'post_id': samplePostId,
          'duration': 45,
        });
      }

      // Flush so the Analytics screen can read them immediately
      await _flushPendingEvents();
    } catch (e) {
      if (kDebugMode) {
        debugPrint(('seedSampleEventsIfNeeded error: $e').toString());
      }
    }
  }

  // Feature usage tracking
  Future<void> trackFeatureUsed(String featureName, {Map<String, dynamic>? properties}) async {
    await trackEvent(
      eventFeatureUsed,
      properties: {
        'feature_name': featureName,
        ...?properties,
      },
    );
  }

  // Error tracking
  Future<void> trackError(
    String errorType,
    String errorMessage, {
    String? stackTrace,
    Map<String, dynamic>? context,
  }) async {
    await trackEvent(
      eventError,
      properties: {
        'error_type': errorType,
        'error_message': errorMessage,
        if (stackTrace != null) 'stack_trace': stackTrace,
        ...?context,
      },
    );
  }

  // Performance tracking
  void startPerformanceTimer(String operationName) {
    _performanceMarkers[operationName] = DateTime.now();
  }

  Future<void> endPerformanceTimer(
    String operationName, {
    Map<String, dynamic>? additionalData,
  }) async {
    final startTime = _performanceMarkers.remove(operationName);
    if (startTime != null) {
      final duration = DateTime.now().difference(startTime).inMilliseconds;
      
      await trackEvent(
        eventPerformance,
        properties: {
          'operation_name': operationName,
          'duration_ms': duration,
          ...?additionalData,
        },
      );
    }
  }

  // Analytics data retrieval
  Future<Map<String, dynamic>> getUserAnalytics(String userId, {AnalyticsRange range = AnalyticsRange.month}) async {
    try {
      final DateTime? start = _startDateForRange(range);
      final response = await _client
          .from('analytics_events')
          .select('*')
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      final List<dynamic> events = start == null
          ? response
          : response.where((e) {
              final created = DateTime.parse(e['created_at'] as String);
              return !created.isBefore(start);
            }).toList();

      return _processAnalyticsData(events);
    } catch (e) {
      if (kDebugMode) {
        debugPrint(('Error fetching user analytics: $e').toString());
      }
      return {};
    }
  }

  Future<Map<String, dynamic>> getPostAnalytics(String postId, {AnalyticsRange range = AnalyticsRange.month}) async {
    try {
      final DateTime? start = _startDateForRange(range);
      final response = await _client
          .from('analytics_events')
          .select('*')
          .eq('properties->>post_id', postId)
          .order('created_at', ascending: false);

      final List<dynamic> events = start == null
          ? response
          : response.where((e) {
              final created = DateTime.parse(e['created_at'] as String);
              return !created.isBefore(start);
            }).toList();

      return _processPostAnalyticsData(events);
    } catch (e) {
      if (kDebugMode) {
        debugPrint(('Error fetching post analytics: $e').toString());
      }
      return {};
    }
  }

  // Batch event processing
  Future<void> _flushPendingEvents() async {
    if (_pendingEvents.isEmpty) return;

    // Skip when not authenticated to avoid RLS errors
    if (_client.auth.currentUser == null) {
      if (kDebugMode) {
        debugPrint(('Skipping flush - not authenticated').toString());
      }
      return;
    }

    // Capture snapshot to allow safe restoration on failure
    final eventsToFlush = List<Map<String, dynamic>>.from(_pendingEvents);
    _pendingEvents.clear();

    try {
      // Insert events in batches
      const batchSize = 100;
      for (int i = 0; i < eventsToFlush.length; i += batchSize) {
        final batch = eventsToFlush.skip(i).take(batchSize).toList();
        await _client.from('analytics_events').insert(batch);
      }

      if (kDebugMode) {
        debugPrint(('Flushed ${eventsToFlush.length} analytics events').toString());
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint(('Error flushing analytics events: $e').toString());
      }
      // Restore events so they can be retried later
      _pendingEvents.addAll(eventsToFlush);
    }
  }

  void _setupPeriodicFlush() {
    _sessionTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
      _flushPendingEvents();
    });
  }

  // Helper methods
  bool _isCriticalEvent(String eventName) {
    return [
      eventLogin,
      eventLogout,
      eventSignup,
      eventError,
      eventPostCreate,
    ].contains(eventName);
  }

  String? _getCurrentUserId() {
    return _client.auth.currentUser?.id;
  }

  Future<String> _getAppVersion() async {
    // In a real app, you'd get this from package_info_plus
    return '1.0.0';
  }

  Map<String, dynamic> _processAnalyticsData(List<dynamic> events) {
    final Map<String, int> eventCounts = {};
    final Map<String, int> dailyActivity = {};
    int totalEvents = events.length;
    
    for (final event in events) {
      final eventName = event['event_name'] as String;
      final timestamp = DateTime.parse(event['created_at'] as String);
      final dateKey = '${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}-${timestamp.day.toString().padLeft(2, '0')}';
      
      eventCounts[eventName] = (eventCounts[eventName] ?? 0) + 1;
      dailyActivity[dateKey] = (dailyActivity[dateKey] ?? 0) + 1;
    }
    
    // Safely compute most_active_day when there is at least one entry
    final String mostActiveDay = dailyActivity.isEmpty
        ? '-'
        : dailyActivity.entries
            .reduce((a, b) => a.value > b.value ? a : b)
            .key;
    
    return {
      'total_events': totalEvents,
      'event_counts': eventCounts,
      'daily_activity': dailyActivity,
      'most_active_day': mostActiveDay,
    };
  }

  Map<String, dynamic> _processPostAnalyticsData(List<dynamic> events) {
    int views = 0;
    int likes = 0;
    int comments = 0;
    int shares = 0;
    final Set<String> uniqueViewers = {};
    
    for (final event in events) {
      final eventName = event['event_name'] as String;
      final userId = event['user_id'] as String?;
      
      switch (eventName) {
        case eventPostView:
          views++;
          if (userId != null) uniqueViewers.add(userId);
          break;
        case eventPostLike:
          likes++;
          break;
        case eventPostComment:
          comments++;
          break;
        case eventPostShare:
          shares++;
          break;
      }
    }
    
    return {
      'views': views,
      'likes': likes,
      'comments': comments,
      'shares': shares,
      'unique_viewers': uniqueViewers.length,
      'engagement_rate': views > 0 ? (likes + comments + shares) / views : 0.0,
    };
  }

  // Cleanup
  Future<void> dispose() async {
    await endSession();
    _sessionTimer?.cancel();
  }
}

DateTime? _startDateForRange(AnalyticsRange range) {
  final now = DateTime.now();
  switch (range) {
    case AnalyticsRange.day:
      return now.subtract(const Duration(days: 1));
    case AnalyticsRange.week:
      return now.subtract(const Duration(days: 7));
    case AnalyticsRange.month:
      return now.subtract(const Duration(days: 30));
    case AnalyticsRange.year:
      return now.subtract(const Duration(days: 365));
    case AnalyticsRange.lifetime:
      return null;
  }
}
