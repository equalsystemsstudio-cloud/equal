import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// Removed: import '../widgets/status_bar.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import '../models/post_model.dart';
import '../services/localization_service.dart';
import '../services/posts_service.dart';
import '../services/auth_service.dart';
import '../services/admob_service.dart';
import '../services/analytics_service.dart';
import '../services/social_service.dart';
import '../services/enhanced_notification_service.dart';
import '../services/location_service.dart';
import '../services/post_media_optimization_service.dart';
import '../widgets/post_widget.dart';
import '../widgets/side_action_bar.dart';
import '../widgets/ads/native_ad_widget.dart';
import 'comments_screen.dart';
import 'harmony_creation_screen.dart';
import '../services/live_streaming_service.dart'
    show LiveStreamingService; // Add live streaming service
import 'live_stream_viewer_screen.dart'
    show LiveStreamViewerScreen; // For navigation to viewer
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_colors.dart';
import 'content_type_selection_screen.dart';
import '../config/feature_flags.dart';

class MainFeedScreen extends StatefulWidget {
  const MainFeedScreen({super.key, this.feedVisibleNotifier});

  // Notifier from parent to indicate whether the Home tab is currently visible
  final ValueNotifier<bool>? feedVisibleNotifier;

  @override
  State<MainFeedScreen> createState() => _MainFeedScreenState();
}

