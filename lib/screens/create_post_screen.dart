import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'dart:math' as math;
import 'package:google_fonts/google_fonts.dart';
import 'package:camera/camera.dart';
import 'package:video_player/video_player.dart';
import 'package:image_picker/image_picker.dart';
import 'package:universal_io/io.dart';
import 'dart:ui' as ui;
import '../services/auth_service.dart';
import '../services/app_service.dart';
import '../services/video_filter_service.dart';
import 'main_screen.dart';
import 'dart:async';
import 'package:file_picker/file_picker.dart';
import '../services/preferences_service.dart';
import 'package:photo_manager/photo_manager.dart';
import '../services/photo_permissions_service.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart'
    show RTCVideoRenderer, RTCVideoView, MediaStream, navigator;
import '../utils/media_recorder_web.dart'
    if (dart.library.io) '../utils/media_recorder_stub.dart';
import '../services/analytics_service.dart';
import '../services/upload_service.dart';
import '../services/localization_service.dart';
import 'package:path/path.dart' as path;
// Conditionally import download helpers: web uses dart:html, non-web stub
import '../utils/download_helper_stub.dart'
    if (dart.library.html) '../utils/download_helper_web.dart';

class CreatePostScreen extends StatefulWidget {
  final String? parentPostId;
  const CreatePostScreen({super.key, this.parentPostId});

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen>
    with TickerProviderStateMixin {
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isRecording = false;
  bool _isInitialized = false; // ignore: unused_field
  String? _videoPath;
  Uint8List? _videoBytes; // For web uploads
  String? _videoFileName; // For web uploads
  VideoPlayerController? _videoPlayerController;
  final TextEditingController _captionController = TextEditingController();
  final TextEditingController _hashtagController = TextEditingController();
  // Web-only: RTC renderer and media stream
  final RTCVideoRenderer _rtcRenderer = RTCVideoRenderer();
  MediaStream? _webStream;
  WebRecorderSession? _webRecorderSession;
  final AnalyticsService _analytics = AnalyticsService();

  // Premium features
  bool _isFlashOn = false;
  bool _isFrontCamera = false;
  int _selectedFilter = 0;
  double _filterIntensity = 0.5;
  // UI: hide the horizontal filter chips row without deleting it
  final bool _showFilterChips = false;
  double _recordingProgress = 0.0; // ignore: unused_field
  double _processingProgress = 0.0;
  // Label for processing overlay to distinguish compression vs effects
  String _processingLabel = 'processing_video';
  // Compression size diagnostics
  int? _sourceSizeBytes;
  int? _compressedSizeBytes;
  // Upload progress state
  bool _isUploading = false;
  double _uploadProgress = 0.0;
  String? _uploadEtaText;
  // Upload cancel & guidance
  bool _cancelUpload = false;
  Completer<Map<String, String>>? _uploadCancelCompleter;
  String? _uploadGuidanceText;
  // Importing state (file pick / preview init)
  bool _isImporting = false;
  double _importProgress = 0.0; // reserved for future granular import
  DateTime? _uploadStartTime; // ensure visible time for upload indicator
  Timer? _uploadProgressTimer; // synthetic upload progress timer
  bool _cancelProcessing = false;
  DateTime? _processingStartTime;
  String? _etaText;
  StreamSubscription<UploadStatus>? _uploadStatusSub;
  final bool _showFilters = false; // ignore: unused_field
  final bool _showEffects = false; // ignore: unused_field
  final bool _showMusic = false; // ignore: unused_field
  final bool _showDurationOptions = false; // ignore: unused_field
  int _selectedDuration = 0; // 0: 15s, 1: 30s, 2: 1min, 3: 5min, 4: longer
  double _speed = 1.0; // playback/processing speed multiplier
  late AnimationController _pulseController;
  late AnimationController _filterController;
  late Animation<double> _pulseAnimation; // ignore: unused_field
  late Animation<double> _filterAnimation; // ignore: unused_field
  Timer? _countdownTimer;
  int? _countdown;
  bool _useCountdown = false;
  bool _autoStop = true;
  // Recording progress timer subscription and stopping guard
  StreamSubscription<int>? _recordingTimerSub;
  bool _isStopping = false;
  final List<Map<String, dynamic>> _filters = [
    {'id': 'original', 'name': 'Original', 'color': Colors.transparent},
    {
      'id': 'teal_orange',
      'name': 'Teal & Orange',
      'color': const Color(0xFFFF7E43).withValues(alpha: 0.25),
    },
    {
      'id': 'cinematic_blue',
      'name': 'Cinematic Blue',
      'color': const Color(0xFF3AA0FF).withValues(alpha: 0.25),
    },
    {
      'id': 'warm_skin_glow',
      'name': 'Warm Skin',
      'color': const Color(0xFFF5B288).withValues(alpha: 0.25),
    },
    {
      'id': 'beauty_soft',
      'name': 'Beauty Soft',
      'color': const Color(0xFFFFA8A8).withValues(alpha: 0.22),
    },
    {
      'id': 'glam_makeup',
      'name': 'Glam Makeup',
      'color': const Color(0xFFFF6F91).withValues(alpha: 0.18),
    },
    {
      'id': 'hdr_pop_plus',
      'name': 'HDR Pop+',
      'color': const Color(0xFF5EE7DF).withValues(alpha: 0.20),
    },
    {
      'id': 'cinema_s35',
      'name': 'Cinema S35',
      'color': const Color(0xFF2C2C54).withValues(alpha: 0.20),
    },
    {
      'id': 'vignette_glow',
      'name': 'Vignette Glow',
      'color': const Color(0xFFA29BFE).withValues(alpha: 0.18),
    },
    {
      'id': 'ink_sketch',
      'name': 'Ink Sketch',
      'color': const Color(0xFF7D6BF2).withValues(alpha: 0.22),
    },
    {
      'id': 'vintage_fade',
      'name': 'Vintage Fade',
      'color': const Color(0xFFC6A674).withValues(alpha: 0.25),
    },
    {
      'id': 'pastel_matte',
      'name': 'Pastel Matte',
      'color': const Color(0xFFB8D8D8).withValues(alpha: 0.25),
    },
    {
      'id': 'cyberpunk_neon',
      'name': 'Cyberpunk',
      'color': const Color(0xFFD04AFF).withValues(alpha: 0.25),
    },
    {
      'id': 'night_boost',
      'name': 'Night Boost',
      'color': const Color(0xFF6A7B8C).withValues(alpha: 0.25),
    },
    {
      'id': 'mono_film',
      'name': 'Mono Film',
      'color': const Color(0xFF888888).withValues(alpha: 0.25),
    },
    {
      'id': 'clarity_pop',
      'name': 'Clarity Pop',
      'color': const Color(0xFF4EC1A7).withValues(alpha: 0.25),
    },
    {
      'id': 'vhs_retro',
      'name': 'VHS Retro',
      'color': const Color(0xFFA0A07A).withValues(alpha: 0.25),
    },
    {
      'id': 'anime_ink',
      'name': 'Anime Ink',
      'color': const Color(0xFF7D6BF2).withValues(alpha: 0.25),
    },
    {
      'id': 'slow_shutter',
      'name': 'Slow Shutter',
      'color': const Color(0xFFFF5E8A).withValues(alpha: 0.25),
    },
  ];

  // Compute a dynamic timeout based on original size, duration, and expected transcode
  Duration _computeDynamicUploadTimeout({
    int? sourceBytes,
    bool expectTranscode = false,
  }) {
    final int mb = ((sourceBytes ?? 0) / (1024 * 1024)).ceil();
    int minutes;
    if (mb <= 25) {
      minutes = 6;
    } else if (mb <= 50) {
      minutes = 8;
    } else if (mb <= 100) {
      minutes = 12;
    } else {
      minutes = 15;
    }
    if (expectTranscode) minutes += 3; // non-MP4 -> MP4
    final int selectedSeconds =
        _videoDurations[_selectedDuration]['seconds'] as int;
    if (selectedSeconds >= 300) minutes += 2; // > 5 min
    if (selectedSeconds >= 600) minutes += 2; // >= 10 min
    // Clamp to sensible range
    minutes = minutes.clamp(5, 20);
    return Duration(minutes: minutes);
  }

  // Build guidance text for larger uploads
  String? _buildUploadGuidance({
    int? sourceBytes,
    bool expectTranscode = false,
  }) {
    final double srcMb = (sourceBytes ?? 0) / (1024 * 1024);
    final int selectedSeconds =
        _videoDurations[_selectedDuration]['seconds'] as int;
    final bool isLarge =
        srcMb >= 100 || selectedSeconds >= 300 || expectTranscode;
    if (!isLarge) return null;
    final List<String> parts = [];
    if (srcMb > 0) parts.add('Original ~${srcMb.toStringAsFixed(1)}MB');
    if (expectTranscode) parts.add('Transcoding to MP4 for compatibility');
    if (selectedSeconds >= 300)
      parts.add('Long video; consider trimming or lowering resolution');
    parts.add('Uploads may take longer on slow connections');
    return parts.join(' • ');
  }

  // Handle user cancel during upload
  void _onCancelUploadTap() {
    if (!_isUploading) return;
    _uploadProgressTimer?.cancel();
    _cancelUpload = true;
    try {
      if (_uploadCancelCompleter != null &&
          !_uploadCancelCompleter!.isCompleted) {
        _uploadCancelCompleter!.completeError(Exception('upload cancelled'));
      }
    } catch (_) {}
    if (mounted) {
      setState(() {
        _isUploading = false;
        _uploadProgress = 0.0;
        _uploadEtaText = null;
        _uploadStartTime = null;
      });
    }
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: LocalizedText('upload_canceled'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (_) {}
  }

  final List<String> _effects = [
    // ignore: unused_field
    '✨ Sparkle',
    '🌟 Glow',
    '💫 Shimmer',
    '🔥 Fire',
    '❄️ Frost',
    '🌈 Rainbow',
  ];

  // Effects Lab catalog (UI-only until native bindings are wired)
  final List<Map<String, dynamic>> _effectsLab = [
    {
      'id': 'beauty_soft',
      'name': 'Beauty Soft',
      'category': 'Beauty',
      'color': const Color(0xFFFFA8A8),
    },
    {
      'id': 'warm_skin_glow',
      'name': 'Warm Skin',
      'category': 'Beauty',
      'color': const Color(0xFFF5B288),
    },
    {
      'id': 'glam_makeup',
      'name': 'Glam Makeup',
      'category': 'Beauty',
      'color': const Color(0xFFFF6F91),
    },
    {
      'id': 'portrait_bokeh',
      'name': 'Portrait Bokeh',
      'category': 'Portrait',
      'color': const Color(0xFF0EA5E9),
    },
    {
      'id': 'background_replace',
      'name': 'Background Replace',
      'category': 'Portrait',
      'color': const Color(0xFF6366F1),
    },
    {
      'id': 'relight_portrait',
      'name': 'Relight',
      'category': 'Portrait',
      'color': const Color(0xFFFB7185),
    },
    {
      'id': 'face_landmarks',
      'name': 'Face Landmarks',
      'category': 'Face',
      'color': const Color(0xFFF59E0B),
    },
    {
      'id': 'eye_brighten',
      'name': 'Eye Brighten',
      'category': 'Face',
      'color': const Color(0xFFFCD34D),
    },
    {
      'id': 'lip_tint',
      'name': 'Lip Tint',
      'category': 'Face',
      'color': const Color(0xFFEF4444),
    },
    {
      'id': 'lut_teal_orange',
      'name': 'Teal & Orange',
      'category': 'Color',
      'color': const Color(0xFFFF7E43),
    },
    {
      'id': 'lut_cinematic_blue',
      'name': 'Cinematic Blue',
      'category': 'Color',
      'color': const Color(0xFF3AA0FF),
    },
    {
      'id': 'lut_mono_film',
      'name': 'Mono Film',
      'category': 'Color',
      'color': const Color(0xFF888888),
    },
    {
      'id': 'curves_enhance',
      'name': 'Curves Enhance',
      'category': 'Body',
      'color': const Color(0xFFFF5E8A),
    },
    {
      'id': 'hip_bum_enhancer',
      'name': 'Hip & Bum Enhancer',
      'category': 'Body',
      'color': const Color(0xFFCF7CAB),
    },
  ];

  String _selectedEffectsCategory = 'Beauty';
  String? _selectedEffectId;
  double _selectedEffectIntensity = 0.5;
  // Persist multiple applied effects with their intensities
  final Map<String, double> _appliedEffects = {};

  // Effect filter helpers to apply selected effect to the live preview
  List<double> _identityColorMatrix() => const [
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

  List<double> _grayscaleMatrix() => const [
    0.2126,
    0.7152,
    0.0722,
    0,
    0,
    0.2126,
    0.7152,
    0.0722,
    0,
    0,
    0.2126,
    0.7152,
    0.0722,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ];

  List<double> _saturationMatrix(double s) {
    // s = 1.0 means no change; s > 1 increases saturation; s < 1 decreases
    const lr = 0.2126;
    const lg = 0.7152;
    const lb = 0.0722;
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

  List<double> _warmthMatrix(double warm) {
    // warm in [0,1]: increase reds, slightly decrease blues
    final double r = 1 + 0.08 * warm;
    final double g = 1 + 0.02 * warm;
    final double b = 1 - 0.06 * warm;
    return [r, 0, 0, 0, 0, 0, g, 0, 0, 0, 0, 0, b, 0, 0, 0, 0, 0, 1, 0];
  }

  List<double> _blueToneMatrix(double cool) {
    // cool in [0,1]: shift towards blue, reduce reds slightly
    final double r = 1 - 0.06 * cool;
    final double g = 1 - 0.02 * cool;
    final double b = 1 + 0.10 * cool;
    return [r, 0, 0, 0, 0, 0, g, 0, 0, 0, 0, 0, b, 0, 0, 0, 0, 0, 1, 0];
  }

  List<double> _brightnessMatrix(double amount) {
    // amount in [0,1]: add stronger positive bias to each channel
    final double bias = 24.0 * amount; // increased bias (0..24)
    return [
      1,
      0,
      0,
      0,
      bias,
      0,
      1,
      0,
      0,
      bias,
      0,
      0,
      1,
      0,
      bias,
      0,
      0,
      0,
      1,
      0,
    ];
  }

  List<double> _lerpMatrix(List<double> a, List<double> b, double t) {
    final out = List<double>.filled(20, 0);
    for (int i = 0; i < 20; i++) {
      out[i] = a[i] + (b[i] - a[i]) * t;
    }
    return out;
  }

  List<double> _composeSimple(
    List<double> base,
    List<double> overlay,
    double t,
  ) {
    // simple blend: lerp base->overlay by t; not a true matrix multiply but good enough for preview
    return _lerpMatrix(base, overlay, t);
  }

  List<double> _effectColorMatrix(String id, double t) {
    final identity = _identityColorMatrix();
    switch (id) {
      case 'lut_mono_film':
      case 'mono_film':
        return _lerpMatrix(identity, _grayscaleMatrix(), t);
      case 'lut_cinematic_blue':
      case 'cinematic_blue':
        return _blueToneMatrix(t);
      case 'lut_teal_orange':
      case 'teal_orange':
        // approximate by significantly increasing saturation and warmth
        final sat = _saturationMatrix(1.0 + 0.90 * t);
        final warm = _warmthMatrix((1.5 * t).clamp(0.0, 1.0));
        return _composeSimple(sat, warm, 0.6);
      case 'warm_skin_glow':
        final warm = _warmthMatrix((1.5 * t).clamp(0.0, 1.0));
        final bright = _brightnessMatrix(1.2 * t);
        return _composeSimple(warm, bright, 0.6);
      case 'glam_makeup':
        return _saturationMatrix(1.0 + 1.2 * t);
      case 'lip_tint':
        // boost red channel significantly
        final double r = 1 + 0.35 * t;
        return [
          r,
          0,
          0,
          0,
          18.0 * t,
          0,
          1,
          0,
          0,
          0,
          0,
          0,
          1,
          0,
          -6.0 * t,
          0,
          0,
          0,
          1,
          0,
        ];
      case 'eye_brighten':
      case 'relight_portrait':
        return _brightnessMatrix(t);
      case 'face_landmarks':
      case 'portrait_bokeh':
      case 'background_replace':
        // complex effects not supported in preview; keep identity
        return identity;
      case 'curves_enhance':
        // preview approximation: stronger saturation + warmth
        final sat = _saturationMatrix(1.0 + 0.80 * t);
        final warm = _warmthMatrix((1.2 * t).clamp(0.0, 1.0));
        return _composeSimple(sat, warm, 0.6);
      case 'hip_bum_enhancer':
        // Geometry-based effect handled separately; keep color matrix identity in preview
        return identity;
      default:
        return identity;
    }
  }

  Widget _withBodyReshape(Widget child, double intensity) {
    // Applies horizontal expansion to lower half of the frame to emphasize hips/bum.
    final double scaleX =
        1.0 + 0.24 * intensity; // up to +24% width in lower half
    return LayoutBuilder(
      builder: (context, constraints) {
        final double h = constraints.maxHeight;
        final double w = constraints.maxWidth;
        return Stack(
          children: [
            // Top half (unscaled)
            ClipRect(
              child: Align(
                alignment: Alignment.topCenter,
                heightFactor: 0.5,
                child: SizedBox(width: w, height: h, child: child),
              ),
            ),
            // Bottom half (scaled horizontally)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: h * 0.5,
              child: ClipRect(
                child: OverflowBox(
                  minWidth: 0,
                  minHeight: 0,
                  maxWidth: double.infinity,
                  maxHeight: double.infinity,
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Transform.scale(
                      alignment: Alignment.bottomCenter,
                      scaleX: scaleX,
                      scaleY: 1.0,
                      child: SizedBox(width: w, height: h, child: child),
                    ),
                  ),
                ),
              ),
            ),
            // Feather seam with a subtle gradient overlay
            Positioned(
              left: 0,
              right: 0,
              top: h * 0.5 - 8,
              height: 16,
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(0.12 * intensity),
                        Colors.transparent,
                        Colors.black.withOpacity(0.12 * intensity),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // Centered vertical (9:16) framed preview that adapts to device size
  Widget _buildPortraitPreviewFrame({
    required Widget child,
    Size? intrinsicSize,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double maxW = constraints.maxWidth;
        final double maxH = constraints.maxHeight;
        final double baseW = math.min(maxW, maxH);

        // Choose a fraction based on device width to keep frame visibly smaller
        double widthFraction;
        if (baseW < 360) {
          widthFraction = 0.84; // very small phones: still prominent
        } else if (baseW < 420) {
          widthFraction = 0.78;
        } else if (baseW < 520) {
          widthFraction = 0.72;
        } else {
          widthFraction = 0.62; // tablets/large screens: noticeably smaller
        }

        double targetW = baseW * widthFraction;
        const double maxPortraitWidth = 420.0; // upper bound to keep compact
        if (targetW > maxPortraitWidth) {
          targetW = maxPortraitWidth;
        }

        double targetH = targetW * (16.0 / 9.0);
        // Cap height to ~82% of available height to avoid edge-to-edge
        final double maxFrameH = maxH * 0.82;
        if (targetH > maxFrameH) {
          targetH = maxFrameH;
          targetW = targetH * (9.0 / 16.0);
        }

        return Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Container(
              width: targetW,
              height: targetH,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withOpacity(0.18)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: intrinsicSize?.width ?? targetW,
                  height: intrinsicSize?.height ?? targetH,
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _withEffect(Widget child) {
    Widget composed = child;
    // Stack all previously applied effects (color effects via nested ColorFiltered)
    for (final entry in _appliedEffects.entries) {
      final String id = entry.key;
      final double t = entry.value.clamp(0.0, 1.0);
      if (id == 'hip_bum_enhancer') continue; // handle geometry separately
      final matrix = _effectColorMatrix(id, t);
      composed = ColorFiltered(
        colorFilter: ColorFilter.matrix(matrix),
        child: composed,
      );
    }

    // Apply filter chip overlay on top if selected
    if (_selectedFilter != 0) {
      final String? fid = _filters[_selectedFilter]['id'] as String?;
      if (fid != null) {
        final double ft = _filterIntensity.clamp(0.0, 1.0);
        final matrix = _effectColorMatrix(fid, ft);
        composed = ColorFiltered(
          colorFilter: ColorFilter.matrix(matrix),
          child: composed,
        );
      }
    }

    // Preview a newly selected effect (not yet applied) without canceling prior ones
    if (_selectedEffectId != null &&
        !_appliedEffects.containsKey(_selectedEffectId)) {
      final String id = _selectedEffectId!;
      final double t = _selectedEffectIntensity.clamp(0.0, 1.0);
      if (id != 'hip_bum_enhancer') {
        final matrix = _effectColorMatrix(id, t);
        composed = ColorFiltered(
          colorFilter: ColorFilter.matrix(matrix),
          child: composed,
        );
      }
    }

    // Geometry-based body reshape applied last (outermost)
    double? hipIntensity = _appliedEffects['hip_bum_enhancer'];
    if (_selectedEffectId == 'hip_bum_enhancer' && hipIntensity == null) {
      hipIntensity = _selectedEffectIntensity.clamp(0.0, 1.0);
    }
    if (hipIntensity != null && hipIntensity > 0) {
      composed = _withBodyReshape(composed, hipIntensity);
    }

    return composed;
  }

  final List<Map<String, String>> _musicTracks = [
    // ignore: unused_field
    {'name': 'Trending Beat 1', 'artist': 'Equal Music'},
    {'name': 'Viral Vibes', 'artist': 'Equal Beats'},
    {'name': 'Dance Energy', 'artist': 'Equal Sound'},
    {'name': 'Chill Mood', 'artist': 'Equal Lounge'},
    {'name': 'Hip Hop Flow', 'artist': 'Equal Hip Hop'},
  ];

  final List<Map<String, dynamic>> _videoDurations = [
    {'name': '15s', 'seconds': 15, 'icon': Icons.timer},
    {'name': '30s', 'seconds': 30, 'icon': Icons.timer},
    {'name': '1min', 'seconds': 60, 'icon': Icons.schedule},
    {'name': '5min', 'seconds': 300, 'icon': Icons.schedule},
    {'name': '12min', 'seconds': 720, 'icon': Icons.schedule},
  ];

  // Output resolution options (affects compression before upload)
  final List<Map<String, dynamic>> _videoResolutions = [
    {'name': '480p', 'height': 480, 'icon': Icons.hd},
    {'name': '720p', 'height': 720, 'icon': Icons.hd},
    {'name': '1080p', 'height': 1080, 'icon': Icons.hd},
  ];
  int _selectedResolution = 1; // default to 720p
  // Hide resolution options in the UI
  final bool _showResolutionOptions = false;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    }
    _initializeCamera();
    if (kIsWeb) {
      _initializeRtcRenderer();
    }
    _initializeAnimations();
    _uploadStatusSub = UploadService().statusStream.listen((status) {
      if (!mounted) return;
      if (status.state == UploadState.idle) {
        setState(() {
          _isUploading = false;
          _uploadProgress = 0.0;
          _uploadEtaText = null;
          _uploadGuidanceText = null;
          _uploadStartTime = null;
        });
        return;
      }
      if (status.state == UploadState.error) {
        setState(() {
          _isUploading = false;
          _uploadProgress = 0.0;
          _uploadEtaText = null;
          _uploadGuidanceText = null;
          _uploadStartTime = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(status.errorMessage ?? 'Upload failed'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      if (status.state == UploadState.success) {
        setState(() {
          _isUploading = false;
          _uploadProgress = 1.0;
          _uploadEtaText = null;
          _uploadGuidanceText = status.message.isNotEmpty
              ? status.message
              : null;
          _uploadStartTime = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              status.message.isNotEmpty ? status.message : 'Upload complete',
            ),
            backgroundColor: Colors.green,
          ),
        );
        return;
      }
      setState(() {
        _isUploading = true;
        _uploadProgress = status.progress;
        _uploadEtaText = null;
        _uploadGuidanceText = status.message.isNotEmpty ? status.message : null;
        _uploadStartTime ??= DateTime.now();
      });
    });
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

  // Start live camera preview on web upon entering the screen
  Future<void> _startWebPreview() async {
    if (!kIsWeb) return;
    try {
      try {
        _webStream?.getTracks().forEach((t) {
          t.stop();
        });
      } catch (_) {}
      _webStream = null;

      try {
        await _rtcRenderer.initialize();
      } catch (_) {}
      _webStream = await webGetUserMedia({'audio': true, 'video': true});
      await webAttachRenderer(_rtcRenderer, _webStream!);
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('startWebPreview failed: ' + e.toString());
    }
  }

  void _initializeAnimations() {
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _filterController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _filterAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _filterController, curve: Curves.easeOut),
    );

    _pulseController.repeat(reverse: true);
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
          enableAudio: true,
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
    _videoPlayerController?.dispose();
    _captionController.dispose();
    _hashtagController.dispose();
    _pulseController.dispose();
    _filterController.dispose();
    _uploadProgressTimer?.cancel();
    _uploadStatusSub?.cancel();
    _countdownTimer?.cancel();
    if (!kIsWeb) {
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    }
    if (kIsWeb) {
      try {
        _rtcRenderer.dispose();
      } catch (_) {}
      try {
        _webStream?.getTracks().forEach((t) {
          t.stop();
        });
      } catch (_) {}
      _webStream = null;
    }
    super.dispose();
  }

  Future<void> _toggleCamera() async {
    if (kIsWeb) {
      if (_isRecording) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: LocalizedText('stop_recording_to_switch_camera')),
        );
        return;
      }
      try {
        setState(() {
          _isFrontCamera = !_isFrontCamera;
        });
        try {
          _webStream?.getTracks().forEach((t) {
            t.stop();
          });
        } catch (_) {}
        _webStream = null;
        try {
          _webStream = await webGetUserMedia({
            'audio': true,
            'video': {'facingMode': _isFrontCamera ? 'user' : 'environment'},
          });
        } catch (_) {
          _webStream = await webGetUserMedia({'audio': true, 'video': true});
        }
        try {
          await _rtcRenderer.initialize();
        } catch (_) {}
        await webAttachRenderer(_rtcRenderer, _webStream!);
        setState(() {});
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: LocalizedText('failed_to_switch_camera'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

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

  Future<void> _startRecording() async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: LocalizedText('video_functionality_not_supported_on_web'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Use the native camera app via ImagePicker for perfect device ratio
    try {
      final picker = ImagePicker();
      final int selectedSeconds =
          _videoDurations[_selectedDuration]['seconds'] as int;
      final Duration? maxDuration = selectedSeconds > 0
          ? Duration(seconds: selectedSeconds)
          : null;
      final XFile? picked = await picker.pickVideo(
        source: ImageSource.camera,
        maxDuration: maxDuration,
      );
      if (picked != null) {
        if (mounted) {
          setState(() {
            _isRecording = false;
            _recordingProgress = 0.0;
            _videoPath = picked.path;
          });
        }
        await _initializeVideoPlayer();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: const LocalizedText('recording_saved')),
        );
      }
    } catch (e) {
      debugPrint(('Error capturing video: $e').toString());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: LocalizedText(
            LocalizationService.t(
              'failed_to_capture_video_error',
            ).replaceAll('{error}', e.toString()),
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _startRecordingTimer() {
    final int selectedSeconds =
        _videoDurations[_selectedDuration]['seconds'] as int;
    final int maxSeconds =
        selectedSeconds; // use selected duration directly (now capped at 12min)
    const interval = Duration(milliseconds: 100);
    int elapsedMs = 0;

    // Cancel any existing subscription before starting
    try {
      _recordingTimerSub?.cancel();
    } catch (_) {}
    _recordingTimerSub = Stream.periodic(interval, (i) => i).listen((
      tick,
    ) async {
      if (!_isRecording || _isStopping) return;

      elapsedMs += 100;
      if (mounted) {
        setState(() {
          _recordingProgress = (elapsedMs / (maxSeconds * 1000)).clamp(
            0.0,
            1.0,
          );
        });
      }

      if (selectedSeconds > 0 && elapsedMs >= selectedSeconds * 1000) {
        if (_autoStop) {
          // Auto-stop at selected duration and load the recorded video
          await _stopRecording();
        } else {
          // Failsafe: if we reached the selected duration and progress is full, stop after brief delay
          if (elapsedMs >= selectedSeconds * 1000 + 500 && !_isStopping) {
            await _stopRecording();
          }
        }
      }
    });
  }

  Future<void> _stopRecording() async {
    // Prevent re-entrant stop calls
    if (_isStopping) {
      debugPrint(
        'STOP: _stopRecording ignored; already stopping. isRecording=' +
            _isRecording.toString() +
            ' hasSession=' +
            (_webRecorderSession != null).toString() +
            ' hasPreview=' +
            (_webStream != null).toString(),
      );
      return;
    }
    _isStopping = true;
    debugPrint(
      'STOP: begin. kIsWeb=' +
          kIsWeb.toString() +
          ' isRecording=' +
          _isRecording.toString() +
          ' hasSession=' +
          (_webRecorderSession != null).toString() +
          ' hasPreview=' +
          (_webStream != null).toString(),
    );

    // Safety timeout to avoid getting stuck; if stop exceeds 7s, keep waiting but avoid resetting session prematurely
    Timer? stopTimeout;
    stopTimeout = Timer(const Duration(seconds: 7), () {
      if (mounted && _isStopping) {
        try {
          _recordingTimerSub?.cancel();
        } catch (_) {}
        // Reflect non-recording state in UI but DO NOT clear recorder session or flip _isStopping to false
        _isRecording = false;
        _recordingProgress = 0.0;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: LocalizedText('finalizing_recording')),
        );
        setState(() {});
      }
    });
    // Cancel the recording progress timer immediately
    try {
      await _recordingTimerSub?.cancel();
    } catch (_) {}
    _recordingTimerSub = null;

    if (kIsWeb) {
      try {
        if (_webRecorderSession == null) {
          debugPrint('STOP: web branch but _webRecorderSession==null');
          // Even if no session, ensure state reflects stopped
          if (mounted) {
            setState(() {
              _isRecording = false;
              _recordingProgress = 0.0;
            });
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: const LocalizedText('no_active_recording')),
          );
          _isStopping = false;
          return;
        }
        final bytes = await webStopRecording(_webRecorderSession!);
        debugPrint('STOP: webStopRecording returned bytesLen=${bytes.length}');
        if (mounted) {
          setState(() {
            _isRecording = false;
            _videoBytes = bytes;
            _videoFileName =
                'recorded_${DateTime.now().millisecondsSinceEpoch}.webm';
            _recordingProgress = 0.0;
          });
        }
        debugPrint(
          'STOP: setState applied. _videoBytes?.length=${_videoBytes?.length ?? -1}',
        );
        // Initialize preview player on web to allow editing before publish
        if (kIsWeb) {
          await _initializeVideoPlayer();
        }
        // Stop tracks and clear stream (both flutter_webrtc and html streams)
        try {
          _webStream?.getTracks().forEach((t) {
            t.stop();
          });
        } catch (_) {}
        try {
          _webRecorderSession?.stream?.getTracks().forEach((t) {
            t.stop();
          });
        } catch (_) {}
        await _analytics.trackEvent(
          'web_recording_stopped',
          properties: {'bytesLength': (bytes.length).toString()},
        );
        _webStream = null;
        _webRecorderSession = null;
        debugPrint('STOP: cleared streams and session.');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: const LocalizedText('recording_saved')),
        );
      } catch (e, st) {
        await _analytics.trackError(
          'web_stop_recording_failed',
          e.toString(),
          stackTrace: st.toString(),
          context: {
            'hadRecorderSession': (_webRecorderSession != null).toString(),
            'hadPreviewStream': (_webStream != null).toString(),
          },
        );
        debugPrint(
          'STOP: ERROR during stop: ${e.toString()} sessionNull=${_webRecorderSession == null} previewNull=${_webStream == null}',
        );
        // Failsafe: even if stop fails, exit recording state so UI doesn't hang
        if (mounted) {
          setState(() {
            _isRecording = false;
            _recordingProgress = 0.0;
          });
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: LocalizedText(
              LocalizationService.t('failed_to_stop_recording') +
                  ': ' +
                  e.toString(),
            ),
            backgroundColor: Colors.red,
          ),
        );
        // Attempt to release any media tracks to avoid device lockups
        try {
          _webStream?.getTracks().forEach((t) {
            t.stop();
          });
        } catch (_) {}
        try {
          _webRecorderSession?.stream?.getTracks().forEach((t) {
            t.stop();
          });
        } catch (_) {}
        _webStream = null;
        _webRecorderSession = null;
      } finally {
        debugPrint('STOP: finally. _isStopping -> false');
        _isStopping = false;
      }
      return;
    }

    if (_cameraController != null) {
      try {
        final XFile videoFile = await _cameraController!.stopVideoRecording();
        if (mounted) {
          setState(() {
            _isRecording = false;
            _videoPath = videoFile.path;
            _recordingProgress = 0.0;
          });
        }
        _initializeVideoPlayer();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: const LocalizedText('recording_saved')),
        );
      } catch (e) {
        debugPrint(('Error stopping recording: $e').toString());
        if (mounted) {
          setState(() {
            _isRecording = false;
            _recordingProgress = 0.0;
          });
        }
      } finally {
        _isStopping = false;
      }
    } else {
      // No active camera recording; ensure flags reset
      if (mounted) {
        setState(() {
          _isRecording = false;
          _recordingProgress = 0.0;
        });
      }
      _isStopping = false;
    }
  }

  Future<void> _initializeVideoPlayer() async {
    if (kIsWeb) {
      // Web: if recorded/uploaded bytes exist, preview them using a data: URL
      try {
        if (_videoBytes != null && _videoBytes!.isNotEmpty) {
          _videoPlayerController?.dispose();
          // Infer MIME type from filename when available; fallback to recorder-provided MIME or mp4
          String mime;
          if (_videoFileName != null && _videoFileName!.contains('.')) {
            final ext = _videoFileName!.split('.').last.toLowerCase();
            switch (ext) {
              case 'mp4':
                mime = 'video/mp4';
                break;
              case 'webm':
                mime = 'video/webm';
                break;
              case 'mov':
                mime = 'video/quicktime';
                break;
              default:
                mime = _webRecorderSession?.mime ?? 'video/mp4';
            }
          } else {
            mime = _webRecorderSession?.mime ?? 'video/webm';
          }
          final String dataUrl =
              'data:' + mime + ';base64,' + base64Encode(_videoBytes!);
          _videoPlayerController = VideoPlayerController.networkUrl(
            Uri.parse(dataUrl),
          );
          await _videoPlayerController!.initialize();
          _videoPlayerController!.setLooping(true);
          _videoPlayerController!.play();
        }
      } catch (e) {
        debugPrint(('Web preview init failed: ' + e.toString()).toString());
      }
      setState(() {});
    } else if (_videoPath != null) {
      try {
        final file = File(_videoPath!);
        // Give the camera a brief moment to finalize the file on some devices
        int tries = 0;
        while (!file.existsSync() && tries < 5) {
          await Future.delayed(const Duration(milliseconds: 200));
          tries++;
        }

        _videoPlayerController = VideoPlayerController.file(file);
        await _videoPlayerController!.initialize();
        _videoPlayerController!.setLooping(true);
        await _videoPlayerController!.play();
      } catch (e) {
        // Fallback: use a file:// URI via network controller; some OEMs prefer this source
        try {
          final uri = Uri.file(_videoPath!);
          _videoPlayerController = VideoPlayerController.networkUrl(uri);
          await _videoPlayerController!.initialize();
          _videoPlayerController!.setLooping(true);
          await _videoPlayerController!.play();
        } catch (e2) {
          debugPrint(
            ('Mobile preview init failed: ' + e2.toString()).toString(),
          );
          rethrow;
        }
      }
      setState(() {});
    }
  }

  Future<void> _publishPost() async {
    if (_isUploading || _isImporting) return;

    // Basic validation
    if (kIsWeb) {
      if (_videoBytes == null && _videoPath == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: LocalizedText('no_video_to_publish')),
        );
        return;
      }
    } else {
      if (_videoPath == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: LocalizedText('no_video_to_publish')),
        );
        return;
      }
    }

    // Stop playback
    if (_videoPlayerController != null) {
      await _videoPlayerController!.pause();
    }

    // Construct metadata
    final List<Map<String, dynamic>> effectsList = [];
    _appliedEffects.forEach((id, intensity) {
      effectsList.add({'id': id, 'intensity': intensity});
    });

    if (_selectedEffectId != null &&
        !_appliedEffects.containsKey(_selectedEffectId)) {
      effectsList.add({
        'id': _selectedEffectId,
        'intensity': _selectedEffectIntensity,
      });
    }

    final metadata = {
      'duration': _videoDurations[_selectedDuration]['seconds'],
      'width': _videoResolutions[_selectedResolution]['width'],
      'height': _videoResolutions[_selectedResolution]['height'],
      'speed': _speed,
      'filter_id': _selectedFilter != 0
          ? _filters[_selectedFilter]['id']
          : null,
      'filter_intensity': _selectedFilter != 0 ? _filterIntensity : null,
      'effectsLab': effectsList,
    };

    try {
      setState(() => _isUploading = true);

      final caption = _captionController.text.trim();
      final hashtags = _hashtagController.text.trim().isEmpty
          ? <String>[]
          : _hashtagController.text.trim().split(' ');

      if (kIsWeb) {
        Uint8List? videoBytes;
        if (_videoBytes != null) {
          videoBytes = _videoBytes;
        } else if (_videoPath != null && _videoPath!.startsWith('data:')) {
          final comma = _videoPath!.indexOf(',');
          if (comma != -1) {
            videoBytes = base64Decode(_videoPath!.substring(comma + 1));
          }
        }
        if (videoBytes == null || videoBytes.isEmpty) {
          throw Exception('No video data available for upload');
        }
        await _publishPostWebSimple(
          bytes: videoBytes,
          fileName: _videoFileName,
          caption: caption,
          hashtags: hashtags,
          metadata: metadata,
        );
        return;
      }

      String? videoPath = _videoPath;

      await UploadService().startVideoUpload(
        videoSource: null,
        videoPath: videoPath,
        videoFileName: _videoFileName,
        caption: caption,
        hashtags: hashtags,
        metadata: metadata,
        userId: AuthService().currentUser!.id,
        parentPostId: widget.parentPostId,
        saveToGallery: await PreferencesService().getSaveToGallery(),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Video processing started in background. You can continue using the app.',
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 4),
          ),
        );

        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const MainScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to start upload: $e'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _isUploading = false);
      }
    }
  }

  Future<void> _publishPostWebSimple({
    required Uint8List bytes,
    required String? fileName,
    required String caption,
    required List<String> hashtags,
    required Map<String, dynamic> metadata,
  }) async {
    try {
      _uploadStartTime ??= DateTime.now();
      if (mounted) {
        setState(() {
          _uploadProgress = 0.1;
          _uploadEtaText = null;
          _uploadGuidanceText = 'Uploading...';
        });
      }

      try {
        _webStream?.getTracks().forEach((t) {
          t.stop();
        });
      } catch (_) {}
      try {
        _webRecorderSession?.stream?.getTracks().forEach((t) {
          t.stop();
        });
      } catch (_) {}
      _webStream = null;
      _webRecorderSession = null;

      final normalizedHashtags = hashtags
          .map((tag) => tag.trim())
          .where((tag) => tag.isNotEmpty)
          .map((tag) => tag.startsWith('#') ? tag : '#$tag')
          .toList();
      final captionForPublish = [
        if (caption.isNotEmpty) caption,
        if (normalizedHashtags.isNotEmpty) normalizedHashtags.join(' '),
      ].join(caption.isNotEmpty && normalizedHashtags.isNotEmpty ? ' ' : '');
      final resolvedFileName =
          fileName ?? 'video_${DateTime.now().millisecondsSinceEpoch}.mp4';

      if (mounted) {
        setState(() {
          _uploadProgress = 0.85;
          _uploadGuidanceText = 'Creating post...';
        });
      }

      await AppService()
          .createPost(
            type: 'video',
            caption: captionForPublish,
            mediaFile: bytes,
            metadata: {...metadata, 'fileName': resolvedFileName},
          )
          .timeout(const Duration(seconds: 60));

      if (mounted) {
        setState(() {
          _isUploading = false;
          _uploadProgress = 1.0;
          _uploadEtaText = null;
          _uploadGuidanceText = null;
          _uploadStartTime = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Upload complete'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const MainScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      final message = e is TimeoutException
          ? 'Upload timed out. Please try again.'
          : e.toString();
      if (mounted) {
        setState(() {
          _isUploading = false;
          _uploadProgress = 0.0;
          _uploadEtaText = null;
          _uploadGuidanceText = null;
          _uploadStartTime = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed: $message'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _selectVideoFromFiles() async {
    setState(() {
      _isImporting = true;
      _importProgress = 0.0;
    });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.video,
        withData: kIsWeb,
      );
      if (result != null && result.files.isNotEmpty) {
        final f = result.files.first;
        // Enforce hard cap: 100MB maximum before import using platform-reported size
        const int absoluteMaxBytes = 100 * 1024 * 1024; // 100MB
        try {
          final int pickedSize = kIsWeb
              ? f.size
              : (f.path != null ? await File(f.path!).length() : 0);
          if (pickedSize > absoluteMaxBytes) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: LocalizedText('Post size must be 100MB and below.'),
                backgroundColor: Colors.red,
              ),
            );
            return;
          }
        } catch (_) {}
        if (kIsWeb) {
          setState(() {
            _videoBytes = f.bytes;
            _videoFileName = f.name;
            _videoPath = null;
          });
        } else {
          if (f.path != null) {
            setState(() {
              _videoPath = f.path;
              _videoBytes = null;
              _videoFileName = null;
            });
          }
        }
        // Initialize preview for uploaded videos
        await _initializeVideoPlayer();
      }
    } finally {
      if (mounted) {
        setState(() {
          _isImporting = false;
          _importProgress = 0.0;
        });
      }
    }
  }

  Future<void> _pickVideoFromGallery() async {
    if (kIsWeb) return;
    setState(() {
      _isImporting = true;
      _importProgress = 0.0;
    });
    try {
      final picker = ImagePicker();
      final XFile? picked = await picker.pickVideo(source: ImageSource.gallery);
      if (picked != null) {
        // Enforce hard cap: 100MB maximum before import
        try {
          const int absoluteMaxBytes = 100 * 1024 * 1024; // 100MB
          final size = await File(picked.path).length();
          if (size > absoluteMaxBytes) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: LocalizedText('Post size must be 100MB and below.'),
                backgroundColor: Colors.red,
              ),
            );
            return;
          }
        } catch (_) {}
        setState(() {
          _videoPath = picked.path;
          _videoBytes = null;
          _videoFileName = null;
        });
        await _initializeVideoPlayer();
      }
    } finally {
      if (mounted) {
        setState(() {
          _isImporting = false;
          _importProgress = 0.0;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: Navigator.canPop(context),
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.pushReplacementNamed(context, '/main');
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // Background: camera/web preview inside a centered vertical frame (9:16), responsive
            Positioned.fill(
              child: Builder(
                builder: (_) {
                  if (!kIsWeb) {
                    if (_videoPlayerController != null &&
                        _videoPlayerController!.value.isInitialized) {
                      final Size s = _videoPlayerController!.value.size;
                      return _buildPortraitPreviewFrame(
                        child: _withEffect(
                          VideoPlayer(_videoPlayerController!),
                        ),
                        intrinsicSize: s,
                      );
                    } else if (_cameraController != null &&
                        _cameraController!.value.isInitialized) {
                      final Size? ps = _cameraController!.value.previewSize;
                      final double cw = ps?.width ?? 1080;
                      final double ch = ps?.height ?? 1920;
                      return _buildPortraitPreviewFrame(
                        child: _withEffect(CameraPreview(_cameraController!)),
                        intrinsicSize: Size(cw, ch),
                      );
                    } else {
                      return Container(color: Colors.black);
                    }
                  } else {
                    if (_videoPlayerController != null &&
                        _videoPlayerController!.value.isInitialized) {
                      final Size s = _videoPlayerController!.value.size;
                      return _buildPortraitPreviewFrame(
                        child: VideoPlayer(_videoPlayerController!),
                        intrinsicSize: s,
                      );
                    } else if (_webStream != null &&
                        _rtcRenderer.textureId != null) {
                      // Web RTC preview — framed vertically
                      return _buildPortraitPreviewFrame(
                        child: _withEffect(RTCVideoView(_rtcRenderer)),
                      );
                    } else {
                      return Container(color: Colors.black);
                    }
                  }
                },
              ),
            ),
            // Effects preview overlay (UI-only tint to simulate live effect)
            Positioned.fill(
              child: Builder(
                builder: (_) {
                  // Derive overlay color/intensity from either selected effect or selected filter for immediate preview
                  final String? overlayId =
                      _selectedEffectId ??
                      (_selectedFilter != 0
                          ? (_filters[_selectedFilter]['id'] as String?)
                          : null);
                  if (overlayId == null) return const SizedBox.shrink();
                  Color overlay = Colors.transparent;
                  switch (overlayId) {
                    case 'lut_teal_orange':
                    case 'teal_orange':
                      overlay = const Color(0xFFFF7E43);
                      break;
                    case 'lut_cinematic_blue':
                    case 'cinematic_blue':
                      overlay = const Color(0xFF3AA0FF);
                      break;
                    case 'lut_mono_film':
                    case 'mono_film':
                      overlay = const Color(0xFF888888);
                      break;
                    case 'beauty_soft':
                    case 'warm_skin_glow':
                    case 'glam_makeup':
                      overlay = const Color(0xFFE100FF);
                      break;
                    case 'portrait_bokeh':
                      overlay = Colors.black;
                      break;
                    case 'background_replace':
                      overlay = const Color(0xFF6366F1);
                      break;
                    case 'relight_portrait':
                      overlay = const Color(0xFFFB7185);
                      break;
                    case 'face_landmarks':
                      overlay = const Color(0xFFF59E0B);
                      break;
                    case 'eye_brighten':
                      overlay = const Color(0xFFFCD34D);
                      break;
                    case 'lip_tint':
                      overlay = const Color(0xFFEF4444);
                      break;
                    default:
                      overlay = Colors.white;
                  }
                  final double intensity =
                      (_selectedEffectId != null
                              ? _selectedEffectIntensity
                              : _filterIntensity)
                          .clamp(0.0, 1.0);
                  // Make overlay subtler so video remains fully visible
                  final double opacity = intensity * 0.06;
                  return IgnorePointer(
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: _isRecording ? opacity * 0.85 : opacity,
                      child: Container(color: overlay.withOpacity(opacity)),
                    ),
                  );
                },
              ),
            ),
            // Legibility gradient overlay (lighter to keep video visible)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.black26,
                        Colors.transparent,
                        Colors.black26,
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ),
            ),
            // Top bar
            if (!_isRecording && (_countdown == null || _countdown == 0))
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        onPressed: () =>
                            Navigator.pushReplacementNamed(context, '/main'),
                        icon: const Icon(Icons.close, color: Colors.white),
                      ),
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const LocalizedText(
                              'create_video',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (_selectedEffectId != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.15),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.color_lens,
                                      size: 16,
                                      color: Colors.white70,
                                    ),
                                    const SizedBox(width: 4),
                                    Builder(
                                      builder: (context) {
                                        final String id = _selectedEffectId!;
                                        final int pct =
                                            (_selectedEffectIntensity * 100)
                                                .round();
                                        return Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            LocalizedText(
                                              'effect_' + id,
                                              style: const TextStyle(
                                                color: Colors.white70,
                                                fontSize: 12,
                                              ),
                                            ),
                                            const Text(
                                              ' · ',
                                              style: TextStyle(
                                                color: Colors.white70,
                                                fontSize: 12,
                                              ),
                                            ),
                                            Text(
                                              '$pct%',
                                              style: const TextStyle(
                                                color: Colors.white70,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 24),
                    ],
                  ),
                ),
              ),
            // Right-side tools
            if (!_isRecording && (_countdown == null || _countdown == 0))
              Positioned(
                right: 12,
                top: 120,
                child: Column(
                  children: [
                    // Settings gear
                    GestureDetector(
                      onTap: _showSettingsSheet,
                      child: Column(
                        children: [
                          const Icon(Icons.settings, color: Colors.white),
                          LocalizedText(
                            'settings',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (!kIsWeb)
                      Column(
                        children: [
                          IconButton(
                            onPressed: _toggleCamera,
                            icon: const Icon(
                              Icons.flip_camera_android,
                              color: Colors.white,
                            ),
                          ),
                          LocalizedText(
                            'flip',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 16),
                    if (!kIsWeb)
                      Column(
                        children: [
                          IconButton(
                            onPressed: _toggleFlash,
                            icon: Icon(
                              _isFlashOn ? Icons.flash_on : Icons.flash_off,
                              color: Colors.white,
                            ),
                          ),
                          LocalizedText(
                            'flash',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 16),
                    if (!_isRecording &&
                        (_countdown == null || _countdown == 0))
                      GestureDetector(
                        onTap: _showEffectsSheet,
                        child: Stack(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.15),
                                ),
                              ),
                              child: Column(
                                children: [
                                  const Icon(
                                    Icons.color_lens,
                                    color: Colors.white,
                                  ),
                                  const SizedBox(height: 4),
                                  LocalizedText(
                                    'effects',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (_selectedEffectId != null)
                              Positioned(
                                top: 6,
                                right: 6,
                                child: Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: LinearGradient(
                                      colors: [
                                        Color(0xFF7F00FF),
                                        Color(0xFFE100FF),
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 16),
                    if (!_isRecording &&
                        (_countdown == null || _countdown == 0))
                      GestureDetector(
                        onTap: _showTimerSheet,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.15),
                            ),
                          ),
                          child: Column(
                            children: [
                              const Icon(Icons.timer, color: Colors.white),
                              const SizedBox(height: 4),
                              LocalizedText(
                                'timer',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    if (!_isRecording &&
                        (_countdown == null || _countdown == 0))
                      GestureDetector(
                        onTap: _showSpeedSheet,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.15),
                            ),
                          ),
                          child: Column(
                            children: [
                              const Icon(Icons.speed, color: Colors.white),
                              const SizedBox(height: 4),
                              LocalizedText(
                                'speed',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    if (false)
                      GestureDetector(
                        onTap: () {
                          final bool initialized =
                              _videoPlayerController?.value.isInitialized ??
                              false;
                          debugPrint(
                            'DEBUG STATE -> kIsWeb=' +
                                kIsWeb.toString() +
                                ' hasController=' +
                                (_videoPlayerController != null).toString() +
                                ' initialized=' +
                                initialized.toString() +
                                ' bytesLen=' +
                                (_videoBytes?.length ?? 0).toString() +
                                ' fileName=' +
                                (_videoFileName ?? 'null') +
                                ' videoPath=' +
                                (_videoPath ?? 'null') +
                                ' webStream=' +
                                (_webStream != null).toString() +
                                ' rtcTexture=' +
                                (_rtcRenderer.textureId?.toString() ?? 'null'),
                          );
                          try {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: AutoTranslatedText(
                                  'Preview: ' +
                                      (initialized
                                          ? 'initialized'
                                          : 'not initialized') +
                                      ' | bytes: ' +
                                      (_videoBytes?.length ?? 0).toString(),
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                            );
                          } catch (_) {}
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.15),
                            ),
                          ),
                          child: Column(
                            children: [
                              const Icon(Icons.bug_report, color: Colors.white),
                              const SizedBox(height: 4),
                              LocalizedText(
                                'debug',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            // Inline processing overlay
            if (_processingStartTime != null)
              Positioned(
                top: 64,
                left: 16,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          value: _processingProgress > 0
                              ? _processingProgress
                              : null,
                          strokeWidth: 3,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            Colors.cyanAccent,
                          ),
                          backgroundColor: Colors.white12,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Use dynamic label for processing state
                            Text(
                              _processingLabel == 'processing_video'
                                  ? 'Processing video'
                                  : 'Preparing for upload',
                              style: const TextStyle(color: Colors.white70),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Text(
                                  '${(_processingProgress * 100).clamp(0, 100).toStringAsFixed(0)}%',
                                  style: const TextStyle(color: Colors.white),
                                ),
                                const SizedBox(width: 8),
                                if (_etaText != null)
                                  LocalizedText(
                                    'ETA ${_etaText}',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            if (_processingLabel == 'preparing_for_upload')
                              Row(
                                children: [
                                  if (_sourceSizeBytes != null)
                                    LocalizedText(
                                      LocalizationService.t(
                                        'original_size_mb',
                                      ).replaceAll(
                                        '{value}',
                                        (_sourceSizeBytes! / (1024 * 1024))
                                            .toStringAsFixed(1),
                                      ),
                                      style: const TextStyle(
                                        color: Colors.white70,
                                      ),
                                    ),
                                  if (_sourceSizeBytes != null &&
                                      _compressedSizeBytes != null)
                                    const SizedBox(width: 8),
                                  if (_compressedSizeBytes != null)
                                    LocalizedText(
                                      LocalizationService.t(
                                        'compressed_size_mb',
                                      ).replaceAll(
                                        '{value}',
                                        (_compressedSizeBytes! / (1024 * 1024))
                                            .toStringAsFixed(1),
                                      ),
                                      style: const TextStyle(
                                        color: Colors.white70,
                                      ),
                                    ),
                                  const SizedBox(width: 8),
                                  const LocalizedText(
                                    'target_upload_limit',
                                    style: TextStyle(color: Colors.white38),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => setState(() {
                          _cancelProcessing = true;
                        }),
                        icon: const Icon(Icons.cancel, color: Colors.white70),
                        label: const LocalizedText(
                          'cancel',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            // Uploading overlay
            if (_isUploading)
              Positioned(
                top: 64 + 60, // stack below processing overlay if both show
                left: 16,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          value: _uploadProgress > 0 ? _uploadProgress : null,
                          strokeWidth: 3,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            Colors.deepPurpleAccent,
                          ),
                          backgroundColor: Colors.white12,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const LocalizedText(
                              'uploading_video',
                              style: TextStyle(color: Colors.white70),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                if (_uploadProgress > 0)
                                  Text(
                                    '${(_uploadProgress * 100).clamp(0, 100).toStringAsFixed(0)}%',
                                    style: const TextStyle(color: Colors.white),
                                  )
                                else
                                  const LocalizedText(
                                    'in_progress',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                const SizedBox(width: 8),
                                if (_uploadEtaText != null)
                                  Text(
                                    'ETA ${_uploadEtaText}',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                    ),
                                  ),
                              ],
                            ),
                            if (_uploadGuidanceText != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                _uploadGuidanceText!,
                                style: const TextStyle(color: Colors.white54),
                              ),
                            ],
                          ],
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _onCancelUploadTap,
                        icon: const Icon(Icons.cancel, color: Colors.white70),
                        label: const Text(
                          'Cancel Upload',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            // Recording progress overlay
            if (_isRecording)
              Positioned(
                top: 64,
                left: 0,
                right: 0,
                child: Column(
                  children: [
                    const LocalizedText(
                      'Recording...',
                      style: TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      (() {
                        final int selectedSeconds =
                            _videoDurations[_selectedDuration]['seconds']
                                as int;
                        final int elapsedSec =
                            (_recordingProgress * selectedSeconds)
                                .clamp(0, selectedSeconds)
                                .round();
                        final String mm = (elapsedSec ~/ 60).toString().padLeft(
                          2,
                          '0',
                        );
                        final String ss = (elapsedSec % 60).toString().padLeft(
                          2,
                          '0',
                        );
                        final String mmTotal = (selectedSeconds ~/ 60)
                            .toString()
                            .padLeft(2, '0');
                        final String ssTotal = (selectedSeconds % 60)
                            .toString()
                            .padLeft(2, '0');
                        return '$mm:$ss / $mmTotal:$ssTotal';
                      })(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: LinearProgressIndicator(
                        value: _recordingProgress > 0
                            ? _recordingProgress
                            : null,
                        minHeight: 6,
                        backgroundColor: Colors.white12,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Colors.blueAccent,
                        ),
                      ),
                    ),
                    if (_isRecording && _recordingProgress >= 0.999)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: const LocalizedText(
                          'finalizing',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ),
                  ],
                ),
              ),
            // Simple countdown overlay when starting with Timer
            if (_countdown != null && _countdown! > 0)
              Positioned(
                top: 64,
                left: 0,
                right: 0,
                child: Center(
                  child: LocalizedText(
                    'Starting in ${_countdown}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            // Bottom control panel
            Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                minimum: const EdgeInsets.only(bottom: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Filter chips (horizontal carousel)
                    if (!_isRecording &&
                        (_countdown == null || _countdown == 0) &&
                        _showFilterChips)
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          children: List<Widget>.generate(_filters.length, (i) {
                            final f = _filters[i];
                            final selected = _selectedFilter == i;
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                              ),
                              child: GestureDetector(
                                onTap: () =>
                                    setState(() => _selectedFilter = i),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(20),
                                    gradient: selected
                                        ? const LinearGradient(
                                            colors: [
                                              Color(0xFF00C6FF),
                                              Color(0xFF0072FF),
                                            ],
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                          )
                                        : null,
                                    color: selected
                                        ? null
                                        : Colors.white.withOpacity(0.08),
                                    border: Border.all(
                                      color: Colors.white.withOpacity(0.18),
                                    ),
                                    boxShadow: selected
                                        ? [
                                            BoxShadow(
                                              color: const Color(
                                                0xFF0072FF,
                                              ).withOpacity(0.35),
                                              blurRadius: 16,
                                              offset: const Offset(0, 6),
                                            ),
                                          ]
                                        : [],
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.filter,
                                        color: Colors.white.withOpacity(
                                          selected ? 1.0 : 0.8,
                                        ),
                                        size: 18,
                                      ),
                                      const SizedBox(width: 8),
                                      LocalizedText(
                                        (f['name'] == 'Original')
                                            ? 'original'
                                            : (f['name'] as String),
                                        style: GoogleFonts.poppins(
                                          color: Colors.white,
                                          fontWeight: selected
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                      ),
                    const SizedBox(height: 8),
                    // Intensity slider
                    if (!_isRecording &&
                        (_countdown == null || _countdown == 0))
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Slider(
                                value: _filterIntensity,
                                min: 0.0,
                                max: 1.0,
                                divisions: 10,
                                onChanged: (v) =>
                                    setState(() => _filterIntensity = v),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${(_filterIntensity * 100).round()}%',
                              style: const TextStyle(color: Colors.white70),
                            ),
                            const SizedBox(width: 12),
                            const Icon(
                              Icons.speed,
                              color: Colors.white70,
                              size: 18,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${_speed.toStringAsFixed(2)}x',
                              style: const TextStyle(color: Colors.white70),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 12),
                    // Resolution chips (hidden by default)
                    if (!_isRecording &&
                        (_countdown == null || _countdown == 0) &&
                        _showResolutionOptions)
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          children: List<Widget>.generate(
                            _videoResolutions.length,
                            (i) {
                              final r = _videoResolutions[i];
                              final selected = _selectedResolution == i;
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                ),
                                child: GestureDetector(
                                  onTap: () =>
                                      setState(() => _selectedResolution = i),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(20),
                                      gradient: selected
                                          ? const LinearGradient(
                                              colors: [
                                                Color(0xFF00C6FF),
                                                Color(0xFF0072FF),
                                              ],
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                            )
                                          : null,
                                      color: selected
                                          ? null
                                          : Colors.white.withOpacity(0.08),
                                      border: Border.all(
                                        color: Colors.white.withOpacity(0.18),
                                      ),
                                      boxShadow: selected
                                          ? [
                                              BoxShadow(
                                                color: const Color(
                                                  0xFF0072FF,
                                                ).withOpacity(0.35),
                                                blurRadius: 16,
                                                offset: const Offset(0, 6),
                                              ),
                                            ]
                                          : [],
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          r['icon'] as IconData,
                                          color: Colors.white.withOpacity(
                                            selected ? 1.0 : 0.8,
                                          ),
                                          size: 18,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          r['name'] as String,
                                          style: GoogleFonts.poppins(
                                            color: Colors.white,
                                            fontWeight: selected
                                                ? FontWeight.w700
                                                : FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    // Duration chips
                    if (!_isRecording &&
                        (_countdown == null || _countdown == 0))
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          children: List<Widget>.generate(
                            _videoDurations.length,
                            (i) {
                              final d = _videoDurations[i];
                              final selected = _selectedDuration == i;
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                ),
                                child: GestureDetector(
                                  onTap: () =>
                                      setState(() => _selectedDuration = i),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(20),
                                      gradient: selected
                                          ? const LinearGradient(
                                              colors: [
                                                Color(0xFFFF5F6D),
                                                Color(0xFFFF2C53),
                                              ],
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                            )
                                          : null,
                                      color: selected
                                          ? null
                                          : Colors.white.withOpacity(0.08),
                                      border: Border.all(
                                        color: Colors.white.withOpacity(0.18),
                                      ),
                                      boxShadow: selected
                                          ? [
                                              BoxShadow(
                                                color: const Color(
                                                  0xFFFF2C53,
                                                ).withOpacity(0.35),
                                                blurRadius: 16,
                                                offset: const Offset(0, 6),
                                              ),
                                            ]
                                          : [],
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.schedule,
                                          color: Colors.white.withOpacity(
                                            selected ? 1.0 : 0.8,
                                          ),
                                          size: 18,
                                        ),
                                        const SizedBox(width: 8),
                                        (() {
                                          final int secs = d['seconds'] as int;
                                          final String key = secs == 15
                                              ? 'dur_15s'
                                              : secs == 30
                                              ? 'dur_30s'
                                              : secs == 60
                                              ? 'dur_1min'
                                              : secs == 300
                                              ? 'dur_5min'
                                              : 'dur_12min';
                                          return LocalizedText(
                                            key,
                                            style: GoogleFonts.poppins(
                                              color: Colors.white,
                                              fontWeight: selected
                                                  ? FontWeight.w700
                                                  : FontWeight.w500,
                                            ),
                                          );
                                        })(),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    // Info label for max duration
                    if (!_isRecording &&
                        (_countdown == null || _countdown == 0))
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.info_outline,
                              color: Colors.white70,
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            const LocalizedText(
                              'max_recording_cap',
                              style: TextStyle(color: Colors.white70),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 12),
                    // Caption and hashtags inputs (only show when we have a video and not recording)
                    if ((_videoPath != null || _videoBytes != null) &&
                        !_isRecording &&
                        (_countdown == null || _countdown == 0))
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Column(
                          children: [
                            TextField(
                              controller: _captionController,
                              maxLines: 2,
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                label: AutoTranslatedText(
                                  'Caption',
                                  style: GoogleFonts.poppins(
                                    color: Colors.white70,
                                  ),
                                ),
                                labelStyle: GoogleFonts.poppins(
                                  color: Colors.white70,
                                ),
                                filled: true,
                                fillColor: const Color(0x22FFFFFF),
                                prefixIcon: const Icon(
                                  Icons.edit,
                                  color: Colors.white70,
                                ),
                                enabledBorder: const OutlineInputBorder(
                                  borderSide: BorderSide(color: Colors.white24),
                                ),
                                focusedBorder: const OutlineInputBorder(
                                  borderSide: BorderSide(color: Colors.white54),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _hashtagController,
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                label: AutoTranslatedText(
                                  'Hashtags (space-separated)',
                                  style: GoogleFonts.poppins(
                                    color: Colors.white70,
                                  ),
                                ),
                                labelStyle: GoogleFonts.poppins(
                                  color: Colors.white70,
                                ),
                                filled: true,
                                fillColor: const Color(0x22FFFFFF),
                                prefixIcon: const Icon(
                                  Icons.tag,
                                  color: Colors.white70,
                                ),
                                enabledBorder: const OutlineInputBorder(
                                  borderSide: BorderSide(color: Colors.white24),
                                ),
                                focusedBorder: const OutlineInputBorder(
                                  borderSide: BorderSide(color: Colors.white54),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 12),
                    // Bottom actions: select, record, publish (premium UI)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: BackdropFilter(
                          filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.15),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.35),
                                  blurRadius: 20,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final bool compact = constraints.maxWidth < 380;
                                final bool ultraCompact =
                                    constraints.maxWidth < 320;
                                final double recordOuter = ultraCompact
                                    ? 72
                                    : (compact ? 80 : 96);
                                final double recordInner = ultraCompact
                                    ? 62
                                    : (compact ? 70 : 80);
                                final double spacing = ultraCompact
                                    ? 10
                                    : (compact ? 12 : 16);
                                return Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    // Upload button
                                    if (!_isRecording &&
                                        (_countdown == null || _countdown == 0))
                                      Flexible(
                                        fit: FlexFit.tight,
                                        child: Align(
                                          alignment: Alignment.centerLeft,
                                          child: FittedBox(
                                            fit: BoxFit.scaleDown,
                                            child: GestureDetector(
                                              onTap: _isImporting
                                                  ? null
                                                  : _selectVideoFromFiles,
                                              child: Container(
                                                padding: ultraCompact
                                                    ? const EdgeInsets.symmetric(
                                                        horizontal: 10,
                                                        vertical: 8,
                                                      )
                                                    : compact
                                                    ? const EdgeInsets.all(10)
                                                    : const EdgeInsets.symmetric(
                                                        horizontal: 14,
                                                        vertical: 10,
                                                      ),
                                                decoration: BoxDecoration(
                                                  color: Colors.white
                                                      .withOpacity(0.12),
                                                  borderRadius:
                                                      BorderRadius.circular(26),
                                                  border: Border.all(
                                                    color: Colors.white
                                                        .withOpacity(0.2),
                                                  ),
                                                ),
                                                child: Column(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Row(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        if (_isImporting)
                                                          SizedBox(
                                                            width: ultraCompact
                                                                ? 14
                                                                : (compact
                                                                      ? 16
                                                                      : 18),
                                                            height: ultraCompact
                                                                ? 14
                                                                : (compact
                                                                      ? 16
                                                                      : 18),
                                                            child: const CircularProgressIndicator(
                                                              strokeWidth: 2.5,
                                                              valueColor:
                                                                  AlwaysStoppedAnimation<
                                                                    Color
                                                                  >(
                                                                    Colors
                                                                        .white70,
                                                                  ),
                                                            ),
                                                          )
                                                        else
                                                          const Icon(
                                                            Icons.video_library,
                                                            color: Colors.white,
                                                          ),
                                                        const SizedBox(
                                                          width: 8,
                                                        ),
                                                        // Use keyed localization for deterministic translations
                                                        _isImporting
                                                            ? LocalizedText(
                                                                'importing',
                                                                style: GoogleFonts.poppins(
                                                                  color: Colors
                                                                      .white,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                ),
                                                              )
                                                            : LocalizedText(
                                                                'upload',
                                                                style: GoogleFonts.poppins(
                                                                  color: Colors
                                                                      .white,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                ),
                                                              ),
                                                      ],
                                                    ),
                                                    if (_isImporting) ...[
                                                      const SizedBox(height: 6),
                                                      SizedBox(
                                                        width: ultraCompact
                                                            ? 60
                                                            : (compact
                                                                  ? 80
                                                                  : 120),
                                                        height: 3,
                                                        child: const LinearProgressIndicator(
                                                          backgroundColor:
                                                              Colors.white12,
                                                          valueColor:
                                                              AlwaysStoppedAnimation<
                                                                Color
                                                              >(Colors.white70),
                                                        ),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    SizedBox(width: spacing),
                                    // Record button (glowing with progress ring)
                                    GestureDetector(
                                      onTap: () {
                                        if (_isStopping) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: LocalizedText(
                                                'stopping_recording',
                                              ),
                                            ),
                                          );
                                          return;
                                        }
                                        if (_isRecording) {
                                          _stopRecording();
                                        } else {
                                          if (_useCountdown) {
                                            _startCountdownThenRecord();
                                          } else {
                                            _startRecording();
                                          }
                                        }
                                      },
                                      child: SizedBox(
                                        width: recordOuter,
                                        height: recordOuter,
                                        child: Stack(
                                          alignment: Alignment.center,
                                          children: [
                                            if (_isRecording)
                                              SizedBox(
                                                width: recordOuter,
                                                height: recordOuter,
                                                child: CircularProgressIndicator(
                                                  value: _recordingProgress > 0
                                                      ? _recordingProgress
                                                      : null,
                                                  strokeWidth: 6,
                                                  valueColor:
                                                      const AlwaysStoppedAnimation<
                                                        Color
                                                      >(Colors.redAccent),
                                                  backgroundColor:
                                                      Colors.white12,
                                                ),
                                              ),
                                            AnimatedBuilder(
                                              animation: _pulseAnimation,
                                              builder: (context, child) {
                                                return Transform.scale(
                                                  scale: _isRecording
                                                      ? 1.0
                                                      : _pulseAnimation.value,
                                                  child: child,
                                                );
                                              },
                                              child: AnimatedContainer(
                                                duration: const Duration(
                                                  milliseconds: 250,
                                                ),
                                                width: recordInner,
                                                height: recordInner,
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  gradient: LinearGradient(
                                                    colors: _isRecording
                                                        ? [
                                                            const Color(
                                                              0xFFFF5F6D,
                                                            ),
                                                            const Color(
                                                              0xFFFF2C53,
                                                            ),
                                                          ]
                                                        : [
                                                            const Color(
                                                              0xFF00C6FF,
                                                            ),
                                                            const Color(
                                                              0xFF0072FF,
                                                            ),
                                                          ],
                                                    begin: Alignment.topLeft,
                                                    end: Alignment.bottomRight,
                                                  ),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color:
                                                          (_isRecording
                                                                  ? Colors
                                                                        .redAccent
                                                                  : Colors
                                                                        .blueAccent)
                                                              .withOpacity(
                                                                0.45,
                                                              ),
                                                      blurRadius: _isRecording
                                                          ? 25
                                                          : 18,
                                                      spreadRadius: _isRecording
                                                          ? 3
                                                          : 1,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                            // Removed stray extra ")" line here
                                            Icon(
                                              _isRecording
                                                  ? Icons.stop
                                                  : Icons.fiber_manual_record,
                                              color: Colors.white,
                                              size: ultraCompact
                                                  ? 28
                                                  : (compact ? 30 : 34),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    SizedBox(width: spacing),
                                    // Publish CTA button
                                    if (!_isRecording &&
                                        (_countdown == null || _countdown == 0))
                                      Flexible(
                                        fit: FlexFit.tight,
                                        child: Align(
                                          alignment: Alignment.centerRight,
                                          child: FittedBox(
                                            fit: BoxFit.scaleDown,
                                            child: GestureDetector(
                                              onTap:
                                                  (_isUploading ||
                                                      (_videoPath == null &&
                                                          _videoBytes == null))
                                                  ? null
                                                  : () async {
                                                      // Proactively stop any active or lingering recorder session on web
                                                      if (_isRecording ||
                                                          (kIsWeb &&
                                                              _webRecorderSession !=
                                                                  null)) {
                                                        ScaffoldMessenger.of(
                                                          context,
                                                        ).showSnackBar(
                                                          SnackBar(
                                                            content: LocalizedText(
                                                              'stopping_recording',
                                                            ),
                                                          ),
                                                        );
                                                        await _stopRecording();
                                                      }

                                                      // Give a moment for stop to finalize and bytes/path to be set (web can take longer due to FileReader)
                                                      const int maxWaitMs =
                                                          8000; // 8s to allow final web recorder flush and FileReader
                                                      int waited = 0;
                                                      while ((_isStopping ||
                                                              _webRecorderSession !=
                                                                  null ||
                                                              (_videoPath ==
                                                                      null &&
                                                                  _videoBytes ==
                                                                      null)) &&
                                                          waited < maxWaitMs) {
                                                        await Future.delayed(
                                                          const Duration(
                                                            milliseconds: 150,
                                                          ),
                                                        );
                                                        waited += 150;
                                                        if (waited % 600 == 0) {
                                                          debugPrint(
                                                            'Publish wait... waited=${waited}ms isStopping=${_isStopping} hasSession=${_webRecorderSession != null} hasPath=${_videoPath != null} hasBytes=${_videoBytes != null} bytesLen=${_videoBytes?.length ?? 0} sessionChunksLen=${_webRecorderSession?.chunks.length ?? -1}',
                                                          );
                                                        }
                                                      }

                                                      // At this point a video exists; proceed
                                                      await _publishPost();
                                                    },
                                              child: Container(
                                                padding: ultraCompact
                                                    ? const EdgeInsets.symmetric(
                                                        horizontal: 12,
                                                        vertical: 8,
                                                      )
                                                    : compact
                                                    ? const EdgeInsets.all(10)
                                                    : const EdgeInsets.symmetric(
                                                        horizontal: 18,
                                                        vertical: 10,
                                                      ),
                                                decoration: BoxDecoration(
                                                  gradient:
                                                      const LinearGradient(
                                                        colors: [
                                                          Color(0xFF8A2BE2),
                                                          Color(0xFFDA70D6),
                                                        ],
                                                        begin:
                                                            Alignment.topLeft,
                                                        end: Alignment
                                                            .bottomRight,
                                                      ),
                                                  borderRadius:
                                                      BorderRadius.circular(26),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: const Color(
                                                        0xFF8A2BE2,
                                                      ).withOpacity(0.4),
                                                      blurRadius: 16,
                                                      offset: const Offset(
                                                        0,
                                                        6,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                child: Column(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Row(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        if (_isUploading)
                                                          SizedBox(
                                                            width: ultraCompact
                                                                ? 14
                                                                : (compact
                                                                      ? 16
                                                                      : 18),
                                                            height: ultraCompact
                                                                ? 14
                                                                : (compact
                                                                      ? 16
                                                                      : 18),
                                                            child: const CircularProgressIndicator(
                                                              strokeWidth: 2.5,
                                                              valueColor:
                                                                  AlwaysStoppedAnimation<
                                                                    Color
                                                                  >(
                                                                    Colors
                                                                        .white70,
                                                                  ),
                                                            ),
                                                          )
                                                        else
                                                          const Icon(
                                                            Icons.send,
                                                            color: Colors.white,
                                                          ),
                                                        const SizedBox(
                                                          width: 8,
                                                        ),
                                                        // Use keyed localization for deterministic translations
                                                        _isUploading
                                                            ? LocalizedText(
                                                                'publishing',
                                                                style: GoogleFonts.poppins(
                                                                  color: Colors
                                                                      .white,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w700,
                                                                ),
                                                              )
                                                            : LocalizedText(
                                                                'publish',
                                                                style: GoogleFonts.poppins(
                                                                  color: Colors
                                                                      .white,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w700,
                                                                ),
                                                              ),
                                                        if (_isUploading &&
                                                            _uploadProgress > 0)
                                                          Padding(
                                                            padding:
                                                                const EdgeInsets.only(
                                                                  left: 8.0,
                                                                ),
                                                            child: Text(
                                                              '${(_uploadProgress * 100).clamp(0, 100).toStringAsFixed(0)}%',
                                                              style:
                                                                  const TextStyle(
                                                                    color: Colors
                                                                        .white70,
                                                                  ),
                                                            ),
                                                          ),
                                                      ],
                                                    ),
                                                    if (_isUploading) ...[
                                                      const SizedBox(height: 6),
                                                      SizedBox(
                                                        width: compact
                                                            ? 100
                                                            : 150,
                                                        height: 3,
                                                        child: LinearProgressIndicator(
                                                          backgroundColor:
                                                              Colors.white12,
                                                          valueColor:
                                                              const AlwaysStoppedAnimation<
                                                                Color
                                                              >(Colors.white),
                                                          value:
                                                              _uploadProgress >
                                                                  0
                                                              ? _uploadProgress
                                                              : null,
                                                        ),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSpeedSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Container(
            margin: const EdgeInsets.all(16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.white.withOpacity(0.12),
                        Colors.white.withOpacity(0.06),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: Border.all(color: Colors.white.withOpacity(0.2)),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 24,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const LocalizedText(
                            'playback_speed',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          IconButton(
                            splashRadius: 20,
                            icon: const Icon(
                              Icons.close,
                              color: Colors.white70,
                            ),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: speeds.map((s) {
                          final selected = _speed == s;
                          return GestureDetector(
                            onTap: () => setState(() {
                              _speed = s;
                              Navigator.pop(ctx);
                            }),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              curve: Curves.easeOut,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(24),
                                gradient: selected
                                    ? const LinearGradient(
                                        colors: [
                                          Color(0xFF00C6FF),
                                          Color(0xFF0072FF),
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      )
                                    : null,
                                color: selected
                                    ? null
                                    : Colors.white.withOpacity(0.12),
                                border: Border.all(
                                  color: selected
                                      ? Colors.white.withOpacity(0.6)
                                      : Colors.white.withOpacity(0.18),
                                ),
                                boxShadow: selected
                                    ? [
                                        BoxShadow(
                                          color: const Color(
                                            0xFF0072FF,
                                          ).withOpacity(0.35),
                                          blurRadius: 18,
                                          offset: const Offset(0, 10),
                                        ),
                                      ]
                                    : [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.25),
                                          blurRadius: 12,
                                          offset: const Offset(0, 8),
                                        ),
                                      ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (selected)
                                    const Icon(
                                      Icons.check_rounded,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                  if (selected) const SizedBox(width: 6),
                                  (() {
                                    final String key = s == 0.5
                                        ? 'speed_0_5x'
                                        : s == 0.75
                                        ? 'speed_0_75x'
                                        : s == 1.0
                                        ? 'speed_1x'
                                        : s == 1.25
                                        ? 'speed_1_25x'
                                        : s == 1.5
                                        ? 'speed_1_5x'
                                        : 'speed_2x';
                                    return LocalizedText(
                                      key,
                                      style: GoogleFonts.poppins(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    );
                                  })(),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 12),
                      SliderTheme(
                        data: SliderTheme.of(ctx).copyWith(
                          trackHeight: 6,
                          activeTrackColor: const Color(0xFF0072FF),
                          inactiveTrackColor: Colors.white.withOpacity(0.2),
                          thumbColor: Colors.white,
                          overlayColor: const Color(
                            0xFF0072FF,
                          ).withOpacity(0.2),
                        ),
                        child: Slider(
                          value: _speed,
                          min: 0.5,
                          max: 2.0,
                          divisions: 15,
                          label: '${_speed.toStringAsFixed(2)}x',
                          onChanged: (v) => setState(
                            () => _speed = double.parse(v.toStringAsFixed(2)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showBeautySheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final beautyIds = ['beauty_soft', 'glam_makeup', 'warm_skin_glow'];
            final beautyOptions = _filters
                .where((f) => beautyIds.contains(f['id']))
                .toList();
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: Container(
                margin: const EdgeInsets.all(16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.white.withOpacity(0.08),
                            Colors.white.withOpacity(0.04),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.16),
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 24,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              AutoTranslatedText(
                                'Beauty',
                                style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              IconButton(
                                splashRadius: 20,
                                icon: const Icon(
                                  Icons.close,
                                  color: Colors.white70,
                                ),
                                onPressed: () => Navigator.pop(ctx),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: List<Widget>.generate(
                              beautyOptions.length,
                              (i) {
                                final f = beautyOptions[i];
                                final idx = _filters.indexOf(f);
                                final selected = _selectedFilter == idx;
                                return GestureDetector(
                                  onTap: () {
                                    setModalState(() {
                                      _selectedFilter = idx;
                                    });
                                    setState(() {});
                                  },
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    curve: Curves.easeOut,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(24),
                                      gradient: selected
                                          ? const LinearGradient(
                                              colors: [
                                                Color(0xFF7F00FF),
                                                Color(0xFFE100FF),
                                              ],
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                            )
                                          : null,
                                      color: selected
                                          ? null
                                          : Colors.white.withOpacity(0.08),
                                      border: Border.all(
                                        color: selected
                                            ? Colors.white.withOpacity(0.6)
                                            : Colors.white.withOpacity(0.15),
                                      ),
                                      boxShadow: selected
                                          ? [
                                              BoxShadow(
                                                color: const Color(
                                                  0xFFE100FF,
                                                ).withOpacity(0.35),
                                                blurRadius: 18,
                                                offset: const Offset(0, 10),
                                              ),
                                            ]
                                          : [
                                              BoxShadow(
                                                color: Colors.black.withOpacity(
                                                  0.20,
                                                ),
                                                blurRadius: 12,
                                                offset: const Offset(0, 8),
                                              ),
                                            ],
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (selected)
                                          const Icon(
                                            Icons.check_rounded,
                                            color: Colors.white,
                                            size: 18,
                                          ),
                                        if (selected) const SizedBox(width: 6),
                                        AutoTranslatedText(
                                          f['name'],
                                          style: GoogleFonts.poppins(
                                            color: Colors.white,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 16),
                          const LocalizedText(
                            'intensity',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          SliderTheme(
                            data: SliderTheme.of(ctx).copyWith(
                              trackHeight: 6,
                              activeTrackColor: const Color(0xFFE100FF),
                              inactiveTrackColor: Colors.white.withOpacity(
                                0.15,
                              ),
                              thumbColor: Colors.white,
                              overlayColor: const Color(
                                0xFFE100FF,
                              ).withOpacity(0.15),
                            ),
                            child: Slider(
                              value: _filterIntensity,
                              min: 0.0,
                              max: 1.0,
                              divisions: 10,
                              label: '${(_filterIntensity * 100).round()}%',
                              onChanged: (v) {
                                setModalState(() {
                                  _filterIntensity = v;
                                });
                                setState(() {});
                              },
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              GestureDetector(
                                onTap: () {
                                  setModalState(() {
                                    // Reset both filter and effects to defaults
                                    _selectedFilter = 0;
                                    _filterIntensity = 0.5;
                                    _selectedEffectId = null;
                                    _selectedEffectIntensity = 0.5;
                                    _selectedEffectsCategory = 'Beauty';
                                  });
                                  setState(() {});
                                  Navigator.pop(ctx);
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    color: Colors.white.withOpacity(0.08),
                                    border: Border.all(
                                      color: Colors.white.withOpacity(0.15),
                                    ),
                                  ),
                                  child: AutoTranslatedText(
                                    'Clear',
                                    style: GoogleFonts.poppins(
                                      color: Colors.white70,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              GestureDetector(
                                onTap: () => Navigator.pop(ctx),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    gradient: const LinearGradient(
                                      colors: [
                                        Color(0xFF7F00FF),
                                        Color(0xFFE100FF),
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(
                                          0xFF7F00FF,
                                        ).withOpacity(0.35),
                                        blurRadius: 16,
                                        offset: const Offset(0, 10),
                                      ),
                                    ],
                                  ),
                                  child: LocalizedText(
                                    'apply',
                                    style: GoogleFonts.poppins(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showTimerSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Container(
            margin: const EdgeInsets.all(16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.white.withOpacity(0.12),
                        Colors.white.withOpacity(0.06),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: Border.all(color: Colors.white.withOpacity(0.2)),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 24,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          LocalizedText(
                            'timer',
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          IconButton(
                            splashRadius: 20,
                            icon: const Icon(
                              Icons.close,
                              color: Colors.white70,
                            ),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: List<Widget>.generate(
                          _videoDurations.length,
                          (i) {
                            final d = _videoDurations[i];
                            final selected = _selectedDuration == i;
                            return GestureDetector(
                              onTap: () => setState(() {
                                _selectedDuration = i;
                              }),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                curve: Curves.easeOut,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(24),
                                  gradient: selected
                                      ? const LinearGradient(
                                          colors: [
                                            Color(0xFFFF8C00),
                                            Color(0xFFFF3D00),
                                          ],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        )
                                      : null,
                                  color: selected
                                      ? null
                                      : Colors.white.withOpacity(0.12),
                                  border: Border.all(
                                    color: selected
                                        ? Colors.white.withOpacity(0.6)
                                        : Colors.white.withOpacity(0.18),
                                  ),
                                  boxShadow: selected
                                      ? [
                                          BoxShadow(
                                            color: const Color(
                                              0xFFFF3D00,
                                            ).withOpacity(0.35),
                                            blurRadius: 18,
                                            offset: const Offset(0, 10),
                                          ),
                                        ]
                                      : [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(
                                              0.25,
                                            ),
                                            blurRadius: 12,
                                            offset: const Offset(0, 8),
                                          ),
                                        ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (selected)
                                      const Icon(
                                        Icons.check_rounded,
                                        color: Colors.white,
                                        size: 18,
                                      ),
                                    if (selected) const SizedBox(width: 6),
                                    (() {
                                      final int secs = d['seconds'] as int;
                                      final String key = secs == 15
                                          ? 'dur_15s'
                                          : secs == 30
                                          ? 'dur_30s'
                                          : secs == 60
                                          ? 'dur_1min'
                                          : secs == 300
                                          ? 'dur_5min'
                                          : 'dur_12min';
                                      return LocalizedText(
                                        key,
                                        style: GoogleFonts.poppins(
                                          color: Colors.white,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      );
                                    })(),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          (() {
                            final secs =
                                _videoDurations[_selectedDuration]['seconds']
                                    as int;
                            final key = secs == 15
                                ? 'dur_15s'
                                : secs == 30
                                ? 'dur_30s'
                                : secs == 60
                                ? 'dur_1min'
                                : secs == 300
                                ? 'dur_5min'
                                : 'dur_12min';
                            return Expanded(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  LocalizedText(
                                    'selected',
                                    style: GoogleFonts.poppins(
                                      color: Colors.white70,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    softWrap: false,
                                  ),
                                  Text(
                                    ': ',
                                    style: GoogleFonts.poppins(
                                      color: Colors.white70,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  Expanded(
                                    child: LocalizedText(
                                      key,
                                      style: GoogleFonts.poppins(
                                        color: Colors.white70,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      softWrap: false,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          })(),
                          const SizedBox(width: 12),
                          Flexible(
                            child: GestureDetector(
                              onTap: () {
                                Navigator.pop(ctx);
                                _startCountdownThenRecord();
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFFFF8C00),
                                      Color(0xFFFF3D00),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(
                                        0xFFFF3D00,
                                      ).withOpacity(0.35),
                                      blurRadius: 16,
                                      offset: const Offset(0, 10),
                                    ),
                                  ],
                                ),
                                child: const LocalizedText(
                                  'start_3s_countdown',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  softWrap: false,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _startCountdownThenRecord() {
    setState(() {
      _countdown = 3;
    });
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _countdown = (_countdown ?? 0) - 1;
      });
      if ((_countdown ?? 0) <= 0) {
        t.cancel();
        setState(() {
          _countdown = null;
        });
        _startRecording();
      }
    });
  }

  void _showSettingsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF121212),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LocalizedText(
                'settings',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                value: _useCountdown,
                onChanged: (v) => setState(() {
                  _useCountdown = v;
                }),
                activeColor: Colors.blueAccent,
                title: const LocalizedText(
                  'use_3s_countdown_on_record',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
              SwitchListTile(
                value: _autoStop,
                onChanged: (v) => setState(() {
                  _autoStop = v;
                }),
                activeColor: Colors.blueAccent,
                title: const LocalizedText(
                  'auto_stop_at_selected_duration',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const LocalizedText('close'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showEffectsSheet() {
    // One-time prefill guard for this modal session
    bool initializedFromApplied = false;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            // Build ordered category list and ensure presence in catalog
            final desiredOrder = [
              'Beauty',
              'Portrait',
              'Face',
              'Color',
              'Body',
            ];
            final present = _effectsLab
                .map((e) => e['category'] as String)
                .toSet();
            final categories = desiredOrder
                .where((c) => present.contains(c))
                .toList();
            // No auto-prefill; user must select an effect explicitly
            final options = _effectsLab
                .where((e) => e['category'] == _selectedEffectsCategory)
                .toList();
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: Container(
                margin: const EdgeInsets.all(16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.white.withOpacity(0.12),
                            Colors.white.withOpacity(0.06),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.2),
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 24,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const LocalizedText(
                                'effects_lab',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              IconButton(
                                splashRadius: 20,
                                icon: const Icon(
                                  Icons.close,
                                  color: Colors.white70,
                                ),
                                onPressed: () => Navigator.pop(ctx),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // Effects category navigation
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: List<Widget>.generate(categories.length, (
                                i,
                              ) {
                                final cat = categories[i];
                                final selected =
                                    _selectedEffectsCategory == cat;
                                return Padding(
                                  padding: const EdgeInsets.only(right: 10),
                                  child: GestureDetector(
                                    onTap: () {
                                      setModalState(() {
                                        _selectedEffectsCategory = cat;
                                        // Do NOT auto-select; require user choice
                                        _selectedEffectId = null;
                                        _selectedEffectIntensity = 0.5;
                                      });
                                    },
                                    child: AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 200,
                                      ),
                                      curve: Curves.easeOut,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 10,
                                      ),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(16),
                                        color: selected
                                            ? null
                                            : Colors.white.withOpacity(0.08),
                                        gradient: selected
                                            ? const LinearGradient(
                                                colors: [
                                                  Color(0xFF0072FF),
                                                  Color(0xFFE100FF),
                                                ],
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                              )
                                            : null,
                                        border: Border.all(
                                          color: selected
                                              ? Colors.white.withOpacity(0.6)
                                              : Colors.white.withOpacity(0.15),
                                        ),
                                        boxShadow: selected
                                            ? [
                                                BoxShadow(
                                                  color: const Color(
                                                    0xFF0072FF,
                                                  ).withOpacity(0.35),
                                                  blurRadius: 18,
                                                  offset: const Offset(0, 10),
                                                ),
                                              ]
                                            : [
                                                BoxShadow(
                                                  color: Colors.black
                                                      .withOpacity(0.20),
                                                  blurRadius: 12,
                                                  offset: const Offset(0, 8),
                                                ),
                                              ],
                                      ),
                                      child: LocalizedText(
                                        {
                                              'Beauty': 'effects_cat_beauty',
                                              'Portrait':
                                                  'effects_cat_portrait',
                                              'Face': 'effects_cat_face',
                                              'Color': 'effects_cat_color',
                                              'Body': 'effects_cat_body',
                                            }[cat] ??
                                            'effects_cat_beauty',
                                        style: GoogleFonts.poppins(
                                          color: Colors.white,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            key: ValueKey(_selectedEffectsCategory),
                            spacing: 10,
                            runSpacing: 10,
                            children: List<Widget>.generate(options.length, (
                              i,
                            ) {
                              final e = options[i];
                              final selected = _selectedEffectId == e['id'];
                              final applied = _appliedEffects.containsKey(
                                e['id'],
                              );
                              final Color bg =
                                  (e['color'] as Color?) ??
                                  Colors.white.withOpacity(0.06);
                              return GestureDetector(
                                onTap: () {
                                  setModalState(() {
                                    _selectedEffectId = e['id'];
                                    if (_appliedEffects.containsKey(e['id'])) {
                                      _selectedEffectIntensity =
                                          _appliedEffects[e['id']]!.clamp(
                                            0.0,
                                            1.0,
                                          );
                                    } else {
                                      _selectedEffectIntensity = 0.5;
                                    }
                                  });
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  curve: Curves.easeOut,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    color: bg,
                                    gradient: selected
                                        ? const LinearGradient(
                                            colors: [
                                              Color(0xFF7F00FF),
                                              Color(0xFFE100FF),
                                            ],
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                          )
                                        : null,
                                    border: Border.all(
                                      color: selected
                                          ? Colors.white.withOpacity(0.6)
                                          : Colors.white.withOpacity(0.15),
                                    ),
                                    boxShadow: selected
                                        ? [
                                            BoxShadow(
                                              color: const Color(
                                                0xFFE100FF,
                                              ).withOpacity(0.35),
                                              blurRadius: 18,
                                              offset: const Offset(0, 10),
                                            ),
                                          ]
                                        : [
                                            BoxShadow(
                                              color: Colors.black.withOpacity(
                                                0.20,
                                              ),
                                              blurRadius: 12,
                                              offset: const Offset(0, 8),
                                            ),
                                          ],
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (selected || applied)
                                        const Icon(
                                          Icons.check_rounded,
                                          color: Colors.white,
                                          size: 18,
                                        ),
                                      if (selected || applied)
                                        const SizedBox(width: 6),
                                      LocalizedText(
                                        'effect_${e['id']}',
                                        style: GoogleFonts.poppins(
                                          color: Colors.white,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }),
                          ),
                          const SizedBox(height: 16),
                          LocalizedText(
                            'intensity',
                            style: GoogleFonts.poppins(
                              color: Colors.white70,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          SliderTheme(
                            data: SliderTheme.of(ctx).copyWith(
                              trackHeight: 6,
                              activeTrackColor: const Color(0xFFE100FF),
                              inactiveTrackColor: Colors.white.withOpacity(
                                0.15,
                              ),
                              thumbColor: Colors.white,
                              overlayColor: const Color(
                                0xFFE100FF,
                              ).withOpacity(0.15),
                            ),
                            child: Slider(
                              value: _selectedEffectIntensity,
                              min: 0.0,
                              max: 1.0,
                              divisions: 10,
                              label:
                                  '${(_selectedEffectIntensity * 100).round()}%',
                              onChanged: (v) {
                                setModalState(() {
                                  _selectedEffectIntensity = v;
                                });
                              },
                            ),
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: GestureDetector(
                              onTap: () {
                                // Persist the chosen effect and intensity without removing prior ones
                                if (_selectedEffectId != null) {
                                  setState(() {
                                    _appliedEffects[_selectedEffectId!] =
                                        _selectedEffectIntensity.clamp(
                                          0.0,
                                          1.0,
                                        );
                                  });
                                }
                                // Show a brief toast/notification while keeping the lab open
                                try {
                                  final messenger = ScaffoldMessenger.of(
                                    context,
                                  );
                                  messenger.hideCurrentSnackBar();
                                  messenger.showSnackBar(
                                    SnackBar(
                                      behavior: SnackBarBehavior.floating,
                                      duration: const Duration(
                                        milliseconds: 1200,
                                      ),
                                      backgroundColor: Colors.black87,
                                      content: const LocalizedText(
                                        'effect_applied',
                                        style: TextStyle(color: Colors.white),
                                      ),
                                    ),
                                  );
                                } catch (_) {}
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFF7F00FF),
                                      Color(0xFFE100FF),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(
                                        0xFF7F00FF,
                                      ).withOpacity(0.35),
                                      blurRadius: 16,
                                      offset: const Offset(0, 10),
                                    ),
                                  ],
                                ),
                                child: const LocalizedText(
                                  'apply',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  softWrap: false,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
