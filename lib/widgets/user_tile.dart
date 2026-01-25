import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/social_service.dart';
import '../services/localization_service.dart';
import '../config/app_colors.dart';
import '../config/supabase_config.dart';

class UserTile extends StatefulWidget {
  final UserModel user;
  final VoidCallback? onTap;
  final bool showFollowButton;
  final EdgeInsets? padding;

  const UserTile({
    super.key,
    required this.user,
    this.onTap,
    this.showFollowButton = true,
    this.padding,
  });

  @override
  State<UserTile> createState() => _UserTileState();
}

class _UserTileState extends State<UserTile> {
  final AuthService _authService = AuthService();
  final SocialService _socialService = SocialService();

  bool _isFollowing = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _isFollowing = widget.user.isFollowing;
  }

  Future<void> _toggleFollow() async {
    if (_isLoading || !_authService.isAuthenticated) return;

    setState(() {
      _isLoading = true;
    });

    try {
      if (_isFollowing) {
        await _socialService.unfollowUser(widget.user.id);
      } else {
        await _socialService.followUser(widget.user.id);
      }

      setState(() {
        _isFollowing = !_isFollowing;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isFollowing
                  ? LocalizationService.t('failed_unfollow_user')
                  : LocalizationService.t('failed_follow_user'),
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
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCurrentUser = _authService.currentUser?.id == widget.user.id;
    final lowerUsername = widget.user.username.toLowerCase();
    final bool showVerified =
        widget.user.isVerified ||
        lowerUsername == 'equal' ||
        lowerUsername == 'vigny';
    final Color verifiedColor = lowerUsername == 'vigny'
        ? Colors.blue
        : AppColors.gold;

    return InkWell(
      onTap: widget.onTap,
      child: Container(
        padding:
            widget.padding ??
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.grey[800]!, width: 1),
              ),
              child: ClipOval(
                child: widget.user.avatarUrl.isNotEmpty
                    ? Image.network(
                        widget.user.avatarUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            color: Colors.grey[800],
                            child: Icon(
                              Icons.person,
                              color: Colors.grey[400],
                              size: 24,
                            ),
                          );
                        },
                      )
                    : Container(
                        color: Colors.grey[800],
                        child: Icon(
                          Icons.person,
                          color: Colors.grey[400],
                          size: 24,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 12),

            // User info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          widget.user.username,
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (showVerified) ...[
                        const SizedBox(width: 4),
                        Icon(Icons.verified, color: verifiedColor, size: 16),
                      ],
                    ],
                  ),
                  if (widget.user.displayName.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      widget.user.displayName,
                      style: GoogleFonts.poppins(
                        color: Colors.grey[400],
                        fontSize: 14,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (widget.user.bio.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      widget.user.bio,
                      style: GoogleFonts.poppins(
                        color: Colors.grey[300],
                        fontSize: 12,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      // Hide public trackers count for privacy
                      Text(
                        '${widget.user.postsCount} ${LocalizationService.t('posts')}',
                        style: GoogleFonts.poppins(
                          color: Colors.grey[500],
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Follow button
            if (widget.showFollowButton && !isCurrentUser) ...[
              const SizedBox(width: 12),
              SizedBox(
                width: 80,
                height: 32,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _toggleFollow,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isFollowing
                        ? Colors.grey[800]
                        : Colors.blue,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: _isFollowing
                          ? BorderSide(color: Colors.grey[600]!, width: 1)
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
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : Text(
                          _isFollowing
                              ? LocalizationService.t('following')
                              : LocalizationService.t('follow'),
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
