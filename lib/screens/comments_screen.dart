import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:timeago/timeago.dart' as timeago;
// import 'package:record/record.dart'; // replaced by EnhancedMessagingService
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'dart:typed_data';
import 'dart:async';
import '../config/app_colors.dart';
import '../config/supabase_config.dart';
import '../services/social_service.dart';
import '../services/auth_service.dart';
import '../services/media_upload_service.dart';
import '../services/storage_service.dart';
import 'package:flutter/foundation.dart';
import '../services/analytics_service.dart';
import '../services/enhanced_messaging_service.dart';
import 'dart:convert';
import 'package:video_player/video_player.dart';
import '../utils/media_recorder_web.dart'
    if (dart.library.io) '../utils/media_recorder_stub.dart';
import '../services/localization_service.dart';

class CommentsScreen extends StatefulWidget {
  final String postId;
  final String postAuthorId;

  const CommentsScreen({
    super.key,
    required this.postId,
    required this.postAuthorId,
  });

  @override
  State<CommentsScreen> createState() => _CommentsScreenState();
}

class _CommentsScreenState extends State<CommentsScreen>
    with TickerProviderStateMixin {
  final _socialService = SocialService();
  final _authService = AuthService();
  final _commentController = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  // Audio recording variables
  final EnhancedMessagingService _messagingService = EnhancedMessagingService();
  bool _isRecording = false;
  bool _isPlayingVoiceNote = false;
  String? _recordedAudioPath;
  Duration _recordingDuration = Duration.zero;
  String? _playingAudioId;
  Duration _currentAudioDuration = Duration.zero; // ignore: unused_field
  Duration _currentAudioPosition = Duration.zero;
  final Map<String, Duration> _audioDurations = {};
  Timer? _recordingTimer;

  // Debug: track latest player state from EnhancedMessagingService
  String _lastPlayerState = 'unknown';

  List<Map<String, dynamic>> _comments = [];
  Map<String, dynamic>? _currentUser;
  bool _isLoading = false;
  bool _isSubmitting = false;
  String? _replyingToId;
  String? _replyingToUsername;
  int _commentCount = 0;
  bool _isVoiceMode = false;
  XFile? _attachedImage;
  Uint8List? _attachedImageBytes;

  // Web video recording state
  WebRecorderSession? _webRecorderSession; // active recorder session on web
  Uint8List? _recordedVideoBytes; // recorded video bytes (web)
  String?
  _recordedVideoMime; // mime of recorded video, e.g., video/webm or video/mp4
  VideoPlayerController?
  _inlineVideoController; // preview controller for recorded video
  // Mobile video recording path (Android/iOS)
  String? _recordedVideoPath;

  // Reply management
  final Set<String> _expandedComments = {};
  final Map<String, List<Map<String, dynamic>>> _replies = {};
  final Set<String> _loadingReplies = {};
  // Sub-replies (depth 3)
  final Map<String, List<Map<String, dynamic>>> _subReplies = {};
  final Set<String> _expandedSubReplies = {};
  final Set<String> _loadingSubReplies = {};

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
    _loadComments();
    _animationController.forward();

    // Remove old local audio player listeners
    // Attach audio player listeners for duration and position updates
    // _audioPlayer.onDurationChanged.listen(...)
    // _audioPlayer.onPositionChanged.listen(...)

    // Attach audio player listeners using shared messaging service
    _messagingService.durationStream.listen((duration) {
      if (mounted) {
        setState(() {
          _currentAudioDuration = duration;
          if (_playingAudioId != null) {
            _audioDurations[_playingAudioId!] = duration;
          }
        });
      }
    });

    _messagingService.positionStream.listen((position) {
      if (mounted) {
        setState(() {
          _currentAudioPosition = position;
        });
      }
    });

    _messagingService.completedStream.listen((_) {
      if (mounted) {
        setState(() {
          _isPlayingVoiceNote = false;
          _playingAudioId = null;
          _currentAudioPosition = Duration.zero;
        });
      }
    });

    // Debug: listen to player state changes
    _messagingService.playerStateStream.listen((state) {
      if (mounted) {
        final s = state.toString();
        setState(() {
          _lastPlayerState = s; // e.g., PlayerState.playing / paused / stopped
          _isPlayingVoiceNote = s.contains('playing');
        });
      }
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    _commentController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    // Ensure any ongoing recording is canceled when leaving the screen
    _messagingService.cancelVoiceRecording();
    _recordingTimer?.cancel();
    // Dispose inline video controller
    try {
      _inlineVideoController?.dispose();
    } catch (_) {}
    // Stop web recorder stream tracks if any
    try {
      _webRecorderSession?.stream?.getTracks().forEach((t) {
        t.stop();
      });
    } catch (_) {}
    _webRecorderSession = null;
    // Remove _audioPlayer.dispose();
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

  Future<void> _loadComments() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final comments = await _socialService.getComments(widget.postId);
      final totalCount = await _socialService.getTotalCommentCount(
        widget.postId,
      );
      setState(() {
        _comments = comments;
        _commentCount = totalCount;
      });
    } catch (e) {
      debugPrint(('Error loading comments: $e').toString());
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _submitComment() async {
    final text = _commentController.text.trim();
    if ((text.isEmpty &&
            _recordedAudioPath == null &&
            _attachedImage == null &&
            _recordedVideoBytes == null &&
            _recordedVideoPath == null) ||
        _isSubmitting)
      return;

    setState(() {
      _isSubmitting = true;
    });

    // Preserve current reply target before we clear it later
    final String? parentId = _replyingToId;

    try {
      String? audioUrl;
      String? mediaUrl;

      // Upload voice note if present
      if (_recordedAudioPath != null) {
        audioUrl = await _uploadVoiceNote(_recordedAudioPath!);
      }
      // Upload recorded video if present (web)
      if (_recordedVideoBytes != null) {
        final currentUserId = _currentUser?['id'] as String?;
        if (currentUserId == null) {
          throw Exception('User not authenticated');
        }
        final String videoFileName =
            'comment_${DateTime.now().millisecondsSinceEpoch}${_recordedVideoMime == 'video/webm' ? '.webm' : '.mp4'}';
        final urls = await StorageService().uploadVideo(
          videoFile: null,
          userId: currentUserId,
          videoBytes: _recordedVideoBytes!,
          videoFileName: videoFileName,
        );
        mediaUrl = urls['videoUrl'];
      }
      // Upload recorded video if present (mobile)
      if (_recordedVideoPath != null) {
        final currentUserId = _currentUser?['id'] as String?;
        if (currentUserId == null) {
          throw Exception('User not authenticated');
        }
        final urls = await StorageService().uploadVideo(
          videoFile: File(_recordedVideoPath!),
          userId: currentUserId,
        );
        mediaUrl = urls['videoUrl'];
      }

      // Upload attached image if present
      if (_attachedImage != null) {
        final currentUserId = _currentUser?['id'] as String?;
        if (currentUserId == null) {
          throw Exception('User not authenticated');
        }
        if (_attachedImageBytes != null) {
          // Upload using bytes (works for web/mobile)
          final bytes = _attachedImageBytes!;
          final fileName = _attachedImage!.name;
          mediaUrl = await StorageService().uploadImage(
            imageFile: null,
            userId: currentUserId,
            imageBytes: bytes,
            fileName: fileName,
          );
        } else {
          mediaUrl = await MediaUploadService().uploadFromXFile(
            file: _attachedImage!,
            bucket: SupabaseConfig.postImagesBucket,
            userId: currentUserId,
            postId: widget.postId,
          );
        }
      }

      await _socialService.addComment(
        widget.postId,
        text.isNotEmpty ? text : null,
        parentId: _replyingToId,
        audioUrl: audioUrl,
        mediaUrl: mediaUrl,
      );

      // Ensure analytics events are flushed so Analytics screen reflects new comment promptly
      try {
        final analytics = AnalyticsService();
        await analytics.flushPendingEvents();
      } catch (e) {
        debugPrint('CommentsScreen: flushPendingEvents failed: $e');
      }

      _commentController.clear();
      _clearReply();
      _deleteVoiceNote(); // Clear voice note after submission
      _clearAttachedImage(); // Clear image attachment after submission
      // Clear recorded video (web)
      try {
        _inlineVideoController?.dispose();
      } catch (_) {}
      _inlineVideoController = null;
      _recordedVideoBytes = null;
      _recordedVideoMime = null;
      _webRecorderSession = null;
      _recordedVideoPath = null;

      // Reload base comments
      await _loadComments();

      // If this was a reply, refresh the corresponding replies list
      if (parentId != null) {
        // If parentId belongs to a top-level comment, reload second-layer replies
        final isTopLevelParent = _comments.any((c) => c['id'] == parentId);
        if (isTopLevelParent) {
          await _loadReplies(parentId);
        } else {
          // Otherwise, parentId is a reply -> reload third-layer sub-replies
          await _loadSubReplies(parentId);
        }
      }

      // Scroll to bottom to show new comment
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }

      HapticFeedback.lightImpact();
    } catch (e) {
      debugPrint(('Error submitting comment: $e').toString());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const LocalizedText('Failed to post comment'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<String?> _uploadVoiceNote(String filePath) async {
    try {
      final currentUserId = _currentUser?['id'] as String?;
      if (currentUserId == null) {
        debugPrint('Upload voice note failed: user not authenticated');
        return null;
      }
      final file = File(filePath);
      if (!await file.exists()) return null;

      final url = await StorageService().uploadAudio(
        audioFile: file,
        userId: currentUserId,
      );
      return url;
    } catch (e) {
      debugPrint(('Error uploading voice note: $e').toString());
      return null;
    }
  }

  void _replyToComment(String commentId, String username) {
    setState(() {
      _replyingToId = commentId;
      _replyingToUsername = username;
    });
    _focusNode.requestFocus();
  }

  void _clearReply() {
    setState(() {
      _replyingToId = null;
      _replyingToUsername = null;
    });
  }

  Future<void> _loadReplies(String commentId) async {
    if (_loadingReplies.contains(commentId)) return;
    _loadingReplies.add(commentId);
    setState(() {});
    try {
      final replies = await _socialService.getReplies(commentId);
      _replies[commentId] = replies;
      _expandedComments.add(commentId);
    } catch (e) {
      debugPrint(('Error loading replies: $e').toString());
    } finally {
      _loadingReplies.remove(commentId);
      if (mounted) setState(() {});
    }
  }

  void _toggleReplies(String commentId) {
    if (_expandedComments.contains(commentId)) {
      setState(() {
        _expandedComments.remove(commentId);
      });
    } else {
      _loadReplies(commentId);
    }
  }

  // Load sub-replies for a reply (third layer)
  Future<void> _loadSubReplies(String replyId) async {
    if (_loadingSubReplies.contains(replyId)) return;
    _loadingSubReplies.add(replyId);
    setState(() {});
    try {
      final replies = await _socialService.getReplies(replyId);
      _subReplies[replyId] = replies;
      _expandedSubReplies.add(replyId);
    } catch (e) {
      debugPrint(('Error loading sub-replies: $e').toString());
    } finally {
      _loadingSubReplies.remove(replyId);
      if (mounted) setState(() {});
    }
  }

  void _toggleSubReplies(String replyId) {
    if (_expandedSubReplies.contains(replyId)) {
      _expandedSubReplies.remove(replyId);
      setState(() {});
      return;
    }
    _loadSubReplies(replyId);
  }

  // Debug: open a bottom sheet showing audio playback diagnostics and quick actions
  void _showAudioDebugPanel() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final currentId = _playingAudioId ?? 'none';
        final currentDuration = _playingAudioId != null
            ? (_audioDurations[_playingAudioId!] ?? _currentAudioDuration)
            : _currentAudioDuration;
        final firstVoiceUrl = _firstVoiceCommentUrl();
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Audio Debug',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const Spacer(),
                  Icon(Icons.bug_report, color: AppColors.primary),
                ],
              ),
              const SizedBox(height: 12),
              // Diagnostics
              _buildDebugRow('Player state', _lastPlayerState),
              _buildDebugRow('Is playing', _isPlayingVoiceNote.toString()),
              _buildDebugRow('Current audio id', currentId),
              _buildDebugRow(
                'Position',
                _formatDuration(_currentAudioPosition),
              ),
              _buildDebugRow('Duration', _formatDuration(currentDuration)),
              _buildDebugRow(
                'Service isRecording',
                _messagingService.isRecording.toString(),
              ),
              _buildDebugRow(
                'Service recordingDuration',
                _messagingService.recordingDuration.toString(),
              ),
              _buildDebugRow(
                'Local recorded path',
                _recordedAudioPath ?? 'none',
              ),
              const SizedBox(height: 16),
              // Quick actions
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  ElevatedButton.icon(
                    onPressed: () {
                      final url = firstVoiceUrl;
                      if (url != null) {
                        _playVoiceNote(url);
                        debugPrint(
                          'Debug: attempting to play first voice comment: $url',
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              LocalizationService.t('no_voice_comments_found'),
                            ),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.play_arrow),
                    label: const LocalizedText('Play first voice comment'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _recordedAudioPath != null
                        ? () {
                            _playVoiceNote(_recordedAudioPath!);
                            debugPrint(
                              'Debug: attempting to play local recorded file: $_recordedAudioPath',
                            );
                          }
                        : null,
                    icon: const Icon(Icons.mic),
                    label: LocalizedText('play_local_recording'),
                  ),
                  ElevatedButton.icon(
                    onPressed: () async {
                      await _messagingService.stopPlayingVoiceMessage();
                      setState(() {
                        _isPlayingVoiceNote = false;
                        _playingAudioId = null;
                        _currentAudioPosition = Duration.zero;
                      });
                      debugPrint('Debug: stopPlayingVoiceMessage invoked');
                    },
                    icon: const Icon(Icons.stop),
                    label: LocalizedText('stop_playback'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.error,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      debugPrint('—— Audio Debug —————————————————————');
                      debugPrint('Player state: $_lastPlayerState');
                      debugPrint('Is playing: $_isPlayingVoiceNote');
                      debugPrint('Current audio id: $currentId');
                      debugPrint(
                        'Position: ${_formatDuration(_currentAudioPosition)}',
                      );
                      debugPrint(
                        'Duration: ${_formatDuration(currentDuration)}',
                      );
                      debugPrint(
                        'Service isRecording: ${_messagingService.isRecording}',
                      );
                      debugPrint(
                        'Service recordingDuration: ${_messagingService.recordingDuration}',
                      );
                      debugPrint(
                        'Local recorded path: ${_recordedAudioPath ?? 'none'}',
                      );
                      debugPrint(
                        'First voice comment url: ${firstVoiceUrl ?? 'none'}',
                      );
                      debugPrint(
                        'Audio durations cache size: ${_audioDurations.length}',
                      );
                      debugPrint('—————————————————————————————————————');
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: LocalizedText(
                            'diagnostics_printed_to_console',
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.list),
                    label: const LocalizedText('print_diagnostics'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _likeComment(String commentId, bool isLiked) async {
    try {
      if (isLiked) {
        await _socialService.unlikeComment(commentId);
      } else {
        await _socialService.likeComment(commentId);
      }

      // Update local state
      setState(() {
        final commentIndex = _comments.indexWhere((c) => c['id'] == commentId);
        if (commentIndex != -1) {
          _comments[commentIndex]['is_liked'] = !isLiked;
          _comments[commentIndex]['likes_count'] =
              (_comments[commentIndex]['likes_count'] ?? 0) +
              (isLiked ? -1 : 1);
        }
      });

      HapticFeedback.lightImpact();
    } catch (e) {
      debugPrint(('Error liking comment: $e').toString());
    }
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
              Expanded(child: _buildCommentsList()),
              _buildCommentInput(),
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
            onPressed: () => Navigator.pop(context, _commentCount),
            icon: Icon(Icons.arrow_back, color: AppColors.textPrimary),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              LocalizationService.t('comments'),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              '$_commentCount',
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Debug button to inspect audio state and run quick actions
          IconButton(
            tooltip: 'Audio Debug',
            onPressed: _showAudioDebugPanel,
            icon: Icon(Icons.bug_report, color: AppColors.primary),
          ),
        ],
      ),
    );
  }

  Widget _buildDebugRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 170,
            child: Text(
              label,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(color: AppColors.textPrimary, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  String? _firstVoiceCommentUrl() {
    try {
      for (final c in _comments) {
        final url = c['audio_url'];
        if (url is String && url.isNotEmpty) return url;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Widget _buildCommentsList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_comments.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 64,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 16),
            Text(
              LocalizationService.t('no_comments_yet'),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              LocalizationService.t('be_the_first_to_comment'),
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: _comments.length,
      itemBuilder: (context, index) {
        final comment = _comments[index];
        return _buildCommentCard(comment);
      },
    );
  }

  Widget _buildCommentCard(Map<String, dynamic> comment) {
    final user = comment['user'] ?? {};
    final username = user['username'] ?? 'Unknown';
    final avatarUrl = user['avatar_url'];
    final text = comment['content'] ?? '';
    final createdAt = DateTime.parse(
      comment['created_at'] ?? DateTime.now().toIso8601String(),
    );
    final likeCount = comment['likes_count'] ?? 0;
    final isLikedRaw = comment['is_liked'];
    final isLiked = isLikedRaw is bool ? isLikedRaw : false;
    final isAuthor = user['id'] == _currentUser?['id'];
    final isPostAuthor = user['id'] == widget.postAuthorId;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: isPostAuthor ? AppColors.primary : AppColors.border,
                width: isPostAuthor ? 2 : 1,
              ),
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
          ),
          const SizedBox(width: 12),
          // Comment content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Username and badges
                Row(
                  children: [
                    Text(
                      username,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                        fontSize: 14,
                      ),
                    ),
                    if (isPostAuthor) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          LocalizationService.t('author'),
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                    const Spacer(),
                    Text(
                      timeago.format(createdAt),
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                // Comment content (text and/or voice note)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Text content
                    if (text.isNotEmpty)
                      Text(
                        text,
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          height: 1.4,
                        ),
                      ),
                    // Voice note
                    if (comment['audio_url'] != null)
                      Container(
                        margin: EdgeInsets.only(top: text.isNotEmpty ? 8 : 0),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            GestureDetector(
                              onTap: () => _playVoiceNote(comment['audio_url']),
                              child: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  _isPlayingVoiceNote &&
                                          _playingAudioId ==
                                              comment['audio_url']
                                      ? Icons.pause
                                      : Icons.play_arrow,
                                  color: Colors.white,
                                  size: 16,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              LocalizationService.t('voice_note'),
                              style: TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _isPlayingVoiceNote &&
                                      _playingAudioId == comment['audio_url']
                                  ? _formatDuration(_currentAudioPosition)
                                  : (_audioDurations[comment['audio_url']] !=
                                            null
                                        ? _formatDuration(
                                            _audioDurations[comment['audio_url']]!,
                                          )
                                        : '0:00'),
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (comment['media_url'] != null)
                      Container(
                        margin: EdgeInsets.only(
                          top: (text.isNotEmpty || comment['audio_url'] != null)
                              ? 6
                              : 0,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.border),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: AspectRatio(
                          aspectRatio: 4 / 3,
                          child: _isVideoUrl(comment['media_url'])
                              ? _InlineNetworkVideo(url: comment['media_url'])
                              : Image.network(
                                  comment['media_url'],
                                  fit: BoxFit.cover,
                                ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                // Actions
                Row(
                  children: [
                    // Like button
                    GestureDetector(
                      onTap: () => _likeComment(comment['id'], isLiked),
                      child: Row(
                        children: [
                          Icon(
                            isLiked ? Icons.favorite : Icons.favorite_border,
                            size: 16,
                            color: isLiked
                                ? AppColors.error
                                : AppColors.textSecondary,
                          ),
                          if (likeCount > 0) ...[
                            const SizedBox(width: 4),
                            Text(
                              likeCount.toString(),
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Reply button
                    GestureDetector(
                      onTap: () => _replyToComment(comment['id'], username),
                      child: Text(
                        LocalizationService.t('reply'),
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (isAuthor) ...[
                      const SizedBox(width: 16),
                      GestureDetector(
                        onTap: () => _showDeleteDialog(comment['id']),
                        child: Text(
                          LocalizationService.t('delete'),
                          style: TextStyle(
                            color: AppColors.error,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                // Replies section
                _buildRepliesSection(comment),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRepliesSection(Map<String, dynamic> comment) {
    final commentId = comment['id'];
    final replies = _replies[commentId] ?? [];
    final isExpanded = _expandedComments.contains(commentId);
    final isLoading = _loadingReplies.contains(commentId);
    // Determine if there are any replies for this comment
    final repliesCountRaw = comment['replies_count'];
    final repliesCount = repliesCountRaw is int ? repliesCountRaw : 0;
    final hasReplies = replies.isNotEmpty || repliesCount > 0;

    // Check if this comment might have replies by looking at database
    // For now, we'll show the button for all comments and let users discover
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // View replies button
        if (!isExpanded && !isLoading && hasReplies)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: GestureDetector(
              onTap: () => _toggleReplies(commentId),
              child: Text(
                LocalizationService.t('view_replies'),
                style: TextStyle(
                  color: AppColors.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        // Loading indicator
        if (isLoading)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
            ),
          ),
        // Replies list
        if (isExpanded) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: GestureDetector(
              onTap: () => _toggleReplies(commentId),
              child: Text(
                LocalizationService.t('hide_replies'),
                style: TextStyle(
                  color: AppColors.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          ...replies.map(
            (reply) => Padding(
              padding: const EdgeInsets.only(left: 24, top: 12),
              child: _buildReplyCard(reply),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildReplyCard(Map<String, dynamic> reply) {
    final user = reply['user'] ?? {};
    final username = user['username'] ?? 'Unknown';
    final avatarUrl = user['avatar_url'];
    final text = reply['content'] ?? '';
    final createdAt = DateTime.parse(
      reply['created_at'] ?? DateTime.now().toIso8601String(),
    );
    final likeCount = reply['likes_count'] ?? 0;
    final isLikedRaw = reply['is_liked'];
    final isLiked = isLikedRaw is bool ? isLikedRaw : false;
    final isAuthor = user['id'] == _currentUser?['id'];
    final isPostAuthor = user['id'] == widget.postAuthorId;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Avatar (smaller for replies)
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: isPostAuthor ? AppColors.primary : AppColors.border,
              width: isPostAuthor ? 2 : 1,
            ),
          ),
          child: ClipOval(
            child: avatarUrl != null
                ? Image.network(
                    avatarUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return _buildSmallDefaultAvatar(username);
                    },
                  )
                : _buildSmallDefaultAvatar(username),
          ),
        ),
        const SizedBox(width: 8),
        // Reply content
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Username and time
              Row(
                children: [
                  Text(
                    username,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                      fontSize: 12,
                    ),
                  ),
                  if (isPostAuthor) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        LocalizationService.t('author'),
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  Text(
                    timeago.format(createdAt),
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              // Reply text
              if (text.isNotEmpty)
                Text(
                  text,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
              // Voice note for replies
              if (reply['audio_url'] != null)
                Container(
                  margin: EdgeInsets.only(top: text.isNotEmpty ? 6 : 0),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: () => _playVoiceNote(reply['audio_url']),
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _isPlayingVoiceNote &&
                                    _playingAudioId == reply['audio_url']
                                ? Icons.pause
                                : Icons.play_arrow,
                            color: Colors.white,
                            size: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        LocalizationService.t('voice_note'),
                        style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                          fontSize: 10,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _isPlayingVoiceNote &&
                                _playingAudioId == reply['audio_url']
                            ? _formatDuration(_currentAudioPosition)
                            : (_audioDurations[reply['audio_url']] != null
                                  ? _formatDuration(
                                      _audioDurations[reply['audio_url']]!,
                                    )
                                  : '0:00'),
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              // Image attachment for replies
              if (reply['media_url'] != null)
                Container(
                  margin: EdgeInsets.only(top: text.isNotEmpty ? 6 : 0),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: AspectRatio(
                    aspectRatio: 4 / 3,
                    child: _isVideoUrl(reply['media_url'])
                        ? _InlineNetworkVideo(url: reply['media_url'])
                        : Image.network(reply['media_url'], fit: BoxFit.cover),
                  ),
                ),
              const SizedBox(height: 4),
              Row(
                children: [
                  GestureDetector(
                    onTap: () => _likeComment(reply['id'], isLiked),
                    child: Row(
                      children: [
                        Icon(
                          isLiked ? Icons.favorite : Icons.favorite_border,
                          size: 11,
                          color: isLiked
                              ? AppColors.error
                              : AppColors.textSecondary,
                        ),
                        if (likeCount > 0) ...[
                          const SizedBox(width: 2),
                          Text(
                            likeCount.toString(),
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 9,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (isAuthor) ...[
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: () => _showDeleteDialog(reply['id']),
                      child: Text(
                        LocalizationService.t('delete'),
                        style: TextStyle(
                          color: AppColors.error,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSmallDefaultAvatar(String username) {
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
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  // Third-layer reply card (no further nesting, no Reply action)
  Widget _buildSubReplyCard(Map<String, dynamic> reply) {
    final user = reply['user'] ?? {};
    final username = user['username'] ?? 'Unknown';
    final avatarUrl = user['avatar_url'];
    final text = reply['content'] ?? '';
    final createdAt = DateTime.parse(
      reply['created_at'] ?? DateTime.now().toIso8601String(),
    );
    final likeCount = reply['likes_count'] ?? 0;
    final isLikedRaw = reply['is_liked'];
    final isLiked = isLikedRaw is bool ? isLikedRaw : false;
    final isAuthor = user['id'] == _currentUser?['id'];
    final isPostAuthor = user['id'] == widget.postAuthorId;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: isPostAuthor ? AppColors.primary : AppColors.border,
              width: isPostAuthor ? 2 : 1,
            ),
          ),
          child: ClipOval(
            child: avatarUrl != null
                ? Image.network(
                    avatarUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return _buildSmallDefaultAvatar(username);
                    },
                  )
                : _buildSmallDefaultAvatar(username),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    username,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                      fontSize: 11,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    timeago.format(createdAt),
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 9,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              if (text.isNotEmpty)
                Text(
                  text,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 11,
                    height: 1.3,
                  ),
                ),
              if (reply['media_url'] != null)
                Container(
                  margin: EdgeInsets.only(top: text.isNotEmpty ? 6 : 0),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.3),
                    ),
                  ),
                  child: AspectRatio(
                    aspectRatio: 4 / 3,
                    child: _isVideoUrl(reply['media_url'])
                        ? _InlineNetworkVideo(url: reply['media_url'])
                        : Image.network(reply['media_url'], fit: BoxFit.cover),
                  ),
                ),
              const SizedBox(height: 4),
              Row(
                children: [
                  GestureDetector(
                    onTap: () => _likeComment(reply['id'], isLiked),
                    child: Row(
                      children: [
                        Icon(
                          isLiked ? Icons.favorite : Icons.favorite_border,
                          size: 11,
                          color: isLiked
                              ? AppColors.error
                              : AppColors.textSecondary,
                        ),
                        if (likeCount > 0) ...[
                          const SizedBox(width: 2),
                          Text(
                            likeCount.toString(),
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 9,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (isAuthor) ...[
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: () => _showDeleteDialog(reply['id']),
                      child: Text(
                        LocalizationService.t('delete'),
                        style: TextStyle(
                          color: AppColors.error,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
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
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildCommentInput() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: Column(
        children: [
          if (_replyingToUsername != null)
            Container(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(Icons.reply, size: 16, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Text(
                    '${LocalizationService.t('replying_to')} @$_replyingToUsername',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: _clearReply,
                    child: Icon(
                      Icons.close,
                      size: 16,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          // Voice note preview (if recorded)
          if (_isVoiceMode && _recordedAudioPath != null)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => _playVoiceNote(_recordedAudioPath),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _isPlayingVoiceNote &&
                                _playingAudioId == _recordedAudioPath
                            ? Icons.pause
                            : Icons.play_arrow,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          LocalizationService.t('voice_note'),
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          _formatDuration(_recordingDuration),
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: _deleteVoiceNote,
                    child: Icon(
                      Icons.delete_outline,
                      color: AppColors.error,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
          // Image preview (if attached)
          if (_attachedImageBytes != null || _attachedImage != null)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.3),
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  AspectRatio(
                    aspectRatio: 4 / 3,
                    child: _attachedImageBytes != null
                        ? Image.memory(_attachedImageBytes!, fit: BoxFit.cover)
                        : Image.file(
                            File(_attachedImage!.path),
                            fit: BoxFit.cover,
                          ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: GestureDetector(
                      onTap: _clearAttachedImage,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.4),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withOpacity(0.6),
                          ),
                        ),
                        child: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          // Video preview (if recorded on web or mobile)
          if (_recordedVideoBytes != null || _recordedVideoPath != null)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.3),
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Builder(
                      builder: (context) {
                        if (_inlineVideoController == null ||
                            !_inlineVideoController!.value.isInitialized) {
                          try {
                            if (_recordedVideoBytes != null) {
                              final mime = _recordedVideoMime ?? 'video/webm';
                              final dataUrl =
                                  'data:' +
                                  mime +
                                  ';base64,' +
                                  base64Encode(_recordedVideoBytes!);
                              _inlineVideoController =
                                  VideoPlayerController.networkUrl(
                                    Uri.parse(dataUrl),
                                  );
                            } else if (_recordedVideoPath != null) {
                              try {
                                final f = File(_recordedVideoPath!);
                                int tries = 0;
                                while (!f.existsSync() && tries < 5) {
                                  tries++;
                                }
                                _inlineVideoController =
                                    VideoPlayerController.file(f);
                              } catch (_) {
                                final uri = Uri.file(_recordedVideoPath!);
                                _inlineVideoController =
                                    VideoPlayerController.networkUrl(uri);
                              }
                            }
                            _inlineVideoController!.initialize().then((_) {
                              _inlineVideoController!.setLooping(true);
                              _inlineVideoController!.play();
                              if (mounted) setState(() {});
                            });
                          } catch (e) {
                            debugPrint(
                              ('Inline video init failed: ' + e.toString())
                                  .toString(),
                            );
                          }
                          return Center(
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  AppColors.primary,
                                ),
                              ),
                            ),
                          );
                        }
                        return VideoPlayer(_inlineVideoController!);
                      },
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: GestureDetector(
                      onTap: () {
                        try {
                          _inlineVideoController?.dispose();
                        } catch (_) {}
                        setState(() {
                          _inlineVideoController = null;
                          _recordedVideoBytes = null;
                          _recordedVideoMime = null;
                          _recordedVideoPath = null;
                        });
                      },
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.4),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withOpacity(0.6),
                          ),
                        ),
                        child: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              // User avatar
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.border, width: 1),
                ),
                child: ClipOval(
                  child: _currentUser?['avatar_url'] != null
                      ? Image.network(
                          _currentUser!['avatar_url'],
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return _buildDefaultAvatar(
                              _currentUser?['username'] ?? 'U',
                            );
                          },
                        )
                      : _buildDefaultAvatar(_currentUser?['username'] ?? 'U'),
                ),
              ),
              const SizedBox(width: 12),
              // Input area (text or voice recording)
              Expanded(
                child: _isVoiceMode
                    ? _buildVoiceRecordingInput()
                    : TextField(
                        controller: _commentController,
                        focusNode: _focusNode,
                        maxLines: null,
                        maxLength: 500,
                        decoration: InputDecoration(
                          hintText: _replyingToUsername != null
                              ? '${LocalizationService.t('replying_to')} @$_replyingToUsername...'
                              : LocalizationService.t('add_a_comment'),
                          hintStyle: TextStyle(color: AppColors.textSecondary),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: BorderSide(color: AppColors.border),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: BorderSide(
                              color: AppColors.primary,
                              width: 2,
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          counterText: '',
                        ),
                        style: TextStyle(color: AppColors.textPrimary),
                        onSubmitted: (_) => _submitComment(),
                      ),
              ),
              const SizedBox(width: 8),
              // Voice mode toggle button
              GestureDetector(
                onTap: _toggleVoiceMode,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _isVoiceMode
                        ? AppColors.primary.withValues(alpha: 0.2)
                        : AppColors.textSecondary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _isVoiceMode ? Icons.keyboard : Icons.mic,
                    color: _isVoiceMode
                        ? AppColors.primary
                        : AppColors.textSecondary,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Image attach button
              GestureDetector(
                onTap: _pickImage,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.textSecondary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.image,
                    color: AppColors.textSecondary,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Mobile: Record video button
              if (!kIsWeb)
                GestureDetector(
                  onTap: () async {
                    await _recordVideoMobile();
                  },
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.textSecondary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.videocam,
                      color: AppColors.textSecondary,
                      size: 20,
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              // Web: Record video button
              if (kIsWeb)
                GestureDetector(
                  onTap: () async {
                    // Toggle recording
                    if (_webRecorderSession == null) {
                      try {
                        final constraints = {
                          'video': {
                            'width': {'ideal': 1280},
                            'height': {'ideal': 720},
                            'frameRate': {'ideal': 30},
                          },
                          'audio': true,
                        };
                        final session = await webStartRecordingAsync(
                          null,
                          timesliceMs: 1000,
                          constraints: constraints,
                        );
                        setState(() {
                          _webRecorderSession = session;
                          _recordingDuration = Duration.zero;
                        });
                        _startRecordingTimer();
                      } catch (e) {
                        debugPrint(
                          ('Start web recording failed: ' + e.toString())
                              .toString(),
                        );
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              LocalizationService.t(
                                'unable_start_camera_mic_check_permissions',
                              ),
                            ),
                            backgroundColor: AppColors.error,
                          ),
                        );
                      }
                    } else {
                      try {
                        final bytes = await webStopRecording(
                          _webRecorderSession!,
                        );
                        final mime = _webRecorderSession?.mime ?? 'video/webm';
                        try {
                          _webRecorderSession?.stream?.getTracks().forEach((t) {
                            t.stop();
                          });
                        } catch (_) {}
                        setState(() {
                          _recordedVideoBytes = bytes;
                          _recordedVideoMime = mime;
                          _webRecorderSession = null;
                        });
                      } catch (e) {
                        debugPrint(
                          ('Stop web recording failed: ' + e.toString())
                              .toString(),
                        );
                        try {
                          _webRecorderSession?.stream?.getTracks().forEach((t) {
                            t.stop();
                          });
                        } catch (_) {}
                        setState(() {
                          _webRecorderSession = null;
                        });
                      }
                    }
                  },
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: (_webRecorderSession != null)
                          ? AppColors.primary.withValues(alpha: 0.2)
                          : AppColors.textSecondary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      (_webRecorderSession != null)
                          ? Icons.stop
                          : Icons.videocam,
                      color: (_webRecorderSession != null)
                          ? AppColors.primary
                          : AppColors.textSecondary,
                      size: 20,
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              // Send button
              GestureDetector(
                onTap: _submitComment,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient:
                        (_commentController.text.trim().isNotEmpty ||
                            _recordedAudioPath != null ||
                            _attachedImage != null ||
                            _recordedVideoBytes != null ||
                            _recordedVideoPath != null)
                        ? AppColors.primaryGradient
                        : null,
                    color:
                        (_commentController.text.trim().isEmpty &&
                            _recordedAudioPath == null &&
                            _attachedImage == null &&
                            _recordedVideoBytes == null &&
                            _recordedVideoPath == null)
                        ? AppColors.textSecondary.withValues(alpha: 0.3)
                        : null,
                    shape: BoxShape.circle,
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : const Icon(Icons.send, color: Colors.white, size: 20),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVoiceRecordingInput() {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: _isRecording
            ? AppColors.error.withValues(alpha: 0.1)
            : AppColors.textSecondary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _isRecording
              ? AppColors.error.withValues(alpha: 0.3)
              : AppColors.border,
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 16),
          if (_isRecording) ...[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: AppColors.error,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${LocalizationService.t('recording')}... ${_formatDuration(_recordingDuration)} / 00:15',
                style: TextStyle(
                  color: AppColors.error,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 120,
              child: LinearProgressIndicator(
                value: (_recordingDuration.inMilliseconds / (15 * 1000)).clamp(
                  0.0,
                  1.0,
                ),
                color: AppColors.error,
                backgroundColor: AppColors.error.withValues(alpha: 0.15),
              ),
            ),
          ] else ...[
            Icon(Icons.mic, color: AppColors.textSecondary, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _recordedAudioPath != null
                    ? LocalizationService.t('voice_note_ready')
                    : (kIsWeb
                          ? LocalizationService.t(
                              'voice_recording_not_supported_web',
                            )
                          : LocalizationService.t('tap_and_hold_to_record')),
                style: TextStyle(color: AppColors.textSecondary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
              ),
            ),
          ],
          const Spacer(),
          GestureDetector(
            onLongPressStart: (_) => _startRecording(),
            onLongPressEnd: (_) => _stopRecording(),
            onTapCancel: () => _stopRecording(),
            onTapDown: (_) {
              if (!kIsWeb) {
                _startRecording();
              } else {
                _showWebRecordingUnsupportedMessage();
              }
            },
            onTapUp: (_) {
              if (!kIsWeb) {
                _stopRecording();
              }
            },
            child: Container(
              width: 36,
              height: 36,
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                color: _isRecording ? AppColors.error : AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: Icon(
                _isRecording ? Icons.stop : Icons.mic,
                color: Colors.white,
                size: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showWebRecordingUnsupportedMessage() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          LocalizationService.t('voice_recording_not_supported_web'),
        ),
        backgroundColor: AppColors.warning,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _showDeleteDialog(String commentId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          LocalizationService.t('delete_comment'),
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          LocalizationService.t('delete_comment_confirmation'),
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              LocalizationService.t('cancel'),
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _deleteComment(commentId);
            },
            child: Text(
              LocalizationService.t('delete'),
              style: TextStyle(
                color: AppColors.error,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteComment(String commentId) async {
    try {
      await _socialService.deleteComment(commentId);
      await _loadComments();
      HapticFeedback.lightImpact();
    } catch (e) {
      debugPrint(('Error deleting comment: $e').toString());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(LocalizationService.t('failed_delete_comment')),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  // Voice recording methods
  Future<void> _toggleVoiceMode() async {
    setState(() {
      _isVoiceMode = !_isVoiceMode;
      if (!_isVoiceMode) {
        _recordedAudioPath = null;
        _recordingDuration = Duration.zero;
      }
    });
  }

  Future<void> _startRecording() async {
    if (kIsWeb) {
      _showWebRecordingUnsupportedMessage();
      return;
    }
    final success = await _messagingService.startVoiceRecording();
    if (!mounted) return;
    if (success) {
      setState(() {
        _isRecording = true;
        _recordedAudioPath = null;
        _recordingDuration = Duration.zero;
      });
      Future.delayed(const Duration(milliseconds: 200), () async {
        if (!_isRecording) return;
        setState(() {
          _recordingDuration = Duration(
            seconds: _messagingService.recordingDuration,
          );
        });
        if (_messagingService.recordingDuration >= 15) {
          await _stopRecording();
        } else {
          _startRecordingTimer();
        }
      });
      HapticFeedback.lightImpact();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Unable to start recording. Please check microphone permissions.',
          ),
          backgroundColor: AppColors.warning,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _stopRecording() async {
    try {
      final recordedPath = await _messagingService.stopVoiceRecording();
      setState(() {
        _isRecording = false;
        if (recordedPath != null && recordedPath.isNotEmpty) {
          _recordedAudioPath = recordedPath;
        }
      });
      HapticFeedback.lightImpact();
    } catch (e) {
      debugPrint(('Error stopping recording: $e').toString());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const LocalizedText('Failed to stop recording'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _playVoiceNote(String? audioPath) async {
    if (audioPath == null) return;

    try {
      if (_isPlayingVoiceNote && _playingAudioId == audioPath) {
        await _messagingService.stopPlayingVoiceMessage();
        setState(() {
          _isPlayingVoiceNote = false;
          _playingAudioId = null;
        });
      } else {
        await _messagingService.stopPlayingVoiceMessage();
        // Choose source type based on path (URL vs local file)
        if (audioPath.startsWith('http')) {
          await _messagingService.playVoiceMessage(audioPath);
        } else {
          await _messagingService.playLocalVoiceMessage(audioPath);
        }
        // Optional: keep any rate/volume logic centralized; messaging service defaults apply
        setState(() {
          _isPlayingVoiceNote = true;
          _playingAudioId = audioPath;
        });
      }
      HapticFeedback.lightImpact();
    } catch (e) {
      debugPrint(('Error playing voice note: $e').toString());
    }
  }

  void _deleteVoiceNote() {
    setState(() {
      _recordedAudioPath = null;
      _recordingDuration = Duration.zero;
    });
    HapticFeedback.lightImpact();
  }

  void _clearAttachedImage() {
    setState(() {
      _attachedImage = null;
      _attachedImageBytes = null;
    });
    HapticFeedback.lightImpact();
  }

  Future<void> _pickImage() async {
    try {
      // Web: use FilePicker directly
      if (kIsWeb) {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.image,
          withData: true,
        );
        if (result != null &&
            result.files.isNotEmpty &&
            result.files.single.bytes != null) {
          final file = result.files.single;
          setState(() {
            _attachedImage = file.path != null ? XFile(file.path!) : null;
            _attachedImageBytes = file.bytes;
          });
          return;
        } else {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(LocalizationService.t('no_image_selected')),
              backgroundColor: AppColors.error,
            ),
          );
          return;
        }
      }

      // Mobile permissions (Android/iOS)
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        // Prefer photos/media permission
        var photosStatus = await Permission.photos.status;
        if (photosStatus.isPermanentlyDenied) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                LocalizationService.t(
                  'photos_permission_permanently_denied_enable_in_settings',
                ),
              ),
              action: SnackBarAction(
                label: LocalizationService.t('open_settings'),
                onPressed: () {
                  openAppSettings();
                },
              ),
              backgroundColor: AppColors.error,
            ),
          );
          return;
        }
        if (!photosStatus.isGranted) {
          photosStatus = await Permission.photos.request();
        }
        // On older Android, fall back to storage
        if (!photosStatus.isGranted && Platform.isAndroid) {
          var storageStatus = await Permission.storage.status;
          if (!storageStatus.isGranted) {
            storageStatus = await Permission.storage.request();
          }
          if (!storageStatus.isGranted) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  LocalizationService.t(
                    'storage_permission_required_to_pick_images',
                  ),
                ),
                backgroundColor: AppColors.error,
              ),
            );
            return;
          }
        }
      }

      final picker = ImagePicker();
      try {
        final picked = await picker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 2000,
          maxHeight: 2000,
          imageQuality: 85,
        );
        if (picked != null) {
          final bytes = await picked.readAsBytes();
          setState(() {
            _attachedImage = picked;
            _attachedImageBytes = bytes;
          });
        }
      } on PlatformException catch (pe) {
        // Fallback to FilePicker when ImagePicker throws platform/channel error
        debugPrint(('ImagePicker PlatformException: $pe').toString());
        final result = await FilePicker.platform.pickFiles(
          type: FileType.image,
          withData: true,
        );
        if (result != null &&
            result.files.isNotEmpty &&
            result.files.single.bytes != null) {
          final file = result.files.single;
          setState(() {
            _attachedImage = file.path != null ? XFile(file.path!) : null;
            _attachedImageBytes = file.bytes;
          });
        } else {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(LocalizationService.t('failed_pick_image')),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint(('Error picking image: $e').toString());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(LocalizationService.t('failed_pick_image')),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _recordVideoMobile() async {
    try {
      if (kIsWeb) return; // mobile only
      if (!(Platform.isAndroid || Platform.isIOS)) return;
      // Request camera and microphone permissions
      var cameraStatus = await Permission.camera.status;
      if (!cameraStatus.isGranted) {
        cameraStatus = await Permission.camera.request();
      }
      var micStatus = await Permission.microphone.status;
      if (!micStatus.isGranted) {
        micStatus = await Permission.microphone.request();
      }
      if (!cameraStatus.isGranted || !micStatus.isGranted) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              LocalizationService.t(
                'camera_microphone_permission_required_to_record_video',
              ),
            ),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }

      final picker = ImagePicker();
      final picked = await picker.pickVideo(
        source: ImageSource.camera,
        maxDuration: const Duration(seconds: 30),
      );
      if (picked != null) {
        final path = picked.path;
        try {
          _inlineVideoController?.dispose();
        } catch (_) {}
        _inlineVideoController = VideoPlayerController.file(File(path));
        await _inlineVideoController!.initialize();
        _inlineVideoController!.setLooping(true);
        setState(() {
          _recordedVideoPath = path;
        });
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(LocalizationService.t('recording_canceled')),
            backgroundColor: AppColors.textSecondary,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error recording video (mobile): $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(LocalizationService.t('failed_record_video')),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  void _startRecordingTimer() {
    _recordingTimer?.cancel();
    const interval = Duration(milliseconds: 250);
    _recordingTimer = Timer.periodic(interval, (timer) async {
      if (!_isRecording) {
        timer.cancel();
        return;
      }
      final seconds = _messagingService.recordingDuration;
      if (mounted) {
        setState(() {
          _recordingDuration = Duration(seconds: seconds);
        });
      }
      if (seconds >= 15) {
        timer.cancel();
        await _stopRecording();
      }
    });
  }

  bool _isVideoUrl(String url) {
    final u = url.toLowerCase();
    return u.startsWith('data:video') ||
        u.endsWith('.mp4') ||
        u.endsWith('.webm') ||
        u.contains('/videos/') ||
        u.contains('video');
  }
}

class _InlineNetworkVideo extends StatefulWidget {
  final String url;
  const _InlineNetworkVideo({required this.url});
  @override
  State<_InlineNetworkVideo> createState() => _InlineNetworkVideoState();
}

class _InlineNetworkVideoState extends State<_InlineNetworkVideo> {
  VideoPlayerController? _controller;
  bool _initialized = false;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final uri = Uri.parse(widget.url);
      _controller = VideoPlayerController.networkUrl(uri);
      await _controller!.initialize();
      _controller!.setLooping(true);
      setState(() {
        _initialized = true;
      });
      _controller!.play();
      setState(() {
        _isPlaying = true;
      });
    } catch (e) {
      debugPrint(
        ('InlineNetworkVideo init failed: ' + e.toString()).toString(),
      );
    }
  }

  @override
  void dispose() {
    try {
      _controller?.dispose();
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final aspect = (_controller != null && _controller!.value.isInitialized)
        ? _controller!.value.aspectRatio
        : 16 / 9;
    return Stack(
      fit: StackFit.expand,
      children: [
        AspectRatio(
          aspectRatio: aspect,
          child: _initialized && _controller != null
              ? VideoPlayer(_controller!)
              : Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
        ),
        Positioned.fill(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                if (_controller == null) return;
                if (_isPlaying) {
                  _controller!.pause();
                } else {
                  _controller!.play();
                }
                setState(() {
                  _isPlaying = !_isPlaying;
                });
              },
              child: Center(
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.3),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _isPlaying ? Icons.pause : Icons.play_arrow,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
