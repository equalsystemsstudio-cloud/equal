import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import '../config/supabase_config.dart';
import '../config/api_config.dart';
import 'auth_service.dart';
// import 'jitsi_meet_service.dart'; // removed
import 'package:livekit_client/livekit_client.dart';
import 'preferences_service.dart';
import 'social_service.dart';
import '../services/supabase_service.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart'
    show
        MediaStream,
        navigator,
        RTCPeerConnection,
        RTCSessionDescription,
        RTCIceCandidate,
        createPeerConnection;

class LiveStreamingService {
  static final LiveStreamingService _instance =
      LiveStreamingService._internal();
  factory LiveStreamingService() => _instance;
  LiveStreamingService._internal();

  final SupabaseClient _client = SupabaseConfig.client;
  final AuthService _authService = AuthService();
  // final JitsiMeetService _jitsiService = JitsiMeetService(); // removed
  final PreferencesService _preferencesService = PreferencesService();

  // Stream controllers for real-time updates
  final _chatController = StreamController<Map<String, dynamic>>.broadcast();
  final _viewersController =
      StreamController<List<Map<String, dynamic>>>.broadcast();
  final _reactionsController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _streamStatusController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _giftsController = StreamController<Map<String, dynamic>>.broadcast();
  final _giftLeaderboardController =
      StreamController<List<Map<String, dynamic>>>.broadcast();
  final Map<String, int> _giftTotals = {};

  // Getters for streams
  Stream<Map<String, dynamic>> get chatStream => _chatController.stream;
  Stream<List<Map<String, dynamic>>> get viewersStream =>
      _viewersController.stream;
  Stream<Map<String, dynamic>> get reactionsStream =>
      _reactionsController.stream;
  Stream<Map<String, dynamic>> get streamStatusStream =>
      _streamStatusController.stream;
  Stream<Map<String, dynamic>> get giftsStream => _giftsController.stream;
  Stream<List<Map<String, dynamic>>> get giftLeaderboardStream =>
      _giftLeaderboardController.stream;

  // Real-time channels
  RealtimeChannel? _streamChannel;
  RealtimeChannel? _chatChannel;
  RealtimeChannel? _presenceChannel;

  // Current stream state
  String? _currentStreamId;
  bool _isStreaming = false;
  int _viewerCount = 0;
  List<Map<String, dynamic>> _viewers = [];
  final List<Map<String, dynamic>> _chatMessages = [];
  Room? _lkRoom; // LiveKit room reference
  // LiveKit local tracks and publications
  LocalVideoTrack? _lkVideoTrack;
  LocalAudioTrack? _lkAudioTrack;
  String? _lkVideoTrackSid;
  String? _lkAudioTrackSid;
  // Prevent late events after teardown
  bool _isDisposed = false;

  // Listener for reacting to Show Online Status preference changes while viewing a stream
  VoidCallback? _presencePreferenceListener;

  // Expose LiveKit references for UI
  Room? get liveKitRoom => _lkRoom;
  LocalVideoTrack? get liveKitLocalVideoTrack => _lkVideoTrack;
  LocalAudioTrack? get liveKitLocalAudioTrack => _lkAudioTrack;
  String? get liveKitLocalAudioTrackSid => _lkAudioTrackSid;

  // Zego token helpers for host and viewer
  Future<String> zegoHostTokenForCurrentUser({
    required String roomId,
    List<String>? streamIdList,
    int effectiveTimeInSeconds = 3600,
  }) async {
    final uid = _authService.currentUser?.id;
    if (uid == null || uid.isEmpty) {
      throw Exception('Not authenticated');
    }
    final res = await SupabaseService.invokeFunction(
      name: 'zego_token',
      body: {
        'user_id': uid,
        'role': 'host',
        'room_id': roomId,
        if (streamIdList != null) 'stream_id_list': streamIdList,
        'effective_time_in_seconds': effectiveTimeInSeconds,
      },
      method: 'POST',
    );
    final token = res['token'] as String?;
    if (token == null || token.isEmpty) {
      throw Exception('Failed to fetch Zego host token');
    }
    return token;
  }

  Future<String> zegoViewerTokenForCurrentUser({
    required String roomId,
    int effectiveTimeInSeconds = 3600,
  }) async {
    final uid = _authService.currentUser?.id;
    if (uid == null || uid.isEmpty) {
      throw Exception('Not authenticated');
    }
    final res = await SupabaseService.invokeFunction(
      name: 'zego_token',
      body: {
        'user_id': uid,
        'role': 'viewer',
        'room_id': roomId,
        'effective_time_in_seconds': effectiveTimeInSeconds,
      },
      method: 'POST',
    );
    final token = res['token'] as String?;
    if (token == null || token.isEmpty) {
      throw Exception('Failed to fetch Zego viewer token');
    }
    return token;
  }

  // LiveKit mid-stream toggles (camera/microphone)
  Future<void> setLiveKitCameraEnabled(bool enabled) async {
    final participant = _lkRoom?.localParticipant;
    if (participant == null) {
      debugPrint(
        'LiveKit: setCameraEnabled ignored (no active room/participant)',
      );
      return;
    }
    try {
      await participant.setCameraEnabled(enabled);
      debugPrint('LiveKit: camera ${enabled ? 'enabled' : 'disabled'}');
      // Update stored SID reference heuristically
      if (!enabled) {
        _lkVideoTrackSid = null;
      } else {
        // Use getTrackPublicationBySource for compatibility across SDK versions
        final pub = participant.getTrackPublicationBySource(TrackSource.camera);
        _lkVideoTrackSid = pub?.sid;
      }
    } catch (e) {
      debugPrint('LiveKit: setCameraEnabled error: ${e.toString()}');
    }
  }

  Future<void> setLiveKitMicrophoneEnabled(bool enabled) async {
    final participant = _lkRoom?.localParticipant;
    if (participant == null) {
      debugPrint(
        'LiveKit: setMicrophoneEnabled ignored (no active room/participant)',
      );
      return;
    }
    try {
      await participant.setMicrophoneEnabled(enabled);
      debugPrint('LiveKit: microphone ${enabled ? 'enabled' : 'disabled'}');
      if (!enabled) {
        _lkAudioTrackSid = null;
      } else {
        // Use getTrackPublicationBySource for compatibility across SDK versions
        final pub = participant.getTrackPublicationBySource(
          TrackSource.microphone,
        );
        _lkAudioTrackSid = pub?.sid;
      }
    } catch (e) {
      debugPrint('LiveKit: setMicrophoneEnabled error: ${e.toString()}');
    }
  }

