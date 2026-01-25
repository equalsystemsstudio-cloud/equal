import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'enhanced_messaging_service.dart';
import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';
import 'live_streaming_service.dart' show fetchLiveKitToken;
import 'push_notification_service.dart';
import '../config/feature_flags.dart';

enum CallType { audio, video }

enum CallStatus { calling, ringing, connected, ended, declined, missed }

class CallModel {
  final String id;
  final String callerId;
  final String receiverId;
  final String callerName;
  final String receiverName;
  final String? callerAvatar;
  final String? receiverAvatar;
  final CallType type;
  final CallStatus status;
  final DateTime startedAt;
  final DateTime? answeredAt;
  final DateTime? endedAt;
  final int durationSeconds;

  CallModel({
    required this.id,
    required this.callerId,
    required this.receiverId,
    required this.callerName,
    required this.receiverName,
    this.callerAvatar,
    this.receiverAvatar,
    required this.type,
    required this.status,
    required this.startedAt,
    this.answeredAt,
    this.endedAt,
    this.durationSeconds = 0,
  });

  factory CallModel.fromMap(Map<String, dynamic> map) {
    // Robust parsing to prevent runtime crashes on missing/typed fields
    try {
      final String id = (map['id'] ?? '').toString();
      final String callerId = (map['caller_id'] ?? map['callerId'] ?? '')
          .toString();
      final String receiverId = (map['receiver_id'] ?? map['receiverId'] ?? '')
          .toString();
      final String callerName =
          (map['caller_name'] ?? map['callerName'] ?? 'Unknown').toString();
      final String receiverName =
          (map['receiver_name'] ?? map['receiverName'] ?? 'Unknown').toString();

      final String? callerAvatar = map['caller_avatar']?.toString();
      final String? receiverAvatar = map['receiver_avatar']?.toString();

      // Type/status may be enums serialized as strings or already matching names
      final String typeStr = (map['type'] ?? 'audio').toString();
      final CallType type = CallType.values.firstWhere(
        (e) => e.name == typeStr,
        orElse: () => CallType.audio,
      );

      final String statusStr = (map['status'] ?? 'calling').toString();
      final CallStatus status = CallStatus.values.firstWhere(
        (e) => e.name == statusStr,
        orElse: () => CallStatus.calling,
      );

      // Timestamps may be String ISO, DateTime, or null
      DateTime parseDate(dynamic v, {DateTime? fallback}) {
        if (v == null) return fallback ?? DateTime.now();
        if (v is DateTime) return v;
        if (v is String && v.isNotEmpty) {
          try {
            return DateTime.parse(v);
          } catch (_) {
            return fallback ?? DateTime.now();
          }
        }
        return fallback ?? DateTime.now();
      }

      final DateTime startedAt = parseDate(map['started_at']);
      final DateTime? answeredAt = map['answered_at'] != null
          ? parseDate(map['answered_at'], fallback: null)
          : null;
      final DateTime? endedAt = map['ended_at'] != null
          ? parseDate(map['ended_at'], fallback: null)
          : null;

      final int durationSeconds = (map['duration_seconds'] is num)
          ? (map['duration_seconds'] as num).toInt()
          : int.tryParse((map['duration_seconds'] ?? '0').toString()) ?? 0;

      return CallModel(
        id: id,
        callerId: callerId,
        receiverId: receiverId,
        callerName: callerName,
        receiverName: receiverName,
        callerAvatar: callerAvatar,
        receiverAvatar: receiverAvatar,
        type: type,
        status: status,
        startedAt: startedAt,
        answeredAt: answeredAt,
        endedAt: endedAt,
        durationSeconds: durationSeconds,
      );
    } catch (e) {
      // Fail-safe: return a minimal model to avoid crashing the app
      debugPrint(('CallModel.fromMap parse error: $e; map: $map').toString());
      return CallModel(
        id: (map['id'] ?? '').toString(),
        callerId: (map['caller_id'] ?? '').toString(),
        receiverId: (map['receiver_id'] ?? '').toString(),
        callerName: (map['caller_name'] ?? 'Unknown').toString(),
        receiverName: (map['receiver_name'] ?? 'Unknown').toString(),
        callerAvatar: map['caller_avatar']?.toString(),
        receiverAvatar: map['receiver_avatar']?.toString(),
        type: CallType.audio,
        status: CallStatus.calling,
        startedAt: DateTime.now(),
        answeredAt: null,
        endedAt: null,
        durationSeconds: 0,
      );
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'caller_id': callerId,
      'receiver_id': receiverId,
      'caller_name': callerName,
      'receiver_name': receiverName,
      'caller_avatar': callerAvatar,
      'receiver_avatar': receiverAvatar,
      'type': type.name,
      'status': status.name,
      'started_at': startedAt.toIso8601String(),
      'answered_at': answeredAt?.toIso8601String(),
      'ended_at': endedAt?.toIso8601String(),
      'duration_seconds': durationSeconds,
    };
  }
}

