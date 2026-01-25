import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/notification_model.dart';
import '../config/app_colors.dart';

class TikTokNotificationBanner extends StatefulWidget {
  final NotificationModel notification;
  final VoidCallback? onTap;
  final VoidCallback? onDismiss;

  const TikTokNotificationBanner({
    super.key,
    required this.notification,
    this.onTap,
    this.onDismiss,
  });

  @override
  State<TikTokNotificationBanner> createState() => _TikTokNotificationBannerState();
}

class _TikTokNotificationBannerState extends State<TikTokNotificationBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.elasticOut,
    ));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));

    _scaleAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.elasticOut,
    ));

    _animationController.forward();

    // Auto dismiss after 4 seconds
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) {
        _dismiss();
      }
    });

    // Haptic feedback
    HapticFeedback.lightImpact();
  }

  void _dismiss() {
    _animationController.reverse().then((_) {
      if (widget.onDismiss != null) {
        widget.onDismiss!();
      }
    });
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
      default:
        return AppColors.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return SlideTransition(
          position: _slideAnimation,
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Material(
                  elevation: 8,
                  borderRadius: BorderRadius.circular(16),
                  shadowColor: _getNotificationColor().withValues(alpha: 0.3),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: LinearGradient(
                        colors: [
                          _getNotificationColor(),
                          _getNotificationColor().withValues(alpha: 0.8),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.2),
                        width: 1,
                      ),
                    ),
                    child: InkWell(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        if (widget.onTap != null) {
                          widget.onTap!();
                        }
                        _dismiss();
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            // Icon with pulse animation
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.3),
                                  width: 2,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  widget.notification.icon,
                                  style: const TextStyle(
                                    fontSize: 20,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Content
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    widget.notification.title,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    widget.notification.message,
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.9),
                                      fontSize: 14,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    widget.notification.timeAgo,
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.7),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Dismiss button
                            GestureDetector(
                              onTap: () {
                                HapticFeedback.lightImpact();
                                _dismiss();
                              },
                              child: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.close,
                                  color: Colors.white.withValues(alpha: 0.8),
                                  size: 18,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }
}

// Overlay manager for showing notifications
class NotificationOverlayManager {
  static OverlayEntry? _currentOverlay;
  static final List<OverlayEntry> _overlayQueue = [];

  static void showNotification(
    BuildContext context,
    NotificationModel notification, {
    VoidCallback? onTap,
  }) {
    // Remove current overlay if exists
    _currentOverlay?.remove();
    _currentOverlay = null;

    // Create new overlay
    final overlay = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + 10,
        left: 0,
        right: 0,
        child: TikTokNotificationBanner(
          notification: notification,
          onTap: onTap,
          onDismiss: () {
            _currentOverlay?.remove();
            _currentOverlay = null;
            _showNextInQueue(context);
          },
        ),
      ),
    );

    // Add to overlay
    Overlay.of(context).insert(overlay);
    _currentOverlay = overlay;
  }

  static void _showNextInQueue(BuildContext context) {
    if (_overlayQueue.isNotEmpty) {
      final nextOverlay = _overlayQueue.removeAt(0);
      Overlay.of(context).insert(nextOverlay);
      _currentOverlay = nextOverlay;
    }
  }

  static void clearAll() {
    _currentOverlay?.remove();
    _currentOverlay = null;
    for (final overlay in _overlayQueue) {
      overlay.remove();
    }
    _overlayQueue.clear();
  }
}
