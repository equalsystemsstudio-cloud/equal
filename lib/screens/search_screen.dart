import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/app_colors.dart';
import '../services/social_service.dart';
import '../services/content_service.dart';
import '../services/posts_service.dart';
import '../widgets/user_card.dart';
import '../widgets/post_card.dart';
import 'comments_screen.dart';
import '../models/post_model.dart';
import '../services/localization_service.dart';
import '../widgets/post_widget.dart';
import '../services/analytics_service.dart';
import 'content_type_selection_screen.dart';
import 'package:share_plus/share_plus.dart';
import 'package:google_fonts/google_fonts.dart';
// Added imports for viewer overlay controls
import '../widgets/side_action_bar.dart';
import '../services/auth_service.dart';
import '../services/enhanced_notification_service.dart';
import '../services/post_media_optimization_service.dart';
import 'profile/profile_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final _socialService = SocialService();
  final _contentService = ContentService();
  final PostsService _postsService = PostsService();
  final PostMediaOptimizationService _optimizationService =
      PostMediaOptimizationService.of();

  late TabController _tabController;

  List<Map<String, dynamic>> _userResults = [];
  List<Map<String, dynamic>> _postResults = [];
  List<Map<String, dynamic>> _hashtagResults = [];
  List<Map<String, dynamic>> _trendingPosts = [];
  List<Map<String, dynamic>> _suggestedUsers = [];
  List<String> _trendingHashtags = [];
  List<PostModel> _trendingPostModels = [];

  bool _isSearching = false;
  bool _isLoading = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadDiscoverContent();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadDiscoverContent() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      final results = await Future.wait([
        _postsService.getTrendingPosts(),
        _socialService.getSuggestedUsers(),
        _contentService.getTrendingHashtags(),
      ]);

      if (mounted) {
        setState(() {
          final trendingModels = results[0] as List<PostModel>;
          _trendingPostModels = trendingModels;
          _trendingPosts = trendingModels.map(_toPostCardMap).toList();
          _suggestedUsers = results[1] as List<Map<String, dynamic>>;
          _trendingHashtags = results[2] as List<String>;
        });
      }
    } catch (e) {
      debugPrint(('Error loading discover content: $e').toString());
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) {
      if (mounted) {
        setState(() {
          _isSearching = false;
          _userResults.clear();
          _postResults.clear();
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isSearching = true;
        _isLoading = true;
        _searchQuery = query;
      });
    }

    try {
      final results = await Future.wait([
        _socialService.searchUsers(query),
        _postsService.searchPosts(query),
        _socialService.searchHashtags(query),
      ]);

      if (mounted) {
        setState(() {
          _userResults = results[0] as List<Map<String, dynamic>>;
          final postModels = results[1] as List<PostModel>;
          _postResults = postModels.map(_toPostCardMap).toList();
          _hashtagResults = results[2] as List<Map<String, dynamic>>;
        });
      }
    } catch (e) {
      debugPrint(('Error performing search: $e').toString());
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleOptimize(int index) async {
    if (index < 0 || index >= _trendingPostModels.length) return;
    final PostModel post = _trendingPostModels[index];
    if (post.mediaType != MediaType.video) return;
    HapticFeedback.lightImpact();
    try {
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

      if (mounted) Navigator.of(context).pop();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(LocalizationService.t('optimization_complete')),
          ),
        );
        setState(() {
          _trendingPostModels[index] = _trendingPostModels[index].copyWith(
            mediaUrl: newUrl,
          );
        });
      }
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${LocalizationService.t('optimization_failed')}: ${e.toString()}',
            ),
          ),
        );
      }
    }
  }

  void _clearSearch() {
    _searchController.clear();
    if (mounted) {
      setState(() {
        _isSearching = false;
        _searchQuery = '';
        _userResults.clear();
        _postResults.clear();
        _hashtagResults.clear();
      });
    }
    HapticFeedback.lightImpact();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildSearchHeader(),
            if (_isSearching) _buildSearchTabs(),
            Expanded(
              child: _isSearching
                  ? _buildSearchResults()
                  : _buildDiscoverContent(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border, width: 1),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: (value) {
                  if (value.isEmpty) {
                    _clearSearch();
                  } else {
                    _performSearch(value);
                  }
                },
                decoration: InputDecoration(
                  hintText: LocalizationService.t('search_hint'),
                  hintStyle: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 16,
                  ),
                  prefixIcon: Icon(
                    Icons.search,
                    color: AppColors.textSecondary,
                  ),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(
                            Icons.clear,
                            color: AppColors.textSecondary,
                          ),
                          onPressed: _clearSearch,
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchTabs() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(10),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        indicatorPadding: const EdgeInsets.all(2),
        labelColor: Colors.white,
        unselectedLabelColor: AppColors.textSecondary,
        labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        unselectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w500,
          fontSize: 14,
        ),
        tabs: [
          Tab(
            text: '${LocalizationService.t('users')} (${_userResults.length})',
          ),
          Tab(
            text: '${LocalizationService.t('posts')} (${_postResults.length})',
          ),
          Tab(
            text:
                '${LocalizationService.t('hashtags')} (${_hashtagResults.length})',
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        const SizedBox(height: 16),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildUserResults(),
              _buildPostResults(),
              _buildHashtagResults(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildUserResults() {
    if (_userResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_search, size: 64, color: AppColors.textSecondary),
            const SizedBox(height: 16),
            Text(
              '${LocalizationService.t('no_users_found_for')} "$_searchQuery"',
              style: TextStyle(fontSize: 16, color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _userResults.length,
      itemBuilder: (context, index) {
        final user = _userResults[index];
        return UserCard(
          user: user,
          onTap: () {
            // Navigate to user profile
            final String? userId = user['id'] as String?;
            if (userId != null && userId.isNotEmpty) {
              HapticFeedback.lightImpact();
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ProfileScreen(userId: userId),
                ),
              );
              try {
                AnalyticsService().trackProfileView(userId);
              } catch (_) {}
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    LocalizationService.t('unable_to_open_profile'),
                  ),
                  backgroundColor: Colors.red,
                ),
              );
            }
          },
        );
      },
    );
  }

  Widget _buildPostResults() {
    if (_postResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 64, color: AppColors.textSecondary),
            const SizedBox(height: 16),
            Text(
              '${LocalizationService.t('no_posts_found_for')} "$_searchQuery"',
              style: TextStyle(fontSize: 16, color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _postResults.length,
      itemBuilder: (context, index) {
        final post = _postResults[index];
        final likesCount = (post['likes_count'] as int?) ?? 0;
        return PostCard(
          post: post,
          onLike: () async {
            final wasLiked = (post['is_liked'] as bool?) ?? false;
            final previousLikes = likesCount;
            // Optimistic update
            setState(() {
              post['is_liked'] = !wasLiked;
              post['likes_count'] = previousLikes + (wasLiked ? -1 : 1);
            });
            final messenger = ScaffoldMessenger.of(context);
            final success = await _postsService.toggleLike(
              post['id'] as String,
            );
            if (!mounted) return;
            if (!success) {
              // Revert on failure
              setState(() {
                post['is_liked'] = wasLiked;
                post['likes_count'] = previousLikes;
              });
              messenger.showSnackBar(
                SnackBar(
                  content: Text(
                    wasLiked
                        ? LocalizationService.t('failed_unlike_post')
                        : LocalizationService.t('failed_like_post'),
                  ),
                  backgroundColor: Colors.red,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            } else {
              try {
                final analytics = AnalyticsService();
                await analytics.flushPendingEvents();
              } catch (e) {
                debugPrint('SearchScreen: like analytics flush failed: $e');
              }
            }
          },
          onComment: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => CommentsScreen(
                  postId: post['id'],
                  postAuthorId: post['user_id'],
                ),
              ),
            ).then((result) {
              if (!mounted) return;
              if (result != null && result is int) {
                setState(() {
                  post['comments_count'] = result;
                });
              }
            });
          },
          onShare: () {
            // Handle share
          },
        );
      },
    );
  }

  Widget _buildHashtagResults() {
    if (_hashtagResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.tag, size: 64, color: AppColors.textSecondary),
            const SizedBox(height: 16),
            Text(
              '${LocalizationService.t('no_hashtags_found_for')} "$_searchQuery"',
              style: TextStyle(fontSize: 16, color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _hashtagResults.length,
      itemBuilder: (context, index) {
        final hashtag = _hashtagResults[index];
        final tag = hashtag['tag'] as String;
        final postCount = hashtag['post_count'] as int;
        final isTrending = hashtag['is_trending'] as bool? ?? false;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border, width: 1),
          ),
          child: ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.tag, color: Colors.white, size: 20),
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    tag,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isTrending) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.orange.withValues(alpha: 0.5),
                        width: 1,
                      ),
                    ),
                    child: const Text(
                      'Trending',
                      style: TextStyle(
                        color: Colors.orange,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            subtitle: Text(
              '$postCount ${postCount == 1 ? LocalizationService.t('post_singular') : LocalizationService.t('post_plural')}',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
            ),
            trailing: Icon(
              Icons.arrow_forward_ios,
              color: AppColors.textSecondary,
              size: 16,
            ),
            onTap: () {
              // Search for posts with this hashtag
              _searchController.text = tag;
              _performSearch(tag);
              HapticFeedback.lightImpact();
            },
          ),
        );
      },
    );
  }

  Widget _buildDiscoverContent() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTrendingHashtags(),
          const SizedBox(height: 24),
          _buildSuggestedUsers(),
          const SizedBox(height: 24),
          _buildTrendingPosts(),
        ],
      ),
    );
  }

  Widget _buildTrendingHashtags() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            LocalizationService.t('trending_hashtags'),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 40,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _trendingHashtags.length,
            itemBuilder: (context, index) {
              final hashtag = _trendingHashtags[index];
              return Container(
                margin: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () {
                    _searchController.text = hashtag;
                    _performSearch(hashtag);
                    HapticFeedback.lightImpact();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      hashtag,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSuggestedUsers() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                LocalizationService.t('suggested_for_you'),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              TextButton(
                onPressed: () {
                  // Show all suggested users
                },
                child: Text(
                  LocalizationService.t('see_all'),
                  style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 200,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _suggestedUsers.length,
            itemBuilder: (context, index) {
              final user = _suggestedUsers[index];
              return Container(
                width: 140,
                margin: const EdgeInsets.only(right: 12),
                child: _buildSuggestedUserCard(user),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSuggestedUserCard(Map<String, dynamic> user) {
    return InkWell(
      onTap: () {
        // Open profile when tapping a suggested user card
        final String? userId = user['id'] as String?;
        if (userId != null && userId.isNotEmpty) {
          HapticFeedback.lightImpact();
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ProfileScreen(userId: userId),
            ),
          );
          try {
            AnalyticsService().trackProfileView(userId);
          } catch (_) {}
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(LocalizationService.t('unable_to_open_profile')),
              backgroundColor: Colors.red,
            ),
          );
        }
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border, width: 1),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 30,
              backgroundImage: user['avatar_url'] != null
                  ? NetworkImage(user['avatar_url'])
                  : null,
              backgroundColor: AppColors.primary.withValues(alpha: 0.1),
              child: user['avatar_url'] == null
                  ? Icon(Icons.person, color: AppColors.primary, size: 30)
                  : null,
            ),
            const SizedBox(height: 8),
            Text(
              user['display_name'] ??
                  user['username'] ??
                  'Unknown', // Fixed: use display_name instead of full_name
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              '@${user['username'] ?? 'unknown'}',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            // Removed followers/trackers count for privacy in suggested users
            // Text(
            //   "${user['followers_count'] ?? 0} ${LocalizationService.t('followers')}",
            //   style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
            // ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  HapticFeedback.lightImpact();
                  try {
                    final isFollowing = user['is_following'] ?? false;
                    if (isFollowing) {
                      await _socialService.unfollowUser(user['id']);
                    } else {
                      await _socialService.followUser(user['id']);
                    }
                    // Refresh to update UI
                    await _loadDiscoverContent();
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            (user['is_following'] ?? false)
                                ? LocalizationService.t('failed_unfollow_user')
                                : LocalizationService.t('failed_follow_user'),
                          ),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(
                  (user['is_following'] ?? false)
                      ? LocalizationService.t('following')
                      : LocalizationService.t('follow'),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrendingPosts() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            LocalizationService.t('trending_posts'),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: 12),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: _trendingPosts.length,
          itemBuilder: (context, index) {
            final post = _trendingPosts[index];
            final likesCount = (post['likes_count'] as int?) ?? 0;
            return PostCard(
              post: post,
              onTap: () {
                if (_trendingPostModels.isEmpty) return;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => _DiscoverViewerPage(
                      posts: _trendingPostModels,
                      initialIndex: index,
                    ),
                  ),
                );
              },
              onLike: () async {
                final wasLiked = (post['is_liked'] as bool?) ?? false;
                final previousLikes = likesCount;
                setState(() {
                  post['is_liked'] = !wasLiked;
                  post['likes_count'] = previousLikes + (wasLiked ? -1 : 1);
                });
                final messenger = ScaffoldMessenger.of(context);
                final success = await _postsService.toggleLike(
                  post['id'] as String,
                );
                if (!mounted) return;
                if (!success) {
                  setState(() {
                    post['is_liked'] = wasLiked;
                    post['likes_count'] = previousLikes;
                  });
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(
                        wasLiked
                            ? LocalizationService.t('failed_unlike_post')
                            : LocalizationService.t('failed_like_post'),
                      ),
                      backgroundColor: Colors.red,
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(milliseconds: 1200),
                    ),
                  );
                } else {
                  // Track analytics immediately and flush on success
                  try {
                    final analytics = AnalyticsService();
                    final postType =
                        (post['media_type'] as String?) ??
                        (post['type'] as String?) ??
                        'text';
                    if (wasLiked) {
                      await analytics.trackPostUnlike(
                        post['id'] as String,
                        postType,
                      );
                    } else {
                      await analytics.trackPostLike(
                        post['id'] as String,
                        postType,
                      );
                    }
                    await analytics.flushPendingEvents();
                  } catch (e) {
                    debugPrint(
                      'SearchScreen: trending like analytics tracking failed: $e',
                    );
                  }
                }
              },
              onComment: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => CommentsScreen(
                      postId: post['id'],
                      postAuthorId: post['user_id'],
                    ),
                  ),
                ).then((result) {
                  if (result != null && result is int) {
                    setState(() {
                      post['comments_count'] = result;
                    });
                  }
                });
              },
              onShare: () {
                // Handle share
              },
            );
          },
        ),
      ],
    );
  }
}

