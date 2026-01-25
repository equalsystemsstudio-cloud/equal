import 'package:flutter/material.dart';
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/app_colors.dart';
import '../../services/enhanced_messaging_service.dart';
import '../../models/conversation_model.dart';
import 'enhanced_chat_screen.dart';
import '../../services/preferences_service.dart';
import '../../services/social_service.dart';
import '../../services/supabase_service.dart';
import '../../services/localization_service.dart';
import '../../services/notification_badge_service.dart';

class ConversationsScreen extends StatefulWidget {
  const ConversationsScreen({super.key});

  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends State<ConversationsScreen> {
  final EnhancedMessagingService _messagingService = EnhancedMessagingService();
  final TextEditingController _searchController = TextEditingController();
  final PreferencesService _preferencesService = PreferencesService();
  final SocialService _socialService = SocialService();
  final NotificationBadgeService _badgeService = NotificationBadgeService();

  List<ConversationModel> _conversations = [];
  List<ConversationModel> _filteredConversations = [];
  List<Map<String, dynamic>> _userShortcuts = [];
  List<Map<String, dynamic>> _filteredUserShortcuts = [];
  bool _isLoading = true;
  int _activeTabIndex = 0;
  String? _currentUserId;
  StreamSubscription<ConversationModel>? _conversationSubscription;
  bool _allowMessageRequests = true;
  // Track online status per conversation (other user presence)
  final Map<String, bool> _onlineByConversation = {};
  // Presence channels per conversation
  final Map<String, RealtimeChannel> _presenceChannels = {};
  // Listener to update presence broadcasting when user toggles privacy
  late VoidCallback _presencePreferenceListener;

  @override
  void initState() {
    super.initState();
    _initializeConversations();
  }

  Future<void> _initializeConversations() async {
    await _messagingService.initialize();
    _currentUserId = Supabase.instance.client.auth.currentUser?.id;
    // Load preference for allowing message requests
    final allowMsgReq = await _preferencesService.getAllowMessageRequests();
    setState(() {
      _allowMessageRequests = allowMsgReq;
    });

    // Subscribe to conversation updates
    _conversationSubscription = _messagingService.conversationStream.listen((
      conversation,
    ) {
      _updateConversationInList(conversation);
      // Ensure presence tracking exists for new/updated conversations
      _reconcilePresenceChannels();
    });

    // Listen for Show Online Status preference changes and update presence broadcasting
    _presencePreferenceListener = () async {
      final allowPresence = PreferencesService.showOnlineStatusNotifier.value;
      _updatePresenceTrackingForAllChannels(allowPresence);
    };
    PreferencesService.showOnlineStatusNotifier.addListener(
      _presencePreferenceListener,
    );

    await _loadConversations();
  }

  Future<void> _loadConversations() async {
    setState(() => _isLoading = true);

    try {
      debugPrint(
        ('Loading conversations for user: $_currentUserId').toString(),
      );
      final conversations = await _messagingService.getConversations();
      debugPrint(('Loaded ${conversations.length} conversations').toString());
      for (var conv in conversations) {
        debugPrint(
          ('Conversation: ${conv.id}, participants: ${conv.participant1Id}, ${conv.participant2Id}')
              .toString(),
        );
      }

      // Load user shortcuts (users who have messaged the current user)
      final userShortcuts = await _messagingService.getUsersWhoMessagedMe();
      debugPrint(('Loaded ${userShortcuts.length} user shortcuts').toString());

      // Apply preference-based filtering: if message requests are disabled, only show conversations/users you track
      List<ConversationModel> convsFiltered = conversations;
      List<Map<String, dynamic>> usersFiltered = userShortcuts;
      if (!_allowMessageRequests) {
        convsFiltered = await _filterConversationsByFollowing(conversations);
        usersFiltered = await _filterUsersByFollowing(userShortcuts);
      }

      if (!mounted) return;
      setState(() {
        _conversations = convsFiltered;
        _filteredConversations = convsFiltered;
        _userShortcuts = usersFiltered;
        _filteredUserShortcuts = usersFiltered;
        _isLoading = false;
      });
      // After conversations load/update, ensure presence channels are set up
      await _reconcilePresenceChannels();
    } catch (e) {
      debugPrint(('Error loading conversations: $e').toString());
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: LocalizedText('Failed to load conversations: $e')),
      );
    }
  }

  Future<List<ConversationModel>> _filterConversationsByFollowing(
    List<ConversationModel> conversations,
  ) async {
    final uid = _currentUserId ?? Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return [];
    final List<ConversationModel> result = [];
    for (final conv in conversations) {
      final otherUserId = conv.getOtherParticipantId(uid);
      try {
        final isFollowing = await _socialService.isFollowing(otherUserId);
        if (isFollowing) {
          result.add(conv);
        }
      } catch (e) {
        debugPrint(('Follow check failed for $otherUserId: $e').toString());
      }
    }
    return result;
  }

  Future<List<Map<String, dynamic>>> _filterUsersByFollowing(
    List<Map<String, dynamic>> users,
  ) async {
    final List<Map<String, dynamic>> result = [];
    for (final user in users) {
      final otherUserId = user['id'] as String?;
      if (otherUserId == null) continue;
      try {
        final isFollowing = await _socialService.isFollowing(otherUserId);
        if (isFollowing) {
          result.add(user);
        }
      } catch (e) {
        debugPrint(('Follow check failed for $otherUserId: $e').toString());
      }
    }
    return result;
  }

  void _updateConversationInList(ConversationModel conversation) {
    setState(() {
      final index = _conversations.indexWhere((c) => c.id == conversation.id);
      if (index != -1) {
        _conversations[index] = conversation;
        final filteredIndex = _filteredConversations.indexWhere(
          (c) => c.id == conversation.id,
        );
        if (filteredIndex != -1) {
          _filteredConversations[filteredIndex] = conversation;
        }
      } else {
        _conversations.insert(0, conversation);
        _filteredConversations.insert(0, conversation);
      }
    });
    // Ensure presence tracking is updated for this conversation
    _reconcilePresenceChannels();
  }

  void _onSearchChanged(String query) {
    setState(() {
      _filteredConversations = _conversations.where((conv) {
        final name = conv.getOtherParticipantName(_currentUserId ?? '');
        final username = conv.getOtherParticipantUsername(_currentUserId ?? '');
        return name.toLowerCase().contains(query.toLowerCase()) ||
            username.toLowerCase().contains(query.toLowerCase());
      }).toList();

      _filteredUserShortcuts = _userShortcuts.where((user) {
        final displayName = (user['display_name'] ?? '').toString();
        final username = (user['username'] ?? '').toString();
        return displayName.toLowerCase().contains(query.toLowerCase()) ||
            username.toLowerCase().contains(query.toLowerCase());
      }).toList();
    });
  }

  void _openChat(ConversationModel conversation) {
    final uid = _currentUserId ?? Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(LocalizationService.t('not_authenticated'))),
      );
      return;
    }

    final otherUserId = conversation.getOtherParticipantId(uid);
    final displayName = conversation.getOtherParticipantName(uid);
    final otherUsernamePlain = conversation.getOtherParticipantUsername(uid);
    final resolvedName = displayName.isNotEmpty
        ? displayName
        : (otherUsernamePlain.isNotEmpty
              ? '@$otherUsernamePlain'
              : LocalizationService.t('unknown_user'));
    final otherUserAvatar = conversation.getOtherParticipantAvatar(uid);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EnhancedChatScreen(
          conversationId: conversation.id,
          otherUserId: otherUserId,
          otherUserName: resolvedName,
          otherUserAvatar: otherUserAvatar,
        ),
      ),
    );
  }

  void _openChatWithUser(Map<String, dynamic> user) async {
    final otherUserId = user['id'] as String?;
    if (otherUserId == null) return;

    final conversation = await _messagingService.getOrCreateConversation(
      otherUserId,
    );
    if (conversation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(LocalizationService.t('cannot_start_conversation')),
        ),
      );
      return;
    }

    final displayName = (user['display_name'] as String?)?.trim() ?? '';
    final username = (user['username'] as String?)?.trim() ?? '';
    final effectiveName = displayName.isNotEmpty
        ? displayName
        : (username.isNotEmpty
              ? '@$username'
              : LocalizationService.t('unknown_user'));
    final avatar = user['avatar_url'] as String?;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EnhancedChatScreen(
          conversationId: conversation.id,
          otherUserId: otherUserId,
          otherUserName: effectiveName,
          otherUserAvatar: avatar,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 1,
        title: Text(
          LocalizationService.t('conversations'),
          style: const TextStyle(color: AppColors.textPrimary),
        ),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                _buildSearchBar(),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Text(
                    LocalizationService.t('conversations'),
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ),
                ..._filteredConversations
                    .map((c) => _buildConversationTile(c))
                    .toList(),
                const SizedBox(height: 24),
              ],
            ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: LocalizationService.t('search_conversations_or_users'),
          prefixIcon: const Icon(Icons.search),
          border: const OutlineInputBorder(),
        ),
        onChanged: _onSearchChanged,
      ),
    );
  }

  Widget _buildTabHeader(String title, int tabIndex, bool isActive) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _activeTabIndex = tabIndex;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isActive ? AppColors.primary : AppColors.textSecondary,
              width: 2,
            ),
          ),
        ),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 16,
            color: isActive ? AppColors.primary : AppColors.textSecondary,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildConversationTile(ConversationModel conversation) {
    final displayName = conversation.getOtherParticipantName(
      _currentUserId ?? '',
    );
    final otherUsernamePlain = conversation.getOtherParticipantUsername(
      _currentUserId ?? '',
    );
    final otherUserName = displayName.isNotEmpty
        ? displayName
        : (otherUsernamePlain.isNotEmpty
              ? '@$otherUsernamePlain'
              : LocalizationService.t('unknown_user'));
    final otherUserAvatar = conversation.getOtherParticipantAvatar(
      _currentUserId ?? '',
    );
    final isOtherOnline = _onlineByConversation[conversation.id] == true;
    final lastMessage = conversation.lastMessageContent;
    final timeAgo = conversation.timeAgo;

    return FutureBuilder<int>(
      future: _messagingService.getUnreadMessageCount(conversation.id),
      builder: (context, snapshot) {
        final unreadCount = snapshot.data ?? 0;
        final hasUnreadMessages = unreadCount > 0;

        return InkWell(
          onTap: () => _openChat(conversation),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                // Avatar
                Stack(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: AppColors.surface,
                      backgroundImage: otherUserAvatar != null
                          ? NetworkImage(otherUserAvatar)
                          : null,
                      child: otherUserAvatar == null
                          ? Text(
                              otherUserName.isNotEmpty
                                  ? otherUserName[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            )
                          : null,
                    ),
                    // Online indicator
                    if (isOtherOnline)
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: AppColors.success,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.textPrimary,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 12),

                // Conversation details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              otherUserName,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: hasUnreadMessages
                                    ? FontWeight.bold
                                    : FontWeight.w500,
                                color: AppColors.textPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (timeAgo.isNotEmpty)
                            Text(
                              timeAgo,
                              style: TextStyle(
                                fontSize: 12,
                                color: hasUnreadMessages
                                    ? AppColors.primary
                                    : AppColors.textSecondary,
                                fontWeight: hasUnreadMessages
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              lastMessage,
                              style: TextStyle(
                                fontSize: 14,
                                color: hasUnreadMessages
                                    ? AppColors.textPrimary
                                    : AppColors.textSecondary,
                                fontWeight: hasUnreadMessages
                                    ? FontWeight.w500
                                    : FontWeight.normal,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                          if (hasUnreadMessages)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                unreadCount.toString(),
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildUserShortcutTile(Map<String, dynamic> user) {
    final displayName = (user['display_name'] ?? '').toString();
    final username = (user['username'] ?? '').toString();
    final userName = displayName.isNotEmpty
        ? displayName
        : (username.isNotEmpty ? '@$username' : 'Unknown User');
    final userAvatar = user['avatar_url'];

    return InkWell(
      onTap: () => _openChatWithUser(user),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Avatar
            Stack(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: AppColors.surface,
                  backgroundImage: userAvatar != null
                      ? NetworkImage(userAvatar)
                      : null,
                  child: userAvatar == null
                      ? Text(
                          userName.isNotEmpty ? userName[0].toUpperCase() : '?',
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        )
                      : null,
                ),
                // Message indicator
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.textPrimary,
                        width: 2,
                      ),
                    ),
                    child: const Icon(
                      Icons.message,
                      size: 10,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),

            // User details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    userName,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    username.isNotEmpty
                        ? '@$username'
                        : 'Tap to start conversation',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _conversationSubscription?.cancel();
    // Remove preference listener
    PreferencesService.showOnlineStatusNotifier.removeListener(
      _presencePreferenceListener,
    );
    // Cleanup presence channels
    for (final ch in _presenceChannels.values) {
      try {
        ch.untrack();
        ch.unsubscribe();
      } catch (_) {}
    }
    _presenceChannels.clear();
    super.dispose();
  }

  // ========== Presence management for conversations ==========

  Future<void> _reconcilePresenceChannels() async {
    final uid = _currentUserId ?? Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;

    // Build a set of current conversation IDs
    final Set<String> currentIds = _conversations.map((c) => c.id).toSet();

    // Remove presence channels for conversations no longer in the list
    final List<String> toRemove = _presenceChannels.keys
        .where((id) => !currentIds.contains(id))
        .toList();
    for (final id in toRemove) {
      final ch = _presenceChannels.remove(id);
      try {
        await ch?.untrack();
        await ch?.unsubscribe();
      } catch (_) {}
      _onlineByConversation.remove(id);
    }

    // Add presence channels for new conversations
    for (final conv in _conversations) {
      if (!_presenceChannels.containsKey(conv.id)) {
        await _initPresenceForConversation(conv);
      } else {
        // Update online state immediately from current presence
        final otherUserId = conv.getOtherParticipantId(uid);
        _updateOnlineForConversation(conv.id, otherUserId);
      }
    }
  }

  Future<void> _initPresenceForConversation(ConversationModel conv) async {
    final uid = _currentUserId ?? Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;

    final otherUserId = conv.getOtherParticipantId(uid);
    final channel = Supabase.instance.client
        .channel('chat:${conv.id}')
        .onPresenceSync(
          (_) => _updateOnlineForConversation(conv.id, otherUserId),
        )
        .onPresenceJoin(
          (_) => _updateOnlineForConversation(conv.id, otherUserId),
        )
        .onPresenceLeave(
          (_) => _updateOnlineForConversation(conv.id, otherUserId),
        );

    _presenceChannels[conv.id] = channel;

    await channel.subscribe((status, [error]) async {
      if (status == RealtimeSubscribeStatus.subscribed) {
        // Respect user's preference for broadcasting their own presence
        final allowPresence = await _preferencesService.getShowOnlineStatus();
        if (allowPresence) {
          await channel.track({
            'user_id': uid,
            'online_at': DateTime.now().toIso8601String(),
          });
        } else {
          await channel.untrack();
        }
        _updateOnlineForConversation(conv.id, otherUserId);
      }
    });
  }

  void _updateOnlineForConversation(String conversationId, String otherUserId) {
    final state =
        _presenceChannels[conversationId]?.presenceState() ??
        <String, dynamic>{};
    bool isOnline = false;

    (state as Map<String, dynamic>).forEach((key, value) {
      final List presences = value as List;
      for (final p in presences) {
        final map = Map<String, dynamic>.from(p as Map);
        if (map['user_id'] == otherUserId) {
          isOnline = true;
          break;
        }
      }
    });

    if (_onlineByConversation[conversationId] != isOnline) {
      setState(() {
        _onlineByConversation[conversationId] = isOnline;
      });
    }
  }

  void _updatePresenceTrackingForAllChannels(bool allowPresence) async {
    final uid = _currentUserId ?? Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    for (final ch in _presenceChannels.values) {
      try {
        if (allowPresence) {
          await ch.track({
            'user_id': uid,
            'online_at': DateTime.now().toIso8601String(),
          });
        } else {
          await ch.untrack();
        }
      } catch (_) {}
    }
  }
}
