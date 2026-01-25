import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import '../config/app_colors.dart';

class PostCard extends StatelessWidget {
  final Map<String, dynamic> post;
  final VoidCallback? onTap;
  final VoidCallback? onLike;
  final VoidCallback? onComment;
  final VoidCallback? onShare;
  final bool showActions;
  final bool playPreview;
  final bool muted;

  const PostCard({
    super.key,
    required this.post,
    this.onTap,
    this.onLike,
    this.onComment,
    this.onShare,
    this.showActions = true,
    this.playPreview = false,
    this.muted = true,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // User info
              Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundImage: post['user_avatar'] != null
                        ? NetworkImage(post['user_avatar'])
                        : null,
                    backgroundColor: AppColors.primary,
                    child: post['user_avatar'] == null
                        ? Text(
                            post['username']?.substring(0, 1).toUpperCase() ?? 'U',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          post['username'] ?? 'Unknown User',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          _formatTimestamp(post['created_at']),
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              
              // Content
              if (post['content'] != null && post['content'].isNotEmpty)
                Text(
                  post['content'],
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
              
              // Media preview
              if (post['media_url'] != null)
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  height: 200,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: AppColors.surface,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: _buildMediaPreview(post['media_url'], post['type'], playPreview, muted, post['content']),
                  ),
                ),
              
              // Actions
              if (showActions)
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  child: Row(
                    children: [
                      _ActionButton(
                        icon: post['is_liked'] == true ? Icons.favorite : Icons.favorite_border,
                        label: post['likes_count']?.toString() ?? '0',
                        onTap: onLike,
                        color: post['is_liked'] == true ? Colors.red : AppColors.textSecondary,
                      ),
                      const SizedBox(width: 16),
                      _ActionButton(
                        icon: Icons.comment_outlined,
                        label: post['comments_count']?.toString() ?? '0',
                        onTap: onComment,
                      ),
                      const SizedBox(width: 16),
                      _ActionButton(
                        icon: Icons.share_outlined,
                        label: 'Share',
                        onTap: onShare ?? () => Share.share(_buildShareText()),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _buildShareText() {
    final username = post['username'] ?? 'someone';
    final content = (post['content'] ?? '').toString();
    final link = post['media_url'] ?? '';
    final parts = [
      'Check out this post by $username!',
      if (content.isNotEmpty) content,
      if (link.isNotEmpty) link,
    ];
    return parts.join('\n');
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return 'Just now';
    
    try {
      DateTime dateTime;
      if (timestamp is String) {
        dateTime = DateTime.parse(timestamp);
      } else if (timestamp is DateTime) {
        dateTime = timestamp;
      } else {
        return 'Just now';
      }
      
      final now = DateTime.now();
      final difference = now.difference(dateTime);
      
      if (difference.inMinutes < 1) {
        return 'Just now';
      } else if (difference.inHours < 1) {
        return '${difference.inMinutes}m ago';
      } else if (difference.inDays < 1) {
        return '${difference.inHours}h ago';
      } else if (difference.inDays < 7) {
        return '${difference.inDays}d ago';
      } else {
        return '${(difference.inDays / 7).floor()}w ago';
      }
    } catch (e) {
      return 'Just now';
    }
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? color;

  const _ActionButton({
    required this.icon,
    required this.label,
    this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: color ?? AppColors.textSecondary,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}


  Widget _buildMediaPreview(String url, dynamic type, bool playPreview, bool muted, String? caption) {
    final mediaType = (type is String) ? type.toLowerCase() : null;
    final lowerUrl = url.toLowerCase();
    final isVideo = mediaType == 'video' || lowerUrl.endsWith('.mp4') || lowerUrl.endsWith('.webm') || lowerUrl.endsWith('.mov') || lowerUrl.endsWith('.m4v');
    if (mediaType == 'audio' || lowerUrl.endsWith('.m4a') || lowerUrl.endsWith('.aac') || lowerUrl.endsWith('.mp3')) {
      return _buildAudioPreview(url, caption);
    }
    if (isVideo) {
      return _InlineVideoPreview(url: url, play: playPreview, muted: muted);
    }
    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        return Container(
          color: AppColors.surface,
          child: Icon(
            Icons.image_not_supported,
            color: AppColors.textSecondary,
            size: 48,
          ),
        );
      },
    );
  }

  Widget _buildAudioPreview(String url, String? caption) {
    final String caption0 = (caption ?? '').trim();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.play_arrow, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Audio', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                if (caption0.isNotEmpty) ...[
                  Text(
                    caption0,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 4),
                ],
                const Text('Tap to open', style: TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

class _InlineVideoPreview extends StatefulWidget {
  final String url;
  final bool play;
  final bool muted;

  const _InlineVideoPreview({
    required this.url,
    required this.play,
    required this.muted,
  });

  @override
  State<_InlineVideoPreview> createState() => _InlineVideoPreviewState();
}

class _InlineVideoPreviewState extends State<_InlineVideoPreview> {
  VideoPlayerController? _controller;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    if (widget.play) {
      _initializeAndPlay();
    }
  }

  @override
  void didUpdateWidget(covariant _InlineVideoPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.url != oldWidget.url) {
      _disposeController();
      if (widget.play) {
        _initializeAndPlay();
      } else {
        setState(() {
          _initialized = false;
        });
      }
      return;
    }

    if (widget.play && !oldWidget.play) {
      _initializeAndPlay();
    } else if (!widget.play && oldWidget.play) {
      _pauseAndDispose();
    } else if (_controller != null && _initialized) {
      // Update mute state if changed
      final targetVolume = widget.muted ? 0.0 : 1.0;
      if ((_controller!.value.volume - targetVolume).abs() > 0.01) {
        _controller!.setVolume(targetVolume);
      }
    }
  }

  Future<void> _initializeAndPlay() async {
    try {
      final url = widget.url;
      final controller = VideoPlayerController.networkUrl(Uri.parse(url));
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(widget.muted ? 0.0 : 1.0);
      await controller.play();
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _initialized = true;
      });
    } catch (e) {
      // Ignore preview initialization errors
      setState(() {
        _initialized = false;
      });
    }
  }

  void _pauseAndDispose() {
    if (_controller != null) {
      _controller!.pause();
    }
    _disposeController();
  }

  void _disposeController() {
    _controller?.dispose();
    _controller = null;
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null || !_initialized) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: Icon(Icons.play_circle, color: Colors.white70, size: 36),
        ),
      );
    }

    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: _controller!.value.size.width,
        height: _controller!.value.size.height,
        child: VideoPlayer(_controller!),
      ),
    );
  }
}