Map<String, dynamic> _toPostCardMap(PostModel p) {
  return {
    'id': p.id,
    'user_id': p.userId,
    'username': p.username,
    'user_avatar': p.userAvatar,
    'content': p.content,
    'media_url': p.mediaUrl,
    'type': p.mediaType.toString().split('.').last,
    'created_at': p.timestamp.toIso8601String(),
    'likes_count': p.likes,
    'comments_count': p.comments,
    'is_liked': p.isLiked,
  };
}

class _DiscoverViewerPage extends StatefulWidget {
  final List<PostModel> posts;
  final int initialIndex;

  const _DiscoverViewerPage({required this.posts, required this.initialIndex});

  @override
  State<_DiscoverViewerPage> createState() => _DiscoverViewerPageState();
}

class _DiscoverViewerPageState extends State<_DiscoverViewerPage> {
  late final PageController _pageController;
  int _currentIndex = 0;
  bool _isScrolling = false;
  // Session-level mute preference for the viewer
  bool _muted = true; // default mute on first open

  // Services for actions (mirror MainFeedScreen)
  final PostsService _postsService = PostsService();
  final AuthService _authService = AuthService();
  final AnalyticsService _analyticsService = AnalyticsService();
  final SocialService _socialService = SocialService();
  final EnhancedNotificationService _notificationService =
      EnhancedNotificationService();
  final PostMediaOptimizationService _optimizationService =
      PostMediaOptimizationService.of();

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification is ScrollUpdateNotification) {
                if (!_isScrolling) {
                  setState(() {
                    _isScrolling = true;
                  });
                }
              } else if (notification is ScrollEndNotification ||
                  notification is UserScrollNotification) {
                if (_isScrolling) {
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
              onPageChanged: (index) {
                setState(() {
                  _currentIndex = index;
                });
              },
              itemCount: widget.posts.length,
              itemBuilder: (context, index) {
                final post = widget.posts[index];
                final isActive = index == _currentIndex && !_isScrolling;
                return PostWidget(
                  post: post,
                  isActive: isActive,
                  muted: _muted,
                );
              },
            ),
          ),
          // Back button
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 8,
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          // Mute toggle
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 8,
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _muted = !_muted; // remember per session
                });
              },
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.35),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _muted ? Icons.volume_off : Icons.volume_up,
                  color: Colors.white,
                ),
              ),
            ),
          ),

          // Side action controls (like, comment, share, delete, duet, statuses)
          Positioned(
            right: 16,
            bottom: 100,
            child: Builder(
              builder: (context) {
                final bool hasPost =
                    widget.posts.isNotEmpty &&
                    _currentIndex >= 0 &&
                    _currentIndex < widget.posts.length;
                final PostModel? currentPost = hasPost
                    ? widget.posts[_currentIndex]
                    : null;
                return SideActionBar(
                  post: currentPost,
                  onLike: hasPost ? () => _handleLike(_currentIndex) : null,
                  onComment: hasPost
                      ? () => _handleComment(_currentIndex)
                      : null,
                  onShare: hasPost ? () => _handleShare(_currentIndex) : null,
                  onDelete:
                      hasPost &&
                          _authService.currentUser != null &&
                          currentPost!.userId == _authService.currentUser!.id
                      ? () => _handleDelete(_currentIndex)
                      : null,
                  onDuet:
                      hasPost &&
                          _authService.currentUser != null &&
                          currentPost!.userId != _authService.currentUser!.id
                      ? () => _handleDuet(_currentIndex)
                      : null,
                  onOptimize:
                      hasPost &&
                          _authService.currentUser != null &&
                          currentPost!.userId == _authService.currentUser!.id &&
                          currentPost.mediaType == MediaType.video
                      ? () => _handleOptimize(_currentIndex)
                      : null,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // Inserted: Action handlers (moved inside state class)
  Future<void> _handleLike(int index) async {
    if (index < 0 || index >= widget.posts.length) return;
    final post = widget.posts[index];
    final wasLiked = post.isLiked;
    setState(() {
      widget.posts[index] = post.copyWith(
        isLiked: !wasLiked,
        likes: wasLiked ? post.likes - 1 : post.likes + 1,
      );
    });
    try {
      await _postsService.toggleLike(post.id);
      try {
        await _analyticsService.flushPendingEvents();
      } catch (_) {}
    } catch (_) {
      if (!mounted) return;
      setState(() {
        widget.posts[index] = post.copyWith(
          isLiked: wasLiked,
          likes: post.likes,
        );
      });
    }
  }

  void _handleComment(int index) {
    if (index < 0 || index >= widget.posts.length) return;
    final post = widget.posts[index];
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            CommentsScreen(postId: post.id, postAuthorId: post.userId),
      ),
    ).then((result) {
      if (!mounted) return;
      if (result != null && result is int) {
        setState(() {
          widget.posts[index] = post.copyWith(comments: result);
        });
      }
    });
  }

  void _handleShare(int index) async {
    if (index < 0 || index >= widget.posts.length) return;
    final post = widget.posts[index];
    final currentUser = _authService.currentUser;
    try {
      await _analyticsService.trackPostShare(
        post.id,
        post.mediaType.toString(),
        'native_share',
      );
      await _socialService.sharePost(post.id);
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
      String shareText = '';
      if (post.content.isNotEmpty) {
        shareText = post.content.length > 100
            ? '${post.content.substring(0, 100)}...'
            : post.content;
      }
      final shareContent = shareText.isNotEmpty
          ? 'Check out this post by @${post.username}: "${shareText}"\n\nhttps://play.google.com/store/apps/details?id=com.equal.app.equal\n\nDownload Equal app to see more amazing content!'
          : 'Check out this amazing post by @${post.username} on Equal!\n\nhttps://play.google.com/store/apps/details?id=com.equal.app.equal\n\nDownload Equal app to see more amazing content!';
      await Share.share(
        shareContent,
        subject: 'Amazing post on Equal by @${post.username}',
      );
      if (!mounted) return;
      setState(() {
        widget.posts[index] = post.copyWith(shares: post.shares + 1);
      });
    } catch (e) {
      debugPrint(('Error sharing post: $e').toString());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(LocalizationService.t('failed_to_share_post')),
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
    if (index < 0 || index >= widget.posts.length) return;
    final post = widget.posts[index];
    final currentUser = _authService.currentUser;
    final messenger = ScaffoldMessenger.of(context);
    if (currentUser == null || post.userId != currentUser.id) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            LocalizationService.t('you_can_only_delete_your_own_posts'),
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
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text(
          LocalizationService.t('delete_post'),
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          LocalizationService.t('delete_post_confirmation'),
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              LocalizationService.t('cancel'),
              style: const TextStyle(color: Colors.white70),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              LocalizationService.t('delete'),
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    if (shouldDelete == true) {
      try {
        await _postsService.deletePost(post.id);
        if (!mounted) return;
        setState(() {
          widget.posts.removeAt(index);
          if (_currentIndex >= widget.posts.length) {
            _currentIndex = widget.posts.isEmpty ? 0 : widget.posts.length - 1;
          }
        });
        messenger.showSnackBar(
          SnackBar(
            content: Text(LocalizationService.t('post_deleted_success')),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      } catch (e) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(LocalizationService.t('failed_delete_post')),
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

  void _handleDuet(int index) {
    if (index < 0 || index >= widget.posts.length) return;
    final post = widget.posts[index];
    final currentUser = _authService.currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(LocalizationService.t('please_log_in')),
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
          content: const LocalizedText(
            'You cannot create a Harmony with your own post',
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
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ContentTypeSelectionScreen(parentPostId: post.id),
      ),
    );
  }

  Future<void> _handleOptimize(int index) async {
    if (index < 0 || index >= widget.posts.length) return;
    final PostModel post = widget.posts[index];
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
        // Update local mediaUrl to refresh playback
        setState(() {
          widget.posts[index] = widget.posts[index].copyWith(mediaUrl: newUrl);
        });
      }
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(LocalizationService.t('optimization_failed'))),
        );
      }
    }
  }
}
