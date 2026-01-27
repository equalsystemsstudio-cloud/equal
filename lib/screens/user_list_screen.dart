import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/app_colors.dart';
import '../services/social_service.dart';
import '../services/auth_service.dart';
import '../widgets/user_card.dart';
import '../services/localization_service.dart';
import 'profile/profile_screen.dart';

class UserListScreen extends StatefulWidget {
  final String title;
  final String userId;
  final UserListType type;

  const UserListScreen({
    super.key,
    required this.title,
    required this.userId,
    required this.type,
  });

  @override
  State<UserListScreen> createState() => _UserListScreenState();
}

enum UserListType { followers, following, likes, shares, suggested }

class _UserListScreenState extends State<UserListScreen>
    with TickerProviderStateMixin {
  final _socialService = SocialService();
  final _authService = AuthService();
  final _searchController = TextEditingController();

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _filteredUsers = [];
  Map<String, dynamic>? _currentUser;
  bool _isLoading = false;
  bool _isSearching = false;
  // ignore: unused_field
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    _loadCurrentUser();
    _loadUsers();
    _animationController.forward();

    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _animationController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentUser() async {
    try {
      final user = await _authService.getCurrentUser();
      setState(() {
        _currentUser = user;
      });
    } catch (e) {
      debugPrint(('Error loading current user: $e').toString());
    }
  }

  Future<void> _loadUsers() async {
    setState(() {
      _isLoading = true;
    });

    try {
      List<Map<String, dynamic>> users = [];

      switch (widget.type) {
        case UserListType.followers:
          users = await _socialService.getFollowers(widget.userId);
          break;
        case UserListType.following:
          users = await _socialService.getFollowing(widget.userId);
          break;
        case UserListType.likes:
          users = await _socialService.getPostLikes(widget.userId);
          break;
        case UserListType.shares:
          users = await _socialService.getPostShares(widget.userId);
          break;
        case UserListType.suggested:
          users = await _socialService.getSuggestedUsers(limit: 50);
          break;
      }

      setState(() {
        _users = users;
        _filteredUsers = users;
      });
    } catch (e) {
      debugPrint(('Error loading users: $e').toString());
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase().trim();
    setState(() {
      _searchQuery = query;
      _isSearching = query.isNotEmpty;

      if (query.isEmpty) {
        _filteredUsers = _users;
      } else {
        _filteredUsers = _users.where((user) {
          final username = (user['username'] ?? '').toLowerCase();
          final displayName = (user['display_name'] ?? '').toLowerCase();
          final bio = (user['bio'] ?? '').toLowerCase();

          return username.contains(query) ||
              displayName.contains(query) ||
              bio.contains(query);
        }).toList();
      }
    });
  }

  Future<void> _refreshUsers() async {
    await _loadUsers();
    HapticFeedback.lightImpact();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Column(
            children: [
              _buildHeader(),
              _buildSearchBar(),
              Expanded(child: _buildUsersList()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(Icons.arrow_back, color: AppColors.textPrimary),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (_users.isNotEmpty)
                  Text(
                    '${_filteredUsers.length} ${_filteredUsers.length == 1 ? 'user' : 'users'}',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            onPressed: _refreshUsers,
            icon: Icon(Icons.refresh, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Search users...',
          hintStyle: TextStyle(color: AppColors.textSecondary),
          prefixIcon: Icon(Icons.search, color: AppColors.textSecondary),
          suffixIcon: _isSearching
              ? IconButton(
                  onPressed: () {
                    _searchController.clear();
                  },
                  icon: Icon(Icons.clear, color: AppColors.textSecondary),
                )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.primary, width: 2),
          ),
          filled: true,
          fillColor: AppColors.surface,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
        style: TextStyle(color: AppColors.textPrimary),
      ),
    );
  }

  Widget _buildUsersList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_filteredUsers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _isSearching ? Icons.search_off : Icons.people_outline,
              size: 64,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 16),
            Text(
              _isSearching ? 'No users found' : _getEmptyMessage(),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _isSearching
                  ? 'Try searching with different keywords'
                  : _getEmptySubMessage(),
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshUsers,
      color: AppColors.primary,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _filteredUsers.length,
        itemBuilder: (context, index) {
          final user = _filteredUsers[index];
          return UserCard(
            user: user,
            currentUser: _currentUser,
            onFollowChanged: (isFollowing) {
              setState(() {
                user['is_following'] = isFollowing;
                user['followers_count'] =
                    (user['followers_count'] ?? 0) + (isFollowing ? 1 : -1);
              });
            },
            onTap: () {
              // Navigate to user profile
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ProfileScreen(
                    userId: user['id'],
                    initialUserProfile: user,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _getEmptyMessage() {
    switch (widget.type) {
      case UserListType.followers:
        return LocalizationService.t('no_trackers_yet');
      case UserListType.following:
        return LocalizationService.t('not_tracking_anyone');
      case UserListType.likes:
        return 'No likes yet';
      case UserListType.shares:
        return 'No shares yet';
      case UserListType.suggested:
        return 'No suggestions available';
    }
  }

  String _getEmptySubMessage() {
    switch (widget.type) {
      case UserListType.followers:
        return LocalizationService.t('followers_empty_sub');
      case UserListType.following:
        return LocalizationService.t('following_empty_sub');
      case UserListType.likes:
        return 'When people like this post,\nthey\'ll appear here.';
      case UserListType.shares:
        return 'When people share this post,\nthey\'ll appear here.';
      case UserListType.suggested:
        return 'Check back later for more suggestions.';
    }
  }
}