class _MainFeedScreenState extends State<MainFeedScreen>
    with TickerProviderStateMixin {
  late PageController _pageController;
  late TabController _tabController;
  int _currentIndex = 0;
  int _selectedTab = 0;

  // Treat a live stream as stale if it hasn't updated recently
  static const Duration _liveStaleThreshold = Duration(minutes: 3);

  // Monetization processing timer
  Timer? _monetizationTimer;

  // Services
  final PostsService _postsService = PostsService();
  final AuthService _authService = AuthService();
  final AdMobService _adMobService = AdMobService();
  final AnalyticsService _analyticsService = AnalyticsService();
  final SocialService _socialService = SocialService();
  final EnhancedNotificationService _notificationService =
      EnhancedNotificationService();
  final LiveStreamingService _liveStreamingService =
      LiveStreamingService(); // new
  final LocationService _locationService = LocationService();
  final PostMediaOptimizationService _optimizationService =
      PostMediaOptimizationService.of();
  RealtimeChannel?
  _liveStreamsChannel; // realtime subscription for live streams

  // Ad tracking
  int _viralPostViewCount = 0;

  // Data
  List<PostModel> _posts = [];
  List<Map<String, dynamic>> _activeStreams =
      []; // new: active live streams for feed
  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';

  // Pagination
  int _currentPage = 0;
  final int _pageSize = 20;
  bool _isLoadingMore = false;
  bool _hasMorePosts = true;

  // Track scroll state to immediately stop playback when leaving a post
  bool _isScrolling = false;
  // Track whether the parent MainScreen has this tab visible
  bool _isParentVisible = true;
  // Header avatar spin animation state
  late AnimationController _headerAvatarRotateController;
  int _avatarRotateDirection = 1;
  bool _avatarSpinCycleRunning = false;
  AnimationStatusListener? _headerRotateStatusListener;

  void _handleParentVisibilityChanged() {
    if (widget.feedVisibleNotifier == null) return;
    if (!mounted) return;
    final visible = widget.feedVisibleNotifier!.value;
    if (_isParentVisible != visible) {
      setState(() {
        _isParentVisible = visible;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _tabController = TabController(length: 4, vsync: this); // Added viral tab
    _initializeAdMob();
    _loadPosts();
    _startMonetizationProcessing();
    // Initialize parent visibility tracking
    if (widget.feedVisibleNotifier != null) {
      _isParentVisible = widget.feedVisibleNotifier!.value;
      widget.feedVisibleNotifier!.addListener(_handleParentVisibilityChanged);
    }
    _subscribeToLiveStreams(); // subscribe to realtime live_streams changes
    // Initialize header avatar rotation controller
    _headerAvatarRotateController = AnimationController(
      vsync: this,
      lowerBound: -1000000.0,
      upperBound: 1000000.0,
      duration: const Duration(seconds: 5),
    );
    _startHeaderAvatarSpinCycle();
  }

  @override
  void didUpdateWidget(covariant MainFeedScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.feedVisibleNotifier != widget.feedVisibleNotifier) {
      oldWidget.feedVisibleNotifier?.removeListener(
        _handleParentVisibilityChanged,
      );
      if (widget.feedVisibleNotifier != null) {
        _isParentVisible = widget.feedVisibleNotifier!.value;
        widget.feedVisibleNotifier!.addListener(_handleParentVisibilityChanged);
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _tabController.dispose();
    _monetizationTimer?.cancel();
    // Keep the version that removes the parent visibility listener
    widget.feedVisibleNotifier?.removeListener(_handleParentVisibilityChanged);
    _unsubscribeFromLiveStreams();
    // Dispose header avatar rotation controller and clean up listener
    if (_headerRotateStatusListener != null) {
      _headerAvatarRotateController.removeStatusListener(
        _headerRotateStatusListener!,
      );
    }
    _headerAvatarRotateController.dispose();
    super.dispose();
  }

  Future<void> _initializeAdMob() async {
    await _adMobService.initialize();
  }

  Future<void> _loadPosts() async {
    try {
      // Start loading state immediately
      if (mounted) {
        setState(() {
          _isLoading = true;
          _hasError = false;
        });
      }

      // For You: apply one-time consent policy and silent update if allowed
      if (_selectedTab == 0) {
        if (!FeatureFlags.screenshotDemoMode) {
          try {
            final consent = await _locationService.getConsentChoice();
            final storedCountry = await _locationService.getStoredCountry();
            if (consent == null) {
              // Legacy users or fresh installs: prompt once
              if (mounted) {
                await showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text(LocalizationService.t('allow_location')),
                    content: Text(
                      LocalizationService.t(
                        'to_improve_your_local_feed_allow_location_access',
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () async {
                          // Persist deny
                          await _locationService.setConsentChoice(false);
                          if (ctx.mounted) Navigator.of(ctx).pop();
                        },
                        child: Text(LocalizationService.t('no_thanks')),
                      ),
                      TextButton(
                        onPressed: () async {
                          await _locationService.setConsentChoice(true);
                          if (ctx.mounted) Navigator.of(ctx).pop();
                          // Try to fetch and store location immediately
                          final ok = await _locationService
                              .updateUserProfileLocation();
                          if (ok && mounted) {
                            final messenger = ScaffoldMessenger.of(context);
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                  LocalizationService.t(
                                    'location_updated_local_feed_enabled',
                                  ),
                                ),
                                backgroundColor: Colors.green,
                              ),
                            );
                            _currentPage = 0;
                            await _loadPosts();
                          }
                        },
                        child: Text(LocalizationService.t('allow')),
                      ),
                    ],
                  ),
                );
              }
            } else if (consent == true && storedCountry == null) {
              // User allowed: attempt silent update to populate country
              await _locationService.updateUserProfileLocation();
            }
          } catch (_) {}
        }
      }

      // Fetch active live streams for For You tab
      if (_selectedTab == 0) {
        try {
          final streams = await _liveStreamingService.getActiveLiveStreams();
          // Defensive filter: only keep streams with status 'live' and no ended_at
          final fresh = streams.where((s) {
            final status = (s['status'] ?? '').toString();
            final endedAt = s['ended_at'];
            if (status != 'live' ||
                (endedAt != null && endedAt.toString().isNotEmpty)) {
              return false;
            }
            return _isStreamFresh(s);
          }).toList();
          _activeStreams = fresh;
        } catch (_) {
          _activeStreams = [];
        }
      } else {
        _activeStreams = [];
      }

      List<PostModel> posts;

      switch (_selectedTab) {
        case 0: // For You
          posts = await _postsService.getPersonalizedForYouPosts(
            limit: _pageSize,
            offset: _currentPage * _pageSize,
          );
          break;
        case 1: // Tracking
          posts = await _postsService.getTrackingPosts(
            limit: _pageSize,
            offset: _currentPage * _pageSize,
          );
          break;
        case 2: // Viral (Fair algorithm)
          posts = await _postsService.getViralPosts(
            limit: _pageSize,
            offset: _currentPage * _pageSize,
          );
          break;
        case 3: // Trending
          posts = await _postsService.getTrendingPosts(
            limit: _pageSize,
            offset: _currentPage * _pageSize,
          );
          break;
        default:
          posts = await _postsService.getPosts(
            limit: _pageSize,
            offset: _currentPage * _pageSize,
          );
      }

      // Demo mode: if no posts fetched, populate with sample posts
      if (FeatureFlags.screenshotDemoMode && posts.isEmpty) {
        // posts = _buildDemoPosts();
      }

      // Only update state if the widget is still mounted
      if (!mounted) return;
      setState(() {
        _posts = posts;
        _isLoading = false;
        _hasMorePosts =
            posts.length == _pageSize && !FeatureFlags.screenshotDemoMode;
      });
    } catch (e) {
      // Demo mode fallback on errors
      if (FeatureFlags.screenshotDemoMode) {
        // final demoPosts = _buildDemoPosts();
        // if (mounted) {
        //   setState(() {
        //     _posts = demoPosts;
        //     _isLoading = false;
        //     _hasError = false;
        //     _errorMessage = '';
        //     _hasMorePosts = false;
        //   });
        // }
        // return;
      }
      // Only update error state if still mounted
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
          _errorMessage = e.toString();
        });
      }
    }
  }

  // Subscribe to realtime changes on live_streams table
  void _subscribeToLiveStreams() {
    try {
      final client = Supabase.instance.client;
      _liveStreamsChannel = client
          .channel('public:live_streams')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'live_streams',
            callback: (payload) {
              _handleLiveStreamsChange(payload);
            },
          )
          .subscribe();
    } catch (e) {
      debugPrint('MainFeed: Failed to subscribe to live_streams: $e');
    }
  }

  void _unsubscribeFromLiveStreams() {
    try {
      if (_liveStreamsChannel != null) {
        Supabase.instance.client.removeChannel(_liveStreamsChannel!);
        _liveStreamsChannel = null;
      }
    } catch (e) {
      debugPrint('MainFeed: Failed to unsubscribe from live_streams: $e');
    }
  }

  void _handleLiveStreamsChange(PostgresChangePayload payload) {
    try {
      if (!mounted) return;
      final eventType = payload.eventType;
      final Map<String, dynamic> newRecord = payload.newRecord;
      final Map<String, dynamic> oldRecord = payload.oldRecord;
      final String? streamId = (newRecord['id'] ?? oldRecord['id'])?.toString();
      final String? newStatus = newRecord['status']?.toString();
      final String? oldStatus = oldRecord['status']?.toString();

      // Only affect For You tab items
      if (_selectedTab != 0) return;

      switch (eventType) {
        case PostgresChangeEvent.update:
          // Remove if transitioned from live to ended
          final endedAt = newRecord['ended_at'];
          final bool isNowEnded =
              (oldStatus == 'live' && newStatus == 'ended') ||
              (endedAt != null && endedAt.toString().isNotEmpty);
          if (isNowEnded && streamId != null) {
            if (!mounted) return;
            setState(() {
              _activeStreams.removeWhere(
                (s) => s['id']?.toString() == streamId,
              );
            });
          } else if (newStatus == 'live') {
            // Refresh to include potential new live stream updates
            _refreshActiveStreams();
          }
          break;
        case PostgresChangeEvent.insert:
          if (newStatus == 'live') {
            _refreshActiveStreams();
          }
          break;
        case PostgresChangeEvent.delete:
          if (streamId != null) {
            if (!mounted) return;
            setState(() {
              _activeStreams.removeWhere(
                (s) => s['id']?.toString() == streamId,
              );
            });
          }
          break;
        default:
          break;
      }
    } catch (e) {
      debugPrint('MainFeed: Error handling live_streams change: $e');
    }
  }

  Future<void> _refreshActiveStreams() async {
    try {
      final streams = await _liveStreamingService.getActiveLiveStreams();
      if (!mounted) return;
      setState(() {
        // Defensive + freshness filter: status live, not ended, and recently updated
        _activeStreams = streams.where((s) {
          final status = (s['status'] ?? '').toString();
          final endedAt = s['ended_at'];
          if (status != 'live' ||
              (endedAt != null && endedAt.toString().isNotEmpty)) {
            return false;
          }
          return _isStreamFresh(s);
        }).toList();
      });
    } catch (e) {
      debugPrint('MainFeed: Error refreshing active streams: $e');
    }
  }

  // Determine if a live stream record is fresh based on updated_at/started_at
  bool _isStreamFresh(Map<String, dynamic> s) {
    final tsString = (s['updated_at'] ?? s['started_at'])?.toString();
    final ts = DateTime.tryParse(tsString ?? '');
    if (ts == null) return false;
    return ts.isAfter(DateTime.now().subtract(_liveStaleThreshold));
  }

  // Start periodic monetization processing
  void _startMonetizationProcessing() {
    _monetizationTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
      _postsService.processMonetization();
    });
  }

  void _onPageChanged(int index) {
    if (!mounted) return;
    setState(() {
      _currentIndex = index;
    });

    // Show interstitial ads for viral posts (every 5th viral post)
    if (_selectedTab == 2 && _posts.isNotEmpty) {
      // Viral tab
      final currentPost = _posts[index];
      if (_adMobService.shouldShowAdsForPost(
        likesCount: currentPost.likesCount,
        commentsCount: currentPost.commentsCount,
        adsEnabled: currentPost.adsEnabled,
      )) {
        _viralPostViewCount++;
        if (_viralPostViewCount % 5 == 0) {
          _adMobService.showInterstitialAd();
        }
      }
    }

    // Load more posts when approaching the end
    if (index >= _posts.length - 3 && !_isLoadingMore && _hasMorePosts) {
      _loadMorePosts();
    }
  }

  Future<void> _loadMorePosts() async {
    if (_isLoadingMore || !_hasMorePosts) return;

    // In screenshot demo mode, disable pagination
    if (FeatureFlags.screenshotDemoMode) {
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
          _hasMorePosts = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isLoadingMore = true;
      });
    }

    try {
      List<PostModel> morePosts;

      switch (_selectedTab) {
        case 0: // For You
          morePosts = await _postsService.getPersonalizedForYouPosts(
            limit: _pageSize,
            offset: (_currentPage + 1) * _pageSize,
          );
          break;
        case 1: // Tracking
          morePosts = await _postsService.getTrackingPosts(
            limit: _pageSize,
            offset: (_currentPage + 1) * _pageSize,
          );
          break;
        case 2: // Viral (Fair algorithm)
          morePosts = await _postsService.getViralPosts(
            limit: _pageSize,
            offset: (_currentPage + 1) * _pageSize,
          );
          break;
        case 3: // Trending
          morePosts = await _postsService.getTrendingPosts(
            limit: _pageSize,
            offset: (_currentPage + 1) * _pageSize,
          );
          break;
        default:
          morePosts = await _postsService.getPosts(
            limit: _pageSize,
            offset: (_currentPage + 1) * _pageSize,
          );
      }

      if (!mounted) return;
      setState(() {
        _posts.addAll(morePosts);
        _currentPage++;
        _isLoadingMore = false;
        _hasMorePosts = morePosts.length == _pageSize;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
          _hasMorePosts = false;
        });
      }
    }
  }

  void _onTabChanged(int index) {
    setState(() {
      _selectedTab = index;
      _currentPage = 0;
    });
    _loadPosts();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
        ),
      );
    }

    if (_hasError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 64),
            const SizedBox(height: 16),
            Text(
              LocalizationService.t('failed_to_load_posts'),
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage,
              style: GoogleFonts.poppins(color: Colors.white70, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loadPosts,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
              child: Text(
                LocalizationService.t('retry'),
                style: GoogleFonts.poppins(),
              ),
            ),
          ],
        ),
      );
    }

    // Show empty state only when both posts and live streams are absent
    if (_posts.isEmpty && _activeStreams.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.inbox_outlined, color: Colors.white, size: 64),
            const SizedBox(height: 16),
            Text(
              LocalizationService.t('no_posts_available'),
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Check back later for new content',
              style: GoogleFonts.poppins(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        // Main content
        NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification is ScrollStartNotification) {
              // As soon as scroll starts, mark all posts inactive
              if (mounted) {
                setState(() {
                  _isScrolling = true;
                });
              }
            } else if (notification is ScrollEndNotification) {
              // Scrolling ended; allow the active page to resume
              if (mounted) {
                setState(() {
                  _isScrolling = false;
                });
              }
            }
            return false;
          },
          child: PageView.builder(
            controller: _pageController,
            scrollDirection: Axis.vertical,
            onPageChanged: _onPageChanged,
            itemCount: _getItemCount(),
            itemBuilder: (context, index) {
              return _buildFeedItem(index);
            },
          ),
        ),

        // Side action bar
        Positioned(
          right: 16,
          bottom: 100,
          child: Builder(
            builder: (context) {
              final bool isViralTab = _selectedTab == 2;
              final bool isAd = isViralTab && ((_currentIndex + 1) % 4 == 0);
              // Map current index to post index depending on tab and live items
              int? mappedIndex;
              if (isViralTab) {
                mappedIndex = _currentIndex - (_currentIndex ~/ 4);
              } else if (_selectedTab == 0) {
                // For You: live stream items occupy the first indices
                if (_currentIndex < _activeStreams.length) {
                  mappedIndex = null; // Live item: hide SideActionBar
                } else {
                  mappedIndex = _currentIndex - _activeStreams.length;
                }
              } else {
                mappedIndex = _currentIndex;
              }
              final bool hasPost =
                  !isAd &&
                  mappedIndex != null &&
                  _posts.isNotEmpty &&
                  mappedIndex >= 0 &&
                  mappedIndex < _posts.length;
              final PostModel? currentPost = hasPost
                  ? _posts[mappedIndex]
                  : null;
              return SideActionBar(
                post: currentPost,
                onLike: hasPost ? () => _handleLike(mappedIndex!) : null,
                onComment: hasPost ? () => _handleComment(mappedIndex!) : null,
                onShare: hasPost ? () => _handleShare(mappedIndex!) : null,
                onDelete:
                    hasPost &&
                        _authService.currentUser != null &&
                        currentPost!.userId == _authService.currentUser!.id
                    ? () => _handleDelete(mappedIndex!)
                    : null,
                onDuet:
                    hasPost &&
                        _authService.currentUser != null &&
                        currentPost!.userId != _authService.currentUser!.id
                    ? () => _handleDuet(mappedIndex!)
                    : null,
                onOptimize: null,
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _handleOptimize(int index) async {
    if (index < 0 || index >= _posts.length) return;
    final PostModel post = _posts[index];
    if (post.mediaType != MediaType.video) return;
    HapticFeedback.lightImpact();
    try {
      // Show progress dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                LocalizationService.t('optimizing_video'),
                style: GoogleFonts.poppins(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );

      final String newUrl = await _optimizationService.optimizePostVideo(post);

      // Close dialog and notify
      if (mounted) Navigator.of(context).pop();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(LocalizationService.t('optimization_complete')),
          ),
        );
        // Optionally replace the local mediaUrl so playback refreshes
        setState(() {
          _posts[index] = _posts[index].copyWith(mediaUrl: newUrl);
        });
      }
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      if (mounted) {
        final err = e.toString();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${LocalizationService.t('optimization_failed')}: $err',
            ),
          ),
        );
      }
    }
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      title: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            _buildTabButton(LocalizationService.t('for_you'), 0),
            const SizedBox(width: 12),
            _buildTabButton(LocalizationService.t('following'), 1),
            const SizedBox(width: 12),
            _buildTabButton(LocalizationService.t('viral'), 2),
            const SizedBox(width: 12),
            _buildTabButton(LocalizationService.t('trending'), 3),
          ],
        ),
      ),
      actions: [],
      // Removed StatusBar from AppBar bottom to eliminate status avatar strip
      // bottom: const StatusBar(),
      // Hide Statuses and Add Status buttons
      // bottom: PreferredSize(
      //   preferredSize: const Size.fromHeight(56),
      //   child: SizedBox.shrink(),
      // ),
    );
  }

  Widget _buildTabButton(String title, int index) {
    final isSelected = _selectedTab == index;
    return GestureDetector(
      onTap: () => _onTabChanged(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.white.withValues(alpha: 0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: isSelected
              ? Border.all(color: Colors.white.withValues(alpha: 0.3))
              : null,
        ),
        child: Text(
          title,
          style: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Future<void> _handleLike(int index) async {
    if (index >= _posts.length) return;

    final post = _posts[index];
    final wasLiked = post.isLiked;

    // Optimistic update
    setState(() {
      _posts[index] = post.copyWith(
        isLiked: !wasLiked,
        likes: wasLiked ? post.likes - 1 : post.likes + 1,
      );
    });

    try {
      await _postsService.toggleLike(post.id);

      // Flush analytics so the Analytics screen reflects the change promptly
      try {
        final analytics = AnalyticsService();
        await analytics.flushPendingEvents();
      } catch (e) {
        debugPrint('_handleLike: analytics flush failed: $e');
      }
    } catch (e) {
      // Revert on error
      setState(() {
        _posts[index] = post.copyWith(isLiked: wasLiked, likes: post.likes);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to ${wasLiked ? 'unlike' : 'like'} post',
              style: GoogleFonts.poppins(),
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    }
  }

  void _handleComment(int index) {
    if (index >= 0 && index < _posts.length) {
      final post = _posts[index];
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) =>
              CommentsScreen(postId: post.id, postAuthorId: post.userId),
        ),
      ).then((result) {
        if (!mounted) return;
        // Update comment count if comments were added/removed
        if (result != null && result is int) {
          setState(() {
            _posts[index] = PostModel(
              id: post.id,
              userId: post.userId,
              username: post.username,
              userAvatar: post.userAvatar,
              isVerified: post.isVerified,
              content: post.content,
              mediaType: post.mediaType,
              mediaUrl: post.mediaUrl,
              location: post.location,
              hashtags: post.hashtags,
              likes: post.likes,
              comments: result,
              shares: post.shares,
              isLiked: post.isLiked,
              timestamp: post.timestamp,
            );
          });
        }
      });
    }
  }

  void _handleShare(int index) async {
    if (index >= _posts.length) return;

    final post = _posts[index];
    final currentUser = _authService.currentUser;

    try {
      // Track share analytics
      await _analyticsService.trackPostShare(
        post.id,
        post.mediaType.toString(),
        'native_share',
      );

      // Update share count in database
      await _socialService.sharePost(post.id);

      // Create notification for post owner (only if not sharing own post)
      if (currentUser != null && post.userId != currentUser.id) {
        await _notificationService.createNotification(
          userId: post.userId,
          type: 'share',
          title: 'Post Shared',
          message:
              '${currentUser.userMetadata?['username'] ?? 'Someone'} shared your post',
          data: {
            'post_id': post.id,
            'sharer_id': currentUser.id,
            'sharer_username':
                currentUser.userMetadata?['username'] ?? 'Unknown',
            'post_content': post.content.length > 50
                ? '${post.content.substring(0, 50)}...'
                : post.content,
          },
        );
      }

      // Create shareable content
      String shareText = '';
      if (post.content.isNotEmpty) {
        shareText = post.content.length > 100
            ? '${post.content.substring(0, 100)}...'
            : post.content;
      }

      final shareContent = shareText.isNotEmpty
          ? 'Check out this post by @${post.username}: "$shareText"\n\nhttps://play.google.com/store/apps/details?id=com.equal.app.equal\n\nDownload Equal app to see more amazing content!'
          : 'Check out this amazing post by @${post.username} on Equal!\n\nhttps://play.google.com/store/apps/details?id=com.equal.app.equal\n\nDownload Equal app to see more amazing content!';

      // Share using native share dialog
      await Share.share(
        shareContent,
        subject: 'Amazing post on Equal by @${post.username}',
      );

      // Update local share count
      if (!mounted) return;
      setState(() {
        _posts[index] = PostModel(
          id: post.id,
          userId: post.userId,
          username: post.username,
          userAvatar: post.userAvatar,
          isVerified: post.isVerified,
          content: post.content,
          mediaType: post.mediaType,
          mediaUrl: post.mediaUrl,
          location: post.location,
          hashtags: post.hashtags,
          likes: post.likes,
          comments: post.comments,
          shares: post.shares + 1,
          isLiked: post.isLiked,
          timestamp: post.timestamp,
        );
      });
    } catch (e) {
      debugPrint(('Error sharing post: $e').toString());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            LocalizationService.t('failed_to_share_post'),
            style: GoogleFonts.poppins(),
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  Future<void> _handleDelete(int index) async {
    if (index >= _posts.length) return;

    final post = _posts[index];
    final currentUser = _authService.currentUser;
    // Capture messenger before any await to avoid using BuildContext across async gaps
    final messenger = ScaffoldMessenger.of(context);

    if (currentUser == null || post.userId != currentUser.id) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            LocalizationService.t('you_can_only_delete_your_own_posts'),
            style: GoogleFonts.poppins(),
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
      return;
    }

    // Show confirmation dialog
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text(
          LocalizationService.t('delete_post'),
          style: GoogleFonts.poppins(color: Colors.white),
        ),
        content: Text(
          LocalizationService.t('delete_post_confirmation'),
          style: GoogleFonts.poppins(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              LocalizationService.t('cancel'),
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              LocalizationService.t('delete'),
              style: GoogleFonts.poppins(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (shouldDelete == true) {
      try {
        await _postsService.deletePost(post.id);

        // Remove post from local list
        if (!mounted) return;
        setState(() {
          _posts.removeAt(index);
        });

        if (mounted) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                LocalizationService.t('post_deleted_success'),
                style: GoogleFonts.poppins(),
              ),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                '${LocalizationService.t('failed_delete_post')}: ${e.toString()}',
                style: GoogleFonts.poppins(),
              ),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        }
      }
    }
  }

  void _handleDuet(int index) {
    if (index >= _posts.length) return;

    final post = _posts[index];
    final currentUser = _authService.currentUser;

    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please log in to create a Harmony',
            style: GoogleFonts.poppins(),
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
      return;
    }

    if (post.userId == currentUser.id) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'You cannot create a Harmony with your own post',
            style: GoogleFonts.poppins(),
          ),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
      return;
    }

    // Navigate to harmony creation screen
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ContentTypeSelectionScreen(parentPostId: post.id),
      ),
    );
  }

  int _getItemCount() {
    if (_selectedTab == 2) {
      // Viral tab with native ads
      // Add native ads every 3 posts
      return _posts.length + (_posts.length ~/ 3);
    }
    // For You tab: include live streams as items at top
    if (_selectedTab == 0) {
      return _activeStreams.length + _posts.length;
    }
    return _posts.length;
  }

  Widget _buildFeedItem(int index) {
    if (_selectedTab == 2) {
      // Viral tab with native ads
      // Every 4th item (index 3, 7, 11, etc.) is a native ad
      if ((index + 1) % 4 == 0) {
        return Container(
          width: double.infinity,
          height: double.infinity,
          color: Colors.black,
          child: const Center(child: FeedNativeAd()),
        );
      }

      // Calculate the actual post index (accounting for ads)
      final postIndex = index - (index ~/ 4);
      if (postIndex >= _posts.length) {
        return const SizedBox.shrink();
      }

      return PostWidget(
        post: _posts[postIndex],
        isActive: index == _currentIndex && !_isScrolling && _isParentVisible,
      );
    }

    // For You tab: render live stream items first
    if (_selectedTab == 0) {
      if (index < _activeStreams.length) {
        return _buildLiveStreamFeedItem(_activeStreams[index]);
      }
      final postIndex = index - _activeStreams.length;
      if (postIndex >= _posts.length) {
        return const SizedBox.shrink();
      }
      return PostWidget(
        post: _posts[postIndex],
        isActive: index == _currentIndex && !_isScrolling && _isParentVisible,
      );
    }

    // For other tabs, show posts normally
    if (index >= _posts.length) {
      return const SizedBox.shrink();
    }

    return PostWidget(
      post: _posts[index],
      isActive: index == _currentIndex && !_isScrolling && _isParentVisible,
    );
  }

  // Live stream feed item (full-screen card with Join action)
  Widget _buildLiveStreamFeedItem(Map<String, dynamic> stream) {
    final String streamId = stream['id']?.toString() ?? '';
    final String title = (stream['title'] ?? 'Live Stream').toString();
    final String description = (stream['description'] ?? '').toString();
    final int viewerCount = (stream['viewer_count'] ?? 0) is int
        ? stream['viewer_count']
        : int.tryParse(stream['viewer_count']?.toString() ?? '0') ?? 0;
    final Map<String, dynamic>? user = stream['users'] is Map<String, dynamic>
        ? (stream['users'] as Map<String, dynamic>)
        : null;
    final String username = (user?['username'] ?? 'Unknown').toString();
    final String? avatarUrl = user?['avatar_url']?.toString();
    final String? ownerId = stream['user_id']?.toString();
    final String? myId = _authService.currentUser?.id;
    final bool isOwnStream = ownerId != null && myId != null && ownerId == myId;

    return GestureDetector(
      onTap: isOwnStream
          ? () {
              final snack = SnackBar(
                content: const Text('You cannot join your own livestream'),
                backgroundColor: Colors.orange,
              );
              ScaffoldMessenger.of(context).showSnackBar(snack);
            }
          : () => _openLiveViewer(
              streamId,
              title: title,
              description: description,
            ),
      child: Container(
        width: double.infinity,
        height: double.infinity,
        color: Colors.black,
        child: Stack(
          children: [
            // Background gradient
            Positioned.fill(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xFF0F0F0F),
                      Color(0xFF1A1A1A),
                      Color(0xFF0F0F0F),
                    ],
                  ),
                ),
              ),
            ),

            // Content
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header: avatar + username + LIVE badge
                    Row(
                      children: [
                        AnimatedBuilder(
                          animation: _headerAvatarRotateController,
                          builder: (context, child) {
                            return Transform.rotate(
                              angle: _headerAvatarRotateController.value,
                              child: child,
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.redAccent,
                                width: 3,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.redAccent.withOpacity(0.6),
                                  blurRadius: 8,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                            child: CircleAvatar(
                              radius: 24,
                              backgroundColor: const Color(0xFF2A2A2A),
                              backgroundImage:
                                  avatarUrl != null && avatarUrl.isNotEmpty
                                  ? NetworkImage(avatarUrl)
                                  : null,
                              child: (avatarUrl == null || avatarUrl.isEmpty)
                                  ? Text(
                                      username.isNotEmpty
                                          ? username[0].toUpperCase()
                                          : '?',
                                      style: GoogleFonts.poppins(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    )
                                  : null,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '@$username',
                                style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.redAccent,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'LIVE',
                                  style: GoogleFonts.poppins(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Viewer count
                        Row(
                          children: [
                            const Icon(
                              Icons.visibility,
                              color: Colors.white70,
                              size: 18,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              viewerCount.toString(),
                              style: GoogleFonts.poppins(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Title
                    Text(
                      title,
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),

                    const SizedBox(height: 8),

                    // Description
                    if (description.isNotEmpty)
                      Text(
                        description,
                        style: GoogleFonts.poppins(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),

                    const Spacer(),

                    // Join button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: isOwnStream
                            ? () {
                                final snack = SnackBar(
                                  content: const Text(
                                    'You cannot join your own livestream',
                                  ),
                                  backgroundColor: Colors.orange,
                                );
                                ScaffoldMessenger.of(
                                  context,
                                ).showSnackBar(snack);
                              }
                            : () => _openLiveViewer(
                                streamId,
                                title: title,
                                description: description,
                              ),
                        icon: const Icon(
                          Icons.play_circle_fill,
                          color: Colors.white,
                        ),
                        label: Text(
                          isOwnStream ? 'Your Live (cannot join)' : 'Join Live',
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openLiveViewer(
    String streamId, {
    String? title,
    String? description,
  }) async {
    if (streamId.isEmpty) return;

    try {
      final active = await _liveStreamingService.getActiveLiveStreams();
      final exists = active.any((s) => (s['id']?.toString() ?? '') == streamId);
      if (!exists) {
        if (!mounted) return;
        final snack = SnackBar(
          content: const Text('This live has ended'),
          backgroundColor: Colors.orange,
        );
        ScaffoldMessenger.of(context).showSnackBar(snack);
        setState(() {
          _activeStreams.removeWhere(
            (s) => (s['id']?.toString() ?? '') == streamId,
          );
        });
        return;
      }
    } catch (_) {}

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LiveStreamViewerScreen(
          streamId: streamId,
          title: title,
          description: description,
        ),
      ),
    );
  }

  // ignore: unused_element
  String _getFeedType() {
    switch (_selectedTab) {
      case 0:
        return 'for_you';
      case 1:
        return 'following';
      case 2:
        return 'viral';
      case 3:
        return 'trending';
      default:
        return 'for_you';
    }
  }

  void _startHeaderAvatarSpinCycle() {
    if (_avatarSpinCycleRunning) return;
    _avatarSpinCycleRunning = true;
    _runSpinPhase(forward: true);
  }

  void _runSpinPhase({required bool forward}) {
    if (!mounted) return;
    // Reset controller
    try {
      _headerAvatarRotateController.stop();
    } catch (_) {
      // Guard against stop() invoked after dispose
      return;
    }
    _headerAvatarRotateController.duration = const Duration(seconds: 5);
    _headerAvatarRotateController.reset();
    _avatarRotateDirection = forward ? 1 : -1;

    // Phase 1: slow rotation for 5 seconds, then accelerate and decelerate
    _headerRotateStatusListener = (status) {
      if (status == AnimationStatus.completed) {
        if (_headerRotateStatusListener != null) {
          _headerAvatarRotateController.removeStatusListener(
            _headerRotateStatusListener!,
          );
        }
        _accelerateRotation().then((_) async {
          await _decelerateRotation();
          if (!mounted) return;
          // After stopping, do opposite side
          _runSpinPhase(forward: !forward);
        });
      }
    };
    _headerAvatarRotateController.addStatusListener(
      _headerRotateStatusListener!,
    );

    _headerAvatarRotateController.animateTo(1.0, curve: Curves.linear);
  }

  Future<void> _accelerateRotation() async {
    const steps = 30; // number of acceleration steps
    for (int i = 0; i < steps; i++) {
      if (!mounted) return;
      final t = i / (steps - 1);
      final speed = lerpDouble(
        0.05,
        1.5,
        t,
      )!; // from slow to very fast radians per tick
      _headerAvatarRotateController.value += speed * _avatarRotateDirection;
      await Future.delayed(const Duration(milliseconds: 60));
    }
  }

  Future<void> _decelerateRotation() async {
    const steps = 30;
    for (int i = 0; i < steps; i++) {
      if (!mounted) return;
      final t = i / (steps - 1);
      final speed = lerpDouble(1.5, 0.0, t)!; // from fast to stop
      _headerAvatarRotateController.value += speed * _avatarRotateDirection;
      await Future.delayed(const Duration(milliseconds: 60));
    }
  }
}

double? lerpDouble(double a, double b, double t) {
  return a + (b - a) * t;
}
