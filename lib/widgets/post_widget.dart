import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../services/storage_service.dart';
import '../services/video_filter_service.dart';
import '../models/post_model.dart';
import '../services/preferences_service.dart';
import '../services/auth_service.dart';
import '../services/social_service.dart';
import '../services/posts_service.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/post_detail_screen.dart';
import '../main.dart';
import 'package:flutter/gestures.dart';
import '../services/localization_service.dart';
import '../services/analytics_service.dart';
import '../services/database_service.dart';
import '../services/status_service.dart';
import '../config/app_colors.dart';
import '../config/supabase_config.dart';
import 'dart:math' as math;
import '../widgets/moderation_blur.dart';
import '../services/safe_mode_service.dart';
import '../services/history_service.dart';

class PostWidget extends StatefulWidget {
  final PostModel post;
  final bool isActive;
  // Add session-level mute flag (defaults to false for existing screens)
  final bool muted;

  const PostWidget({
    super.key,
    required this.post,
    required this.isActive,
    this.muted = false,
  });

  @override
  State<PostWidget> createState() => _PostWidgetState();
}

class _PostWidgetState extends State<PostWidget>
    with
        AutomaticKeepAliveClientMixin<PostWidget>,
        WidgetsBindingObserver,
        RouteAware,
        TickerProviderStateMixin {
  VideoPlayerController? _videoController;
  bool _isVideoInitialized = false;
  bool _wasPlayingBeforePause = false;
  bool _isScreenVisible = true;
  // Add init state tracking for video
  bool _isVideoInitializing = false;
  String? _videoInitError;
  PostModel? _parentPost; // Prefetched original post for harmony preview
  bool _isLoadingParent = false;
  // Parent media preview state
  VideoPlayerController? _parentVideoController;
  bool _isParentVideoInitialized = false;
  bool _isParentVideoMuted = true;

  // Audio player variables
  AudioPlayer? _audioPlayer;
  bool _isAudioPlaying = false;
  bool _isAudioInitialized = false;
  Duration _audioDuration = Duration.zero;
  Duration _audioPosition = Duration.zero;
  Timer? _audioSeekTimer;
  // Video tracking for controls
  Duration _videoDuration = Duration.zero;
  Duration _videoPosition = Duration.zero;
  Timer? _videoSeekTimer;
  Timer? _videoInitDebounceTimer;

  // Effective media URL that may replace the original after fallback
  String? _effectiveMediaUrl;

  // Services
  final AuthService _authService = AuthService();
  final SocialService _socialService = SocialService();
  final PostsService _postsService = PostsService();
  final PreferencesService _preferencesService = PreferencesService();
  final AnalyticsService _analyticsService = AnalyticsService();
  final DatabaseService _databaseService = DatabaseService();
  final StatusService _statusService = StatusService.of();
  final SafeModeService _safeModeService = SafeModeService();

  // Preferences
  bool _autoPlayEnabled = true;
  bool _prefsLoaded = false;

  // Track functionality
  bool _isTracking = false;
  bool _isTrackLoading = false;
  // View tracking state
  DateTime? _viewStart;
  bool _hasIncrementedView = false;
  // History recording threshold timer/state
  Timer? _historyTimer;
  bool _historyAdded = false;

  // Audio playback options
  bool _playOriginal = false;

  // Unseen statuses ring state for author
  bool _authorHasUnseenStatuses = false;

  // Safe Mode moderation state
  bool _safeModeEnabled = false;
  bool _contentRevealed = false;

  // Avatar rotation animation for header avatar
  late AnimationController _avatarRotationController;
  late Animation<double> _avatarRotation;
  AnimationStatusListener? _avatarRotationStatusListener;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Initialize avatar rotation animation
    _avatarRotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    );
    _avatarRotation = Tween<double>(
      begin: 0.0,
      end: 2 * math.pi,
    ).animate(_avatarRotationController);
    // Start first forward rotation
    _avatarRotationController.forward(from: 0.0);
    // Set up listener to inject a 1s pause between direction changes
    _avatarRotationStatusListener = (status) async {
      if (status == AnimationStatus.completed ||
          status == AnimationStatus.dismissed) {
        // Pause for 1 second before reversing/forwarding
        await Future.delayed(const Duration(seconds: 1));
        if (!mounted) return;
        if (_avatarRotationController.status == AnimationStatus.completed) {
          _avatarRotationController.reverse();
        } else if (_avatarRotationController.status ==
            AnimationStatus.dismissed) {
          _avatarRotationController.forward(from: 0.0);
        }
      }
    };
    _avatarRotationController.addStatusListener(_avatarRotationStatusListener!);

    _loadPlaybackPreferences();
    if (widget.post.mediaType == MediaType.video &&
        widget.post.mediaUrl != null &&
        widget.isActive) {
      _initializeVideo();
    } else if (widget.post.mediaType == MediaType.audio &&
        widget.post.mediaUrl != null) {
      _initializeAudio();
    }
    _checkTrackingStatus();
    _checkAuthorUnseenStatuses();
    // Prefetch parent post for harmony/duet inline preview
    if (widget.post.parentPostId != null &&
        widget.post.parentPostId!.isNotEmpty) {
      _loadParentPost();
    }

    // Load Safe Mode preference to control content blurring
    _loadSafeModePreference();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _updateViewTrackingState();
    });
  }

  Future<void> _loadSafeModePreference() async {
    try {
      final enabled = await _safeModeService.getSafeMode();
      if (!mounted) return;
      setState(() {
        _safeModeEnabled = enabled;
        // Do not auto-play when content is blurred by Safe Mode
        if (_safeModeEnabled &&
            !_contentRevealed &&
            _isSensitiveVisualContent()) {
          _pauseVideo();
          _endViewTracking();
        }
      });
    } catch (_) {
      // Keep default false on errors
    }
  }

  Future<void> _loadPlaybackPreferences() async {
    try {
      final autoPlay = await _preferencesService.getAutoPlayVideos();
      if (mounted) {
        setState(() {
          _autoPlayEnabled = autoPlay;
          _prefsLoaded = true;
        });
      }
      // Apply playback after preferences load
      if (_isVideoInitialized) {
        _updateVideoPlayback();
      }
    } catch (_) {
      // Keep default true on errors
    }
  }

  Future<void> _checkTrackingStatus() async {
    if (_authService.isAuthenticated &&
        _authService.currentUser?.id != widget.post.userId) {
      try {
        final isTracking = await _socialService.isFollowing(widget.post.userId);
        if (mounted) {
          setState(() {
            _isTracking = isTracking;
          });
        }
      } catch (e) {
        // Handle error silently
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      routeObserver.subscribe(this, route);
    }
  }

  @override
  void didUpdateWidget(PostWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Lazy-init video only when becoming active; dispose when deactivated to free resources
    if (widget.post.mediaType == MediaType.video &&
        widget.post.mediaUrl != null) {
      if (widget.isActive &&
          _videoController == null &&
          !_isVideoInitializing) {
        _initializeVideo();
      } else if (!widget.isActive && _videoController != null) {
        try {
          _videoController!.pause();
        } catch (_) {}
        _videoController!.dispose();
        _videoController = null;
        _isVideoInitialized = false;
      }
    }
    _updateVideoPlayback();
    _updateAudioPlayback();
    // Re-apply mute/effects on updates (e.g., session mute toggled)
    try {
      if (_videoController != null) {
        _videoController!.setVolume(widget.muted ? 0.0 : 1.0);
      }
    } catch (_) {}
    _applyAudioEffects();
    // Re-check unseen statuses when author changes or activation toggles
    try {
      if (oldWidget.post.userId != widget.post.userId ||
          (widget.isActive && !oldWidget.isActive)) {
        _checkAuthorUnseenStatuses();
      }
    } catch (_) {}
    _updateViewTrackingState();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        _pauseVideo();
        _pauseAudio();
        _endViewTracking();
        break;
      case AppLifecycleState.resumed:
        if (_wasPlayingBeforePause && widget.isActive && _isScreenVisible) {
          _resumeVideo();
        }
        _updateAudioPlayback();
        _updateViewTrackingState();
        break;
      default:
        break;
    }
  }

  @override
  void didPushNext() {
    // Screen is no longer visible (navigated to another screen)
    _isScreenVisible = false;
    _pauseVideo();
    _pauseAudio();
    _endViewTracking();
  }

  @override
  void didPopNext() {
    // Screen is visible again (returned from another screen)
    _isScreenVisible = true;
    if (_wasPlayingBeforePause && widget.isActive) {
      _resumeVideo();
    }
    _updateAudioPlayback();
    _updateViewTrackingState();
  }

  void _updateVideoPlayback() {
    if (_videoController == null || !_isVideoInitialized) return;

    // Respect Safe Mode: do not auto-play while blurred
    final safeModeBlocksPlayback =
        _safeModeEnabled && !_contentRevealed && _isSensitiveVisualContent();

    if (widget.isActive &&
        _isScreenVisible &&
        _autoPlayEnabled &&
        !safeModeBlocksPlayback) {
      _resumeVideo();
      _startViewTracking();
    } else {
      _pauseVideo();
      _endViewTracking();
    }
    // Apply mute state after playback change
    try {
      _videoController!.setVolume(widget.muted ? 0.0 : 1.0);
    } catch (_) {}
  }

  void _updateAudioPlayback() {
    if (_audioPlayer == null || !_isAudioInitialized) return;

    if (widget.isActive && _isScreenVisible) {
      // Auto-play when audio post is active and visible
      if (!_isAudioPlaying) {
        if (_audioPosition == Duration.zero) {
          _audioPlayer!.play(UrlSource(widget.post.mediaUrl!));
        } else {
          _audioPlayer!.resume();
        }
      }
      _startViewTracking();
      // Ensure effects are applied appropriately
      _applyAudioEffects();
    } else {
      _pauseAudio();
      _endViewTracking();
    }
  }

  void _updateViewTrackingState() {
    // If content is active and visible, ensure view tracking is started
    final isMediaReady =
        (widget.post.mediaType == MediaType.video && _isVideoInitialized) ||
        (widget.post.mediaType == MediaType.audio && _isAudioInitialized) ||
        (widget.post.mediaType == MediaType.image) ||
        (widget.post.mediaType == MediaType.text);
    if (widget.isActive && _isScreenVisible && isMediaReady) {
      _startViewTracking();
    } else {
      _endViewTracking();
    }
  }

  void _pauseVideo() {
    if (_videoController != null && _videoController!.value.isPlaying) {
      _wasPlayingBeforePause = true;
      // Track video pause event
      try {
        final watched = _viewStart != null
            ? DateTime.now().difference(_viewStart!).inSeconds
            : 0;
        _analyticsService.trackVideoPause(
          widget.post.id,
          _videoPosition.inSeconds,
          watched,
        );
      } catch (_) {}
      _videoController!.pause();
    }
  }

  void _resumeVideo() {
    if (_videoController != null && !_videoController!.value.isPlaying) {
      _videoController!.play();
      _wasPlayingBeforePause = false;
      // Track video play event
      try {
        _analyticsService.trackVideoPlay(
          widget.post.id,
          _videoPosition.inSeconds,
        );
      } catch (_) {}
    }
  }

  void _initializeVideo() async {
    if (_isVideoInitializing || _videoController != null) return;
    setState(() {
      _isVideoInitializing = true;
      _videoInitError = null;
    });
    try {
      final url = _effectiveMediaUrl ?? widget.post.mediaUrl!;
      final uri = Uri.parse(url);
      final ext = uri.path.split('.').last.toLowerCase();
      final isNonMp4 =
          ext == 'webm' || ext == 'mkv' || ext == 'mov' || ext == 'avi';

      try {
        final controller = VideoPlayerController.networkUrl(uri);
        await controller.initialize().timeout(
          const Duration(seconds: 12),
          onTimeout: () {
            throw TimeoutException('Video initialization timed out');
          },
        );
        await controller.setLooping(true);
        controller.addListener(() {
          if (!mounted) return;
          final value = controller.value;
          setState(() {
            _videoPosition = value.position;
            _videoDuration = value.duration;
          });
        });
        if (!mounted) {
          controller.dispose();
          return;
        }
        setState(() {
          _videoController = controller;
          _isVideoInitialized = true;
        });
        try {
          controller.setVolume(widget.muted ? 0.0 : 1.0);
        } catch (_) {}
        if (_prefsLoaded) {
          _updateVideoPlayback();
        }
      } catch (initError) {
        // Mobile fallback: if non-MP4 and not web, transcode and upload MP4 then retry
        final shouldFallback = !kIsWeb && isNonMp4;
        if (shouldFallback) {
          try {
            final resp = await http
                .get(uri)
                .timeout(const Duration(seconds: 20));
            if (resp.statusCode != 200)
              throw Exception('Download failed (${resp.statusCode})');
            final originalBytes = resp.bodyBytes;

            // Transcode to MP4
            final mp4Bytes = await VideoFilterService.compressVideo(
              input: originalBytes,
              scaleHeight: 720,
              audioKbps: 96,
              crf: 28,
            );

            // Upload MP4
            final storage = StorageService();
            final userId = _authService.currentUser?.id ?? widget.post.userId;
            final nameGuess = uri.pathSegments.isNotEmpty
                ? uri.pathSegments.last
                : 'video_${DateTime.now().millisecondsSinceEpoch}.mp4';
            final mp4Name = nameGuess.replaceAll(
              RegExp(r"\.(webm|mkv|mov|avi)$", caseSensitive: false),
              '.mp4',
            );
            final uploadResult = await storage.uploadVideo(
              videoFile: null,
              userId: userId,
              videoBytes: mp4Bytes,
              videoFileName: mp4Name,
            );
            final newUrl = uploadResult['videoUrl']!;

            // Persist new media_url
            await _postsService.updatePostMediaFields(
              postId: widget.post.id,
              mediaUrl: newUrl,
            );

            // Use new URL for playback
            _effectiveMediaUrl = newUrl;
            final controller = VideoPlayerController.networkUrl(
              Uri.parse(newUrl),
            );
            await controller.initialize().timeout(
              const Duration(seconds: 12),
              onTimeout: () {
                throw TimeoutException('Video initialization timed out');
              },
            );
            await controller.setLooping(true);
            controller.addListener(() {
              if (!mounted) return;
              final value = controller.value;
              setState(() {
                _videoPosition = value.position;
                _videoDuration = value.duration;
              });
            });
            if (!mounted) {
              controller.dispose();
              return;
            }
            setState(() {
              _videoController = controller;
              _isVideoInitialized = true;
              _videoInitError = null;
            });
            try {
              controller.setVolume(widget.muted ? 0.0 : 1.0);
            } catch (_) {}
            if (_prefsLoaded) {
              _updateVideoPlayback();
            }
          } catch (fallbackError) {
            debugPrint('Fallback transcoding failed: $fallbackError');
            rethrow;
          }
        } else {
          rethrow;
        }
      }
    } catch (e) {
      debugPrint('Error initializing video: $e');
      if (mounted) {
        setState(() {
          _isVideoInitialized = false;
          _videoInitError = e.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isVideoInitializing = false;
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    routeObserver.unsubscribe(this);
    // Dispose avatar rotation controller
    if (_avatarRotationStatusListener != null) {
      _avatarRotationController.removeStatusListener(
        _avatarRotationStatusListener!,
      );
    }
    _avatarRotationController.dispose();
    // Ensure we end view tracking before disposing
    _endViewTracking();
    // Cancel any pending timers/listeners
    _videoInitDebounceTimer?.cancel();
    _audioSeekTimer?.cancel();
    _videoSeekTimer?.cancel();
    _historyTimer?.cancel();
    _videoController?.dispose();
    _audioPlayer?.dispose();
    _parentVideoController?.dispose();
    super.dispose();
  }

  void _retryVideoInit() {
    try {
      _videoController?.dispose();
    } catch (_) {}
    _videoController = null;
    setState(() {
      _isVideoInitialized = false;
      _videoInitError = null;
    });
    _initializeVideo();
  }

  void _initializeAudio() async {
    try {
      debugPrint(
        ('Initializing audio for URL: ${widget.post.mediaUrl}').toString(),
      );
      _audioPlayer = AudioPlayer();
      // Set up listeners before setting source
      _audioPlayer!.onDurationChanged.listen((duration) {
        debugPrint(('Audio duration changed: $duration').toString());
        if (mounted) {
          setState(() {
            _audioDuration = duration;
          });
        }
      });
      _audioPlayer!.onPositionChanged.listen((position) {
        if (mounted) {
          setState(() {
            _audioPosition = position;
          });
        }
      });
      _audioPlayer!.onPlayerStateChanged.listen((state) {
        debugPrint(('Audio player state changed: $state').toString());
        if (mounted) {
          setState(() {
            _isAudioPlaying = state == PlayerState.playing;
          });
        }
      });
      _audioPlayer!.onPlayerComplete.listen((_) {
        if (!mounted) return;
        setState(() {
          // Reset to start to re-enable controls after completion
          _audioPosition = Duration.zero;
          _isAudioPlaying = false;
        });
      });
      // Set the audio source
      await _audioPlayer!.setSource(UrlSource(widget.post.mediaUrl!));
      // Apply persisted effects if present (or original if toggled)
      await _applyAudioEffects();
      debugPrint(('Audio source set successfully').toString());
      if (mounted) {
        setState(() {
          _isAudioInitialized = true;
        });
        debugPrint(('Audio initialized successfully').toString());
        _updateAudioPlayback();
      }
    } catch (e) {
      debugPrint('Error initializing audio: $e');
      if (mounted) {
        setState(() {
          _isAudioInitialized = false;
        });
      }
    }
  }

  void _pauseAudio() {
    if (_audioPlayer != null && _isAudioPlaying) {
      // End view tracking on audio pause
      _endViewTracking();
      _audioPlayer!.pause();
    }
  }

  void _toggleAudioPlayback() async {
    debugPrint(('Toggle audio playback called').toString());
    debugPrint(('Audio player null: ${_audioPlayer == null}').toString());
    debugPrint(('Is audio playing: $_isAudioPlaying').toString());
    debugPrint(('Audio position: $_audioPosition').toString());
    if (_audioPlayer == null || !_isAudioInitialized) {
      debugPrint(('Audio player not ready, aborting play').toString());
      return;
    }
    try {
      if (_isAudioPlaying) {
        debugPrint(('Pausing audio').toString());
        await _audioPlayer!.pause();
      } else {
        if (_audioPosition == Duration.zero) {
          debugPrint(('Starting audio from beginning').toString());
          await _audioPlayer!.play(UrlSource(widget.post.mediaUrl!));
        } else if (_audioDuration > Duration.zero &&
            _audioPosition >= _audioDuration) {
          debugPrint(
            ('Restarting audio from beginning after completion').toString(),
          );
          try {
            await _audioPlayer!.seek(Duration.zero);
          } catch (_) {}
          await _audioPlayer!.play(UrlSource(widget.post.mediaUrl!));
        } else {
          debugPrint(
            ('Resuming audio from position: $_audioPosition').toString(),
          );
          await _audioPlayer!.resume();
        }
        await _applyAudioEffects();
      }
    } catch (e) {
      debugPrint(('Error in toggle audio playback: $e').toString());
    }
  }

  void _seekAudioBy(Duration delta) {
    if (_audioPlayer == null || !_isAudioInitialized) return;
    final newPosMs = (_audioPosition.inMilliseconds + delta.inMilliseconds)
        .clamp(0, _audioDuration.inMilliseconds);
    final newPos = Duration(milliseconds: newPosMs);
    _audioPlayer!.seek(newPos);
    setState(() {
      _audioPosition = newPos;
    });
  }

  void _seekVideoBy(Duration delta) {
    if (_videoController == null || !_isVideoInitialized) return;
    final current = _videoController!.value.position;
    final duration = _videoController!.value.duration;
    final newPosMs = (current.inMilliseconds + delta.inMilliseconds).clamp(
      0,
      duration.inMilliseconds,
    );
    final newPos = Duration(milliseconds: newPosMs);
    _videoController!.seekTo(newPos);
    setState(() {
      _videoPosition = newPos;
    });
  }

  void _startViewTracking() {
    // Start the view if not already started
    if (_viewStart == null) {
      _viewStart = DateTime.now();
      _hasIncrementedView = false;
      _historyAdded = false;
      _historyTimer?.cancel();
      _historyTimer = Timer(const Duration(seconds: 2), () async {
        if (!mounted) return;
        // Still actively viewing the post after 2s
        if (_viewStart != null && widget.isActive && _isScreenVisible) {
          if (!_historyAdded) {
            try {
              await HistoryService.addPostView(widget.post);
            } catch (_) {}
            if (mounted) {
              setState(() {
                _historyAdded = true;
              });
            } else {
              _historyAdded = true;
            }
          }
        }
      });
    }

    // Increment views_count once per visible session
    if (!_hasIncrementedView) {
      _hasIncrementedView = true;
      try {
        _databaseService.incrementPostViewsCount(widget.post.id);
      } catch (_) {}
    }
  }

  void _endViewTracking() {
    // If a view session was started, compute duration and send analytics
    if (_viewStart != null) {
      _historyTimer?.cancel();
      final duration = DateTime.now().difference(_viewStart!).inSeconds;
      // Record history if minimum watch time met and not already added
      if (!_historyAdded && duration >= 7) {
        try {
          HistoryService.addPostView(widget.post);
        } catch (_) {}
        _historyAdded = true;
      }
      // Send analytics with duration (best-effort)
      try {
        _analyticsService.trackPostView(
          widget.post.id,
          widget.post.mediaType.name,
          duration: duration,
        );
      } catch (_) {}
    }
    _viewStart = null;
    if (_historyAdded) {
      if (mounted) {
        setState(() {
          _historyAdded = false;
        });
      } else {
        _historyAdded = false;
      }
    }
  }

  // Long-press continuous seeking
  void _startContinuousAudioSeek(Duration step) {
    _audioSeekTimer?.cancel();
    _audioSeekTimer = Timer.periodic(const Duration(milliseconds: 150), (_) {
      _seekAudioBy(step);
    });
  }

  void _stopContinuousAudioSeek() {
    _audioSeekTimer?.cancel();
    _audioSeekTimer = null;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.black,
      child: Stack(
        children: [
          // Background content
          _buildMediaContent(),

          // Gradient overlay
          IgnorePointer(
            ignoring: true,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.transparent,
                    Colors.black.withOpacity(0.3),
                    Colors.black.withOpacity(0.7),
                  ],
                  stops: const [0.0, 0.5, 0.8, 1.0],
                ),
              ),
            ),
          ),
          if (kDebugMode && _historyAdded)
            Positioned(
              top: MediaQuery.of(context).padding.top + 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppColors.success.withOpacity(0.6)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(
                      Icons.check_circle,
                      color: AppColors.success,
                      size: 14,
                    ),
                    SizedBox(width: 6),
                    Text(
                      'Recorded',
                      style: TextStyle(
                        color: AppColors.success,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Effect badge for audio posts
          if (widget.post.mediaType == MediaType.audio &&
              widget.post.effects != null)
            Positioned(
              top: MediaQuery.of(context).padding.top + 12,
              left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.2)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.graphic_eq, color: Colors.white, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      _effectLabel(widget.post.effects!),
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Content overlay
          Positioned(
            left: 16,
            right: 80,
            bottom: 100,
            child: IgnorePointer(
              ignoring: false,
              child: _buildContentOverlay(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaContent() {
    switch (widget.post.mediaType) {
      case MediaType.video:
        return _wrapWithModeration(_buildVideoContent());
      case MediaType.image:
        return _wrapWithModeration(_buildImageContent());
      case MediaType.text:
        return _buildTextContent();
      case MediaType.audio:
        return _buildAudioContent();
    }
  }

  // Infer a content rating for visual media from available metadata/effects.
  // Returns one of: 'safe' | 'sensitive' | 'adult' | 'banned'. Defaults to 'safe'.
  String _inferContentRating() {
    try {
      final meta = widget.post.aiMetadata;
      if (meta != null) {
        final direct =
            (meta['content_rating'] ??
            meta['rating'] ??
            meta['moderation_rating']);
        if (direct is String && direct.isNotEmpty) {
          final s = direct.toLowerCase();
          if (s == 'banned' || s == 'adult' || s == 'sensitive') return s;
        }
        final moderation = meta['moderation'];
        if (moderation is Map<String, dynamic>) {
          final flagged = moderation['flagged'] == true;
          final category = (moderation['category'] as String?)?.toLowerCase();
          if (flagged) {
            if (category == 'adult' || category == 'nsfw') return 'adult';
            return 'sensitive';
          }
        }
        if (meta['nsfw'] == true) return 'adult';
      }

      final effects = widget.post.effects;
      if (effects != null) {
        final effRating = effects['rating'];
        if (effRating is String && effRating.isNotEmpty) {
          final s = effRating.toLowerCase();
          if (s == 'banned' || s == 'adult' || s == 'sensitive') return s;
        }
        if (effects['nsfw'] == true) return 'adult';
      }
    } catch (_) {}
    return 'safe';
  }

  bool _isSensitiveVisualContent() {
    final isVisual =
        widget.post.mediaType == MediaType.video ||
        widget.post.mediaType == MediaType.image;
    if (!isVisual) return false;
    final rating = _inferContentRating();
    return rating == 'sensitive' || rating == 'adult' || rating == 'banned';
  }

  Widget _wrapWithModeration(Widget child) {
    // Only blur visual media in Safe Mode; text/audio remain unchanged
    final isVisualMedia =
        widget.post.mediaType == MediaType.video ||
        widget.post.mediaType == MediaType.image;
    if (!_safeModeEnabled || !isVisualMedia) return child;

    return ModerationBlur(
      child: child,
      contentRating: _inferContentRating(),
      blurPreview: !_contentRevealed && _isSensitiveVisualContent(),
      onReveal: () {
        if (!mounted) return;
        setState(() {
          _contentRevealed = true;
          // Re-apply playback now that content is revealed
          _updateVideoPlayback();
        });
      },
    );
  }

  Widget _buildVideoContent() {
    if (_videoInitError != null) {
      return Container(
        color: Colors.grey[900],
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.white, size: 28),
              const SizedBox(height: 8),
              Text(
                LocalizationService.t('unable_to_load_video'),
                style: GoogleFonts.poppins(color: Colors.white),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _retryVideoInit,
                child: Text(LocalizationService.t('retry')),
              ),
            ],
          ),
        ),
      );
    }
    if (_videoController == null || !_isVideoInitialized) {
      return Container(
        color: Colors.grey[900],
        child: const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }
    return Stack(
      children: [
        // Base video content with tap-to-toggle play/pause
        GestureDetector(
          onTap: () {
            final controllerValue = _videoController!.value;
            if (controllerValue.isPlaying) {
              // Track pause
              try {
                final watched = _viewStart != null
                    ? DateTime.now().difference(_viewStart!).inSeconds
                    : 0;
                _analyticsService.trackVideoPause(
                  widget.post.id,
                  _videoPosition.inSeconds,
                  watched,
                );
              } catch (_) {}
              _endViewTracking();
              _videoController!.pause();
            } else {
              if (controllerValue.duration > Duration.zero &&
                  controllerValue.position >= controllerValue.duration) {
                _videoController!.seekTo(Duration.zero);
              }
              _videoController!.play();
              // Track play
              try {
                _analyticsService.trackVideoPlay(
                  widget.post.id,
                  _videoPosition.inSeconds,
                );
              } catch (_) {}
              _startViewTracking();
            }
          },
          child: SizedBox.expand(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _videoController!.value.size.width,
                height: _videoController!.value.size.height,
                child: VideoPlayer(_videoController!),
              ),
            ),
          ),
        ),
        // Invisible overlay zones for double-tap seek left/right and tap-to-toggle
        Positioned.fill(
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () {
                    final playing = _videoController!.value.isPlaying;
                    if (playing) {
                      try {
                        final watched = _viewStart != null
                            ? DateTime.now().difference(_viewStart!).inSeconds
                            : 0;
                        _analyticsService.trackVideoPause(
                          widget.post.id,
                          _videoPosition.inSeconds,
                          watched,
                        );
                      } catch (_) {}
                      _endViewTracking();
                      _videoController!.pause();
                    } else {
                      _videoController!.play();
                      try {
                        _analyticsService.trackVideoPlay(
                          widget.post.id,
                          _videoPosition.inSeconds,
                        );
                      } catch (_) {}
                      _startViewTracking();
                    }
                  },
                  onDoubleTap: () => _seekVideoBy(const Duration(seconds: -10)),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () {
                    final controllerValue = _videoController!.value;
                    final playing = controllerValue.isPlaying;
                    if (playing) {
                      try {
                        final watched = _viewStart != null
                            ? DateTime.now().difference(_viewStart!).inSeconds
                            : 0;
                        _analyticsService.trackVideoPause(
                          widget.post.id,
                          _videoPosition.inSeconds,
                          watched,
                        );
                      } catch (_) {}
                      _endViewTracking();
                      _videoController!.pause();
                    } else {
                      if (controllerValue.duration > Duration.zero &&
                          controllerValue.position >=
                              controllerValue.duration) {
                        _videoController!.seekTo(Duration.zero);
                      }
                      _videoController!.play();
                      try {
                        _analyticsService.trackVideoPlay(
                          widget.post.id,
                          _videoPosition.inSeconds,
                        );
                      } catch (_) {}
                      _startViewTracking();
                    }
                  },
                  onDoubleTap: () => _seekVideoBy(const Duration(seconds: 10)),
                ),
              ),
            ],
          ),
        ),
        // Bottom overlay: keep only the progress slider
        Positioned(
          left: 16,
          right: 16,
          bottom: 24,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: Colors.white,
                  inactiveTrackColor: Colors.white.withValues(alpha: 0.3),
                  thumbColor: Colors.white,
                  overlayColor: Colors.white.withValues(alpha: 0.2),
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 6,
                  ),
                ),
                child: Slider(
                  value: _videoDuration.inMilliseconds > 0
                      ? _videoPosition.inMilliseconds /
                            _videoDuration.inMilliseconds
                      : 0.0,
                  onChanged: (value) {
                    final pos = Duration(
                      milliseconds: (value * _videoDuration.inMilliseconds)
                          .round(),
                    );
                    _videoController?.seekTo(pos);
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildImageContent() {
    if (widget.post.mediaUrl == null) {
      return _buildTextContent();
    }

    return CachedNetworkImage(
      imageUrl: widget.post.mediaUrl!,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      placeholder: (context, url) => Container(
        color: Colors.grey[900],
        child: const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      ),
      errorWidget: (context, url, error) => Container(
        color: Colors.grey[900],
        child: const Center(
          child: Icon(Icons.error, color: Colors.white, size: 50),
        ),
      ),
    );
  }

  Widget _buildTextContent() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF667eea),
            const Color(0xFF764ba2),
            const Color(0xFFf093fb),
            const Color(0xFFf5576c),
          ],
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: _buildRichTextWithMentions(
            widget.post.content,
            style: GoogleFonts.poppins(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: Colors.white,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  Widget _buildAudioContent() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [const Color(0xFF667eea), const Color(0xFF764ba2)],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Audio visualization
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.1),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.3),
                  width: 2,
                ),
              ),
              child: Icon(
                Icons.music_note,
                size: 60,
                color: Colors.white.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(height: 24),
            // Audio title
            Text(
              'Audio Post',
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            // Caption if available
            if (widget.post.content.isNotEmpty) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32.0),
                child: _buildRichTextWithMentions(
                  widget.post.content,
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    color: Colors.white.withValues(alpha: 0.9),
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
            const SizedBox(height: 32),
            // Audio controls
            if (_isAudioInitialized) ...[
              // Progress bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40.0),
                child: Column(
                  children: [
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: Colors.white,
                        inactiveTrackColor: Colors.white.withValues(alpha: 0.3),
                        thumbColor: Colors.white,
                        overlayColor: Colors.white.withValues(alpha: 0.2),
                        trackHeight: 3,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 6,
                        ),
                      ),
                      child: Slider(
                        value: _audioDuration.inMilliseconds > 0
                            ? _audioPosition.inMilliseconds /
                                  _audioDuration.inMilliseconds
                            : 0.0,
                        onChanged: (value) {
                          final position = Duration(
                            milliseconds:
                                (value * _audioDuration.inMilliseconds).round(),
                          );
                          _audioPlayer?.seek(position);
                          setState(() {
                            _audioPosition = position;
                          });
                        },
                      ),
                    ),
                    // Time display
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _formatDuration(_audioPosition),
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.8),
                            ),
                          ),
                          Text(
                            _formatDuration(_audioDuration),
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // Control buttons: back, play/pause, forward
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Rewind 15s
                  GestureDetector(
                    onTap: () => _seekAudioBy(const Duration(seconds: -15)),
                    onLongPressStart: (_) =>
                        _startContinuousAudioSeek(const Duration(seconds: -3)),
                    onLongPressEnd: (_) => _stopContinuousAudioSeek(),
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black.withValues(alpha: 0.25),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.replay_10, color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Play/Pause button
                  GestureDetector(
                    onTap: _toggleAudioPlayback,
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Icon(
                        _isAudioPlaying ? Icons.pause : Icons.play_arrow,
                        size: 32,
                        color: const Color(0xFF667eea),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Forward 15s
                  GestureDetector(
                    onTap: () => _seekAudioBy(const Duration(seconds: 15)),
                    onLongPressStart: (_) =>
                        _startContinuousAudioSeek(const Duration(seconds: 3)),
                    onLongPressEnd: (_) => _stopContinuousAudioSeek(),
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black.withValues(alpha: 0.25),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.forward_10, color: Colors.white),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Original speed toggle
              GestureDetector(
                onTap: () async {
                  setState(() {
                    _playOriginal = !_playOriginal;
                  });
                  await _applyAudioEffects();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: _playOriginal
                        ? Colors.white
                        : Colors.black.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.speed, color: Colors.white, size: 16),
                      const SizedBox(width: 6),
                      LocalizedText(
                        _playOriginal ? 'playing_original' : 'play_original',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: _playOriginal
                              ? const Color(0xFF667eea)
                              : Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ] else ...[
              // Loading state
              const CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              ),
              const SizedBox(height: 16),
              Text(
                'Loading audio...',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: Colors.white.withValues(alpha: 0.8),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  String _effectLabel(Map<String, dynamic> effects) {
    final name = effects['name'] as String?;
    final speed = (effects['speed'] as num?)?.toDouble();
    final volume = (effects['volume'] as num?)?.toDouble();
    if (name != null && name.isNotEmpty) {
      // Localize the default effect name when it is 'Original'
      if (name == 'Original') {
        return LocalizationService.t('original');
      }
      return name;
    }
    final parts = <String>[];
    if (speed != null) parts.add('Speed x${speed.toStringAsFixed(2)}');
    if (volume != null) parts.add('Vol ${(volume * 100).round()}%');
    return parts.isNotEmpty ? parts.join(' • ') : 'Effect applied';
  }

  Future<void> _applyAudioEffects() async {
    if (_audioPlayer == null) return;
    try {
      double speed = 1.0;
      double volume = 1.0;
      final effects = widget.post.effects;
      if (!_playOriginal && effects != null) {
        final s = (effects['speed'] as num?)?.toDouble();
        final v = (effects['volume'] as num?)?.toDouble();
        if (s != null && s > 0) {
          speed = s;
        }
        if (v != null) {
          final vc = v.toDouble();
          volume = vc < 0.0 ? 0.0 : (vc > 1.0 ? 1.0 : vc);
        }
      }
      // If session is muted, force volume to zero
      if (widget.muted) {
        volume = 0.0;
      }
      try {
        await _audioPlayer!.setPlaybackRate(speed);
      } catch (e) {
        // Some versions may not support setPlaybackRate; ignore
      }
      await _audioPlayer!.setVolume(volume);
    } catch (e) {
      debugPrint(('Error applying audio effects: $e').toString());
    }
  }

  // Build rich text with clickable @mentions
  Widget _buildRichTextWithMentions(
    String text, {
    required TextStyle style,
    int? maxLines,
    TextOverflow overflow = TextOverflow.visible,
    TextAlign textAlign = TextAlign.left,
  }) {
    final spans = <TextSpan>[];
    final regex = RegExp(r'@[a-zA-Z0-9_]+');
    int start = 0;
    for (final match in regex.allMatches(text)) {
      if (match.start > start) {
        spans.add(
          TextSpan(text: text.substring(start, match.start), style: style),
        );
      }
      final mention = match.group(0)!; // includes '@'
      spans.add(
        TextSpan(
          text: mention,
          style: style.copyWith(
            color: Colors.blueAccent,
            fontWeight: FontWeight.w600,
          ),
          recognizer: TapGestureRecognizer()
            ..onTap = () => _onMentionTap(mention.substring(1).trim()),
        ),
      );
      start = match.end;
    }
    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start), style: style));
    }
    return RichText(
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
      text: TextSpan(children: spans),
    );
  }

  Future<void> _onMentionTap(String username) async {
    HapticFeedback.selectionClick();
    try {
      final unameRaw = username.startsWith('@')
          ? username.substring(1)
          : username;
      final uname = unameRaw.trim();
      if (uname.isEmpty) return;

      // 1) Fast local fallback: if mention equals the post author's username, open their profile
      final postUsername = widget.post.username.trim();
      if (postUsername.isNotEmpty &&
          postUsername.toLowerCase() == uname.toLowerCase()) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ProfileScreen(userId: widget.post.userId),
          ),
        );
        return;
      }

      // 2) Resolve via service (exact/partial case-insensitive across users and profiles)
      String? userId = await _socialService.getUserIdByUsername(uname);

      // 3) Fallback: attempt a user search and pick best match
      if (userId == null) {
        try {
          final results = await _socialService.searchUsers(uname);
          if (results.isNotEmpty) {
            // Prefer exact case-insensitive username match, else fallback to first result
            final exact = results.firstWhere(
              (e) =>
                  ((e['username'] as String?) ?? '').toLowerCase() ==
                  uname.toLowerCase(),
              orElse: () => results.first,
            );
            userId = exact['id'] as String?;
          }
        } catch (_) {}
      }

      if (!mounted) return;
      if (userId != null) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ProfileScreen(userId: userId!),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('User @$uname not found'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to open profile for @$username'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _navigateToProfile() {
    HapticFeedback.lightImpact();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProfileScreen(userId: widget.post.userId),
      ),
    );
  }

  Future<void> _toggleTrack() async {
    if (_isTrackLoading || !_authService.isAuthenticated) return;

    // Don't allow tracking yourself
    if (_authService.currentUser?.id == widget.post.userId) return;

    setState(() {
      _isTrackLoading = true;
    });

    try {
      if (_isTracking) {
        await _socialService.unfollowUser(widget.post.userId);
      } else {
        await _socialService.followUser(widget.post.userId);
      }

      if (mounted) {
        setState(() {
          _isTracking = !_isTracking;
        });
      }

      HapticFeedback.lightImpact();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isTracking
                  ? LocalizationService.t('failed_unfollow_user')
                  : LocalizationService.t('failed_follow_user'),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isTrackLoading = false;
        });
      }
    }
  }

  Future<void> _navigateToOriginalPost() async {
    if (widget.post.parentPostId == null) return;

    // Show a quick loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final parentId = widget.post.parentPostId!;
      final parentPost = await _postsService.getPostById(parentId);

      if (!mounted) return;
      Navigator.pop(context); // close loading

      if (parentPost != null) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PostDetailScreen(post: parentPost),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: LocalizedText('original_post_not_found'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // close loading
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: LocalizedText('failed_to_open_original_post'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildContentOverlay() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Harmony ribbon and inline preview
        if (widget.post.parentPostId != null) ...[
          GestureDetector(
            onTap: () => _navigateToOriginalPost(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.white.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.reply,
                    color: Colors.white.withOpacity(0.9),
                    size: 14,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      _parentPost != null
                          ? '@${_parentPost!.username} harmonied by @${widget.post.username}'
                          : 'Harmonied by @${widget.post.username}',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.9),
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Compact inline preview of the original post (if accessible)
          if (_parentPost != null) ...[
            GestureDetector(
              onTap: () => _navigateToOriginalPost(),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.2),
                    width: 1,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Avatar
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child:
                          (_parentPost!.userAvatar != null &&
                              _parentPost!.userAvatar!.isNotEmpty)
                          ? CachedNetworkImage(
                              imageUrl: _parentPost!.userAvatar!,
                              width: 16,
                              height: 16,
                              fit: BoxFit.cover,
                            )
                          : Container(
                              width: 16,
                              height: 16,
                              color: Colors.white.withOpacity(0.1),
                              child: const Icon(
                                Icons.person,
                                color: Colors.white,
                                size: 12,
                              ),
                            ),
                    ),
                    const SizedBox(width: 4),
                    // Username and snippet
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '@${_parentPost!.username}',
                            style: GoogleFonts.poppins(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 1),
                          (_parentPost!.content?.isNotEmpty == true)
                              ? Text(
                                  _parentPost!.content!,
                                  style: GoogleFonts.poppins(
                                    fontSize: 9,
                                    color: Colors.white.withOpacity(0.9),
                                    fontWeight: FontWeight.w400,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                )
                              : LocalizedText(
                                  _parentPost!.mediaType == MediaType.video
                                      ? 'original_video'
                                      : _parentPost!.mediaType ==
                                            MediaType.image
                                      ? 'original_image'
                                      : _parentPost!.mediaType ==
                                            MediaType.audio
                                      ? 'original_audio'
                                      : 'original_post',
                                  style: GoogleFonts.poppins(
                                    fontSize: 9,
                                    color: Colors.white.withOpacity(0.9),
                                    fontWeight: FontWeight.w400,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    // Enlarged media preview area
                    if (_parentPost!.mediaType == MediaType.video &&
                        _isParentVideoInitialized &&
                        _parentVideoController != null) ...[
                      SizedBox(
                        width: 110,
                        child: Stack(
                          children: [
                            AspectRatio(
                              aspectRatio:
                                  _parentVideoController!.value.aspectRatio > 0
                                  ? _parentVideoController!.value.aspectRatio
                                  : 16 / 9,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: VideoPlayer(_parentVideoController!),
                              ),
                            ),
                            Positioned(
                              top: 6,
                              right: 6,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.5),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.2),
                                    width: 1,
                                  ),
                                ),
                                child: IconButton(
                                  icon: Icon(
                                    _isParentVideoMuted
                                        ? Icons.volume_off
                                        : Icons.volume_up,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                  onPressed: _toggleParentMute,
                                  tooltip: _isParentVideoMuted
                                      ? LocalizationService.t('unmute_original')
                                      : LocalizationService.t('mute_original'),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else if (_parentPost!.mediaType == MediaType.image &&
                        _parentPost!.mediaUrl != null &&
                        _parentPost!.mediaUrl!.isNotEmpty) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: CachedNetworkImage(
                          imageUrl: _parentPost!.mediaUrl!,
                          width: 110,
                          height: 62,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ] else if (_parentPost!.thumbnailUrl != null &&
                        _parentPost!.thumbnailUrl!.isNotEmpty) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: CachedNetworkImage(
                          imageUrl: _parentPost!.thumbnailUrl!,
                          width: 110,
                          height: 62,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ] else ...[
                      Container(
                        width: 110,
                        height: 62,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          _parentPost!.mediaType == MediaType.video
                              ? Icons.videocam
                              : _parentPost!.mediaType == MediaType.audio
                              ? Icons.audiotrack
                              : Icons.description,
                          color: Colors.white.withOpacity(0.9),
                          size: 14,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ] else if (_isLoadingParent) ...[
            // Subtle loading indicator while fetching parent
            const SizedBox(height: 6),
            Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
                const SizedBox(width: 6),
                LocalizedText(
                  'loading_original',
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
              ],
            ),
          ],
        ],
        // User info
        Row(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: _navigateToProfile,
                  child: _authorHasUnseenStatuses
                      ? Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(
                              colors: [
                                Color(0xFF8AB4F8),
                                Color(0xFFFFFFFF),
                                Color(0xFFFFD700),
                              ],
                              stops: [0.0, 0.5, 1.0],
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x668AB4F8),
                                blurRadius: 6,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: Container(
                            margin: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.black,
                            ),
                            child: AnimatedBuilder(
                              animation: _avatarRotationController,
                              builder: (context, child) => Transform.rotate(
                                angle: _avatarRotation.value,
                                child: child,
                              ),
                              child: CircleAvatar(
                                radius: 20,
                                backgroundColor: Colors.white,
                                child: widget.post.userAvatar != null
                                    ? ClipOval(
                                        child: CachedNetworkImage(
                                          imageUrl: widget.post.userAvatar!,
                                          width: 40,
                                          height: 40,
                                          fit: BoxFit.cover,
                                          placeholder: (context, url) =>
                                              Container(
                                                color: Colors.grey[300],
                                                child: const Icon(
                                                  Icons.person,
                                                  color: Colors.grey,
                                                ),
                                              ),
                                          errorWidget: (context, url, error) =>
                                              Container(
                                                color: Colors.grey[300],
                                                child: const Icon(
                                                  Icons.person,
                                                  color: Colors.grey,
                                                ),
                                              ),
                                        ),
                                      )
                                    : const Icon(
                                        Icons.person,
                                        color: Colors.grey,
                                      ),
                              ),
                            ),
                          ),
                        )
                      : AnimatedBuilder(
                          animation: _avatarRotationController,
                          builder: (context, child) => Transform.rotate(
                            angle: _avatarRotation.value,
                            child: child,
                          ),
                          child: CircleAvatar(
                            radius: 20,
                            backgroundColor: Colors.white,
                            child: widget.post.userAvatar != null
                                ? ClipOval(
                                    child: CachedNetworkImage(
                                      imageUrl: widget.post.userAvatar!,
                                      width: 40,
                                      height: 40,
                                      fit: BoxFit.cover,
                                      placeholder: (context, url) => Container(
                                        color: Colors.grey[300],
                                        child: const Icon(
                                          Icons.person,
                                          color: Colors.grey,
                                        ),
                                      ),
                                      errorWidget: (context, url, error) =>
                                          Container(
                                            color: Colors.grey[300],
                                            child: const Icon(
                                              Icons.person,
                                              color: Colors.grey,
                                            ),
                                          ),
                                    ),
                                  )
                                : const Icon(Icons.person, color: Colors.grey),
                          ),
                        ),
                ),
                const SizedBox(height: 6),
                if ((widget.post.hashtags?.any(
                      (h) =>
                          h.toLowerCase().replaceAll('#', '') ==
                          'mock-experiment',
                    ) ??
                    false)) ...{
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF6C00),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Mock-Experiment',
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                },
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            GestureDetector(
                              onTap: _navigateToProfile,
                              child: Text(
                                '@${widget.post.username}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                softWrap: false,
                                style: GoogleFonts.poppins(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            if (((widget.post.isVerified == true) ||
                                (widget.post.username?.toLowerCase() ==
                                    'equal') ||
                                (widget.post.username?.toLowerCase() ==
                                    'vigny'))) ...{
                              const SizedBox(width: 4),
                              Icon(
                                Icons.verified,
                                color:
                                    (widget.post.username?.toLowerCase() ==
                                        'vigny')
                                    ? Colors.blue
                                    : AppColors.gold,
                                size: 16,
                              ),
                            },
                          ],
                        ),
                      ),
                      if (_authService.isAuthenticated &&
                          _authService.currentUser?.id !=
                              widget.post.userId) ...{
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: _isTrackLoading ? null : _toggleTrack,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: _isTracking
                                  ? Colors.white.withOpacity(0.2)
                                  : Colors.blue,
                              borderRadius: BorderRadius.circular(12),
                              border: _isTracking
                                  ? Border.all(
                                      color: Colors.white.withOpacity(0.5),
                                      width: 1,
                                    )
                                  : null,
                            ),
                            child: _isTrackLoading
                                ? const SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                    ),
                                  )
                                : Text(
                                    _isTracking
                                        ? LocalizationService.t('following')
                                        : LocalizationService.t('follow'),
                                    style: GoogleFonts.poppins(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                          ),
                        ),
                      },
                      const SizedBox(width: 8),
                      Text(
                        widget.post.formattedTimeAgo,
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        // Post content (for non-text posts)
        if (widget.post.mediaType != MediaType.text)
          _buildRichTextWithMentions(
            widget.post.content,
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: Colors.white,
              height: 1.3,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),

        if (widget.post.location != null) ...{
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                Icons.location_on,
                color: Colors.white.withOpacity(0.7),
                size: 14,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  widget.post.location!,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: Colors.white.withOpacity(0.7),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        },

        if (widget.post.hashtags != null &&
            widget.post.hashtags!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: widget.post.hashtags!
                .take(3)
                .map(
                  (hashtag) => Text(
                    '#$hashtag',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: Colors.blue[300],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ],
    );
  }

  Future<void> _loadParentPost() async {
    if (_isLoadingParent) return;
    setState(() => _isLoadingParent = true);
    try {
      final parentId = widget.post.parentPostId!;
      final parent = await _postsService.getPostById(parentId);
      if (!mounted) return;
      setState(() {
        _parentPost = parent;
        _isLoadingParent = false;
      });
      if (_parentPost?.mediaType == MediaType.video) {
        // Initialize parent video after post is loaded
        await _initParentVideo();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingParent = false);
    }
  }

  Future<void> _initParentVideo() async {
    try {
      final url = _parentPost?.mediaUrl;
      if (url == null || url.isEmpty) return;
      _parentVideoController?.dispose();
      _parentVideoController = VideoPlayerController.networkUrl(Uri.parse(url));
      await _parentVideoController!.initialize().timeout(
        const Duration(seconds: 8),
        onTimeout: () {
          throw TimeoutException('Parent video initialization timed out');
        },
      );
      _parentVideoController!.setLooping(true);
      _parentVideoController!.setVolume(_isParentVideoMuted ? 0.0 : 1.0);
      setState(() {
        _isParentVideoInitialized = true;
      });
      _parentVideoController!.play();
    } catch (_) {}
  }

  void _toggleParentMute() {
    if (_parentVideoController == null) return;
    setState(() {
      _isParentVideoMuted = !_isParentVideoMuted;
    });
    _parentVideoController!.setVolume(_isParentVideoMuted ? 0.0 : 1.0);
  }

  Future<void> _checkAuthorUnseenStatuses() async {
    try {
      final viewerId = _authService.currentUser?.id;
      final ownerId = widget.post.userId;
      bool hasUnseen = false;
      if (viewerId != null &&
          viewerId.isNotEmpty &&
          ownerId.isNotEmpty &&
          viewerId != ownerId) {
        hasUnseen = await _statusService.hasUnseenStatusesForUser(
          ownerUserId: ownerId,
          viewerUserId: viewerId,
        );
      }
      if (!mounted) return;
      setState(() {
        _authorHasUnseenStatuses = hasUnseen;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _authorHasUnseenStatuses = false;
      });
    }
  }
}