  // Supabase-only: switch camera facing with renegotiation to all viewers
  Future<void> switchSupabaseCameraFacing({required bool useFront}) async {
    try {
      if (!_isStreaming || _rtcLocalStream == null) {
        if (kDebugMode) {
          debugPrint(
            'SupabaseRTC: switch camera ignored - no active local stream',
          );
        }
        return;
      }

      final MediaStream? oldStream = _rtcLocalStream;

      // Try several constraint sets to maximize compatibility across devices
      final constraintCandidates = [
        {
          'audio': true,
          'video': {
            'facingMode': useFront ? 'user' : 'environment',
            'width': {'ideal': 1280},
            'height': {'ideal': 720},
          },
        },
        {
          'audio': true,
          'video': {'facingMode': useFront ? 'user' : 'environment'},
        },
        {'audio': true, 'video': true},
      ];

      dynamic lastError;
      MediaStream? newStream;
      for (final c in constraintCandidates) {
        try {
          newStream = await navigator.mediaDevices.getUserMedia(c);
          if (newStream != null) {
            if (kDebugMode) {
              debugPrint(
                'SupabaseRTC: switched camera with constraints: ${c.toString()}',
              );
            }
            break;
          }
        } catch (e) {
          lastError = e;
          final err = e.toString().toLowerCase();
          final isPermissionOrSecurity =
              err.contains('permission') ||
              err.contains('denied') ||
              err.contains('notallowederror') ||
              err.contains('security') ||
              err.contains('blocked') ||
              err.contains('insecure');
          if (isPermissionOrSecurity) {
            throw Exception(
              'Could not access camera/microphone while switching. Please grant permissions. Details: $e',
            );
          }
        }
      }

      if (newStream == null) {
        throw Exception(
          'Unable to switch camera. Details: ${lastError?.toString() ?? 'Unknown error'}',
        );
      }

      // Replace local stream and stop old tracks
      _rtcLocalStream = newStream;
      try {
        final tracks = [
          ...?oldStream?.getVideoTracks(),
          ...?oldStream?.getAudioTracks(),
        ];
        for (final t in tracks) {
          t.stop();
        }
      } catch (_) {}

      // Notify UI to rebind preview immediately
      _streamStatusController.add({'type': 'local_stream_updated'});

      // Renegotiate with all active viewer peer connections
      for (final entry in _rtcPublisherPcs.entries.toList()) {
        final viewerId = entry.key;
        final pc = entry.value;
        try {
          // Best-effort remove previous stream (older SDKs use addStream/removeStream)
          // ignore: deprecated_member_use
          if (oldStream != null) {
            // ignore: deprecated_member_use
            pc.removeStream(oldStream);
          }
          pc.addStream(newStream);

          final offer = await pc.createOffer();
          await pc.setLocalDescription(offer);
          await _broadcastToStream({
            'type': 'publisher_offer',
            'viewer_id': viewerId,
            'sdp': offer.sdp,
            'sdp_type': offer.type,
          });
        } catch (e) {
          if (kDebugMode) {
            debugPrint(
              'SupabaseRTC: renegotiation failed for viewer $viewerId: ${e.toString()}',
            );
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('SupabaseRTC: switch camera error: ${e.toString()}');
      }
      rethrow;
    }
  }

  // Supabase WebRTC viewer-side (peer-to-peer) fields
  RTCPeerConnection? _rtcViewerPc;
  MediaStream? _rtcViewerRemoteStream;
  bool _isViewing = false;
  Timer? _viewerHandshakeTimer;

  // Viewer remote stream getter for UI
  MediaStream? get viewerRemoteStream => _rtcViewerRemoteStream;

  // Expose viewer RTCPeerConnection for debugging (ICE/signaling states)
  RTCPeerConnection? get viewerPeerConnection => _rtcViewerPc;

  // Publisher-side WebRTC (Supabase) fields
  RTCPeerConnection? _rtcPc;
  MediaStream? _rtcLocalStream;
  final Map<String, RTCPeerConnection> _rtcPublisherPcs = {};

  // Expose Supabase local stream for UI (publisher preview)
  MediaStream? get supabaseLocalStream => _rtcLocalStream;

  // Create a WebRTC peer connection (flutter_webrtc)
  Future<RTCPeerConnection> _createPeerConnection() async {
    final List<Map<String, dynamic>> iceServers = [];
    // STUN
    if (ApiConfig.stunUrl1.isNotEmpty) {
      iceServers.add({'urls': [ApiConfig.stunUrl1]});
    }
    if (ApiConfig.stunUrl2.isNotEmpty) {
      iceServers.add({'urls': [ApiConfig.stunUrl2]});
    }
    // TURN (UDP)
    if (ApiConfig.turnUrl.isNotEmpty) {
      final turn = {
        'urls': [ApiConfig.turnUrl],
        if (ApiConfig.turnUsername.isNotEmpty) 'username': ApiConfig.turnUsername,
        if (ApiConfig.turnCredential.isNotEmpty) 'credential': ApiConfig.turnCredential,
      };
      iceServers.add(turn);
    }
    // TURNS (TCP/TLS)
    if (ApiConfig.turnsUrl.isNotEmpty) {
      final turns = {
        'urls': [ApiConfig.turnsUrl],
        if (ApiConfig.turnUsername.isNotEmpty) 'username': ApiConfig.turnUsername,
        if (ApiConfig.turnCredential.isNotEmpty) 'credential': ApiConfig.turnCredential,
      };
      iceServers.add(turns);
    }
    // Fallback to Google STUN if none configured
    if (iceServers.isEmpty) {
      iceServers.add({'urls': ['stun:stun.l.google.com:19302']});
    }
    final config = {'iceServers': iceServers};
    final pc = await createPeerConnection(config);
    return pc;
  }

  Future<void> _handlePublisherOffer(String sdp, String type) async {
    try {
      // An offer arriving means the handshake started – cancel timeout timer
      try {
        _viewerHandshakeTimer?.cancel();
      } catch (_) {}

      var pc = _rtcViewerPc;
      if (pc == null) {
        pc = await _createPeerConnection();
        _rtcViewerPc = pc;
        // Listen for remote track
        pc.onTrack = (event) {
          if (_isDisposed) return;
          if (event.streams.isNotEmpty) {
            _rtcViewerRemoteStream = event.streams.first;
            _streamStatusController.add({
              'type': 'viewer_remote_stream_updated',
            });
          } else {
            // Some platforms emit onTrack without streams; attach track manually.
            try {
              final existing = _rtcViewerRemoteStream;
              if (existing != null) {
                existing.addTrack(event.track);
                _rtcViewerRemoteStream = existing;
              } else {
                // No stream provided in onTrack; attempt to attach track to existing stream if available.
                final existing2 = _rtcViewerRemoteStream;
                if (existing2 != null) {
                  existing2.addTrack(event.track);
                  _rtcViewerRemoteStream = existing2;
                }
                // Otherwise, wait for onAddStream callback to provide the full MediaStream.
              }
              _streamStatusController.add({'type': 'viewer_remote_stream_updated'});
            } catch (_) {}
          }
        };
        // Compatibility: when publisher uses addStream(local), some platforms
        // emit onAddStream instead of onTrack. Handle both to ensure viewers
        // actually receive and bind the remote media stream.
        // See flutter_webrtc docs: addStream triggers onAddStream on receiver.
        // This avoids "cannot join live" when remote track never binds.
        // https://github.com/flutter-webrtc/flutter-webrtc
        // ignore: deprecated_member_use
        pc.onAddStream = (MediaStream stream) {
          if (_isDisposed) return;
          _rtcViewerRemoteStream = stream;
          _streamStatusController.add({'type': 'viewer_remote_stream_updated'});
        };
        // ICE from viewer to publisher
        pc.onIceCandidate = (c) {
          final me = _authService.currentUser?.id;
          if (me != null) {
            _broadcastToStream({
              'type': 'viewer_ice',
              'viewer_id': me,
              'candidate': c.candidate,
              'sdpMid': c.sdpMid,
              'sdpMlineIndex': c.sdpMLineIndex,
            });
          }
        };
      }
      // Validate SDP type
      if (type.toLowerCase() != 'offer') {
        if (kDebugMode) {
          debugPrint(
            'SupabaseRTC: unexpected SDP type for publisher offer: $type',
          );
        }
        return;
      }
      await pc.setRemoteDescription(RTCSessionDescription(sdp, type));
      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      final me = _authService.currentUser?.id;
      if (me != null) {
        await _broadcastToStream({
          'type': 'viewer_answer',
          'viewer_id': me,
          'sdp': answer.sdp,
          'sdp_type': answer.type,
        });
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          'SupabaseRTC: error handling publisher offer: ${e.toString()}',
        );
      }
    }
  }

  Future<Map<String, dynamic>> startViewingStream(String streamId) async {
    try {
      // Guard: require authenticated user
      final user = _authService.currentUser;
      if (user == null) {
        throw Exception('User must be authenticated to view stream');
      }

      // Guard: prevent duplicate viewing sessions
      if (_isViewing) {
        throw Exception('Already viewing a stream');
      }

      // Guard: verify stream exists and is live; also fetch owner
      final streamResponse = await _client
          .from('live_streams')
          .select('id, status, provider, user_id')
          .eq('id', streamId)
          .single();
      if (streamResponse['status'] != 'live') {
        throw Exception('Stream not found or not live');
      }

      // Guard: prevent self-join (viewer is the publisher)
      final ownerId = streamResponse['user_id']?.toString();
      if (ownerId != null && ownerId == user.id) {
        throw Exception('You cannot join your own livestream');
      }

      _currentStreamId = streamId;

      // Set up real-time channels for viewing
      await _setupViewerChannels(streamId);

      // Mark viewer state active BEFORE signaling so incoming offers are processed
      _isViewing = true;

      // Respect user's Show Online Status preference before broadcasting presence
      final allowPresence = await _preferencesService.getShowOnlineStatus();
      if (allowPresence) {
        await _joinPresence(streamId, {
          'user_id': user.id,
          'username': user.userMetadata?['username'] ?? 'Anonymous',
          'avatar_url': user.userMetadata?['avatar_url'],
          'joined_at': DateTime.now().toIso8601String(),
        });
      } else if (kDebugMode) {
        debugPrint(
          'LiveStreamingService: Presence tracking disabled by user preference; not advertising viewer presence for stream $streamId',
        );
      }

      // Listen for preference changes to update presence immediately while viewing
      void listener() async {
        final allowPresenceNow =
            PreferencesService.showOnlineStatusNotifier.value;
        if (allowPresenceNow) {
          await _joinPresence(streamId, {
            'user_id': user.id,
            'username': user.userMetadata?['username'] ?? 'Anonymous',
            'avatar_url': user.userMetadata?['avatar_url'],
            'joined_at': DateTime.now().toIso8601String(),
          });
        } else {
          await _leavePresence(streamId);
        }
      }

      _presencePreferenceListener = listener;
      PreferencesService.showOnlineStatusNotifier.addListener(listener);

      if (kDebugMode) {
        debugPrint('Joined live stream: $streamId');
      }

      // Supabase-only: skip LiveKit join path

      // Kick off WebRTC handshake with publisher (Supabase RTC)
      await _broadcastToStream({
        'type': 'viewer_request',
        'viewer_id': user.id,
      });

      // Start handshake timeout watchdog (10s)
      try {
        _viewerHandshakeTimer?.cancel();
      } catch (_) {}
      _viewerHandshakeTimer = Timer(const Duration(seconds: 10), () {
        if (_isViewing && _rtcViewerRemoteStream == null) {
          _streamStatusController.add({
            'type': 'viewer_handshake_timeout',
            'message': 'Connection is taking longer than expected. Retrying…',
          });
          final me = _authService.currentUser?.id;
          if (me != null) {
            _broadcastToStream({'type': 'viewer_request', 'viewer_id': me});
          }
        }
      });

      // No Jitsi join; for LiveKit viewers, subscribing can be implemented later
      return {
        'success': true,
        'stream_id': streamId,
        'stream_data': streamResponse,
        'provider': 'jitsi',
      };
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error starting viewer: ${e.toString()}');
      }
      _streamStatusController.add({'type': 'error', 'message': e.toString()});
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<void> stopViewingStream() async {
    try {
      _isViewing = false;
      // Leave presence when stopping viewing
      try {
        final sid = _currentStreamId;
        if (sid != null) {
          await _leavePresence(sid);
        }
      } catch (_) {}
      try {
        _viewerHandshakeTimer?.cancel();
      } catch (_) {}
      _viewerHandshakeTimer = null;
      try {
        await _rtcViewerPc?.close();
      } catch (_) {}
      _rtcViewerPc = null;
      _rtcViewerRemoteStream = null;
      // Disconnect LiveKit room if we were viewing a LiveKit stream
      try {
        if (_lkRoom != null && !_isStreaming) {
          await _lkRoom?.disconnect();
        }
      } catch (_) {}
      _lkRoom = null;
      _lkVideoTrack = null;
      _lkAudioTrack = null;
      _lkVideoTrackSid = null;
      _lkAudioTrackSid = null;
      await _cleanupChannels();
      _streamStatusController.add({'type': 'viewer_stopped'});
    } catch (e) {
      if (kDebugMode) {
        debugPrint('SupabaseRTC: error stopping viewer: ${e.toString()}');
      }
    }
  }

  // Manual viewer recovery helpers for debug UI
  Future<void> retryViewerHandshake() async {
    final sid = _currentStreamId;
    final user = _authService.currentUser;
    if (!_isViewing || sid == null || user == null) {
      _streamStatusController.add({
        'type': 'error',
        'message': 'Cannot retry handshake: not viewing or missing stream/user',
      });
      return;
    }
    await _broadcastToStream({
      'type': 'viewer_request',
      'viewer_id': user.id,
    });
    try {
      _viewerHandshakeTimer?.cancel();
    } catch (_) {}
    _viewerHandshakeTimer = Timer(const Duration(seconds: 10), () {
      if (_isViewing && _rtcViewerRemoteStream == null) {
        _streamStatusController.add({
          'type': 'viewer_handshake_timeout',
          'message': 'Connection is taking longer than expected. Retrying…',
        });
        final me = _authService.currentUser?.id;
        if (me != null) {
          _broadcastToStream({'type': 'viewer_request', 'viewer_id': me});
        }
      }
    });
  }

  Future<void> forceFallbackToSupabase() async {
    if (!_isViewing) return;
    try {
      await _lkRoom?.disconnect();
    } catch (_) {}
    _lkRoom = null;
    final me = _authService.currentUser?.id;
    if (me != null) {
      await _broadcastToStream({'type': 'viewer_request', 'viewer_id': me});
    }
    try {
      _viewerHandshakeTimer?.cancel();
    } catch (_) {}
    _viewerHandshakeTimer = Timer(const Duration(seconds: 10), () {
      if (_isViewing && _rtcViewerRemoteStream == null) {
        _streamStatusController.add({
          'type': 'viewer_handshake_timeout',
          'message': 'Connection is taking longer than expected. Retrying…',
        });
        final myId = _authService.currentUser?.id;
        if (myId != null) {
          _broadcastToStream({'type': 'viewer_request', 'viewer_id': myId});
        }
      }
    });
    _streamStatusController.add({
      'provider': 'jitsi',
      'status': 'forced_fallback',
      'message': 'User triggered fallback to Supabase RTC',
      'stream_id': _currentStreamId,
    });
  }

  // Supabase-only: enable/disable camera/microphone by toggling MediaStream tracks
  Future<void> setSupabaseCameraEnabled(bool enabled) async {
    try {
      final tracks = _rtcLocalStream?.getVideoTracks() ?? [];
      for (final t in tracks) {
        t.enabled = enabled;
      }
      if (kDebugMode) {
        debugPrint('SupabaseRTC: camera ${enabled ? 'enabled' : 'disabled'}');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('SupabaseRTC: set camera error: ${e.toString()}');
      }
    }
  }

  Future<void> setSupabaseMicrophoneEnabled(bool enabled) async {
    try {
      final tracks = _rtcLocalStream?.getAudioTracks() ?? [];
      for (final t in tracks) {
        t.enabled = enabled;
      }
      if (kDebugMode) {
        debugPrint(
          'SupabaseRTC: microphone ${enabled ? 'enabled' : 'disabled'}',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('SupabaseRTC: set microphone error: ${e.toString()}');
      }
    }
  }

  // Supabase-only: start local publisher (P2P/WebRTC signaling via Supabase Realtime)
  Future<Map<String, dynamic>> startSupabasePublisher({
    required String title,
    String? description,
    List<String>? tags,
    bool isEphemeral = true,
    bool savedLocally = false,
    String? localFilePath,
  }) async {
    try {
      final user = _authService.currentUser;
      if (user == null) {
        throw Exception('User must be authenticated to start streaming');
      }

      // Guard: prevent duplicate publisher starts
      if (_isStreaming) {
        throw Exception('A stream is already in progress');
      }

      // Soft-check: enumerate devices (no longer a hard barrier)
      bool hasCam = true;
      bool hasMic = true;
      try {
        final devices = await navigator.mediaDevices.enumerateDevices();
        hasCam = devices.any((d) => d.kind == 'videoinput');
        hasMic = devices.any((d) => d.kind == 'audioinput');
        if (kDebugMode) {
          debugPrint('SupabaseRTC: devices -> cams=${hasCam ? 'yes' : 'no'}, mics=${hasMic ? 'yes' : 'no'}');
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('SupabaseRTC: error enumerating devices (soft): ${e.toString()}');
        }
      }

      // Acquire local media (camera + microphone) with fallbacks for devices that don't support requested constraints
      // Prefer specific deviceId selections to avoid overconstrained errors on systems with multiple cameras/mics
      String? preferredCamId;
      String? preferredMicId;
      try {
        final devsPref = await navigator.mediaDevices.enumerateDevices();
        for (final d in devsPref) {
          if (d.kind == 'videoinput' && preferredCamId == null) {
            preferredCamId = d.deviceId;
          }
          if (d.kind == 'audioinput' && preferredMicId == null) {
            preferredMicId = d.deviceId;
          }
        }
        if (kDebugMode) {
          debugPrint('SupabaseRTC: preferred devices -> cam: ${preferredCamId ?? 'none'}, mic: ${preferredMicId ?? 'none'}');
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('SupabaseRTC: enumerateDevices (preferred) failed: ${e.toString()}');
        }
      }

      final constraintCandidates = [
        {
          'audio': preferredMicId != null ? {'deviceId': preferredMicId} : true,
          'video': {
            if (preferredCamId != null) 'deviceId': preferredCamId,
            'facingMode': 'user',
            'width': {'ideal': 1280},
            'height': {'ideal': 720},
            'frameRate': {'ideal': 30},
          },
        },
        {
          'audio': preferredMicId != null ? {'deviceId': preferredMicId} : true,
          'video': {
            if (preferredCamId != null) 'deviceId': preferredCamId,
            'width': {'ideal': 640},
            'height': {'ideal': 480},
          },
        },
        {
          'audio': true,
          'video': {'facingMode': 'user'},
        },
        {
          'audio': preferredMicId != null ? {'deviceId': preferredMicId} : true,
          'video': {
            if (preferredCamId != null) 'deviceId': preferredCamId,
          },
        },
        {'audio': true, 'video': true},
      ];
      dynamic lastError;
      for (final c in constraintCandidates) {
        try {
          _rtcLocalStream = await navigator.mediaDevices.getUserMedia(c);
          if (_rtcLocalStream != null) {
            if (kDebugMode) {
              debugPrint(
                'SupabaseRTC: getUserMedia succeeded with constraints: ${c.toString()}',
              );
            }
            break;
          }
        } catch (e) {
          lastError = e;
          if (kDebugMode) {
            debugPrint(
              'SupabaseRTC: getUserMedia attempt failed: ${e.toString()} with constraints: ${c.toString()}',
            );
          }
          // Only continue to next candidate for overconstrained/NotFound-like errors; propagate for permissions/security
          final err = e.toString().toLowerCase();
          final isPermissionOrSecurity =
              err.contains('permission') ||
              err.contains('denied') ||
              err.contains('notallowederror') ||
              err.contains('security') ||
              err.contains('blocked') ||
              err.contains('insecure');
          if (isPermissionOrSecurity) {
            throw Exception(
              'Could not access camera/microphone. Please grant permissions and ensure devices are connected. Details: $e',
            );
          }
          // else try next candidate
        }
      }
      if (_rtcLocalStream == null) {
        // Try audio-only and video-only as last resort to avoid blocking start
        try {
          if (kDebugMode) {
            debugPrint('SupabaseRTC: trying audio-only fallback');
          }
          _rtcLocalStream = await navigator.mediaDevices.getUserMedia({'audio': true});
        } catch (e) {
          if (kDebugMode) {
            debugPrint('SupabaseRTC: audio-only fallback failed: ${e.toString()}');
          }
        }
        if (_rtcLocalStream == null) {
          try {
            if (kDebugMode) {
              debugPrint('SupabaseRTC: trying video-only fallback');
            }
            _rtcLocalStream = await navigator.mediaDevices.getUserMedia({'video': true});
          } catch (e) {
            if (kDebugMode) {
              debugPrint('SupabaseRTC: video-only fallback failed: ${e.toString()}');
            }
          }
        }
        if (_rtcLocalStream == null) {
          // Only throw if we truly cannot get any media (likely permissions/security)
          try {
            final devices2 = await navigator.mediaDevices.enumerateDevices();
            final cams = devices2.where((d) => d.kind == 'videoinput').length;
            final mics = devices2.where((d) => d.kind == 'audioinput').length;
            throw Exception('Could not access any media devices. Cameras detected: $cams, microphones detected: $mics. Details: ${lastError?.toString() ?? 'Unknown error'}');
          } catch (_) {
            throw Exception('Could not access any media devices. Details: ${lastError?.toString() ?? 'Unknown error'}');
          }
        }
      }

      // Create initial stream record in Supabase with provider
      final nowIso = DateTime.now().toIso8601String();
      final insertData = {
        'user_id': user.id,
        'title': title,
        'description': description ?? '',
        'tags': tags ?? [],
        // Provider must satisfy DB CHECK (allowed: 'jitsi', 'livekit')
        'provider': 'jitsi',
        // Satisfy NOT NULL columns in schema even when not using Jitsi
        'jitsi_room_name': '',
        'jitsi_stream_url': '',
        'status': 'live',
        'viewer_count': 0,
        'started_at': nowIso,
        'created_at': nowIso,
        'is_ephemeral': isEphemeral,
        'saved_locally': savedLocally,
        'local_file_path': localFilePath,
      };
      final inserted = await _client
          .from('live_streams')
          .insert(insertData)
          .select()
          .single();
      _currentStreamId = inserted['id'] as String?;
      _isStreaming = true;

      // Notify followers that the user went live
      try {
        final social = SocialService();
        final followers = await social.getFollowers(user.id);
        final actorUsername = user.userMetadata?['username'] ?? 'Someone';
        for (final f in followers) {
          final followerId = f['follower_id'] as String?;
          if (followerId == null) continue;
          await social.createNotification(followerId, 'live', {
            'stream_id': _currentStreamId,
            'actor_id': user.id,
            'username': actorUsername,
            'title': title,
            'action_type': 'live',
          });
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint(
            'LiveStreamingService: error notifying followers of live start: ${e.toString()}',
          );
        }
      }

      // Setup Supabase realtime channels for stream/chat/presence
      await _setupStreamChannels(_currentStreamId!);

      // Broadcast stream started event
      await _broadcastToStream({
        'type': 'stream_started',
        'provider': 'jitsi',
        'title': title,
        'timestamp': nowIso,
      });

      _streamStatusController.add({
        'provider': 'jitsi',
        'status': 'started',
        'stream_id': _currentStreamId,
      });

      if (kDebugMode) {
        debugPrint(
          'SupabaseRTC: publisher started streamId=${_currentStreamId ?? 'unknown'}',
        );
      }

      // NOTE: Signaling (SDP/ICE) for viewer connections will be implemented over _streamChannel broadcasts.
      // For now, we expose local preview via supabaseLocalStream.

      return {
        'success': true,
        'provider': 'jitsi',
        'status': 'started',
        'stream_id': _currentStreamId,
      };
    } catch (e) {
      _streamStatusController.add({
        'provider': 'jitsi',
        'status': 'error',
        'message': e.toString(),
      });
      if (kDebugMode) {
        debugPrint('SupabaseRTC: error starting publisher: ${e.toString()}');
      }
      return {'success': false, 'error': e.toString()};
    }
  }

  // Supabase-only: stop publisher and cleanup
  Future<void> stopSupabasePublisher({
    int? finalDuration,
    bool? savedLocally,
    String? localFilePath,
  }) async {
    try {
      // Stop local media tracks
      try {
        final allTracks = [
          ...(_rtcLocalStream?.getVideoTracks() ?? []),
          ...(_rtcLocalStream?.getAudioTracks() ?? []),
        ];
        for (final t in allTracks) {
          t.stop();
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('SupabaseRTC: error stopping local tracks: $e');
        }
      }
      _rtcLocalStream = null;

      // Close peer connection if created
      try {
        await _rtcPc?.close();
      } catch (_) {}
      _rtcPc = null;

      // Update stream record
      if (_currentStreamId != null) {
        final updateData = {
          'status': 'ended',
          'ended_at': DateTime.now().toIso8601String(),
          'final_viewer_count': _viewerCount,
          'final_duration': finalDuration,
        };
        if (savedLocally != null) {
          updateData['saved_locally'] = savedLocally;
        }
        if (localFilePath != null) {
          updateData['local_file_path'] = localFilePath;
        }
        await _client
            .from('live_streams')
            .update(updateData)
            .eq('id', _currentStreamId!);
      }

      // Clean up channels
      await _cleanupChannels();

      _isStreaming = false;
      _currentStreamId = null;

      _streamStatusController.add({
        'provider': 'jitsi',
        'status': 'ended',
      });
      if (kDebugMode) {
        debugPrint('SupabaseRTC: publisher stopped');
      }
    } catch (e) {
      _streamStatusController.add({
        'provider': 'jitsi',
        'status': 'error',
        'message': e.toString(),
      });
      if (kDebugMode) {
        debugPrint('SupabaseRTC: error stopping publisher: $e');
      }
    }
  }

  Future<void> _handleViewerRequest(String viewerId) async {
    try {
      // Guard: ensure publisher is streaming and has local media
      if (!_isStreaming || _currentStreamId == null) {
        if (kDebugMode) {
          debugPrint('SupabaseRTC: viewer request ignored - no active stream');
        }
        return;
      }
      final local = _rtcLocalStream;
      if (local == null) {
        if (kDebugMode) {
          debugPrint(
            'SupabaseRTC: viewer request ignored - local stream missing',
          );
        }
        return;
      }
      // Guard: avoid duplicate per-viewer peer connections
      if (_rtcPublisherPcs.containsKey(viewerId)) {
        if (kDebugMode) {
          debugPrint(
            'SupabaseRTC: viewer request ignored - PC already exists for $viewerId',
          );
        }
        return;
      }
      // Create per-viewer PC on publisher side
      final pc = await _createPeerConnection();
      _rtcPublisherPcs[viewerId] = pc;
      // Send ICE to viewer via stream channel
      pc.onIceCandidate = (c) {
        _broadcastToStream({
          'type': 'publisher_ice',
          'viewer_id': viewerId,
          'candidate': c.candidate,
          'sdpMid': c.sdpMid,
          'sdpMlineIndex': c.sdpMLineIndex,
        });
      };
      // Add local media to PC (prefer addTrack for Unified Plan)
      try {
        for (final t in local.getTracks()) {
          await pc.addTrack(t, local);
        }
      } catch (_) {
        // ignore: deprecated_member_use
        pc.addStream(local);
      }
      // Create and send offer
      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      await _broadcastToStream({
        'type': 'publisher_offer',
        'viewer_id': viewerId,
        'sdp': offer.sdp,
        'sdp_type': offer.type,
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          'SupabaseRTC: error handling viewer request: ${e.toString()}',
        );
      }
    }
  }

  // Getters
  bool get isStreaming => _isStreaming;
  int get viewerCount => _viewerCount;
  List<Map<String, dynamic>> get viewers => List.unmodifiable(_viewers);
  List<Map<String, dynamic>> get chatMessages =>
      List.unmodifiable(_chatMessages);
  String? get currentStreamId => _currentStreamId;

  // Initialize live streaming service
  Future<void> initialize() async {
    try {
      // await _jitsiService.initialize(); // removed

      // _jitsiService.setEventCallbacks( // removed
      //   onConferenceJoined: (url) { /* ... */ },
      //   onConferenceLeft: (url) { /* ... */ },
      //   onParticipantJoined: (participantId) { /* ... */ },
      //   onParticipantLeft: (participantId) { /* ... */ },
      // );

      if (kDebugMode) {
        debugPrint('LiveStreamingService initialized successfully');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to initialize LiveStreamingService: $e');
      }
      rethrow;
    }
  }

  // Start a live stream
  Future<LiveStreamModel> startLiveStream({
    required String title,
    required String description,
    List<String>? tags,
    bool isEphemeral = true,
    bool savedLocally = false,
    String? localFilePath,
  }) async {
    try {
      final user = _authService.currentUser;
      if (user == null) {
        throw Exception('User must be authenticated to start streaming');
      }

      // Start Supabase WebRTC publisher
      final sbResult = await startSupabasePublisher(
        title: title,
        description: description,
        tags: tags,
        isEphemeral: isEphemeral,
        savedLocally: savedLocally,
        localFilePath: localFilePath,
      );
      if (sbResult['success'] != true) {
        throw Exception(
          'Failed to start Supabase WebRTC: ${sbResult['error']?.toString() ?? 'unknown error'}',
        );
      }

      // startSupabasePublisher sets up channels and state

      // Notify stream status change
      _streamStatusController.add({
        'status': 'started',
        'stream_id': _currentStreamId,
        'title': title,
        'viewer_count': 0,
        'provider': 'jitsi',
      });

      if (kDebugMode) {
        debugPrint(
          'Live stream (Supabase) started: ${_currentStreamId ?? 'unknown'}',
        );
      }

      return LiveStreamModel(
        id: _currentStreamId!,
        userId: user.id,
        title: title,
        description: description,
        tags: tags ?? [],
        provider: 'jitsi',
        jitsiRoomName: null,
        jitsiStreamUrl: null,
        status: 'live',
        viewerCount: 0,
        startedAt: DateTime.now(),
        createdAt: DateTime.now(),
        isEphemeral: isEphemeral,
        savedLocally: savedLocally,
        localFilePath: localFilePath,
        finalDuration: null,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error starting live stream: $e');
      }
      rethrow;
    }
  }

  // Stop the current live stream
  Future<Map<String, dynamic>> stopLiveStream({
    int? finalDuration,
    bool? savedLocally,
    String? localFilePath,
  }) async {
    try {
      if (!_isStreaming) {
        throw Exception('No active stream to stop');
      }

      // Stop Supabase publisher
      await stopSupabasePublisher(
        finalDuration: finalDuration,
        savedLocally: savedLocally,
        localFilePath: localFilePath,
      );

      // Clean up channels
      await _cleanupChannels();

      // Broadcast stream ended to all viewers
      await _broadcastToStream({
        'type': 'stream_ended',
        'message': 'The live stream has ended. Thanks for watching!',
        'timestamp': DateTime.now().toIso8601String(),
      });

      final endedStreamId = _currentStreamId;

      _isStreaming = false;
      final finalViewerCount = _viewerCount;
      _viewerCount = 0;
      _viewers.clear();
      _chatMessages.clear();
      _currentStreamId = null;

      // Notify stream status change
      _streamStatusController.add({
        'status': 'ended',
        'stream_id': endedStreamId,
        'final_viewer_count': finalViewerCount,
        'provider': 'jitsi',
      });

      if (kDebugMode) {
        debugPrint('Supabase stream stopped: ${endedStreamId ?? 'unknown'}');
      }

      return {'success': true, 'stream_id': endedStreamId};
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error stopping live stream: $e');
      }
      return {'success': false, 'error': e.toString()};
    }
  }

  // Join a live stream as a viewer
  Future<Map<String, dynamic>> joinStream(String streamId) async {
    try {
      final user = _authService.currentUser;
      if (user == null) {
        throw Exception('User must be authenticated to join stream');
      }

      // Get stream info from Supabase
      final streamResponse = await _client
          .from('live_streams')
          .select('*')
          .eq('id', streamId)
          .eq('status', 'live')
          .single();

      _currentStreamId = streamId;

      // Set up real-time channels for viewing
      await _setupViewerChannels(streamId);

      // Mark viewer state active BEFORE signaling so incoming offers are processed
      _isViewing = true;

      // Respect user's Show Online Status preference before broadcasting presence
      final allowPresence = await _preferencesService.getShowOnlineStatus();
      if (allowPresence) {
        await _joinPresence(streamId, {
          'user_id': user.id,
          'username': user.userMetadata?['username'] ?? 'Anonymous',
          'avatar_url': user.userMetadata?['avatar_url'],
          'joined_at': DateTime.now().toIso8601String(),
        });
      } else if (kDebugMode) {
        debugPrint(
          'LiveStreamingService: Presence tracking disabled by user preference; not advertising viewer presence for stream $streamId',
        );
      }

      // Listen for preference changes to update presence immediately while viewing
      listener() async {
        final allowPresenceNow =
            PreferencesService.showOnlineStatusNotifier.value;
        if (allowPresenceNow) {
          await _joinPresence(streamId, {
            'user_id': user.id,
            'username': user.userMetadata?['username'] ?? 'Anonymous',
            'avatar_url': user.userMetadata?['avatar_url'],
            'joined_at': DateTime.now().toIso8601String(),
          });
        } else {
          await _leavePresence(streamId);
        }
      }

      _presencePreferenceListener = listener;
      PreferencesService.showOnlineStatusNotifier.addListener(listener);

      if (kDebugMode) {
        debugPrint('Joined live stream: $streamId');
      }

      // Kick off WebRTC handshake with publisher
      await _broadcastToStream({
        'type': 'viewer_request',
        'viewer_id': user.id,
      });

      // Start handshake timeout watchdog (10s)
      try {
        _viewerHandshakeTimer?.cancel();
      } catch (_) {}
      _viewerHandshakeTimer = Timer(const Duration(seconds: 10), () {
        if (_isViewing && _rtcViewerRemoteStream == null) {
          _streamStatusController.add({
            'type': 'viewer_handshake_timeout',
            'message': 'Connection is taking longer than expected. Retrying…',
          });
          final me = _authService.currentUser?.id;
          if (me != null) {
            _broadcastToStream({'type': 'viewer_request', 'viewer_id': me});
          }
        }
      });

      // No Jitsi join; for LiveKit viewers, subscribing can be implemented later
      return {
        'success': true,
        'stream_id': streamId,
        'stream_data': streamResponse,
        'provider': streamResponse['provider'],
      };
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error joining stream: $e');
      }
      return {'success': false, 'error': e.toString()};
    }
  }

  // Leave the current stream
  Future<void> leaveStream() async {
    try {
      if (_currentStreamId != null) {
        // No Jitsi leave
        await _leavePresence(_currentStreamId!);
        await _cleanupChannels();
        _currentStreamId = null;
        _viewers.clear();
        _chatMessages.clear();
        _viewerCount = 0;

        // Remove presence preference listener
        final listener = _presencePreferenceListener;
        if (listener != null) {
          PreferencesService.showOnlineStatusNotifier.removeListener(listener);
          _presencePreferenceListener = null;
        }

        if (kDebugMode) {
          debugPrint('Left live stream');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error leaving stream: $e');
      }
    }
  }

  // End a live stream (for streamers)
  Future<void> endLiveStream(String streamId) async {
    try {
      // Clean up all channels and connections
      await _cleanupChannels();

      // Reset state
      _currentStreamId = null;
      _viewers.clear();
      _chatMessages.clear();
      _viewerCount = 0;

      // Remove presence preference listener
      final listener = _presencePreferenceListener;
      if (listener != null) {
        PreferencesService.showOnlineStatusNotifier.removeListener(listener);
        _presencePreferenceListener = null;
      }

      if (kDebugMode) {
        debugPrint('Ended live stream: $streamId');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error ending stream: $e');
      }
    }
  }

  // Send a chat message
  Future<void> sendChatMessage(String message) async {
    try {
      if (_currentStreamId == null) {
        throw Exception('No active stream');
      }

      final user = _authService.currentUser;
      if (user == null) {
        throw Exception('User must be authenticated to send messages');
      }

      final chatMessage = {
        'type': 'chat_message',
        'stream_id': _currentStreamId,
        'user_id': user.id,
        'username': user.userMetadata?['username'] ?? 'Anonymous',
        'avatar_url': user.userMetadata?['avatar_url'],
        'message': message,
        'timestamp': DateTime.now().toIso8601String(),
      };

      // Broadcast to chat channel
      await _broadcastToChat(chatMessage);

      // Store in local chat messages
      _chatMessages.add(chatMessage);
      _chatController.add(chatMessage);

      if (kDebugMode) {
        debugPrint('Chat message sent: $message');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error sending chat message: $e');
      }
      rethrow;
    }
  }

  // Send a reaction (like, heart, etc.)
  Future<void> sendReaction(String reactionType) async {
    try {
      if (_currentStreamId == null) {
        throw Exception('No active stream');
      }

      final user = _authService.currentUser;
      if (user == null) {
        throw Exception('User must be authenticated to send reactions');
      }

      final reaction = {
        'type': 'reaction',
        'stream_id': _currentStreamId,
        'user_id': user.id,
        'username': user.userMetadata?['username'] ?? 'Anonymous',
        'reaction_type': reactionType,
        'timestamp': DateTime.now().toIso8601String(),
      };

      // Broadcast reaction
      await _broadcastToStream(reaction);
      _reactionsController.add(reaction);

      if (kDebugMode) {
        debugPrint('Reaction sent: $reactionType');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error sending reaction: $e');
      }
      rethrow;
    }
  }

  // Get list of active live streams
  Future<List<Map<String, dynamic>>> getActiveLiveStreams({
    Duration staleThreshold = const Duration(minutes: 3),
  }) async {
    try {
      final String thresholdIso = DateTime.now()
          .subtract(staleThreshold)
          .toIso8601String();
      final response = await _client
          .from('live_streams')
          .select('*, users!live_streams_user_id_fkey(username, avatar_url)')
          .eq('status', 'live')
          .filter('ended_at', 'is', null)
          .gte('updated_at', thresholdIso)
          .order('updated_at', ascending: false);

      final List<Map<String, dynamic>> rows = List<Map<String, dynamic>>.from(
        response,
      );

      final cutoff = DateTime.now().subtract(staleThreshold);
      return rows.where((s) {
        final tsString = (s['updated_at'] ?? s['started_at'])?.toString();
        final ts = DateTime.tryParse(tsString ?? '');
        if (ts == null) return false;
        return ts.isAfter(cutoff);
      }).toList();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error getting active streams: $e');
      }
      return [];
    }
  }

  // Setup real-time channels for streaming
  Future<void> _setupStreamChannels(String streamId) async {
    // Stream channel for general stream events
    _streamChannel = _client.channel('stream_$streamId')
      ..onBroadcast(
        event: 'stream_event',
        callback: (payload) {
          _handleStreamEvent(payload);
        },
      )
      ..subscribe();

    // Chat channel for chat messages
    _chatChannel = _client.channel('chat_$streamId')
      ..onBroadcast(
        event: 'chat_message',
        callback: (payload) {
          _handleChatMessage(payload);
        },
      )
      ..subscribe();

    // Presence channel for viewer tracking
    _presenceChannel = _client.channel('presence_$streamId')
      ..onPresenceSync((payload) {
        _handlePresenceSync();
      })
      ..onPresenceJoin((payload) {
        _handlePresenceJoin(payload);
      })
      ..onPresenceLeave((payload) {
        _handlePresenceLeave(payload);
      })
      ..subscribe();
  }

  // Setup channels for viewing (not streaming)
  Future<void> _setupViewerChannels(String streamId) async {
    // Stream channel for general stream events
    _streamChannel = _client.channel('stream_$streamId')
      ..onBroadcast(
        event: 'stream_event',
        callback: (payload) {
          _handleStreamEvent(payload);
        },
      )
      ..subscribe();

    // Chat channel for chat messages
    _chatChannel = _client.channel('chat_$streamId')
      ..onBroadcast(
        event: 'chat_message',
        callback: (payload) {
          _handleChatMessage(payload);
        },
      )
      ..subscribe();

    // Presence channel for viewer tracking
    _presenceChannel = _client.channel('presence_$streamId')
      ..onPresenceSync((payload) {
        _handlePresenceSync();
      })
      ..onPresenceJoin((payload) {
        _handlePresenceJoin(payload);
      })
      ..onPresenceLeave((payload) {
        _handlePresenceLeave(payload);
      })
      ..subscribe();
  }

  // Join presence channel
  Future<void> _joinPresence(
    String streamId,
    Map<String, dynamic> userData,
  ) async {
    await _presenceChannel?.track(userData);
  }

  // Leave presence channel
  Future<void> _leavePresence(String streamId) async {
    await _presenceChannel?.untrack();
  }

  // Broadcast message to stream channel
  Future<void> _broadcastToStream(Map<String, dynamic> payload) async {
    await _streamChannel?.sendBroadcastMessage(
      event: 'stream_event',
      payload: payload,
    );
  }

  // Broadcast message to chat channel
  Future<void> _broadcastToChat(Map<String, dynamic> payload) async {
    await _chatChannel?.sendBroadcastMessage(
      event: 'chat_message',
      payload: payload,
    );
  }

  // Handle stream events
  void _handleStreamEvent(Map<String, dynamic> payload) {
    if (_isDisposed) return;
    if (kDebugMode) {
      debugPrint('Stream event received: $payload');
    }

    switch (payload['type']) {
      case 'stream_ended':
        _isStreaming = false;
        _streamStatusController.add(payload);
        break;
      case 'reaction':
        _reactionsController.add(payload);
        break;
      case 'gift':
        _giftsController.add(payload);
        // Update in-memory leaderboard totals
        final uid = (payload['user_id'] as String?) ?? '';
        final coins = (payload['coins_spent'] as int?) ?? 0;
        if (uid.isNotEmpty && coins > 0) {
          _giftTotals.update(uid, (v) => v + coins, ifAbsent: () => coins);
          // Create a simple leaderboard list
          final username = (payload['username'] as String?) ?? 'Anonymous';
          final avatarUrl = payload['avatar_url'];
          final entries =
              _giftTotals.entries
                  .map(
                    (e) => {
                      'user_id': e.key,
                      'username': username,
                      'avatar_url': avatarUrl,
                      'coins_spent': e.value,
                    },
                  )
                  .toList()
                ..sort(
                  (a, b) => (b['coins_spent'] as int).compareTo(
                    a['coins_spent'] as int,
                  ),
                );
          _giftLeaderboardController.add(entries.take(5).toList());
        }
        break;
      // Viewer-side: receive offer/ICE from publisher
      case 'publisher_offer':
        if (_isViewing) {
          final viewerId = payload['viewer_id'] as String?;
          final me = _authService.currentUser?.id;
          if (viewerId != null && me != null && viewerId == me) {
            final sdp = payload['sdp'] as String?;
            final type = payload['sdp_type'] as String?;
            if (sdp != null && type != null) {
              _handlePublisherOffer(sdp, type);
            }
          }
        }
        break;
      case 'publisher_ice':
        if (_isViewing) {
          final viewerId = payload['viewer_id'] as String?;
          final me = _authService.currentUser?.id;
          if (viewerId != null && me != null && viewerId == me) {
            final candidate = payload['candidate'] as String?;
            final sdpMid = payload['sdpMid'] as String?;
            final sdpMlineIndex = payload['sdpMlineIndex'] as int?;
            if (candidate != null && sdpMid != null && sdpMlineIndex != null) {
              _rtcViewerPc?.addCandidate(
                RTCIceCandidate(candidate, sdpMid, sdpMlineIndex),
              );
            }
          }
        }
        break;
      // Publisher-side: handle viewer request/answer/ICE
      case 'viewer_request':
        if (_isStreaming) {
          final viewerId = payload['viewer_id'] as String?;
          if (viewerId != null) {
            _handleViewerRequest(viewerId);
          }
        }
        break;
      case 'viewer_answer':
        if (_isStreaming) {
          final viewerId = payload['viewer_id'] as String?;
          final sdp = payload['sdp'] as String?;
          final type = payload['sdp_type'] as String?;
          if (viewerId != null && sdp != null && type != null) {
            final pc = _rtcPublisherPcs[viewerId];
            if (pc != null) {
              // Validate SDP type
              if (type.toLowerCase() != 'answer') {
                if (kDebugMode) {
                  debugPrint(
                    'SupabaseRTC: unexpected SDP type for viewer_answer: $type',
                  );
                }
              } else {
                pc.setRemoteDescription(RTCSessionDescription(sdp, type));
              }
            }
          }
        }
        break;
      case 'viewer_ice':
        if (_isStreaming) {
          final viewerId = payload['viewer_id'] as String?;
          final candidate = payload['candidate'] as String?;
          final sdpMid = payload['sdpMid'] as String?;
          final sdpMlineIndex = payload['sdpMlineIndex'] as int?;
          if (viewerId != null &&
              candidate != null &&
              sdpMid != null &&
              sdpMlineIndex != null) {
            final pc = _rtcPublisherPcs[viewerId];
            pc?.addCandidate(RTCIceCandidate(candidate, sdpMid, sdpMlineIndex));
          }
        }
        break;
      default:
        _streamStatusController.add(payload);
    }
  }

  // Handle chat messages
  void _handleChatMessage(Map<String, dynamic> payload) {
    if (_isDisposed) return;
    if (kDebugMode) {
      debugPrint('Chat message received: ${payload['message']}');
    }

    _chatMessages.add(payload);
    _chatController.add(payload);
  }

  // Handle presence sync (all current viewers)
  void _handlePresenceSync() {
    if (_isDisposed) return;
    final state = _presenceChannel?.presenceState();

    List<Map<String, dynamic>> viewersList = [];

    Map<String, dynamic>? _presenceItemToMap(dynamic item) {
      // Common case: payload is a plain Map
      if (item is Map<String, dynamic>) return Map<String, dynamic>.from(item);

      // Supabase realtime may return SinglePresenceState objects on web
      // Try to access a `payload` field dynamically
      try {
        final dynamic payload = (item as dynamic).payload;
        if (payload is Map<String, dynamic>) {
          return Map<String, dynamic>.from(payload);
        }
      } catch (_) {}

      // Fallback: try toJson if available
      try {
        final dynamic json = (item as dynamic).toJson();
        if (json is Map<String, dynamic>) {
          final dynamic payload = json['payload'] ?? json;
          if (payload is Map<String, dynamic>) {
            return Map<String, dynamic>.from(payload);
          }
        }
      } catch (_) {}

      return null;
    }

    if (state is Map) {
      // Newer realtime clients may return Map<String, List<Presence>>
      for (final entry in (state as Map).entries) {
        final val = entry.value;
        if (val is List) {
          for (final item in val) {
            final m = _presenceItemToMap(item);
            if (m != null) viewersList.add(m);
          }
        } else {
          final m = _presenceItemToMap(val);
          if (m != null) viewersList.add(m);
        }
      }
    } else if (state is List) {
      // On web, presenceState() may be List<SinglePresenceState>
      for (final item in (state as List)) {
        final m = _presenceItemToMap(item);
        if (m != null) viewersList.add(m);
      }
    }

    _viewers = viewersList;

    _viewerCount = _viewers.length;
    _viewersController.add(_viewers);

    if (kDebugMode) {
      debugPrint('Presence sync: $_viewerCount viewers');
    }
  }

  // Handle viewer joining
  void _handlePresenceJoin(dynamic payload) {
    if (kDebugMode) {
      debugPrint('Viewer joined: $payload');
    }
    _handlePresenceSync();
  }

  // Handle viewer leaving
  void _handlePresenceLeave(dynamic payload) {
    if (kDebugMode) {
      debugPrint('Viewer left: $payload');
    }
    _handlePresenceSync();
  }

  // Clean up all channels
  Future<void> _cleanupChannels() async {
    try {
      if (_streamChannel != null) {
        await _client.removeChannel(_streamChannel!);
        _streamChannel = null;
      }
      if (_chatChannel != null) {
        await _client.removeChannel(_chatChannel!);
        _chatChannel = null;
      }
      if (_presenceChannel != null) {
        await _client.removeChannel(_presenceChannel!);
        _presenceChannel = null;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error cleaning up channels: $e');
      }
    }
  }

  // Get user's past livestreams
  Future<List<LiveStreamModel>> getUserStreams({
    String? userId,
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final targetUserId = userId ?? _authService.currentUser?.id;
      if (targetUserId == null) {
        throw Exception('User ID is required');
      }

      final response = await _client
          .from('live_streams')
          .select('*')
          .eq('user_id', targetUserId)
          .order('started_at', ascending: false)
          .range(offset, offset + limit - 1);

      return (response as List)
          .map((json) => LiveStreamModel.fromJson(json))
          .toList();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error fetching user streams: $e');
      }
      rethrow;
    }
  }

