import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:uuid/uuid.dart';
import 'package:path/path.dart' as path;
import 'package:photo_manager/photo_manager.dart';
import 'video_filter_service.dart';
import 'storage_service.dart';
import 'posts_service.dart';
import 'auth_service.dart';
import 'analytics_service.dart';

enum UploadState { idle, compressing, uploading, success, error }

class UploadStatus {
  final String id;
  final UploadState state;
  final double progress; // 0.0 to 1.0
  final String message;
  final String? errorMessage;

  UploadStatus({
    required this.id,
    required this.state,
    this.progress = 0.0,
    this.message = '',
    this.errorMessage,
  });
}

class UploadService {
  static final UploadService _instance = UploadService._internal();
  factory UploadService() => _instance;
  UploadService._internal();

  final _statusController = StreamController<UploadStatus>.broadcast();
  Stream<UploadStatus> get statusStream => _statusController.stream;

  UploadStatus _currentStatus = UploadStatus(id: '', state: UploadState.idle);

  UploadStatus get currentStatus => _currentStatus;

  bool get isUploading =>
      _currentStatus.state == UploadState.compressing ||
      _currentStatus.state == UploadState.uploading;

  Future<void> startVideoUpload({
    required dynamic videoSource, // File (mobile) or Uint8List (web)
    required String? videoPath, // Mobile only
    required String? videoFileName, // Web only
    required String caption,
    required List<String> hashtags,
    required Map<String, dynamic> metadata, // duration, width, height, etc.
    required String userId,
    String? parentPostId,
    bool isPrivate = false,
    bool allowComments = true,
    bool allowDuet = true,
    bool allowStitch = true,
    bool saveToGallery = false,
  }) async {
    if (isUploading) {
      throw Exception('Another upload is already in progress');
    }

    final uploadId = const Uuid().v4();
    _updateStatus(
      UploadStatus(
        id: uploadId,
        state: UploadState.compressing,
        progress: 0.0,
        message: 'Preparing video...',
      ),
    );

    // Start the upload process in the background (fire and forget)
    _processUpload(
      uploadId: uploadId,
      videoSource: videoSource,
      videoPath: videoPath,
      videoFileName: videoFileName,
      caption: caption,
      hashtags: hashtags,
      metadata: metadata,
      userId: userId,
      parentPostId: parentPostId,
      isPrivate: isPrivate,
      allowComments: allowComments,
      allowDuet: allowDuet,
      allowStitch: allowStitch,
      saveToGallery: saveToGallery,
    );
  }

