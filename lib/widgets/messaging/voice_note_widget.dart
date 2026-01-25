import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../models/message_model.dart';

class VoiceNoteWidget extends StatefulWidget {
  final MessageModel message;
  final bool isMe;
  final VoidCallback onPlay;
  final VoidCallback onStop;

  const VoiceNoteWidget({
    super.key,
    required this.message,
    required this.isMe,
    required this.onPlay,
    required this.onStop,
  });

  @override
  State<VoiceNoteWidget> createState() => _VoiceNoteWidgetState();
}

class _VoiceNoteWidgetState extends State<VoiceNoteWidget>
    with TickerProviderStateMixin {
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  AudioPlayer? _audioPlayer;
  
  late AnimationController _waveAnimationController;
  late Animation<double> _waveAnimation;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _initializeAudioPlayer();
  }

  void _setupAnimations() {
    _waveAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _waveAnimation = Tween<double>(
      begin: 0.3,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _waveAnimationController,
      curve: Curves.easeInOut,
    ));
  }

  void _initializeAudioPlayer() {
    _audioPlayer = AudioPlayer();
    
    _audioPlayer!.onDurationChanged.listen((duration) {
      if (mounted) {
        setState(() {
          _duration = duration;
        });
      }
    });

    _audioPlayer!.onPositionChanged.listen((position) {
      if (mounted) {
        setState(() {
          _position = position;
        });
      }
    });

    _audioPlayer!.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state == PlayerState.playing;
        });
        
        if (_isPlaying) {
          _waveAnimationController.repeat(reverse: true);
        } else {
          _waveAnimationController.stop();
        }
      }
    });

    // Stop animation and finalize position when playback completes
    _audioPlayer!.onPlayerComplete.listen((event) {
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _position = _duration > Duration.zero ? _duration : Duration.zero;
        });
        _waveAnimationController.stop();
      }
    });
  }

  Future<void> _togglePlayback() async {
    if (_audioPlayer == null) return;

    final url = widget.message.mediaUrl;
    if (url == null || url.isEmpty) return;

    if (_isPlaying) {
      await _audioPlayer!.pause();
    } else {
      await _audioPlayer!.play(UrlSource(url));
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final progress = _duration.inMilliseconds > 0
        ? _position.inMilliseconds / _duration.inMilliseconds
        : 0.0;

    return Container(
      width: 200,
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          GestureDetector(
            onTap: _togglePlayback,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: widget.isMe ? Colors.white.withValues(alpha: 0.2) : Colors.blue.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _isPlaying ? Icons.pause : Icons.play_arrow,
                color: widget.isMe ? Colors.white : Colors.blue,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildWaveform(progress),
                const SizedBox(height: 4),
                Text(
                  _duration.inMilliseconds > 0
                      ? _formatDuration(_isPlaying ? _position : _duration)
                      : _formatDuration(_position),
                  style: TextStyle(
                    color: widget.isMe
                        ? Colors.white.withValues(alpha: 0.8)
                        : Colors.grey[600],
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWaveform(double progress) {
    return AnimatedBuilder(
      animation: _waveAnimation,
      builder: (context, child) {
        return SizedBox(
          height: 30,
          child: Row(
            children: List.generate(20, (index) {
              final isActive = progress > (index / 20);
              final baseHeight = 4.0 + (index % 3) * 4.0;
              final animatedHeight = _isPlaying
                  ? baseHeight * _waveAnimation.value
                  : baseHeight;
              
              return Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  child: Align(
                    alignment: Alignment.center,
                    child: Container(
                      width: 2,
                      height: animatedHeight,
                      decoration: BoxDecoration(
                        color: isActive
                            ? (widget.isMe ? Colors.white : Colors.blue)
                            : (widget.isMe
                                ? Colors.white.withValues(alpha: 0.3)
                                : Colors.grey[400]),
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _audioPlayer?.dispose();
    _waveAnimationController.dispose();
    super.dispose();
  }
}
