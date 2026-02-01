import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../config/supabase_config.dart';
import '../config/api_config.dart';
import '../utils/auth_test.dart';
import 'auth_service.dart';
import 'database_service.dart';
import 'storage_service.dart';
import 'cache_service.dart';
import 'analytics_service.dart';
import 'social_service.dart';
import 'content_service.dart';
import 'push_notification_service.dart';
import 'musicbrainz_service.dart';
import 'audio_fingerprinting_service.dart';
import 'package:http/http.dart' as http;
import 'video_audio_extractor.dart' as vae;

class AppService {
  static final AppService _instance = AppService._internal();
  factory AppService() => _instance;
  AppService._internal();

  // Service instances
  late final AuthService _authService;
  late final DatabaseService _databaseService;
  late final StorageService _storageService;
  late final CacheService _cacheService;
  late final AnalyticsService _analyticsService;
  late final SocialService _socialService;
  late final ContentService _contentService;

  // App state
  bool _isInitialized = false;
  bool _isOnline = true;
  bool _isPasswordRecoveryInProgress = false;
  String? _currentUserId;
  Map<String, dynamic>? _currentUser;

  // Stream controllers for app-wide state
  final _appStateController = StreamController<AppState>.broadcast();
  final _connectivityController = StreamController<bool>.broadcast();
  final _userController = StreamController<Map<String, dynamic>?>.broadcast();

  // Getters
  bool get isInitialized => _isInitialized;
  bool get isOnline => _isOnline;
  String? get currentUserId => _currentUserId;
  Map<String, dynamic>? get currentUser => _currentUser;

  // Service getters
  AuthService get auth => _authService;
  DatabaseService get database => _databaseService;
  StorageService get storage => _storageService;
  CacheService get cache => _cacheService;
  AnalyticsService get analytics => _analyticsService;
  SocialService get social => _socialService;
  ContentService get content => _contentService;

  // Streams
  Stream<AppState> get appStateStream => _appStateController.stream;
  Stream<bool> get connectivityStream => _connectivityController.stream;
  Stream<Map<String, dynamic>?> get userStream => _userController.stream;

  // Initialize the app
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _emitAppState(AppState.initializing);

