import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
// Add permission_handler and file_picker for robust gallery selection
import 'package:permission_handler/permission_handler.dart';
import 'package:file_picker/file_picker.dart' as fp;
import '../../services/calling_service.dart';
import '../calling/calling_screen.dart';
import 'dart:io';
import '../../services/enhanced_messaging_service.dart';
import '../../services/notification_badge_service.dart';
import '../../models/message_model.dart';
import '../../services/localization_service.dart';
import '../../widgets/messaging/message_bubble.dart';
import '../../widgets/messaging/voice_recording_overlay.dart';
import '../../widgets/messaging/emoji_picker.dart';
import '../../config/app_colors.dart';
import '../../services/preferences_service.dart';
import '../../services/supabase_service.dart';
import '../../config/feature_flags.dart';
// Removed unused import: '../../services/auth_service.dart'
// Removed duplicate import of localization_service.dart

class EnhancedChatScreen extends StatefulWidget {
  final String conversationId;
  final String otherUserId;
  final String otherUserName;
  final String? otherUserAvatar;

  const EnhancedChatScreen({
    super.key,
    required this.conversationId,
    required this.otherUserId,
    required this.otherUserName,
    this.otherUserAvatar,
  });

  @override
  State<EnhancedChatScreen> createState() => _EnhancedChatScreenState();
}