  Future<void> _processUpload({
    required String uploadId,
    required dynamic videoSource,
    required String? videoPath,
    required String? videoFileName,
    required String caption,
    required List<String> hashtags,
    required Map<String, dynamic> metadata,
    required String userId,
    String? parentPostId,
    required bool isPrivate,
    required bool allowComments,
    required bool allowDuet,
    required bool allowStitch,
    required bool saveToGallery,
  }) async {
    try {
      // 1. Compression & Effects
      dynamic compressedVideo = videoSource;
      String? compressedPath = videoPath;
      Map<String, dynamic>? preUploadedUrls;

      if (kIsWeb) {
        if (videoSource is! Uint8List) {
          throw Exception('Web upload requires Uint8List video source');
        }
        compressedVideo = videoSource;

        // Check for effects
        final bool hasEffects =
            (metadata['effectsLab'] != null &&
                (metadata['effectsLab'] as List).isNotEmpty) ||
            metadata['filter_id'] != null;

        if (hasEffects) {
          // Check if file is too large for client-side processing (>50MB)
          // or if we want to force server-side for stability on large files
          final int size = (compressedVideo as Uint8List).length;
          if (size > 50 * 1024 * 1024) {
            _updateStatus(
              UploadStatus(
                id: uploadId,
                state: UploadState.compressing,
                progress: 0.5,
                message: 'Large video: Processing on server...',
              ),
            );

            // Upload original/compressed first
            final storage = StorageService();
            final originalUrls = await storage.uploadVideo(
              videoFile: null,
              videoBytes: compressedVideo,
              userId: userId,
              videoFileName:
                  videoFileName ??
                  'video_${DateTime.now().millisecondsSinceEpoch}.mp4',
            );

            // Identify the filter to apply (matching CreatePostScreen logic: apply last transform)
            // Construct transforms list to find the last one
            final List<Map<String, dynamic>> transforms = [];
            if (metadata['effectsLab'] != null) {
              for (final e in metadata['effectsLab']) {
                transforms.add({'id': e['id'], 'intensity': e['intensity']});
              }
            }
            if (metadata['filter_id'] != null) {
              transforms.add({
                'id': metadata['filter_id'],
                'intensity': metadata['filter_intensity'] ?? 0.8,
              });
            }

            if (transforms.isNotEmpty) {
              final last = transforms.last;
              final jobId = await VideoFilterService().startServerProcessingJob(
                sourceUrl: originalUrls['videoUrl'] as String,
                filterId: last['id'] as String,
                intensity: (last['intensity'] as num).toDouble(),
                options: {'thumbnail': true, 'speed': metadata['speed'] ?? 1.0},
              );

              // Poll for completion
              bool processingComplete = false;
              int pollAttempts = 0;
              // Poll for up to 5 minutes (300s / 2s = 150 attempts)
              while (!processingComplete && pollAttempts < 150) {
                await Future.delayed(const Duration(seconds: 2));
                final status = await VideoFilterService()
                    .getServerProcessingJobStatus(jobId);
                final st = status['status'] as String? ?? 'pending';
                final prog = (status['progress'] ?? 0.0) as num;

                _updateStatus(
                  UploadStatus(
                    id: uploadId,
                    state: UploadState.compressing,
                    progress: 0.5 + (prog.toDouble() * 0.4),
                    message: 'Server processing: ${(prog * 100).toInt()}%',
                  ),
                );

                if (st == 'completed') {
                  preUploadedUrls = {
                    'videoUrl': status['resultUrl'],
                    'thumbnailUrl':
                        status['thumbnailUrl'] ?? originalUrls['thumbnailUrl'],
                    'gifUrl':
                        originalUrls['gifUrl'], // Preserve if original had it
                  };
                  processingComplete = true;
                } else if (st == 'failed') {
                  debugPrint('Server processing failed: ${status['error']}');
                  // Fallback to original
                  preUploadedUrls = originalUrls;
                  processingComplete = true;
                }
                pollAttempts++;
              }

              if (!processingComplete) {
                // Timed out, use original
                preUploadedUrls = originalUrls;
              }
            } else {
              // No actual transforms found despite check? Use original.
              preUploadedUrls = originalUrls;
            }
          } else {
            // Client-side processing
            compressedVideo = await _applyFiltersWeb(compressedVideo, metadata);
          }
        }
      } else {
        if (videoPath == null) {
          throw Exception('Mobile upload requires video path');
        }

        compressedPath = videoPath;

        // Mobile: Apply Effects
        if (metadata['effectsLab'] != null || metadata['filter_id'] != null) {
          compressedPath = await _applyFiltersMobile(compressedPath!, metadata);
        }

        compressedVideo = File(compressedPath!);
      }

      _updateStatus(
        UploadStatus(
          id: uploadId,
          state: UploadState.uploading,
          progress: 0.0,
          message: 'Uploading video...',
        ),
      );

      // 3. Upload to Storage (if not already done)
      final storage = StorageService();
      Map<String, dynamic> urls;

      if (preUploadedUrls != null) {
        urls = preUploadedUrls;
        _stopProgressTimer();
        _updateStatus(
          UploadStatus(
            id: uploadId,
            state: UploadState.uploading,
            progress: 1.0,
            message: 'Upload complete!',
          ),
        );
      } else {
        if (kIsWeb) {
          // Web Upload
          _startFakeProgress(UploadState.uploading);

          urls = await storage.uploadVideo(
            videoFile: null,
            videoBytes: compressedVideo as Uint8List,
            userId: userId,
            thumbnailBytes: null,
            videoFileName: videoFileName,
          );
        } else {
          // Mobile Upload
          _startFakeProgress(UploadState.uploading);

          urls = await storage.uploadVideo(
            videoFile: File(compressedPath!),
            userId: userId,
            thumbnailBytes: null,
          );
        }
        _stopProgressTimer();
      }

      // 4. Create Post Record
      _updateStatus(
        UploadStatus(
          id: uploadId,
          state: UploadState.uploading,
          progress: 0.9,
          message: 'Finalizing...',
        ),
      );

      await PostsService().createPost(
        type: 'video',
        caption: caption,
        hashtags: hashtags,
        mediaUrl: urls['videoUrl'],
        thumbnailUrl: urls['thumbnailUrl'],
        effects: {
          ...metadata,
          'filter_id': metadata['filterId'],
          'filter_intensity': metadata['filterIntensity'],
        },
        parentPostId: parentPostId,
        isPublic: !isPrivate,
        allowComments: allowComments,
        allowDuets: allowDuet,
      );

      _updateStatus(
        UploadStatus(
          id: uploadId,
          state: UploadState.success,
          progress: 1.0,
          message: 'Upload complete!',
        ),
      );

      // 5. Save to Gallery
      if (saveToGallery && !kIsWeb && compressedPath != null) {
        try {
          _updateStatus(
            UploadStatus(
              id: uploadId,
              state: UploadState.success,
              progress: 1.0,
              message: 'Saving to gallery...',
            ),
          );

          await _saveToGallery(compressedPath);

          _updateStatus(
            UploadStatus(
              id: uploadId,
              state: UploadState.success,
              progress: 1.0,
              message: 'Upload complete & saved!',
            ),
          );
        } catch (e) {
          debugPrint('Save to gallery failed: $e');
        }
      }

      // Reset after delay
      Future.delayed(const Duration(seconds: 3), () {
        if (_currentStatus.id == uploadId) {
          _updateStatus(UploadStatus(id: '', state: UploadState.idle));
        }
      });
    } catch (e) {
      _stopProgressTimer();
      _updateStatus(
        UploadStatus(
          id: uploadId,
          state: UploadState.error,
          message: 'Upload failed',
          errorMessage: e.toString(),
        ),
      );
      debugPrint('UploadService Error: $e');
    }
  }