  // Get stream analytics for a specific stream
  Future<Map<String, dynamic>?> getStreamAnalytics(String streamId) async {
    try {
      final response = await _client
          .from('stream_analytics')
          .select('*')
          .eq('id', streamId)
          .maybeSingle();

      return response;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error fetching stream analytics: $e');
      }
      return null;
    }
  }

  // Dispose of the service
  void dispose() {
    _isDisposed = true;
    _isStreaming = false;
    _isViewing = false;
    // Remove presence preference listener
    final listener = _presencePreferenceListener;
    if (listener != null) {
      PreferencesService.showOnlineStatusNotifier.removeListener(listener);
      _presencePreferenceListener = null;
    }

    try {
      _viewerHandshakeTimer?.cancel();
    } catch (_) {}
    _viewerHandshakeTimer = null;

    _cleanupChannels();
    _chatController.close();
    _viewersController.close();
    _reactionsController.close();
    _streamStatusController.close();
    _giftsController.close();
    _giftLeaderboardController.close();
  }

  // LiveKit: get publisher token based on current user and a naming convention
  Future<Map<String, dynamic>> getPublisherTokenForCurrentUser({
    required String roomPrefix,
  }) async {
    final user = _authService.currentUser;
    if (user == null) {
      throw Exception('User must be authenticated to get LiveKit token');
    }
    final roomName = '$roomPrefix-${user.id}';
    return await fetchLiveKitToken(
      room: roomName,
      identity: user.id,
      name: user.userMetadata?['username'] ?? 'Anonymous',
      canPublish: true,
      canSubscribe: true,
      canPublishData: true,
      ttlSeconds: 600,
      metadata: {'role': 'host', 'user_id': user.id},
    );
  }

  // Start LiveKit publishing (ephemeral, local recording optional handled elsewhere)
  Future<Map<String, dynamic>> startLiveKitPublisher({
    required String roomPrefix,
    String? title,
    String? description,
    List<String>? tags,
    bool isEphemeral = true,
    bool savedLocally = false,
    String? localFilePath,
  }) async {
    try {
      final user = _authService.currentUser;
      if (user == null) {
        throw Exception('User must be authenticated to start LiveKit');
      }
      final tokenData = await getPublisherTokenForCurrentUser(
        roomPrefix: roomPrefix,
      );
      var url = tokenData['url'] as String;
      final token = tokenData['token'] as String;

      // Enforce websocket scheme for web
      if (url.startsWith('http://')) {
        url = url.replaceFirst('http://', 'ws://');
      } else if (url.startsWith('https://')) {
        url = url.replaceFirst('https://', 'wss://');
      }

      // Connect to LiveKit
      final room = Room();
      await room.connect(url, token);
      _lkRoom = room;

      // Create and publish local camera track
      try {
        final localVideo = await LocalVideoTrack.createCameraTrack(
          const CameraCaptureOptions(),
        );
        final videoPub = await room.localParticipant?.publishVideoTrack(
          localVideo,
        );
        _lkVideoTrack = localVideo;
        _lkVideoTrackSid = videoPub?.sid;
        debugPrint(
          'LiveKit: published camera track sid=${_lkVideoTrackSid ?? 'unknown'}',
        );
      } catch (e) {
        debugPrint('LiveKit: failed to publish video track: ${e.toString()}');
      }

      // Create and publish local microphone track
      try {
        final localAudio = await LocalAudioTrack.create(
          const AudioCaptureOptions(),
        );
        final audioPub = await room.localParticipant?.publishAudioTrack(
          localAudio,
        );
        _lkAudioTrack = localAudio;
        _lkAudioTrackSid = audioPub?.sid;
        debugPrint(
          'LiveKit: published microphone track sid=${_lkAudioTrackSid ?? 'unknown'}',
        );
      } catch (e) {
        debugPrint('LiveKit: failed to publish audio track: ${e.toString()}');
      }

      // Persist LiveKit session to Supabase
      final nowIso = DateTime.now().toIso8601String();
      final insertData = {
        'user_id': user.id,
        'title': title ?? 'Jitsi Stream',
        'description': description ?? '',
        'tags': tags ?? [],
        'provider': 'jitsi',
        'status': 'live',
        'viewer_count': 0,
        'started_at': nowIso,
        'created_at': nowIso,
        'is_ephemeral': isEphemeral,
        'saved_locally': savedLocally,
        'local_file_path': localFilePath,
      };
      final inserted = await _client
          .from('live_streams')
          .insert(insertData)
          .select()
          .single();
      _currentStreamId = inserted['id'] as String?;
      _isStreaming = true;

      // Notify followers that the user went live
      try {
        final social = SocialService();
        final followers = await social.getFollowers(user.id);
        final actorUsername = user.userMetadata?['username'] ?? 'Someone';
        final streamTitle = (title ?? 'Live Stream');
        for (final f in followers) {
          final followerId = f['follower_id'] as String?;
          if (followerId == null) continue;
          await social.createNotification(followerId, 'live', {
            'stream_id': _currentStreamId,
            'actor_id': user.id,
            'username': actorUsername,
            'title': streamTitle,
            'action_type': 'live',
          });
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint(
            'LiveStreamingService: error notifying followers (LiveKit) of live start: ${e.toString()}',
          );
        }
      }

      // Emit status or return info
      _streamStatusController.add({
        'provider': 'jitsi',
        'room': room.name,
        'status': 'connected',
        'stream_id': _currentStreamId,
      });
      debugPrint('Connected to LiveKit room: ${room.name}');
      return {
        'success': true,
        'provider': 'jitsi',
        'room': room.name,
        'status': 'connected',
        'stream_id': _currentStreamId,
      };
    } catch (e) {
      _streamStatusController.add({
        'provider': 'jitsi',
        'status': 'error',
        'message': e.toString(),
      });
      debugPrint('Error starting LiveKit publisher: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // Stop LiveKit publishing
  Future<void> stopLiveKitPublisher({
    int? finalDuration,
    bool? savedLocally,
    String? localFilePath,
  }) async {
    try {
      // Unpublish and stop local tracks first
      // removed unused variable 'participant'
      try {
        await _lkVideoTrack?.stop();
      } catch (e) {
        if (kDebugMode) {
          debugPrint('LiveKit: error stopping video track: ${e.toString()}');
        }
      }
      try {
        await _lkAudioTrack?.stop();
      } catch (e) {
        if (kDebugMode) {
          debugPrint('LiveKit: error stopping audio track: ${e.toString()}');
        }
      }

      _lkVideoTrack = null;
      _lkAudioTrack = null;
      _lkVideoTrackSid = null;
      _lkAudioTrackSid = null;

      // Update Supabase record if exists
      if (_currentStreamId != null) {
        final updateData = {
          'status': 'ended',
          'ended_at': DateTime.now().toIso8601String(),
          'final_viewer_count': _viewerCount,
          'final_duration': finalDuration,
        };
        if (savedLocally != null) {
          updateData['saved_locally'] = savedLocally;
        }
        if (localFilePath != null) {
          updateData['local_file_path'] = localFilePath;
        }
        await _client
            .from('live_streams')
            .update(updateData)
            .eq('id', _currentStreamId!);
      }

      // Disconnect from room
      await _lkRoom?.disconnect();
      _lkRoom = null;
      _isStreaming = false;
      _currentStreamId = null;

      _streamStatusController.add({
        'provider': 'jitsi',
        'status': 'disconnected',
      });
      if (kDebugMode) {
        debugPrint('Disconnected from LiveKit room');
      }
    } catch (e) {
      _streamStatusController.add({
        'provider': 'jitsi',
        'status': 'error',
        'message': e.toString(),
      });
      if (kDebugMode) {
        debugPrint('Error stopping LiveKit publisher: $e');
      }
    }
  }
}

// Live Stream Model
class LiveStreamModel {
  final String id;
  final String userId;
  final String title;
  final String description;
  final List<String> tags;
  final String provider;
  final String? jitsiRoomName;
  final String? jitsiStreamUrl;
  final String status;
  final int viewerCount;
  final DateTime startedAt;
  final DateTime? endedAt;
  final DateTime createdAt;
  // Ephemeral/local recording metadata
  final bool isEphemeral;
  final bool savedLocally;
  final String? localFilePath;
  final int? finalDuration;

  LiveStreamModel({
    required this.id,
    required this.userId,
    required this.title,
    required this.description,
    required this.tags,
    required this.provider,
    this.jitsiRoomName,
    this.jitsiStreamUrl,
    required this.status,
    required this.viewerCount,
    required this.startedAt,
    this.endedAt,
    required this.createdAt,
    // Ephemeral/local recording metadata
    required this.isEphemeral,
    required this.savedLocally,
    this.localFilePath,
    this.finalDuration,
  });

  factory LiveStreamModel.fromJson(Map<String, dynamic> json) {
    return LiveStreamModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      title: json['title'] as String,
      description: json['description'] as String,
      tags: List<String>.from(json['tags'] ?? []),
      provider: json['provider'] as String? ?? 'livekit',
      jitsiRoomName: json['jitsi_room_name'] as String?,
      jitsiStreamUrl: json['jitsi_stream_url'] as String?,
      status: json['status'] as String,
      viewerCount: json['viewer_count'] as int? ?? 0,
      startedAt: DateTime.parse(json['started_at'] as String),
      endedAt: json['ended_at'] != null
          ? DateTime.parse(json['ended_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      // Ephemeral/local recording metadata
      isEphemeral: json['is_ephemeral'] as bool? ?? false,
      savedLocally: json['saved_locally'] as bool? ?? false,
      localFilePath: json['local_file_path'] as String?,
      finalDuration: json['final_duration'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'title': title,
      'description': description,
      'tags': tags,
      'provider': provider,
      'jitsi_room_name': jitsiRoomName,
      'jitsi_stream_url': jitsiStreamUrl,
      'status': status,
      'viewer_count': viewerCount,
      'started_at': startedAt.toIso8601String(),
      'ended_at': endedAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'is_ephemeral': isEphemeral,
      'saved_locally': savedLocally,
      'local_file_path': localFilePath,
      'final_duration': finalDuration,
    };
  }

  String? get streamUrl => jitsiStreamUrl;
}

// LiveKit: fetch an access token for joining/publishing in a room
Future<Map<String, dynamic>> fetchLiveKitToken({
  required String room,
  required String identity,
  String? name,
  bool canPublish = true,
  bool canSubscribe = true,
  bool canPublishData = true,
  int ttlSeconds = 600,
  Map<String, dynamic>? metadata,
}) async {
  try {
    final response = await SupabaseConfig.client.functions.invoke(
      'livekit-token',
      body: {
        'room': room,
        'identity': identity,
        'name': name ?? identity,
        'canPublish': canPublish,
        'canSubscribe': canSubscribe,
        'canPublishData': canPublishData,
        'ttlSeconds': ttlSeconds,
        'metadata': metadata,
      },
    );

    if (response.data == null) {
      throw Exception('livekit-token returned no data');
    }

    final data = Map<String, dynamic>.from(response.data as Map);
    if (!data.containsKey('token') || !data.containsKey('url')) {
      throw Exception('Invalid livekit-token response: ${response.data}');
    }

    if (kDebugMode) {
      debugPrint('LiveKit token fetched for room "$room"');
    }
    return data;
  } catch (e) {
    if (kDebugMode) {
      debugPrint('Error fetching LiveKit token: $e');
    }
    rethrow;
  }
}