class CallingService {
  static final CallingService _instance = CallingService._internal();
  factory CallingService() => _instance;
  CallingService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;
  final StreamController<CallModel> _callStreamController =
      StreamController<CallModel>.broadcast();

  Stream<CallModel> get callStream => _callStreamController.stream;
  RealtimeChannel? _callSubscription;
  CallModel? _currentCall;
  Timer? _callTimer;
  int _callDuration = 0;
  String? _currentUserId;
  Room? _lkRoom;
  LocalAudioTrack? _lkAudioTrack;
  LocalVideoTrack? _lkVideoTrack;
  // New: expose last error for UI feedback
  String? lastRtcError;

  Room? get liveKitRoom => _lkRoom;
  LocalVideoTrack? get liveKitLocalVideoTrack => _lkVideoTrack;

  // Initialize calling service
  Future<void> initialize(String userId) async {
    _currentUserId = userId;

    // Listen for call updates
    try {
      _callSubscription = _supabase
          .channel('calls')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'calls',
            callback: (payload) {
              final callData = payload.newRecord;
              final call = CallModel.fromMap(callData);
              // Only emit calls related to current user
              if (call.callerId == _currentUserId ||
                  call.receiverId == _currentUserId) {
                _callStreamController.add(call);
              }
            },
          )
          .subscribe();
    } catch (e) {
      // Prevent app crash if calls table is missing (PGRST205)
      // Calling features will remain disabled until backend migration is applied
      // See supabase/migrations/20241201000000_create_calls_table.sql
      // for the required table and indexes
      // ignore: avoid_print
      debugPrint(('Failed to subscribe to calls channel: $e').toString());
    }
  }

  // Start RTC (LiveKit) for a specific call
  Future<bool> startRtcForCall(CallModel call) async {
    lastRtcError = null;
    try {
      if (_lkRoom != null) {
        return true; // already started
      }
      final user = _supabase.auth.currentUser;
      if (user == null) {
        lastRtcError = 'No authenticated user';
        debugPrint('CallingService: cannot start RTC, no auth user');
        return false;
      }
      final roomName = 'call-${call.id}';
      final tokenData = await fetchLiveKitToken(
        room: roomName,
        identity: user.id,
        name: user.userMetadata?['display_name'] ?? user.email ?? user.id,
        canPublish: true,
        canSubscribe: true,
        canPublishData: true,
        ttlSeconds: 600,
        metadata: {'role': 'caller_receiver', 'call_id': call.id},
      );
      var url = tokenData['url'] as String;
      final token = tokenData['token'] as String;

      // Enforce websocket scheme for web
      if (url.startsWith('http://')) {
        url = url.replaceFirst('http://', 'ws://');
      } else if (url.startsWith('https://')) {
        url = url.replaceFirst('https://', 'wss://');
      }

      final room = Room();
      await room.connect(url, token);
      _lkRoom = room;

      // Publish audio track for both voice/video calls
      try {
        final localAudio = await LocalAudioTrack.create(
          const AudioCaptureOptions(),
        );
        await room.localParticipant?.publishAudioTrack(localAudio);
        _lkAudioTrack = localAudio;
        debugPrint('CallingService: published microphone track');
      } catch (e) {
        debugPrint(
          'CallingService: failed to publish audio track: ${e.toString()}',
        );
      }

      // Publish camera track for video calls
      if (call.type == CallType.video) {
        try {
          final localVideo = await LocalVideoTrack.createCameraTrack(
            const CameraCaptureOptions(),
          );
          await room.localParticipant?.publishVideoTrack(localVideo);
          _lkVideoTrack = localVideo;
          debugPrint('CallingService: published camera track');
        } catch (e) {
          debugPrint(
            'CallingService: failed to publish video track: ${e.toString()}',
          );
        }
      }
      return true;
    } catch (e) {
      lastRtcError = e.toString();
      debugPrint(('CallingService: startRtcForCall error: $e').toString());
      return false;
    }
  }

  Future<void> endRtcForCurrentCall() async {
    try {
      final room = _lkRoom;
      _lkRoom = null;
      try {
        await room?.disconnect();
      } catch (_) {}
      try {
        await _lkAudioTrack?.stop();
        await _lkAudioTrack?.dispose();
      } catch (_) {}
      _lkAudioTrack = null;
      try {
        await _lkVideoTrack?.stop();
        await _lkVideoTrack?.dispose();
      } catch (_) {}
      _lkVideoTrack = null;
    } catch (e) {
      debugPrint(('CallingService: endRtcForCurrentCall error: $e').toString());
    }
  }

  Future<void> setLiveKitMicrophoneEnabled(bool enabled) async {
    final participant = _lkRoom?.localParticipant;
    if (participant == null) {
      debugPrint(
        'CallingService: setMicrophoneEnabled ignored (no active room/participant)',
      );
      return;
    }
    try {
      await participant.setMicrophoneEnabled(enabled);
      debugPrint(
        'CallingService: microphone ${enabled ? 'enabled' : 'disabled'}',
      );
    } catch (e) {
      debugPrint('CallingService: setMicrophoneEnabled error: ${e.toString()}');
    }
  }

  Future<void> setLiveKitCameraEnabled(bool enabled) async {
    final participant = _lkRoom?.localParticipant;
    if (participant == null) {
      debugPrint(
        'CallingService: setCameraEnabled ignored (no active room/participant)',
      );
      return;
    }
    try {
      await participant.setCameraEnabled(enabled);
      debugPrint('CallingService: camera ${enabled ? 'enabled' : 'disabled'}');
    } catch (e) {
      debugPrint('CallingService: setCameraEnabled error: ${e.toString()}');
    }
  }

  // Initiate a new call
  Future<CallModel?> initiateCall({
    required String receiverId,
    required String receiverName,
    required CallType type,
  }) async {
    try {
      // Respect feature flag: disable call initiation when calls are disabled
      if (!FeatureFlags.callsEnabled) {
        if (kDebugMode) {
          debugPrint('CallingService: calls disabled, initiateCall ignored');
        }
        return null;
      }
      final currentUser = _supabase.auth.currentUser;
      if (currentUser == null) return null;

      final callData = {
        'caller_id': currentUser.id,
        'receiver_id': receiverId,
        'caller_name': currentUser.userMetadata?['display_name'] ?? 'Unknown',
        'receiver_name': receiverName,
        'type': type.name,
        'status': CallStatus.calling.name,
        'started_at': DateTime.now().toIso8601String(),
      };

      final response = await _supabase
          .from('calls')
          .insert(callData)
          .select()
          .single();

      final call = CallModel.fromMap(response);

      // Fire a push notification so the receiver's device rings even if app is background/locked
      try {
        final callerDisplayName =
            currentUser.userMetadata?['display_name'] ??
            currentUser.email ??
            'Someone';
        await PushNotificationService().sendNotificationToUser(
          userId: receiverId,
          title: 'Incoming call',
          body: '$callerDisplayName is calling you',
          type: 'incoming_call',
          data: {
            'call_id': call.id,
            'caller_name': callerDisplayName,
            'type': type.name,
          },
        );
      } catch (e) {
        if (kDebugMode) {
          debugPrint('initiateCall: failed to send incoming_call push: $e');
        }
      }

      return call;
    } catch (e) {
      debugPrint(('Error initiating call: $e').toString());
      return null;
    }
  }

  // Answer an incoming call
  Future<bool> answerCall(String callId) async {
    try {
      await _supabase
          .from('calls')
          .update({
            'status': CallStatus.connected.name,
            'answered_at': DateTime.now().toIso8601String(),
          })
          .eq('id', callId);

      _startCallTimer();
      return true;
    } catch (e) {
      debugPrint(('Error answering call: $e').toString());
      return false;
    }
  }

  // Decline an incoming call
  Future<bool> declineCall(String callId) async {
    try {
      await _supabase
          .from('calls')
          .update({
            'status': CallStatus.declined.name,
            'ended_at': DateTime.now().toIso8601String(),
          })
          .eq('id', callId);

      return true;
    } catch (e) {
      debugPrint(('Error declining call: $e').toString());
      return false;
    }
  }

  // End an active call
  Future<bool> endCall(String callId) async {
    try {
      await _supabase
          .from('calls')
          .update({
            'status': CallStatus.ended.name,
            'ended_at': DateTime.now().toIso8601String(),
            'duration_seconds': _callDuration,
          })
          .eq('id', callId);

      _stopCallTimer();
      await endRtcForCurrentCall();
      return true;
    } catch (e) {
      debugPrint(('Error ending call: $e').toString());
      return false;
    }
  }

  // Start call duration timer
  void _startCallTimer() {
    _callDuration = 0;
    _callTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _callDuration++;
    });
  }

  // Stop call duration timer
  void _stopCallTimer() {
    _callTimer?.cancel();
    _callTimer = null;
  }

  // Get formatted call duration
  String get formattedCallDuration {
    final minutes = _callDuration ~/ 60;
    final seconds = _callDuration % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  // Get current call
  CallModel? get currentCall => _currentCall;

  // Dispose resources
  void dispose() {
    _callSubscription?.unsubscribe();
    _callTimer?.cancel();
    _callStreamController.close();
    // Ensure RTC is cleaned up
    // ignore: discarded_futures
    endRtcForCurrentCall();
  }

  // Mark a call as missed if not answered and leave a "Missed call" message in chat
  Future<bool> markMissedCallAndNotify(String callId) async {
    try {
      // Fetch latest call state
      final callRecord = await _supabase
          .from('calls')
          .select(
            'id, caller_id, receiver_id, status, answered_at, started_at, ended_at',
          )
          .eq('id', callId)
          .maybeSingle();
      if (callRecord == null) return false;

      final String status =
          (callRecord['status'] as String?) ?? CallStatus.calling.name;
      final bool answered = callRecord['answered_at'] != null;

      // Only mark missed if not answered and still pending
      if (!answered &&
          (status == CallStatus.calling.name ||
              status == CallStatus.ringing.name)) {
        await _supabase
            .from('calls')
            .update({
              'status': CallStatus.missed.name,
              'ended_at': DateTime.now().toIso8601String(),
              'duration_seconds': 0,
            })
            .eq('id', callId);

        // Leave a "Missed call" message in the conversation between participants
        final currentUserId = _supabase.auth.currentUser?.id;
        final String callerId = callRecord['caller_id'] as String;
        final String receiverId = callRecord['receiver_id'] as String;
        final String otherUserId = (currentUserId == callerId)
            ? receiverId
            : callerId;

        // Only the caller should send the missed call message to avoid duplicates
        final bool isCallerDevice = currentUserId == callerId;
        if (!isCallerDevice) {
          return true; // Status updated; skip sending message
        }

        // Try via messaging service first (respects preferences)
        final messaging = EnhancedMessagingService();
        final conversation = await messaging.getOrCreateConversation(
          otherUserId,
        );
        String? conversationId = conversation?.id;

        // Fallback: force create/find conversation ignoring preferences
        if (conversationId == null) {
          // Check if conversation already exists
          final existing = await _supabase
              .from('conversations')
              .select('id')
              .or(
                'and(participant_1_id.eq.$currentUserId,participant_2_id.eq.$otherUserId),and(participant_1_id.eq.$otherUserId,participant_2_id.eq.$currentUserId)',
              )
              .maybeSingle();
          if (existing != null) {
            conversationId = existing['id'] as String?;
          } else {
            // Create new conversation without gating
            final created = await _supabase
                .from('conversations')
                .insert({
                  'participant_1_id': currentUserId,
                  'participant_2_id': otherUserId,
                })
                .select('id')
                .single();
            conversationId = created['id'] as String?;
          }
        }

        if (conversationId != null) {
          await messaging.sendTextMessage(
            conversationId: conversationId,
            content: 'Missed call',
          );
        }
        return true;
      }

      // Already answered or finished; nothing to do
      return false;
    } catch (e) {
      debugPrint(('Error marking missed call: $e').toString());
      return false;
    }
  }
}
