import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:camera/camera.dart';
import 'package:image_picker/image_picker.dart';
import '../models/post_model.dart';
import '../services/posts_service.dart';
import '../services/auth_service.dart';
import '../services/storage_service.dart';
import '../widgets/post_widget.dart';
import '../config/app_colors.dart';
import 'dart:typed_data';
import 'dart:convert';
import '../services/video_filter_service.dart';
import 'package:http/http.dart' as http;
import '../services/localization_service.dart';

// Content mode enum
enum ContentMode { video, photo, text }

class HarmonyCreationScreen extends StatefulWidget {
  final PostModel originalPost;

  const HarmonyCreationScreen({super.key, required this.originalPost});

  @override
  State<HarmonyCreationScreen> createState() => _HarmonyCreationScreenState();
}

class _HarmonyCreationScreenState extends State<HarmonyCreationScreen>
    with TickerProviderStateMixin {
  // Services
  final PostsService _postsService = PostsService();
  final AuthService _authService = AuthService();

  // Camera and recording
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isRecording = false;
  bool _isInitialized = false;
  String? _recordedVideoPath;
  Duration _recordingElapsed = Duration.zero;

  // Import functionality
  final ImagePicker _imagePicker = ImagePicker();
  String? _importedMediaPath;
  Uint8List? _importedMediaBytes;
  String? _importedMediaFileName;
  bool _isVideo = false;
  bool _isPhoto = false; // ignore: unused_field

  // UI State
  bool _isLoading = false;
  final bool _showOriginalPost = true; // ignore: unused_field
  late AnimationController _recordButtonController;
  late Animation<double> _recordButtonAnimation;

  // Content modes
  final TextEditingController _textController = TextEditingController();
  ContentMode _contentMode = ContentMode.video;

  @override
  void initState() {
    super.initState();
    // Camera initialization removed for repost-style UI
    // _initializeCamera();
    _recordButtonController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _recordButtonAnimation = Tween<double>(begin: 1.0, end: 0.8).animate(
      CurvedAnimation(parent: _recordButtonController, curve: Curves.easeInOut),
    );
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras!.isNotEmpty) {
        _cameraController = CameraController(
          _cameras![0],
          ResolutionPreset.high,
          enableAudio: true,
        );
        await _cameraController!.initialize();
        try {
          final minZoom = await _cameraController!.getMinZoomLevel();
          // setZoomLevel not available in rtmp_broadcaster on web; skip applying.
        } catch (_) {}
        if (mounted) {
          setState(() {
            _isInitialized = true;
          });
        }
      }
    } catch (e) {
      debugPrint(('Error initializing camera: $e').toString());
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _recordButtonController.dispose();
    _textController.dispose();
    super.dispose();
  }

  Future<void> _toggleRecording() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    // Capture messenger prior to awaits and outside try/catch scope
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (_isRecording) {
        // Stop recording
        final video = await _cameraController!.stopVideoRecording();
        if (!mounted) return;
        setState(() {
          _isRecording = false;
          _recordedVideoPath = video.path;
        });
        _recordButtonController.reverse();
      } else {
        // Start recording
        await _cameraController!.startVideoRecording();
        if (!mounted) return;
        setState(() {
          _isRecording = true;
        });
        _recordButtonController.forward();
        _startRecordingTimer();
      }
    } catch (e) {
      debugPrint(('Error toggling recording: $e').toString());
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: LocalizedText('Recording error: ${e.toString()}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _importPhotoFromDevice() async {
    // Capture messenger before awaits and outside try/catch scope
    final messenger = ScaffoldMessenger.of(context);
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (image != null) {
        if (kIsWeb) {
          final bytes = await image.readAsBytes();
          final String fileName = image.name;
          if (!mounted) return;
          setState(() {
            _importedMediaBytes = bytes;
            _importedMediaFileName = fileName;
            _importedMediaPath = null;
            _isPhoto = true;
            _isVideo = false;
          });
        } else {
          final String imagePath = image.path;
          if (!mounted) return;
          setState(() {
            _importedMediaPath = imagePath;
            _importedMediaBytes = null;
            _importedMediaFileName = null;
            _isPhoto = true;
            _isVideo = false;
          });
        }

        if (mounted) {
          messenger.showSnackBar(
            SnackBar(
              content: LocalizedText('Photo imported successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: LocalizedText('Failed to import photo: ${e.toString()}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _importVideoFromDevice() async {
    // Capture messenger before awaits and outside try/catch scope
    final messenger = ScaffoldMessenger.of(context);
    try {
      final XFile? video = await _imagePicker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(seconds: 15),
      );

      if (video != null) {
        if (kIsWeb) {
          final bytes = await video.readAsBytes();
          if (!mounted) return;
          setState(() {
            _importedMediaBytes = bytes;
            _importedMediaFileName = video.name;
            _importedMediaPath = null;
            _isVideo = true;
            _isPhoto = false;
          });
        } else {
          if (!mounted) return;
          setState(() {
            _importedMediaPath = video.path;
            _importedMediaBytes = null;
            _importedMediaFileName = null;
            _isVideo = true;
            _isPhoto = false;
          });
        }

        if (mounted) {
          messenger.showSnackBar(
            const SnackBar(
              content: LocalizedText('Video imported successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      // Map common errors for clearer feedback
      String errorMessage = 'Failed to create harmony. Please try again.';
      final es = e.toString().toLowerCase();
      if (es.contains('network') || es.contains('connection')) {
        errorMessage = 'Network error. Please check your internet connection.';
      } else if (es.contains('unauthorized') || es.contains('401')) {
        errorMessage = 'Session expired. Please log in again.';
      } else if (es.contains('forbidden') || es.contains('403')) {
        errorMessage = 'Access denied. Please check your permissions.';
      } else if (es.contains('foreign key') ||
          es.contains('relationship') ||
          es.contains('constraint') ||
          es.contains('users!')) {
        errorMessage =
            'Publishing failed due to account or database configuration. Please try again later or contact support.';
      } else if (es.contains('server') || es.contains('500')) {
        errorMessage = 'Server error. Please try again later.';
      }
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: LocalizedText(errorMessage),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: LocalizedText(
          'create_harmony',
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [],
      ),
      body: Column(
        children: [
          // Original post preview (full width)
          Expanded(
            child: Stack(
              children: [
                PostWidget(post: widget.originalPost, isActive: true),
                Positioned(
                  top: 16,
                  left: 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            LocalizedText(
                              'original_post',
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              ' — @${widget.originalPost.username}',
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        if (widget.originalPost.content.isNotEmpty)
                          Text(
                            widget.originalPost.content,
                            style: GoogleFonts.poppins(
                              color: Colors.white70,
                              fontSize: 11,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Caption input (like repost screen)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: TextField(
              controller: _textController,
              style: GoogleFonts.poppins(color: Colors.white, fontSize: 16),
              decoration: InputDecoration(
                hintText: LocalizationService.t('add_caption_harmony_optional'),
                hintStyle: GoogleFonts.poppins(
                  color: Colors.white54,
                  fontSize: 16,
                ),
                filled: true,
                fillColor: Colors.grey[900],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white24),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white24),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.primary),
                ),
                contentPadding: const EdgeInsets.all(14),
              ),
              maxLines: 2,
            ),
          ),

          // Bottom controls
          _buildBottomControls(),
        ],
      ),
    );
  }

  Widget _buildContentMode() {
    // No longer used in repost-style UI
    return const SizedBox.shrink();
  }

  Widget _buildVideoMode() {
    // Removed: camera recording/import UI in repost-style
    return const SizedBox.shrink();
  }

  Widget _buildPhotoMode() {
    // Removed: photo import UI in repost-style
    return const SizedBox.shrink();
  }

  Widget _buildImportedMediaPreview() {
    // Removed: imported media preview in repost-style
    return const SizedBox.shrink();
  }

  Widget _buildTextMode() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white24),
              ),
              child: TextField(
                controller: _textController,
                style: GoogleFonts.poppins(color: Colors.white, fontSize: 16),
                decoration: InputDecoration(
                  hintText: LocalizationService.t('share_harmony_thoughts'),
                  hintStyle: GoogleFonts.poppins(
                    color: Colors.white54,
                    fontSize: 16,
                  ),
                  border: InputBorder.none,
                ),
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomControls() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.black,
        border: Border(top: BorderSide(color: Colors.white24, width: 1)),
      ),
      child: Row(
        children: [
          // Import Video button (to provide right-side media for Harmony)
          Expanded(
            child: TextButton(
              onPressed: _isLoading ? null : _importVideoFromDevice,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: const BorderSide(color: Colors.white24),
                ),
              ),
              child: Text(
                LocalizationService.t('import_video'),
                style: GoogleFonts.poppins(
                  color: Colors.white70,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),

          const SizedBox(width: 16),

          // Cancel button
          Expanded(
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: const BorderSide(color: Colors.white24),
                ),
              ),
              child: Text(
                LocalizationService.t('cancel'),
                style: GoogleFonts.poppins(
                  color: Colors.white70,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),

          const SizedBox(width: 16),

          // Create harmony button
          Expanded(
            flex: 2,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _createHarmony,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : LocalizedText(
                      'create_harmony',
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  void _startRecordingTimer() {
    const interval = Duration(milliseconds: 100);
    int elapsedMs = 0;
    Stream.periodic(interval, (i) => i).listen((tick) async {
      if (!_isRecording) return;
      elapsedMs += 100;
      setState(() {
        _recordingElapsed = Duration(milliseconds: elapsedMs);
      });
      if (elapsedMs >= 12 * 60 * 1000) {
        // Auto-stop at 12 minutes
        try {
          final video = await _cameraController!.stopVideoRecording();
          setState(() {
            _isRecording = false;
            _recordedVideoPath = video.path;
          });
          _recordButtonController.reverse();
        } catch (e) {
          debugPrint(('Error auto-stopping recording: $e').toString());
        }
      }
    });
  }

  String _formatDuration(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final mm = two(d.inMinutes.remainder(60));
    final ss = two(d.inSeconds.remainder(60));
    return '$mm:$ss';
  }

  Future<void> _createHarmony() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      final user = _authService.currentUser;
      if (user == null) throw Exception('User not authenticated');

      final String? caption = _textController.text.trim().isNotEmpty
          ? _textController.text.trim()
          : null;

      final original = widget.originalPost;
      final String type = original.type;

      String? finalMediaUrl;
      String? finalThumbnailUrl = original.thumbnailUrl;

      // Attempt side-by-side combine only for video posts with available user video
      if (type == 'video' && original.mediaUrl != null) {
        try {
          // Download original video bytes
          final resp = await http.get(Uri.parse(original.mediaUrl!));
          if (resp.statusCode >= 200 && resp.statusCode < 300) {
            final leftBytes = Uint8List.fromList(resp.bodyBytes);

            // Prepare right-side user video bytes
            Uint8List? rightBytes;
            if (_importedMediaBytes != null && _isVideo) {
              rightBytes = _importedMediaBytes;
            } else if (!kIsWeb && _recordedVideoPath != null) {
              rightBytes = await File(_recordedVideoPath!).readAsBytes();
            } else if (kIsWeb &&
                _recordedVideoPath != null &&
                _recordedVideoPath!.startsWith('data:video')) {
              try {
                final base64Str = _recordedVideoPath!.split(',').last;
                rightBytes = base64Decode(base64Str);
              } catch (_) {}
            }

            if (rightBytes != null) {
              // Combine using platform-specific implementation
              final combined = await VideoFilterService.combineSideBySide(
                left: leftBytes,
                right: rightBytes,
                scaleHeight: 720,
                mute: false,
              );

              // Upload combined video
              final storage = StorageService();
              final urls = await storage.uploadVideo(
                videoFile: null,
                userId: user.id,
                videoBytes: combined,
                videoFileName:
                    'harmony_${DateTime.now().millisecondsSinceEpoch}.mp4',
              );
              finalMediaUrl = urls['videoUrl'];
              if (urls.containsKey('thumbnailUrl')) {
                finalThumbnailUrl = urls['thumbnailUrl'];
              }
            } else {
              // No user video available; fallback to repost original media
              finalMediaUrl = original.mediaUrl;
            }
          } else {
            // Download failed; fallback to original
            finalMediaUrl = original.mediaUrl;
          }
        } catch (_) {
          // Any processing errors fallback to original
          finalMediaUrl = original.mediaUrl;
        }
      } else {
        // Non-video or missing media: reuse original
        finalMediaUrl = original.mediaUrl;
      }

      await _postsService.createPost(
        type: type,
        caption: caption,
        mediaUrl: finalMediaUrl,
        thumbnailUrl: finalThumbnailUrl,
        parentPostId: original.id,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: LocalizedText('Harmony created!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('Harmony creation error: $e');
      String errorMessage = 'Failed to create harmony. Please try again.';
      final es = e.toString().toLowerCase();
      if (es.contains('network') || es.contains('connection')) {
        errorMessage = 'Network error. Please check your internet connection.';
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: LocalizedText(errorMessage),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}
