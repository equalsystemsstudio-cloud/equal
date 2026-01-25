import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import '../config/app_colors.dart';
import '../services/social_service.dart';
import '../services/enhanced_notification_service.dart';
import '../services/notification_badge_service.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../models/notification_model.dart';
import '../services/localization_service.dart';
import '../services/supabase_service.dart';
import 'package:flutter/foundation.dart';

import '../widgets/enhanced_notification_card.dart';
import '../widgets/tiktok_notification_banner.dart';
import 'messaging/conversations_screen.dart';
import 'messaging/enhanced_chat_screen.dart';
import '../widgets/user_card.dart';
import 'live_stream_viewer_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen>
    with SingleTickerProviderStateMixin {
  final _socialService = SocialService();
  final _notificationService = EnhancedNotificationService();
  final _badgeService = NotificationBadgeService();
  final _authService = AuthService();
  final _databaseService = DatabaseService();
  late TabController _tabController;

  List<NotificationModel> _allNotifications = [];
  List<NotificationModel> _followNotifications = [];
  List<NotificationModel> _likeNotifications = [];
  List<NotificationModel> _commentNotifications = [];

  bool _isLoading = false;
  bool _isRefreshing = false;
  // int _unreadCount = 0; // removed reliance on global unread count for Activity UI
  int _unreadMessageCount = 0;
  int _trackerCount = 0; // Actual trackers count from follows table
  // Tracks tab state
  List<Map<String, dynamic>> _trackerUsers = [];
  List<Map<String, dynamic>> _filteredTrackerUsers = [];
  final TextEditingController _tracksSearchController = TextEditingController();
  bool _isLoadingTrackers = false;
  // New: Effective unread count (new since last seen)
  int _effectiveUnreadCount = 0;
  // Baseline counts captured when Activity is visited
  int _baselineAllCount = 0;
  int _baselineLikeCount = 0;
  int _baselineCommentCount = 0;
  int _baselineFollowCount = 0;
  int _baselineMessageCount = 0;
  // Debounce timer for badge-triggered refreshes
  Timer? _badgeRefreshDebounce;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    // Reset baselines only when specific tabs are viewed (see listener below)
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        final int idx = _tabController.index;
        if (idx == 1) {
          // Messages tab viewed: capture baseline for unread messages
          setState(() {
            _baselineMessageCount = _unreadMessageCount;
          });
        } else if (idx == 2) {
          // People tracking you tab viewed: capture baseline for follows
          setState(() {
            _baselineFollowCount = _followNotifications.length;
          });
        } else if (idx == 0) {
          // All tab viewed: capture baseline for All
          setState(() {
            _baselineAllCount = _allNotifications.length;
          });
        } else if (idx == 3) {
          // Likes tab viewed: capture baseline for likes
          setState(() {
            _baselineLikeCount = _likeNotifications.length;
          });
        } else if (idx == 4) {
          // Comments tab viewed: capture baseline for comments
          setState(() {
            _baselineCommentCount = _commentNotifications.length;
          });
        }
        // Auto-mark notifications as read for the viewed tab
        _autoMarkReadForTab(idx);
      }
    });
    _initializeNotifications();
  }

  Future<void> _initializeNotifications() async {
    await _notificationService.initialize();
    await _loadNotifications();
    await _loadUnreadCount();
    await _loadTrackerCount();
    await _loadTrackersList();
    _resetActivityBaselines();

    // Listen for real-time notifications from EnhancedNotificationService
    _notificationService.notificationStream.listen((notification) {
      if (!mounted) return;
      _addNewNotification(notification);
      if (ModalRoute.of(context)?.isCurrent != true) {
        NotificationOverlayManager.showNotification(
          context,
          notification,
          onTap: () => _handleNotificationTap(notification),
        );
      }
    });

    // Listen for effective notification count (new since last seen)
    _badgeService.effectiveNotificationBadgeStream.listen((count) {
      if (!mounted) return;
      setState(() {
        _effectiveUnreadCount = count;
      });
      if (ModalRoute.of(context)?.isCurrent == true && count == 0) {
        // Reset baselines that correspond to Activity lists, but DO NOT reset Messages/Follows here
        _resetActivityBaselines();
      }
      if (ModalRoute.of(context)?.isCurrent == true && count > 0) {
        _badgeRefreshDebounce?.cancel();
        _badgeRefreshDebounce = Timer(
          const Duration(milliseconds: 300),
          () async {
            if (!mounted) return;
            if (ModalRoute.of(context)?.isCurrent != true) return;
            await _loadNotifications();
          },
        );
      }
    });

    // Also listen to raw notification count to trigger list refresh when inserts arrive
    _badgeService.notificationBadgeStream.listen((count) {
      if (!mounted) return;
      if (ModalRoute.of(context)?.isCurrent == true) {
        _badgeRefreshDebounce?.cancel();
        _badgeRefreshDebounce = Timer(
          const Duration(milliseconds: 250),
          () async {
            if (!mounted) return;
            if (ModalRoute.of(context)?.isCurrent != true) return;
            await _loadNotifications();
          },
        );
      }
    });

    // Listen for message count changes (badge only)
    _badgeService.messageBadgeStream.listen((count) {
      if (!mounted) return;
      setState(() {
        _unreadMessageCount = count;
      });
    });
  }

  Future<void> _loadTrackerCount() async {
    try {
      final userId = _authService.currentUser?.id;
      if (userId == null) return;
      final trackers = await _databaseService.getTrackers(userId);
      final count = trackers.length;
      if (mounted) {
        setState(() {
          _trackerCount = count;
        });
      }
    } catch (e) {
      debugPrint('Failed to load tracker count: $e');
    }
  }

  void _addNewNotification(NotificationModel notification) {
    setState(() {
      _allNotifications.insert(0, notification);

      // Add to specific category lists
      final String resolvedType = (notification.type.isNotEmpty)
          ? notification.type
          : (notification.data?['action_type']?.toString() ?? '');
      switch (resolvedType) {
        case 'follow':
          _followNotifications.insert(0, notification);
          break;
        case 'like':
          _likeNotifications.insert(0, notification);
          break;
        case 'comment':
          _commentNotifications.insert(0, notification);
          break;
        case 'share':
          // Share notifications appear in 'All' tab only
          break;
      }
    });
  }

  void _handleNotificationTap(NotificationModel notification) async {
    // Mark as read
    _notificationService.markAsRead(notification.id);
    // Update local UI immediately
    _markNotificationAsRead(notification.id);

    // Navigate based on notification type
    switch (notification.type) {
      case 'like':
      case 'comment':
      case 'mention':
      case 'share':
        final postId = notification.data?['post_id'] ?? notification.postId;
        if (postId != null) {
          // Navigate to post detail screen
          Navigator.pushNamed(
            context,
            '/post_detail',
            arguments: {'postId': postId},
          );
        }
        break;
      case 'follow':
        if (notification.actionUserId != null) {
          // Navigate to user profile (implement navigation logic)
          debugPrint(
            ('Navigate to profile: ${notification.actionUserId}').toString(),
          );
        }
        break;
      case 'message':
        // Navigate directly to the specific chat
        final conversationId = notification.data?['conversation_id'];
        final senderId = notification.data?['sender_id'];
        final senderUsername = notification.data?['sender_username'];

        if (conversationId != null && senderId != null) {
          String resolvedName =
              (senderUsername != null && senderUsername.toString().isNotEmpty)
              ? '@$senderUsername'
              : 'Unknown User';
          String? resolvedAvatar;

          // Capture navigator before any async gaps
          final navigator = Navigator.of(context);

          // Try to hydrate from profile if username is missing or generic
          if (resolvedName == 'Unknown User') {
            try {
              final profile = await SupabaseService.getProfile(senderId);
              if (profile != null) {
                final displayName = (profile['display_name'] as String?) ?? '';
                final username = (profile['username'] as String?) ?? '';
                resolvedName = displayName.isNotEmpty
                    ? displayName
                    : (username.isNotEmpty ? '@$username' : resolvedName);
                resolvedAvatar =
                    (profile['avatar_url'] as String?) ?? resolvedAvatar;
              }
            } catch (_) {
              // Ignore hydration errors; fall back to existing values
            }
          }

          navigator.push(
            MaterialPageRoute(
              builder: (context) => EnhancedChatScreen(
                conversationId: conversationId,
                otherUserId: senderId,
                otherUserName: resolvedName,
                otherUserAvatar: resolvedAvatar, // Avatar may be hydrated
              ),
            ),
          );
        } else {
          // Fallback to conversations screen if data is missing
          final navigator = Navigator.of(context);
          navigator.push(
            MaterialPageRoute(
              builder: (context) => const ConversationsScreen(),
            ),
          );
        }
        break;
      case 'live':
        {
          final dynamic rawStreamId =
              notification.data?['stream_id'] ?? notification.data?['streamId'];
          final String? streamId = rawStreamId?.toString();
          final String? streamTitleFromData = notification.data?['title']
              ?.toString();
          final String streamTitle =
              (streamTitleFromData != null && streamTitleFromData.isNotEmpty)
              ? streamTitleFromData
              : notification.title;
          if (streamId != null && streamId.isNotEmpty) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => LiveStreamViewerScreen(
                  streamId: streamId,
                  title: streamTitle,
                ),
              ),
            );
          }
        }
        break;
    }
  }

  @override
  void dispose() {
    _badgeRefreshDebounce?.cancel();
    _tabController.dispose();
    _tracksSearchController.dispose();
    super.dispose();
  }

  Future<void> _loadNotifications() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      final notifications = await _notificationService.loadNotifications(
        limit: 50,
      );

      if (mounted) {
        setState(() {
          _allNotifications = notifications;
          _followNotifications = notifications
              .where(
                (n) =>
                    n.type == 'follow' ||
                    (n.data?['action_type']?.toString() == 'follow'),
              )
              .toList();
          _likeNotifications = notifications.where((n) {
            final type = n.type;
            final dataType = n.data?['action_type']?.toString();
            return type == 'like' || dataType == 'like';
          }).toList();
          _commentNotifications = notifications.where((n) {
            final type = n.type;
            final dataType = n.data?['action_type']?.toString();
            return type == 'comment' || dataType == 'comment';
          }).toList();
        });
      }
    } catch (e) {
      debugPrint(('Error loading notifications: $e').toString());
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadUnreadCount() async {
    try {
      // Prefer badge service for real-time accurate counts
      final count = _badgeService.notificationCount;
      final messageCount = _badgeService.messageCount;
      if (mounted) {
        setState(() {
          // _unreadCount = count; // removed reliance on unread notification count
          _unreadMessageCount = messageCount;
        });
      }
    } catch (e) {
      debugPrint(('Error loading unread count: $e').toString());
    }
  }

  Future<void> _refreshNotifications() async {
    if (mounted) {
      setState(() {
        _isRefreshing = true;
      });
    }

    await Future.wait([
      _loadNotifications(),
      _loadUnreadCount(),
      _loadTrackerCount(),
      _loadTrackersList(),
    ]);

    if (mounted) {
      setState(() {
        _isRefreshing = false;
      });
    }

    HapticFeedback.lightImpact();
  }

  Future<void> _markAllAsRead() async {
    try {
      await _notificationService.markAllAsRead();
      setState(() {
        // Update all notifications to read status
        for (int i = 0; i < _allNotifications.length; i++) {
          _allNotifications[i] = _allNotifications[i].copyWith(isRead: true);
        }
      });
      // Sync badge service immediately
      _badgeService.updateNotificationCount(0);
      HapticFeedback.lightImpact();
    } catch (e) {
      debugPrint(('Error marking all as read: $e').toString());
    }
  }

  // Auto-mark notifications as read for the active tab
  void _autoMarkReadForTab(int tabIndex) {
    switch (tabIndex) {
      case 0: // All
        // Mark all notifications as read
        _markAllAsRead();
        break;
      case 1: // Messages
        _markCategoryAsReadOnView('message');
        break;
      case 2: // Tracking You (Follows)
        _markCategoryAsReadOnView('follow');
        break;
      case 3: // Likes
        _markCategoryAsReadOnView('like');
        break;
      case 4: // Comments
        _markCategoryAsReadOnView('comment');
        break;
    }
  }

  // Helper: mark all notifications in a category as read on view, and update local UI immediately
  Future<void> _markCategoryAsReadOnView(String category) async {
    try {
      await _notificationService.markCategoryAsRead(category);
      setState(() {
        // Update in All list
        for (int i = 0; i < _allNotifications.length; i++) {
          final n = _allNotifications[i];
          final String type = n.type;
          final String? dataType = n.data?['action_type']?.toString();
          if (type == category || dataType == category) {
            _allNotifications[i] = n.copyWith(isRead: true);
          }
        }
        // Update in category-specific lists
        if (category == 'follow') {
          for (int i = 0; i < _followNotifications.length; i++) {
            _followNotifications[i] = _followNotifications[i].copyWith(
              isRead: true,
            );
          }
        } else if (category == 'like') {
          for (int i = 0; i < _likeNotifications.length; i++) {
            _likeNotifications[i] = _likeNotifications[i].copyWith(
              isRead: true,
            );
          }
        } else if (category == 'comment') {
          for (int i = 0; i < _commentNotifications.length; i++) {
            _commentNotifications[i] = _commentNotifications[i].copyWith(
              isRead: true,
            );
          }
        }
      });
      // Provide gentle haptic feedback on successful auto-mark
      HapticFeedback.selectionClick();
    } catch (e) {
      debugPrint('Error auto-marking category "$category" as read: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildTabs(),
            Expanded(child: _buildContent()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isNarrow = constraints.maxWidth < 420;

        final Widget headerLeft = Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              LocalizationService.t('activity'),
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            if (_effectiveUnreadCount > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.error,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _effectiveUnreadCount.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        );

        final Widget headerRight = const SizedBox.shrink();

        return Container(
          padding: const EdgeInsets.all(16),
          child: isNarrow
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    headerLeft,
                    const SizedBox(height: 8),
                    Align(alignment: Alignment.centerRight, child: headerRight),
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: headerLeft),
                    headerRight,
                  ],
                ),
        );
      },
    );
  }

  Widget _buildTabs() {
    // Compute unread counts per category
    final int unreadAll = _allNotifications.where((n) => !n.isRead).length;
    final int unreadLikes = _likeNotifications.where((n) => !n.isRead).length;
    final int unreadComments = _commentNotifications
        .where((n) => !n.isRead)
        .length;
    final int unreadFollows = _followNotifications
        .where((n) => !n.isRead)
        .length;
    final int unreadMessages = _unreadMessageCount;

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
        labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
        unselectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w500,
          fontSize: 12,
        ),
        isScrollable: true,
        tabs: [
          Tab(
            text: unreadAll > 0
                ? "${LocalizationService.t('all')} ($unreadAll)"
                : LocalizationService.t('all'),
          ),
          Tab(
            text: unreadMessages > 0
                ? "${LocalizationService.t('messages')} ($unreadMessages)"
                : LocalizationService.t('messages'),
          ),
          Tab(
            text: unreadFollows > 0
                ? "${LocalizationService.t('tracking_you')} ($unreadFollows)"
                : LocalizationService.t('tracking_you'),
          ),
          Tab(
            text: unreadLikes > 0
                ? "${LocalizationService.t('likes')} ($unreadLikes)"
                : LocalizationService.t('likes'),
          ),
          Tab(
            text: unreadComments > 0
                ? "${LocalizationService.t('comments')} ($unreadComments)"
                : LocalizationService.t('comments'),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    // Show a global loading indicator during initial load
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    return TabBarView(
      controller: _tabController,
      children: [
        // All
        _buildNotificationsList(_allNotifications, showActionButton: false),
        // Messages
        _buildMessagesTab(),
        // People tracking you
        _buildTracksTab(),
        // Likes
        _buildNotificationsList(_likeNotifications),
        // Comments
        _buildNotificationsList(_commentNotifications),
      ],
    );
  }

  Widget _buildMessagesTab() {
    return const ConversationsScreen();
  }

  Widget _buildNotificationsList(
    List<NotificationModel> notifications, {
    bool showActionButton = true,
  }) {
    if (notifications.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.notifications_none,
              size: 64,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 16),
            Text(
              LocalizationService.t('no_notifications_yet'),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              LocalizationService.t('notifications_empty_subtitle'),
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshNotifications,
      color: AppColors.primary,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: notifications.length,
        itemBuilder: (context, index) {
          final notification = notifications[index];
          return EnhancedNotificationCard(
            notification: notification,
            onTap: () {
              _handleNotificationTap(notification);
            },
            onMarkAsRead: () async {
              await _notificationService.markAsRead(notification.id);
              _markNotificationAsRead(notification.id);
            },
            showActionButton: showActionButton,
          );
        },
      ),
    );
  }

  // Update local UI when a notification is marked as read
  Future<void> _markNotificationAsRead(String notificationId) async {
    try {
      if (mounted) {
        // Determine if this notification was previously unread
        bool wasUnread = false;
        for (int i = 0; i < _allNotifications.length; i++) {
          if (_allNotifications[i].id == notificationId) {
            wasUnread = !_allNotifications[i].isRead;
            break;
          }
        }
        setState(() {
          // Update the notification in all lists
          for (int i = 0; i < _allNotifications.length; i++) {
            if (_allNotifications[i].id == notificationId) {
              _allNotifications[i] = _allNotifications[i].copyWith(
                isRead: true,
              );
            }
          }
          for (int i = 0; i < _followNotifications.length; i++) {
            if (_followNotifications[i].id == notificationId) {
              _followNotifications[i] = _followNotifications[i].copyWith(
                isRead: true,
              );
            }
          }
          for (int i = 0; i < _likeNotifications.length; i++) {
            if (_likeNotifications[i].id == notificationId) {
              _likeNotifications[i] = _likeNotifications[i].copyWith(
                isRead: true,
              );
            }
          }
          for (int i = 0; i < _commentNotifications.length; i++) {
            if (_commentNotifications[i].id == notificationId) {
              _commentNotifications[i] = _commentNotifications[i].copyWith(
                isRead: true,
              );
            }
          }
          if (wasUnread) {
            // _unreadCount = (_unreadCount - 1).clamp(0, 1 << 30); // removed reliance on unread count
          }
        });
        if (wasUnread) {
          // Sync badge service immediately to update Activity icon (unread count not used for Activity badge anymore)
          // _badgeService.updateNotificationCount(_unreadCount);
          // Do not mark Activity as seen here; baseline advances only when Activity tab is opened
          // _badgeService.markActivitySeen();
        }
      }
    } catch (e) {
      debugPrint('Error marking notification as read: $e');
    }
  }

  // Build Tracks tab content with search and list of trackers
  Widget _buildTracksTab() {
    final currentUserId = _authService.currentUser?.id;
    // Compute new trackers since last seen (effective follows)
    final int _newTrackerCountRaw =
        _followNotifications.length - _baselineFollowCount;
    final int _newTrackerCount = _newTrackerCountRaw > 0
        ? _newTrackerCountRaw
        : 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  LocalizationService.t('tracking_you'),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              // Show ONLY new tracker count since last seen
              if (_newTrackerCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _newTrackerCount.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        // Search field
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border, width: 1),
            ),
            child: TextField(
              controller: _tracksSearchController,
              onChanged: _filterTracks,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: LocalizationService.t('search_trackers'),
                hintStyle: const TextStyle(color: AppColors.textSecondary),
                prefixIcon: const Icon(
                  Icons.search,
                  color: AppColors.textSecondary,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _isLoadingTrackers
              ? const Center(child: CircularProgressIndicator())
              : (_filteredTrackerUsers.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.group_outlined,
                              size: 64,
                              color: AppColors.textSecondary,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              LocalizationService.t('no_one_tracking_you'),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _refreshNotifications,
                        color: AppColors.primary,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          itemCount: _filteredTrackerUsers.length,
                          itemBuilder: (context, index) {
                            final user = _filteredTrackerUsers[index];
                            return UserCard(
                              user: user,
                              currentUser: currentUserId != null
                                  ? {'id': currentUserId}
                                  : null,
                              onTap: () {
                                // TODO: navigate to profile screen when implemented
                              },
                              onFollowChanged: (isFollowing) {
                                setState(() {
                                  _filteredTrackerUsers[index]['is_following'] =
                                      isFollowing;
                                });
                              },
                              showTrackBackLabel: true,
                            );
                          },
                        ),
                      )),
        ),
      ],
    );
  }

  void _filterTracks(String query) {
    setState(() {
      final lower = query.toLowerCase();
      _filteredTrackerUsers = _trackerUsers.where((u) {
        final username = (u['username'] ?? '').toString().toLowerCase();
        final displayName = (u['display_name'] ?? '').toString().toLowerCase();
        return username.contains(lower) || displayName.contains(lower);
      }).toList();
    });
  }

  Future<void> _loadTrackersList() async {
    try {
      final currentUserId = _authService.currentUser?.id;
      if (currentUserId == null) return;

      if (mounted) {
        setState(() {
          _isLoadingTrackers = true;
        });
      }

      // Fetch the list of users the current user is already tracking
      List<Map<String, dynamic>> trackingList = [];
      try {
        trackingList = await _databaseService.getTracking(currentUserId);
      } catch (_) {}
      final Set<String> trackingIds = trackingList
          .map((u) => (u['id'] ?? u['following_id'])?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();

      List<Map<String, dynamic>> users = [];
      try {
        final trackers = await _databaseService.getTrackers(currentUserId);
        users = trackers.map<Map<String, dynamic>>((t) {
          final String uid = (t['id'] ?? t['follower_id'])?.toString() ?? '';
          return {
            'id': uid,
            'username': t['username'],
            'display_name': t['display_name'] ?? t['username'],
            'avatar_url': t['avatar_url'],
            'bio': t['bio'] ?? '',
            'is_verified': t['is_verified'] ?? false,
            'followers_count': t['followers_count'] ?? 0,
            'following_count': t['following_count'] ?? 0,
            'posts_count': t['posts_count'] ?? 0,
            // Correctly mark whether current user is already tracking this tracker
            'is_following': trackingIds.contains(uid),
          };
        }).toList();
      } catch (e) {
        // Fallback to legacy followers join
        final legacyFollowers = await _socialService.getFollowers(
          currentUserId,
        );
        users = legacyFollowers.map<Map<String, dynamic>>((f) {
          final p = f['profiles'] ?? {};
          final String uid = (p['id'] ?? f['follower_id'])?.toString() ?? '';
          return {
            'id': uid,
            'username': p['username'] ?? 'unknown',
            'display_name': p['display_name'] ?? p['username'] ?? 'Unknown',
            'avatar_url': p['avatar_url'],
            'bio': p['bio'] ?? '',
            'is_verified': false,
            'followers_count': 0,
            'following_count': 0,
            'posts_count': 0,
            // Correctly mark whether current user is already tracking this tracker
            'is_following': trackingIds.contains(uid),
          };
        }).toList();
      }

      if (mounted) {
        setState(() {
          _trackerUsers = users;
          _filteredTrackerUsers = users;
          _isLoadingTrackers = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading trackers list: $e');
      if (mounted) {
        setState(() {
          _isLoadingTrackers = false;
        });
      }
    }
  }

  void _resetActivityBaselines() {
    _baselineAllCount = _allNotifications.length;
    _baselineLikeCount = _likeNotifications.length;
    _baselineCommentCount = _commentNotifications.length;
    _baselineFollowCount = _followNotifications.length;
    _baselineMessageCount = _unreadMessageCount;
  }

  // Dev-only: insert a test notification to verify real-time UI
  Future<void> _insertDebugNotification() async {
    if (!kDebugMode) return;
    try {
      final userId = _authService.currentUser?.id;
      if (userId == null) {
        debugPrint('Cannot insert debug notification: no authenticated user');
        return;
      }
      final now = DateTime.now().toIso8601String();
      await _notificationService.createNotification(
        userId: userId,
        type: 'message',
        title: 'New Message',
        message: 'Debug: Hi at $now',
        data: {
          'action_type': 'message',
          'sender_id': userId,
          'sender_username':
              _authService.currentUser?.userMetadata?['username'],
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: LocalizedText('Inserted test notification')),
      );
    } catch (e) {
      debugPrint('Failed to insert debug notification: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: LocalizedText('Insert failed: $e')));
    }
  }

  // Dev-only: insert a test comment notification to verify Activity badge updates
  Future<void> _insertDebugCommentNotification() async {
    if (!kDebugMode) return;
    try {
      final userId = _authService.currentUser?.id;
      if (userId == null) {
        debugPrint('Cannot insert debug comment: no authenticated user');
        return;
      }
      final now = DateTime.now().toIso8601String();
      await _notificationService.createNotification(
        userId: userId,
        type: 'comment',
        title: '💬 New Comment',
        message: 'Debug: New comment at $now',
        data: {
          'action_type': 'comment',
          'post_id': 'debug_post',
          'comment_id': 'debug_comment',
          'commenter_id': userId,
          'commenter_username':
              _authService.currentUser?.userMetadata?['username'],
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: LocalizedText('Inserted test comment notification')),
      );
    } catch (e) {
      debugPrint('Failed to insert debug comment notification: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: LocalizedText('Insert failed: $e')));
    }
  }

  // Dev-only: force badge counts to reload from database and update Activity icon
  Future<void> _forceBadgeSync() async {
    if (!kDebugMode) return;
    try {
      await _badgeService.loadInitialCounts();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: LocalizedText('Badge counts reloaded')));
    } catch (e) {
      debugPrint('Failed to force badge sync: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: LocalizedText('Badge sync failed: $e')));
    }
  }
}
