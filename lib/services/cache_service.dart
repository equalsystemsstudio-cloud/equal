import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CacheService {
  static final CacheService _instance = CacheService._internal();
  factory CacheService() => _instance;
  CacheService._internal();

  SharedPreferences? _prefs;
  Directory? _cacheDir;
  
  // Cache keys
  static const String _userProfileKey = 'user_profile';
  static const String _feedPostsKey = 'feed_posts';
  static const String _userPostsKey = 'user_posts';
  static const String _followersKey = 'followers';
  static const String _followingKey = 'following';
  static const String _notificationsKey = 'notifications';
  static const String _searchHistoryKey = 'search_history';
  static const String _settingsKey = 'app_settings';
  static const String _draftsKey = 'content_drafts';
  
  // Cache expiration times (in milliseconds)
  static const int _shortCacheExpiry = 5 * 60 * 1000; // 5 minutes
  static const int _mediumCacheExpiry = 30 * 60 * 1000; // 30 minutes
  static const int _longCacheExpiry = 24 * 60 * 60 * 1000; // 24 hours

  // Initialize cache service
  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    
    // Only initialize file cache on platforms that support it
    if (!kIsWeb) {
      try {
        _cacheDir = await getTemporaryDirectory();
      } catch (e) {
        if (kDebugMode) {
          debugPrint(('Warning: Could not initialize file cache directory: $e').toString());
        }
      }
    }
  }

  // User Profile Cache
  Future<void> cacheUserProfile(Map<String, dynamic> profile) async {
    await _cacheWithExpiry(_userProfileKey, profile, _mediumCacheExpiry);
  }

  Future<Map<String, dynamic>?> getCachedUserProfile() async {
    return await _getCachedData(_userProfileKey);
  }

  Future<void> clearUserProfileCache() async {
    await _clearCache(_userProfileKey);
  }

  // Feed Posts Cache
  Future<void> cacheFeedPosts(List<Map<String, dynamic>> posts, {String? userId}) async {
    final key = userId != null ? '${_feedPostsKey}_$userId' : _feedPostsKey;
    await _cacheWithExpiry(key, posts, _shortCacheExpiry);
  }

  Future<List<Map<String, dynamic>>?> getCachedFeedPosts({String? userId}) async {
    final key = userId != null ? '${_feedPostsKey}_$userId' : _feedPostsKey;
    final data = await _getCachedData(key);
    return data != null ? List<Map<String, dynamic>>.from(data) : null;
  }

  Future<void> clearFeedPostsCache({String? userId}) async {
    final key = userId != null ? '${_feedPostsKey}_$userId' : _feedPostsKey;
    await _clearCache(key);
  }

  // User Posts Cache
  Future<void> cacheUserPosts(String userId, List<Map<String, dynamic>> posts) async {
    final key = '${_userPostsKey}_$userId';
    await _cacheWithExpiry(key, posts, _mediumCacheExpiry);
  }

  Future<List<Map<String, dynamic>>?> getCachedUserPosts(String userId) async {
    final key = '${_userPostsKey}_$userId';
    final data = await _getCachedData(key);
    return data != null ? List<Map<String, dynamic>>.from(data) : null;
  }

  Future<void> clearUserPostsCache(String userId) async {
    final key = '${_userPostsKey}_$userId';
    await _clearCache(key);
  }

  // Followers Cache
  Future<void> cacheFollowers(String userId, List<Map<String, dynamic>> followers) async {
    final key = '${_followersKey}_$userId';
    await _cacheWithExpiry(key, followers, _mediumCacheExpiry);
  }

  Future<List<Map<String, dynamic>>?> getCachedFollowers(String userId) async {
    final key = '${_followersKey}_$userId';
    final data = await _getCachedData(key);
    return data != null ? List<Map<String, dynamic>>.from(data) : null;
  }

  // Following Cache
  Future<void> cacheFollowing(String userId, List<Map<String, dynamic>> following) async {
    final key = '${_followingKey}_$userId';
    await _cacheWithExpiry(key, following, _mediumCacheExpiry);
  }

  Future<List<Map<String, dynamic>>?> getCachedFollowing(String userId) async {
    final key = '${_followingKey}_$userId';
    final data = await _getCachedData(key);
    return data != null ? List<Map<String, dynamic>>.from(data) : null;
  }

  // Notifications Cache
  Future<void> cacheNotifications(String userId, List<Map<String, dynamic>> notifications) async {
    final key = '${_notificationsKey}_$userId';
    await _cacheWithExpiry(key, notifications, _shortCacheExpiry);
  }

  Future<List<Map<String, dynamic>>?> getCachedNotifications(String userId) async {
    final key = '${_notificationsKey}_$userId';
    final data = await _getCachedData(key);
    return data != null ? List<Map<String, dynamic>>.from(data) : null;
  }

  // Search History Cache
  Future<void> addToSearchHistory(String query) async {
    final history = await getSearchHistory();
    
    // Remove if already exists
    history.removeWhere((item) => item.toLowerCase() == query.toLowerCase());
    
    // Add to beginning
    history.insert(0, query);
    
    // Keep only last 20 searches
    if (history.length > 20) {
      history.removeRange(20, history.length);
    }
    
    await _prefs?.setStringList(_searchHistoryKey, history);
  }

  Future<List<String>> getSearchHistory() async {
    return _prefs?.getStringList(_searchHistoryKey) ?? [];
  }

  Future<void> clearSearchHistory() async {
    await _prefs?.remove(_searchHistoryKey);
  }

  // App Settings Cache
  Future<void> cacheAppSettings(Map<String, dynamic> settings) async {
    await _prefs?.setString(_settingsKey, jsonEncode(settings));
  }

  Future<Map<String, dynamic>?> getCachedAppSettings() async {
    final settingsString = _prefs?.getString(_settingsKey);
    if (settingsString != null) {
      try {
        return Map<String, dynamic>.from(jsonDecode(settingsString));
      } catch (e) {
        if (kDebugMode) {
          debugPrint(('Error decoding app settings: $e').toString());
        }
      }
    }
    return null;
  }

  // Content Drafts Cache
  Future<void> saveDraft({
    required String type,
    required Map<String, dynamic> draftData,
    String? draftId,
  }) async {
    final drafts = await getDrafts();
    final id = draftId ?? DateTime.now().millisecondsSinceEpoch.toString();
    
    drafts[id] = {
      'id': id,
      'type': type,
      'data': draftData,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    };
    
    await _prefs?.setString(_draftsKey, jsonEncode(drafts));
  }

  Future<Map<String, dynamic>> getDrafts() async {
    final draftsString = _prefs?.getString(_draftsKey);
    if (draftsString != null) {
      try {
        return Map<String, dynamic>.from(jsonDecode(draftsString));
      } catch (e) {
        if (kDebugMode) {
          debugPrint(('Error decoding drafts: $e').toString());
        }
      }
    }
    return {};
  }

  Future<Map<String, dynamic>?> getDraft(String draftId) async {
    final drafts = await getDrafts();
    return drafts[draftId];
  }

  Future<void> deleteDraft(String draftId) async {
    final drafts = await getDrafts();
    drafts.remove(draftId);
    await _prefs?.setString(_draftsKey, jsonEncode(drafts));
  }

  Future<void> clearAllDrafts() async {
    await _prefs?.remove(_draftsKey);
  }

  // File Cache (for images, videos, etc.)
  Future<void> cacheFile(String url, List<int> bytes) async {
    // File caching not supported on web platform
    if (_cacheDir == null || kIsWeb) {
      if (kDebugMode) {
        debugPrint(('File caching not available on this platform').toString());
      }
      return;
    }
    
    try {
      final fileName = _getFileNameFromUrl(url);
      final file = File('${_cacheDir!.path}/$fileName');
      await file.writeAsBytes(bytes);
      
      // Store metadata
      await _prefs?.setInt('cache_${fileName}_timestamp', DateTime.now().millisecondsSinceEpoch);
      await _prefs?.setString('cache_${fileName}_url', url);
    } catch (e) {
      if (kDebugMode) {
        debugPrint(('Error caching file: $e').toString());
      }
    }
  }

  Future<File?> getCachedFile(String url) async {
    // File caching not supported on web platform
    if (_cacheDir == null || kIsWeb) {
      return null;
    }
    
    try {
      final fileName = _getFileNameFromUrl(url);
      final file = File('${_cacheDir!.path}/$fileName');
      
      if (await file.exists()) {
        // Check if cache is still valid (24 hours)
        final timestamp = _prefs?.getInt('cache_${fileName}_timestamp') ?? 0;
        final now = DateTime.now().millisecondsSinceEpoch;
        
        if (now - timestamp < _longCacheExpiry) {
          return file;
        } else {
          // Cache expired, delete file
          await file.delete();
          await _prefs?.remove('cache_${fileName}_timestamp');
          await _prefs?.remove('cache_${fileName}_url');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint(('Error getting cached file: $e').toString());
      }
    }
    
    return null;
  }

  // Cache management
  Future<void> clearExpiredCache() async {
    final keys = _prefs?.getKeys() ?? <String>{};
    final now = DateTime.now().millisecondsSinceEpoch;
    
    for (final key in keys) {
      if (key.endsWith('_timestamp')) {
        final timestamp = _prefs?.getInt(key) ?? 0;
        final dataKey = key.replaceAll('_timestamp', '');
        
        // Check if cache has expired
        if (now - timestamp > _longCacheExpiry) {
          await _prefs?.remove(key);
          await _prefs?.remove(dataKey);
        }
      }
    }
    
    // Clean up cached files
    await _cleanupCachedFiles();
  }

  Future<void> clearAllCache() async {
    // Clear SharedPreferences cache
    final keys = _prefs?.getKeys() ?? <String>{};
    final keysToRemove = keys.where((key) => 
        key.startsWith(_userProfileKey) ||
        key.startsWith(_feedPostsKey) ||
        key.startsWith(_userPostsKey) ||
        key.startsWith(_followersKey) ||
        key.startsWith(_followingKey) ||
        key.startsWith(_notificationsKey) ||
        key.startsWith('cache_')
    ).toList();
    
    for (final key in keysToRemove) {
      await _prefs?.remove(key);
    }
    
    // Clear cached files
    await _cleanupCachedFiles();
  }

  Future<int> getCacheSize() async {
    int totalSize = 0;
    
    // Calculate SharedPreferences size (approximate)
    final keys = _prefs?.getKeys() ?? <String>{};
    for (final key in keys) {
      final value = _prefs?.get(key);
      if (value is String) {
        totalSize += value.length * 2; // UTF-16 encoding
      }
    }
    
    // Calculate cached files size (not available on web)
    if (!kIsWeb && _cacheDir != null && await _cacheDir!.exists()) {
      final files = _cacheDir!.listSync();
      for (final file in files) {
        if (file is File) {
          totalSize += await file.length();
        }
      }
    }
    
    return totalSize;
  }

  String formatCacheSize(int bytes) {
    if (bytes <= 0) return '0 B';
    
    const suffixes = ['B', 'KB', 'MB', 'GB'];
    final i = (bytes.bitLength - 1) ~/ 10;
    
    if (i >= suffixes.length) {
      return '${(bytes / (1 << ((suffixes.length - 1) * 10))).toStringAsFixed(1)} ${suffixes.last}';
    }
    
    return '${(bytes / (1 << (i * 10))).toStringAsFixed(1)} ${suffixes[i]}';
  }

  // Private helper methods
  Future<void> _cacheWithExpiry(String key, dynamic data, int expiryMs) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    await _prefs?.setString(key, jsonEncode(data));
    await _prefs?.setInt('${key}_timestamp', timestamp);
  }

  Future<dynamic> _getCachedData(String key) async {
    final timestamp = _prefs?.getInt('${key}_timestamp') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    
    // Check if cache has expired
    if (now - timestamp > _longCacheExpiry) {
      await _clearCache(key);
      return null;
    }
    
    final dataString = _prefs?.getString(key);
    if (dataString != null) {
      try {
        return jsonDecode(dataString);
      } catch (e) {
        if (kDebugMode) {
          debugPrint(('Error decoding cached data for key $key: $e').toString());
        }
        await _clearCache(key);
      }
    }
    
    return null;
  }

  Future<void> _clearCache(String key) async {
    await _prefs?.remove(key);
    await _prefs?.remove('${key}_timestamp');
  }

  String _getFileNameFromUrl(String url) {
    final uri = Uri.parse(url);
    final segments = uri.pathSegments;
    if (segments.isNotEmpty) {
      return segments.last;
    }
    return url.hashCode.toString();
  }

  Future<void> _cleanupCachedFiles() async {
    // File cleanup not needed on web platform
    if (_cacheDir == null || kIsWeb || !await _cacheDir!.exists()) return;
    
    try {
      final files = _cacheDir!.listSync();
      final now = DateTime.now().millisecondsSinceEpoch;
      
      for (final file in files) {
        if (file is File) {
          final fileName = file.path.split('/').last;
          final timestamp = _prefs?.getInt('cache_${fileName}_timestamp') ?? 0;
          
          // Delete files older than 24 hours
          if (now - timestamp > _longCacheExpiry) {
            await file.delete();
            await _prefs?.remove('cache_${fileName}_timestamp');
            await _prefs?.remove('cache_${fileName}_url');
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint(('Error cleaning up cached files: $e').toString());
      }
    }
  }

  // Specific cache invalidation methods
  Future<void> invalidateUserCache(String userId) async {
    await clearUserPostsCache(userId);
    await _clearCache('${_followersKey}_$userId');
    await _clearCache('${_followingKey}_$userId');
    await _clearCache('${_notificationsKey}_$userId');
  }

  Future<void> invalidatePostCache(String postId) async {
    // Clear feed caches that might contain this post
    final keys = _prefs?.getKeys() ?? <String>{};
    final feedKeys = keys.where((key) => key.startsWith(_feedPostsKey)).toList();
    
    for (final key in feedKeys) {
      await _clearCache(key);
    }
  }

  // Preload cache for better performance
  Future<void> preloadUserData(String userId) async {
    // This method can be called to preload user data in the background
    // Implementation would depend on your specific needs
  }
}
