import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:camera/camera.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../config/app_colors.dart';
import '../../services/status_service.dart';
import '../../services/ai_service.dart';
import '../../services/storage_service.dart';
import '../../services/video_filter_service.dart';
import '../../services/auth_service.dart';
import '../../models/status_model.dart';
import 'status_viewer_screen.dart';
import 'package:file_picker/file_picker.dart';
import '../../services/localization_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

enum MediaType { text, image, video, audio, aiPhoto }

class StatusCreateScreen extends StatefulWidget {
  const StatusCreateScreen({super.key});

  @override
  State<StatusCreateScreen> createState() => _StatusCreateScreenState();
}

class _StatusCreateScreenState extends State<StatusCreateScreen>
    with TickerProviderStateMixin {
  final _textController = TextEditingController();
  final _aiPromptController = TextEditingController();
  final _service = StatusService.of();
  final _aiService = AIService();
  final _imagePicker = ImagePicker();

  int _selectedHours = 24;
  bool _posting = false;
  MediaType _selectedMediaType = MediaType.text;

  // Media files
  XFile? _selectedImageFile;
  Uint8List? _selectedImageBytes;
  File? _selectedVideoFile;
  File? _selectedAudioFile;
  Uint8List? _selectedAudioBytes;
  String? _selectedAudioFileName;
  Uint8List? _aiGeneratedImage;
  // Audio recording state
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isAudioRecording = false;
  String? _recordedAudioPath;
  Timer? _audioTimer;
  Duration _audioDuration = Duration.zero;
  // ignore: unused_field
  String? _aiImageFileName;
  // Web video selection
  Uint8List? _selectedVideoBytes;
  String? _selectedVideoFileName;
  String? _thumbnailUrl;

  // Camera
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  // ignore: unused_field
  bool _isCameraInitialized = false;
  // ignore: unused_field
  final bool _isRecording = false;

  // Animations
  late AnimationController _slideController;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // AI Style Selection
  String _selectedAIStyle = 'realistic';
  bool _isGeneratingAI = false;
  late AnimationController _fadeController;
  late AnimationController _scaleController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;
  // ignore: unused_field
  late Animation<double> _scaleAnimation;

  // AI Generation
  // ignore: unused_field
  double _aiProgress = 0.0;

  final _options = const [6, 12, 24, 48];

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    if (!kIsWeb) {
      _initializeCamera();
    }
  }

  void _initializeAnimations() {
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _pulseController.repeat(reverse: true);

    _slideAnimation = Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
        );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _fadeController, curve: Curves.easeOut));

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.elasticOut),
    );

    _slideController.forward();
    _fadeController.forward();
    _scaleController.forward();
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras!.isNotEmpty) {
        _cameraController = CameraController(
          _cameras![0],
          ResolutionPreset.medium,
        );
        await _cameraController!.initialize();
        if (mounted) {
          setState(() {
            _isCameraInitialized = true;
          });
        }
        // Ensure default minimal zoom and respect camera aspect ratio
        try {
          final minZoom = await _cameraController!.getMinZoomLevel();
          // setZoomLevel not available in rtmp_broadcaster on web; skip applying.
        } catch (_) {}
      }
    } catch (e) {
      debugPrint(('Error initializing camera: $e').toString());
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _aiPromptController.dispose();
    _slideController.dispose();
    _fadeController.dispose();
    _scaleController.dispose();
    _pulseController.dispose();
    _cameraController?.dispose();
    // Stop any ongoing audio timers and dispose recorder
    _audioTimer?.cancel();
    _audioRecorder.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      if (mounted) {
        _showErrorSnackBar('You must be logged in to post a status.');
      }
      return;
    }

    // Validate content based on media type
    if (_selectedMediaType == MediaType.text &&
        _textController.text.trim().isEmpty) {
      _showErrorSnackBar('Write something for your status.');
      return;
    }

    if (_selectedMediaType == MediaType.image &&
        _selectedImageFile == null &&
        _aiGeneratedImage == null) {
      _showErrorSnackBar('Please select or generate an image.');
      return;
    }

    if (_selectedMediaType == MediaType.video &&
        _selectedVideoFile == null &&
        _selectedVideoBytes == null) {
      _showErrorSnackBar('Please select a video.');
      return;
    }

    if (_selectedMediaType == MediaType.audio && _isWebAudioInvalid()) {
      _showErrorSnackBar('Please record or select an audio file.');
      return;
    }

    setState(() => _posting = true);

    try {
      String? mediaUrl;

      // Upload media if not text-only
      if (_selectedMediaType != MediaType.text) {
        mediaUrl = await _uploadMedia();
      }

      // Post status with media
      await _service.createStatus(
        userId: user.id,
        text: _textController.text.trim(),
        mediaUrl: mediaUrl,
        mediaType: _selectedMediaType.name,
        ttl: Duration(hours: _selectedHours),
        // Propagate default audio effects for audio statuses
        effects: _selectedMediaType == MediaType.audio
            ? {'speed': 1.0, 'volume': 1.0}
            : null,
        thumbnailUrl: _thumbnailUrl,
      );

      if (mounted) {
        _showSuccessSnackBar('Status posted for $_selectedHours hours!');
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('Failed to post status: $e');
      }
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  Future<String?> _uploadMedia() async {
    final storageService = StorageService();
    final authService = AuthService();
    switch (_selectedMediaType) {
      case MediaType.image:
      case MediaType.aiPhoto:
        if (_aiGeneratedImage != null) {
          final inferredExt = _inferImageExtension(_aiGeneratedImage!);
          // Always use the inferred extension to avoid mismatched content types
          final baseName = 'ai_${DateTime.now().millisecondsSinceEpoch}';
          final effectiveFileName = '$baseName.$inferredExt';
          return await storageService.uploadImage(
            imageFile: null,
            imageBytes: _aiGeneratedImage!,
            fileName: effectiveFileName,
            userId: authService.currentUser!.id,
          );
        } else if (_selectedImageBytes != null) {
          final fileName =
              _selectedImageFile?.name ??
              'image_${DateTime.now().millisecondsSinceEpoch}.jpg';
          return await storageService.uploadImage(
            imageFile: null,
            imageBytes: _selectedImageBytes!,
            fileName: fileName,
            userId: authService.currentUser!.id,
          );
        }
        break;
      case MediaType.video:
        if (kIsWeb && _selectedVideoBytes != null) {
          // Transcode to MP4 (H.264/AAC) for cross-platform playback
          Uint8List bytes = _selectedVideoBytes!;
          try {
            // Prefer CRF-based compression for quality; downscale to 720p
            bytes = await VideoFilterService.compressVideo(
              input: bytes,
              scaleHeight: 720,
              audioKbps: 96,
              crf: 28,
            );
          } catch (_) {
            // If compression fails, fallback to original bytes (may be WebM)
          }
          // Generate a thumbnail from the compressed (or original) bytes
          Uint8List? thumb;
          try {
            thumb = await VideoFilterService.extractThumbnail(
              input: bytes,
              atSeconds: 0.2,
            );
          } catch (_) {
            thumb = null;
          }
          final fileName =
              _selectedVideoFileName ??
              'video_${DateTime.now().millisecondsSinceEpoch}.mp4';
          final thumbName =
              'thumb_${DateTime.now().millisecondsSinceEpoch}.jpg';
          return await storageService
              .uploadVideo(
                videoFile: null,
                userId: authService.currentUser!.id,
                videoBytes: bytes,
                videoFileName: fileName,
                thumbnailBytes: thumb,
                thumbnailFileName: thumb != null ? thumbName : null,
              )
              .then((urls) {
                _thumbnailUrl = urls['thumbnailUrl'];
                return urls['videoUrl'];
              });
        } else if (_selectedVideoFile != null) {
          // Mobile: generate thumbnail from file path
          Uint8List? thumb;
          try {
            thumb = await VideoFilterService().extractThumbnailPath(
              _selectedVideoFile!.path,
              atSeconds: 0.2,
            );
          } catch (_) {
            thumb = null;
          }
          final thumbName =
              'thumb_${DateTime.now().millisecondsSinceEpoch}.jpg';
          return await storageService
              .uploadVideo(
                videoFile: _selectedVideoFile!,
                userId: authService.currentUser!.id,
                thumbnailBytes: thumb,
                thumbnailFileName: thumb != null ? thumbName : null,
              )
              .then((urls) {
                _thumbnailUrl = urls['thumbnailUrl'];
                return urls['videoUrl'];
              });
        }
        break;
      case MediaType.audio:
        if (kIsWeb && _selectedAudioBytes != null) {
          final fileName =
              _selectedAudioFileName ??
              'audio_${DateTime.now().millisecondsSinceEpoch}.m4a';
          return await storageService.uploadAudio(
            audioFile: null,
            userId: authService.currentUser!.id,
            audioBytes: _selectedAudioBytes!,
            fileName: fileName,
          );
        } else if (_selectedAudioFile != null) {
          return await storageService.uploadAudio(
            audioFile: _selectedAudioFile!,
            userId: authService.currentUser!.id,
          );
        }
        break;
      default:
        break;
    }
    return null;
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: LocalizedText(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // Media selection methods
  Future<void> _selectImage() async {
    try {
      // Request photo/storage permission on mobile
      if (!kIsWeb) {
        if (Platform.isIOS) {
          final status = await Permission.photos.status;
          if (!status.isGranted) {
            final req = await Permission.photos.request();
            if (!req.isGranted) {
              _showErrorSnackBar('Photo access permission denied.');
              return;
            }
          }
        } else {
          final status = await Permission.storage.status;
          if (!status.isGranted) {
            final req = await Permission.storage.request();
            if (!req.isGranted) {
              _showErrorSnackBar('Storage permission denied.');
              return;
            }
          }
        }
      }

      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );
      if (image != null) {
        final bytes = await image.readAsBytes();
        setState(() {
          _selectedImageFile = image;
          _selectedImageBytes = bytes;
          _selectedMediaType = MediaType.image;
        });
      }
    } catch (e) {
      // Fallback: use FilePicker on mobile
      if (!kIsWeb) {
        try {
          final FilePickerResult? result = await FilePicker.platform.pickFiles(
            type: FileType.image,
            withData: true,
          );
          if (result != null && result.files.isNotEmpty) {
            final PlatformFile file = result.files.first;
            final Uint8List? bytes = file.bytes;
            if (bytes != null) {
              setState(() {
                _selectedImageFile = null;
                _selectedImageBytes = bytes;
                _selectedMediaType = MediaType.image;
              });
              return;
            }
          }
        } catch (_) {}
      }
      _showErrorSnackBar('Failed to select image: $e');
    }
  }

  Future<void> _takePhoto() async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: LocalizedText('camera_functionality_not_supported_on_web'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
      return;
    }

    try {
      if (!kIsWeb) {
        final camStatus = await Permission.camera.status;
        if (!camStatus.isGranted) {
          final req = await Permission.camera.request();
          if (!req.isGranted) {
            _showErrorSnackBar('Camera permission denied.');
            return;
          }
        }
      }

      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );
      if (image != null) {
        final bytes = await image.readAsBytes();
        setState(() {
          _selectedImageFile = image;
          _selectedImageBytes = bytes;
          _selectedMediaType = MediaType.image;
        });
      }
    } catch (e) {
      _showErrorSnackBar('Failed to take photo: $e');
    }
  }

  Future<void> _selectVideo() async {
    if (kIsWeb) {
      // Use FilePicker on web since ImagePicker's video selection is limited on web
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.video,
        withData: true,
      );
      if (result != null && result.files.isNotEmpty) {
        final PlatformFile file = result.files.first;
        final Uint8List? bytes = file.bytes;
        if (bytes != null) {
          setState(() {
            _selectedVideoBytes = bytes;
            _selectedVideoFileName = file.name;
            _selectedVideoFile = null;
            _selectedMediaType = MediaType.video;
          });
        } else {
          _showErrorSnackBar(
            'Failed to read selected video. Please try again.',
          );
        }
      }
      return;
    }

    try {
      // Request photo/storage permission on mobile for gallery access
      if (Platform.isIOS) {
        final status = await Permission.photos.status;
        if (!status.isGranted) {
          final req = await Permission.photos.request();
          if (!req.isGranted) {
            _showErrorSnackBar('Photo access permission denied.');
            return;
          }
        }
      } else {
        final status = await Permission.storage.status;
        if (!status.isGranted) {
          final req = await Permission.storage.request();
          if (!req.isGranted) {
            _showErrorSnackBar(
              LocalizationService.t('storage_permission_denied'),
            );
            return;
          }
        }
      }

      final XFile? video = await _imagePicker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(seconds: 15),
      );
      if (video != null) {
        setState(() {
          _selectedVideoFile = File(video.path);
          _selectedVideoBytes = null;
          _selectedVideoFileName = null;
          _selectedMediaType = MediaType.video;
        });
      }
    } catch (e) {
      // Fallback: FilePicker video selection
      try {
        final FilePickerResult? result = await FilePicker.platform.pickFiles(
          type: FileType.video,
        );
        if (result != null && result.files.isNotEmpty) {
          final String? path = result.files.first.path;
          if (path != null) {
            setState(() {
              _selectedVideoFile = File(path);
              _selectedVideoBytes = null;
              _selectedVideoFileName = result.files.first.name;
              _selectedMediaType = MediaType.video;
            });
            return;
          }
        }
      } catch (_) {}
      _showErrorSnackBar('Failed to select video: $e');
    }
  }

  Future<void> _recordVideo() async {
    if (kIsWeb) {
      // Recording via camera is not supported on web for ImagePicker
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: LocalizedText('video_functionality_not_supported_on_web'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
      return;
    }

    try {
      // Request camera and microphone permissions
      final camStatus = await Permission.camera.status;
      if (!camStatus.isGranted) {
        final reqCam = await Permission.camera.request();
        if (!reqCam.isGranted) {
          _showErrorSnackBar('Camera permission denied.');
          return;
        }
      }
      final micStatus = await Permission.microphone.status;
      if (!micStatus.isGranted) {
        final reqMic = await Permission.microphone.request();
        if (!reqMic.isGranted) {
          _showErrorSnackBar(
            LocalizationService.t('microphone_permission_denied'),
          );
          return;
        }
      }

      final XFile? video = await _imagePicker.pickVideo(
        source: ImageSource.camera,
        maxDuration: const Duration(seconds: 15),
      );
      if (video != null) {
        setState(() {
          _selectedVideoFile = File(video.path);
          _selectedVideoBytes = null;
          _selectedVideoFileName = null;
          _selectedMediaType = MediaType.video;
        });
      }
    } catch (e) {
      _showErrorSnackBar('${LocalizationService.t('failed_record_video')}: $e');
    }
  }

  Future<void> _pickAudioFromDevice() async {
    if (kIsWeb) {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        withData: true,
      );
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        setState(() {
          _selectedAudioBytes = file.bytes;
          _selectedAudioFile = null;
          _selectedAudioFileName = file.name;
          _selectedMediaType = MediaType.audio;
        });
      } else {
        _showErrorSnackBar(LocalizationService.t('no_audio_selected'));
      }
      return;
    }

    try {
      // Request storage permission on Android for file access
      if (Platform.isAndroid) {
        final status = await Permission.storage.status;
        if (!status.isGranted) {
          final req = await Permission.storage.request();
          if (!req.isGranted) {
            _showErrorSnackBar('Storage permission denied.');
            return;
          }
        }
      }

      final result = await FilePicker.platform.pickFiles(type: FileType.audio);
      if (result != null && result.files.isNotEmpty) {
        final path = result.files.first.path;
        if (path != null) {
          setState(() {
            _selectedAudioFile = File(path);
            _selectedAudioBytes = null;
            _selectedAudioFileName = result.files.first.name;
            _selectedMediaType = MediaType.audio;
          });
        } else {
          _showErrorSnackBar(LocalizationService.t('failed_read_audio_file'));
        }
      }
    } catch (e) {
      _showErrorSnackBar('${LocalizationService.t('failed_select_audio')}: $e');
    }
  }

  Future<void> _startAudioRecording() async {
    if (kIsWeb) {
      _showErrorSnackBar(
        LocalizationService.t('voice_recording_not_supported_web'),
      );
      return;
    }
    final micStatus = await Permission.microphone.status;
    if (!micStatus.isGranted) {
      final req = await Permission.microphone.request();
      if (!req.isGranted) {
        _showErrorSnackBar(
          LocalizationService.t('microphone_permission_denied'),
        );
        return;
      }
    }
    try {
      final dir = await getTemporaryDirectory();
      final filePath =
          '${dir.path}/status_audio_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: filePath,
      );
      setState(() {
        _isAudioRecording = true;
        _recordedAudioPath = filePath;
        _audioDuration = Duration.zero;
      });
      _audioTimer?.cancel();
      _audioTimer = Timer.periodic(const Duration(seconds: 1), (t) async {
        setState(() {
          _audioDuration = Duration(seconds: _audioDuration.inSeconds + 1);
        });
        if (_audioDuration.inSeconds >= 15) {
          t.cancel();
          await _stopAudioRecording();
        }
      });
    } catch (e) {
      _showErrorSnackBar('Failed to start recording: $e');
    }
  }

  Future<void> _stopAudioRecording() async {
    if (!_isAudioRecording) return;
    try {
      final recordedPath = await _audioRecorder.stop();
      _audioTimer?.cancel();
      setState(() {
        _isAudioRecording = false;
        if (recordedPath != null) {
          _selectedAudioFile = File(recordedPath);
          _selectedAudioBytes = null;
          _selectedAudioFileName = recordedPath
              .split(Platform.pathSeparator)
              .last;
          _selectedMediaType = MediaType.audio;
        }
      });
    } catch (e) {
      _showErrorSnackBar('Failed to stop recording: $e');
    }
  }

  Future<void> _generateAIImage() async {
    if (_aiPromptController.text.trim().isEmpty) {
      _showErrorSnackBar('Please enter a prompt for AI image generation.');
      return;
    }

    setState(() {
      _isGeneratingAI = true;
      _aiProgress = 0.0;
    });

    try {
      final imageData = await _aiService.generateImage(
        prompt: _aiPromptController.text.trim(),
        size: '1024x1024',
        style: 'realistic',
        onProgress: (progress) {
          setState(() {
            _aiProgress = progress;
          });
        },
      );

      if (imageData != null) {
        setState(() {
          _aiGeneratedImage = imageData;
          _aiImageFileName =
              'ai_${DateTime.now().millisecondsSinceEpoch}.png'; // default to PNG
          _selectedMediaType = MediaType.aiPhoto;
        });
        _showSuccessSnackBar('AI image generated successfully!');
      }
    } catch (e) {
      _showErrorSnackBar('Failed to generate AI image: $e');
    } finally {
      setState(() {
        _isGeneratingAI = false;
        _aiProgress = 0.0;
      });
    }
  }

  void _clearMedia() {
    setState(() {
      _selectedImageFile = null;
      _selectedImageBytes = null;
      _selectedVideoFile = null;
      _selectedVideoBytes = null;
      _selectedVideoFileName = null;
      _selectedAudioFile = null;
      // Clear audio bytes and name as well
      _selectedAudioBytes = null;
      _selectedAudioFileName = null;
      _aiGeneratedImage = null;
      _aiImageFileName = null;
      _selectedMediaType = MediaType.text;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.3),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.close, color: Colors.white),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Create Status',
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1a1a2e), Color(0xFF16213e), Color(0xFF0f3460)],
          ),
        ),
        child: SafeArea(
          child: SlideTransition(
            position: _slideAnimation,
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Column(
                children: [
                  StatusStrip(),
                  SizedBox(height: 8),
                  // Media Type Selector
                  _buildMediaTypeSelector(),

                  // Content Area (scrollable to prevent overflow on smaller screens)
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: EdgeInsets.only(
                        bottom: MediaQuery.of(context).viewPadding.bottom + 16,
                      ),
                      child: _buildContentArea(),
                    ),
                  ),

                  // Duration Selector
                  _buildDurationSelector(),

                  // Post Button
                  _buildPostButton(),

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMediaTypeSelector() {
    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          _buildMediaTypeButton(MediaType.text, Icons.text_fields, 'Text'),
          _buildMediaTypeButton(
            MediaType.image,
            Icons.image,
            LocalizationService.t('photo'),
          ),
          _buildMediaTypeButton(MediaType.video, Icons.videocam, 'Video'),
          _buildMediaTypeButton(MediaType.audio, Icons.mic, 'Audio'),
          _buildMediaTypeButton(MediaType.aiPhoto, Icons.auto_awesome, 'AI'),
        ],
      ),
    );
  }

  Widget _buildMediaTypeButton(MediaType type, IconData icon, String label) {
    final isSelected = _selectedMediaType == type;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          setState(() {
            _selectedMediaType = type;
          });
        },
        child: AnimatedBuilder(
          animation: _pulseAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: isSelected ? _pulseAnimation.value : 1.0,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.elasticOut,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  gradient: isSelected
                      ? LinearGradient(
                          colors: [
                            Colors.white,
                            Colors.white.withValues(alpha: 0.9),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                  color: isSelected ? null : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: Colors.white.withValues(alpha: 0.4),
                            blurRadius: 15,
                            spreadRadius: 3,
                            offset: const Offset(0, 5),
                          ),
                          BoxShadow(
                            color: Colors.white.withValues(alpha: 0.1),
                            blurRadius: 30,
                            spreadRadius: 10,
                            offset: const Offset(0, 15),
                          ),
                        ]
                      : null,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        icon,
                        color: isSelected ? Colors.black : Colors.white,
                        size: isSelected ? 22 : 20,
                      ),
                    ),
                    const SizedBox(height: 4),
                    AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 200),
                      style: GoogleFonts.poppins(
                        color: isSelected ? Colors.black : Colors.white,
                        fontSize: isSelected ? 11 : 10,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                      child: Text(label),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildContentArea() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 400),
        transitionBuilder: (Widget child, Animation<double> animation) {
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position:
                  Tween<Offset>(
                    begin: const Offset(0.0, 0.3),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                    ),
                  ),
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.8, end: 1.0).animate(
                  CurvedAnimation(parent: animation, curve: Curves.elasticOut),
                ),
                child: child,
              ),
            ),
          );
        },
        child: Container(
          key: ValueKey(_selectedMediaType),
          child: _buildContentForMediaType(),
        ),
      ),
    );
  }

  Widget _buildContentForMediaType() {
    switch (_selectedMediaType) {
      case MediaType.text:
        return _buildTextContent();
      case MediaType.image:
        return _buildImageContent();
      case MediaType.video:
        return _buildVideoContent();
      case MediaType.audio:
        return _buildAudioContent();
      case MediaType.aiPhoto:
        return _buildAIPhotoContent();
    }
  }

  Widget _buildTextContent() {
    return AnimatedBuilder(
      animation: _fadeAnimation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, (1 - _fadeAnimation.value) * 20),
          child: Opacity(
            opacity: _fadeAnimation.value,
            child: Container(
              constraints: const BoxConstraints(minHeight: 200, maxHeight: 400),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withValues(alpha: 0.08),
                    Colors.white.withValues(alpha: 0.03),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.15),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 20,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: TextField(
                controller: _textController,
                maxLines: null,
                minLines: 6,
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 16,
                  height: 1.5,
                ),
                decoration: InputDecoration(
                  hintText: 'Share what\'s on your mind...',
                  hintStyle: GoogleFonts.poppins(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 16,
                  ),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildImageContent() {
    return Column(
      children: [
        if (_selectedImageBytes != null || _aiGeneratedImage != null)
          Container(
            height: 300,
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 15,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: _selectedImageBytes != null
                  ? Image.memory(_selectedImageBytes!, fit: BoxFit.cover)
                  : Image.memory(_aiGeneratedImage!, fit: BoxFit.cover),
            ),
          )
        else
          Container(
            height: 200,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.2),
                width: 2,
                style: BorderStyle.solid,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.add_photo_alternate,
                  color: Colors.white.withValues(alpha: 0.5),
                  size: 48,
                ),
                const SizedBox(height: 16),
                Text(
                  'Add a photo to your status',
                  style: GoogleFonts.poppins(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),

        const SizedBox(height: 20),

        // Action buttons
        Row(
          children: [
            Expanded(
              child: _buildActionButton(
                'Gallery',
                Icons.photo_library,
                _selectImage,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildActionButton('Camera', Icons.camera_alt, _takePhoto),
            ),
            if (_selectedImageBytes != null || _aiGeneratedImage != null) ...[
              const SizedBox(width: 12),
              _buildClearButton(),
            ],
          ],
        ),

        const SizedBox(height: 16),

        // Caption input
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(15),
          ),
          child: TextField(
            controller: _textController,
            maxLines: 3,
            style: GoogleFonts.poppins(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Add a caption...',
              hintStyle: GoogleFonts.poppins(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 14,
              ),
              border: InputBorder.none,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVideoContent() {
    return Column(
      children: [
        if (_selectedVideoFile != null || _selectedVideoBytes != null)
          Container(
            height: 300,
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: Colors.black,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 15,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: const Center(
                child: Icon(
                  Icons.play_circle_fill,
                  color: Colors.white,
                  size: 64,
                ),
              ),
            ),
          )
        else
          Container(
            height: 200,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.2),
                width: 2,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.videocam,
                  color: Colors.white.withValues(alpha: 0.5),
                  size: 48,
                ),
                const SizedBox(height: 16),
                Text(
                  'Add a video to your status',
                  style: GoogleFonts.poppins(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),

        const SizedBox(height: 20),

        Row(
          children: [
            Expanded(
              child: _buildActionButton(
                'Gallery',
                Icons.video_library,
                _selectVideo,
              ),
            ),
            // Record temporarily hidden
            // const SizedBox(width: 12),
            // Expanded(
            //   child: _buildActionButton(
            //     'Record',
            //     Icons.videocam,
            //     _recordVideo,
            //   ),
            // ),
            if (_selectedVideoFile != null || _selectedVideoBytes != null) ...[
              const SizedBox(width: 12),
              _buildClearButton(),
            ],
          ],
        ),

        const SizedBox(height: 16),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(15),
          ),
          child: TextField(
            controller: _textController,
            maxLines: 3,
            style: GoogleFonts.poppins(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Add a caption...',
              hintStyle: GoogleFonts.poppins(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 14,
              ),
              border: InputBorder.none,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAudioContent() {
    return Column(
      children: [
        Container(
          height: 200,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.2),
              width: 2,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.mic,
                color: Colors.white.withValues(alpha: 0.5),
                size: 48,
              ),
              const SizedBox(height: 16),
              Text(
                'Record or add audio',
                style: GoogleFonts.poppins(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              if (_isAudioRecording) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Recording ${_audioDuration.inMinutes}:${(_audioDuration.inSeconds % 60).toString().padLeft(2, '0')}',
                      style: GoogleFonts.poppins(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ] else if (_selectedAudioFileName != null) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Text(
                    'Selected: ${_selectedAudioFileName}',
                    style: GoogleFonts.poppins(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 14,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 20),

        Row(
          children: [
            Expanded(
              child: _buildActionButton(
                'Gallery',
                Icons.library_music,
                _pickAudioFromDevice,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildActionButton(
                _isAudioRecording ? 'Stop' : 'Record',
                _isAudioRecording ? Icons.stop : Icons.mic,
                () => _isAudioRecording
                    ? _stopAudioRecording()
                    : _startAudioRecording(),
              ),
            ),
            if (_selectedAudioFile != null || _selectedAudioBytes != null) ...[
              const SizedBox(width: 12),
              _buildClearButton(),
            ],
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(15),
          ),
          child: TextField(
            controller: _textController,
            maxLines: 3,
            style: GoogleFonts.poppins(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Add a caption...',
              hintStyle: GoogleFonts.poppins(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 14,
              ),
              border: InputBorder.none,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAIPhotoContent() {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // AI Prompt Input with Glassmorphism Effect
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                colors: [
                  Colors.white.withValues(alpha: 0.1),
                  Colors.white.withValues(alpha: 0.05),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.2),
                width: 1,
              ),
            ),
            child: TextField(
              controller: _aiPromptController,
              style: GoogleFonts.poppins(color: Colors.white, fontSize: 16),
              decoration: InputDecoration(
                hintText: '✨ Describe your dream image...',
                hintStyle: GoogleFonts.poppins(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 16,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.all(20),
                prefixIcon: Icon(
                  Icons.auto_awesome,
                  color: Colors.white.withValues(alpha: 0.8),
                ),
              ),
              maxLines: 3,
            ),
          ),
          const SizedBox(height: 24),

          // AI Style Selector
          SizedBox(
            height: 60,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _buildStyleChip('🎨 Artistic', 'artistic'),
                _buildStyleChip('📸 Realistic', 'realistic'),
                _buildStyleChip('🌈 Fantasy', 'fantasy'),
                _buildStyleChip('🔮 Futuristic', 'futuristic'),
                _buildStyleChip('🎭 Dramatic', 'dramatic'),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Generate Button with Shimmer Effect
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: double.infinity,
            height: 56,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              gradient: _isGeneratingAI
                  ? LinearGradient(
                      colors: [
                        Colors.purple.withValues(alpha: 0.6),
                        Colors.blue.withValues(alpha: 0.6),
                      ],
                    )
                  : const LinearGradient(
                      colors: [
                        Color(0xFF6C5CE7),
                        Color(0xFFA29BFE),
                        Color(0xFF74B9FF),
                      ],
                    ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6C5CE7).withValues(alpha: 0.4),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(28),
                onTap: _isGeneratingAI ? null : _generateAIImage,
                child: Center(
                  child: _isGeneratingAI
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Creating Magic...',
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.auto_awesome,
                              color: Colors.white,
                              size: 24,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Generate AI Image',
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),

          // AI Generated Image Preview with Animations
          if (_aiGeneratedImage != null) ...[
            const SizedBox(height: 24),
            AnimatedContainer(
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOutBack,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Stack(
                  children: [
                    Image.memory(
                      _aiGeneratedImage!,
                      height: 300,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                    // Gradient Overlay for Better Text Visibility
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        height: 60,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.7),
                            ],
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Icon(
                                Icons.auto_awesome,
                                color: Colors.white,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'AI Generated',
                                  style: GoogleFonts.poppins(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: () => setState(() {
                                  _aiGeneratedImage = null;
                                }),
                                icon: const Icon(
                                  Icons.close,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(15),
              ),
              child: TextField(
                controller: _textController,
                maxLines: 3,
                style: GoogleFonts.poppins(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Add a caption...',
                  hintStyle: GoogleFonts.poppins(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 14,
                  ),
                  border: InputBorder.none,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionButton(
    String label,
    IconData icon,
    VoidCallback onTap, {
    Gradient? gradient,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          gradient:
              gradient ??
              LinearGradient(
                colors: [
                  Colors.white.withValues(alpha: 0.1),
                  Colors.white.withValues(alpha: 0.05),
                ],
              ),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClearButton() {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        _clearMedia();
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: Colors.red.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: const Icon(Icons.clear, color: Colors.red, size: 20),
      ),
    );
  }

  Widget _buildDurationSelector() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Disappear after',
            style: GoogleFonts.poppins(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: _options.asMap().entries.map((entry) {
              final index = entry.key;
              final h = entry.value;
              final selected = h == _selectedHours;
              return Expanded(
                child: AnimatedBuilder(
                  animation: _fadeAnimation,
                  builder: (context, child) {
                    return Transform.translate(
                      offset: Offset(
                        0,
                        (1 - _fadeAnimation.value) * (10 + index * 5),
                      ),
                      child: Opacity(
                        opacity: _fadeAnimation.value,
                        child: GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _selectedHours = h);
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.elasticOut,
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              gradient: selected
                                  ? const LinearGradient(
                                      colors: [
                                        Color(0xFF667eea),
                                        Color(0xFF764ba2),
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    )
                                  : null,
                              color: selected
                                  ? null
                                  : Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(15),
                              border: Border.all(
                                color: selected
                                    ? Colors.transparent
                                    : Colors.white.withValues(alpha: 0.2),
                                width: 1,
                              ),
                              boxShadow: selected
                                  ? [
                                      BoxShadow(
                                        color: const Color(
                                          0xFF667eea,
                                        ).withValues(alpha: 0.4),
                                        blurRadius: 15,
                                        spreadRadius: 2,
                                        offset: const Offset(0, 5),
                                      ),
                                      BoxShadow(
                                        color: const Color(
                                          0xFF764ba2,
                                        ).withValues(alpha: 0.3),
                                        blurRadius: 30,
                                        spreadRadius: 10,
                                        offset: const Offset(0, 15),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: AnimatedDefaultTextStyle(
                              duration: const Duration(milliseconds: 200),
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: selected ? 15 : 14,
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                letterSpacing: selected ? 0.5 : 0.0,
                              ),
                              child: Text('${h}h', textAlign: TextAlign.center),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildStyleChip(String label, String style) {
    final isSelected = _selectedAIStyle == style;
    return Container(
      margin: const EdgeInsets.only(right: 12),
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedAIStyle = style;
          });
          HapticFeedback.selectionClick();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            gradient: isSelected
                ? const LinearGradient(
                    colors: [Color(0xFF6C5CE7), Color(0xFFA29BFE)],
                  )
                : null,
            color: isSelected ? null : Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected
                  ? Colors.transparent
                  : Colors.white.withValues(alpha: 0.3),
              width: 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: const Color(0xFF6C5CE7).withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: 14,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPostButton() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      width: double.infinity,
      child: AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _posting ? 1.0 : (0.98 + (_pulseAnimation.value * 0.02)),
            child: GestureDetector(
              onTap: _posting
                  ? null
                  : () {
                      HapticFeedback.heavyImpact();
                      _submit();
                    },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(vertical: 18),
                decoration: BoxDecoration(
                  gradient: _posting
                      ? LinearGradient(
                          colors: [
                            Colors.grey.withValues(alpha: 0.6),
                            Colors.grey.withValues(alpha: 0.4),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : const LinearGradient(
                          colors: [
                            Color(0xFF667eea),
                            Color(0xFF764ba2),
                            Color(0xFF667eea),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          stops: [0.0, 0.5, 1.0],
                        ),
                  borderRadius: BorderRadius.circular(25),
                  boxShadow: _posting
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 10,
                            spreadRadius: 1,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : [
                          BoxShadow(
                            color: const Color(
                              0xFF667eea,
                            ).withValues(alpha: 0.5),
                            blurRadius: 20,
                            spreadRadius: 3,
                            offset: const Offset(0, 8),
                          ),
                          BoxShadow(
                            color: const Color(
                              0xFF764ba2,
                            ).withValues(alpha: 0.3),
                            blurRadius: 30,
                            spreadRadius: 5,
                            offset: const Offset(0, 15),
                          ),
                        ],
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder:
                      (Widget child, Animation<double> animation) {
                        return FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0.0, 0.2),
                              end: Offset.zero,
                            ).animate(animation),
                            child: child,
                          ),
                        );
                      },
                  child: _posting
                      ? Row(
                          key: const ValueKey('posting'),
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                                backgroundColor: Colors.white.withValues(
                                  alpha: 0.3,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Posting...',
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        )
                      : Text(
                          'Post Status',
                          key: const ValueKey('post'),
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.8,
                          ),
                        ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ignore: unused_element
  Widget _buildAIStyleButton(String label, String style) {
    final isSelected = _selectedAIStyle == style;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedAIStyle = style;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF6C5CE7)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF6C5CE7)
                : Colors.white.withValues(alpha: 0.1),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontSize: 14,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  bool _isWebAudioInvalid() {
    if (kIsWeb) {
      return _selectedAudioBytes == null;
    }
    return _selectedAudioFile == null;
  }

  String _inferImageExtension(Uint8List bytes) {
    try {
      if (bytes.length < 12) return 'png';
      final b0 = bytes[0];
      final b1 = bytes[1];
      final b2 = bytes[2];
      final b3 = bytes[3];
      // PNG: 89 50 4E 47
      if (b0 == 0x89 && b1 == 0x50 && b2 == 0x4E && b3 == 0x47) return 'png';
      // JPEG: FF D8 FF ..
      if (b0 == 0xFF && b1 == 0xD8) return 'jpg';
      // WEBP: RIFF....WEBP
      if (b0 == 0x52 && b1 == 0x49 && b2 == 0x46 && b3 == 0x46) {
        final sig = String.fromCharCodes(bytes.sublist(8, 12));
        if (sig == 'WEBP') return 'webp';
      }
      return 'png';
    } catch (_) {
      return 'png';
    }
  }
}

class StatusStrip extends StatefulWidget {
  const StatusStrip({super.key});

  @override
  State<StatusStrip> createState() => _StatusStripState();
}

class _StatusStripState extends State<StatusStrip> {
  final _service = StatusService.of();
  List<StatusModel> _statuses = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      setState(() {
        _loading = false;
        _statuses = [];
      });
      return;
    }
    // Load ONLY current user's statuses for the "Posted Statuses" strip
    try {
      final all = await _service.fetchUserStatuses(user.id);
      if (kDebugMode) {
        debugPrint(
          ('[StatusStrip] fetchUserStatuses returned ${all.length} items for user ${user.id}')
              .toString(),
        );
      }
      final active = all.where((s) => !s.isExpired).toList();
      if (kDebugMode) {
        debugPrint(
          ('[StatusStrip] Active (not expired) statuses count: ${active.length}')
              .toString(),
        );
      }
      if (mounted) {
        setState(() {
          _statuses = active;
          _loading = false;
        });
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint(('[StatusStrip] Error loading statuses: $e').toString());
      }
      if (mounted) {
        setState(() {
          _statuses = [];
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<StatusModel>>{};
    for (final s in _statuses) {
      grouped.putIfAbsent(s.userId, () => []).add(s);
    }
    final userIds = grouped.keys.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text(
                'Posted Statuses',
                style: TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 72,
          child: _loading
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : (userIds.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20.0),
                          child: Text(
                            'No posted statuses yet',
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      )
                    : ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        itemCount: userIds.length,
                        itemBuilder: (_, i) {
                          final uid = userIds[i];
                          final statuses = grouped[uid]!;
                          final first = statuses.first;
                          final name =
                              (first.displayName != null &&
                                  first.displayName!.trim().isNotEmpty)
                              ? first.displayName!
                              : (() {
                                  final u = first.username ?? 'User';
                                  return u.startsWith('@') ? u.substring(1) : u;
                                })();

                          // Find the latest posted photo or video thumbnail (list already ordered by created_at desc)
                          String? latestPhotoUrl;
                          for (final s in statuses) {
                            if (s.type == StatusType.image &&
                                (s.mediaUrl?.isNotEmpty ?? false)) {
                              latestPhotoUrl = s.mediaUrl;
                              break;
                            } else if (s.type == StatusType.video &&
                                (s.thumbnailUrl?.isNotEmpty ?? false)) {
                              latestPhotoUrl = s.thumbnailUrl;
                              break;
                            }
                          }

                          final fallbackAvatar = first.userAvatar;
                          final avatarUrl = latestPhotoUrl ?? fallbackAvatar;

                          final preview =
                              (first.type == StatusType.text &&
                                  (first.text?.trim().isNotEmpty ?? false))
                              ? first.text!.trim()
                              : (first.type == StatusType.image
                                    ? LocalizationService.t('photo')
                                    : (first.type == StatusType.video
                                          ? 'Video'
                                          : 'Status'));
                          return Padding(
                            padding: const EdgeInsets.only(right: 12.0),
                            child: Column(
                              children: [
                                GestureDetector(
                                  onTap: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => StatusViewerScreen(
                                          statuses: statuses,
                                          posterName: name,
                                          posterAvatarUrl: fallbackAvatar,
                                        ),
                                      ),
                                    );
                                  },
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      // Outer gradient ring
                                      Container(
                                        width: 48,
                                        height: 48,
                                        decoration: const BoxDecoration(
                                          shape: BoxShape.circle,
                                          gradient: LinearGradient(
                                            colors: [
                                              Color(0xFF8AB4F8), // bluish
                                              Color(0xFFFFFFFF), // whitish
                                              Color(0xFFFFD700), // goldish
                                            ],
                                            stops: [0.0, 0.5, 1.0],
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Color(0x668AB4F8),
                                              blurRadius: 8,
                                              spreadRadius: 1,
                                            ),
                                          ],
                                        ),
                                      ),
                                      // Inner circle background + avatar (latest photo or fallback)
                                      Container(
                                        width: 46,
                                        height: 46,
                                        margin: const EdgeInsets.all(1),
                                        decoration: const BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: Colors.black,
                                        ),
                                        child: CircleAvatar(
                                          radius: 22,
                                          backgroundImage: avatarUrl != null
                                              ? NetworkImage(avatarUrl)
                                              : null,
                                          child: avatarUrl == null
                                              ? const Icon(
                                                  Icons.person,
                                                  color: Colors.white,
                                                )
                                              : null,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 6),
                                SizedBox(
                                  width: 64,
                                  child: Text(
                                    preview,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      )),
        ),
      ],
    );
  }
}