class _EnhancedChatScreenState extends State<EnhancedChatScreen>
    with SingleTickerProviderStateMixin {
  final EnhancedMessagingService _messagingService = EnhancedMessagingService();
  final NotificationBadgeService _badgeService = NotificationBadgeService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _messageFocusNode = FocusNode();
  final PreferencesService _preferencesService = PreferencesService();

  // Hydrated display values for other user
  String _displayUserName = '';
  String? _displayUserAvatar;

  List<MessageModel> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  bool _isRecording = false;
  bool _showVoiceRecording = false;
  bool _showEmojiPicker = false;
  bool _hasText = false;
  bool _isOtherUserOnline = false;
  DateTime? _lastSeenTime;
  String? _currentUserId;
  String? _selectedImagePath;
  Uint8List? _selectedImageBytes;
  XFile? _selectedImageFile;
  bool _showImagePreview = false;
  StreamSubscription<MessageModel>? _messageSubscription;
  RealtimeChannel? _presenceChannel;
  late VoidCallback _presencePreferenceListener;

  // Recording animation and UI timer for voice messages
  late AnimationController _recordingAnimationController;
  late Animation<double> _recordingAnimation;
  Timer? _uiUpdateTimer;

  // De-dup helpers
  void _upsertMessage(MessageModel message) {
    final existingIndex = _messages.indexWhere((m) => m.id == message.id);
    if (existingIndex >= 0) {
      _messages[existingIndex] = message;
    } else {
      _messages.add(message);
    }
  }

  void _dedupeMessages() {
    final Map<String, MessageModel> unique = {};
    for (final m in _messages) {
      unique[m.id] = m;
    }
    _messages = unique.values.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  @override
  void initState() {
    super.initState();
    // Initialize hydrated display values from initial props
    _displayUserName = widget.otherUserName;
    _displayUserAvatar = widget.otherUserAvatar;

    _initializeChat();
    // Attempt hydration if we have an ID but only have placeholder name
    _hydrateOtherUserIfNeeded();

    _recordingAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _recordingAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(
        parent: _recordingAnimationController,
        curve: Curves.easeInOut,
      ),
    );

    // Listen to text changes to update button state
    _messageController.addListener(() {
      final hasText = _messageController.text.trim().isNotEmpty;
      if (hasText != _hasText) {
        setState(() {
          _hasText = hasText;
        });
      }
    });
    // Register presence preference listener
    _presencePreferenceListener = () async {
      final allowPresence = PreferencesService.showOnlineStatusNotifier.value;
      if (allowPresence) {
        if (_presenceChannel != null) {
          _presenceChannel?.track({
            'user_id': _currentUserId,
            'online_at': DateTime.now().toIso8601String(),
          });
        }
      } else {
        _presenceChannel?.untrack();
      }
    };
    PreferencesService.showOnlineStatusNotifier.addListener(
      _presencePreferenceListener,
    );
  }

  Future<void> _hydrateOtherUserIfNeeded() async {
    try {
      // If already hydrated, skip
      if (_displayUserName.isNotEmpty && _displayUserAvatar != null) return;

      final profile = await SupabaseService.getProfile(widget.otherUserId);

      if (!mounted) return;

      if (profile != null) {
        final rawDisplayName =
            (profile['display_name'] as String?)?.trim() ?? '';
        final rawUsername = (profile['username'] as String?)?.trim() ?? '';
        final effectiveName = _displayUserName.isNotEmpty
            ? _displayUserName
            : (rawDisplayName.isNotEmpty
                  ? rawDisplayName
                  : (rawUsername.isNotEmpty
                        ? '@$rawUsername'
                        : widget.otherUserName));
        setState(() {
          _displayUserName = effectiveName;
          _displayUserAvatar =
              _displayUserAvatar ?? (profile['avatar_url'] as String?);
        });
      }
    } catch (_) {
      // Silently ignore hydration errors to avoid disrupting chat UX
    }
  }

  Future<void> _initializeChat() async {
    await _messagingService.initialize();
    _currentUserId = Supabase.instance.client.auth.currentUser?.id;

    // Subscribe to new messages
    await _messagingService.subscribeToConversation(widget.conversationId);
    _messageSubscription = _messagingService.messageStream.listen((
      message,
    ) async {
      if (message.conversationId != widget.conversationId) return;

      _upsertMessage(message);

      // Mark new incoming messages as read since user is viewing the conversation
      if (message.senderId != _currentUserId) {
        await _messagingService.forceMarkMessagesAsRead(widget.conversationId);
        await _badgeService.loadInitialCounts();
      }
    });

    // Initialize presence tracking
    _initializePresence();

    // Load existing messages
    await _loadMessages();

    // Mark messages as read
    await _messagingService.forceMarkMessagesAsRead(widget.conversationId);

    // Refresh badge service to update message count
    await _badgeService.loadInitialCounts();
  }

  Future<void> _loadMessages() async {
    setState(() => _isLoading = true);
    final messages = await _messagingService.getMessages(widget.conversationId);
    setState(() {
      _messages = messages;
      _dedupeMessages();
      _isLoading = false;
    });
    // Scroll to bottom immediately after loading messages
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });
  }

  void _showMessageOptions(MessageModel message) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.delete, color: Colors.red),
                  title: Text(LocalizationService.t('delete_message')),
                  onTap: () => Navigator.of(ctx).pop(true),
                ),
                ListTile(
                  leading: const Icon(Icons.close),
                  title: const LocalizedText('cancel'),
                  onTap: () => Navigator.of(ctx).pop(false),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (confirmed == true) {
      final ok = await _messagingService.deleteMessage(
        messageId: message.id,
        conversationId: widget.conversationId,
      );
      if (ok) {
        setState(() {
          _messages.removeWhere((m) => m.id == message.id);
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: LocalizedText('failed_delete_message')),
        );
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  void _scrollToBottomAnimated() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // Presence helpers
  void _initializePresence() {
    _presenceChannel = Supabase.instance.client
        .channel('chat:${widget.conversationId}')
        .onPresenceSync((_) => _updateOtherUserOnlineFromPresenceState())
        .onPresenceJoin((_) => _updateOtherUserOnlineFromPresenceState())
        .onPresenceLeave((_) => _updateOtherUserOnlineFromPresenceState());

    _presenceChannel?.subscribe((status, [error]) async {
      if (status == RealtimeSubscribeStatus.subscribed) {
        final allowPresence = await _preferencesService.getShowOnlineStatus();
        if (allowPresence) {
          _presenceChannel?.track({
            'user_id': _currentUserId,
            'online_at': DateTime.now().toIso8601String(),
          });
        } else {
          _presenceChannel?.untrack();
        }
        _updateOtherUserOnlineFromPresenceState();
      }
    });
  }

  void _updateOtherUserOnlineFromPresenceState() {
    final state = _presenceChannel?.presenceState() ?? <String, dynamic>{};
    bool isOnline = false;

    (state as Map<String, dynamic>).forEach((key, value) {
      final List presences = value as List;
      for (final p in presences) {
        final map = Map<String, dynamic>.from(p as Map);
        if (map['user_id'] == widget.otherUserId) {
          isOnline = true;
          break;
        }
      }
    });

    if (mounted) {
      setState(() {
        if (_isOtherUserOnline && !isOnline) {
          _lastSeenTime = DateTime.now();
        }
        _isOtherUserOnline = isOnline;
      });
    }
  }

  String _getOnlineStatusText() {
    // Only show explicit "Active now"; hide any "last seen" text entirely
    return _isOtherUserOnline ? 'Active now' : '';
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppColors.surface,
      elevation: 1,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
        onPressed: () => Navigator.pop(context),
      ),
      title: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.surfaceVariant,
            backgroundImage: _displayUserAvatar != null
                ? NetworkImage(_displayUserAvatar!)
                : null,
            child: _displayUserAvatar == null
                ? Text(
                    _displayUserName.isNotEmpty
                        ? _displayUserName[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 24,
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
                  _displayUserName,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (_isOtherUserOnline) const SizedBox(height: 2),
                if (_isOtherUserOnline)
                  Text(
                    _getOnlineStatusText(),
                    style: const TextStyle(
                      color: AppColors.success,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        if (FeatureFlags.callsEnabled) ...[
          IconButton(
            icon: const Icon(Icons.videocam, color: AppColors.textPrimary),
            onPressed: _startVideoCall,
          ),
          IconButton(
            icon: const Icon(Icons.call, color: AppColors.textPrimary),
            onPressed: _startVoiceCall,
          ),
        ],
        IconButton(
          icon: const Icon(Icons.info_outline, color: AppColors.textPrimary),
          onPressed: _showUserInfo,
        ),
      ],
    );
  }

  Widget _buildMessagesList() {
    if (_messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 40,
              backgroundColor: AppColors.surfaceVariant,
              backgroundImage: _displayUserAvatar != null
                  ? NetworkImage(_displayUserAvatar!)
                  : null,
              child: _displayUserAvatar == null
                  ? Text(
                      _displayUserName.isNotEmpty
                          ? _displayUserName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 24,
                      ),
                    )
                  : null,
            ),
            const SizedBox(height: 16),
            Text(
              _displayUserName,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              LocalizationService.t('start_a_conversation'),
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];
        final isMe = message.senderId == _currentUserId;
        final showAvatar =
            !isMe &&
            (index == _messages.length - 1 ||
                (index < _messages.length - 1 &&
                    _messages[index + 1].senderId != message.senderId));

        return MessageBubble(
          message: message,
          isMe: isMe,
          showAvatar: showAvatar,
          otherUserAvatar: _displayUserAvatar,
          onPlayVoice: (url) => _messagingService.playVoiceMessage(url),
          onStopVoice: () => _messagingService.stopPlayingVoiceMessage(),
          otherUserOnline: _isOtherUserOnline,
          onLongPress: isMe ? () => _showMessageOptions(message) : null,
        );
      },
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(25),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(
                      _showEmojiPicker ? Icons.keyboard : Icons.emoji_emotions,
                      color: AppColors.textSecondary,
                    ),
                    onPressed: () {
                      setState(() {
                        _showEmojiPicker = !_showEmojiPicker;
                      });
                      if (_showEmojiPicker) {
                        _messageFocusNode.unfocus();
                      } else {
                        _messageFocusNode.requestFocus();
                      }
                    },
                  ),
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      focusNode: _messageFocusNode,
                      decoration: const InputDecoration(
                        hintText: 'Message...',
                        border: InputBorder.none,
                        hintStyle: TextStyle(color: AppColors.textSecondary),
                      ),
                      style: const TextStyle(color: AppColors.textPrimary),
                      maxLines: null,
                      textCapitalization: TextCapitalization.sentences,
                      onSubmitted: (_) => _sendTextMessage(),
                      onTap: () {
                        if (_showEmojiPicker) {
                          setState(() {
                            _showEmojiPicker = false;
                          });
                        }
                      },
                    ),
                  ),

                  IconButton(
                    icon: const Icon(
                      Icons.photo,
                      color: AppColors.textSecondary,
                    ),
                    onPressed: _selectFromGallery,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _hasText ? _sendTextMessage : null,
            onLongPressStart: (_) {
              if (!_hasText) {
                _startVoiceRecording();
              }
            },
            onLongPressEnd: (_) {
              if (_isRecording) {
                _stopVoiceRecording();
              }
            },
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _hasText ? AppColors.primary : AppColors.accent,
                shape: BoxShape.circle,
              ),
              child: Icon(
                _hasText ? Icons.send : Icons.mic,
                color: AppColors.textPrimary,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _cancelImagePreview() {
    setState(() {
      _showImagePreview = false;
      _selectedImagePath = null;
      _selectedImageBytes = null;
      _selectedImageFile = null;
    });
  }

  void _sendSelectedImage() {
    if (_selectedImageFile != null) {
      _sendImageMessageFromFile(_selectedImageFile!);
    }
  }

  Widget _buildImagePreviewOverlay() {
    return Container(
      color: AppColors.overlay,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              constraints: const BoxConstraints(maxWidth: 300, maxHeight: 400),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: kIsWeb && _selectedImageBytes != null
                    ? Image.memory(_selectedImageBytes!, fit: BoxFit.contain)
                    : _selectedImagePath != null
                    ? Image.file(File(_selectedImagePath!), fit: BoxFit.contain)
                    : Container(
                        color: AppColors.surfaceVariant,
                        child: const Icon(
                          Icons.image,
                          size: 50,
                          color: AppColors.textPrimary,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: _cancelImagePreview,
                  icon: const Icon(Icons.close, color: AppColors.textPrimary),
                  label: const Text(
                    'Cancel',
                    style: TextStyle(color: AppColors.textPrimary),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _isSending ? null : _sendSelectedImage,
                  icon: _isSending
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.textPrimary,
                          ),
                        )
                      : const Icon(Icons.send, color: AppColors.textPrimary),
                  label: Text(
                    _isSending ? 'Sending...' : 'Send',
                    style: const TextStyle(color: AppColors.textPrimary),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _startVideoCall() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Row(
          children: [
            const Icon(Icons.videocam, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(
              LocalizationService.t('video_call'),
              style: TextStyle(color: AppColors.textPrimary),
            ),
          ],
        ),
        content: Text(
          "${LocalizationService.t('start_a_video_call_with')} ${widget.otherUserName}?\n\n${LocalizationService.t('this_will_open_device_video_call_app')}",
          style: TextStyle(color: AppColors.textPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              LocalizationService.t('cancel'),
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _initiateVideoCall();
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: Text(
              LocalizationService.t('start_call'),
              style: TextStyle(color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  void _startVoiceCall() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Row(
          children: [
            const Icon(Icons.call, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(
              LocalizationService.t('voice_call'),
              style: TextStyle(color: AppColors.textPrimary),
            ),
          ],
        ),
        content: Text(
          "${LocalizationService.t('start_a_voice_call_with')} ${widget.otherUserName}?\n\n${LocalizationService.t('this_will_open_device_phone_app')}",
          style: TextStyle(color: AppColors.textPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              LocalizationService.t('cancel'),
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _initiateVoiceCall();
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: Text(
              LocalizationService.t('start_call'),
              style: TextStyle(color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  void _showUserInfo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          'User Information',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 30,
              backgroundImage: widget.otherUserAvatar != null
                  ? NetworkImage(widget.otherUserAvatar!)
                  : null,
              child: widget.otherUserAvatar == null
                  ? Text(
                      widget.otherUserName.isNotEmpty
                          ? widget.otherUserName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    )
                  : null,
            ),
            const SizedBox(height: 16),
            Text(
              'Name: ${widget.otherUserName}',
              style: TextStyle(color: AppColors.textPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              'User ID: ${widget.otherUserId}',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            if (FeatureFlags.showUserStatus) const SizedBox(height: 8),
            if (FeatureFlags.showUserStatus)
              Text(
                'Status: ${_isOtherUserOnline ? "Online" : "Offline"}',
                style: TextStyle(
                  color: _isOtherUserOnline
                      ? AppColors.success
                      : AppColors.textSecondary,
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Close', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  Future<void> _cancelVoiceRecording() async {
    await _messagingService.cancelVoiceRecording();

    _uiUpdateTimer?.cancel();
    _uiUpdateTimer = null;

    setState(() {
      _isRecording = false;
      _showVoiceRecording = false;
    });
    _recordingAnimationController.stop();
    _recordingAnimationController.reset();

    HapticFeedback.lightImpact();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Column(
                  children: [
                    Expanded(
                      child: _isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : _buildMessagesList(),
                    ),
                  ],
                ),
                if (_showVoiceRecording)
                  VoiceRecordingOverlay(
                    isRecording: _isRecording,
                    duration: _messagingService.recordingDuration,
                    onCancel: _cancelVoiceRecording,
                    onStop: _stopVoiceRecording,
                    animation: _recordingAnimation,
                  ),
                if (_showImagePreview &&
                    (_selectedImagePath != null || _selectedImageBytes != null))
                  _buildImagePreviewOverlay(),
              ],
            ),
          ),
          _buildMessageInput(),
          if (_showEmojiPicker)
            EmojiPicker(
              onEmojiSelected: (emoji) {
                final currentText = _messageController.text;
                final selection = _messageController.selection;
                final newText = currentText.replaceRange(
                  selection.start,
                  selection.end,
                  emoji,
                );
                _messageController.text = newText;
                _messageController.selection = TextSelection.collapsed(
                  offset: selection.start + emoji.length,
                );
              },
              onClose: () {
                setState(() {
                  _showEmojiPicker = false;
                });
              },
            ),
        ],
      ),
    );
  }

  Future<void> _sendTextMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty || _isSending) return;

    setState(() => _isSending = true);
    _messageController.clear();

    final messenger = ScaffoldMessenger.of(context);
    try {
      final message = await _messagingService.sendTextMessage(
        conversationId: widget.conversationId,
        content: content,
      );

      if (!mounted) return;
      if (message != null) {
        _upsertMessage(message);
        _scrollToBottom();
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: LocalizedText(
            '${LocalizationService.t('failed_to_send_message')}: $e',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  Future<void> _startVoiceRecording() async {
    final success = await _messagingService.startVoiceRecording();
    if (!mounted) return;

    if (success) {
      setState(() {
        _isRecording = true;
        _showVoiceRecording = true;
      });
      _recordingAnimationController.repeat(reverse: true);

      _uiUpdateTimer = Timer.periodic(const Duration(milliseconds: 100), (
        timer,
      ) {
        if (_isRecording) {
          setState(() {});
          if (_messagingService.recordingDuration >= 15) {
            _stopVoiceRecording();
          }
        } else {
          if (_showVoiceRecording &&
              _messagingService.recordingDuration >= 15) {
            _stopVoiceRecording();
          }
          timer.cancel();
        }
      });

      HapticFeedback.lightImpact();
    } else {
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        SnackBar(
          content: LocalizedText(
            kIsWeb
                ? LocalizationService.t('voice_recording_not_supported_web')
                : LocalizationService.t(
                    'unable_to_start_recording_check_mic_permissions',
                  ),
          ),
          backgroundColor: AppColors.warning,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _stopVoiceRecording() async {
    final audioPath = await _messagingService.stopVoiceRecording();
    if (!mounted) return;

    _uiUpdateTimer?.cancel();
    _uiUpdateTimer = null;

    setState(() {
      _isRecording = false;
      _showVoiceRecording = false;
    });
    _recordingAnimationController.stop();
    _recordingAnimationController.reset();

    if (audioPath != null) {
      await _sendVoiceMessage(audioPath);
    }
  }

  Future<void> _sendVoiceMessage(String audioPath) async {
    setState(() => _isSending = true);

    final messenger = ScaffoldMessenger.of(context);
    try {
      final message = await _messagingService.sendVoiceMessage(
        conversationId: widget.conversationId,
        audioPath: audioPath,
      );

      if (!mounted) return;
      if (message != null) {
        _upsertMessage(message);
        _scrollToBottomAnimated();
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: LocalizedText(
            '${LocalizationService.t('failed_to_send_voice_message')}: $e',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  Future<void> _selectFromGallery() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      // On Android 13+, ensure READ_MEDIA_IMAGES or Photos permission
      if (!kIsWeb && Platform.isAndroid) {
        final status = await Permission
            .photos
            .status; // Photos covers media on Android/iOS in permission_handler >=10
        if (!status.isGranted) {
          final req = await Permission.photos.request();
          if (!req.isGranted) {
            messenger.showSnackBar(
              SnackBar(
                content: Text(
                  LocalizationService.t('permission_required_photos'),
                ),
                backgroundColor: AppColors.error,
              ),
            );
            if (req.isPermanentlyDenied) {
              await openAppSettings();
            }
            return;
          }
        }
      }

      final ImagePicker picker = ImagePicker();
      XFile? image;
      try {
        image = await picker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 1920,
          maxHeight: 1080,
          imageQuality: 85,
        );
      } on PlatformException catch (pe) {
        // Fallback to FilePicker for robustness when channel errors occur
        debugPrint(
          'ImagePicker PlatformException: $pe — falling back to FilePicker',
        );
        final result = await fp.FilePicker.platform.pickFiles(
          type: fp.FileType.image,
          allowMultiple: false,
          withData: true,
        );
        if (result != null && result.files.isNotEmpty) {
          final file = result.files.first;
          if (kIsWeb) {
            // On web, build XFile from bytes
            final bytes = file.bytes;
            if (bytes != null) {
              final xf = XFile.fromData(
                bytes,
                name: file.name,
                mimeType: file.extension,
              );
              image = xf;
            }
          } else if (file.path != null) {
            image = XFile(file.path!);
          }
        }
      }

      if (!mounted) return;

      if (image != null) {
        if (kIsWeb) {
          final bytes = await image.readAsBytes();
          if (!mounted) return;
          setState(() {
            _selectedImageFile = image;
            _selectedImageBytes = bytes;
            _selectedImagePath = null;
            _showImagePreview = true;
          });
        } else {
          setState(() {
            _selectedImagePath = image!.path;
            _selectedImageFile = image;
            _selectedImageBytes = null;
            _showImagePreview = true;
          });
        }
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${LocalizationService.t('failed_to_select_image')}: $e',
          ),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _sendImageMessageFromFile(XFile imageFile) async {
    setState(() => _isSending = true);

    final messenger = ScaffoldMessenger.of(context);
    try {
      final message = await _messagingService.sendImageMessageFromFile(
        conversationId: widget.conversationId,
        imageFile: imageFile,
      );

      if (!mounted) return;
      if (message != null) {
        setState(() {
          _upsertMessage(message);
          _showImagePreview = false;
          _selectedImagePath = null;
        });
        _scrollToBottom();
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('${LocalizationService.t('failed_to_send_image')}: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  void _initiateVideoCall() async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final callingService = CallingService();
      final call = await callingService.initiateCall(
        receiverId: widget.otherUserId,
        receiverName: widget.otherUserName,
        type: CallType.video,
      );

      if (call != null) {
        navigator.push(
          MaterialPageRoute(
            builder: (context) => CallingScreen(call: call, isIncoming: false),
          ),
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${LocalizationService.t('failed_to_start_video_call')}: $e',
          ),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  void _initiateVoiceCall() async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final callingService = CallingService();
      final call = await callingService.initiateCall(
        receiverId: widget.otherUserId,
        receiverName: widget.otherUserName,
        type: CallType.audio,
      );

      if (call != null) {
        navigator.push(
          MaterialPageRoute(
            builder: (context) => CallingScreen(call: call, isIncoming: false),
          ),
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${LocalizationService.t('failed_to_start_voice_call')}: $e',
          ),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  void dispose() {
    // Cancel timers
    _uiUpdateTimer?.cancel();

    // Dispose controllers and focus nodes
    _recordingAnimationController.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    _messageFocusNode.dispose();

    // Cancel message subscription if active
    _messageSubscription?.cancel();

    // Remove presence preference listener and untrack presence
    PreferencesService.showOnlineStatusNotifier.removeListener(
      _presencePreferenceListener,
    );
    _presenceChannel?.untrack();
    _presenceChannel?.unsubscribe();

    super.dispose();
  }
}
