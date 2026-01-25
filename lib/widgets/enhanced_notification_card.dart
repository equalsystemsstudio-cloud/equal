import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/notification_model.dart';
import '../config/app_colors.dart';
import '../services/supabase_service.dart';
import '../services/localization_service.dart';

class EnhancedNotificationCard extends StatefulWidget {
  final NotificationModel notification;
  final VoidCallback? onTap;
  final VoidCallback? onMarkAsRead;
  final VoidCallback? onDelete;
  final bool
  showActionButton; // Control visibility of action button (e.g., 'Track Back')

  const EnhancedNotificationCard({
    super.key,
    required this.notification,
    this.onTap,
    this.onMarkAsRead,
    this.onDelete,
    this.showActionButton = true,
  });

  @override
  State<EnhancedNotificationCard> createState() =>
      _EnhancedNotificationCardState();
}

class _EnhancedNotificationCardState extends State<EnhancedNotificationCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  // ignore: unused_field
  bool _isPressed = false;
  String? _actorAvatarUrl;
  String? _actorDisplayName;
  String? _actorUsername;

  String _mapTitle(String original, String type) {
    switch (type) {
      case 'comment':
        return '💬 ${LocalizationService.t('new_comment_title')}';
      case 'message':
        return '✉️ ${LocalizationService.t('new_message_title')}';
      case 'like':
        return '❤️ ${LocalizationService.t('new_like_title')}';
      default:
        // Fallback: map known English originals to localized keys
        if (original.trim().toLowerCase() == 'new like') {
          return '❤️ ${LocalizationService.t('new_like_title')}';
        }
        if (original.trim().toLowerCase() == 'new comment') {
          return '💬 ${LocalizationService.t('new_comment_title')}';
        }
        if (original.trim().toLowerCase() == 'new message') {
          return '✉️ ${LocalizationService.t('new_message_title')}';
        }
        return original;
    }
  }

  String _mapMessage(String original) {
    var msg = original;
    // Replace known English phrases with localized variants while keeping actor name intact
    msg = msg.replaceAll(
      'commented on your post',
      LocalizationService.t('commented_on_your_post'),
    );
    msg = msg.replaceAll(
      'sent you a message',
      LocalizationService.t('sent_you_a_message'),
    );
    msg = msg.replaceAll(
      'sent a voice message',
      LocalizationService.t('sent_voice_message'),
    );
    msg = msg.replaceAll('sent a photo', LocalizationService.t('sent_a_photo'));
    msg = msg.replaceAll(
      'liked your post',
      LocalizationService.t('liked_your_post'),
    );
    // Additional fallback for capitalized title casing
    msg = msg.replaceAll(
      'Liked your post',
      LocalizationService.t('liked_your_post'),
    );
    return msg;
  }

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    _fadeAnimation = Tween<double>(begin: 1.0, end: 0.8).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    // Load actor profile for follow, like, and comment notifications when we have an actor user id
    final t = widget.notification.type;
    final hasActor = widget.notification.actionUserId != null;
    if (hasActor &&
        (t == 'follow' ||
            t == 'like' ||
            t == 'comment' ||
            t == 'message' ||
            t == 'live')) {
      _loadActorProfile();
    }
  }

  Future<void> _loadActorProfile() async {
    try {
      final userId = widget.notification.actionUserId;
      if (userId == null) return;
      final profile = await SupabaseService.getProfile(userId);
      if (!mounted) return;
      if (profile != null) {
        setState(() {
          _actorAvatarUrl = profile['avatar_url'] as String?;
          _actorDisplayName = profile['display_name'] as String?;
          _actorUsername = profile['username'] as String?;
        });
      }
    } catch (e) {
      debugPrint('Error loading actor profile: $e');
    }
  }

  Widget _buildActorAvatar() {
    final type = widget.notification.type;
    final color = _getNotificationColor();
    final initialSource = _actorDisplayName ?? _actorUsername ?? 'U';
    final initial = initialSource.isNotEmpty
        ? initialSource[0].toUpperCase()
        : 'U';

    // Show actor avatar for follow/like/comment when actor profile is available

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.border, width: 2),
          ),
          child: ClipOval(
            child: (_actorAvatarUrl != null && _actorAvatarUrl!.isNotEmpty)
                ? Image.network(
                    _actorAvatarUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        decoration: BoxDecoration(
                          gradient: AppColors.primaryGradient,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            initial,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      );
                    },
                  )
                : Container(
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        initial,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
          ),
        ),
        Positioned(
          bottom: -2,
          right: -2,
          child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: Icon(
              type == 'follow'
                  ? Icons.person_add
                  : type == 'like'
                  ? Icons.favorite
                  : type == 'live'
                  ? Icons.fiber_manual_record
                  : Icons.chat_bubble,
              size: 10,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  void _onTapDown(TapDownDetails details) {
    setState(() {
      _isPressed = true;
    });
    _animationController.forward();
    HapticFeedback.lightImpact();
  }

  void _onTapUp(TapUpDetails details) {
    setState(() {
      _isPressed = false;
    });
    _animationController.reverse();
  }

  void _onTapCancel() {
    setState(() {
      _isPressed = false;
    });
    _animationController.reverse();
  }

  Color _getNotificationColor() {
    switch (widget.notification.type) {
      case 'like':
        return const Color(0xFFFF3040); // TikTok red
      case 'comment':
        return const Color(0xFF25D366); // WhatsApp green
      case 'follow':
        return const Color(0xFF1DA1F2); // Twitter blue
      case 'mention':
        return const Color(0xFFFF6B35); // Orange
      case 'message':
        return const Color(0xFF8A2BE2); // Purple
      case 'live':
        return const Color(0xFFFF3040); // Red for live
      default:
        return AppColors.primary;
    }
  }

  Widget _buildNotificationIcon() {
    final color = _getNotificationColor();
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, color.withValues(alpha: 0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Text(
          widget.notification.icon,
          style: const TextStyle(fontSize: 20),
        ),
      ),
    );
  }

  Widget _buildActionButton() {
    if (!widget.showActionButton) {
      return const SizedBox.shrink();
    }
    if (widget.notification.type == 'follow') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          LocalizationService.t('follow_back'),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }
    // For likes and comments, show "View Post" button if we have a postId
    if (widget.notification.type == 'like' ||
        widget.notification.type == 'comment') {
      final dynamic rawPostId =
          widget.notification.data?['post_id'] ?? widget.notification.postId;
      final String? postId = rawPostId?.toString();
      if (postId == null || postId.isEmpty) {
        return const SizedBox.shrink();
      }
      return GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          // Navigate to the post detail screen
          Navigator.pushNamed(context, '/post_detail', arguments: postId);
          // Mark as read if needed
          if (!widget.notification.isRead && widget.onMarkAsRead != null) {
            widget.onMarkAsRead!();
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            LocalizationService.t('view_post'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }
    // For messages, show "Open Chat" if available
    if (widget.notification.type == 'message') {
      final String? conversationId = widget
          .notification
          .data?['conversation_id']
          ?.toString();
      if (conversationId == null || conversationId.isEmpty) {
        return const SizedBox.shrink();
      }
      return GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          // Delegate navigation to onTap handler to keep routing centralized
          if (widget.onTap != null) {
            widget.onTap!();
          }
          // Mark as read if needed
          if (!widget.notification.isRead && widget.onMarkAsRead != null) {
            widget.onMarkAsRead!();
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            LocalizationService.t('open_chat'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    // ... existing code ...
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Opacity(
            opacity: _fadeAnimation.value,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: GestureDetector(
                onTapDown: _onTapDown,
                onTapUp: _onTapUp,
                onTapCancel: _onTapCancel,
                onTap: () {
                  if (widget.onTap != null) {
                    widget.onTap!();
                  }
                  if (!widget.notification.isRead &&
                      widget.onMarkAsRead != null) {
                    widget.onMarkAsRead!();
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: widget.notification.isRead
                        ? AppColors.surface
                        : AppColors.surface.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: widget.notification.isRead
                          ? AppColors.border
                          : _getNotificationColor().withValues(alpha: 0.3),
                      width: widget.notification.isRead ? 1 : 2,
                    ),
                    boxShadow: widget.notification.isRead
                        ? null
                        : [
                            BoxShadow(
                              color: _getNotificationColor().withValues(
                                alpha: 0.1,
                              ),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                  ),
                  child: Row(
                    children: [
                      // Use avatar for follow/like/comment when we have actor, else fallback to icon
                      (widget.notification.actionUserId != null &&
                              (widget.notification.type == 'follow' ||
                                  widget.notification.type == 'like' ||
                                  widget.notification.type == 'comment' ||
                                  widget.notification.type == 'message' ||
                                  widget.notification.type == 'live'))
                          ? _buildActorAvatar()
                          : _buildNotificationIcon(),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    widget.notification.type == 'follow'
                                        ? (_actorDisplayName ??
                                              _actorUsername ??
                                              widget.notification.title)
                                        : _mapTitle(
                                            widget.notification.title,
                                            widget.notification.type,
                                          ),
                                    style: TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 16,
                                      fontWeight: widget.notification.isRead
                                          ? FontWeight.w500
                                          : FontWeight.w700,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (widget.notification.isRecent)
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: _getNotificationColor(),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                              ],
                            ),
                            if ((widget.notification.type == 'follow' ||
                                    widget.notification.type == 'like' ||
                                    widget.notification.type == 'comment' ||
                                    widget.notification.type == 'message') &&
                                _actorUsername != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                '@${_actorUsername!}',
                                style: TextStyle(
                                  color: AppColors.textSecondary.withValues(
                                    alpha: 0.8,
                                  ),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                            const SizedBox(height: 4),
                            Text(
                              _mapMessage(widget.notification.message),
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 14,
                                fontWeight: FontWeight.w400,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  widget.notification.timeAgo,
                                  style: TextStyle(
                                    color: AppColors.textSecondary.withValues(
                                      alpha: 0.7,
                                    ),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                                _buildActionButton(),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      // More options button
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          _showOptionsBottomSheet(context);
                        },
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.border,
                              width: 1,
                            ),
                          ),
                          child: Icon(
                            Icons.more_horiz,
                            color: AppColors.textSecondary,
                            size: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showOptionsBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
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
            if (!widget.notification.isRead)
              ListTile(
                leading: Icon(Icons.mark_email_read, color: AppColors.primary),
                title: Text(
                  LocalizationService.t('mark_as_read'),
                  style: TextStyle(color: AppColors.textPrimary),
                ),
                onTap: () {
                  Navigator.pop(context);
                  if (widget.onMarkAsRead != null) {
                    widget.onMarkAsRead!();
                  }
                },
              ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: Colors.red),
              title: Text(
                LocalizationService.t('delete_notification'),
                style: const TextStyle(color: Colors.red),
              ),
              onTap: () {
                Navigator.pop(context);
                if (widget.onDelete != null) {
                  widget.onDelete!();
                }
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }
}