  void _updateStatus(UploadStatus status) {
    _currentStatus = status;
    _statusController.add(status);
  }

  Timer? _progressTimer;

  void _stopProgressTimer() {
    _progressTimer?.cancel();
    _progressTimer = null;
  }

  void _startFakeProgress(UploadState state) {
    _stopProgressTimer();
    double current = 0.0;
    _progressTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      current += 0.05;
      if (current > 0.9) current = 0.9;
      _updateStatus(
        UploadStatus(
          id: _currentStatus.id,
          state: state,
          progress: current,
          message: _currentStatus.message,
        ),
      );
    });
  }

  void _startProgressPolling(VideoFilterService svc) {
    _stopProgressTimer();
    _progressTimer = Timer.periodic(const Duration(milliseconds: 250), (timer) {
      final p = svc.getProgressInstance(); // returns double 0.0-1.0
      _updateStatus(
        UploadStatus(
          id: _currentStatus.id,
          state: UploadState.compressing,
          progress: p,
          message: 'Compressing video...',
        ),
      );
    });
  }

  void _stopProgressPolling() {
    _stopProgressTimer();
  }

  Future<Uint8List> _applyFiltersWeb(
    Uint8List bytes,
    Map<String, dynamic> metadata,
  ) async {
    _updateStatus(
      UploadStatus(
        id: _currentStatus.id,
        state: UploadState.compressing,
        progress: 0.5, // Start of effects
        message: 'Applying effects...',
      ),
    );

    Uint8List currentBytes = bytes;

    final svc = VideoFilterService();
    String currentDataUri = 'data:video/mp4;base64,${base64Encode(bytes)}';

    // Construct transforms list from metadata
    final List<Map<String, dynamic>> transforms = [];

    if (metadata['effectsLab'] != null) {
      final List<dynamic> effects = metadata['effectsLab'];
      for (final e in effects) {
        transforms.add({'id': e['id'], 'intensity': e['intensity']});
      }
    }

    if (metadata['filter_id'] != null) {
      transforms.add({
        'id': metadata['filter_id'],
        'intensity': metadata['filter_intensity'] ?? 0.8,
      });
    }

    if (transforms.isEmpty) return bytes;

    try {
      for (int i = 0; i < transforms.length; i++) {
        _updateStatus(
          UploadStatus(
            id: _currentStatus.id,
            state: UploadState.compressing,
            progress: 0.5 + (0.4 * (i / transforms.length)),
            message: 'Applying effect ${i + 1}/${transforms.length}...',
          ),
        );

        final step = transforms[i];
        final bool isLast = i == transforms.length - 1;
        // Apply speed only on last step if needed
        final speed = isLast ? (metadata['speed'] ?? 1.0) : 1.0;
        final intensity = (step['intensity'] as num).toDouble();
        final filterId = step['id'] as String;

        // Build filter graph for Web (ffmpeg.wasm)
        final graph = _buildFilterGraph(filterId, intensity);

        // If graph is 'null' or empty, skip
        if (graph == 'null' || graph.isEmpty) continue;

        // Use byte-based applyFilter which invokes equalApplyFilterFFmpegWasm
        final nextBytes = await VideoFilterService.applyFilter(
          input: currentBytes,
          filterGraph: graph,
          speed: speed.toDouble(),
        );

        if (nextBytes.isNotEmpty) {
          currentBytes = nextBytes;
        }
      }
    } catch (e) {
      debugPrint('Web filter application failed: $e');
    }

    return currentBytes;
  }

  String _buildFilterGraph(String filterId, double t) {
    double lerp(double a, double b, double t) => a + (b - a) * t;

    switch (filterId) {
      case 'lut_teal_orange':
        return 'colorbalance=bs=${lerp(0.0, -0.25, t)}:rm=${lerp(0.0, 0.30, t)},eq=contrast=${lerp(1.0, 1.20, t)}:saturation=${lerp(1.0, 1.35, t)}';
      case 'lut_cinematic_blue':
        return 'colorbalance=bs=${lerp(0.0, 0.22, t)}:gs=${lerp(0.0, 0.12, t)},eq=contrast=${lerp(1.0, 1.18, t)}:brightness=${lerp(0.0, -0.06, t)}:saturation=${lerp(1.0, 1.18, t)}';
      case 'lut_mono_film':
        return 'hue=s=0,eq=contrast=${lerp(1.0, 1.20, t)}:brightness=${lerp(0.0, -0.08, t)}';
      case 'teal_orange':
        return 'colorbalance=bs=${lerp(0.0, -0.25, t)}:rm=${lerp(0.0, 0.30, t)},eq=contrast=${lerp(1.0, 1.20, t)}:saturation=${lerp(1.0, 1.35, t)}';
      case 'cinematic_blue':
        return 'colorbalance=bs=${lerp(0.0, 0.22, t)}:gs=${lerp(0.0, 0.12, t)},eq=contrast=${lerp(1.0, 1.18, t)}:brightness=${lerp(0.0, -0.06, t)}:saturation=${lerp(1.0, 1.18, t)}';
      case 'warm_skin_glow':
        return 'colorbalance=rm=${lerp(0.0, 0.28, t)}:gm=${lerp(0.0, 0.14, t)},eq=gamma=${lerp(1.0, 0.85, t)}:saturation=${lerp(1.0, 1.30, t)}';
      case 'beauty_soft':
        return 'bilateral=sigmaS=${lerp(0.0, 4.0, t)}:sigmaR=${lerp(0.0, 0.35, t)},eq=saturation=${lerp(1.0, 1.25, t)}:gamma=${lerp(1.0, 0.90, t)},curves=preset=lighter';
      case 'glam_makeup':
        return 'unsharp=luma_msize_x=5:luma_msize_y=5:luma_amount=${lerp(0.0, 3.0, t)},eq=saturation=${lerp(1.0, 1.35, t)}:contrast=${lerp(1.0, 1.20, t)},colorbalance=rm=${lerp(0.0, 0.20, t)}:gm=${lerp(0.0, 0.05, t)}';
      case 'lip_tint':
        return 'colorbalance=rm=${lerp(0.0, 0.40, t)}:gm=${lerp(0.0, 0.08, t)},eq=saturation=${lerp(1.0, 1.20, t)}';
      case 'eye_brighten':
        return 'eq=brightness=${lerp(0.0, 0.14, t)}:saturation=${lerp(1.0, 1.12, t)}';
      case 'relight_portrait':
        return 'eq=gamma=${lerp(1.0, 0.85, t)}:brightness=${lerp(0.0, 0.12, t)}';
      case 'vintage_fade':
        return 'eq=contrast=${lerp(1.0, 0.85, t)}:saturation=${lerp(1.0, 0.65, t)},curves=preset=vintage';
      case 'pastel_matte':
        return 'eq=contrast=${lerp(1.0, 0.78, t)}:saturation=${lerp(1.0, 0.70, t)},curves=preset=lighter';
      case 'cyberpunk_neon':
        return 'eq=saturation=${lerp(1.0, 1.60, t)}:contrast=${lerp(1.0, 1.20, t)},hue=h=${lerp(0.0, 25.0, t)}';
      case 'night_boost':
        return 'eq=brightness=${lerp(0.0, 0.12, t)}:contrast=${lerp(1.0, 1.22, t)}:saturation=${lerp(1.0, 1.18, t)}';
      case 'mono_film':
        return 'hue=s=0,eq=contrast=${lerp(1.0, 1.20, t)}:brightness=${lerp(0.0, -0.08, t)}';
      case 'clarity_pop':
        return 'unsharp=luma_msize_x=7:luma_msize_y=7:luma_amount=${lerp(0.0, 4.0, t)},eq=saturation=${lerp(1.0, 1.25, t)}:contrast=${lerp(1.0, 1.18, t)}';
      case 'curves_enhance':
        return 'curves=preset=lighter,eq=saturation=${lerp(1.0, 1.25, t)}';
      case 'vhs_retro':
        return 'noise=alls=${lerp(0.0, 25.0, t)}:allf=t+u,curves=preset=vintage,eq=saturation=${lerp(1.0, 0.65, t)}';
      case 'anime_ink':
        return 'unsharp=luma_msize_x=7:luma_msize_y=7:luma_amount=${lerp(0.0, 4.0, t)},eq=saturation=${lerp(1.0, 1.6, t)}';
      case 'slow_shutter':
        return 'tmix=frames=${lerp(1.0, 12.0, t).round()}';
      case 'vignette_glow':
        return 'gblur=sigma=${lerp(0.0, 14.0, t)},vignette=angle=${lerp(0.0, 0.6, t)}:x0=0.5:y0=0.5,eq=saturation=${lerp(1.0, 1.18, t)}';
      case 'portrait_bokeh':
        return 'gblur=sigma=${lerp(0.0, 12.0, t)},vignette=angle=${lerp(0.0, 0.5, t)}:x0=0.5:y0=0.5';
      case 'background_replace':
        return 'curves=preset=lighter,eq=brightness=${lerp(0.0, 0.12, t)}';
      case 'face_landmarks':
        return 'edgedetect=high=${lerp(0.2, 0.8, t)}:low=${lerp(0.02, 0.12, t)}';
      case 'hip_bum_enhancer':
        // Fallback for web: simple horizontal stretch in lower half
        final sx = (1.0 + (0.12 * t)).toStringAsFixed(3);
        return 'split=2[base][tmp];[tmp]crop=iw:ih*0.5:0:ih*0.5,scale=trunc(iw*${sx}/2)*2:ih,boxblur=2:2[low];[base][low]overlay=x=(W-w)/2:y=H/2';
      case 'original':
      default:
        return 'null';
    }
  }

  Future<String> _applyFiltersMobile(
    String path,
    Map<String, dynamic> metadata,
  ) async {
    _updateStatus(
      UploadStatus(
        id: _currentStatus.id,
        state: UploadState.compressing,
        progress: 0.5,
        message: 'Applying effects...',
      ),
    );

    final svc = VideoFilterService();
    String currentPath = path;

    // Construct transforms list
    final List<Map<String, dynamic>> transforms = [];

    if (metadata['effectsLab'] != null) {
      final List<dynamic> effects = metadata['effectsLab'];
      for (final e in effects) {
        transforms.add({'id': e['id'], 'intensity': e['intensity']});
      }
    }

    if (metadata['filter_id'] != null) {
      transforms.add({
        'id': metadata['filter_id'],
        'intensity': metadata['filter_intensity'] ?? 0.8,
      });
    }

    if (transforms.isEmpty) return path;

    _startProgressPolling(svc);

    try {
      for (int i = 0; i < transforms.length; i++) {
        _updateStatus(
          UploadStatus(
            id: _currentStatus.id,
            state: UploadState.compressing,
            progress: 0.5 + (0.4 * (i / transforms.length)),
            message: 'Applying effect ${i + 1}/${transforms.length}...',
          ),
        );

        final step = transforms[i];
        final bool isLast = i == transforms.length - 1;
        final options = isLast ? {'speed': metadata['speed'] ?? 1.0} : null;

        final nextPath = await svc.applyFilterPath(
          currentPath,
          step['id'] as String,
          (step['intensity'] as num).toDouble(),
          options: options,
        );

        if (nextPath.isNotEmpty && File(nextPath).existsSync()) {
          currentPath = nextPath;
        }
      }
    } catch (e) {
      debugPrint('Mobile filter application failed: $e');
    } finally {
      _stopProgressPolling();
    }

    return currentPath;
  }

  Future<void> _saveToGallery(String videoPath) async {
    // Attempt to append an outro segment before saving
    Uint8List? outroBytes;
    try {
      ByteData bd;
      try {
        bd = await rootBundle.load('assets/audio/outro_you.m4a');
      } catch (_) {
        bd = await rootBundle.load('assets/audio/outro_you.mp3');
      }
      outroBytes = bd.buffer.asUint8List();
    } catch (_) {}

    String pathToSave = videoPath;
    try {
      final processed = await VideoFilterService().appendOutroToVideoPath(
        videoPath,
        outroAudioBytes: outroBytes,
        outroSeconds: 10,
      );
      if (processed != null && File(processed).existsSync()) {
        pathToSave = processed;
      }
    } catch (_) {}

    // Ensure Android gallery receives MP4 to avoid platform NPEs with WEBM/MKV
    try {
      final lower = pathToSave.toLowerCase();
      if (!(lower.endsWith('.mp4') ||
          lower.endsWith('.mov') ||
          lower.endsWith('.3gp'))) {
        final converted = await VideoFilterService().compressVideoPath(
          pathToSave,
          options: {'scaleHeight': 720, 'crf': 23},
        );
        if (converted != pathToSave && File(converted).existsSync()) {
          pathToSave = converted;
        }
      }
    } catch (_) {}

    // Save to gallery
    AssetEntity? saved = await PhotoManager.editor.saveVideo(
      File(pathToSave),
      title: path.basename(pathToSave),
      relativePath: 'Movies/Equal',
    );
    if (saved == null) {
      // Fallback attempts
      try {
        saved = await PhotoManager.editor.saveVideo(
          File(pathToSave),
          title: path.basename(pathToSave),
          relativePath: 'Movies',
        );
      } catch (_) {}
      if (saved == null) {
        await PhotoManager.editor.saveVideo(File(pathToSave));
      }
    }
  }
}
