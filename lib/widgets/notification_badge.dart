import 'package:flutter/material.dart';
import '../config/app_colors.dart';

class NotificationBadge extends StatelessWidget {
  final Widget child;
  final int count;
  final bool showZero;
  final Color? badgeColor;
  final Color? textColor;
  final double? fontSize;
  final EdgeInsets? padding;
  final double? size;
  final Alignment alignment;
  final bool animate;

  const NotificationBadge({
    super.key,
    required this.child,
    required this.count,
    this.showZero = false,
    this.badgeColor,
    this.textColor,
    this.fontSize,
    this.padding,
    this.size,
    this.alignment = Alignment.topRight,
    this.animate = true,
  });

  @override
  Widget build(BuildContext context) {
    final shouldShow = count > 0 || (showZero && count == 0);
    
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        if (shouldShow)
          Positioned(
            top: alignment == Alignment.topRight || alignment == Alignment.topLeft ? -8 : null,
            bottom: alignment == Alignment.bottomRight || alignment == Alignment.bottomLeft ? -8 : null,
            right: alignment == Alignment.topRight || alignment == Alignment.bottomRight ? -8 : null,
            left: alignment == Alignment.topLeft || alignment == Alignment.bottomLeft ? -8 : null,
            child: animate
                ? AnimatedScale(
                    scale: shouldShow ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.elasticOut,
                    child: _buildBadge(),
                  )
                : _buildBadge(),
          ),
      ],
    );
  }

  Widget _buildBadge() {
    final displayText = count > 99 ? '99+' : count.toString();
    final badgeSize = size ?? (count > 99 ? 24.0 : 20.0);
    
    return Container(
      constraints: BoxConstraints(
        minWidth: badgeSize,
        minHeight: badgeSize,
      ),
      padding: padding ?? const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: badgeColor ?? AppColors.error,
        borderRadius: BorderRadius.circular(badgeSize / 2),
        border: Border.all(
          color: Colors.white,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Text(
          displayText,
          style: TextStyle(
            color: textColor ?? Colors.white,
            fontSize: fontSize ?? (count > 99 ? 10 : 12),
            fontWeight: FontWeight.bold,
            height: 1,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

// Specialized badge for TikTok-style notifications
class TikTokNotificationBadge extends StatelessWidget {
  final Widget child;
  final int count;
  final bool showZero;
  final bool animate;

  const TikTokNotificationBadge({
    super.key,
    required this.child,
    required this.count,
    this.showZero = false,
    this.animate = true,
  });

  @override
  Widget build(BuildContext context) {
    return NotificationBadge(
      count: count,
      showZero: showZero,
      animate: animate,
      badgeColor: const Color(0xFFFF3040), // TikTok red
      textColor: Colors.white,
      fontSize: 11,
      size: 18,
      child: child,
    );
  }
}

// Specialized badge for Facebook-style messages
class FacebookMessageBadge extends StatelessWidget {
  final Widget child;
  final int count;
  final bool showZero;
  final bool animate;

  const FacebookMessageBadge({
    super.key,
    required this.child,
    required this.count,
    this.showZero = false,
    this.animate = true,
  });

  @override
  Widget build(BuildContext context) {
    return NotificationBadge(
      count: count,
      showZero: showZero,
      animate: animate,
      badgeColor: const Color(0xFF1877F2), // Facebook blue
      textColor: Colors.white,
      fontSize: 11,
      size: 18,
      child: child,
    );
  }
}

// Pulsing badge for urgent notifications
class PulsingNotificationBadge extends StatefulWidget {
  final Widget child;
  final int count;
  final bool showZero;
  final Color? badgeColor;
  final bool enablePulsing;

  const PulsingNotificationBadge({
    super.key,
    required this.child,
    required this.count,
    this.showZero = false,
    this.badgeColor,
    this.enablePulsing = true,
  });

  @override
  State<PulsingNotificationBadge> createState() => _PulsingNotificationBadgeState();
}

class _PulsingNotificationBadgeState extends State<PulsingNotificationBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));

    if (widget.enablePulsing && widget.count > 0) {
      _animationController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(PulsingNotificationBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    if (widget.enablePulsing && widget.count > 0 && oldWidget.count == 0) {
      _animationController.repeat(reverse: true);
    } else if (widget.count == 0 && oldWidget.count > 0) {
      _animationController.stop();
      _animationController.reset();
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _scaleAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: widget.enablePulsing && widget.count > 0 ? _scaleAnimation.value : 1.0,
          child: NotificationBadge(
            count: widget.count,
            showZero: widget.showZero,
            badgeColor: widget.badgeColor ?? AppColors.error,
            animate: true,
            child: widget.child,
          ),
        );
      },
    );
  }
}

// Dot badge for simple indicators
class DotNotificationBadge extends StatelessWidget {
  final Widget child;
  final bool show;
  final Color? dotColor;
  final double? size;
  final Alignment alignment;

  const DotNotificationBadge({
    super.key,
    required this.child,
    required this.show,
    this.dotColor,
    this.size,
    this.alignment = Alignment.topRight,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        if (show)
          Positioned(
            top: alignment == Alignment.topRight || alignment == Alignment.topLeft ? -4 : null,
            bottom: alignment == Alignment.bottomRight || alignment == Alignment.bottomLeft ? -4 : null,
            right: alignment == Alignment.topRight || alignment == Alignment.bottomRight ? -4 : null,
            left: alignment == Alignment.topLeft || alignment == Alignment.bottomLeft ? -4 : null,
            child: AnimatedScale(
              scale: show ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.elasticOut,
              child: Container(
                width: size ?? 12,
                height: size ?? 12,
                decoration: BoxDecoration(
                  color: dotColor ?? AppColors.error,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white,
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 2,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
