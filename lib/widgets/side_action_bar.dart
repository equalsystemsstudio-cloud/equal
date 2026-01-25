import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/post_model.dart';
// Removed: import '../screens/status/status_create_screen.dart';
import '../screens/status/status_home_screen.dart';
import '../services/localization_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/status_service.dart';
import '../models/status_model.dart';

class SideActionBar extends StatefulWidget {
  final PostModel? post;
  final VoidCallback? onLike;
  final VoidCallback? onComment;
  final VoidCallback? onShare;
  final VoidCallback? onDelete;
  final VoidCallback? onDuet;
  final VoidCallback? onOptimize;

  const SideActionBar({
    super.key,
    this.post,
    this.onLike,
    this.onComment,
    this.onShare,
    this.onDelete,
    this.onDuet,
    this.onOptimize,
  });

  @override
  State<SideActionBar> createState() => _SideActionBarState();
}

class _SideActionBarState extends State<SideActionBar>
    with TickerProviderStateMixin {
  late AnimationController _likeController;
  late AnimationController _pulseController;
  late Animation<double> _likeScale;
  late Animation<double> _pulseScale;
  late AnimationController _rotateController;
  late Animation<double> _rotation;

  final StatusService _statusService = StatusService.of();
  String? _statusAvatarUrl;
  bool _authorHasUnseenStatuses = false;
  String? _lastOwnerId; // track owner id to refresh on change

  @override
  void initState() {
    super.initState();
    _likeController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _likeScale = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(parent: _likeController, curve: Curves.elasticOut),
    );

    _pulseScale = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _pulseController.repeat(reverse: true);
    
    // Rotation for bottom user profile avatar
    _rotateController = AnimationController(
      duration: const Duration(seconds: 6),
      vsync: this,
    )..repeat();
    _rotation = Tween<double>(begin: 0.0, end: 2 * math.pi).animate(
      CurvedAnimation(parent: _rotateController, curve: Curves.linear),
    );

    _lastOwnerId = widget.post?.userId;
    _loadAuthorStatusAvatarAndUnseen();
  }

  @override
  void didUpdateWidget(covariant SideActionBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final currentOwner = widget.post?.userId;
    if (currentOwner != _lastOwnerId) {
      _lastOwnerId = currentOwner;
      // Reset and reload avatar/unseen state when owner changes
      if (mounted) {
        setState(() {
          _statusAvatarUrl = null;
          _authorHasUnseenStatuses = false;
        });
      }
      _loadAuthorStatusAvatarAndUnseen();
    }
  }

  @override
  void dispose() {
    _likeController.dispose();
    _pulseController.dispose();
    _rotateController.dispose();
    super.dispose();
  }

  Future<void> _loadAuthorStatusAvatarAndUnseen() async {
    try {
      final ownerId = widget.post?.userId ?? '';
      if (ownerId.isEmpty) return;
      final viewerId = Supabase.instance.client.auth.currentUser?.id;
      bool hasUnseen = false;
      if (viewerId != null && viewerId.isNotEmpty && viewerId != ownerId) {
        hasUnseen = await _statusService.hasUnseenStatusesForUser(
          ownerUserId: ownerId,
          viewerUserId: viewerId,
        );
      }

      final statuses = await _statusService.fetchUserStatuses(ownerId);
      String? latestPhotoUrl;
      for (final s in statuses) {
        if (s.type == StatusType.image && (s.mediaUrl?.isNotEmpty ?? false)) {
          latestPhotoUrl = s.mediaUrl;
          break; // list is ordered by created_at desc
        } else if (s.type == StatusType.video && (s.thumbnailUrl?.isNotEmpty ?? false)) {
          latestPhotoUrl = s.thumbnailUrl;
          break; // list is ordered by created_at desc
        }
      }

      if (!mounted) return;
      setState(() {
        _statusAvatarUrl = latestPhotoUrl ?? widget.post?.userAvatar;
        _authorHasUnseenStatuses = hasUnseen;
      });
    } catch (_) {}
  }

  void _handleLike() {
    if (widget.onLike != null) {
      widget.onLike!();
      _likeController.forward().then((_) {
        _likeController.reverse();
      });
    }
  }

  void _openStatuses() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const StatusHomeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.post == null) {
      return const SizedBox.shrink();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        

        // Like button
        _buildActionButton(
          icon: widget.post!.isLiked ? Icons.favorite : Icons.favorite_border,
          count: widget.post!.formattedLikes,
          color: widget.post!.isLiked ? Colors.red : Colors.white,
          onTap: _handleLike,
          isLiked: widget.post!.isLiked,
        ),

        const SizedBox(height: 16),

        // Comment button
        _buildActionButton(
          icon: Icons.chat_bubble_outline,
          count: widget.post!.formattedComments,
          color: Colors.white,
          onTap: widget.onComment,
        ),

        const SizedBox(height: 16),

        // Share button
        _buildActionButton(
          icon: Icons.share,
          count: widget.post!.formattedShares,
          color: Colors.white,
          onTap: widget.onShare,
        ),

        const SizedBox(height: 16),

        // Duet button (for other users' posts)
        if (widget.onDuet != null)
          _buildActionButton(
            icon: Icons.video_call,
            count: LocalizationService.t('harmony'),
            color: Colors.white,
            onTap: widget.onDuet,
          ),

        if (widget.onDuet != null) const SizedBox(height: 16),

        // Optimize Video (for own video posts)
        if (widget.onOptimize != null)
          _buildActionButton(
            icon: Icons.video_settings,
            count: LocalizationService.t('optimize'),
            color: Colors.white,
            onTap: widget.onOptimize,
          ),

        if (widget.onOptimize != null) const SizedBox(height: 16),

        // Delete button (for own posts)
        if (widget.onDelete != null)
          _buildActionButton(
            icon: Icons.delete_outline,
            count: LocalizationService.t('delete'),
            color: Colors.red,
            onTap: widget.onDelete,
          ),

        if (widget.onDelete != null) const SizedBox(height: 16),

        // Statuses button moved below avatar

        // Profile picture (spinning) — moved below Status button
        AnimatedBuilder(
          animation: _pulseController,
          builder: (context, child) {
            final Gradient ringGradient = _authorHasUnseenStatuses
                ? const LinearGradient(
                    colors: [
                      Color(0xFF8AB4F8),
                      Color(0xFFFFFFFF),
                      Color(0xFFFFD700),
                    ],
                    stops: [0.0, 0.5, 1.0],
                  )
                : LinearGradient(
                    colors: [
                      Colors.grey.shade500,
                      Colors.grey.shade800,
                    ],
                  );
            return Column(
              children: [
                Transform.scale(
                  scale: _pulseScale.value,
                  child: GestureDetector(
                    onTap: _openStatuses,
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: ringGradient,
                        boxShadow: _authorHasUnseenStatuses
                            ? const [BoxShadow(color: Color(0x668AB4F8), blurRadius: 8, spreadRadius: 1)]
                            : null,
                      ),
                      child: Container(
                        margin: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black,
                        ),
                        child: CircleAvatar(
                          radius: 22,
                          backgroundImage: _statusAvatarUrl != null ? NetworkImage(_statusAvatarUrl!) : null,
                          child: _statusAvatarUrl == null
                              ? const Icon(
                                  Icons.person,
                                  color: Colors.white,
                                )
                              : null,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  LocalizationService.t('statuses'),
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    shadows: [
                      Shadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        offset: const Offset(0, 1),
                        blurRadius: 2,
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        
        // Bottom rotating avatar with user profile picture (temporarily hidden)
        const SizedBox.shrink(),

      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String count,
    required Color color,
    VoidCallback? onTap,
    bool isLiked = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          AnimatedBuilder(
            animation: isLiked ? _likeScale : const AlwaysStoppedAnimation(1.0),
            builder: (context, child) {
              return Transform.scale(
                scale: isLiked ? _likeScale.value : 1.0,
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withValues(alpha: 0.3),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.2),
                      width: 1,
                    ),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
              );
            },
          ),
          const SizedBox(height: 4),
          Text(
            count,
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white,
              shadows: [
                Shadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  offset: const Offset(0, 1),
                  blurRadius: 2,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

