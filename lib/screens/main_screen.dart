import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/app_colors.dart';
import 'main_feed_screen.dart';
import 'search_screen.dart';
import 'content_type_selection_screen.dart';
import 'notifications_screen.dart';
import 'profile/profile_screen.dart';
import '../services/auth_service.dart';
import '../services/notification_badge_service.dart';
import '../services/call_listener_service.dart';
import '../widgets/notification_badge.dart';
import '../services/localization_service.dart';
import 'dart:async'; // Added for StreamSubscription
import 'package:supabase_flutter/supabase_flutter.dart'; // Import Supabase types
import 'dart:ui' as ui;
import '../services/calling_service.dart';
import '../config/feature_flags.dart';

import '../widgets/upload_status_widget.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  final PageController _pageController = PageController();
  final _authService = AuthService();
  final _badgeService = NotificationBadgeService();
  final _callListenerService = CallListenerService();
  // New: CallingService for realtime call status updates
  final CallingService _callingService = CallingService();
  String? _currentUserId;

  // Track how many notifications were seen the last time Activity was opened
  int _activitySeenNotificationCount = 0; // ignore: unused_field

  // Listen to auth changes to reinitialize badge service for the current user
  // Listener for auth state
  StreamSubscription<AuthState>? _authSubscription; // Listener for auth state

  // Visibility notifier for Home/Feed tab
  final ValueNotifier<bool> _homeVisibleNotifier = ValueNotifier<bool>(true);

  // Visual-only press feedback for nav items
  int? _pressedIndex;

  @override
  void initState() {
    super.initState();
    // Preselect initial tab for screenshot/demo mode
    if (FeatureFlags.screenshotDemoMode &&
        FeatureFlags.screenshotInitialTabIndex != null) {
      _currentIndex = FeatureFlags.screenshotInitialTabIndex!;
      // Defer page jump until after first frame so PageController is attached
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_pageController.hasClients) {
          _pageController.jumpToPage(_currentIndex);
        }
      });
    }
    _getCurrentUser();
    _initializeBadgeService();
    _initializeCallListener();

    // Subscribe to auth state changes; reinitialize badges when session changes
    _authSubscription = _authService.authStateChanges.listen((authState) {
      try {
        final userId = authState.session?.user.id;
        if (userId != null) {
          // Signed in or user refreshed/updated
          if (!mounted) return;
          setState(() {
            _currentUserId = userId;
          });
          // Re-bind to current user defensively
          _badgeService.initialize();
          // Ensure widget is mounted before passing context
          if (!mounted) return;
          _callListenerService.initialize(context, userId);
          // NEW: initialize CallingService so CallingScreen receives realtime updates
          _callingService.initialize(userId);
        } else {
          // Signed out
          if (!mounted) return;
          setState(() {
            _currentUserId = null;
            _activitySeenNotificationCount = 0;
          });
          _badgeService.clearAllBadges();
        }
      } catch (e) {
        debugPrint('MainScreen: Error in auth state listener: $e');
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _badgeService.dispose();
    _callListenerService.dispose();
    _homeVisibleNotifier.dispose();
    _authSubscription?.cancel(); // Cancel auth listener
    super.dispose();
  }

  void _onTabTapped(int index) {
    if (index == _currentIndex) {
      // If tapping the same tab, scroll to top or refresh
      return;
    }

    setState(() {
      _currentIndex = index;
    });

    // Update visibility notifier based on selected tab
    _homeVisibleNotifier.value = index == 0;

    // If navigating to Activity, mark activity as seen so badge only shows new ones after this
    if (index == 3) {
      _badgeService.markActivitySeen();
    }

    if (_pageController.hasClients) {
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }

    HapticFeedback.lightImpact();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          PageView(
            controller: _pageController,
            onPageChanged: (index) {
              setState(() {
                _currentIndex = index;
              });
              // Update visibility notifier when swiping between tabs
              _homeVisibleNotifier.value = index == 0;
              // If swiping to Activity, mark seen
              if (index == 3) {
                _badgeService.markActivitySeen();
              }
            },
            children: [
              MainFeedScreen(feedVisibleNotifier: _homeVisibleNotifier),
              const SearchScreen(),
              const ContentTypeSelectionScreen(),
              const NotificationsScreen(),
              _currentUserId != null
                  ? ProfileScreen(userId: _currentUserId!)
                  : const Center(child: CircularProgressIndicator()),
              // Removed StatusHomeScreen page
            ],
          ),
          const UploadStatusWidget(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          // Subtle glossy gradient and lifted shadow for premium feel
          gradient: LinearGradient(
            colors: [
              AppColors.surface.withOpacity(0.92),
              AppColors.surface.withOpacity(0.88),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          border: Border(top: BorderSide(color: AppColors.border, width: 0.6)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.35),
              blurRadius: 24,
              offset: const Offset(0, -8),
            ),
          ],
        ),
        child: ClipRect(
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: SafeArea(
              child: Container(
                height: 78,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildNavItem(
                      icon: Icons.home_filled,
                      inactiveIcon: Icons.home_outlined,
                      index: 0,
                      label: LocalizationService.t('home'),
                    ),
                    _buildNavItem(
                      icon: Icons.search,
                      inactiveIcon: Icons.search_outlined,
                      index: 1,
                      label: LocalizationService.t('discover'),
                    ),
                    _buildCreateButton(),
                    _buildNavItemWithBadge(
                      icon: Icons.favorite,
                      inactiveIcon: Icons.favorite_outline,
                      index: 3,
                      label: LocalizationService.t('activity'),
                      // Show total unread notifications on Activity icon
                      badgeStream: _badgeService.notificationBadgeStream,
                    ),
                    _buildNavItem(
                      icon: Icons.person,
                      inactiveIcon: Icons.person_outline,
                      index: 4,
                      label: LocalizationService.t('profile'),
                    ),

                    // Removed bottom nav Status item
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required IconData inactiveIcon,
    required int index,
    required String label,
  }) {
    final isActive = _currentIndex == index;

    return GestureDetector(
      onTap: () => _onTabTapped(index),
      onTapDown: (_) => setState(() => _pressedIndex = index),
      onTapUp: (_) => Future.delayed(const Duration(milliseconds: 120), () {
        if (mounted) setState(() => _pressedIndex = null);
      }),
      onTapCancel: () => Future.delayed(const Duration(milliseconds: 120), () {
        if (mounted) setState(() => _pressedIndex = null);
      }),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Single icon with accent halo (removes duplicate icon)
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: EdgeInsets.all(isActive ? 9 : 7),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: isActive ? _accentGradientForIndex(index) : null,
                boxShadow: isActive
                    ? [
                        BoxShadow(
                          color: AppColors.primary.withOpacity(0.35),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ]
                    : [],
              ),
              child: AnimatedScale(
                scale: isActive ? 1.08 : (_pressedIndex == index ? 0.94 : 1.0),
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOutBack,
                child: Icon(
                  isActive ? icon : inactiveIcon,
                  color: isActive ? AppColors.primary : AppColors.textSecondary,
                  size: 22,
                ),
              ),
            ),
            const SizedBox(height: 4),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                  color: isActive ? AppColors.primary : AppColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(height: 2),
            AnimatedOpacity(
              opacity: isActive ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: Container(
                width: 6,
                height: 2.5,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItemWithBadge({
    required IconData icon,
    required IconData inactiveIcon,
    required int index,
    required String label,
    required Stream<int> badgeStream,
  }) {
    final isActive = _currentIndex == index;

    return GestureDetector(
      onTap: () => _onTabTapped(index),
      onTapDown: (_) => setState(() => _pressedIndex = index),
      onTapUp: (_) => Future.delayed(const Duration(milliseconds: 120), () {
        if (mounted) setState(() => _pressedIndex = null);
      }),
      onTapCancel: () => Future.delayed(const Duration(milliseconds: 120), () {
        if (mounted) setState(() => _pressedIndex = null);
      }),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            StreamBuilder<int>(
              stream: badgeStream,
              initialData: 0,
              builder: (context, snapshot) {
                final badgeCount = snapshot.data ?? 0;
                return TikTokNotificationBadge(
                  count: badgeCount,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: EdgeInsets.all(isActive ? 9 : 7),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: isActive
                          ? _accentGradientForIndex(index)
                          : null,
                      boxShadow: isActive
                          ? [
                              BoxShadow(
                                color: AppColors.primary.withOpacity(0.35),
                                blurRadius: 18,
                                offset: const Offset(0, 8),
                              ),
                            ]
                          : [],
                    ),
                    child: AnimatedScale(
                      scale: isActive
                          ? 1.08
                          : (_pressedIndex == index ? 0.94 : 1.0),
                      duration: const Duration(milliseconds: 120),
                      curve: Curves.easeOutBack,
                      child: Icon(
                        isActive ? icon : inactiveIcon,
                        color: isActive
                            ? AppColors.primary
                            : AppColors.textSecondary,
                        size: 22,
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 4),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                  color: isActive ? AppColors.primary : AppColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(height: 2),
            AnimatedOpacity(
              opacity: isActive ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: Container(
                width: 6,
                height: 2.5,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCreateButton() {
    return GestureDetector(
      onTap: () => _onTabTapped(2),
      onTapDown: (_) => setState(() => _pressedIndex = 2),
      onTapUp: (_) => Future.delayed(const Duration(milliseconds: 120), () {
        if (mounted) setState(() => _pressedIndex = null);
      }),
      onTapCancel: () => Future.delayed(const Duration(milliseconds: 120), () {
        if (mounted) setState(() => _pressedIndex = null);
      }),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Transform.translate(
              offset: const Offset(0, -3),
              child: Container(
                width: 58,
                height: 38,
                decoration: BoxDecoration(
                  gradient: _currentIndex == 2
                      ? AppColors.primaryGradient
                      : LinearGradient(
                          colors: [
                            AppColors.textSecondary,
                            AppColors.textSecondary,
                          ],
                        ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.25),
                      blurRadius: 24,
                      offset: const Offset(0, 6),
                    ),
                    if (_currentIndex == 2)
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.35),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                  ],
                ),
                child: AnimatedScale(
                  scale: _currentIndex == 2
                      ? 1.06
                      : (_pressedIndex == 2 ? 0.94 : 1.0),
                  duration: const Duration(milliseconds: 120),
                  curve: Curves.easeOutBack,
                  child: Icon(
                    _currentIndex == 2 ? Icons.add : Icons.add_outlined,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              LocalizationService.t('create'),
              style: TextStyle(
                fontSize: 10,
                fontWeight: _currentIndex == 2
                    ? FontWeight.w600
                    : FontWeight.w400,
                color: _currentIndex == 2
                    ? AppColors.primary
                    : AppColors.textSecondary,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Accent gradient per tab while keeping core brand glow
  LinearGradient _accentGradientForIndex(int index) {
    switch (index) {
      case 1: // Discover
        return LinearGradient(
          colors: [
            Colors.tealAccent.withOpacity(0.28),
            AppColors.primary.withOpacity(0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case 3: // Activity
        return LinearGradient(
          colors: [
            Colors.pinkAccent.withOpacity(0.28),
            AppColors.primary.withOpacity(0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case 4: // Profile
        return LinearGradient(
          colors: [
            Colors.deepPurpleAccent.withOpacity(0.28),
            AppColors.primary.withOpacity(0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      default: // Home
        return LinearGradient(
          colors: [
            AppColors.primary.withOpacity(0.22),
            AppColors.primary.withOpacity(0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
    }
  }

  // Add missing helper methods
  void _getCurrentUser() {
    try {
      _currentUserId = _authService.currentUser?.id;
    } catch (e) {
      debugPrint('MainScreen: Failed to get current user: $e');
      _currentUserId = null;
    }
  }

  Future<void> _initializeBadgeService() async {
    try {
      await _badgeService.initialize();
    } catch (e) {
      debugPrint('MainScreen: Failed to initialize badge service: $e');
    }
  }

  void _initializeCallListener() {
    try {
      final uid = _authService.currentUser?.id;
      if (uid != null) {
        if (!mounted) return;
        if (FeatureFlags.callsEnabled) {
          _callListenerService.initialize(context, uid);
          _callingService.initialize(uid);
        }
      }
    } catch (e) {
      debugPrint('MainScreen: Failed to initialize call listener: $e');
    }
  }
}
