import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/post_model.dart';
import '../widgets/post_widget.dart';
import '../widgets/side_action_bar.dart';
import 'comments_screen.dart';
import '../services/posts_service.dart';
import '../services/analytics_service.dart';
import '../services/history_service.dart';

class PostDetailScreen extends StatefulWidget {
  final PostModel post;

  const PostDetailScreen({super.key, required this.post});

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  late PostModel _post;
  bool _isLiked = false;
  int _likeCount = 0;
  int _commentCount = 0;
  int _shareCount = 0;
  final PostsService _postsService = PostsService();

  @override
  void initState() {
    super.initState();
    _post = widget.post;
    _isLiked = _post.isLiked;
    _likeCount = _post.likes;
    _commentCount = _post.comments;
    _shareCount = _post.shares;
    // Log history for this post view
    try {
      HistoryService.addPostView(_post);
    } catch (_) {}
  }

  void _handleLike() async {
    final wasLiked = _isLiked;
    final previousLikeCount = _likeCount;

    setState(() {
      _isLiked = !_isLiked;
      _likeCount += _isLiked ? 1 : -1;

      // Update the post model
      _post = PostModel(
        id: _post.id,
        userId: _post.userId,
        username: _post.username,
        userAvatar: _post.userAvatar,
        isVerified: _post.isVerified,
        content: _post.content,
        mediaType: _post.mediaType,
        mediaUrl: _post.mediaUrl,
        location: _post.location,
        hashtags: _post.hashtags,
        likes: _likeCount,
        comments: _commentCount,
        shares: _shareCount,
        isLiked: _isLiked,
        timestamp: _post.timestamp,
      );
    });

    // Call actual like API (creates notifications when liking others' posts)
    try {
      await _postsService.toggleLike(_post.id);
      // Track analytics immediately, redundant to PostsService for faster UI reflection
      try {
        final analytics = AnalyticsService();
        final postType = _post.type; // getter string
        if (wasLiked) {
          await analytics.trackPostUnlike(_post.id, postType);
        } else {
          await analytics.trackPostLike(_post.id, postType);
        }
        await analytics.flushPendingEvents();
      } catch (e) {
        debugPrint('PostDetailScreen: like analytics tracking failed: $e');
      }
    } catch (e) {
      // Revert on error
      setState(() {
        _isLiked = wasLiked;
        _likeCount = previousLikeCount;
        _post = PostModel(
          id: _post.id,
          userId: _post.userId,
          username: _post.username,
          userAvatar: _post.userAvatar,
          isVerified: _post.isVerified,
          content: _post.content,
          mediaType: _post.mediaType,
          mediaUrl: _post.mediaUrl,
          location: _post.location,
          hashtags: _post.hashtags,
          likes: _likeCount,
          comments: _commentCount,
          shares: _shareCount,
          isLiked: _isLiked,
          timestamp: _post.timestamp,
        );
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to ${wasLiked ? 'unlike' : 'like'} post'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            duration: const Duration(milliseconds: 1500),
          ),
        );
      }
    }
  }

  void _handleComment() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            CommentsScreen(postId: _post.id, postAuthorId: _post.userId),
      ),
    ).then((result) {
      // Update comment count if comments were added/removed
      if (result != null && result is int) {
        setState(() {
          _commentCount = result;
          _post = PostModel(
            id: _post.id,
            userId: _post.userId,
            username: _post.username,
            userAvatar: _post.userAvatar,
            isVerified: _post.isVerified,
            content: _post.content,
            mediaType: _post.mediaType,
            mediaUrl: _post.mediaUrl,
            location: _post.location,
            hashtags: _post.hashtags,
            likes: _likeCount,
            comments: _commentCount,
            shares: _shareCount,
            isLiked: _isLiked,
            timestamp: _post.timestamp,
          );
        });
      }
    });
  }

  void _handleShare() async {
    try {
      // Create shareable content
      String shareText = '';
      if (_post.content.isNotEmpty) {
        shareText = _post.content.length > 100
            ? '${_post.content.substring(0, 100)}...'
            : _post.content;
      }

      final shareContent = shareText.isNotEmpty
          ? 'Check out this post by @${_post.username}: "$shareText"\n\nhttps://play.google.com/store/apps/details?id=com.equal.app.equal\n\nDownload Equal app to see more amazing content!'
          : 'Check out this amazing post by @${_post.username} on Equal!\n\nhttps://play.google.com/store/apps/details?id=com.equal.app.equal\n\nDownload Equal app to see more amazing content!';

      final messenger = ScaffoldMessenger.of(context);

      // Share using native share dialog
      await Share.share(
        shareContent,
        subject: 'Amazing post on Equal by @${_post.username}',
      );

      if (!mounted) return;

      // Update share count locally and in UI
      setState(() {
        _shareCount += 1;
        _post = PostModel(
          id: _post.id,
          userId: _post.userId,
          username: _post.username,
          userAvatar: _post.userAvatar,
          isVerified: _post.isVerified,
          content: _post.content,
          mediaType: _post.mediaType,
          mediaUrl: _post.mediaUrl,
          location: _post.location,
          hashtags: _post.hashtags,
          likes: _likeCount,
          comments: _commentCount,
          shares: _shareCount,
          isLiked: _isLiked,
          timestamp: _post.timestamp,
        );
      });

      // Show success message
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Post shared successfully!',
            style: GoogleFonts.poppins(),
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          duration: const Duration(milliseconds: 1500),
        ),
      );
    } catch (e) {
      debugPrint(('Error sharing post: $e').toString());
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Failed to share post. Please try again.',
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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          // Main post content
          PostWidget(
            post: _post,
            isActive: true, // Always active in detail view
          ),

          // Back button
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 16,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withValues(alpha: 0.5),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.2),
                    width: 1,
                  ),
                ),
                child: const Icon(
                  Icons.arrow_back,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          ),

          // Side action bar
          Positioned(
            right: 16,
            bottom: 100,
            child: SideActionBar(
              post: _post,
              onLike: _handleLike,
              onComment: _handleComment,
              onShare: _handleShare,
            ),
          ),
        ],
      ),
    );
  }
}
