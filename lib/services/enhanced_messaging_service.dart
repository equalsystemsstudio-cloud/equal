import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:record/record.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart'; // Added for runtime microphone permission
import '../models/message_model.dart';
import '../models/conversation_model.dart';
import 'storage_service.dart';
import 'preferences_service.dart';
import 'social_service.dart';
import 'enhanced_notification_service.dart';
import 'supabase_service.dart';
import 'localization_service.dart';

class EnhancedMessagingService {
  static final EnhancedMessagingService _instance =
      EnhancedMessagingService._internal();
  factory EnhancedMessagingService() => _instance;
  EnhancedMessagingService._internal();

  static const Duration _networkTimeout = Duration(seconds: 10);

  final SupabaseClient _supabase = Supabase.instance.client;
  final AudioRecorder _audioRecorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final PreferencesService _preferencesService = PreferencesService();

  final StreamController<MessageModel> _messageController =
      StreamController<MessageModel>.broadcast();
  final StreamController<ConversationModel> _conversationController =
      StreamController<ConversationModel>.broadcast();
  final Map<String, RealtimeChannel> _conversationChannels = {};

  Stream<MessageModel> get messageStream => _messageController.stream;
  Stream<ConversationModel> get conversationStream =>
      _conversationController.stream;

  bool _isRecording = false;
  String? _currentRecordingPath;
  Timer? _recordingTimer;
  int _recordingDuration = 0;

  // Initialize messaging service
  Future<void> initialize() async {
    await _setupRealtimeSubscriptions();
  }

