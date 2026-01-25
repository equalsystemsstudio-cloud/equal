import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:math';
import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'package:file_picker/file_picker.dart';
import 'package:record/record.dart';
import '../services/posts_service.dart';
import '../services/storage_service.dart';
import '../services/auth_service.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/preferences_service.dart';
import '../services/localization_service.dart';

class AudioCreationScreen extends StatefulWidget {
  final String? parentPostId;
  const AudioCreationScreen({super.key, this.parentPostId});

  @override
  State<AudioCreationScreen> createState() => _AudioCreationScreenState();
}

class _AudioCreationScreenState extends State<AudioCreationScreen>
    with TickerProviderStateMixin {
  late AnimationController _waveController;
  late AnimationController _pulseController;
  late AnimationController _recordController;
  late Animation<double> _waveAnimation;
  late Animation<double> _pulseAnimation;
  late Animation<double> _recordAnimation;

  bool _isRecording = false;
  bool _isPlaying = false;
  bool _hasRecording = false;
  Duration _recordingDuration = Duration.zero;
  Duration _playbackPosition = Duration.zero;
  Timer? _recordingTimer;
  Timer? _playbackTimer;

  // Audio recording
  final AudioRecorder _audioRecorder = AudioRecorder();
  late AudioPlayer _audioPlayer;
  String? _audioPath;
  Uint8List? _audioBytes; // For web uploads
  String? _audioFileName; // For web: keep original filename from picker
  bool _isPermissionGranted = false;

  // Audio effects
  double _pitch = 1.0;
  double _speed = 1.0;
  double _reverb = 0.0;
  double _echo = 0.0;
  double _volume = 1.0;
  int _selectedEffect = 0;

  // UI state
  bool _showEffects = false;
  bool _showMusic = false;
  bool _showSettings = false;
  // Feature flag: toggle background music UI
  static const bool _enableBackgroundMusicUI = false;

  final TextEditingController _captionController = TextEditingController();
  final TextEditingController _hashtagController = TextEditingController();

  final List<Map<String, dynamic>> _voiceEffects = [
    {'key': 'original', 'icon': Icons.mic, 'pitch': 1.0, 'speed': 1.0},
    {
      'key': 'voice_effect_pitch_up_chipmunk',
      'icon': Icons.pets,
      'pitch': 1.5,
      'speed': 1.2,
    },
    {
      'key': 'voice_effect_low_pitch_synthetic',
      'icon': Icons.smart_toy,
      'pitch': 0.8,
      'speed': 0.9,
    },
    {
      'key': 'voice_effect_pitch_down_deep_voice',
      'icon': Icons.record_voice_over,
      'pitch': 0.6,
      'speed': 0.8,
    },
    {
      'key': 'voice_effect_balanced_no_echo',
      'icon': Icons.graphic_eq,
      'pitch': 1.0,
      'speed': 1.0,
    },
    {
      'key': 'voice_effect_soft_whisper',
      'icon': Icons.volume_down,
      'pitch': 0.9,
      'speed': 0.7,
    },
    {
      'key': 'voice_effect_slow_dramatic',
      'icon': Icons.theater_comedy,
      'pitch': 0.7,
      'speed': 0.6,
    },
    {
      'key': 'voice_effect_fast_high_alien',
      'icon': Icons.science,
      'pitch': 1.8,
      'speed': 1.5,
    },
  ];

  // Hide specific effects from the UI without removing underlying presets
  static const Set<String> _hiddenEffectKeys = {
    'voice_effect_balanced_no_echo',
    'voice_effect_soft_whisper',
    'voice_effect_slow_dramatic',
    'voice_effect_fast_high_alien',
  };

  List<int> get _visibleEffectIndices {
    return List<int>.generate(_voiceEffects.length, (i) => i)
        .where(
          (i) => !_hiddenEffectKeys.contains(_voiceEffects[i]['key'] as String),
        )
        .toList(growable: false);
  }

  final List<Map<String, dynamic>> _backgroundMusic = [
    {'name': 'None', 'icon': Icons.music_off, 'color': Colors.grey},
    {'name': 'Chill Beats', 'icon': Icons.headphones, 'color': Colors.blue},
    {'name': 'Upbeat Pop', 'icon': Icons.music_note, 'color': Colors.pink},
    {'name': 'Acoustic', 'icon': Icons.piano, 'color': Colors.brown},
    {
      'name': 'Electronic',
      'icon': Icons.electrical_services,
      'color': Colors.purple,
    },
    {'name': 'Jazz', 'icon': Icons.music_note, 'color': Colors.orange},
    {'name': 'Classical', 'icon': Icons.library_music, 'color': Colors.green},
    {'name': 'Hip Hop', 'icon': Icons.queue_music, 'color': Colors.red},
  ];

  // Discoverable free/open-source music platforms
  final List<Map<String, String>> _freeMusicSources = [
    {'name': 'Free Music Archive', 'url': 'https://freemusicarchive.org/'},
    {'name': 'ccMixter', 'url': 'https://ccmixter.org/'},
    {'name': 'Pixabay Music', 'url': 'https://pixabay.com/music/'},
    {
      'name': 'Incompetech',
      'url': 'https://incompetech.com/music/royalty-free/',
    },
  ];

  // Waveform data
  List<double> _waveformData = [];
  int _selectedMusic = 0;

  // Max audio recording duration options
  int _selectedAudioDuration = 0; // 0: 15s (default)
  final List<Map<String, dynamic>> _audioDurations = [
    {'name': '15s', 'seconds': 15},
    {'name': '30s', 'seconds': 30},
    {'name': '1min', 'seconds': 60},
    {'name': '5min', 'seconds': 300},
    {'name': 'Longer', 'seconds': -1}, // unlimited
  ];

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _initializeWaveform();
    _initializeAudio();
  }

  Future<void> _initializeAudio() async {
    _audioPlayer = AudioPlayer();
    await _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    final messenger = ScaffoldMessenger.of(context);
    final micStatus = await Permission.microphone.request();
    final cameraStatus = await Permission.camera.request();

    if (!mounted) return;
    setState(() {
      _isPermissionGranted =
          micStatus == PermissionStatus.granted &&
          (kIsWeb || cameraStatus == PermissionStatus.granted);
    });

    if (!_isPermissionGranted) {
      messenger.showSnackBar(
        SnackBar(
          content: LocalizedText(
            'Camera and microphone permissions are required to record audio',
          ),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 4),
        ),
      );
    }
  }

  void _initializeAnimations() {
    _waveController = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    )..repeat(reverse: true);

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat(reverse: true);

    _recordController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _waveAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _waveController, curve: Curves.easeInOut),
    );

    _pulseAnimation = Tween<double>(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _recordAnimation = Tween<double>(begin: 1.0, end: 0.9).animate(
      CurvedAnimation(parent: _recordController, curve: Curves.easeInOut),
    );
  }

  void _initializeWaveform() {
    // Initialize with empty waveform
    _waveformData = List.filled(100, 0.0);
  }

  void _updateWaveformData() {
    // In a real implementation, this would analyze actual audio data
    // For now, simulate realistic waveform based on recording state
    if (_isRecording) {
      final random = Random();
      // Simulate more realistic audio waveform patterns
      for (int i = 0; i < _waveformData.length; i++) {
        // Create more natural waveform patterns
        final baseAmplitude = 0.3 + (random.nextDouble() * 0.4);
        final variation = (random.nextDouble() - 0.5) * 0.3;
        _waveformData[i] = (baseAmplitude + variation).clamp(0.0, 1.0);
      }
    } else {
      // Gradually fade out waveform when not recording
      for (int i = 0; i < _waveformData.length; i++) {
        _waveformData[i] *= 0.95; // Fade effect
      }
    }
  }

  @override
  void dispose() {
    _waveController.dispose();
    _pulseController.dispose();
    _recordController.dispose();
    _recordingTimer?.cancel();
    _playbackTimer?.cancel();
    _captionController.dispose();
    _hashtagController.dispose();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  void _toggleRecording() {
    setState(() {
      _isRecording = !_isRecording;
    });

    if (_isRecording) {
      _startRecording();
    } else {
      _stopRecording();
    }
  }

  Future<void> _startRecording() async {
    final messenger = ScaffoldMessenger.of(context);
    if (!_isPermissionGranted) {
      await _requestPermissions();
      if (!_isPermissionGranted) return;
    }

    try {
      if (kIsWeb) {
        // For web, show message that recording is not available
        messenger.showSnackBar(
          SnackBar(
            content: LocalizedText(
              'Audio recording not available on web. Please use the import feature.',
            ),
          ),
        );
        if (!mounted) return;
        setState(() {
          _isRecording = false;
        });
        return;
      }

      // Get temporary directory for the recorded file
      String audioPath;
      try {
        final directory = await getTemporaryDirectory();
        audioPath =
            '${directory.path}/audio_${DateTime.now().millisecondsSinceEpoch}.m4a';
      } catch (e) {
        audioPath = 'audio_${DateTime.now().millisecondsSinceEpoch}.m4a';
      }
      _audioPath = audioPath;

      // Start audio recording
      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: audioPath,
      );

      _recordController.forward();
      _recordingDuration = Duration.zero;
      _recordingTimer = Timer.periodic(const Duration(milliseconds: 100), (
        timer,
      ) {
        // Update UI duration
        setState(() {
          _recordingDuration = Duration(milliseconds: timer.tick * 100);
        });
        _updateWaveformData(); // Update waveform visualization

        // Enforce max duration auto-stop
        final int limitSeconds =
            _audioDurations[_selectedAudioDuration]['seconds'] as int;
        if (limitSeconds > 0 &&
            _recordingDuration.inMilliseconds >= limitSeconds * 1000) {
          timer.cancel();
          // Auto-stop and save recording immediately at limit
          _stopRecording();
        }
      });

      debugPrint(('Started recording to: $_audioPath').toString());
    } catch (e) {
      debugPrint(('Error starting recording: $e').toString());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: LocalizedText('Failed to start recording: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _stopRecording() async {
    try {
      final messenger = ScaffoldMessenger.of(context);
      final recordedPath = await _audioRecorder.stop();

      if (recordedPath != null) {
        _audioPath = recordedPath;

        // For web, store bytes
        if (kIsWeb && File(recordedPath).existsSync()) {
          _audioBytes = await File(recordedPath).readAsBytes();
        }
      }

      _recordController.reverse();
      _recordingTimer?.cancel();
      if (!mounted) return;
      setState(() {
        _hasRecording = true;
      });

      debugPrint(('Recording stopped. File saved at: $_audioPath').toString());

      messenger.showSnackBar(
        const SnackBar(
          content: LocalizedText('Audio recording saved successfully!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      debugPrint(('Error stopping recording: $e').toString());
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        SnackBar(
          content: LocalizedText('Failed to stop recording: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  void _togglePlayback() {
    if (!_hasRecording) return;

    setState(() {
      _isPlaying = !_isPlaying;
    });

    if (_isPlaying) {
      _startPlayback();
    } else {
      _stopPlayback();
    }
  }

  Future<void> _startPlayback() async {
    // Validate recording/media presence to play
    final messenger = ScaffoldMessenger.of(context);
    if (kIsWeb) {
      if (_audioBytes == null) {
        messenger.showSnackBar(
          const SnackBar(
            content: LocalizedText('No audio file to play'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    } else {
      if (_audioPath == null || !File(_audioPath!).existsSync()) {
        messenger.showSnackBar(
          const SnackBar(
            content: LocalizedText('No audio file to play'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    try {
      if (kIsWeb) {
        await _audioPlayer.play(BytesSource(_audioBytes!));
      } else {
        await _audioPlayer.play(DeviceFileSource(_audioPath!));
      }
      await _applyPlaybackParams();

      _playbackTimer = Timer.periodic(const Duration(milliseconds: 100), (
        timer,
      ) async {
        final position = await _audioPlayer.getCurrentPosition();
        if (position != null) {
          if (!mounted) return;
          setState(() {
            _playbackPosition = position;
            if (_playbackPosition >= _recordingDuration) {
              _stopPlayback();
            }
          });
        }
      });
    } catch (e) {
      debugPrint(('Error playing audio: $e').toString());
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: LocalizedText('Failed to play audio: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _stopPlayback() async {
    try {
      await _audioPlayer.stop();
      _playbackTimer?.cancel();
      if (!mounted) return;
      setState(() {
        _isPlaying = false;
        _playbackPosition = Duration.zero;
      });
    } catch (e) {
      debugPrint(('Error stopping playback: $e').toString());
    }
  }

  Future<void> _importAudio() async {
    try {
      final messenger = ScaffoldMessenger.of(context);
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: false,
      );

      if (result != null) {
        // Stop any current playback
        if (_isPlaying) {
          await _stopPlayback();
        }

        // For web, use bytes directly; for mobile, use file path
        String? filePath;
        Uint8List? pickedBytes;
        String? pickedName;

        final PlatformFile pf = result.files.single;

        if (kIsWeb) {
          // Web: path is unavailable, use bytes and name
          pickedBytes = pf.bytes;
          pickedName = pf.name;
        } else {
          if (pf.path != null) {
            try {
              final directory = await getTemporaryDirectory();
              final newPath =
                  '${directory.path}/imported_audio_${DateTime.now().millisecondsSinceEpoch}.${pf.extension ?? 'mp3'}';
              await File(pf.path!).copy(newPath);
              filePath = newPath;
            } catch (e) {
              // If copy fails, fall back to original path when available
              if (pf.path != null) {
                filePath = pf.path!;
              }
            }
            pickedName = pf.name;
          }
        }

        // Determine duration using appropriate source
        Duration? duration;
        try {
          final audioPlayer = AudioPlayer();
          if (kIsWeb && pickedBytes != null) {
            await audioPlayer.setSourceBytes(pickedBytes);
          } else if (filePath != null) {
            await audioPlayer.setSourceDeviceFile(filePath);
          }
          duration = await audioPlayer.getDuration();
          await audioPlayer.dispose();
        } catch (e) {
          debugPrint(('Could not get audio duration: $e').toString());
          duration = const Duration(seconds: 30);
        }

        setState(() {
          if (kIsWeb) {
            _audioBytes = pickedBytes;
            _audioFileName = pickedName;
            _audioPath = null;
          } else {
            _audioPath = filePath;
            _audioBytes = null;
            _audioFileName = pickedName;
          }
          _hasRecording = true;
          _recordingDuration = duration ?? const Duration(seconds: 30);
          _playbackPosition = Duration.zero;
          _isRecording = false;
          _isPlaying = false;
        });

        messenger.showSnackBar(
          const SnackBar(
            content: LocalizedText('Audio imported successfully!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint(('Error importing audio: $e').toString());
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        SnackBar(
          content: LocalizedText('Failed to import audio: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  void _applyVoiceEffect(int index) {
    setState(() {
      _selectedEffect = index;
      _pitch = _voiceEffects[index]['pitch'];
      _speed = _voiceEffects[index]['speed'];
    });
    if (_isPlaying || _hasRecording) {
      _applyPlaybackParams();
    }
  }

  Future<void> _applyPlaybackParams() async {
    try {
      await _audioPlayer.setVolume(_volume.clamp(0.0, 1.0));
      final double rate = (_speed * _pitch).clamp(0.5, 2.0);
      await _audioPlayer.setPlaybackRate(rate);
    } catch (e) {
      debugPrint('Audio params apply error: $e');
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
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Animated Background
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.purple.withValues(alpha: 0.3),
                    Colors.blue.withValues(alpha: 0.3),
                    Colors.black,
                  ],
                ),
              ),
            ),
          ),

          // Camera Preview and Waveform Visualization
          Positioned.fill(
            child: Center(
              child: Container(
                height: 300,
                margin: const EdgeInsets.symmetric(horizontal: 40),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Waveform Visualization
                    SizedBox(
                      height: 200,
                      child: AnimatedBuilder(
                        animation: _waveAnimation,
                        builder: (context, child) {
                          return CustomPaint(
                            painter: WaveformPainter(
                              waveformData: _waveformData,
                              isRecording: _isRecording,
                              playbackPosition: _playbackPosition,
                              totalDuration: _recordingDuration,
                              animationValue: _waveAnimation.value,
                            ),
                            size: Size.infinite,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Top Controls
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Close Button
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),

                // Title
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.black.withValues(alpha: 0.7),
                        Colors.blue.withValues(alpha: 0.4),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.blue.withValues(alpha: 0.2),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: LocalizedText(
                    'create_audio',
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),

                // Settings Button
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _showSettings = !_showSettings;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _showSettings
                          ? Colors.blue.withValues(alpha: 0.8)
                          : Colors.black.withValues(alpha: 0.6),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.tune,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Recording Duration
          if (_isRecording || _hasRecording)
            Positioned(
              top: MediaQuery.of(context).size.height * 0.25,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(25),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isRecording
                            ? Icons.fiber_manual_record
                            : Icons.audiotrack,
                        color: _isRecording ? Colors.red : Colors.blue,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatDuration(
                          _isRecording ? _recordingDuration : _playbackPosition,
                        ),
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (_hasRecording && !_isRecording) ...[
                        const SizedBox(height: 16),
                        Text(
                          ' / ${_formatDuration(_recordingDuration)}',
                          style: GoogleFonts.poppins(
                            color: Colors.grey,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),

          // Side Controls
          Positioned(
            right: 20,
            top: MediaQuery.of(context).size.height * 0.35,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 10,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Column(
                children: [
                  _buildSideButton(
                    icon: Icons.auto_fix_high,
                    label: LocalizationService.t('effects'),
                    isActive: _showEffects,
                    onTap: () {
                      setState(() {
                        _showEffects = !_showEffects;
                        _showMusic = false;
                      });
                    },
                  ),
                  if (_enableBackgroundMusicUI) ...[
                    const SizedBox(height: 12),
                    _buildSideButton(
                      icon: Icons.library_music,
                      label: LocalizationService.t('music'),
                      isActive: _showMusic,
                      onTap: () {
                        setState(() {
                          _showMusic = !_showMusic;
                          _showEffects = false;
                        });
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Bottom Controls
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 30,
            left: 0,
            right: 0,
            child: Column(
              children: [
                // Playback Controls (when has recording)
                if (_hasRecording && !_isRecording)
                  Container(
                    margin: const EdgeInsets.only(bottom: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Play/Pause Button
                        GestureDetector(
                          onTap: _togglePlayback,
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.blue,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.blue.withValues(alpha: 0.3),
                                  blurRadius: 15,
                                  spreadRadius: 5,
                                ),
                              ],
                            ),
                            child: Icon(
                              _isPlaying ? Icons.pause : Icons.play_arrow,
                              color: Colors.white,
                              size: 32,
                            ),
                          ),
                        ),
                        const SizedBox(width: 20),
                        // Delete Recording
                        GestureDetector(
                          onTap: () async {
                            final messenger = ScaffoldMessenger.of(context);
                            try {
                              // Stop any ongoing playback
                              if (_isPlaying) {
                                await _stopPlayback();
                              }

                              // Delete the audio file if it exists
                              if (_audioPath != null &&
                                  File(_audioPath!).existsSync()) {
                                await File(_audioPath!).delete();
                              }

                              setState(() {
                                _hasRecording = false;
                                _recordingDuration = Duration.zero;
                                _playbackPosition = Duration.zero;
                                _audioPath = null;
                              });

                              messenger.showSnackBar(
                                SnackBar(
                                  content: LocalizedText('recording_deleted'),
                                  backgroundColor: Colors.orange,
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            } catch (e) {
                              debugPrint(
                                ('Error deleting recording: $e').toString(),
                              );
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.8),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.delete,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Recording Controls Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Import Button
                    if (!_isRecording && !_hasRecording)
                      GestureDetector(
                        onTap: _importAudio,
                        child: Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                            border: Border.all(color: Colors.purple, width: 3),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.purple.withValues(alpha: 0.3),
                                blurRadius: 15,
                                spreadRadius: 5,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.file_upload,
                            color: Colors.purple,
                            size: 28,
                          ),
                        ),
                      ),

                    if (!_isRecording && !_hasRecording)
                      const SizedBox(width: 30),

                    // Record Button
                    AnimatedBuilder(
                      animation: _recordAnimation,
                      builder: (context, child) {
                        return Transform.scale(
                          scale: _recordAnimation.value,
                          child: AnimatedBuilder(
                            animation: _pulseAnimation,
                            builder: (context, child) {
                              return Transform.scale(
                                scale: _isRecording
                                    ? _pulseAnimation.value
                                    : 1.0,
                                child: GestureDetector(
                                  onTap: _toggleRecording,
                                  child: Container(
                                    width: 80,
                                    height: 80,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: _isRecording
                                          ? Colors.red
                                          : Colors.white,
                                      border: Border.all(
                                        color: _isRecording
                                            ? Colors.red
                                            : Colors.blue,
                                        width: 4,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color:
                                              (_isRecording
                                                      ? Colors.red
                                                      : Colors.blue)
                                                  .withValues(alpha: 0.3),
                                          blurRadius: 20,
                                          spreadRadius: 8,
                                        ),
                                      ],
                                    ),
                                    child: Icon(
                                      _isRecording ? Icons.stop : Icons.mic,
                                      color: _isRecording
                                          ? Colors.white
                                          : Colors.blue,
                                      size: 36,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
                  ],
                ),

                // Share Button (when has recording)
                if (_hasRecording)
                  Column(
                    children: [
                      // Caption Input
                      Container(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 40,
                          vertical: 8,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.blue.withValues(alpha: 0.4),
                          ),
                        ),
                        child: TextField(
                          controller: _captionController,
                          style: GoogleFonts.poppins(color: Colors.white),
                          maxLines: 2,
                          minLines: 1,
                          decoration: InputDecoration(
                            hintText: LocalizationService.t('add_caption'),
                            hintStyle: GoogleFonts.poppins(
                              color: Colors.white70,
                            ),
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      // Hashtag Input
                      Container(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 40,
                          vertical: 8,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.purple.withValues(alpha: 0.4),
                          ),
                        ),
                        child: TextField(
                          controller: _hashtagController,
                          style: GoogleFonts.poppins(color: Colors.white),
                          maxLines: 1,
                          decoration: InputDecoration(
                            hintText: LocalizationService.t('hashtags_hint'),
                            hintStyle: GoogleFonts.poppins(
                              color: Colors.white70,
                            ),
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      Container(
                        margin: const EdgeInsets.only(top: 10),
                        width: MediaQuery.of(context).size.width - 80,
                        child: ElevatedButton(
                          onPressed: _publishPost,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(25),
                            ),
                            elevation: 8,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.send, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                LocalizationService.t('share_audio'),
                                style: GoogleFonts.poppins(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),

          // Effects Panel
          if (_showEffects)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 250,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.95),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      margin: const EdgeInsets.symmetric(vertical: 10),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    LocalizedText(
                      'voice_effects',
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Expanded(
                      child: GridView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 4,
                              crossAxisSpacing: 15,
                              mainAxisSpacing: 15,
                            ),
                        itemCount: _visibleEffectIndices.length,
                        itemBuilder: (context, index) {
                          final int effectIndex = _visibleEffectIndices[index];
                          final effect = _voiceEffects[effectIndex];
                          return GestureDetector(
                            onTap: () => _applyVoiceEffect(effectIndex),
                            child: Container(
                              decoration: BoxDecoration(
                                color: _selectedEffect == effectIndex
                                    ? Colors.blue.withValues(alpha: 0.3)
                                    : Colors.grey.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: _selectedEffect == effectIndex
                                      ? Colors.blue
                                      : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    effect['icon'],
                                    color: Colors.white,
                                    size: 24,
                                  ),
                                  const SizedBox(height: 8),
                                  LocalizedText(
                                    effect['key'] as String,
                                    style: GoogleFonts.poppins(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Music Panel (hidden via feature flag)
          if (_enableBackgroundMusicUI && _showMusic)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 250,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.95),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      margin: const EdgeInsets.symmetric(vertical: 10),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Text(
                      'Background Music',
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Expanded(
                      child: GridView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 4,
                              crossAxisSpacing: 15,
                              mainAxisSpacing: 15,
                            ),
                        itemCount: _backgroundMusic.length,
                        itemBuilder: (context, index) {
                          final music = _backgroundMusic[index];
                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                _selectedMusic = index;
                              });
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                color: _selectedMusic == index
                                    ? music['color'].withValues(alpha: 0.3)
                                    : Colors.grey.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: _selectedMusic == index
                                      ? music['color']
                                      : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    music['icon'],
                                    color: Colors.white,
                                    size: 24,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    music['name'],
                                    style: GoogleFonts.poppins(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: LocalizedText(
                          'explore_free_music_tip',
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _freeMusicSources.map((src) {
                          return GestureDetector(
                            onTap: () async {
                              final messenger = ScaffoldMessenger.of(context);
                              final url = src['url']!;
                              final uri = Uri.parse(url);
                              final launched = await launchUrl(
                                uri,
                                mode: LaunchMode.platformDefault,
                              );
                              if (!launched) {
                                if (!mounted) return;
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      '${LocalizationService.t('could_not_open')} ${src['name']}',
                                    ),
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                              }
                            },
                            onLongPress: () {
                              final messenger = ScaffoldMessenger.of(context);
                              final url = src['url']!;
                              Clipboard.setData(ClipboardData(text: url));
                              if (!mounted) return;
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '${LocalizationService.t('link_copied')}: ${src['name']}',
                                  ),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.blue.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.blueAccent),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.link,
                                    color: Colors.white,
                                    size: 14,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    src['name']!,
                                    style: GoogleFonts.poppins(
                                      color: Colors.white,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Settings Panel
          if (_showSettings)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 300,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.95),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      margin: const EdgeInsets.symmetric(vertical: 10),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    LocalizedText(
                      'audio_settings',
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Column(
                          children: [
                            _buildSettingSlider(
                              LocalizationService.t('volume'),
                              Icons.volume_up,
                              _volume,
                              0.0,
                              1.0,
                              (value) {
                                setState(() => _volume = value);
                                _audioPlayer.setVolume(_volume.clamp(0.0, 1.0));
                              },
                            ),
                            _buildSettingSlider(
                              LocalizationService.t('pitch'),
                              Icons.tune,
                              _pitch,
                              0.5,
                              2.0,
                              (value) {
                                setState(() => _pitch = value);
                                if (_isPlaying || _hasRecording) {
                                  _applyPlaybackParams();
                                }
                              },
                            ),
                            _buildSettingSlider(
                              LocalizationService.t('speed'),
                              Icons.speed,
                              _speed,
                              0.5,
                              2.0,
                              (value) {
                                setState(() => _speed = value);
                                if (_isPlaying || _hasRecording) {
                                  _applyPlaybackParams();
                                }
                              },
                            ),
                            _buildSettingSlider(
                              'Reverb',
                              Icons.surround_sound,
                              _reverb,
                              0.0,
                              1.0,
                              (value) => setState(() => _reverb = value),
                            ),
                            _buildSettingSlider(
                              'Echo',
                              Icons.graphic_eq,
                              _echo,
                              0.0,
                              1.0,
                              (value) => setState(() => _echo = value),
                            ),
                            const SizedBox(height: 12),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.timer,
                                    color: Colors.white70,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Max Duration',
                                    style: GoogleFonts.poppins(
                                      color: Colors.white70,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: List.generate(_audioDurations.length, (
                                index,
                              ) {
                                final isSelected =
                                    _selectedAudioDuration == index;
                                return ChoiceChip(
                                  label: Text(
                                    _audioDurations[index]['name'] as String,
                                    style: TextStyle(
                                      color: isSelected
                                          ? Colors.black
                                          : Colors.white,
                                    ),
                                  ),
                                  selected: isSelected,
                                  onSelected: (selected) {
                                    if (selected) {
                                      setState(() {
                                        _selectedAudioDuration = index;
                                      });
                                    }
                                  },
                                  selectedColor: Colors.white,
                                  backgroundColor: Colors.white10,
                                  shape: StadiumBorder(
                                    side: BorderSide(
                                      color: isSelected
                                          ? Colors.white
                                          : Colors.white24,
                                    ),
                                  ),
                                );
                              }),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSideButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isActive
              ? Colors.blue.withValues(alpha: 0.8)
              : Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive ? Colors.blue : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingSlider(
    String label,
    IconData icon,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.blue, size: 20),
              const SizedBox(width: 8),
              Text(
                label,
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              Text(
                value.toStringAsFixed(2),
                style: GoogleFonts.poppins(color: Colors.grey, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: Colors.blue,
              inactiveTrackColor: Colors.grey.withValues(alpha: 0.3),
              thumbColor: Colors.blue,
              overlayColor: Colors.blue.withValues(alpha: 0.2),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _publishPost() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    if (kIsWeb) {
      if (_audioBytes == null) {
        messenger.showSnackBar(
          const SnackBar(
            content: LocalizedText('No audio recording to publish'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    } else {
      if (_audioPath == null || !File(_audioPath!).existsSync()) {
        messenger.showSnackBar(
          const SnackBar(
            content: LocalizedText('No audio recording to publish'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    bool dialogShown = false;

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );
      dialogShown = true;

      final mediaUrl = await StorageService().uploadAudio(
        audioFile: kIsWeb ? null : File(_audioPath!),
        userId: AuthService().currentUser!.id,
        audioBytes: kIsWeb ? _audioBytes : null,
        fileName: kIsWeb ? _audioFileName : null,
      );

      final post = await PostsService().createPost(
        type: 'audio',
        caption: _captionController.text.trim().isEmpty
            ? null
            : _captionController.text.trim(),
        mediaUrl: mediaUrl,
        duration: _recordingDuration.inSeconds,
        hashtags: _hashtagController.text.trim().isEmpty
            ? null
            : _hashtagController.text.trim().split(' '),
        effects: {
          'name': LocalizationService.t(
            _voiceEffects[_selectedEffect]['key'] as String,
          ),
          'pitch': _pitch,
          'speed': _speed,
          'volume': _volume,
        },
        parentPostId: widget.parentPostId,
      );

      if (dialogShown) navigator.pop();

      messenger.showSnackBar(
        const SnackBar(
          content: LocalizedText('Audio posted successfully!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );

      // Display detection info if available (MusicBrainz)
      try {
        if (post != null) {
          final Map<String, dynamic>? aiMd =
              post.aiMetadata as Map<String, dynamic>?;
          final Map<String, dynamic>? detection = aiMd != null
              ? aiMd['copyright_detection'] as Map<String, dynamic>?
              : null;
          final bool matched =
              detection != null && (detection['match'] == true);
          if (matched) {
            final String artist =
                (detection?['artist'] as String?)?.trim() ?? '';
            final String title = (detection?['title'] as String?)?.trim() ?? '';
            if (artist.isNotEmpty || title.isNotEmpty) {
              final info = artist.isNotEmpty && title.isNotEmpty
                  ? 'Song detected: $artist — $title'
                  : artist.isNotEmpty
                  ? 'Song detected: $artist'
                  : 'Song detected: $title';
              messenger.showSnackBar(
                SnackBar(
                  content: LocalizedText(info),
                  backgroundColor: Colors.blue,
                  duration: const Duration(seconds: 4),
                ),
              );
            }
          }
        }
      } catch (_) {}

      if (!kIsWeb) {
        try {
          final savePref = await PreferencesService().getSaveToGallery();
          if (savePref) {
            messenger.showSnackBar(
              const SnackBar(
                content: LocalizedText(
                  'Audio saving to gallery is not supported yet',
                ),
                duration: Duration(seconds: 2),
              ),
            );
          }
        } catch (e) {
          messenger.showSnackBar(
            SnackBar(
              content: LocalizedText('Failed to save audio: ${e.toString()}'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }

      navigator.pop();
    } catch (e) {
      if (dialogShown) {
        try {
          navigator.pop();
        } catch (_) {}
      }

      String errorMessage = 'Failed to publish audio. Please try again.';
      final errorString = e.toString().toLowerCase();

      if (errorString.contains('network') ||
          errorString.contains('connection')) {
        errorMessage = 'Network error. Please check your internet connection.';
      } else if (errorString.contains('unauthorized') ||
          errorString.contains('401')) {
        errorMessage = 'Session expired. Please log in again.';
      } else if (errorString.contains('forbidden') ||
          errorString.contains('403')) {
        errorMessage = 'Access denied. Please check your permissions.';
      } else if (errorString.contains('timeout')) {
        errorMessage =
            'Upload timed out. Please try again with a smaller file.';
      } else if (errorString.contains('file size') ||
          errorString.contains('too large')) {
        errorMessage = 'Audio file is too large. Please choose a smaller file.';
      } else if (errorString.contains('format') ||
          errorString.contains('mime')) {
        errorMessage = 'Unsupported audio format. Please try recording again.';
      } else if (errorString.contains('storage') ||
          errorString.contains('bucket') ||
          errorString.contains('row-level security') ||
          errorString.contains('policy') ||
          errorString.contains('violates')) {
        errorMessage =
            'Storage error or configuration issue. Please try again later or contact support.';
      } else if (errorString.contains('server') ||
          errorString.contains('500')) {
        errorMessage = 'Server error. Please try again later.';
      }

      debugPrint(('Audio upload error: $e').toString());

      messenger.showSnackBar(
        SnackBar(
          content: LocalizedText(errorMessage),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }
}

class WaveformPainter extends CustomPainter {
  final List<double> waveformData;
  final bool isRecording;
  final Duration playbackPosition;
  final Duration totalDuration;
  final double animationValue;

  WaveformPainter({
    required this.waveformData,
    required this.isRecording,
    required this.playbackPosition,
    required this.totalDuration,
    required this.animationValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.blue
      ..strokeWidth = 2
      ..style = PaintingStyle.fill;

    final playedPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2
      ..style = PaintingStyle.fill;

    final recordingPaint = Paint()
      ..color = Colors.red
      ..strokeWidth = 2
      ..style = PaintingStyle.fill;

    final barWidth = size.width / waveformData.length;
    final centerY = size.height / 2;

    for (int i = 0; i < waveformData.length; i++) {
      final x = i * barWidth;
      final height =
          waveformData[i] *
          size.height *
          0.8 *
          (isRecording ? animationValue : 1.0);

      Paint currentPaint = paint;

      if (isRecording) {
        currentPaint = recordingPaint;
      } else if (totalDuration.inMilliseconds > 0) {
        final progress =
            playbackPosition.inMilliseconds / totalDuration.inMilliseconds;
        if (i / waveformData.length <= progress) {
          currentPaint = playedPaint;
        }
      }

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(x + barWidth / 2, centerY),
            width: barWidth * 0.8,
            height: height,
          ),
          const Radius.circular(2),
        ),
        currentPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
