import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import '../../config/app_colors.dart';
import '../../config/supabase_config.dart';
import '../../models/post_model.dart';
import '../../services/analytics_service.dart';
import '../../services/auth_service.dart';
import '../../services/posts_service.dart';
import '../../services/localization_service.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen>
    with SingleTickerProviderStateMixin {
  final AnalyticsService _analyticsService = AnalyticsService();
  final AuthService _authService = AuthService();
  final PostsService _postsService = PostsService();

  late TabController _tabController;
  AnalyticsRange _selectedRange = AnalyticsRange.month;

  bool _loading = true;
  String? _error;

  Map<String, dynamic> _userAnalytics = {};
  List<PostModel> _posts = [];
  final Map<String, Map<String, dynamic>> _postAnalytics = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this, initialIndex: 2);
    _tabController.addListener(_onTabChanged);
    _init();
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    setState(() {
      _selectedRange = _rangeForTabIndex(_tabController.index);
      _loading = true;
      _error = null;
    });
    _fetchAnalytics();
  }

  AnalyticsRange _rangeForTabIndex(int index) {
    switch (index) {
      case 0:
        return AnalyticsRange.day; // 1 day
      case 1:
        return AnalyticsRange.week; // 1 week
      case 2:
        return AnalyticsRange.month; // 30 days
      case 3:
        return AnalyticsRange.year; // 1 year
      case 4:
      default:
        return AnalyticsRange.lifetime; // Lifetime
    }
  }

  // New: dynamic summary title based on selected range
  String _summaryTitle() {
    switch (_selectedRange) {
      case AnalyticsRange.day:
        return LocalizationService.t('account_summary_last_1_day');
      case AnalyticsRange.week:
        return LocalizationService.t('account_summary_last_1_week');
      case AnalyticsRange.month:
        return LocalizationService.t('account_summary_last_30_days');
      case AnalyticsRange.year:
        return LocalizationService.t('account_summary_last_1_year');
      case AnalyticsRange.lifetime:
        return LocalizationService.t('account_summary_lifetime');
    }
  }

  // Compute the starting timestamp for the selected range relative to now
  DateTime? _rangeStartDate() {
    final now = DateTime.now();
    // Use calendar day boundaries: start from today at midnight
    final startOfToday = DateTime(now.year, now.month, now.day);
    switch (_selectedRange) {
      case AnalyticsRange.day:
        return startOfToday; // today only
      case AnalyticsRange.week:
        return startOfToday.subtract(
          const Duration(days: 6),
        ); // last 7 calendar days incl. today
      case AnalyticsRange.month:
        return startOfToday.subtract(
          const Duration(days: 29),
        ); // last 30 calendar days incl. today
      case AnalyticsRange.year:
        return startOfToday.subtract(
          const Duration(days: 364),
        ); // last 365 calendar days incl. today
      case AnalyticsRange.lifetime:
        return null; // No filtering
    }
  }

  Future<void> _init() async {
    try {
      await _analyticsService.trackScreenView('AnalyticsScreen');
      await _analyticsService.flushPendingEvents();

      final userId = _authService.currentUser?.id;
      if (userId == null) {
        setState(() {
          _error = LocalizationService.t('sign_in_required_to_view_analytics');
          _loading = false;
        });
        return;
      }

      // Removed auto seeding to ensure analytics only reflect real activity
      // await _analyticsService.seedSampleEventsIfNeeded(userId: userId);
      await _fetchAnalytics();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = LocalizationService.t('failed_to_load_analytics');
        _loading = false;
      });
    }
  }

  Future<void> _fetchAnalytics() async {
    try {
      final userId = _authService.currentUser?.id;
      if (userId == null) return;

      // Fetch user's posts and compute analytics directly from post counters
      final posts = await _postsService.getUserPosts(userId: userId, limit: 50);

      // Build a minimal analytics map using existing post counters
      final Map<String, dynamic> userAnalytics = {
        'total_events': 0, // Not using event stream here
        'event_counts': <String, int>{},
        'daily_activity': <String, int>{},
        'most_active_day': '-',
      };

      if (!mounted) return;
      setState(() {
        _userAnalytics = userAnalytics;
        _posts = posts;
        _postAnalytics.clear(); // Not using per-range analytics events
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = LocalizationService.t('failed_to_load_analytics');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          LocalizationService.t('analytics'),
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (kDebugMode && false)
            IconButton(
              tooltip: LocalizationService.t('debug_analytics'),
              icon: const Icon(Icons.bug_report, color: AppColors.textPrimary),
              onPressed: _onDebugPressed,
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: AppColors.primary,
          labelColor: AppColors.textPrimary,
          unselectedLabelColor: AppColors.textSecondary,
          tabs: [
            Tab(text: LocalizationService.t('tab_1d')),
            Tab(text: LocalizationService.t('tab_1w')),
            Tab(text: LocalizationService.t('tab_30d')),
            Tab(text: LocalizationService.t('tab_1y')),
            Tab(text: LocalizationService.t('tab_lifetime')),
          ],
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    if (_error != null) {
      return Center(
        child: Text(_error!, style: const TextStyle(color: AppColors.error)),
      );
    }

    // Determine the start of the selected calendar range
    final DateTime? rangeStart = _rangeStartDate();

    // Filter posts by publish date within the selected range (inclusive)
    final List<PostModel> filteredPosts = (rangeStart == null)
        ? _posts
        : _posts.where((p) => !p.createdAt.isBefore(rangeStart)).toList();

    // Aggregate metrics from filtered posts
    int totalViews = 0;
    int totalLikes = 0;
    int totalComments = 0;
    int totalShares = 0;
    for (final p in filteredPosts) {
      totalViews += p.views;
      totalLikes += p.likes;
      totalComments += p.comments;
      totalShares += p.shares;
    }

    // Total Events is the sum of all counters
    final int totalEvents =
        totalViews + totalLikes + totalComments + totalShares;

    // Build daily activity map (publish count per day)
    final Map<String, int> dailyActivity = <String, int>{};
    for (final p in filteredPosts) {
      final String key =
          '${p.createdAt.year}-${p.createdAt.month.toString().padLeft(2, '0')}-${p.createdAt.day.toString().padLeft(2, '0')}';
      dailyActivity[key] = (dailyActivity[key] ?? 0) + 1;
    }
    final String mostActiveDay = dailyActivity.isEmpty
        ? '-'
        : dailyActivity.entries
              .reduce((a, b) => a.value >= b.value ? a : b)
              .key;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary Section
          Text(
            _summaryTitle(),
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _statCard(LocalizationService.t('total_events'), '$totalEvents'),
              _statCard(LocalizationService.t('post_views'), '$totalViews'),
              _statCard(LocalizationService.t('post_likes'), '$totalLikes'),
              _statCard(LocalizationService.t('comments'), '$totalComments'),
              _statCard(LocalizationService.t('shares'), '$totalShares'),
              _statCard(
                LocalizationService.t('most_active_day'),
                mostActiveDay,
              ),
            ],
          ),

          const SizedBox(height: 24),
          Text(
            LocalizationService.t('daily_activity'),
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          _activityChart(dailyActivity),

          const SizedBox(height: 24),
          Text(
            LocalizationService.t('posts_analytics'),
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          ...filteredPosts.map(_buildPostTile),
        ],
      ),
    );
  }

  Widget _statCard(String title, String value) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _activityChart(Map<String, int> dailyActivity) {
    if (dailyActivity.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
        ),
        child: Text(
          LocalizationService.t('no_activity_recorded'),
          style: const TextStyle(color: AppColors.textSecondary),
        ),
      );
    }

    final entries = dailyActivity.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final maxValue = entries
        .map((e) => e.value)
        .fold<int>(0, (p, c) => c > p ? c : p);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          for (final e in entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 90,
                    child: Text(
                      e.key,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final width = maxValue == 0
                            ? 0.0
                            : (constraints.maxWidth) * (e.value / maxValue);
                        return Stack(
                          alignment: Alignment.centerLeft,
                          children: [
                            Container(
                              height: 10,
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(
                                  alpha: 0.15,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            Container(
                              width: width,
                              height: 10,
                              decoration: BoxDecoration(
                                gradient: AppColors.primaryGradient,
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 32,
                    child: Text(
                      '${e.value}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPostTile(PostModel post) {
    // Display metrics using canonical counters from posts
    final views = post.views;
    final likes = post.likes;
    final comments = post.comments;
    final shares = post.shares;
    final engagementRate = views > 0
        ? (likes + comments + shares) / views
        : 0.0;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          // Preview thumbnail
          SizedBox(
            width: 56,
            height: 56,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                children: [
                  _buildPostPreview(post),
                  // ID overlay to help identify untitled posts
                  Positioned(
                    left: 4,
                    bottom: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        post.id.substring(0, 8),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (post.content.isNotEmpty)
                      ? post.content
                      : '${LocalizationService.t('untitled')} ${post.type}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    _metricChip(Icons.visibility, views),
                    const SizedBox(width: 8),
                    _metricChip(Icons.favorite, likes),
                    const SizedBox(width: 8),
                    _metricChip(Icons.comment, comments),
                    const SizedBox(width: 8),
                    _metricChip(Icons.share, shares),
                    const SizedBox(width: 8),
                    _metricChip(
                      Icons.insights,
                      '${(engagementRate * 100).toStringAsFixed(1)}%',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricChip(IconData icon, dynamic value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.textSecondary, size: 16),
          const SizedBox(width: 4),
          Text(
            '$value',
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Future<void> _onDebugPressed() async {
    final userId = _authService.currentUser?.id;
    if (userId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: LocalizedText('sign_in_required_to_debug_analytics')),
      );
      return;
    }

    try {
      // Mark that the debug button was used
      await _analyticsService.trackFeatureUsed('analytics_debug_button');

      // Emit a handful of test events to verify pipeline
      await _analyticsService.trackScreenView('AnalyticsScreen_Debug');
      await _analyticsService.trackSearch('debug_query', 'posts', 3);

      // Use a real post id if available to avoid UUID cast errors
      String? samplePostId;
      String samplePostType = 'image';
      try {
        final posts = await SupabaseConfig.client
            .from('posts')
            .select('id, type')
            .eq('user_id', userId)
            .limit(1);
        if (posts is List && posts.isNotEmpty) {
          final p = posts.first;
          samplePostId = p['id'] as String?;
          samplePostType = (p['type'] as String?) ?? 'image';
        }
      } catch (_) {}

      if (samplePostId != null) {
        await _analyticsService.trackPostView(
          samplePostId,
          samplePostType,
          duration: 5,
        );
        await _analyticsService.trackPostLike(samplePostId, samplePostType);
        await _analyticsService.trackPostComment(samplePostId, samplePostType);
        await _analyticsService.trackPostShare(
          samplePostId,
          samplePostType,
          'copy_link',
        );
      }

      // Also seed demo events if the account is brand new
      await _analyticsService.seedSampleEventsIfNeeded(userId: userId);

      // Push everything immediately
      await _analyticsService.flushPendingEvents();

      // Refresh UI with latest analytics
      await _fetchAnalytics();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: LocalizedText('debug_events_sent_analytics_refreshed'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: LocalizedText('failed_to_send_debug_events')),
      );
    }
  }
}

// New: render a preview image for the post if available
Widget _buildPostPreview(PostModel post) {
  final String? thumb = post.thumbnailUrl;
  final String? media = post.mediaUrl;
  if (thumb != null && thumb.isNotEmpty) {
    return Image.network(
      thumb,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => _previewPlaceholder(post),
    );
  }
  if (media != null && media.isNotEmpty) {
    return Image.network(
      media,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => _previewPlaceholder(post),
    );
  }
  return _previewPlaceholder(post);
}

Widget _previewPlaceholder(PostModel post) {
  return Container(
    color: AppColors.primary.withValues(alpha: 0.15),
    child: Icon(
      post.type == 'video' ? Icons.videocam : Icons.image,
      color: AppColors.primary,
    ),
  );
}
