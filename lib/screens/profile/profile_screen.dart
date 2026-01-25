import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/auth_service.dart';
import '../../services/posts_service.dart';
import '../../services/enhanced_messaging_service.dart';
import '../../models/post_model.dart';
import '../../config/app_colors.dart';
import '../../config/supabase_config.dart';
import '../../widgets/custom_button.dart';
import '../messaging/enhanced_chat_screen.dart';
import '../post_detail_screen.dart';
import 'edit_profile_screen.dart';
import 'settings_screen.dart';
import 'livestream_history_screen.dart';
import '../live_stream_viewer_screen.dart';
import '../../services/live_streaming_service.dart';
import '../../services/content_service.dart';
import '../../services/localization_service.dart';
import '../../services/ai_service.dart';
import 'storage_management_screen.dart';
import 'analytics_screen.dart';
import '../../services/app_service.dart';
import 'package:video_player/video_player.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

class ProfileScreen extends StatefulWidget {
  final String? userId;

  const ProfileScreen({super.key, this.userId});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with TickerProviderStateMixin {
  final _authService = AuthService();
  final _postsService = PostsService();
  final _contentService = ContentService();
  final _aiService = AIService();
  late TabController _tabController;

  Map<String, dynamic>? _userProfile;
  bool _isLoading = true;
  bool _isOwnProfile = false;
  bool _isFollowing = false;
  bool _hasBlockedUser = false;
  bool _isLoadingPosts = false;

  List<PostModel> _posts = [];
  final List<PostModel> _likedPosts = [];
  List<PostModel> _harmonyPosts = [];

  // Streams support
  final LiveStreamingService _liveStreamingService = LiveStreamingService();
  List<LiveStreamModel> _streams = [];
  bool _isLoadingStreams = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_onTabChanged);
    _isOwnProfile =
        widget.userId == null || widget.userId == _authService.currentUser?.id;
    _loadUserProfile();
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging && _tabController.index == 2) {
      _loadStreamsIfNeeded();
    }
  }

  Future<void> _loadStreamsIfNeeded() async {
    if (_isLoadingStreams) return;
    if (_streams.isNotEmpty) return;
    await _loadStreams();
  }

  Future<void> _loadStreams() async {
    setState(() => _isLoadingStreams = true);
    try {
      final targetUserId = _userProfile?['id']?.toString() ?? widget.userId;
      final streams = await _liveStreamingService.getUserStreams(
        userId: targetUserId,
        limit: 50,
      );
      if (mounted) {
        setState(() {
          _streams = streams;
          _isLoadingStreams = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingStreams = false);
    }
  }

  Future<void> _loadUserProfile() async {
    try {
      final profile = await _authService.getUserProfile(widget.userId);
      if (mounted && profile != null) {
        // Determine ownership based on loaded profile ID (more reliable than widget.userId)
        final bool isOwn = profile['id'] == _authService.currentUser?.id;

        // Check if there's a blocking relationship
        bool isBlockedByUser = false;
        bool hasBlockedUser = false;
        bool isFollowing = false;

        if (!isOwn && _authService.currentUser != null) {
          // Check if current user is blocked by this user
          isBlockedByUser = await _authService.isBlockedBy(profile['id']);

          // Check if current user has blocked this user
          hasBlockedUser = await _authService.isBlocked(profile['id']);

          // Only check following status if not blocked
          if (!isBlockedByUser && !hasBlockedUser) {
            isFollowing = await _authService.isFollowing(profile['id']);
          }
        }

        // If blocked by user, show restricted access
        if (isBlockedByUser) {
          if (mounted) {
            setState(() => _isLoading = false);
            _showBlockedByUserDialog();
          }
          return;
        }

        setState(() {
          _userProfile = profile;
          _isOwnProfile = isOwn;
          _isFollowing = isFollowing;
          _hasBlockedUser = hasBlockedUser;
          _isLoading = false;
        });

        // Load user posts only if not blocked
        if (!hasBlockedUser) {
          _loadUserPosts();
        }
      } else if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadUserPosts() async {
    if (_userProfile == null) return;

    setState(() => _isLoadingPosts = true);

    try {
      final results = await Future.wait([
        _postsService.getUserPosts(userId: _userProfile!['id'], limit: 50),
        _contentService.getLikedPosts(_userProfile!['id'], limit: 50),
      ]);

      final posts = results[0] as List<PostModel>;
      final likedMaps = (results[1] as List)
          .whereType<Map<String, dynamic>>()
          .toList();

      final likedPosts = likedMaps.map((m) {
        final users = m['users'] as Map<String, dynamic>?;
        final userId = (users != null && users['id'] != null)
            ? users['id'].toString()
            : (m['user_id']?.toString() ?? '');
        return PostModel.fromJson({
          ...m,
          // Normalize keys to PostModel expectations
          'type': m['type'] as String?,
          'user_id': userId,
          'user': users == null
              ? null
              : {
                  'username': users['username'],
                  'display_name': users['display_name'],
                  'avatar_url': users['avatar_url'],
                  // is_verified may not be present; default handled in model
                },
          'is_liked': true,
        });
      }).toList();

      if (mounted) {
        setState(() {
          _posts = posts;
          _likedPosts
            ..clear()
            ..addAll(likedPosts);
          _harmonyPosts = posts
              .where((p) => (p.parentPostId?.isNotEmpty ?? false))
              .toList();
          _isLoadingPosts = false;
        });
      }
    } catch (e) {
      debugPrint(('Error loading user posts or liked posts: $e').toString());
      if (mounted) {
        setState(() => _isLoadingPosts = false);
      }
    }
  }

  Future<void> _handleFollowToggle() async {
    if (!_isOwnProfile && _userProfile != null) {
      // Check blocking status before allowing follow actions
      final isBlocked = await _authService.isBlocked(_userProfile!['id']);
      final isBlockedBy = await _authService.isBlockedBy(_userProfile!['id']);

      if (isBlocked || isBlockedBy) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(LocalizationService.t('cannot_track_user')),
              backgroundColor: AppColors.error,
            ),
          );
        }
        return;
      }

      HapticFeedback.lightImpact();

      try {
        if (_isFollowing) {
          await _authService.unfollowUser(_userProfile!['id']);
        } else {
          await _authService.followUser(_userProfile!['id']);
        }

        setState(() {
          _isFollowing = !_isFollowing;
          if (_isFollowing) {
            _userProfile!['followers_count'] =
                (_userProfile!['followers_count'] ?? 0) + 1;
          } else {
            _userProfile!['followers_count'] =
                (_userProfile!['followers_count'] ?? 1) - 1;
          }
        });
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _isFollowing
                    ? LocalizationService.t('failed_unfollow_user')
                    : LocalizationService.t('failed_follow_user'),
              ),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }

  Future<void> _handleSignOut() async {
    final shouldSignOut = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          LocalizationService.t('sign_out'),
          style: const TextStyle(color: AppColors.textPrimary),
        ),
        content: Text(
          LocalizationService.t('confirm_sign_out'),
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              LocalizationService.t('cancel'),
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              LocalizationService.t('sign_out'),
              style: const TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );

    if (shouldSignOut == true) {
      try {
        // Perform full sign-out via AppService; AuthWrapper will route accordingly
        await AppService().signOut();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const LocalizedText('failed_sign_out'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }

  // Cache-bust avatar URLs to ensure immediate refresh after updates
  String _cacheBustedAvatarUrl(String url) {
    final updatedAt = _userProfile?['updated_at'];
    final version = (updatedAt is String && updatedAt.isNotEmpty)
        ? updatedAt
        : DateTime.now().millisecondsSinceEpoch.toString();
    final separator = url.contains('?') ? '&' : '?';
    return '$url${separator}v=$version';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    if (_userProfile == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back_ios, color: AppColors.textPrimary),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.person_off, size: 64, color: AppColors.textSecondary),
              const SizedBox(height: 16),
              const LocalizedText('User not found'),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: _isOwnProfile
            ? null
            : IconButton(
                icon: Icon(
                  Icons.arrow_back_ios,
                  color: AppColors.textPrimary,
                ),
                onPressed: () => Navigator.pop(context),
              ),
        title: Text(
          _userProfile!['username'] ?? LocalizationService.t('profile'),
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          if (_isOwnProfile)
            IconButton(
              icon: Icon(
                Icons.bar_chart_rounded,
                color: AppColors.textPrimary,
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AnalyticsScreen(),
                  ),
                );
              },
              tooltip: LocalizationService.t('analytics'),
            ),
          if (_isOwnProfile)
            IconButton(
              icon: Icon(Icons.settings, color: AppColors.textPrimary),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const SettingsScreen(),
                  ),
                );
              },
            ),
          IconButton(
            icon: Icon(Icons.more_vert, color: AppColors.textPrimary),
            onPressed: () {
              _showMoreOptions();
            },
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Fixed profile header (non-scrollable)
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                // Avatar and Stats
                Row(
                  children: [
                    // Avatar
                    Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: AppColors.primaryGradient,
                        border: Border.all(
                          color: AppColors.primary,
                          width: 3,
                        ),
                      ),
                      child: _userProfile!['avatar_url'] != null &&
                              _userProfile!['avatar_url'].isNotEmpty
                          ? ClipOval(
                              child: Image.network(
                                _cacheBustedAvatarUrl(
                                  _userProfile!['avatar_url'],
                                ),
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) =>
                                    _buildDefaultAvatar(),
                              ),
                            )
                          : _buildDefaultAvatar(),
                    ),

                    const SizedBox(width: 20),

                    // Stats
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildStatColumn(
                            LocalizationService.t('posts'),
                            (_userProfile!['posts_count'] != null
                                ? _userProfile!['posts_count'].toString()
                                : _posts.length.toString()),
                          ),
                          if (_isOwnProfile) ...[
                            _buildStatColumn(
                              LocalizationService.t('followers'),
                              _formatCount(
                                _userProfile!['followers_count'] ?? 0,
                              ),
                            ),
                            _buildStatColumn(
                              LocalizationService.t('following'),
                              _formatCount(
                                _userProfile!['following_count'] ?? 0,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Name and Bio
                Align(
                  alignment: Alignment.centerLeft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _userProfile!['display_name'] ?? 'User',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (((_userProfile!['is_verified'] == true) ||
                              ((_userProfile!['username']
                                      ?.toString()
                                      .toLowerCase()) ==
                                  'equal') ||
                              ((_userProfile!['username']
                                      ?.toString()
                                      .toLowerCase()) ==
                                  'vigny'))) ...[
                            const SizedBox(width: 4),
                            Icon(
                              Icons.verified,
                              color: (((_userProfile!['username']
                                          ?.toString()
                                          .toLowerCase()) ==
                                      'vigny')
                                  ? Colors.blue
                                  : AppColors.gold),
                              size: 16,
                            ),
                          ],
                        ],
                      ),
                      if (_userProfile!['bio'] != null &&
                          _userProfile!['bio'].isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          _userProfile!['bio'],
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                      if (_userProfile!['created_at'] != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          _formatJoinDate(_userProfile!['created_at']),
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary.withOpacity(0.9),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Action Buttons
                Row(
                  children: [
                    if (_isOwnProfile) ...[
                      Expanded(
                        child: CustomButton(
                          text: LocalizationService.t('edit_profile'),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => EditProfileScreen(
                                  userProfile: _userProfile!,
                                ),
                              ),
                            ).then((_) => _loadUserProfile());
                          },
                          isOutlined: true,
                        ),
                      ),
                    ] else ...[
                      Expanded(
                        child: CustomButton(
                          text: _isFollowing
                              ? LocalizationService.t('following')
                              : LocalizationService.t('follow'),
                          onPressed: _handleFollowToggle,
                          isOutlined: _isFollowing,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: CustomButton(
                          text: _hasBlockedUser
                              ? LocalizationService.t('unblock')
                              : LocalizationService.t('block'),
                          onPressed: () async {
                            if (_hasBlockedUser) {
                              await _handleUnblockUser();
                            } else {
                              _showBlockDialog();
                            }
                          },
                          isOutlined: true,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppColors.border,
                            width: 1,
                          ),
                        ),
                        child: IconButton(
                          icon: Icon(
                            Icons.message,
                            color: AppColors.textPrimary,
                            size: 20,
                          ),
                          onPressed: () {
                            _navigateToChat();
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),

          // Fixed TabBar below header
          Container(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppColors.border, width: 1),
              ),
            ),
            child: Material(
              color: AppColors.background,
              child: SizedBox(
                height: kTextTabBarHeight,
                child: TabBar(
                  controller: _tabController,
                  indicator: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.35),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  labelColor: Colors.white,
                  unselectedLabelColor: AppColors.textSecondary,
                  isScrollable: false,
                  labelPadding: const EdgeInsets.symmetric(horizontal: 10),
                  labelStyle: const TextStyle(fontSize: 12),
                  unselectedLabelStyle: const TextStyle(fontSize: 12),
                  tabs: [
                    Tab(icon: const Icon(Icons.grid_on), text: LocalizationService.t('posts')),
                    Tab(icon: const Icon(Icons.favorite_border), text: LocalizationService.t('liked')),
                    Tab(icon: const Icon(Icons.videocam), text: LocalizationService.t('streams')),
                    Tab(icon: const Icon(Icons.call_split), text: LocalizationService.t('harmonies')),
                  ],
                ),
              ),
            ),
          ),

          // Only posts area scrolls
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildPostsGrid(_posts),
                _buildPostsGrid(_likedPosts),
                _buildStreamsTab(),
                _buildPostsGrid(_harmonyPosts),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDefaultAvatar() {
    return Container(
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: AppColors.primaryGradient,
      ),
      child: Center(
        child: Text(
          (_userProfile!['display_name'] ?? 'U')[0]
              .toUpperCase(), // Fixed: use display_name instead of full_name
          style: const TextStyle(
            color: Colors.white,
            fontSize: 32,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildStatColumn(String label, String count) {
    return Column(
      children: [
        Text(
          count,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }

  Widget _buildPostsGrid(List<PostModel> posts) {
    if (_isLoadingPosts) {
      return Center(child: CircularProgressIndicator(color: AppColors.primary));
    }

    if (posts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.photo_library_outlined,
              size: 64,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 16),
            Text(
              LocalizationService.t('no_posts_yet'),
              style: TextStyle(fontSize: 18, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            Text(
              'Start creating amazing content!',
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(2),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
      ),
      itemCount: posts.length,
      itemBuilder: (context, index) {
        final post = posts[index];
        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => PostDetailScreen(post: post),
              ),
            );
          },
          onLongPress: (_isOwnProfile && (post.userId == _authService.currentUser?.id))
              ? () => _showPostOptions(post, index)
              : null,
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Post thumbnail or rich preview
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: _GridTilePreview(post: post),
                ),

                // Post type indicator
                if (post.type == 'video')
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Icon(
                        Icons.play_arrow,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
                if (post.type == 'audio')
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Icon(
                        Icons.music_note,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
                if (post.type == 'text')
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Icon(
                        Icons.article,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ),

                // Duration overlay for video/audio
                if ((post.type == 'video' || post.type == 'audio') &&
                    post.duration != null)
                  Positioned(
                    bottom: 4,
                    left: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        _formatDuration(post.duration!),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),

                // Engagement stats
                Positioned(
                  bottom: 4,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.favorite,
                          color: Colors.white,
                          size: 12,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          _formatCount(post.likesCount),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ignore: unused_element
  Widget _buildPostPlaceholder(PostModel post) {
    final postType = post.type;
    if (postType == 'text') {
      final snippet = post.content.trim();
      return Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.all(8),
        child: Text(
          snippet.isEmpty ? 'Tap to view' : snippet,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
          textAlign: TextAlign.left,
        ),
      );
    }

    if (postType == 'audio') {
      return Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.music_note, color: AppColors.textSecondary, size: 28),
            const SizedBox(height: 8),
            // Show optional title snippet if present
            if (post.content.isNotEmpty)
              Text(
                post.content,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _eqBar(height: 10),
                const SizedBox(width: 3),
                _eqBar(height: 16),
                const SizedBox(width: 3),
                _eqBar(height: 12),
                const SizedBox(width: 3),
                _eqBar(height: 18),
                const SizedBox(width: 3),
                _eqBar(height: 14),
              ],
            ),
          ],
        ),
      );
    }

    // Default placeholders (image/video)
    IconData icon;
    switch (postType) {
      case 'video':
        icon = Icons.play_arrow;
        break;
      case 'image':
        icon = Icons.photo;
        break;
      default:
        icon = Icons.article;
    }

    return Container(
      color: AppColors.surface,
      child: Center(
        child: Icon(icon, color: AppColors.textSecondary, size: 32),
      ),
    );
  }

  Widget _eqBar({required double height}) {
    return Container(
      width: 3,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.textSecondary.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  String _formatCount(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    } else if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K';
    } else {
      return count.toString();
    }
  }

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String _formatJoinDate(dynamic createdAt) {
    if (createdAt == null) return 'Joined — Unknown date';
    DateTime dt;
    if (createdAt is DateTime) {
      dt = createdAt;
    } else if (createdAt is String) {
      try {
        dt = DateTime.parse(createdAt);
      } catch (_) {
        return 'Joined — Unknown date';
      }
    } else {
      return 'Joined — Unknown date';
    }
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return 'Joined ${months[dt.month - 1]} ${dt.year}';
  }

  void _showPostOptions(PostModel post, int index) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textSecondary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            if (post.userId == _authService.currentUser?.id) ...[
              ListTile(
                leading: Icon(Icons.edit_outlined, color: AppColors.textPrimary),
                title: Text(
                  'Edit post',
                  style: TextStyle(color: AppColors.textPrimary),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _showEditPostDialog(post, index);
                },
              ),
              ListTile(
                leading: Icon(Icons.delete_outline, color: AppColors.error),
                title: Text(
                  LocalizationService.t('delete_post'),
                  style: TextStyle(color: AppColors.error),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _confirmDeletePost(post, index);
                },
              ),
            ],
            ListTile(
              leading: Icon(Icons.cancel, color: AppColors.textSecondary),
              title: Text(
                LocalizationService.t('cancel'),
                style: TextStyle(color: AppColors.textSecondary),
              ),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeletePost(PostModel post, int index) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          LocalizationService.t('delete_post'),
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: const LocalizedText(
          'delete_post_confirmation',
          style: TextStyle(color: AppColors.textSecondary),
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
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );

    if (shouldDelete == true) {
      try {
        await _postsService.deletePost(post.id);

        // Remove post from all relevant local lists
        setState(() {
          if (index >= 0 && index < _posts.length && _posts[index].id == post.id) {
            _posts.removeAt(index);
          } else {
            _posts.removeWhere((p) => p.id == post.id);
          }
          _likedPosts.removeWhere((p) => p.id == post.id);
          _harmonyPosts.removeWhere((p) => p.id == post.id);

          // Decrement posts_count in profile header if available
          if (_userProfile != null) {
            final dynamic raw = _userProfile!['posts_count'];
            int currentCount;
            if (raw is int) {
              currentCount = raw;
            } else {
              currentCount = int.tryParse(raw?.toString() ?? '') ?? _posts.length;
            }
            _userProfile!['posts_count'] = (currentCount > 0) ? currentCount - 1 : 0;
          }
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const LocalizedText('post_deleted_success'),
              backgroundColor: AppColors.success,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${LocalizationService.t('failed_delete_post')}: ${e.toString()}',
              ),
              backgroundColor: AppColors.error,
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

  Future<void> _showEditPostDialog(PostModel post, int index) async {
    final captionController = TextEditingController(text: post.content);
    final hashtagsController = TextEditingController(
      text: (post.hashtags ?? []).join(', '),
    );

    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Edit post',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: captionController,
              maxLines: 3,
              style: TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                labelText: LocalizationService.t('caption'),
                labelStyle: TextStyle(color: AppColors.textSecondary),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: AppColors.textSecondary.withOpacity(0.3)),
                  borderRadius: BorderRadius.circular(10),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: AppColors.primary),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: hashtagsController,
              style: TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                labelText: 'Hashtags',
                hintText: '#fun, #travel',
                labelStyle: TextStyle(color: AppColors.textSecondary),
                hintStyle: TextStyle(color: AppColors.textSecondary),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: AppColors.textSecondary.withOpacity(0.3)),
                  borderRadius: BorderRadius.circular(10),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: AppColors.primary),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
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
              LocalizationService.t('save'),
              style: TextStyle(color: AppColors.primary),
            ),
          ),
        ],
      ),
    );

    if (shouldSave == true) {
      try {
        final rawTags = hashtagsController.text
            .split(RegExp(r"[\s,]+"))
            .where((t) => t.trim().isNotEmpty)
            .map((t) => t.trim())
            .toList();
        final normalizedTags = rawTags
            .map((t) => t.startsWith('#') ? t.substring(1) : t)
            .toList();

        final updated = await _postsService.updatePost(
          postId: post.id,
          caption: captionController.text.trim(),
          hashtags: normalizedTags.isEmpty ? null : normalizedTags,
        );

        if (updated == null) {
          // Backend failed to return a full model; create a patched copy
          final patched = PostModel(
            id: post.id,
            userId: post.userId,
            username: post.username,
            userAvatar: post.userAvatar,
            displayName: post.displayName,
            content: captionController.text.trim(),
            mediaUrl: post.mediaUrl,
            thumbnailUrl: post.thumbnailUrl,
            mediaType: post.mediaType,
            likes: post.likes,
            comments: post.comments,
            shares: post.shares,
            views: post.views,
            saves: post.saves,
            isLiked: post.isLiked,
            timestamp: post.timestamp,
            hashtags: normalizedTags.isEmpty ? post.hashtags : normalizedTags,
            mentions: post.mentions,
            location: post.location,
            isVerified: post.isVerified,
            aspectRatio: post.aspectRatio,
            duration: post.duration,
            width: post.width,
            height: post.height,
            isAiGenerated: post.isAiGenerated,
            aiPrompt: post.aiPrompt,
            aiModel: post.aiModel,
            isPublic: post.isPublic,
            allowComments: post.allowComments,
            allowDuets: post.allowDuets,
            user: post.user,
            parentPostId: post.parentPostId,
            adsEnabled: post.adsEnabled,
            monetizationEnabledAt: post.monetizationEnabledAt,
            viralScore: post.viralScore,
            effects: post.effects,
            aiMetadata: post.aiMetadata,
            musicId: post.musicId,
          );

          _applyPostUpdateLocally(patched, index);
        } else {
          _applyPostUpdateLocally(updated, index);
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const LocalizedText('post_updated_success'),
              backgroundColor: AppColors.success,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${LocalizationService.t('failed_update_post')}: ${e.toString()}',
              ),
              backgroundColor: AppColors.error,
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

  void _applyPostUpdateLocally(PostModel newPost, int index) {
    setState(() {
      if (index >= 0 && index < _posts.length && _posts[index].id == newPost.id) {
        _posts[index] = newPost;
      } else {
        final i = _posts.indexWhere((p) => p.id == newPost.id);
        if (i != -1) _posts[i] = newPost;
      }
      final li = _likedPosts.indexWhere((p) => p.id == newPost.id);
      if (li != -1) _likedPosts[li] = newPost;
      final hi = _harmonyPosts.indexWhere((p) => p.id == newPost.id);
      if (hi != -1) _harmonyPosts[hi] = newPost;
    });
  }

  void _showMoreOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            if (_isOwnProfile) ...[
              // Utilities section hidden inside profile
              // ignore: dead_code
              if (false) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Utilities',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _buildOptionTile(
                  icon: Icons.smart_toy,
                  title: 'Qwen API Key',
                  onTap: () {
                    Navigator.pop(context);
                    _showApiKeyDialog();
                  },
                ),
                _buildOptionTile(
                  icon: Icons.tune,
                  title: 'AI Preferences',
                  onTap: () {
                    Navigator.pop(context);
                    _showAiPreferencesDialog();
                  },
                ),
                _buildOptionTile(
                  icon: Icons.download,
                  title: 'Downloads',
                  onTap: () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          LocalizationService.t(
                            'downloads_manager_coming_soon',
                          ),
                        ),
                        backgroundColor: AppColors.textSecondary,
                      ),
                    );
                  },
                ),
                _buildOptionTile(
                  icon: Icons.storage,
                  title: 'Storage & Data',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const StorageManagementScreen(),
                      ),
                    );
                  },
                ),
                _buildOptionTile(
                  icon: Icons.clear_all,
                  title: 'Clear Cache',
                  onTap: () {
                    Navigator.pop(context);
                    _showClearCacheDialog();
                  },
                ),
                const SizedBox(height: 12),
              ],
              _buildOptionTile(
                icon: Icons.logout,
                title: LocalizationService.t('sign_out'),
                onTap: () {
                  Navigator.pop(context);
                  _handleSignOut();
                },
                isDestructive: true,
              ),
            ] else ...[
              _buildOptionTile(
                icon: Icons.report,
                title: LocalizationService.t('report_user'),
                onTap: () {
                  Navigator.pop(context);
                  _showReportDialog();
                },
                isDestructive: true,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildOptionTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    return ListTile(
      leading: Icon(
        icon,
        color: isDestructive ? AppColors.error : AppColors.textPrimary,
      ),
      title: Text(
        title,
        style: TextStyle(
          color: isDestructive ? AppColors.error : AppColors.textPrimary,
          fontWeight: FontWeight.w500,
        ),
      ),
      onTap: onTap,
    );
  }

  void _showReportDialog() {
    final List<String> reportReasons = [
      'Inappropriate content',
      'Harassment or bullying',
      'Spam or fake account',
      'Hate speech',
      'Violence or dangerous behavior',
      'Other',
    ];

    String? selectedReason;
    String details = '';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text('Report User', style: TextStyle(color: AppColors.error)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Why are you reporting this user?',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              ...reportReasons.map(
                (reason) => RadioListTile<String>(
                  title: Text(
                    reason,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                    ),
                  ),
                  value: reason,
                  groupValue: selectedReason,
                  onChanged: (value) {
                    setState(() {
                      selectedReason = value;
                    });
                  },
                  activeColor: AppColors.primary,
                ),
              ),
              if (selectedReason == 'Other') ...[
                const SizedBox(height: 12),
                Text(
                  'Please describe the issue',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 8),
                TextField(
                  onChanged: (v) => details = v,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'Provide details to help our team review',
                    hintStyle: TextStyle(color: AppColors.textSecondary),
                    filled: true,
                    fillColor: AppColors.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppColors.border),
                    ),
                  ),
                  style: TextStyle(color: AppColors.textPrimary),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Cancel',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
            TextButton(
              onPressed: selectedReason != null
                  ? () async {
                      Navigator.pop(context);
                      try {
                        await _authService.reportUser(
                          _userProfile!['id'],
                          selectedReason!,
                          details:
                              selectedReason == 'Other' && details.isNotEmpty
                              ? details
                              : null,
                        );
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const LocalizedText(
                              'User reported successfully',
                            ),
                            backgroundColor: AppColors.success,
                          ),
                        );
                      } catch (e) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const LocalizedText(
                              'Failed to report user',
                            ),
                            backgroundColor: AppColors.error,
                          ),
                        );
                      }
                    }
                  : null,
              child: Text(
                'Report',
                style: TextStyle(
                  color: selectedReason != null
                      ? AppColors.error
                      : AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showBlockDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          LocalizationService.t('user_not_available'),
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: Text(
          LocalizationService.t('profile_not_available_to_you'),
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              LocalizationService.t('ok'),
              style: TextStyle(color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }

  void _showClearCacheDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const LocalizedText(
          'Clear Cache',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: const LocalizedText(
          'This will clear cached data. The app may take longer to load content initially.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              LocalizationService.t('cancel'),
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              HapticFeedback.lightImpact();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const LocalizedText('cache_cleared_success'),
                  backgroundColor: AppColors.success,
                ),
              );
            },
            child: const LocalizedText(
              'Clear',
              style: TextStyle(color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }

  void _showApiKeyDialog() {
    final TextEditingController apiKeyController = TextEditingController();
    bool isObscured = true;

    _aiService.getApiKey().then((currentKey) {
      if (currentKey.isNotEmpty) {
        apiKeyController.text = currentKey;
      }
    });

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const LocalizedText(
            'Qwen API Key',
            style: TextStyle(color: AppColors.textPrimary),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const LocalizedText(
                'Enter your Alibaba Qwen API key to enable AI features:',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: apiKeyController,
                obscureText: isObscured,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'sk-xxxxxxxxxxxxxxxx',
                  hintStyle: TextStyle(color: AppColors.textSecondary),
                  filled: true,
                  fillColor: AppColors.background,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: AppColors.textSecondary.withValues(alpha: 0.3),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: AppColors.textSecondary.withValues(alpha: 0.3),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.primary),
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      isObscured ? Icons.visibility : Icons.visibility_off,
                      color: AppColors.textSecondary,
                    ),
                    onPressed: () {
                      setState(() {
                        isObscured = !isObscured;
                      });
                    },
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const LocalizedText(
                'Get your API key from Alibaba Cloud Console',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                LocalizationService.t('cancel'),
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
            TextButton(
              onPressed: () async {
                final apiKey = apiKeyController.text.trim();
                if (apiKey.isNotEmpty) {
                  final isValid = _aiService.validateApiKey(apiKey);
                  if (!isValid) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          LocalizationService.t('invalid_api_key_format'),
                        ),
                        backgroundColor: AppColors.error,
                      ),
                    );
                    return;
                  }

                  try {
                    await _aiService.setApiKey(apiKey);
                    if (!context.mounted) return;
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: LocalizedText('API key saved successfully'),
                        backgroundColor: AppColors.success,
                      ),
                    );
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          LocalizationService.t('error_saving_api_key'),
                        ),
                        backgroundColor: AppColors.error,
                      ),
                    );
                  }
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: LocalizedText('Please enter a valid API key'),
                      backgroundColor: AppColors.error,
                    ),
                  );
                }
              },
              child: const LocalizedText(
                'Save',
                style: TextStyle(color: AppColors.primary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAiPreferencesDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const LocalizedText(
          'AI Preferences',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.image, color: AppColors.primary),
              title: const LocalizedText(
                'Default Image Size',
                style: TextStyle(color: AppColors.textPrimary),
              ),
              subtitle: const LocalizedText(
                '1024x1024',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              onTap: () {
                // Show size selection dialog
              },
            ),
            ListTile(
              leading: const Icon(Icons.palette, color: AppColors.primary),
              title: const LocalizedText(
                'Default Art Style',
                style: TextStyle(color: AppColors.textPrimary),
              ),
              subtitle: const LocalizedText(
                'Realistic',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              onTap: () {
                // Show style selection dialog
              },
            ),
            ListTile(
              leading: const Icon(Icons.speed, color: AppColors.primary),
              title: const LocalizedText(
                'Generation Quality',
                style: TextStyle(color: AppColors.textPrimary),
              ),
              subtitle: const LocalizedText(
                'High Quality (slower)',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              onTap: () {
                // Show quality selection dialog
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              LocalizationService.t('close'),
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  void _showBlockedByUserDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          LocalizationService.t('user_not_available'),
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: Text(
          LocalizationService.t('profile_not_available_to_you'),
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              LocalizationService.t('ok'),
              style: TextStyle(color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleUnblockUser() async {
    if (_userProfile == null) return;
    try {
      await _authService.unblockUser(_userProfile!['id']);
      if (mounted) {
        setState(() {
          _hasBlockedUser = false;
        });
        _loadUserPosts();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: LocalizedText(
              '${_userProfile!['username']} has been unblocked',
            ),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const LocalizedText('Failed to unblock user'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _navigateToChat() async {
    if (_userProfile != null) {
      // Check blocking relationships before allowing chat
      final isBlocked = await _authService.isBlocked(_userProfile!['id']);
      final isBlockedBy = await _authService.isBlockedBy(_userProfile!['id']);

      if (isBlocked || isBlockedBy) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(LocalizationService.t('cannot_message_user')),
              backgroundColor: AppColors.error,
            ),
          );
        }
        return;
      }

      // Create or get conversation, then navigate directly to enhanced chat
      final messagingService = EnhancedMessagingService();
      final conversation = await messagingService.getOrCreateConversation(
        _userProfile!['id'],
      );

      if (conversation != null && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => EnhancedChatScreen(
              conversationId: conversation.id,
              otherUserId: _userProfile!['id'],
              otherUserName:
                  (((_userProfile!['display_name'] as String?)?.isNotEmpty ??
                      false))
                  ? (_userProfile!['display_name'] as String)
                  : (((_userProfile!['username'] as String?)?.isNotEmpty ??
                        false))
                  ? '@${_userProfile!['username']}'
                  : LocalizationService.t('unknown_user'),
              otherUserAvatar: _userProfile!['avatar_url'],
            ),
          ),
        );
      }
    }
  }

  Widget _buildStreamsTab() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const SizedBox.shrink(),
          Expanded(
            child: _isLoadingStreams
                ? Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  )
                : (_streams.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.live_tv,
                                size: 48,
                                color: AppColors.textSecondary,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                LocalizationService.t('no_streams_yet'),
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                LocalizationService.t('no_streams_available_yet'),
                                style: TextStyle(
                                  fontSize: 14,
                                  color: AppColors.textSecondary,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadStreams,
                          color: AppColors.primary,
                          child: ListView.builder(
                            padding: const EdgeInsets.all(0),
                            itemCount: _streams.length,
                            itemBuilder: (context, index) {
                              final stream = _streams[index];
                              return _buildStreamCard(stream);
                            },
                          ),
                        )),
          ),
        ],
      ),
    );
  }

  // Helper methods for stream rendering
  String _formatDurationFromDates(DateTime? startedAt, DateTime? endedAt) {
    if (startedAt == null) return 'Unknown';
    final end = endedAt ?? DateTime.now();
    final duration = end.difference(startedAt);
    if (duration.inHours > 0) {
      return '${duration.inHours}h ${duration.inMinutes % 60}m';
    } else {
      return '${duration.inMinutes}m';
    }
  }

  String _formatDurationForStream(LiveStreamModel stream) {
    final seconds = stream.finalDuration;
    if (seconds != null && seconds > 0) {
      final mins = seconds ~/ 60;
      final hours = mins ~/ 60;
      if (hours > 0) {
        return '${hours}h ${mins % 60}m';
      } else {
        return '${mins}m';
      }
    }
    return _formatDurationFromDates(stream.startedAt, stream.endedAt);
  }

  String _formatDate(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    if (difference.inDays == 0) {
      return 'Today';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'live':
        return Colors.red;
      case 'ended':
        return Colors.green;
      case 'error':
        return Colors.orange;
      default:
        return AppColors.textSecondary;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'live':
        return Icons.circle;
      case 'ended':
        return Icons.check_circle;
      case 'error':
        return Icons.error;
      default:
        return Icons.help;
    }
  }

  Widget _buildStreamCard(LiveStreamModel stream) {
    final bool isLive = stream.status.toLowerCase() == 'live';
    return GestureDetector(
      onTap: isLive
          ? (_isOwnProfile
                ? () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'You cannot join your own livestream from here',
                        ),
                        backgroundColor: Colors.orange,
                      ),
                    );
                  }
                : () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => LiveStreamViewerScreen(
                          streamId: stream.id,
                          title: stream.title,
                          description: stream.description,
                        ),
                      ),
                    );
                  })
          : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      stream.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _getStatusColor(
                        stream.status,
                      ).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _getStatusIcon(stream.status),
                          size: 12,
                          color: _getStatusColor(stream.status),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          stream.status.toUpperCase(),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: _getStatusColor(stream.status),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (stream.description.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  stream.description,
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  _buildStatItem(
                    Icons.visibility,
                    '${stream.viewerCount} viewers',
                  ),
                  const SizedBox(width: 16),
                  _buildStatItem(
                    Icons.access_time,
                    _formatDurationForStream(stream),
                  ),
                  const Spacer(),
                  Text(
                    _formatDate(stream.startedAt),
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (((stream.provider ?? '').toLowerCase()) != 'livekit')
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.green.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Text(
                        (stream.provider ?? '').toUpperCase(),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.green,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
              if (stream.isEphemeral || stream.savedLocally) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (stream.isEphemeral)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.orange.withValues(alpha: 0.3),
                          ),
                        ),
                        child: const Text(
                          'EPHEMERAL',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    if (stream.savedLocally)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.blue.withValues(alpha: 0.3),
                          ),
                        ),
                        child: const Text(
                          'SAVED LOCALLY',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
              if (stream.tags.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: stream.tags.take(3).map((tag) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '#$tag',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],

              if (isLive) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => LiveStreamViewerScreen(
                            streamId: stream.id,
                            title: stream.title,
                            description: stream.description,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(
                      Icons.play_circle_fill,
                      color: Colors.white,
                    ),
                    label: const Text(
                      'Join Live',
                      style: TextStyle(
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
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatItem(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.textSecondary),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class _GridTilePreview extends StatefulWidget {
  final PostModel post;
  const _GridTilePreview({required this.post});
  @override
  State<_GridTilePreview> createState() => _GridTilePreviewState();
}

class _GridTilePreviewState extends State<_GridTilePreview>
    with SingleTickerProviderStateMixin {
  VideoPlayerController? _videoController;
  bool _videoInitialized = false;

  AudioPlayer? _audioPlayer;
  bool _audioPreviewActive = false;

  AnimationController? _textAnimController;
  String _textTwoWords = '';

  @override
  void initState() {
    super.initState();
    // Prepare typewriter animation for text posts (first two words)
    if (widget.post.type == 'text') {
      final content = widget.post.content.trim();
      final words = content.split(RegExp(r'\s+'));
      _textTwoWords = words.isEmpty
          ? ''
          : (words.length >= 2 ? '${words[0]} ${words[1]}' : words[0]);
      final length = _textTwoWords.length;
      if (length > 0) {
        _textAnimController = AnimationController(
          vsync: this,
          duration: Duration(
            milliseconds: ((length * 80).clamp(400, 2000)).toInt(),
          ),
        )..repeat(reverse: true);
      }
    }
    // Autoplay muted video preview looping first 3 seconds
    if (widget.post.type == 'video') {
      _initVideoIfNeeded().then((_) => _playVideo());
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _audioPlayer?.dispose();
    _textAnimController?.dispose();
    super.dispose();
  }

  Future<void> _initVideoIfNeeded() async {
    if (_videoController != null || widget.post.mediaUrl == null) return;
    try {
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.post.mediaUrl!),
      );
      await controller.initialize();
      // Loop only the first 3 seconds by seeking back to 0 when position exceeds 3s
      await controller.setLooping(false);
      await controller.setVolume(0.0);
      controller.addListener(() {
        final pos = controller.value.position;
        if (pos >= const Duration(seconds: 3)) {
          controller.seekTo(Duration.zero);
        }
      });
      setState(() {
        _videoController = controller;
        _videoInitialized = true;
      });
    } catch (e) {
      // Fallback silently on init error
    }
  }

  Future<void> _playVideo() async {
    if (_videoController == null || !_videoInitialized) return;
    try {
      await _videoController!.play();
    } catch (_) {}
  }

  Future<void> _pauseVideo() async {
    if (_videoController == null || !_videoInitialized) return;
    try {
      await _videoController!.pause();
    } catch (_) {}
  }

  // ignore: unused_element
  Future<void> _startAudioPreview() async {
    if (_audioPreviewActive || widget.post.mediaUrl == null) return;
    try {
      _audioPlayer ??= AudioPlayer();
      await _audioPlayer!.setVolume(0.3);
      await _audioPlayer!.play(UrlSource(widget.post.mediaUrl!));
      setState(() {
        _audioPreviewActive = true;
      });
    } catch (_) {}
  }

  // ignore: unused_element
  Future<void> _stopAudioPreview() async {
    try {
      await _audioPlayer?.stop();
      setState(() {
        _audioPreviewActive = false;
      });
    } catch (_) {}
  }

  void _onHoverEnter(_) async {
    // For web, auto-play video previews on hover
    if (kIsWeb) {
      if (widget.post.type == 'video') {
        await _initVideoIfNeeded();
        await _playVideo();
      }
      // No audio playback for grid preview
    }
  }

  void _onHoverExit(_) async {
    if (kIsWeb) {
      if (widget.post.type == 'video') {
        await _pauseVideo();
      }
    }
  }

  void _onLongPressStart(_) async {
    // Mobile long-press preview
    if (!kIsWeb) {
      if (widget.post.type == 'video') {
        await _initVideoIfNeeded();
        await _playVideo();
      }
      // No audio playback for grid preview
    }
  }

  void _onLongPressEnd(_) async {
    if (!kIsWeb) {
      if (widget.post.type == 'video') {
        await _pauseVideo();
      }
    }
  }

  Widget _buildImage(String url) {
    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => _buildPlaceholder(),
    );
  }

  Widget _buildPlaceholder() {
    switch (widget.post.type) {
      case 'video':
        return Container(
          color: Colors.black,
          child: const Center(
            child: Icon(
              Icons.play_circle_fill,
              color: Colors.white70,
              size: 32,
            ),
          ),
        );
      case 'audio':
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.surface,
                AppColors.primary.withValues(alpha: 0.25),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: const Center(
            child: Icon(Icons.music_note, color: Colors.white70, size: 28),
          ),
        );
      case 'text':
        final content = widget.post.content.trim();
        final words = content.split(RegExp(r'\s+'));
        final two = words.isEmpty
            ? ''
            : (words.length >= 2 ? '${words[0]} ${words[1]}' : words[0]);
        return Container(
          color: AppColors.surface,
          padding: const EdgeInsets.all(8),
          child: AnimatedBuilder(
            animation: _textAnimController ?? kAlwaysDismissedAnimation,
            builder: (context, _) {
              final len = two.length;
              final v = (_textAnimController?.value ?? 0.0);
              final current = (len * v).round().clamp(0, len);
              final visible = two.substring(0, current);
              return Text(
                visible.isEmpty ? 'Tap to view' : visible,
                maxLines: 1,
                overflow: TextOverflow.clip,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              );
            },
          ),
        );
      default:
        return Container(color: AppColors.surface);
    }
  }

  Widget _buildVideoPreview() {
    if (_videoController == null || !_videoInitialized) {
      // Try thumbnail first, then media image fallback
      if (widget.post.thumbnailUrl != null &&
          widget.post.thumbnailUrl!.isNotEmpty) {
        return _buildImage(widget.post.thumbnailUrl!);
      } else if (widget.post.mediaUrl != null &&
          widget.post.mediaUrl!.isNotEmpty) {
        return _buildImage(widget.post.mediaUrl!);
      }
      return _buildPlaceholder();
    }

    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: _videoController!.value.size.width,
          height: _videoController!.value.size.height,
          child: VideoPlayer(_videoController!),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: _onHoverEnter,
      onExit: _onHoverExit,
      child: GestureDetector(
        onLongPressStart: _onLongPressStart,
        onLongPressEnd: _onLongPressEnd,
        child: Builder(
          builder: (context) {
            switch (widget.post.type) {
              case 'video':
                return _buildVideoPreview();
              case 'image':
                if (widget.post.thumbnailUrl != null &&
                    widget.post.thumbnailUrl!.isNotEmpty) {
                  return _buildImage(widget.post.thumbnailUrl!);
                } else if (widget.post.mediaUrl != null &&
                    widget.post.mediaUrl!.isNotEmpty) {
                  return _buildImage(widget.post.mediaUrl!);
                }
                return _buildPlaceholder();
              case 'audio':
                return _buildPlaceholder();
              case 'text':
                return _buildPlaceholder();
              default:
                return _buildPlaceholder();
            }
          },
        ),
      ),
    );
  }
}