  // Setup real-time subscriptions for conversations and messages
  Future<void> _setupRealtimeSubscriptions() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    // Subscribe to new conversations
    _supabase
        .channel('conversations:$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'conversations',
          callback: (payload) {
            _handleConversationChange(payload);
          },
        )
        .subscribe();
  }

  // Handle conversation changes
  void _handleConversationChange(PostgresChangePayload payload) {
    try {
      final conversation = ConversationModel.fromJson(payload.newRecord);
      _conversationController.add(conversation);
    } catch (e) {
      debugPrint('Error handling conversation change: $e');
    }
  }

  // Subscribe to messages in a specific conversation
  Future<void> subscribeToConversation(String conversationId) async {
    if (_conversationChannels.containsKey(conversationId)) return;

    final channel = _supabase
        .channel('messages:$conversationId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (payload) {
            if (payload.newRecord['conversation_id'] == conversationId) {
              _handleNewMessage(payload.newRecord);
            }
          },
        )
        // Subscribe to updates so read status changes propagate to the sender
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'messages',
          callback: (payload) {
            if (payload.newRecord['conversation_id'] == conversationId) {
              _handleMessageUpdated(payload.newRecord);
            }
          },
        )
        .subscribe();

    _conversationChannels[conversationId] = channel;
  }

  // Handle new message
  void _handleNewMessage(Map<String, dynamic> data) async {
    try {
      final message = MessageModel.fromJson(data);
      _messageController.add(message);

      // Create a fallback notification for the recipient so it appears under the "All" tab
      // This covers cases where the sender's client did not insert a notifications row.
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId != null && message.senderId != currentUserId) {
        try {
          // Skip if a notification for this message already exists (avoid duplicates)
          final existing = await _supabase
              .from('notifications')
              .select('id')
              .eq('user_id', currentUserId)
              .eq('type', 'message')
              .contains('data', {'message_id': message.id});
          if (existing is List && existing.isNotEmpty) {
            // Notification already exists, no need to insert another
            return;
          }

          final effectiveName =
              (message.senderInfo?['display_name'] as String?)
                      ?.trim()
                      .isNotEmpty ==
                  true
              ? message.senderInfo!['display_name'] as String
              : (message.senderInfo?['username'] as String?)
                        ?.trim()
                        .isNotEmpty ==
                    true
              ? message.senderInfo!['username'] as String
              : 'Someone';

          String messageText;
          if (message.isTextMessage) {
            final preview = message.content.trim();
            final truncated = preview.length > 80
                ? '${preview.substring(0, 80)}…'
                : preview;
            messageText = truncated.isNotEmpty
                ? '$effectiveName: $truncated'
                : '$effectiveName ${LocalizationService.t('sent_you_a_message')}';
          } else if (message.isVoiceMessage) {
            messageText =
                '$effectiveName ${LocalizationService.t('sent_voice_message')}';
          } else if (message.isImageMessage) {
            messageText =
                '$effectiveName ${LocalizationService.t('sent_a_photo')}';
          } else {
            messageText =
                '$effectiveName ${LocalizationService.t('sent_you_a_message')}';
          }

          await EnhancedNotificationService().createNotification(
            userId: currentUserId,
            type: 'message',
            title: LocalizationService.t('new_message_title'),
            message: messageText,
            data: {
              'conversation_id': message.conversationId,
              'sender_id': message.senderId,
              'sender_username': message.senderInfo?['username'],
              'message_id': message.id,
              'action_type': 'message',
            },
          );
        } catch (e) {
          debugPrint('Error creating local message notification: $e');
        }
      }
    } catch (e) {
      debugPrint('Error handling new message: $e');
    }
  }

  // Emit updated messages (e.g., read receipts) to update sender-side UI ticks
  void _handleMessageUpdated(Map<String, dynamic> data) {
    try {
      final message = MessageModel.fromJson(data);
      _messageController.add(message);
    } catch (e) {
      debugPrint('Error handling message update: $e');
    }
  }

  // Get or create conversation between two users
  Future<ConversationModel?> getOrCreateConversation(String otherUserId) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return null;

      // Check if conversation already exists
      final existingConversation = await _supabase
          .from('conversations')
          .select('''
            *,
            participant_1:participant_1_id(id, display_name, avatar_url),
            participant_2:participant_2_id(id, display_name, avatar_url)
          ''')
          .or(
            'and(participant_1_id.eq.$currentUserId,participant_2_id.eq.$otherUserId),and(participant_1_id.eq.$otherUserId,participant_2_id.eq.$currentUserId)',
          )
          .maybeSingle();

      if (existingConversation != null) {
        return ConversationModel.fromJson(existingConversation);
      }

      // Gate new conversation creation based on preferences and following
      final allowRequests = await _preferencesService.getAllowMessageRequests();
      bool isFollowingUser = false;
      try {
        isFollowingUser = await SocialService().isFollowing(otherUserId);
      } catch (e) {
        debugPrint('Follow check failed: $e');
      }

      if (!allowRequests && !isFollowingUser) {
        debugPrint(
          'Message requests disabled and not following; refusing to create conversation with $otherUserId',
        );
        return null;
      }

      // Create new conversation
      final newConversation = await _supabase
          .from('conversations')
          .insert({
            'participant_1_id': currentUserId,
            'participant_2_id': otherUserId,
          })
          .select('''
            *,
            participant_1:participant_1_id(id, display_name, avatar_url),
            participant_2:participant_2_id(id, display_name, avatar_url)
          ''')
          .single();

      return ConversationModel.fromJson(newConversation);
    } catch (e) {
      debugPrint('Error getting/creating conversation: $e');
      return null;
    }
  }

  // Get conversations for current user
  Future<List<ConversationModel>> getConversations() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      debugPrint('Getting conversations for user: $userId');
      if (userId == null) {
        debugPrint('No authenticated user found');
        return [];
      }

      // Base query without joining last_message because there is no FK on last_message_id
      final response = await _supabase
          .from('conversations')
          .select('''
            *,
            participant_1:participant_1_id(id, display_name, avatar_url, username),
            participant_2:participant_2_id(id, display_name, avatar_url, username)
          ''')
          .or('participant_1_id.eq.$userId,participant_2_id.eq.$userId')
          .order('last_message_at', ascending: false)
          .timeout(_networkTimeout);

      debugPrint('Database response: ${response.length} conversations found');
      // Map to models first
      final baseConversations = (response as List)
          .map((json) => ConversationModel.fromJson(json))
          .toList();

      // Hydrate missing participant info from profile fallbacks
      final List<ConversationModel> hydratedConversations = [];
      for (final conv in baseConversations) {
        Map<String, dynamic>? p1 = conv.participant1Info;
        Map<String, dynamic>? p2 = conv.participant2Info;

        String p1Name = (p1?['display_name'] as String?)?.trim() ?? '';
        String p1User = (p1?['username'] as String?)?.trim() ?? '';
        String p2Name = (p2?['display_name'] as String?)?.trim() ?? '';
        String p2User = (p2?['username'] as String?)?.trim() ?? '';

        // If either participant lacks both display_name and username, fetch profile
        if ((p1Name.isEmpty && p1User.isEmpty) || (p1 == null)) {
          final prof = await SupabaseService.getProfile(conv.participant1Id);
          if (prof != null) {
            p1 = {
              'id': conv.participant1Id,
              'display_name': (prof['display_name'] as String?)?.trim(),
              'username': (prof['username'] as String?)?.trim(),
              'avatar_url': prof['avatar_url'],
            };
          }
        }
        if ((p2Name.isEmpty && p2User.isEmpty) || (p2 == null)) {
          final prof = await SupabaseService.getProfile(conv.participant2Id);
          if (prof != null) {
            p2 = {
              'id': conv.participant2Id,
              'display_name': (prof['display_name'] as String?)?.trim(),
              'username': (prof['username'] as String?)?.trim(),
              'avatar_url': prof['avatar_url'],
            };
          }
        }

        hydratedConversations.add(
          conv.copyWith(participant1Info: p1, participant2Info: p2),
        );
      }

      // Batch fetch last messages to avoid N+1
      final lastIds = hydratedConversations
          .map((c) => c.lastMessageId)
          .whereType<String>()
          .toList();
      Map<String, Map<String, dynamic>> lastMap = {};
      if (lastIds.isNotEmpty) {
        try {
          final lastResp =
              await _supabase
                      .from('messages')
                      .select('id, content, media_type, created_at')
                      .inFilter('id', lastIds)
                      .timeout(_networkTimeout)
                  as List;
          for (final row in lastResp) {
            final id = row['id']?.toString();
            if (id != null) lastMap[id] = Map<String, dynamic>.from(row);
          }
        } catch (e) {
          debugPrint('Batch fetch last messages failed: $e');
        }
      }

      // Enrich with last message content when available
      final List<ConversationModel> enriched = [];
      for (final conv in hydratedConversations) {
        final String? lastId = conv.lastMessageId;
        final info = (lastId != null) ? lastMap[lastId] : null;
        if (info != null) {
          enriched.add(conv.copyWith(lastMessageInfo: info));
        } else {
          enriched.add(conv);
        }
      }

      debugPrint('Conversations prepared: ${enriched.length}');
      return enriched;
    } catch (e) {
      debugPrint('Error getting conversations: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getUsersWhoMessagedMe() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      debugPrint('Getting users who messaged user: $userId');
      if (userId == null) {
        debugPrint('No authenticated user found');
        return [];
      }

      final response = await _supabase
          .from('messages')
          .select('''
            sender_id,
            created_at,
            sender:sender_id(
              id,
              display_name,
              avatar_url,
              username
            ),
            conversation:conversation_id(
              id,
              participant_1_id,
              participant_2_id
            )
          ''')
          .neq('sender_id', userId)
          .order('created_at', ascending: false)
          .timeout(_networkTimeout);

      debugPrint('Messages response: ${response.length} messages found');

      // Filter messages where current user is a participant and get unique senders
      final Map<String, Map<String, dynamic>> uniqueSenders = {};

      for (final message in response) {
        final conversation = message['conversation'];
        final senderId = message['sender_id'];
        final sender = message['sender'];

        // Check if current user is participant in this conversation
        if (conversation != null &&
            (conversation['participant_1_id'] == userId ||
                conversation['participant_2_id'] == userId)) {
          // Add sender to unique list (keep most recent message time)
          if (!uniqueSenders.containsKey(senderId)) {
            final rawDisplayName =
                (sender?['display_name'] as String?)?.trim() ?? '';
            final rawUsername = (sender?['username'] as String?)?.trim() ?? '';
            String effectiveDisplayName = rawDisplayName;
            String effectiveUsername = rawUsername;
            String? effectiveAvatar = sender?['avatar_url'] as String?;

            // Hydrate missing identity using SupabaseService.getProfile
            if (effectiveDisplayName.isEmpty && effectiveUsername.isEmpty) {
              try {
                final profile = await SupabaseService.getProfile(senderId);
                final pDisplay =
                    (profile?['display_name'] as String?)?.trim() ?? '';
                final pUser = (profile?['username'] as String?)?.trim() ?? '';
                effectiveAvatar =
                    profile?['avatar_url'] as String? ?? effectiveAvatar;
                effectiveDisplayName = pDisplay.isNotEmpty
                    ? pDisplay
                    : (pUser.isNotEmpty ? pUser : 'Unknown User');
                effectiveUsername = pUser;
              } catch (_) {}
            } else {
              // Ensure a non-empty display string
              effectiveDisplayName = effectiveDisplayName.isNotEmpty
                  ? effectiveDisplayName
                  : (effectiveUsername.isNotEmpty
                        ? effectiveUsername
                        : 'Unknown User');
            }

            uniqueSenders[senderId] = {
              'id': senderId,
              'display_name': effectiveDisplayName,
              'avatar_url': effectiveAvatar,
              'username': effectiveUsername,
              'last_message_at': message['created_at'],
            };
          }
        }
      }

      final result = uniqueSenders.values.toList();
      debugPrint(
        'Found ${result.length} unique users who messaged current user',
      );

      return result;
    } catch (e) {
      debugPrint('Error getting users who messaged me: $e');
      return [];
    }
  }

  Future<List<MessageModel>> getMessages(
    String conversationId, {
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final response = await _supabase
          .from('messages')
          .select('''
            *,
            sender:sender_id(id, display_name, avatar_url)
          ''')
          .eq('conversation_id', conversationId)
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1)
          .timeout(_networkTimeout);

      return (response as List)
          .map((json) => MessageModel.fromJson(json))
          .toList()
          .reversed
          .toList();
    } catch (e) {
      debugPrint('Error getting messages: $e');
      return [];
    }
  }

  // Send text message
  Future<MessageModel?> sendTextMessage({
    required String conversationId,
    required String content,
  }) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return null;

      final messageData = {
        'conversation_id': conversationId,
        'sender_id': userId,
        'content': content,
        'media_type': 'text',
      };

      final response = await _supabase
          .from('messages')
          .insert(messageData)
          .select()
          .single();

      // Update conversation's last message
      await _updateConversationLastMessage(conversationId, response['id']);

      // Create a unified notification for the recipient so it appears under All
      await _notifyRecipientOfMessage(
        conversationId,
        contentType: 'text',
        contentPreview: content,
      );

      return MessageModel.fromJson(response);
    } catch (e) {
      debugPrint('Error sending text message: $e');
      return null;
    }
  }

  // Start voice recording
  Future<bool> startVoiceRecording() async {
    try {
      if (_isRecording) {
        debugPrint('⚠️ Recording already in progress');
        return false;
      }

      // Check if running on web - voice recording has limitations on web
      if (kIsWeb) {
        debugPrint(
          '🌐 Voice recording is not supported on web browsers due to security restrictions',
        );
        return false;
      }

      // Ensure microphone permission via permission_handler
      final micStatus = await Permission.microphone.status;
      if (!micStatus.isGranted) {
        final requested = await Permission.microphone.request();
        if (!requested.isGranted) {
          debugPrint('❌ Microphone permission not granted: $requested');
          if (requested.isPermanentlyDenied) {
            debugPrint(
              '🔒 Permission permanently denied. Prompting to open app settings.',
            );
            // Optionally open app settings to let user grant permission
            await openAppSettings();
          }
          return false;
        }
      }

      // Double-check via record plugin
      final hasRecordPermission = await _audioRecorder.hasPermission();
      if (!hasRecordPermission) {
        debugPrint('❌ Record plugin reports no permission even after request');
        return false;
      }

      final directory = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      _currentRecordingPath = '${directory.path}/voice_note_$timestamp.m4a';

      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: _currentRecordingPath!,
      );

      _isRecording = true;
      _recordingDuration = 0;
      debugPrint('🎙️ Voice recording started: $_currentRecordingPath');

      // Start timer for recording duration
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (
        timer,
      ) async {
        _recordingDuration++;
        // Auto-stop at 15 seconds
        if (_recordingDuration >= 15) {
          timer.cancel();
          await stopVoiceRecording();
        }
      });

      return true;
    } catch (e) {
      debugPrint('Error starting voice recording: $e');
      return false;
    }
  }

  // Stop voice recording
  Future<String?> stopVoiceRecording() async {
    try {
      if (!_isRecording) {
        // If already stopped (e.g., via auto-stop), return the existing path
        debugPrint(
          'ℹ️ Recording already stopped, path: $_currentRecordingPath',
        );
        return _currentRecordingPath;
      }

      await _audioRecorder.stop();
      _isRecording = false;
      _recordingTimer?.cancel();
      _recordingTimer = null;
      debugPrint('🛑 Voice recording stopped: $_currentRecordingPath');

      return _currentRecordingPath;
    } catch (e) {
      debugPrint('Error stopping voice recording: $e');
      return null;
    }
  }

  // Cancel voice recording
  Future<void> cancelVoiceRecording() async {
    try {
      if (!_isRecording) return;

      await _audioRecorder.stop();
      _isRecording = false;
      _recordingTimer?.cancel();
      _recordingTimer = null;

      // Delete the recording file
      if (_currentRecordingPath != null) {
        final file = File(_currentRecordingPath!);
        if (await file.exists()) {
          await file.delete();
        }
      }
      _currentRecordingPath = null;
    } catch (e) {
      debugPrint('Error canceling voice recording: $e');
    }
  }

  // Send voice message
  Future<MessageModel?> sendVoiceMessage({
    required String conversationId,
    required String audioPath,
  }) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return null;

      // Upload audio using centralized StorageService
      final file = File(audioPath);
      if (!await file.exists()) return null;

      final mediaUrl = await StorageService().uploadAudio(
        audioFile: file,
        userId: userId,
      );

      final messageData = {
        'conversation_id': conversationId,
        'sender_id': userId,
        'content': LocalizationService.t('voice_message'),
        'media_url': mediaUrl,
        'media_type': 'voice',
      };

      final response = await _supabase
          .from('messages')
          .insert(messageData)
          .select()
          .single();

      // Update conversation's last message
      await _updateConversationLastMessage(conversationId, response['id']);

      // Create notification to unify message under All
      await _notifyRecipientOfMessage(conversationId, contentType: 'voice');

      // Delete local file
      await file.delete();

      return MessageModel.fromJson(response);
    } catch (e) {
      debugPrint('Error sending voice message: $e');
      return null;
    }
  }

  // Send voice message from web bytes (web-compatible)
  Future<MessageModel?> sendVoiceMessageBytes({
    required String conversationId,
    required Uint8List audioBytes,
    required String fileName,
  }) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return null;

      // Upload audio using centralized StorageService with web bytes
      final mediaUrl = await StorageService().uploadAudio(
        audioFile: null,
        userId: userId,
        audioBytes: audioBytes,
        fileName: fileName,
      );

      final messageData = {
        'conversation_id': conversationId,
        'sender_id': userId,
        'content': LocalizationService.t('voice_message'),
        'media_url': mediaUrl,
        'media_type': 'voice',
      };

      final response = await _supabase
          .from('messages')
          .insert(messageData)
          .select()
          .single();

      // Update conversation's last message
      await _updateConversationLastMessage(conversationId, response['id']);

      // Create notification to unify message under All
      await _notifyRecipientOfMessage(conversationId, contentType: 'voice');

      return MessageModel.fromJson(response);
    } catch (e) {
      debugPrint('Error sending voice message from bytes: $e');
      return null;
    }
  }

  // Send image message from XFile (supports both web and mobile)
  Future<MessageModel?> sendImageMessageFromFile({
    required String conversationId,
    required XFile imageFile,
  }) async {
    try {
      debugPrint('🔄 Starting image upload process...');

      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('❌ User not authenticated');
        return null;
      }
      debugPrint('✅ User authenticated: $userId');

      final fileName = '$userId/${DateTime.now().millisecondsSinceEpoch}.jpg';
      debugPrint('📁 Upload filename: $fileName');

      String uploadResponse;

      if (kIsWeb) {
        debugPrint('🌐 Web platform detected, uploading bytes...');
        // For web, upload using bytes
        final bytes = await imageFile.readAsBytes();
        debugPrint('📊 Image size: ${bytes.length} bytes');

        uploadResponse = await _supabase.storage
            .from('post-images')
            .uploadBinary(fileName, bytes);
      } else {
        debugPrint('📱 Mobile platform detected, uploading file...');
        // For mobile, upload using file
        final file = File(imageFile.path);
        if (!await file.exists()) {
          debugPrint('❌ File does not exist: ${imageFile.path}');
          return null;
        }

        uploadResponse = await _supabase.storage
            .from('post-images')
            .upload(fileName, file);
      }

      debugPrint('📤 Upload response: $uploadResponse');
      if (uploadResponse.isEmpty) {
        debugPrint('❌ Upload response is empty');
        return null;
      }

      // Get public URL
      final mediaUrl = _supabase.storage
          .from('post-images')
          .getPublicUrl(fileName);
      debugPrint('🔗 Public URL: $mediaUrl');

      final messageData = {
        'conversation_id': conversationId,
        'sender_id': userId,
        'content': 'Image',
        'media_url': mediaUrl,
        'media_type': 'image',
      };
      debugPrint('💾 Inserting message data: $messageData');

      final response = await _supabase
          .from('messages')
          .insert(messageData)
          .select()
          .single();
      debugPrint('✅ Message inserted: ${response['id']}');

      // Update conversation's last message
      await _updateConversationLastMessage(conversationId, response['id']);
      debugPrint('✅ Conversation updated');

      return MessageModel.fromJson(response);
    } catch (e) {
      debugPrint('❌ Error sending image message: $e');
      debugPrint('❌ Error type: ${e.runtimeType}');
      if (e.toString().contains('403')) {
        debugPrint('🔧 This appears to be a Row Level Security policy issue.');
        debugPrint(
          '🔧 Please ensure storage policies are applied in Supabase Dashboard.',
        );
      }
      return null;
    }
  }

  // Send image message (legacy method for backward compatibility)
  Future<MessageModel?> sendImageMessage({
    required String conversationId,
    required String imagePath,
  }) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return null;

      // Upload image file to Supabase storage
      final file = File(imagePath);
      if (!await file.exists()) return null;

      final fileName = '$userId/${DateTime.now().millisecondsSinceEpoch}.jpg';
      final uploadResponse = await _supabase.storage
          .from('post-images')
          .upload(fileName, file);

      if (uploadResponse.isEmpty) return null;

      // Get public URL
      final mediaUrl = _supabase.storage
          .from('post-images')
          .getPublicUrl(fileName);

      final messageData = {
        'conversation_id': conversationId,
        'sender_id': userId,
        'content': 'Image',
        'media_url': mediaUrl,
        'media_type': 'image',
      };

      final response = await _supabase
          .from('messages')
          .insert(messageData)
          .select()
          .single();

      // Update conversation's last message
      await _updateConversationLastMessage(conversationId, response['id']);

      // Create notification to unify message under All
      await _notifyRecipientOfMessage(conversationId, contentType: 'image');

      return MessageModel.fromJson(response);
    } catch (e) {
      debugPrint('Error sending image message: $e');
      return null;
    }
  }

  // Play voice message (URL)
  Future<void> playVoiceMessage(String audioUrl) async {
    try {
      await _audioPlayer.play(UrlSource(audioUrl));
    } catch (e) {
      debugPrint('Error playing voice message: $e');
    }
  }

  // Play voice message from local file path
  Future<void> playLocalVoiceMessage(String filePath) async {
    try {
      await _audioPlayer.play(DeviceFileSource(filePath));
    } catch (e) {
      debugPrint('Error playing local voice message: $e');
    }
  }

  // Stop playing voice message
  Future<void> stopPlayingVoiceMessage() async {
    try {
      await _audioPlayer.stop();
    } catch (e) {
      debugPrint('Error stopping voice message: $e');
    }
  }

  // Expose player streams so UI layers (e.g., comments) can mirror messaging behavior
  Stream<Duration> get positionStream => _audioPlayer.onPositionChanged;
  Stream<Duration> get durationStream => _audioPlayer.onDurationChanged;
  Stream<PlayerState> get playerStateStream =>
      _audioPlayer.onPlayerStateChanged;
  Stream<void> get completedStream => _audioPlayer.onPlayerComplete;

  // Mark messages as read
  Future<void> markMessagesAsRead(String conversationId) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) {
        throw Exception('User not authenticated');
      }

      // Respect user's Read Receipts preference
      final allowReceipts = await _preferencesService.getShowReadReceipts();
      if (!allowReceipts) {
        if (kDebugMode) {
          debugPrint(
            'Read receipts disabled; skipping markMessagesAsRead for conversation $conversationId',
          );
        }
        return;
      }

      final updated = await _supabase
          .from('messages')
          .update({'is_read': true})
          .eq('conversation_id', conversationId)
          .neq('sender_id', currentUserId)
          .eq('is_read', false)
          .select('id');

      if (kDebugMode) {
        final count = (updated as List).length;
        debugPrint(
          'markMessagesAsRead: conversation=$conversationId user=$currentUserId updated=$count messages',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error marking messages as read: $e');
      }
      rethrow;
    }
  }

  // Force mark messages as read regardless of the Read Receipts preference (used for "Mark all read")
  Future<void> forceMarkMessagesAsRead(String conversationId) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) {
        throw Exception('User not authenticated');
      }

      final updated = await _supabase
          .from('messages')
          .update({'is_read': true})
          .eq('conversation_id', conversationId)
          .neq('sender_id', currentUserId)
          .eq('is_read', false)
          .select('id');

      if (kDebugMode) {
        final count = (updated as List).length;
        debugPrint(
          'forceMarkMessagesAsRead: conversation=$conversationId user=$currentUserId updated=$count messages',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error force marking messages as read: $e');
      }
      rethrow;
    }
  }

  // Get unread message count for a conversation
  Future<int> getUnreadMessageCount(String conversationId) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return 0;

      final result = await _supabase
          .from('messages')
          .select('*')
          .eq('conversation_id', conversationId)
          .neq('sender_id', userId)
          .eq('is_read', false);

      final count = (result as List).length;
      if (kDebugMode) {
        debugPrint(
          'getUnreadMessageCount: conversation=$conversationId user=$userId unread=$count',
        );
      }
      return count;
    } catch (e) {
      debugPrint('Error getting unread message count: $e');
      return 0;
    }
  }

  // Update conversation's last message
  Future<void> _updateConversationLastMessage(
    String conversationId,
    String messageId,
  ) async {
    try {
      await _supabase
          .from('conversations')
          .update({
            'last_message_id': messageId,
            'last_message_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', conversationId);
    } catch (e) {
      debugPrint('Error updating conversation last message: $e');
    }
  }

  // Create a notification record for the recipient so messages show under the All tab
  Future<void> _notifyRecipientOfMessage(
    String conversationId, {
    required String contentType,
    String? contentPreview,
  }) async {
    try {
      final senderId = _supabase.auth.currentUser?.id;
      if (senderId == null) return;

      // Find the recipient (the other participant in the conversation)
      final conv = await _supabase
          .from('conversations')
          .select('participant_1_id, participant_2_id')
          .eq('id', conversationId)
          .maybeSingle();
      if (conv == null) return;

      final recipientId = (conv['participant_1_id'] == senderId)
          ? conv['participant_2_id']
          : conv['participant_1_id'];
      if (recipientId == null || recipientId == senderId) return;

      // Resolve sender display name/username for nicer notification text
      String? senderDisplayName;
      String? senderUsername;
      try {
        final user = await _supabase
            .from('users')
            .select('display_name, username')
            .eq('id', senderId)
            .maybeSingle();
        if (user != null) {
          final dn = (user['display_name'] as String?)?.trim() ?? '';
          final un = (user['username'] as String?)?.trim() ?? '';
          senderDisplayName = dn.isNotEmpty ? dn : null;
          senderUsername = un.isNotEmpty ? un : null;
        }
      } catch (_) {}

      final effectiveName = senderDisplayName ?? senderUsername ?? 'Someone';
      String messageText;
      switch (contentType) {
        case 'text':
          final preview = (contentPreview ?? '').trim();
          final truncated = preview.length > 80
              ? '${preview.substring(0, 80)}…'
              : preview;
          messageText = truncated.isNotEmpty
              ? '$effectiveName: $truncated'
              : '$effectiveName ${LocalizationService.t('sent_you_a_message')}';
          break;
        case 'voice':
          messageText =
              '$effectiveName ${LocalizationService.t('sent_voice_message')}';
          break;
        case 'image':
          messageText =
              '$effectiveName ${LocalizationService.t('sent_a_photo')}';
          break;
        default:
          messageText =
              '$effectiveName ${LocalizationService.t('sent_you_a_message')}';
      }

      // Insert unified notification for the recipient
      await EnhancedNotificationService().createNotification(
        userId: recipientId as String,
        type: 'message',
        title: LocalizationService.t('new_message_title'),
        message: messageText,
        data: {
          'conversation_id': conversationId,
          'sender_id': senderId,
          'sender_username': senderUsername,
          'action_type': 'message',
        },
      );
    } catch (e) {
      debugPrint('Error creating message notification: $e');
    }
  }

  // Get recording status
  bool get isRecording => _isRecording;
  int get recordingDuration => _recordingDuration;

  // Delete a message
  Future<bool> deleteMessage({
    required String messageId,
    required String conversationId,
  }) async {
    try {
      // Delete the message row
      await _supabase.from('messages').delete().eq('id', messageId);

      // Update conversation's last message to latest remaining
      final latest = await _supabase
          .from('messages')
          .select('id, created_at')
          .eq('conversation_id', conversationId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      await _supabase
          .from('conversations')
          .update({
            'last_message_id': latest?['id'],
            'last_message_at': latest?['created_at'],
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', conversationId);

      return true;
    } catch (e) {
      debugPrint('Error deleting message: $e');
      return false;
    }
  }

  // Dispose resources
  void dispose() {
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    _recordingTimer?.cancel();
    _messageController.close();
    _conversationController.close();

    // Unsubscribe from all channels
    for (final channel in _conversationChannels.values) {
      channel.unsubscribe();
    }
    _conversationChannels.clear();
  }
}
