import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/app_colors.dart';
import '../services/social_service.dart';
import '../services/localization_service.dart';
import '../config/supabase_config.dart';

class UserCard extends StatefulWidget {
  final Map<String, dynamic> user;
  final Map<String, dynamic>? currentUser;
  final Function(bool)? onFollowChanged;
  final VoidCallback? onTap;
  final bool showFollowButton;
  final bool showBio;
  final bool showTrackBackLabel; // If true and not following, show 'Track Back'

  const UserCard({
    super.key,
    required this.user,
    this.currentUser,
    this.onFollowChanged,
    this.onTap,
    this.showFollowButton = true,
    this.showBio = true,
    this.showTrackBackLabel = false,
  });

  @override
  State<UserCard> createState() => _UserCardState();
}

class _UserCardState extends State<UserCard>
    with SingleTickerProviderStateMixin {
  final _socialService = SocialService();

  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  bool _isFollowing = false;
  bool _isLoading = false;
  // int _followersCount = 0;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    _isFollowing = widget.user['is_following'] ?? false;
    // _followersCount = widget.user['followers_count'] ?? 0;
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _toggleFollow() async {
    if (_isLoading || widget.currentUser == null) return;

    // Don't allow following yourself
    if (widget.user['id'] == widget.currentUser!['id']) return;

    setState(() {
      _isLoading = true;
    });

    try {
      if (_isFollowing) {
        await _socialService.unfollowUser(widget.user['id']);
      } else {
        await _socialService.followUser(widget.user['id']);
      }

      setState(() {
        _isFollowing = !_isFollowing;
        // _followersCount += _isFollowing ? 1 : -1;
      });

      widget.onFollowChanged?.call(_isFollowing);
      HapticFeedback.lightImpact();
    } catch (e) {
      debugPrint('Error toggling track: $e');
      if (!mounted) return;
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
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final username = widget.user['username'] ?? 'Unknown';
    final displayName = widget.user['display_name'] ?? username;
    final bio = widget.user['bio'] ?? '';
    final avatarUrl = widget.user['avatar_url'];
    final isVerified = widget.user['is_verified'] ?? false;
    final followingCount = widget.user['following_count'] ?? 0;
    final postsCount = widget.user['posts_count'] ?? 0;
    final isCurrentUser = widget.user['id'] == widget.currentUser?['id'];

    return GestureDetector(
      onTapDown: (_) => _animationController.forward(),
      onTapUp: (_) => _animationController.reverse(),
      onTapCancel: () => _animationController.reverse(),
      onTap: widget.onTap,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              _buildAvatar(avatarUrl, username),
              const SizedBox(width: 12),
              Expanded(
                child: _buildUserInfo(
                  username,
                  displayName,
                  bio,
                  isVerified,
                  followingCount,
                  postsCount,
                ),
              ),
              if (widget.showFollowButton && !isCurrentUser)
                _buildFollowButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar(String? avatarUrl, String username) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.border, width: 2),
      ),
      child: ClipOval(
        child: avatarUrl != null
            ? Image.network(
                avatarUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return _buildDefaultAvatar(username);
                },
              )
            : _buildDefaultAvatar(username),
      ),
    );
  }

  Widget _buildDefaultAvatar(String username) {
    return Container(
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          username[0].toUpperCase(),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildUserInfo(
    String username,
    String displayName,
    String bio,
    bool isVerified,
    int followingCount,
    int postsCount,
  ) {
    final lowerUsername = username.toLowerCase();
    final bool shouldShowVerified =
        isVerified || lowerUsername == 'equal' || lowerUsername == 'vigny';
    final Color verifiedColor = lowerUsername == 'vigny'
        ? Colors.blue
        : AppColors.gold;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Display name and verification
        Row(
          children: [
            Expanded(
              child: Text(
                displayName,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (shouldShowVerified) ...[
              const SizedBox(width: 4),
              Icon(Icons.verified, size: 16, color: verifiedColor),
            ],
          ],
        ),
        const SizedBox(height: 2),
        // Username
        Text(
          '@$username',
          style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        // Bio
        if (widget.showBio && bio.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            bio,
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textPrimary,
              height: 1.3,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        const SizedBox(height: 8),
        // Stats
        Row(
          children: [
            _buildStat(LocalizationService.t('posts'), postsCount),
            // Followers/Following counts hidden for privacy on public cards
          ],
        ),
      ],
    );
  }

  Widget _buildStat(String label, int count) {
    return Row(
      children: [
        Text(
          _formatCount(count),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(width: 2),
        Text(
          label,
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  Widget _buildFollowButton() {
    return SizedBox(
      width: 96,
      height: 36,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _toggleFollow,
        style: ElevatedButton.styleFrom(
          backgroundColor: _isFollowing ? AppColors.surface : AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: _isFollowing
                ? BorderSide(color: AppColors.border, width: 1)
                : BorderSide.none,
          ),
          padding: EdgeInsets.zero,
        ),
        child: _isLoading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Text(
                _isFollowing
                    ? LocalizationService.t('following')
                    : (widget.showTrackBackLabel
                          ? LocalizationService.t('follow_back')
                          : LocalizationService.t('follow')),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
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
}
