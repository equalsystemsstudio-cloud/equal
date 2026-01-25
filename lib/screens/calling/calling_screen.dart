import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import '../../services/calling_service.dart';
import '../../config/app_colors.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;

class CallingScreen extends StatefulWidget {
  final CallModel call;
  final bool isIncoming;

  const CallingScreen({
    super.key,
    required this.call,
    required this.isIncoming,
  });

  @override
  State<CallingScreen> createState() => _CallingScreenState();
}

class _CallingScreenState extends State<CallingScreen>
    with TickerProviderStateMixin {
  final CallingService _callingService = CallingService();
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late AnimationController _avatarController;
  late Animation<double> _avatarAnimation;
  
  StreamSubscription<CallModel>? _callSubscription;
  CallModel? _currentCall;
  Timer? _uiTimer;
  bool _isMuted = false;
  bool _isSpeakerOn = false;
  String _callStatusText = '';
  String _callDurationText = '00:00';
  Room? _lkRoom;
  RemoteVideoTrack? _remoteVideoTrack;
  LocalVideoTrack? _localVideoTrack;
  Timer? _videoProbeTimer;
  
  // New: differentiate caller tone and receiver vibration
  bool _outgoingTonePlayed = false;
  Timer? _vibrationTimer;
  
  // New: auto-missed-call timeout
  Timer? _missTimer;
  static const int _missTimeoutSeconds = 30;
  // New: periodic ringback loop for caller (outgoing)
  Timer? _ringbackTimer;

  @override
  void initState() {
    super.initState();
    _currentCall = widget.call;
    _setupAnimations();
    _setupCallListener();
    _updateCallStatus();
    _handleRingtoneOnStatus();
    _ensureMissTimeout();
    
    // Start UI update timer
    _uiTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        _updateCallDuration();
      }
    });
  }

  void _setupAnimations() {
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(
      begin: 1.0,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));

    _avatarController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );
    _avatarAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _avatarController,
      curve: Curves.elasticOut,
    ));

    _avatarController.forward();
    
    if (_currentCall?.status == CallStatus.calling || _currentCall?.status == CallStatus.ringing) {
      _pulseController.repeat(reverse: true);
    }
  }

  void _setupCallListener() {
    _callSubscription = _callingService.callStream.listen((call) {
      if (call.id == widget.call.id) {
        setState(() {
          _currentCall = call;
          _updateCallStatus();
          _handleRingtoneOnStatus();
          _ensureMissTimeout();
        });
        
        if (call.status == CallStatus.connected) {
          _pulseController.stop();
          _pulseController.reset();
          _stopVibration();
          _cancelMissTimeout();
          // Start RTC once connected
          () async {
            final ok = await _callingService.startRtcForCall(call);
            if (!ok) {
              final err = _callingService.lastRtcError ?? 'Failed to start audio/video';
              _showError(err);
            } else {
              _bindLiveKitRoomIfReady();
            }
          }();
        } else if (call.status == CallStatus.ended || call.status == CallStatus.declined) {
          _stopRingtone();
          _stopVibration();
          _cancelMissTimeout();
          _endCall();
        } else if (call.status == CallStatus.missed) {
          _stopRingtone();
          _stopVibration();
          _cancelMissTimeout();
          _callingService.markMissedCallAndNotify(widget.call.id);
          _endCall();
        }
      }
    });
  }

  void _updateCallStatus() {
    switch (_currentCall?.status) {
      case CallStatus.calling:
        _callStatusText = 'Calling...';
        break;
      case CallStatus.ringing:
        _callStatusText = 'Ringing...';
        break;
      case CallStatus.connected:
        _callStatusText = 'Connected';
        _stopRingtone();
        _stopVibration();
        break;
      case CallStatus.ended:
        _callStatusText = 'Call ended';
        _stopRingtone();
        _stopVibration();
        break;
      case CallStatus.declined:
        _callStatusText = 'Call declined';
        _stopRingtone();
        _stopVibration();
        break;
      case CallStatus.missed:
        _callStatusText = 'Missed call';
        _stopRingtone();
        _stopVibration();
        break;
      default:
        _callStatusText = 'Unknown';
    }
  }

  void _updateCallDuration() {
    if (_currentCall?.status == CallStatus.connected) {
      setState(() {
        _callDurationText = _callingService.formattedCallDuration;
      });
    }
  }

  Future<void> _answerCall() async {
    HapticFeedback.lightImpact();
    final success = await _callingService.answerCall(widget.call.id);
    _stopRingtone();
    _stopVibration();
    if (!success) {
      _showError('Failed to answer call');
    } else {
      // Start RTC immediately on successful answer
      final call = _currentCall;
      if (call != null) {
        final ok = await _callingService.startRtcForCall(call);
        if (!ok) {
          final err = _callingService.lastRtcError ?? 'Failed to start audio/video';
          _showError(err);
        } else {
          _bindLiveKitRoomIfReady();
        }
      }
    }
  }

  Future<void> _declineCall() async {
    HapticFeedback.mediumImpact();
    final success = await _callingService.declineCall(widget.call.id);
    _stopRingtone();
    _stopVibration();
    _stopRingback();
    if (success || !success) { // Always close on decline attempt
      _endCall();
    }
  }

  Future<void> _endCall() async {
    HapticFeedback.mediumImpact();
    _stopRingtone();
    _stopVibration();
    _stopRingback();
    await _callingService.endCall(widget.call.id);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  void _toggleMute() {
    setState(() {
      _isMuted = !_isMuted;
    });
    HapticFeedback.selectionClick();
    // Implement actual mute via LiveKit
    // ignore: discarded_futures
    _callingService.setLiveKitMicrophoneEnabled(!_isMuted);
  }

  void _toggleSpeaker() {
    setState(() {
      _isSpeakerOn = !_isSpeakerOn;
    });
    HapticFeedback.selectionClick();
    // Implement speaker functionality on mobile; web/desktop no-op
    if (!kIsWeb && (Theme.of(context).platform == TargetPlatform.android || Theme.of(context).platform == TargetPlatform.iOS)) {
      // Best-effort route switch; ignore errors
      webrtc.Helper.setSpeakerphoneOn(_isSpeakerOn).catchError((_) {});
    }
  }

  void _bindLiveKitRoomIfReady() {
    final room = _callingService.liveKitRoom;
    if (room == null) {
      // Retry shortly since startRtcForCall is async
      Future.delayed(const Duration(milliseconds: 300), _bindLiveKitRoomIfReady);
      return;
    }
    setState(() {
      _lkRoom = room;
      _localVideoTrack = _callingService.liveKitLocalVideoTrack;
    });
    _startRemoteVideoProbe();
  }
  
  void _startRemoteVideoProbe() {
    _videoProbeTimer?.cancel();
    _videoProbeTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      final room = _lkRoom;
      if (room == null) return;
      // Find first remote participant camera track
      for (final participant in room.remoteParticipants.values) {
        final pub = participant.getTrackPublicationBySource(TrackSource.camera);
        final track = pub?.track;
        if (track is RemoteVideoTrack) {
          setState(() {
            _remoteVideoTrack = track;
          });
          _videoProbeTimer?.cancel();
          _videoProbeTimer = null;
          return;
        }
      }
    });
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
      ),
    );
  }

  // Duplicate dispose removed to avoid compilation error.

  @override
  Widget build(BuildContext context) {
    final isVideoCall = _currentCall?.type == CallType.video;
    final otherUserName = widget.isIncoming 
        ? _currentCall?.callerName ?? 'Unknown'
        : _currentCall?.receiverName ?? 'Unknown';
    final otherUserAvatar = widget.isIncoming 
        ? _currentCall?.callerAvatar
        : _currentCall?.receiverAvatar;

    return Scaffold(
      backgroundColor: isVideoCall ? Colors.black : AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Top section with user info or video
            Expanded(
              flex: 3,
              child: isVideoCall && _currentCall?.status == CallStatus.connected
                  ? Stack(
                      children: [
                        Positioned.fill(
                          child: _remoteVideoTrack != null
                              ? VideoTrackRenderer(_remoteVideoTrack!)
                              : Container(color: Colors.black),
                        ),
                        if (_localVideoTrack != null)
                          Positioned(
                            right: 16,
                            bottom: 16,
                            child: Container(
                              width: 120,
                              height: 160,
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.4),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white24),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: VideoTrackRenderer(_localVideoTrack!),
                              ),
                            ),
                          ),
                        // Overlay labels
                        Positioned(
                          left: 0,
                          right: 0,
                          top: 0,
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Color.fromARGB(150, 0, 0, 0),
                                  Color.fromARGB(50, 0, 0, 0),
                                  Color.fromARGB(0, 0, 0, 0),
                                ],
                              ),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  otherUserName,
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _callStatusText + (_currentCall?.status == CallStatus.connected ? '  •  ' + _callDurationText : ''),
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.white.withValues(alpha: 0.85),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    )
                  : Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Avatar
                          ScaleTransition(
                            scale: _avatarAnimation,
                            child: AnimatedBuilder(
                              animation: _pulseAnimation,
                              builder: (context, child) {
                                return Transform.scale(
                                  scale: _pulseAnimation.value,
                                  child: Container(
                                    width: 150,
                                    height: 150,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: AppColors.primary.withValues(alpha: 0.3),
                                        width: 4,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppColors.primary.withValues(alpha: 0.2),
                                          blurRadius: 20,
                                          spreadRadius: 5,
                                        ),
                                      ],
                                    ),
                                    child: CircleAvatar(
                                      radius: 73,
                                      backgroundColor: AppColors.surface,
                                      backgroundImage: otherUserAvatar != null
                                          ? NetworkImage(otherUserAvatar)
                                          : null,
                                      child: otherUserAvatar == null
                                          ? Icon(
                                              Icons.person,
                                              size: 60,
                                              color: AppColors.textSecondary,
                                            )
                                          : null,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 24),
                          // User name
                          Text(
                            otherUserName,
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: isVideoCall ? Colors.white : AppColors.textPrimary,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          // Call status
                          Text(
                            _callStatusText,
                            style: TextStyle(
                              fontSize: 16,
                              color: isVideoCall 
                                  ? Colors.white.withValues(alpha: 0.8) 
                                  : AppColors.textSecondary,
                            ),
                          ),
                          // Call duration (only show when connected)
                          if (_currentCall?.status == CallStatus.connected) ...[
                            const SizedBox(height: 4),
                            Text(
                              _callDurationText,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w500,
                                color: isVideoCall ? Colors.white : AppColors.primary,
                              ),
                            ),
                          ],
                          // Call type indicator
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                isVideoCall ? Icons.videocam : Icons.call,
                                color: isVideoCall 
                                    ? Colors.white.withValues(alpha: 0.7) 
                                    : AppColors.primary,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                isVideoCall ? 'Video Call' : 'Voice Call',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: isVideoCall 
                                      ? Colors.white.withValues(alpha: 0.7) 
                                      : AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
            ),
            // Call controls
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 32),
              child: _buildCallControls(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCallControls() {
    final isConnected = _currentCall?.status == CallStatus.connected;
    final isIncomingCall = widget.isIncoming && 
        (_currentCall?.status == CallStatus.calling || _currentCall?.status == CallStatus.ringing);

    if (isIncomingCall) {
      // Incoming call controls
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Decline button
          _buildCallButton(
            icon: Icons.call_end,
            color: AppColors.error,
            onPressed: _declineCall,
            size: 64,
          ),
          // Answer button
          _buildCallButton(
            icon: Icons.call,
            color: AppColors.success,
            onPressed: _answerCall,
            size: 64,
          ),
        ],
      );
    } else if (isConnected) {
      // Connected call controls
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Mute button
          _buildCallButton(
            icon: _isMuted ? Icons.mic_off : Icons.mic,
            color: _isMuted ? AppColors.error : AppColors.surface,
            onPressed: _toggleMute,
            size: 56,
          ),
          // End call button
          _buildCallButton(
            icon: Icons.call_end,
            color: AppColors.error,
            onPressed: _endCall,
            size: 64,
          ),
          // Speaker button
          _buildCallButton(
            icon: _isSpeakerOn ? Icons.volume_up : Icons.volume_down,
            color: _isSpeakerOn ? AppColors.primary : AppColors.surface,
            onPressed: _toggleSpeaker,
            size: 56,
          ),
        ],
      );
    } else {
      // Outgoing call controls
      return Center(
        child: _buildCallButton(
          icon: Icons.call_end,
          color: AppColors.error,
          onPressed: _endCall,
          size: 64,
        ),
      );
    }
  }

  Widget _buildCallButton({
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
    required double size,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.3),
            blurRadius: 12,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(size / 2),
          onTap: onPressed,
          child: Icon(
            icon,
            color: Colors.white,
            size: size * 0.4,
          ),
        ),
      ),
    );
  }
  
  // New: ensure auto-miss timeout is scheduled while waiting
  void _ensureMissTimeout() {
    final status = _currentCall?.status;
    if (status == CallStatus.calling || status == CallStatus.ringing) {
      _missTimer ??= Timer(Duration(seconds: _missTimeoutSeconds), () async {
          final stillWaiting = _currentCall?.status == CallStatus.calling || _currentCall?.status == CallStatus.ringing;
          if (stillWaiting) {
            _stopRingtone();
            _stopVibration();
            await _callingService.markMissedCallAndNotify(widget.call.id);
            if (mounted) {
              _endCall();
            }
          }
        });
    } else {
      _cancelMissTimeout();
    }
  }

  void _cancelMissTimeout() {
    _missTimer?.cancel();
    _missTimer = null;
  }

  @override
  void dispose() {
    _callSubscription?.cancel();
    _uiTimer?.cancel();
    _stopRingtone();
    _stopVibration();
    _stopRingback();
    _cancelMissTimeout();
    _pulseController.dispose();
    _avatarController.dispose();
    _videoProbeTimer?.cancel();
    // Ensure RTC cleaned when screen goes away (endCall also cleans up)
    // ignore: discarded_futures
    _callingService.endRtcForCurrentCall();
    super.dispose();
  }

  void _startRingtone({bool looping = true}) {
    try {
      FlutterRingtonePlayer().play(
        android: AndroidSounds.ringtone,
        ios: IosSounds.electronic,
        looping: looping,
        volume: 0.8,
        asAlarm: false,
      );
    } catch (e) {
      debugPrint('Ringtone start failed: $e');
    }
  }

  // New: short outgoing tone for caller
  void _playOutgoingTone() {
    try {
      FlutterRingtonePlayer().play(
        android: AndroidSounds.notification,
        ios: IosSounds.triTone,
        looping: false,
        volume: 0.6,
        asAlarm: false,
      );
    } catch (e) {
      debugPrint('Outgoing tone failed: $e');
    }
  }

  // New: vibration for receiver while ringing
  void _startVibration() {
    if (_vibrationTimer != null) return;
    try {
      _vibrationTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        try {
          HapticFeedback.vibrate();
        } catch (e) {
          debugPrint('Vibration failed: $e');
        }
      });
    } catch (e) {
      debugPrint('Start vibration failed: $e');
    }
  }

  void _handleRingtoneOnStatus() {
    final status = _currentCall?.status;
    if (status == CallStatus.calling) {
      if (widget.isIncoming) {
        // Receiver: use device default ringtone while it is calling
        _startRingtone(looping: true);
        _startVibration();
      } else {
        // Caller: play a periodic ringback-style tone
        _stopRingtone();
        _stopVibration();
        _startRingbackLoop();
      }
      return;
    }
    if (status == CallStatus.ringing) {
      if (widget.isIncoming) {
        _startRingtone(looping: true);
        _startVibration();
      } else {
        // Caller: continue ringback loop during ringing
        _stopRingtone();
        _stopVibration();
        _startRingbackLoop();
      }
      return;
    }
    _stopRingtone();
    _stopVibration();
    _stopRingback();
  }

  void _stopVibration() {
    try {
      _vibrationTimer?.cancel();
      _vibrationTimer = null;
    } catch (e) {
      debugPrint('Stop vibration failed: $e');
    }
  }

  void _stopRingtone() {
    try {
      FlutterRingtonePlayer().stop();
    } catch (e) {
      debugPrint('Ringtone stop failed: $e');
    }
  }

  // New: start/stop a periodic ringback tone loop for caller side
  void _startRingbackLoop() {
    if (_ringbackTimer != null) return;
    try {
      _ringbackTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        try {
          FlutterRingtonePlayer().play(
            android: AndroidSounds.notification,
            ios: IosSounds.triTone,
            looping: false,
            volume: 0.5,
            asAlarm: false,
          );
        } catch (e) {
          debugPrint('Ringback play failed: $e');
        }
      });
    } catch (e) {
      debugPrint('Start ringback loop failed: $e');
    }
  }

  void _stopRingback() {
    try {
      _ringbackTimer?.cancel();
      _ringbackTimer = null;
    } catch (e) {
      debugPrint('Stop ringback failed: $e');
    }
  }
}
