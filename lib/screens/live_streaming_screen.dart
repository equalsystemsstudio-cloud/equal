import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:async';
import 'dart:math';
// removed: import 'package:camera/camera.dart';
import 'package:rtmp_broadcaster/camera.dart';
import 'package:flutter/foundation.dart';
import '../config/feature_flags.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/auth_service.dart';
import '../services/live_streaming_service.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/localization_service.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
// Use web widget on web, stub on other platforms to avoid dart:html
// import '../widgets/jitsi_meet_web_widget_stub.dart'
//    if (dart.library.html) '../widgets/jitsi_meet_web_widget.dart';

class LiveStreamingScreen extends StatefulWidget {
  const LiveStreamingScreen({super.key});

  @override
  State<LiveStreamingScreen> createState() => _LiveStreamingScreenState();
}

class _LiveStreamingScreenState extends State<LiveStreamingScreen>
    with TickerProviderStateMixin {
  bool _isStreaming = false;
  bool _isCameraOn = true;
  bool _isMicOn = true;
  bool _isFlashOn = false;
  bool _isFrontCamera = true;
  int _viewerCount = 0; // ignore: unused_field
  int _streamDuration = 0;
  Timer? _streamTimer;

  final RTCVideoRenderer _rtcRenderer = RTCVideoRenderer();

  // Jitsi integration
  // final JitsiMeetService _jitsiService = JitsiMeetService(); // removed
  // bool _isJitsiInitialized = false; // removed
  final AuthService _authService = AuthService();
  final LiveStreamingService _liveStreamingService = LiveStreamingService();
  LiveStreamModel? _currentLiveStream; // ignore: unused_field
  String? _streamTitle;
  String? _streamDescription;
  // bool _useLiveKit = true; // removed
  bool _saveToDevice = false; // Local recording toggle
  bool _isLocalRecording =
      false; // Tracks if local recording is currently active
  String? _localRecordingPath; // Saved local recording file path

  // RTMP state (mobile only)
  bool _isRtmpStreaming = false;
  String? _rtmpUrl;

  // Camera functionality
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isCameraInitialized = false;
  bool _isInitializing = false;

  late AnimationController _pulseController;
  late AnimationController _heartController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _heartAnimation;

  final List<String> _chatMessages = [];
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();
  bool _showChatOverlay = true; // Toggle to show/hide chat panel
  // Gifts overlay state (streamer-side)
  Map<String, dynamic>? _activeGift;
  bool _showGiftOverlay = false;
  StreamSubscription? _giftsSub;
  // Reactions overlay state (streamer-side)
  Map<String, dynamic>? _activeReaction;
  bool _showReactionOverlay = false;
  StreamSubscription? _reactionsSub;
  // Status updates (e.g., local stream updated -> rebind preview)
  StreamSubscription? _statusSub;
  // Debug overlay state
  bool _showDebugChip = true; // small status chip while streaming
  // Active participants cache (presence viewers)
  List<Map<String, dynamic>> _currentViewers = [];

  final List<Map<String, dynamic>> _streamEffects = [
    {'name': 'Beauty', 'icon': Icons.face_retouching_natural, 'active': false},
    {'name': 'Blur BG', 'icon': Icons.blur_on, 'active': false},
    {'name': 'Vintage', 'icon': Icons.photo_filter, 'active': false},
    {'name': 'Neon', 'icon': Icons.lightbulb, 'active': false},
  ];

  @override
  void initState() {
    super.initState();
    // Force portrait orientation for vertical video
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _initializeAnimations();
    _initializeCamera();
    _initializeRtcRenderer();
    // _initializeJitsi(); // Jitsi removed
  }

  Future<void> _initializeRtcRenderer() async {
    try {
      await _rtcRenderer.initialize();
    } catch (e) {
      if (kDebugMode) {
        debugPrint(('Error initializing RTC renderer: $e').toString());
      }
    }
  }

  void _setupRealtimeListeners() {
    // Subscribe regardless of provider; service manages channels internally
    _liveStreamingService.viewersStream.listen((viewers) {
      if (mounted) {
        setState(() {
          _viewerCount = viewers.length;
          _currentViewers = List<Map<String, dynamic>>.from(viewers);
        });
      }
    });

    _liveStreamingService.chatStream.listen((message) {
      if (mounted) {
        _addChatMessage(
          message['username'] ?? 'Anonymous',
          message['message'] ?? '',
        );
      }
    });

    // Subscribe to gift events for in-stream overlay
    _giftsSub?.cancel();
    _giftsSub = _liveStreamingService.giftsStream.listen((gift) {
      _triggerGiftOverlay(gift);
    });

    // Subscribe to reactions to show floating overlay
    _reactionsSub?.cancel();
    _reactionsSub = _liveStreamingService.reactionsStream.listen((reaction) {
      _triggerReactionOverlay(reaction);
    });

    // Subscribe to stream status to rebind preview when local stream changes
    _statusSub?.cancel();
    _statusSub = _liveStreamingService.streamStatusStream.listen((status) {
      final type = status['type']?.toString();
      if (type == 'local_stream_updated') {
        final local = _liveStreamingService.supabaseLocalStream;
        if (mounted && local != null) {
          setState(() {
            _rtcRenderer.srcObject = local;
          });
        }
      }
    });
  }

  Future<void> _initializeJitsi() async {
    // ignore: unused_element
    // No-op: removed
  }

  void _initializeAnimations() {
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);

    _heartController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _heartAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _heartController, curve: Curves.elasticOut),
    );
  }

  void _simulateViewers() {
    // ignore: unused_element
    Timer.periodic(const Duration(seconds: 3), (timer) {
      if (_isStreaming && mounted) {
        setState(() {
          _viewerCount += Random().nextInt(5) + 1;
        });
      }
    });
  }

  Future<void> _initializeCamera() async {
    if (_isInitializing) return;
    _isInitializing = true;

    try {
      if (kIsWeb) {
        // On web, camera access is handled by LiveKit (when streaming)
        // Skip native camera initialization
        if (mounted) {
          setState(() {
            _isCameraInitialized = true;
            _isInitializing = false;
          });
        }
        if (kDebugMode) {
          debugPrint(
            ('Web platform: Camera will be handled by LiveKit').toString(),
          );
        }
        return;
      }

      // Request camera and microphone permissions
      final cameraStatus = await Permission.camera.request();
      final micStatus = await Permission.microphone.request();

      if (cameraStatus != PermissionStatus.granted) {
        if (kDebugMode) {
          debugPrint(('Camera permission denied').toString());
        }
        _showPermissionDialog('Camera');
        return;
      }

      if (micStatus != PermissionStatus.granted) {
        if (kDebugMode) {
          debugPrint(('Microphone permission denied').toString());
        }
        _showPermissionDialog('Microphone');
        return;
      }

      // Get available cameras
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        if (kDebugMode) {
          debugPrint(('No cameras available').toString());
        }
        return;
      }

      // Initialize camera controller
      final cameraIndex = _isFrontCamera
          ? _cameras!.indexWhere(
              (camera) => camera.lensDirection == CameraLensDirection.front,
            )
          : _cameras!.indexWhere(
              (camera) => camera.lensDirection == CameraLensDirection.back,
            );

      final selectedCamera = cameraIndex >= 0
          ? _cameras![cameraIndex]
          : _cameras![0];

      _cameraController = CameraController(
        selectedCamera,
        ResolutionPreset.high,
        enableAudio: _isMicOn,
      );

      await _cameraController!.initialize();

      // Zoom level APIs are not available with rtmp_broadcaster on web; skipping.

      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
          _isInitializing = false;
        });
      }

      if (kDebugMode) {
        debugPrint(('Camera initialized successfully').toString());
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint(('Error initializing camera: $e').toString());
      }
      _isInitializing = false;
      _showErrorDialog('Failed to initialize camera: ${e.toString()}');
    }
  }

  void _showPermissionDialog(String permission) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: LocalizedText(
          'permission_required',
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: LocalizedText(
          permission.toLowerCase() == 'camera'
              ? 'camera_permission_required'
              : 'microphone_permission_required',
          style: GoogleFonts.poppins(color: Colors.grey[300]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: LocalizedText(
              'cancel',
              style: GoogleFonts.poppins(
                color: Colors.grey,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            child: LocalizedText(
              'Settings',
              style: GoogleFonts.poppins(
                color: Colors.blue,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: LocalizedText(
          'Error',
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: LocalizedText(
          message,
          style: GoogleFonts.poppins(color: Colors.grey[300]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: LocalizedText(
              'OK',
              style: GoogleFonts.poppins(
                color: Colors.blue,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleCameraDirection() async {
    if (!_isStreaming || _liveStreamingService.currentStreamId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: LocalizedText('start_stream_to_switch_camera_direction'),
        ),
      );
      return;
    }

    if (kIsWeb) {
      // On web, camera switching is handled by LiveKit (browser media APIs) during streaming
      setState(() {
        _isFrontCamera = !_isFrontCamera;
      });
      if (kDebugMode) {
        debugPrint(
          ('Web: Camera direction preference set to: ${_isFrontCamera ? "front" : "back"}')
              .toString(),
        );
      }
      return;
    }

    try {
      await _liveStreamingService.switchSupabaseCameraFacing(
        useFront: !_isFrontCamera,
      );
      final local = _liveStreamingService.supabaseLocalStream;
      if (mounted) {
        setState(() {
          _isFrontCamera = !_isFrontCamera;
          if (local != null) {
            _rtcRenderer.srcObject = local;
          }
        });
      }
      if (kDebugMode) {
        debugPrint(
          (
            'SupabaseRTC: camera direction switched to: ${_isFrontCamera ? "front" : "back"}',
          ).toString(),
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint(('Error switching Supabase camera: $e').toString());
      }
      _showErrorDialog('Failed to switch camera');
    }
  }

  Future<void> _toggleFlash() async {
    // Flash control is not supported in this screen with the current RTMP/mobile setup
    // On web, browsers generally do not expose flash control either
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: LocalizedText('flash_not_supported_on_camera')),
    );
  }

  // Duplicate local recording methods removed; see the single implementation earlier in the file.

  void _toggleMicrophone() {
    if (!_isStreaming || _liveStreamingService.currentStreamId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: LocalizedText('start_stream_to_toggle_microphone')),
      );
      return;
    }

    setState(() {
      _isMicOn = !_isMicOn;
    });

    if (kDebugMode) {
      debugPrint(('Microphone toggled: ${_isMicOn ? "on" : "off"}').toString());
    }

    // Toggle microphone for both providers (LiveKit and Supabase)
    _liveStreamingService.setLiveKitMicrophoneEnabled(_isMicOn);
    _liveStreamingService.setSupabaseMicrophoneEnabled(_isMicOn);
  }

  void _toggleCamera() {
    if (!_isStreaming || _liveStreamingService.currentStreamId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: LocalizedText('start_stream_to_toggle_camera')),
      );
      return;
    }

    setState(() {
      _isCameraOn = !_isCameraOn;
    });

    if (kDebugMode) {
      debugPrint(('Camera toggled: ${_isCameraOn ? "on" : "off"}').toString());
    }

    // Toggle camera for both providers (LiveKit and Supabase)
    _liveStreamingService.setLiveKitCameraEnabled(_isCameraOn);
    _liveStreamingService.setSupabaseCameraEnabled(_isCameraOn);
  }

  void _toggleChatOverlay() {
    if (!_isStreaming || _liveStreamingService.currentStreamId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: LocalizedText('start_stream_to_toggle_chat')),
      );
      return;
    }
    setState(() {
      _showChatOverlay = !_showChatOverlay;
    });
  }

  void _toggleEffect(int index) {
    setState(() {
      _streamEffects[index]['active'] = !_streamEffects[index]['active'];
    });

    final effect = _streamEffects[index];
    final status = effect['active'] ? 'enabled' : 'disabled';

    _addChatMessage(
      LocalizationService.t('system_label'),
      '${effect['name']} effect $status',
    );

    if (kDebugMode) {
      debugPrint(('Effect ${effect['name']} $status').toString());
    }
  }

  void _sendChatMessage() async {
    final message = _chatController.text.trim();
    if (message.isNotEmpty) {
      try {
        await _liveStreamingService.sendChatMessage(message);
        _chatController.clear();
      } catch (e) {
        if (kDebugMode) {
          debugPrint(('Error sending chat message: $e').toString());
        }
        // Fallback to local message
        _addChatMessage('You', message);
        _chatController.clear();
      }
    }
  }

  void _sendReaction(String reactionType) async {
    try {
      await _liveStreamingService.sendReaction(reactionType);
    } catch (e) {
      if (kDebugMode) {
        debugPrint(('Error sending reaction: $e').toString());
      }
    }
  }

  // Reaction overlay helpers
  String _emojiForReaction(String? key) {
    switch (key) {
      case 'heart':
        return '❤️';
      case 'fire':
        return '🔥';
      case 'star':
        return '⭐';
      case 'thumbs_up':
        return '👍';
      case 'party':
        return '🎉';
      case 'clap':
        return '👏';
      default:
        return '✨';
    }
  }

  void _triggerReactionOverlay(Map<String, dynamic> reaction) {
    setState(() {
      _activeReaction = reaction;
      _showReactionOverlay = true;
    });
    _heartController.forward(from: 0);
    Future.delayed(const Duration(milliseconds: 1000), () {
      if (!mounted) return;
      setState(() {
        _showReactionOverlay = false;
      });
    });
  }

  // Gift overlay helpers
  void _triggerGiftOverlay(Map<String, dynamic> gift) {
    setState(() {
      _activeGift = gift;
      _showGiftOverlay = true;
    });
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      setState(() {
        _showGiftOverlay = false;
      });
    });
  }

  IconData _iconForGiftKey(String? key) {
    switch (key) {
      case 'gift':
        return Icons.card_giftcard;
      case 'star':
        return Icons.star_rounded;
      case 'fire':
        return Icons.local_fire_department_rounded;
      case 'heart':
        return Icons.favorite_rounded;
      default:
        return Icons.emoji_objects_rounded;
    }
  }

  // Debug helpers
  String _debugProvider() {
    if (_liveStreamingService.supabaseLocalStream != null) {
      return 'Supabase WebRTC';
    }
    if (_liveStreamingService.liveKitRoom != null) {
      return 'LiveKit';
    }
    return 'Unknown';
  }

  Map<String, int> _debugTrackCounts() {
    final local = _liveStreamingService.supabaseLocalStream;
    final v = local?.getVideoTracks().length ?? 0;
    final a = local?.getAudioTracks().length ?? 0;
    return {'video': v, 'audio': a};
  }

  Widget _buildDebugStatusChip() {
    if (!_isStreaming || !_showDebugChip) return const SizedBox.shrink();
    final bound = _rtcRenderer.srcObject != null;
    final counts = _debugTrackCounts();
    final provider = _debugProvider();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.bug_report, color: Colors.white70, size: 16),
          const SizedBox(width: 6),
          Text(
            'RTC ${bound ? 'bound' : 'not bound'} • V:${counts['video']} A:${counts['audio']} • $provider',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  void _openDebugSheet() {
    final bound = _rtcRenderer.srcObject != null;
    final counts = _debugTrackCounts();
    final provider = _debugProvider();
    final streamId = _liveStreamingService.currentStreamId ?? '-';
    final roomName = _liveStreamingService.liveKitRoom?.name ?? '-';
    final lkRoom = _liveStreamingService.liveKitRoom;
    final lkRemoteCount = (lkRoom?.remoteParticipants.length ?? 0);
    final lkRemoteNames = lkRoom == null
        ? const <String>[]
        : (lkRoom.remoteParticipants.values
              .map((p) => (p.identity?.toString() ?? 'remote'))
              .toList());
    final lkLocalIdentity = lkRoom?.localParticipant?.identity?.toString();

    showModalBottomSheet(
      context: context,
      isScrollControlled: false,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final textStyle = GoogleFonts.poppins(
          color: Colors.white70,
          fontSize: 13,
        );
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Stream Debug',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text('Stream ID: $streamId', style: textStyle),
              const SizedBox(height: 6),
              Text('Provider: $provider', style: textStyle),
              const SizedBox(height: 6),
              Text('Preview bound: ${bound ? 'yes' : 'no'}', style: textStyle),
              const SizedBox(height: 6),
              Text(
                'Tracks (video/audio): ${counts['video']}/${counts['audio']}',
                style: textStyle,
              ),
              const SizedBox(height: 6),
              Text('LiveKit room: $roomName', style: textStyle),
              const SizedBox(height: 12),
              const Divider(color: Colors.white24),
              const SizedBox(height: 10),
              const Text(
                'Active Participants',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              // Presence viewers (Supabase)
              Text('Viewers (presence): $_viewerCount', style: textStyle),
              const SizedBox(height: 6),
              if (_currentViewers.isNotEmpty)
                ..._currentViewers
                    .take(8)
                    .map(
                      (v) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          '• ${(v['username'] ?? 'Anonymous').toString()}',
                          style: textStyle,
                        ),
                      ),
                    ),
              if (_currentViewers.isEmpty)
                Text('No viewers present', style: textStyle),
              const SizedBox(height: 12),
              // LiveKit participants (if applicable)
              if (provider == 'LiveKit') ...[
                Text(
                  'LiveKit participants: ${lkRemoteCount + (lkLocalIdentity != null ? 1 : 0)}',
                  style: textStyle,
                ),
                const SizedBox(height: 6),
                if (lkLocalIdentity != null)
                  Text('• You ($lkLocalIdentity)', style: textStyle),
                ...lkRemoteNames
                    .take(8)
                    .map(
                      (n) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text('• $n', style: textStyle),
                      ),
                    ),
                if (lkRemoteNames.isEmpty)
                  Text('No remote participants', style: textStyle),
                const SizedBox(height: 12),
              ],
              const Divider(color: Colors.white24),
              const SizedBox(height: 10),
              Row(
                children: [
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple,
                    ),
                    onPressed: () {
                      // Try to re-bind local preview to renderer (Supabase path)
                      final local = _liveStreamingService.supabaseLocalStream;
                      if (local != null) {
                        setState(() {
                          _rtcRenderer.srcObject = local;
                        });
                      }
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Attempted preview rebind'),
                        ),
                      );
                    },
                    child: const Text('Rebind Preview'),
                  ),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: () async {
                      final summary =
                          'stream_id=$streamId; provider=$provider; bound=${bound ? 'yes' : 'no'}; video=${counts['video']}; audio=${counts['audio']}; room=$roomName';
                      await Clipboard.setData(ClipboardData(text: summary));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Copied debug summary')),
                      );
                    },
                    child: const Text(
                      'Copy Summary',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _simulateViewerResponse(String userMessage) {
    // ignore: unused_element
    final responses = [
      'Great stream! 👍',
      'Love this content! ❤️',
      'Keep it up! 🔥',
      'Amazing! 🌟',
      'So cool! 😎',
      'Nice! 👌',
    ];

    // Add a random response after a short delay
    Timer(Duration(seconds: 1 + Random().nextInt(3)), () {
      if (_isStreaming && mounted) {
        final response = responses[Random().nextInt(responses.length)];
        _addChatMessage('Viewer${Random().nextInt(100)}', response);
      }
    });
  }

  void _addChatMessage(String username, String message) {
    setState(() {
      _chatMessages.add('$username: $message');
    });
    // Scroll to latest message
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _formatDuration(int seconds) {
    final d = Duration(seconds: seconds);
    String two(int n) => n.toString().padLeft(2, '0');
    if (d.inHours > 0) {
      return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
    }
    return '${two(d.inMinutes)}:${two(d.inSeconds % 60)}';
  }

  Future<void> _startStream() async {
    if (!_isCameraInitialized && !kIsWeb) {
      _showErrorDialog(LocalizationService.t('wait_for_camera_initialization'));
      return;
    }

    // Show stream setup dialog
    final streamInfo = await _showStreamSetupDialog();
    if (streamInfo == null) return;

    _streamTitle = streamInfo['title'];
    _streamDescription = streamInfo['description'];

    try {
      final user = _authService.currentUser;
      if (user == null) {
        _showErrorDialog(
          LocalizationService.t('please_log_in_to_start_streaming'),
        );
        return;
      }

      // Mobile RTMP path (only if RTMP URL provided and not web)
      if (!kIsWeb) {
        final rtmpUrl = streamInfo['rtmpUrl']?.trim();
        if (rtmpUrl != null && rtmpUrl.isNotEmpty) {
          if (_cameraController == null || !_isCameraInitialized) {
            _showErrorDialog(LocalizationService.t('camera_not_initialized'));
            return;
          }

          // Start RTMP streaming from the mobile camera
          await _cameraController!.startVideoStreaming(rtmpUrl);

          setState(() {
            _isStreaming = true;
            _isRtmpStreaming = true;
            _rtmpUrl = rtmpUrl;
            _streamDuration = 0;
            _viewerCount = 0;
          });

          _streamTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
            if (mounted) {
              setState(() {
                _streamDuration++;
              });
            }
          });

          // Start local recording if opted-in
          if (_saveToDevice && !kIsWeb) {
            try {
              final ctrl = _cameraController;
              final initialized = ctrl?.value.isInitialized == true;
              if (ctrl != null && initialized) {
                // Provide a file path as required by CameraController API
                final tmpDir = await getTemporaryDirectory();
                final filePath = '${tmpDir.path}/equal_stream_${DateTime.now().millisecondsSinceEpoch}.mp4';
                await ctrl.startVideoRecording(filePath);
                _localRecordingPath = filePath;
                setState(() {
                  _isLocalRecording = true;
                });
              }
            } catch (e) {
              if (kDebugMode) {
                debugPrint(('Failed to start local recording: $e').toString());
              }
            }
          }

          // Setup real-time listeners (e.g., viewers/reactions via Supabase channels)
          _setupRealtimeListeners();

          _addChatMessage(
            LocalizationService.t('system_label'),
            LocalizationService.t('stream_started_celebration'),
          );

          if (kDebugMode) {
            debugPrint(
              ('RTMP stream started to URL: $rtmpUrl by user: ${user.id}').toString(),
            );
          }
          return; // Done with RTMP path
        }
      }

      // Supabase WebRTC path (default)
      final rtcResult = await _liveStreamingService.startSupabasePublisher(
        title: _streamTitle!,
        description: _streamDescription,
        tags: const ['live', 'streaming'],
        isEphemeral: true,
        savedLocally: _saveToDevice && !kIsWeb,
        localFilePath: null,
      );
      if (rtcResult['success'] != true) {
        throw Exception(
          'Failed to start Supabase WebRTC: ${rtcResult['error']?.toString() ?? 'unknown error'}',
        );
      }

      // Bind local preview to RTC renderer
      final localStream = _liveStreamingService.supabaseLocalStream;
      if (localStream != null) {
        _rtcRenderer.srcObject = localStream;
      }

      setState(() {
        _isStreaming = true;
        _isRtmpStreaming = false;
        _rtmpUrl = null;
        _streamDuration = 0;
        _viewerCount = 0;
      });

      _streamTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted) {
          setState(() {
            _streamDuration++;
          });
        }
      });

      // Start local recording if opted-in
      if (_saveToDevice && !kIsWeb) {
        try {
          final ctrl = _cameraController;
          final initialized = ctrl?.value.isInitialized == true;
          if (ctrl != null && initialized) {
            final tmpDir = await getTemporaryDirectory();
            final filePath = '${tmpDir.path}/equal_stream_${DateTime.now().millisecondsSinceEpoch}.mp4';
            await ctrl.startVideoRecording(filePath);
            _localRecordingPath = filePath;
            setState(() {
              _isLocalRecording = true;
            });
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint(('Failed to start local recording: $e').toString());
          }
        }
      }

      // Setup real-time listeners (Supabase channels configured in service)
      _setupRealtimeListeners();

      _addChatMessage(
        LocalizationService.t('system_label'),
        LocalizationService.t('stream_started_celebration'),
      );

      if (kDebugMode) {
        debugPrint(
          ('Supabase WebRTC stream started by user: ${user.id}').toString(),
        );
      }
      return; // Done
    } catch (e) {
      final err = e.toString().toLowerCase();
      String msg = 'Error starting stream: $e';
      if (err.contains('permission') ||
          err.contains('denied') ||
          err.contains('notallowederror')) {
        msg =
            'Camera/Microphone permission denied. Please allow access in your browser or system settings and try again.';
      } else if (err.contains('notfounderror') ||
          err.contains('device') ||
          err.contains('unavailable') ||
          err.contains('no devices')) {
        msg =
            'No camera or microphone detected. Please connect a device and try again.';
      } else if (err.contains('security') ||
          err.contains('blocked') ||
          err.contains('insecure')) {
        msg =
            'Access blocked by browser security. Check site permissions and ensure you are using a secure (https) context.';
      }
      _showErrorDialog(msg);
    }
  }

  Future<void> _stopStream() async {
    try {
      // Stop local recording first and save
      if (_isLocalRecording) {
        if (!kIsWeb && _cameraController != null) {
          try {
            await _cameraController!.stopVideoRecording();
            setState(() {
              _isLocalRecording = false;
            });
            if (mounted && _localRecordingPath != null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: LocalizedText('Recording saved to: ${_localRecordingPath!}'),
                ),
              );
            }
          } catch (e) {
            _showErrorDialog('Failed to stop/save recording: $e');
            setState(() {
              _isLocalRecording = false;
            });
          }
        }
      }

      if (_isRtmpStreaming) {
        // Stop RTMP streaming
        try {
          await _cameraController?.stopVideoStreaming();
        } catch (e) {
          if (kDebugMode) {
            debugPrint(('Error stopping RTMP stream: $e').toString());
          }
        }
      } else {
        final int? finalDurationSeconds = _isStreaming ? _streamDuration : null;
        final bool? finalSavedLocally = (_localRecordingPath != null)
            ? true
            : null;
        final String? finalLocalFilePath = _localRecordingPath;

        // End Supabase WebRTC publisher
        await _liveStreamingService.stopSupabasePublisher(
          finalDuration: finalDurationSeconds,
          savedLocally: finalSavedLocally,
          localFilePath: finalLocalFilePath,
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint(('Error stopping stream: $e').toString());
      }
    }

    if (mounted) {
      setState(() {
        _isStreaming = false;
        _isRtmpStreaming = false;
        _rtmpUrl = null;
        _viewerCount = 0;
      });
    }
    _streamTimer?.cancel();
    _currentLiveStream = null;
    _streamTitle = null;
    _streamDescription = null;
    if (_rtcRenderer.srcObject != null) {
      _rtcRenderer.srcObject = null;
    }

    if (mounted) {
      _addChatMessage(
        LocalizationService.t('system_label'),
        LocalizationService.t('stream_ended_thanks'),
      );
    }

    if (kDebugMode) {
      debugPrint(
        (
          'Live stream stopped. Duration: ${_formatDuration(_streamDuration)}',
        ).toString(),
      );
    }
  }

  @override
  void dispose() {
    // If leaving while streaming, end the stream immediately
    if (_isStreaming) {
      // Non-blocking; _stopStream handles service updates
      _stopStream();
    }
    _pulseController.dispose();
    _heartController.dispose();
    _streamTimer?.cancel();
    _chatController.dispose();
    _chatScrollController.dispose();
    _cameraController?.dispose();
    if (_rtcRenderer.srcObject != null) {
      _rtcRenderer.srcObject = null;
    }
    _rtcRenderer.dispose();
    _giftsSub?.cancel();
    _reactionsSub?.cancel();
    _statusSub?.cancel();
    // Restore all orientations when leaving this screen
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_isStreaming) {
          final confirm = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) {
              return AlertDialog(
                title: const Text('End Stream?'),
                content: const Text(
                  'Leaving this screen will end your livestream immediately. Do you want to end the stream now?',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: const Text('End Stream'),
                  ),
                ],
              );
            },
          );
          if (confirm == true) {
            await _stopStream();
            return true;
          }
          return false;
        }
        return true;
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: _buildLiveStreamingBody(context),
      ),
    );
  }

  Widget _buildLiveStreamingBody(BuildContext context) {
    final preview = _isStreaming
        ? (_isRtmpStreaming && !kIsWeb && _cameraController != null)
            ? CameraPreview(_cameraController!)
            : _rtcRenderer.srcObject != null
                ? RTCVideoView(
                    _rtcRenderer,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  )
                : Container(
                    color: Theme.of(context).colorScheme.surface,
                    alignment: Alignment.center,
                    child: const Text(
                      'Starting stream…',
                      style: TextStyle(color: Colors.white70),
                    ),
                  )
        : (!kIsWeb && _isCameraInitialized && _cameraController != null)
        ? CameraPreview(_cameraController!)
        : Container(
            color: Theme.of(context).colorScheme.surface,
            alignment: Alignment.center,
            child: Text(
              kIsWeb
                  ? 'Press Start to activate camera via WebRTC'
                  : 'Initializing camera…',
              style: const TextStyle(color: Colors.white70),
            ),
          );

    return SafeArea(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Video preview (camera before start; RTC while streaming)
          Positioned.fill(child: preview),

          // Top overlay: viewer count + debug chip
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.remove_red_eye,
                        color: Colors.white70,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '$_viewerCount',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                _buildDebugStatusChip(),
                const SizedBox(width: 8),
                if (kDebugMode)
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black54,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    ),
                    onPressed: () async {
                      try {
                        final roomId = _liveStreamingService.currentStreamId;
                        if (roomId == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Start a stream first to get ZEGO token')),
                          );
                          return;
                        }
                        await _liveStreamingService.zegoHostTokenForCurrentUser(roomId: roomId);
                        _addChatMessage(LocalizationService.t('system_label'), 'ZEGO token fetched successfully.');
                      } catch (e) {
                        _showErrorDialog('ZEGO token fetch failed: $e');
                      }
                    },
                    child: const Text(
                      'Fetch ZEGO',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),

          // Right-side controls
          Positioned(
            right: 12,
            top: 80,
            child: Column(
              children: [
                _buildSideButton(
                  icon: Icons.chat_bubble,
                  onTap: _toggleChatOverlay,
                  isActive: _showChatOverlay,
                  disabled: !_isStreaming,
                  disabledMessage: 'start_stream_to_toggle_chat',
                ),
                const SizedBox(height: 12),
                _buildSideButton(
                  icon: Icons.emoji_emotions,
                  onTap: _openStickerSheet,
                  disabled: !_isStreaming || !FeatureFlags.liveReactionsEnabled,
                  disabledMessage: !_isStreaming
                      ? 'start_stream_to_send_stickers'
                      : 'reactions_disabled',
                ),
                const SizedBox(height: 12),
                _buildSideButton(
                  icon: Icons.cameraswitch,
                  onTap: _toggleCameraDirection,
                  disabled: !(_cameras != null && _cameras!.length >= 2),
                  disabledMessage: 'multiple_cameras_not_available',
                ),
                const SizedBox(height: 12),
                _buildSideButton(
                  icon: Icons.videocam,
                  onTap: _toggleCamera,
                  isActive: _isCameraOn,
                  disabled: !_isStreaming,
                  disabledMessage: 'start_stream_to_toggle_camera',
                ),
                const SizedBox(height: 12),
                _buildSideButton(
                  icon: Icons.mic,
                  onTap: _toggleMicrophone,
                  isActive: _isMicOn,
                  disabled: !_isStreaming,
                  disabledMessage: 'start_stream_to_toggle_microphone',
                ),
                const SizedBox(height: 12),
                _buildSideButton(
                  icon: Icons.flash_on,
                  onTap: _toggleFlash,
                  isActive: _isFlashOn,
                  disabled: kIsWeb || !_isStreaming,
                  disabledMessage: kIsWeb
                      ? 'flash_not_available_on_web'
                      : 'start_stream_to_toggle_flash',
                ),
              ],
            ),
          ),

          // Bottom bar: Start/Stop & save toggle
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.0),
                    Colors.black.withValues(alpha: 0.6),
                  ],
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Switch(
                        value: _saveToDevice,
                        onChanged: (v) {
                          setState(() => _saveToDevice = v);
                        },
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Save locally',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isStreaming
                          ? Colors.redAccent
                          : Colors.purple,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                    ),
                    onPressed: () async {
                      if (_isStreaming) {
                        await _stopStream();
                      } else {
                        await _startStream();
                      }
                    },
                    icon: Icon(
                      _isStreaming ? Icons.stop : Icons.wifi_tethering,
                      color: Colors.white,
                    ),
                    label: Text(
                      _isStreaming
                          ? 'End'
                          : LocalizationService.t('start_live_streaming'),
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Chat overlay: messages + input (visible while streaming)
          if (_isStreaming && _showChatOverlay)
            Positioned(
              left: 12,
              bottom: 100,
              child: Container(
                width: MediaQuery.of(context).size.width * 0.68,
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.38,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white24),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Messages list
                    Flexible(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                        child: ListView.builder(
                          controller: _chatScrollController,
                          itemCount: _chatMessages.length,
                          shrinkWrap: true,
                          itemBuilder: (_, i) {
                            final msg = _chatMessages[i];
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  msg,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 13,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    const Divider(height: 1, color: Colors.white24),
                    // Input row
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _chatController,
                              style: const TextStyle(color: Colors.white),
                              maxLines: 1,
                              decoration: InputDecoration(
                                hintText: 'Say something…',
                                hintStyle: const TextStyle(
                                  color: Colors.white54,
                                ),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 10,
                                ),
                                filled: true,
                                fillColor: Colors.black.withValues(alpha: 0.35),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(
                                    color: Colors.white24,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(
                                    color: Colors.white24,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(
                                    color: Colors.white38,
                                  ),
                                ),
                              ),
                              textInputAction: TextInputAction.send,
                              onSubmitted: (_) => _sendChatMessage(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: _sendChatMessage,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.purple,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                            ),
                            child: const Icon(Icons.send, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Quick reactions (bottom-right)
          if (_isStreaming && FeatureFlags.liveReactionsEnabled)
            Positioned(
              right: 12,
              bottom: 110,
              child: Column(
                children: [
                  _buildReactionButton('❤️', 'heart'),
                  const SizedBox(height: 8),
                  _buildReactionButton('🔥', 'fire'),
                  const SizedBox(height: 8),
                  _buildReactionButton('⭐', 'star'),
                ],
              ),
            ),

          // Floating reaction overlay (center)
          if (_isStreaming && _showReactionOverlay && _activeReaction != null)
            Positioned.fill(
              child: IgnorePointer(
                ignoring: true,
                child: AnimatedBuilder(
                  animation: _heartAnimation,
                  builder: (context, child) {
                    final scale = 0.8 + 0.4 * _heartAnimation.value;
                    final opacity = _heartAnimation.value;
                    final emoji = _emojiForReaction(
                      _activeReaction?['type']?.toString(),
                    );
                    return Center(
                      child: Opacity(
                        opacity: opacity,
                        child: Transform.scale(
                          scale: scale,
                          child: Text(
                            emoji,
                            style: const TextStyle(fontSize: 64),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

          // Timer badge while streaming
          if (_isStreaming)
            Positioned(
              bottom: 90,
              left: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white24),
                ),
                child: Text(
                  _formatDuration(_streamDuration),
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSideButton({
    required IconData icon,
    required VoidCallback onTap,
    bool isActive = false,
    bool disabled = false,
    String? disabledMessage,
  }) {
    return GestureDetector(
      onTap: () {
        if (disabled) {
          if (disabledMessage != null && disabledMessage.isNotEmpty) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: LocalizedText(disabledMessage)));
          }
          return;
        }
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: disabled
              ? Colors.black.withValues(alpha: 0.2)
              : (isActive
                    ? Colors.purple.withValues(alpha: 0.8)
                    : Colors.black.withValues(alpha: 0.5)),
          shape: BoxShape.circle,
          border: (isActive && !disabled)
              ? Border.all(color: Colors.purple, width: 2)
              : null,
        ),
        child: Icon(
          icon,
          color: disabled ? Colors.white54 : Colors.white,
          size: 20,
        ),
      ),
    );
  }

  Widget _buildReactionButton(String emoji, String reactionType) {
    // ignore: unused_element
    return GestureDetector(
      onTap: () => _sendReaction(reactionType),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
          shape: BoxShape.circle,
        ),
        child: Text(emoji, style: const TextStyle(fontSize: 20)),
      ),
    );
  }

  Future<void> _openStickerSheet() async {
    if (!_isStreaming) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: LocalizedText('start_stream_to_send_stickers')),
      );
      return;
    }
    if (!FeatureFlags.liveReactionsEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: LocalizedText('reactions_disabled')),
      );
      return;
    }

    final stickers = [
      {'emoji': '❤️', 'key': 'heart'},
      {'emoji': '🔥', 'key': 'fire'},
      {'emoji': '⭐', 'key': 'star'},
      {'emoji': '👍', 'key': 'thumbs_up'},
      {'emoji': '🎉', 'key': 'party'},
      {'emoji': '👏', 'key': 'clap'},
    ];

    await showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Choose a reaction',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: stickers.map((s) {
                    return GestureDetector(
                      onTap: () {
                        Navigator.of(context).pop();
                        _sendReaction(s['key']!);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Text(
                          s['emoji']!,
                          style: const TextStyle(fontSize: 28),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<Map<String, String>?> _showStreamSetupDialog() async {
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    final rtmpUrlController = TextEditingController(text: 'rtmp://YOUR_SERVER/live/your_stream_key');

    return showDialog<Map<String, String>>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: LocalizedText(
          'setup_stream',
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: LocalizationService.t('stream_title'),
                hintStyle: TextStyle(color: Colors.grey[400]),
                filled: true,
                fillColor: Colors.grey[800],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: descriptionController,
              style: const TextStyle(color: Colors.white),
              maxLines: 3,
              decoration: InputDecoration(
                hintText: LocalizationService.t('stream_description_optional'),
                hintStyle: TextStyle(color: Colors.grey[400]),
                filled: true,
                fillColor: Colors.grey[800],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (!kIsWeb)
              TextField(
                controller: rtmpUrlController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'RTMP server URL (e.g., rtmp://<host>/live/<stream_key>)',
                  hintStyle: TextStyle(color: Colors.grey[400]),
                  filled: true,
                  fillColor: Colors.grey[800],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const LocalizedText(
              'cancel',
              style: TextStyle(color: Colors.grey),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              if (titleController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: LocalizedText('please_enter_stream_title')),
                );
                return;
              }
              if (!kIsWeb && rtmpUrlController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter RTMP server URL')),
                );
                return;
              }
              Navigator.of(context).pop({
                'title': titleController.text.trim(),
                'description': descriptionController.text.trim(),
                'rtmpUrl': rtmpUrlController.text.trim(),
              });
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.purple),
            child: const LocalizedText('start_stream'),
          ),
        ],
      ),
    );
  }
}