      // Initialize Supabase with timeout
      await SupabaseConfig.initialize().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          if (kDebugMode) {
            debugPrint(
              ('Supabase initialization timed out - continuing with offline mode')
                  .toString(),
            );
          }
        },
      );

      // Test Supabase connection with timeout
      if (kDebugMode) {
        try {
          await AuthTest.printAuthDiagnostics().timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              debugPrint(('Auth diagnostics timed out').toString());
            },
          );
        } catch (e) {
          debugPrint(('Auth diagnostics failed: $e').toString());
        }
      }

      // Load remote configuration (API keys, etc.)
      try {
        await ApiConfig.loadRemoteConfig().timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            if (kDebugMode) {
              debugPrint('Remote config loading timed out');
            }
          },
        );
      } catch (e) {
        if (kDebugMode) {
          debugPrint('Remote config loading failed: $e');
        }
      }

      try {
        final connectionTest = await AuthTest.testSupabaseConnection().timeout(
          const Duration(seconds: 5),
          onTimeout: () => false,
        );
        if (!connectionTest) {
          if (kDebugMode) {
            debugPrint(
              ('Warning: Supabase connection test failed. App may not function properly.')
                  .toString(),
            );
          }
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint(('Connection test failed: $e').toString());
        }
      }

      // Initialize services
      _authService = AuthService();
      _databaseService = DatabaseService();
      _storageService = StorageService();
      _cacheService = CacheService();
      _analyticsService = AnalyticsService();
      _socialService = SocialService();
      _contentService = ContentService();

      // Initialize cache service with error handling
      try {
        await _cacheService.initialize().timeout(const Duration(seconds: 5));
      } catch (e) {
        if (kDebugMode) {
          debugPrint(('Cache service initialization failed: $e').toString());
        }
      }

      // Initialize analytics with error handling
      try {
        await _analyticsService.initialize().timeout(
          const Duration(seconds: 5),
        );
      } catch (e) {
        if (kDebugMode) {
          debugPrint(
            ('Analytics service initialization failed: $e').toString(),
          );
        }
      }

      // Set up auth state listener with error handling
      try {
        _setupAuthStateListener();
      } catch (e) {
        if (kDebugMode) {
          debugPrint(('Auth state listener setup failed: $e').toString());
        }
      }

      // Set up connectivity monitoring with error handling
      try {
        _setupConnectivityMonitoring();
      } catch (e) {
        if (kDebugMode) {
          debugPrint(('Connectivity monitoring setup failed: $e').toString());
        }
      }

      // Clean up expired cache with error handling
      try {
        await _cacheService.clearExpiredCache().timeout(
          const Duration(seconds: 3),
        );
      } catch (e) {
        if (kDebugMode) {
          debugPrint(('Cache cleanup failed: $e').toString());
        }
      }

      _isInitialized = true;
      _emitAppState(AppState.ready);

      if (kDebugMode) {
        debugPrint('App services initialized successfully');
      }
    } catch (e) {
      _emitAppState(AppState.error);
      await _analyticsService.trackError('app_initialization', e.toString());
      rethrow;
    }
  }

  // User authentication and session management
  Future<void> signIn(String email, String password) async {
    try {
      _emitAppState(AppState.authenticating);

      final response = await _authService.signIn(
        email: email,
        password: password,
      );
      await _handleAuthSuccess(response.user!);

      await _analyticsService.trackLogin('email');
    } catch (e) {
      _emitAppState(AppState.ready);
      await _analyticsService.trackError('sign_in', e.toString());
      rethrow;
    }
  }

  Future<void> signUp(String email, String password, String username) async {
    try {
      _emitAppState(AppState.authenticating);

      await _authService.signUp(
        email: email,
        password: password,
        fullName: username,
        username: username,
      );

      // Do not handle auth success as we require email verification
      // Ensure state is reset to ready
      _emitAppState(AppState.ready);

      await _analyticsService.trackSignup('email');
    } catch (e) {
      _emitAppState(AppState.ready);
      await _analyticsService.trackError('sign_up', e.toString());
      rethrow;
    }
  }

  Future<void> signOut() async {
    try {
      _emitAppState(AppState.signingOut);

      // Capture user ID before clearing it to allow cleanup
      final previousUserId = _currentUserId;

      // Immediately mark unauthenticated and update UI state
      await _handleAuthSignOut();

      // Perform cleanup without blocking UI/navigation; schedule on event queue
      Future(() async {
        try {
          if (previousUserId != null) {
            await _cacheService.invalidateUserCache(previousUserId);
          }
          await _databaseService.dispose();

          // Sign out from Supabase session (network) after UI transition
          await _authService.signOut();
          await _analyticsService.trackLogout();
        } catch (e) {
          await _analyticsService.trackError('sign_out_cleanup', e.toString());
        }
      });
    } catch (e) {
      _emitAppState(AppState.ready);
      await _analyticsService.trackError('sign_out', e.toString());
      rethrow;
    }
  }

  // User profile management
  Future<void> updateUserProfile(Map<String, dynamic> updates) async {
    try {
      if (_currentUserId == null) throw Exception('User not authenticated');

      await _authService.updateProfile(
        fullName:
            updates['display_name'], // Fixed: use display_name instead of full_name
        username: updates['username'],
        bio: updates['bio'],
        avatarUrl: updates['avatar_url'],
      );

      // Fetch updated user profile
      _currentUser = await _authService.getCurrentUserProfile();
      _userController.add(_currentUser);

      // Update cache
      if (_currentUser != null) {
        await _cacheService.cacheUserProfile(_currentUser!);
      }

      await _analyticsService.trackFeatureUsed(
        'profile_update',
        properties: {'fields_updated': updates.keys.toList()},
      );
    } catch (e) {
      await _analyticsService.trackError('profile_update', e.toString());
      rethrow;
    }
  }

  Future<void> uploadAvatar(dynamic imageFile) async {
    try {
      if (_currentUserId == null) throw Exception('User not authenticated');

      String avatarUrl;

      if (kIsWeb && imageFile is XFile) {
        // Web upload: read bytes from XFile
        final bytes = await imageFile.readAsBytes();
        final fileName = imageFile.name;

        avatarUrl = await _storageService.uploadAvatar(
          userId: _currentUserId!,
          avatarBytes: bytes,
          fileName: fileName,
        );
      } else {
        // Mobile upload: use File directly
        avatarUrl = await _storageService.uploadAvatar(
          avatarFile: imageFile,
          userId: _currentUserId!,
        );
      }

      await updateUserProfile({'avatar_url': avatarUrl});

      await _analyticsService.trackFeatureUsed('avatar_upload');
    } catch (e) {
      await _analyticsService.trackError('avatar_upload', e.toString());
      rethrow;
    }
  }

  // Content management
  Future<Map<String, dynamic>> createPost({
    required String type,
    String? caption,
    dynamic mediaFile,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      if (_currentUserId == null) throw Exception('User not authenticated');

      String? mediaUrl;
      String? thumbnailUrl;
      Map<String, dynamic>? aiMetadata;
      String? musicId;

      // Upload media if provided (skip for text-only posts)
      if (mediaFile != null && type != 'text') {
        switch (type) {
          case 'video':
            if (kIsWeb) {
              Uint8List? videoBytes;
              String? videoFileName;
              // Handle various web inputs: Uint8List, PlatformFile, or Map
              if (mediaFile is Uint8List) {
                videoBytes = mediaFile;
                // Try metadata for fileName if provided
                videoFileName = metadata != null
                    ? metadata['fileName'] as String?
                    : null;
              } else if (mediaFile is PlatformFile) {
                videoBytes = mediaFile.bytes;
                videoFileName = mediaFile.name;
              } else if (mediaFile is Map) {
                final mf = mediaFile;
                final b = mf['bytes'];
                final n = mf['fileName'];
                if (b is Uint8List) videoBytes = b;
                if (n is String) videoFileName = n;
              }

              if (videoBytes == null || videoFileName == null) {
                throw Exception(
                  'On web, provide video bytes and fileName for upload',
                );
              }

              final urls = await _storageService.uploadVideo(
                videoFile: null,
                userId: _currentUserId!,
                videoBytes: videoBytes,
                videoFileName: videoFileName,
              );
              mediaUrl = urls['videoUrl'];
              thumbnailUrl = urls['thumbnailUrl'];
            } else {
              final urls = await _storageService.uploadVideo(
                videoFile: mediaFile,
                userId: _currentUserId!,
              );
              mediaUrl = urls['videoUrl'];
              thumbnailUrl = urls['thumbnailUrl'];
            }
            break;
          case 'image':
            if (kIsWeb) {
              Uint8List? imageBytes;
              String? imageFileName;
              // Handle various web inputs: Uint8List, PlatformFile, or Map
              if (mediaFile is Uint8List) {
                imageBytes = mediaFile;
                imageFileName = metadata != null
                    ? metadata['fileName'] as String?
                    : null;
              } else if (mediaFile is PlatformFile) {
                imageBytes = mediaFile.bytes;
                imageFileName = mediaFile.name;
              } else if (mediaFile is Map) {
                final mf = mediaFile;
                final b = mf['bytes'];
                final n = mf['fileName'];
                if (b is Uint8List) imageBytes = b;
                if (n is String) imageFileName = n;
              }

              if (imageBytes == null || imageFileName == null) {
                throw Exception(
                  'On web, provide image bytes and fileName for upload',
                );
              }

              mediaUrl = await _storageService.uploadImage(
                imageFile: null,
                userId: _currentUserId!,
                imageBytes: imageBytes,
                fileName: imageFileName,
              );
            } else {
              mediaUrl = await _storageService.uploadImage(
                imageFile: mediaFile,
                userId: _currentUserId!,
              );
            }
            break;
          case 'audio':
            if (kIsWeb) {
              Uint8List? audioBytes;
              String? audioFileName;
              // Handle various web inputs: Uint8List, PlatformFile, or Map
              if (mediaFile is Uint8List) {
                audioBytes = mediaFile;
                audioFileName = metadata != null
                    ? metadata['fileName'] as String?
                    : null;
              } else if (mediaFile is PlatformFile) {
                audioBytes = mediaFile.bytes;
                audioFileName = mediaFile.name;
              } else if (mediaFile is Map) {
                final mf = mediaFile;
                final b = mf['bytes'];
                final n = mf['fileName'];
                if (b is Uint8List) audioBytes = b;
                if (n is String) audioFileName = n;
              }

              if (audioBytes == null || audioFileName == null) {
                throw Exception(
                  'On web, provide audio bytes and fileName for upload',
                );
              }

              // Upload audio
              mediaUrl = await _storageService.uploadAudio(
                audioFile: null,
                userId: _currentUserId!,
                audioBytes: audioBytes,
                fileName: audioFileName,
              );

              // MusicBrainz detection via metadata + MB search
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
              // Prefer fingerprinting from WAV PCM snippet for reliability
              Map<String, dynamic>? fp;
              // Try multiple offsets to improve match likelihood
              for (final offset in [0, 15, 45]) {
                try {
                  final wav =
                      await vae
                          .VideoAudioExtractor.extractWavSnippetFromAudioBytes(
                        audioBytes,
                        seconds: 20,
                        offsetSeconds: offset,
                      );
                  fp = await AudioFingerprintService().detectFromBytes(
                    wav,
                    fileName: 'audio_snippet.wav',
                  );
                  if (fp != null) break;
                } catch (_) {}
              }
              if (fp != null) {
                aiMetadata = {'copyright_detection': fp};
                if (musicId == null && fp['recordingId'] is String) {
                  musicId = fp['recordingId'] as String;
                }
              } else {
                // MusicBrainz detection via metadata + MB search
                final detection = await MusicBrainzService().detect(
                  bytes: audioBytes,
                  fileName: audioFileName,
                  titleHint: titleHint,
                  artistHint: artistHint,
                );
                aiMetadata = {'copyright_detection': detection};
                if (detection != null &&
                    detection['match'] == true &&
                    detection['recordingId'] is String) {
                  musicId = detection['recordingId'] as String;
                }
                // Fingerprinting fallback when MB detection fails or low confidence
                final mbConfidence =
                    detection != null && detection['confidence'] is num
                    ? (detection['confidence'] as num).toDouble()
                    : 0.0;
                if (detection == null || mbConfidence < 0.4) {
                  try {
                    Map<String, dynamic>? fp2;
                    for (final offset in [0, 15, 45]) {
                      try {
                        final wav2 =
                            await vae
                                .VideoAudioExtractor.extractWavSnippetFromAudioBytes(
                              audioBytes,
                              seconds: 20,
                              offsetSeconds: offset,
                            );
                        fp2 = await AudioFingerprintService().detectFromBytes(
                          wav2,
                          fileName: 'audio_snippet.wav',
                        );
                        if (fp2 != null) break;
                      } catch (_) {}
                    }
                    if (fp2 != null) {
                      aiMetadata = {'copyright_detection': fp2};
                      if (musicId == null && fp2['recordingId'] is String) {
                        musicId = fp2['recordingId'] as String;
                      }
                    }
                  } catch (_) {}
                }
              }
            } else {
              // Mobile: upload first, then fetch bytes from uploaded URL for detection
              mediaUrl = await _storageService.uploadAudio(
                audioFile: mediaFile,
                userId: _currentUserId!,
              );
              try {
                if (mediaUrl != null) {
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
                      .timeout(const Duration(seconds: 10));
                  if (resp.statusCode == 200) {
                    // Prefer fingerprint from WAV snippet
                    Map<String, dynamic>? fp;
                    for (final offset in [0, 15, 45]) {
                      try {
                        final wav =
                            await vae
                                .VideoAudioExtractor.extractWavSnippetFromAudioBytes(
                              resp.bodyBytes,
                              seconds: 20,
                              offsetSeconds: offset,
                            );
                        fp = await AudioFingerprintService().detectFromBytes(
                          wav,
                          fileName: 'audio_snippet.wav',
                        );
                        if (fp != null) break;
                      } catch (_) {}
                    }
                    if (fp != null) {
                      aiMetadata = {'copyright_detection': fp};
                      if (musicId == null && fp['recordingId'] is String) {
                        musicId = fp['recordingId'] as String;
                      }
                    } else {
                      final detection = await MusicBrainzService().detect(
                        bytes: resp.bodyBytes,
                        fileName: mediaUrl.split('/').last,
                        titleHint: titleHint,
                        artistHint: artistHint,
                      );
                      aiMetadata = {'copyright_detection': detection};
                      if (detection != null &&
                          detection['match'] == true &&
                          detection['recordingId'] is String) {
                        musicId = detection['recordingId'] as String;
                      }
                      final mbConfidence2 =
                          detection != null && detection['confidence'] is num
                          ? (detection['confidence'] as num).toDouble()
                          : 0.0;
                      if (detection == null || mbConfidence2 < 0.4) {
                        try {
                          Map<String, dynamic>? fp2;
                          for (final offset in [0, 15, 45]) {
                            try {
                              final wav2 =
                                  await vae
                                      .VideoAudioExtractor.extractWavSnippetFromAudioBytes(
                                    resp.bodyBytes,
                                    seconds: 20,
                                    offsetSeconds: offset,
                                  );
                              fp2 = await AudioFingerprintService()
                                  .detectFromBytes(
                                    wav2,
                                    fileName: 'audio_snippet.wav',
                                  );
                              if (fp2 != null) break;
                            } catch (_) {}
                          }
                          if (fp2 != null) {
                            aiMetadata = {'copyright_detection': fp2};
                            if (musicId == null &&
                                fp2['recordingId'] is String) {
                              musicId = fp2['recordingId'] as String;
                            }
                          }
                        } catch (_) {}
                      }
                    }
                  }
                }
              } catch (_) {}
            }
            break;
        }
      }

      // For text posts, ensure caption is provided
      if (type == 'text' && (caption == null || caption.trim().isEmpty)) {
        throw Exception('Text posts require content');
      }

      // Extract hashtags from caption if present
      List<String>? hashtags;
      if (caption != null) {
        final hashtagRegex = RegExp(r'#\w+');
        final matches = hashtagRegex.allMatches(caption);
        hashtags = matches
            .map((match) => match.group(0)!.substring(1))
            .toList();
      }

      // Create post in database
      final post = await _databaseService.createPost(
        userId: _currentUserId!,
        type: type,
        caption: caption,
        mediaUrl: mediaUrl,
        thumbnailUrl: thumbnailUrl,
        hashtags: hashtags,
        aiMetadata: aiMetadata,
        musicId: musicId,
      );

      // Clear relevant caches
      await _cacheService.clearFeedPostsCache();
      await _cacheService.clearUserPostsCache(_currentUserId!);

      await _analyticsService.trackPostCreate(type, metadata);

      return post;
    } catch (e) {
      await _analyticsService.trackError('post_create', e.toString());
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getFeedPosts({
    int limit = 20,
    int offset = 0,
    bool useCache = true,
  }) async {
    try {
      // Try cache first if enabled
      if (useCache && offset == 0) {
        final cachedPosts = await _cacheService.getCachedFeedPosts(
          userId: _currentUserId,
        );
        if (cachedPosts != null && cachedPosts.isNotEmpty) {
          return cachedPosts;
        }
      }

      // Fetch from database
      final posts = await _databaseService.getFeedPosts(
        userId: _currentUserId,
        limit: limit,
        offset: offset,
      );

      // Cache the results
      if (offset == 0) {
        await _cacheService.cacheFeedPosts(posts, userId: _currentUserId);
      }

      return posts;
    } catch (e) {
      await _analyticsService.trackError('feed_fetch', e.toString());
      rethrow;
    }
  }

  // Social interactions
  Future<void> likePost(String postId, String postType) async {
    try {
      if (_currentUserId == null) throw Exception('User not authenticated');

      await _databaseService.likePost(postId, _currentUserId!);

      // Invalidate relevant caches
      await _cacheService.invalidatePostCache(postId);

      await _analyticsService.trackPostLike(postId, postType);
    } catch (e) {
      await _analyticsService.trackError('post_like', e.toString());
      rethrow;
    }
  }

  Future<void> unlikePost(String postId, String postType) async {
    try {
      if (_currentUserId == null) throw Exception('User not authenticated');

      await _databaseService.unlikePost(postId, _currentUserId!);

      // Invalidate relevant caches
      await _cacheService.invalidatePostCache(postId);

      await _analyticsService.trackPostUnlike(postId, postType);
    } catch (e) {
      await _analyticsService.trackError('post_unlike', e.toString());
      rethrow;
    }
  }

  Future<void> trackUser(String targetUserId) async {
    try {
      if (_currentUserId == null) throw Exception('User not authenticated');

      await _databaseService.trackUser(_currentUserId!, targetUserId);

      // Invalidate relevant caches
      await _cacheService.invalidateUserCache(_currentUserId!);
      await _cacheService.invalidateUserCache(targetUserId);

      await _analyticsService.trackUserTrack(targetUserId);
    } catch (e) {
      await _analyticsService.trackError('user_track', e.toString());
      rethrow;
    }
  }

  Future<void> untrackUser(String targetUserId) async {
    try {
      if (_currentUserId == null) throw Exception('User not authenticated');

      await _databaseService.untrackUser(_currentUserId!, targetUserId);

      // Invalidate relevant caches
      await _cacheService.invalidateUserCache(_currentUserId!);
      await _cacheService.invalidateUserCache(targetUserId);

      await _analyticsService.trackUserUntrack(targetUserId);
    } catch (e) {
      await _analyticsService.trackError('user_untrack', e.toString());
      rethrow;
    }
  }

  // Search functionality
  Future<Map<String, List<Map<String, dynamic>>>> search(String query) async {
    try {
      final users = await _databaseService.searchUsers(query);
      final posts = await _socialService.searchPosts(query);

      await _cacheService.addToSearchHistory(query);
      await _analyticsService.trackSearch(
        query,
        'combined',
        users.length + posts.length,
      );

      return {'users': users, 'posts': posts};
    } catch (e) {
      await _analyticsService.trackError('search', e.toString());
      rethrow;
    }
  }

  // App lifecycle management
  Future<void> onAppPaused() async {
    try {
      // Save any pending data
      await _cacheService.clearExpiredCache();

      // End analytics session
      await _analyticsService.endSession();
    } catch (e) {
      if (kDebugMode) {
        debugPrint(('Error handling app pause: $e').toString());
      }
    }
  }

  Future<void> onAppResumed() async {
    try {
      // Restart analytics session
      await _analyticsService.initialize();

      // Refresh user data if needed
      if (_currentUserId != null) {
        await _refreshUserData();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint(('Error handling app resume: $e').toString());
      }
    }
  }

  // Settings management
  Future<void> updateAppSettings(Map<String, dynamic> settings) async {
    try {
      await _cacheService.cacheAppSettings(settings);

      await _analyticsService.trackFeatureUsed(
        'settings_update',
        properties: {'settings_changed': settings.keys.toList()},
      );
    } catch (e) {
      await _analyticsService.trackError('settings_update', e.toString());
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> getAppSettings() async {
    try {
      return await _cacheService.getCachedAppSettings();
    } catch (e) {
      await _analyticsService.trackError('settings_fetch', e.toString());
      return null;
    }
  }

  // Cleanup and disposal
  Future<void> dispose() async {
    try {
      await _analyticsService.dispose();
      await _databaseService.dispose();

      _appStateController.close();
      _connectivityController.close();
      _userController.close();
    } catch (e) {
      if (kDebugMode) {
        debugPrint(('Error disposing app service: $e').toString());
      }
    }
  }

  // Handle manual password recovery trigger
  void handlePasswordRecovery() {
    _isPasswordRecoveryInProgress = true;
    _emitAppState(AppState.passwordRecovery);
  }

  // Set recovery flag without emitting state (useful for OTP flow)
  void setRecoveryInProgress(bool value) {
    _isPasswordRecoveryInProgress = value;
  }

  void completePasswordRecovery() {
    _isPasswordRecoveryInProgress = false;
    if (_currentUserId != null) {
      _emitAppState(AppState.authenticated);
    } else {
      _emitAppState(AppState.unauthenticated);
    }
  }

  // Private helper methods
  void _setupAuthStateListener() {
    _authService.authStateChanges.listen((authState) async {
      final user = authState.session?.user;

      // Handle password recovery event specifically
      if (authState.event == AuthChangeEvent.passwordRecovery) {
        _emitAppState(AppState.passwordRecovery);
        return;
      }

      if (user != null) {
        await _handleAuthSuccess(user);
      } else {
        await _handleAuthSignOut();
      }
    });
  }

  void _setupConnectivityMonitoring() {
    // In a real app, you'd use connectivity_plus package
    // For now, we'll assume online connectivity
    _isOnline = true;
    _connectivityController.add(_isOnline);
  }

  Future<void> _handleAuthSuccess(User user) async {
    _currentUserId = user.id;

    // Fetch user profile
    _currentUser = await _authService.getCurrentUserProfile();
    _userController.add(_currentUser);

    // Initialize real-time subscriptions
    await _databaseService.initializeRealtime(user.id);

    // Cache user profile
    if (_currentUser != null) {
      await _cacheService.cacheUserProfile(_currentUser!);
    }

    if (_isPasswordRecoveryInProgress) {
      _emitAppState(AppState.passwordRecovery);
    } else {
      _emitAppState(AppState.authenticated);
    }
  }

  Future<void> _handleAuthSignOut() async {
    _currentUserId = null;
    _currentUser = null;
    _userController.add(null);

    // Emit unauthenticated immediately so UI can transition without waiting
    _emitAppState(AppState.unauthenticated);

    // Immediately navigate to Login and clear the stack to avoid hanging on previous screen
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        PushNotificationService.navigatorKey.currentState
            ?.pushNamedAndRemoveUntil('/login', (route) => false);
      } catch (e) {
        if (kDebugMode) {
          debugPrint(
            ('AppService: Failed to navigate to login after sign-out: $e')
                .toString(),
          );
        }
      }
    });

    // Clear user-specific cache and other cleanup without blocking the UI
    Future(() async {
      try {
        await _cacheService.clearAllCache();
      } catch (e) {
        if (kDebugMode) {
          debugPrint(('Error clearing cache on sign-out: $e').toString());
        }
      }
    });
  }

  Future<void> _refreshUserData() async {
    if (_currentUserId == null) return;

    try {
      _currentUser = await _authService.getCurrentUserProfile();
      _userController.add(_currentUser);

      if (_currentUser != null) {
        await _cacheService.cacheUserProfile(_currentUser!);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint(('Error refreshing user data: $e').toString());
      }
    }
  }

  void _emitAppState(AppState state) {
    if (kDebugMode) {
      debugPrint(('AppService: Emitting app state -> $state').toString());
    }
    _appStateController.add(state);
  }
}

// App state enum
enum AppState {
  initializing,
  ready,
  authenticating,
  authenticated,
  unauthenticated,
  signingOut,
  passwordRecovery,
  error,
}
