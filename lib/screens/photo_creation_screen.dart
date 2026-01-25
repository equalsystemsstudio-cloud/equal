import 'dart:io';
import 'dart:ui' as ui;
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import '../config/supabase_config.dart';
import '../services/posts_service.dart';
import '../services/storage_service.dart';
import '../services/auth_service.dart';
import '../services/preferences_service.dart';
import 'main_screen.dart';
import 'package:photo_manager/photo_manager.dart';
import '../services/photo_permissions_service.dart';
import '../services/localization_service.dart';

class PhotoCreationScreen extends StatefulWidget {
  final Uint8List? preGeneratedImage;
  final String? parentPostId;

  const PhotoCreationScreen({
    super.key,
    this.preGeneratedImage,
    this.parentPostId,
  });

  @override
  State<PhotoCreationScreen> createState() => _PhotoCreationScreenState();
}

class _PhotoCreationScreenState extends State<PhotoCreationScreen>
    with TickerProviderStateMixin {
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isInitialized = false;
  String? _imagePath;
  Uint8List? _imageBytes; // For web compatibility
  String? _imageFileName; // For web compatibility
  bool _isFlashOn = false;
  bool _isFrontCamera = false;
  int _selectedFilter = 0;
  bool _showFilters = false;
  bool _showStickers = false;
  bool _showAdjustments = false;
  late AnimationController _captureController;
  late AnimationController _filterController;
  late Animation<double> _captureAnimation;
  late Animation<double> _filterAnimation;

  // Photo editing properties
  double _brightness = 0.0;
  double _contrast = 1.0;
  double _saturation = 1.0;
  double _warmth = 0.0;
  double _vignette = 0.0;

  final TextEditingController _captionController = TextEditingController();
  final TextEditingController _hashtagController = TextEditingController();

  final List<Map<String, dynamic>> _filters = [
    {'name': 'Original', 'color': Colors.transparent, 'matrix': null},
    {
      'name': 'Vintage',
      'color': Colors.orange.withValues(alpha: 0.3),
      'matrix': [
        0.8,
        0.2,
        0.1,
        0,
        0,
        0.1,
        0.7,
        0.2,
        0,
        0,
        0.1,
        0.1,
        0.6,
        0,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
      ],
    },
    {
      'name': 'Cool',
      'color': Colors.blue.withValues(alpha: 0.2),
      'matrix': [
        0.6,
        0.2,
        0.2,
        0,
        0,
        0.2,
        0.8,
        0.2,
        0,
        0,
        0.4,
        0.2,
        1.0,
        0,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
      ],
    },
    {
      'name': 'Warm',
      'color': Colors.red.withValues(alpha: 0.15),
      'matrix': [
        1.2,
        0.1,
        0.1,
        0,
        0,
        0.1,
        0.9,
        0.1,
        0,
        0,
        0.1,
        0.1,
        0.7,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
      ],
    },
    {
      'name': 'Dramatic',
      'color': Colors.purple.withValues(alpha: 0.3),
      'matrix': [
        1.5,
        0,
        0,
        0,
        -50,
        0,
        1.5,
        0,
        0,
        -50,
        0,
        0,
        1.5,
        0,
        -50,
        0,
        0,
        0,
        1,
        0,
      ],
    },
    {
      'name': 'B&W',
      'color': Colors.grey.withValues(alpha: 0.1),
      'matrix': [
        0.299,
        0.587,
        0.114,
        0,
        0,
        0.299,
        0.587,
        0.114,
        0,
        0,
        0.299,
        0.587,
        0.114,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
      ],
    },
    {
      'name': 'Sunset',
      'color': Colors.deepOrange.withValues(alpha: 0.25),
      'matrix': [
        1.3,
        0.2,
        0,
        0,
        0,
        0.2,
        1.0,
        0.1,
        0,
        0,
        0,
        0.1,
        0.8,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
      ],
    },
    {
      'name': 'Neon',
      'color': Colors.cyan.withValues(alpha: 0.2),
      'matrix': [
        1.0,
        0.3,
        0.8,
        0,
        0,
        0.2,
        1.2,
        0.5,
        0,
        0,
        0.8,
        0.2,
        1.5,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
      ],
    },
  ];

  final List<String> _stickers = [
    '😍',
    '🔥',
    '💯',
    '✨',
    '🌟',
    '💖',
    '🦄',
    '🌈',
    '👑',
    '💎',
    '🎉',
    '🎊',
    '🌸',
    '🌺',
    '🦋',
    '🐝',
    '🍕',
    '🍔',
    '🍟',
    '🍦',
    '🧁',
    '🍭',
    '☕',
    '🥤',
    '🎵',
    '🎶',
    '🎸',
    '🎤',
    '🎧',
    '📱',
    '💻',
    '📷',
  ];

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      _initializeCamera();
    }
    _initializeAnimations();

    // Set pre-generated image if provided
    if (widget.preGeneratedImage != null) {
      debugPrint(
        ('PhotoCreationScreen: Received preGeneratedImage with ${widget.preGeneratedImage!.length} bytes')
            .toString(),
      );
      setState(() {
        _imageBytes = widget.preGeneratedImage;
        _imageFileName = 'ai_generated_image.jpg';
      });
      debugPrint(
        ('PhotoCreationScreen: Set _imageBytes to ${_imageBytes?.length} bytes, _imageFileName to $_imageFileName')
            .toString(),
      );
    }
  }

  void _initializeAnimations() {
    _captureController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _filterController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _captureAnimation = Tween<double>(begin: 1.0, end: 0.8).animate(
      CurvedAnimation(parent: _captureController, curve: Curves.easeInOut),
    );
    _filterAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _filterController, curve: Curves.easeOut),
    );
  }

  Future<void> _initializeCamera() async {
    if (kIsWeb) {
      // Camera not supported on web platform
      return;
    }

    try {
      _cameras = await availableCameras();
      if (_cameras!.isNotEmpty) {
        _cameraController = CameraController(
          _cameras![_isFrontCamera ? 1 : 0],
          ResolutionPreset.medium,
          enableAudio: false,
        );
        await _cameraController!.initialize();
        try {
          final minZoom = await _cameraController!.getMinZoomLevel();
          // setZoomLevel not available in rtmp_broadcaster on web; skip applying.
        } catch (_) {}
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      debugPrint(('Error initializing camera: $e').toString());
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _captionController.dispose();
    _hashtagController.dispose();
    _captureController.dispose();
    _filterController.dispose();
    super.dispose();
  }

  Future<void> _toggleCamera() async {
    if (_cameras != null && _cameras!.length > 1) {
      setState(() {
        _isFrontCamera = !_isFrontCamera;
        _isInitialized = false;
      });
      await _cameraController?.dispose();
      await _initializeCamera();
    }
  }

  Future<void> _toggleFlash() async {
    if (_cameraController != null) {
      setState(() {
        _isFlashOn = !_isFlashOn;
      });
      await _cameraController!.setFlashMode(
        _isFlashOn ? FlashMode.torch : FlashMode.off,
      );
    }
  }

  Future<void> _capturePhoto() async {
    if (kIsWeb) {
      // Show localized message that camera is not available on web
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: LocalizedText('camera_functionality_not_supported_on_web'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    // Use the native camera app via ImagePicker to ensure perfect device ratio
    try {
      _captureController.forward().then((_) {
        _captureController.reverse();
      });

      final ImagePicker picker = ImagePicker();
      final XFile? imageFile = await picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: _isFrontCamera
            ? CameraDevice.front
            : CameraDevice.rear,
      );
      if (imageFile != null) {
        setState(() {
          _imagePath = imageFile.path;
        });
      }
    } catch (e) {
      debugPrint(('Error capturing photo: $e').toString());
    }
  }

  void _showCaptionDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            margin: const EdgeInsets.all(20),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.grey[900],
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LocalizedText(
                  'share_your_photo',
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _captionController,
                  style: GoogleFonts.poppins(color: Colors.white),
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: LocalizationService.t('add_caption'),
                    hintStyle: GoogleFonts.poppins(color: Colors.grey),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey[600]!),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey[600]!),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.blue),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _hashtagController,
                  style: GoogleFonts.poppins(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: LocalizationService.t('hashtags_hint'),
                    hintStyle: GoogleFonts.poppins(color: Colors.grey),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey[600]!),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey[600]!),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.blue),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const MainScreen(),
                        ),
                        (route) => false,
                      ),
                      child: Text(
                        LocalizationService.t('cancel'),
                        style: GoogleFonts.poppins(
                          color: Colors.grey,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: () {
                        _publishPost();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        LocalizationService.t('share'),
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _publishPost() async {
    debugPrint(
      ('PhotoCreationScreen: _publishPost called with _imagePath=$_imagePath, _imageBytes length=${_imageBytes?.length}')
          .toString(),
    );
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    if (_imagePath == null && _imageBytes == null) {
      messenger.showSnackBar(
        SnackBar(content: LocalizedText('no_photo_to_publish')),
      );
      return;
    }

    try {
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      // Render edits into the image so effects stick
      Uint8List? sourceBytes = _imageBytes;
      String effectiveFileName = _imageFileName ?? 'photo_edited.png';
      if (sourceBytes == null && _imagePath != null) {
        final file = File(_imagePath!);
        sourceBytes = await file.readAsBytes();
        effectiveFileName = path.setExtension(
          path.basename(_imagePath!),
          '.png',
        );
      }
      if (sourceBytes == null) {
        throw Exception('No image data available for upload');
      }

      final Uint8List processedBytes = await _renderEditedImageBytes(
        sourceBytes,
      );

      // Upload processed image bytes
      final String mediaUrl = await StorageService().uploadImage(
        imageFile: null,
        userId: AuthService().currentUser!.id,
        imageBytes: processedBytes,
        fileName: effectiveFileName,
      );

      // Create post with image upload
      await PostsService().createPost(
        type: 'image',
        caption: _captionController.text.trim().isEmpty
            ? null
            : _captionController.text.trim(),
        mediaUrl: mediaUrl,
        hashtags: _hashtagController.text.trim().isEmpty
            ? null
            : _hashtagController.text.trim().split(' '),
        parentPostId: widget.parentPostId,
        // Persist compact effects metadata for forward-compatibility
        effects: {
          'photo': {
            'filter': _selectedFilter > 0
                ? _filterKeyForName(
                    (_filters[_selectedFilter]['name'] as String),
                  )
                : 'original',
            'adjustments': {
              'brightness': _brightness,
              'contrast': _contrast,
              'saturation': _saturation,
              'warmth': _warmth,
              'vignette': _vignette,
            },
          },
        },
        filterId: _selectedFilter > 0
            ? _filterKeyForName((_filters[_selectedFilter]['name'] as String))
            : null,
      );

      // Save to Gallery if preference enabled (mobile only)
      try {
        if (!kIsWeb) {
          bool savePref = false;
          try {
            savePref = await PreferencesService().getSaveToGallery();
          } catch (prefsError) {
            debugPrint(('getSaveToGallery failed: $prefsError').toString());
            savePref = false;
          }
          if (savePref) {
            String? pathToSave;
            if (_imagePath != null) {
              pathToSave = _imagePath!;
            }
            if (pathToSave != null && File(pathToSave).existsSync()) {
              if (!mounted) return;
              final bool granted =
                  await PhotoPermissionsService.ensurePhotoAccess(context);
              if (granted) {
                await PhotoManager.editor.saveImageWithPath(pathToSave);
                if (mounted) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: LocalizedText('Saved photo to gallery'),
                      backgroundColor: Colors.black87,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              } else {
                if (mounted) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: LocalizedText(
                        'Allow photo library access to save to gallery',
                      ),
                      backgroundColor: Colors.orange,
                      duration: const Duration(seconds: 3),
                    ),
                  );
                }
              }
            }
          }
        }
      } catch (e) {
        if (mounted) {
          messenger.showSnackBar(
            SnackBar(
              content: Text('Could not save to gallery: $e'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }

      // Close loading dialog
      if (mounted) nav.pop();

      // Show success message
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: LocalizedText('Photo posted successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        nav.pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const MainScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      // Close loading dialog
      if (mounted) nav.pop();

      // Get specific error message
      String errorMessage = 'Failed to publish photo. Please try again.';
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
        errorMessage = 'Photo file is too large. Please choose a smaller file.';
      } else if (errorString.contains('format') ||
          errorString.contains('mime')) {
        errorMessage =
            'Unsupported photo format. Please use JPEG, PNG, or WebP.';
      } else if (errorString.contains('storage') ||
          errorString.contains('bucket')) {
        errorMessage = 'Storage error. Please try again in a few moments.';
      } else if (errorString.contains('row-level security') ||
          errorString.contains('policy') ||
          errorString.contains('violates')) {
        errorMessage =
            'Storage configuration issue. Please contact support or try again later.';
      } else if (errorString.contains('server') ||
          errorString.contains('500')) {
        errorMessage = 'Server error. Please try again later.';
      }

      // Debug logging
      debugPrint(('Photo upload error: $e').toString());

      // Show error message
      if (mounted) {
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

  // --- Image rendering helpers to bake adjustments into pixels ---

  // Identity 4x5 color matrix
  List<double> _identityMatrix() => const [
    1,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ];

  // Multiply two 4x5 color matrices (m2 after m1)
  List<double> _mulColorMatrix(List<double> m2, List<double> m1) {
    // Convert to 4x5 rows for easier math
    List<List<double>> a = [
      m2.sublist(0, 5),
      m2.sublist(5, 10),
      m2.sublist(10, 15),
      m2.sublist(15, 20),
    ];
    List<List<double>> b = [
      m1.sublist(0, 5),
      m1.sublist(5, 10),
      m1.sublist(10, 15),
      m1.sublist(15, 20),
    ];
    final r = List<List<double>>.generate(4, (_) => List<double>.filled(5, 0));
    for (int i = 0; i < 4; i++) {
      for (int j = 0; j < 4; j++) {
        double sum = 0;
        for (int k = 0; k < 4; k++) {
          sum += a[i][k] * b[k][j];
        }
        r[i][j] = sum;
      }
      // bias column
      double bias = a[i][4];
      for (int k = 0; k < 4; k++) {
        bias += a[i][k] * b[k][4];
      }
      r[i][4] = bias;
    }
    return [...r[0], ...r[1], ...r[2], ...r[3]];
  }

  List<double> _composeColorMatrix() {
    // Start with identity and apply: filter -> warmth -> saturation -> contrast
    List<double> m = _identityMatrix();
    // Selected filter matrix
    final dynamic fm = _filters[_selectedFilter]['matrix'];
    if (_selectedFilter > 0 && fm is List) {
      final List<double> fmd = fm.cast<double>();
      m = _mulColorMatrix(fmd, m);
    }
    // Warmth
    if (_warmth != 0.0) {
      m = _mulColorMatrix(_warmthMatrix(_warmth.clamp(-1.0, 1.0)), m);
    }
    // Saturation
    if (_saturation != 1.0) {
      m = _mulColorMatrix(_saturationMatrix(_saturation.clamp(0.0, 2.0)), m);
    }
    // Contrast (includes bias)
    if (_contrast != 1.0) {
      m = _mulColorMatrix(_contrastMatrix(_contrast.clamp(0.0, 2.0)), m);
    }
    return m;
  }

  Future<Uint8List> _renderEditedImageBytes(Uint8List input) async {
    // Decode original input
    final codec = await ui.instantiateImageCodec(input);
    final frame = await codec.getNextFrame();
    final img = frame.image;

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final Size size = Size(img.width.toDouble(), img.height.toDouble());

    // Draw source image with composite color matrix
    final List<double> matrix = _composeColorMatrix();
    final Paint imagePaint = Paint()
      ..filterQuality = FilterQuality.high
      ..colorFilter = ColorFilter.matrix(matrix);
    final Rect src = Rect.fromLTWH(
      0,
      0,
      img.width.toDouble(),
      img.height.toDouble(),
    );
    final Rect dst = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawImageRect(img, src, dst, imagePaint);

    // Brightness overlay
    if (_brightness != 0.0) {
      final double a = (_brightness > 0)
          ? (_brightness.clamp(0.0, 1.0) * 0.3)
          : ((-_brightness).clamp(0.0, 1.0) * 0.3);
      final Color overlay = _brightness > 0
          ? Colors.white.withOpacity(a)
          : Colors.black.withOpacity(a);
      final Paint p = Paint()..color = overlay;
      canvas.drawRect(dst, p);
    }

    // Vignette overlay
    if (_vignette > 0.0) {
      final double radius = math.max(size.width, size.height) / 2.0;
      final shader = ui.Gradient.radial(
        Offset(size.width / 2, size.height / 2),
        radius,
        [
          Colors.transparent,
          Colors.black.withOpacity(0.6 * _vignette.clamp(0.0, 1.0)),
        ],
        const [0.6, 1.0],
      );
      final Paint p = Paint()..shader = shader;
      canvas.drawRect(dst, p);
    }

    // Finalize drawing and encode with size-aware downscaling to stay under upload limits
    final picture = recorder.endRecording();

    // Start with original dimensions
    int outW = img.width;
    int outH = img.height;

    // Heuristic: cap longest side to 1920 for efficiency, then iteratively shrink if needed
    const int maxInitialSide = 1920;
    final int maxSide = math.max(outW, outH);
    if (maxSide > maxInitialSide) {
      final double scale = maxInitialSide / maxSide;
      outW = (outW * scale).round().clamp(1, outW);
      outH = (outH * scale).round().clamp(1, outH);
    }

    // Helper to encode PNG at given dimensions
    Future<Uint8List> encodeAt(int w, int h) async {
      final ui.Image uiImage = await picture.toImage(w, h);
      final ByteData? bd = await uiImage.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (bd == null) {
        throw Exception('Failed to encode edited image');
      }
      return bd.buffer.asUint8List();
    }

    // Encode and iteratively downscale if above SupabaseConfig.maxImageSize
    Uint8List bytes = await encodeAt(outW, outH);
    const double shrinkFactor = 0.8; // 20% shrink per attempt
    int attempts = 0;
    while (bytes.length > SupabaseConfig.maxImageSize && attempts < 4) {
      attempts += 1;
      final double f = math.pow(shrinkFactor, attempts).toDouble();
      final int newW = math.max(1, (outW * f).round());
      final int newH = math.max(1, (outH * f).round());
      bytes = await encodeAt(newW, newH);
    }

    return bytes;
  }

  Future<void> _importPhotoFromDevice() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (!kIsWeb) {
        final bool hasAccess = await PhotoPermissionsService.ensurePhotoAccess(
          context,
        );
        if (!hasAccess) {
          return;
        }
      }
      final ImagePicker picker = ImagePicker();
      XFile? image;
      try {
        image = await picker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 1920,
          maxHeight: 1920,
          imageQuality: 85,
        );
      } catch (pickerError) {
        debugPrint(('ImagePicker pickImage failed: $pickerError').toString());
        image = null;
      }

      if (image != null) {
        if (kIsWeb) {
          // For web, store bytes and filename
          final bytes = await image.readAsBytes();
          final String fileName = image.name;
          setState(() {
            _imageBytes = bytes;
            _imageFileName = fileName;
            _imagePath = null; // Clear path for web
          });
        } else {
          // For mobile, store path
          final String imagePath = image.path;
          setState(() {
            _imagePath = imagePath;
            _imageBytes = null; // Clear bytes for mobile
            _imageFileName = null;
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
      // Try fallback using FilePicker
      try {
        final FilePickerResult? result = await FilePicker.platform.pickFiles(
          type: FileType.image,
          withData: kIsWeb,
        );
        if (result != null && result.files.isNotEmpty) {
          final PlatformFile file = result.files.first;
          if (kIsWeb || file.bytes != null) {
            setState(() {
              _imageBytes = file.bytes!;
              _imageFileName = file.name;
              _imagePath = null;
            });
          } else if (file.path != null) {
            setState(() {
              _imagePath = file.path!;
              _imageBytes = null;
              _imageFileName = null;
            });
          } else {
            throw Exception('No file path or bytes returned');
          }

          if (mounted) {
            messenger.showSnackBar(
              SnackBar(
                content: LocalizedText('Photo imported successfully!'),
                backgroundColor: Colors.green,
              ),
            );
          }
          return; // Fallback succeeded
        }
      } catch (fallbackError) {
        debugPrint(('FilePicker fallback failed: $fallbackError').toString());
        // Continue to error handling below
      }

      // Get specific error message
      String errorMessage = 'Failed to import photo. Please try again.';
      final errorString = e.toString().toLowerCase();

      if (errorString.contains('permission')) {
        errorMessage =
            'Permission denied. Please allow access to your gallery.';
      } else if (errorString.contains('format') ||
          errorString.contains('unsupported')) {
        errorMessage =
            'Unsupported photo format. Please choose JPEG, PNG, or WebP.';
      } else if (errorString.contains('size') ||
          errorString.contains('large')) {
        errorMessage = 'Photo file is too large. Please choose a smaller file.';
      } else if (errorString.contains('corrupt')) {
        errorMessage =
            'Photo file appears to be corrupted. Please choose another file.';
      }

      debugPrint(('Photo import error: $e').toString());

      if (mounted) {
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

  void _retakePhoto() {
    setState(() {
      _imagePath = null;
      _imageBytes = null;
      _imageFileName = null;
      _selectedFilter = 0;
      _brightness = 0.0;
      _contrast = 1.0;
      _saturation = 1.0;
      _warmth = 0.0;
      _vignette = 0.0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: Navigator.canPop(context),
      onPopInvokedWithResult: (didPop, result) {
        debugPrint('PhotoCreationScreen: PopScope didPop=$didPop');
        if (didPop) return;
        // If can't pop, navigate to main screen instead
        Navigator.pushReplacementNamed(context, '/main');
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // Camera/Photo Preview with Filter Overlay
            Positioned.fill(
              child: Stack(
                children: [
                  // Base camera/photo preview
                  _buildPreviewWithAdjustments(),
                  // Filter Overlay
                  if (_selectedFilter > 0)
                    Positioned.fill(
                      child: Container(
                        color: _filters[_selectedFilter]['color'],
                        child: BackdropFilter(
                          filter: ui.ImageFilter.blur(sigmaX: 0, sigmaY: 0),
                          child: Container(color: Colors.transparent),
                        ),
                      ),
                    ),
                  // Adjustment Overlays (brightness as simple overlay to avoid double bias)
                  if (_brightness != 0.0)
                    Positioned.fill(
                      child: Container(
                        color: _brightness > 0
                            ? Colors.white.withValues(alpha: _brightness * 0.3)
                            : Colors.black.withValues(
                                alpha: -_brightness * 0.3,
                              ),
                      ),
                    ),
                  // Vignette overlay
                  if (_vignette > 0.0)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: RadialGradient(
                              center: Alignment.center,
                              radius: 1.0,
                              colors: [
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.6 * _vignette),
                              ],
                              stops: const [0.6, 1.0],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
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
                    onTap: () => Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const MainScreen(),
                      ),
                      (route) => false,
                    ),
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
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: LocalizedText(
                      'photo',
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),

                  // Top Right Controls
                  Row(
                    children: [
                      // Flash Toggle
                      if (_imagePath == null)
                        GestureDetector(
                          onTap: _toggleFlash,
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.6),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _isFlashOn ? Icons.flash_on : Icons.flash_off,
                              color: _isFlashOn ? Colors.yellow : Colors.white,
                              size: 24,
                            ),
                          ),
                        ),
                      if (_imagePath == null) const SizedBox(width: 12),
                      // Camera Flip or Retake
                      GestureDetector(
                        onTap: _imagePath == null
                            ? _toggleCamera
                            : _retakePhoto,
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _imagePath == null
                                ? Icons.flip_camera_ios
                                : Icons.refresh,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Side Controls (only when photo is captured)
            if (_imagePath != null || _imageBytes != null)
              Positioned(
                right: 20,
                top: MediaQuery.of(context).size.height * 0.3,
                child: Column(
                  children: [
                    // Filters
                    _buildSideButton(
                      icon: Icons.photo_filter,
                      label: 'filters',
                      isActive: _showFilters,
                      onTap: _showFilterPanel,
                    ),
                    const SizedBox(height: 20),
                    // Adjustments
                    _buildSideButton(
                      icon: Icons.tune,
                      label: 'adjust',
                      isActive: _showAdjustments,
                      onTap: _showAdjustmentPanel,
                    ),
                    const SizedBox(height: 20),
                    // Stickers
                    _buildSideButton(
                      icon: Icons.emoji_emotions,
                      label: 'stickers',
                      isActive: _showStickers,
                      onTap: _showStickerPanel,
                    ),
                    const SizedBox(height: 20),
                    // Import from Device
                    _buildSideButton(
                      icon: Icons.photo_library,
                      label: 'import',
                      isActive: false,
                      onTap: _importPhotoFromDevice,
                    ),
                  ],
                ),
              ),

            // Bottom Controls
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 30,
              left: 0,
              right: 0,
              child: Column(
                children: [
                  // Capture and Import Buttons
                  if (_imagePath == null)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Import Button
                        GestureDetector(
                          onTap: _importPhotoFromDevice,
                          child: Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.black.withValues(alpha: 0.6),
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: const Icon(
                              Icons.photo_library,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                        ),
                        const SizedBox(width: 40),
                        // Capture Button
                        AnimatedBuilder(
                          animation: _captureAnimation,
                          builder: (context, child) {
                            return Transform.scale(
                              scale: _captureAnimation.value,
                              child: GestureDetector(
                                onTap: _capturePhoto,
                                child: Container(
                                  width: 80,
                                  height: 80,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 4,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.blue.withValues(
                                          alpha: 0.3,
                                        ),
                                        blurRadius: 15,
                                        spreadRadius: 5,
                                      ),
                                    ],
                                  ),
                                  child: Container(
                                    margin: const EdgeInsets.all(8),
                                    decoration: const BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(width: 100), // Spacer for balance
                      ],
                    ),

                  // Post Button (after capturing)
                  if (_imagePath != null || _imageBytes != null)
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 40),
                      child: ElevatedButton(
                        onPressed: _showCaptionDialog,
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
                            LocalizedText(
                              'share_photo',
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
            ),

            // Filter Panel
            if (_showFilters)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: AnimatedBuilder(
                  animation: _filterAnimation,
                  builder: (context, child) {
                    return Transform.translate(
                      offset: Offset(0, 200 * (1 - _filterAnimation.value)),
                      child: Container(
                        height: 200,
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
                              'choose_filter',
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 20),
                            Expanded(
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                ),
                                itemCount: _filters.length,
                                itemBuilder: (context, index) {
                                  return GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _selectedFilter = index;
                                      });
                                    },
                                    child: Container(
                                      margin: const EdgeInsets.only(right: 15),
                                      child: Column(
                                        children: [
                                          Container(
                                            width: 60,
                                            height: 80,
                                            decoration: BoxDecoration(
                                              color: _filters[index]['color'],
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              border: Border.all(
                                                color: _selectedFilter == index
                                                    ? Colors.blue
                                                    : Colors.grey.withValues(
                                                        alpha: 0.5,
                                                      ),
                                                width: 2,
                                              ),
                                            ),
                                            child: const Icon(
                                              Icons.photo_filter,
                                              color: Colors.white,
                                              size: 24,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          LocalizedText(
                                            _filterKeyForName(
                                              (_filters[index]['name']
                                                  as String),
                                            ),
                                            style: GoogleFonts.poppins(
                                              color: Colors.white,
                                              fontSize: 12,
                                            ),
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
                    );
                  },
                ),
              ),

            // Adjustment Panel
            if (_showAdjustments)
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
                        'adjust_photo',
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
                              _buildAdjustmentSlider(
                                'brightness',
                                Icons.brightness_6,
                                _brightness,
                                -1.0,
                                1.0,
                                (value) => setState(() => _brightness = value),
                              ),
                              _buildAdjustmentSlider(
                                'contrast',
                                Icons.contrast,
                                _contrast,
                                0.0,
                                2.0,
                                (value) => setState(() => _contrast = value),
                              ),
                              _buildAdjustmentSlider(
                                'saturation',
                                Icons.palette,
                                _saturation,
                                0.0,
                                2.0,
                                (value) => setState(() => _saturation = value),
                              ),
                              _buildAdjustmentSlider(
                                'warmth',
                                Icons.wb_sunny,
                                _warmth,
                                -1.0,
                                1.0,
                                (value) => setState(() => _warmth = value),
                              ),
                              _buildAdjustmentSlider(
                                'vignette',
                                Icons.circle,
                                _vignette,
                                0.0,
                                1.0,
                                (value) => setState(() => _vignette = value),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Sticker Panel
            if (_showStickers)
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
                        'add_stickers',
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
                                crossAxisCount: 8,
                                crossAxisSpacing: 10,
                                mainAxisSpacing: 10,
                              ),
                          itemCount: _stickers.length,
                          itemBuilder: (context, index) {
                            return GestureDetector(
                              onTap: () {
                                // TODO: Add sticker to photo
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.grey.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Center(
                                  child: Text(
                                    _stickers[index],
                                    style: const TextStyle(fontSize: 24),
                                  ),
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

            // Caption Input (after capturing)
            if (_imagePath != null)
              Positioned(
                bottom: 100,
                left: 20,
                right: 20,
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.grey.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    children: [
                      TextField(
                        controller: _captionController,
                        style: GoogleFonts.poppins(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: LocalizationService.t('add_caption'),
                          hintStyle: GoogleFonts.poppins(
                            color: Colors.grey,
                            fontSize: 14,
                          ),
                          border: InputBorder.none,
                          prefixIcon: const Icon(
                            Icons.edit,
                            color: Colors.blue,
                            size: 20,
                          ),
                        ),
                        maxLines: 2,
                      ),
                      const Divider(color: Colors.grey),
                      TextField(
                        controller: _hashtagController,
                        style: GoogleFonts.poppins(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: LocalizationService.t('hashtags_hint'),
                          hintStyle: GoogleFonts.poppins(
                            color: Colors.grey,
                            fontSize: 14,
                          ),
                          border: InputBorder.none,
                          prefixIcon: const Icon(
                            Icons.tag,
                            color: Colors.blue,
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ), // Close Stack
      ), // Close Scaffold body
    ); // Close WillPopScope
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
            Icon(icon, color: Colors.white, size: 24),
            const SizedBox(height: 4),
            LocalizedText(
              label,
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdjustmentSlider(
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
              LocalizedText(
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

  Widget _buildCameraPreview() {
    // Display selected image (web or mobile)
    if (_imageBytes != null) {
      // Web: use Image.memory for bytes, constrained to 4:3
      return Center(
        child: AspectRatio(
          aspectRatio: 4 / 3,
          child: FittedBox(
            fit: BoxFit.cover,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(0),
              child: Image.memory(_imageBytes!, fit: BoxFit.cover),
            ),
          ),
        ),
      );
    } else if (_imagePath != null) {
      // Mobile: use Image.file for path, constrained to 4:3
      return Center(
        child: AspectRatio(
          aspectRatio: 4 / 3,
          child: FittedBox(
            fit: BoxFit.cover,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(0),
              child: Image.file(File(_imagePath!), fit: BoxFit.cover),
            ),
          ),
        ),
      );
    }

    // Show platform-specific message for web
    if (kIsWeb) {
      return Container(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.camera_alt_outlined,
                color: Colors.white.withValues(alpha: 0.7),
                size: 80,
              ),
              const SizedBox(height: 20),
              LocalizedText(
                'camera_not_available',
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              LocalizedText(
                'camera_functionality_not_supported_on_web',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (!_isInitialized || _cameraController == null) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.blue, strokeWidth: 3),
              SizedBox(height: 20),
              LocalizedText(
                'initializing_camera',
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    // Constrain to 4:3 and center-crop to preserve framing
    return Center(
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final double w = constraints.maxWidth;
            final double h = constraints.maxHeight;
            return SizedBox(
              width: w,
              height: h,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(0),
                child: CameraPreview(_cameraController!),
              ),
            );
          },
        ),
      ),
    );
  }

  String _filterKeyForName(String name) {
    switch (name.toLowerCase()) {
      case 'original':
        return 'original';
      case 'vintage':
        return 'vintage';
      case 'cool':
        return 'cool';
      case 'warm':
        return 'warm';
      case 'dramatic':
        return 'dramatic';
      case 'b&w':
        return 'black_and_white';
      case 'sunset':
        return 'sunset';
      case 'neon':
        return 'neon';
      default:
        // Fallback: use the original string as a key, which will show raw if missing
        return name;
    }
  }

  // Helpers for color adjustments
  List<double> _saturationMatrix(double s) {
    // s = 1.0 means no change; s > 1 increases saturation; s < 1 decreases
    const double lr = 0.2126, lg = 0.7152, lb = 0.0722;
    final double ir = lr * (1 - s);
    final double ig = lg * (1 - s);
    final double ib = lb * (1 - s);
    return [
      ir + s,
      ig,
      ib,
      0,
      0,
      ir,
      ig + s,
      ib,
      0,
      0,
      ir,
      ig,
      ib + s,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
    ];
  }

  List<double> _contrastMatrix(double c) {
    // c = 1.0 no change; bias keeps midpoint stable
    final double bias = 128.0 * (1 - c);
    return [
      c,
      0,
      0,
      0,
      bias,
      0,
      c,
      0,
      0,
      bias,
      0,
      0,
      c,
      0,
      bias,
      0,
      0,
      0,
      1,
      0,
    ];
  }

  List<double> _warmthMatrix(double warm) {
    // warm in [-1,1]: increase reds, slightly decrease blues
    final double r = 1 + 0.08 * warm;
    final double g = 1 + 0.02 * warm;
    final double b = 1 - 0.06 * warm;
    return [r, 0, 0, 0, 0, 0, g, 0, 0, 0, 0, 0, b, 0, 0, 0, 0, 0, 1, 0];
  }

  Widget _buildPreviewWithAdjustments() {
    Widget child = _buildCameraPreview();

    // Apply warmth, saturation, and contrast via nested ColorFiltered wrappers
    final double w = _warmth.clamp(-1.0, 1.0);
    final double s = _saturation.clamp(0.0, 2.0);
    final double c = _contrast.clamp(0.0, 2.0);

    if (w != 0.0) {
      child = ColorFiltered(
        colorFilter: ColorFilter.matrix(_warmthMatrix(w)),
        child: child,
      );
    }
    if (s != 1.0) {
      child = ColorFiltered(
        colorFilter: ColorFilter.matrix(_saturationMatrix(s)),
        child: child,
      );
    }
    if (c != 1.0) {
      child = ColorFiltered(
        colorFilter: ColorFilter.matrix(_contrastMatrix(c)),
        child: child,
      );
    }

    return child;
  }

  void _showFilterPanel() {
    setState(() {
      _showFilters = !_showFilters;
      _showStickers = false;
      _showAdjustments = false;
    });
    if (_showFilters) {
      _filterController.forward();
    } else {
      _filterController.reverse();
    }
  }

  void _showStickerPanel() {
    setState(() {
      _showStickers = !_showStickers;
      _showFilters = false;
      _showAdjustments = false;
    });
  }

  void _showAdjustmentPanel() {
    setState(() {
      _showAdjustments = !_showAdjustments;
      _showFilters = false;
      _showStickers = false;
    });
  }
}
