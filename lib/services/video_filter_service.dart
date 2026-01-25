import 'dart:typed_data';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;

import 'video_filter_mobile_impl.dart'
    if (dart.library.html) 'video_filter_web_impl.dart'
    as impl;

class VideoFilterService {
  // Existing byte-based, platform-agnostic APIs
  static Future<Uint8List> applyFilter({
    required Uint8List input,
    required String filterGraph,
    double speed = 1.0,
  }) {
    return impl.applyFilterImpl(
      input: input,
      filterGraph: filterGraph,
      speed: speed,
    );
  }

  static Future<Uint8List> compressVideo({
    required Uint8List input,
    int scaleHeight = 720,
    int? targetKbps,
    int audioKbps = 96,
    int? crf,
  }) {
    return impl.compressVideoImpl(
      input: input,
      scaleHeight: scaleHeight,
      targetKbps: targetKbps,
      audioKbps: audioKbps,
      crf: crf,
    );
  }

  static double getProgress() {
    return impl.getProgressImpl();
  }

  static Future<Uint8List> combineSideBySide({
    required Uint8List left,
    required Uint8List right,
    int scaleHeight = 720,
    bool mute = false,
    int? crf,
  }) {
    return impl.combineSideBySideImpl(
      left: left,
      right: right,
      scaleHeight: scaleHeight,
      mute: mute,
      crf: crf,
    );
  }

  // Optional server processing hooks (byte-based)
  static Future<void> startServerProcessing(Uint8List input) {
    return impl.startServerProcessingImpl(input);
  }

  static Future<Map<String, dynamic>> getServerProcessingStatus(String id) {
    return impl.getServerProcessingStatusImpl(id);
  }

  // Instance wrapper methods for legacy flows used by CreatePostScreen
  // Mobile: delegate to path-based impl; Web: operate on data URIs and convert to bytes-based static APIs

  Future<String> compressVideoPath(
    String inputPath, {
    int maxSizeMB = 100,
    Map<String, dynamic>? options,
  }) async {
    if (!kIsWeb) {
      // Delegate to mobile implementation (path-based)
      return await impl.compressVideoPathImpl(
        inputPath,
        maxSizeMB: maxSizeMB,
        options: options,
      );
    }
    // Web: inputPath is expected to be a data URI. Decode, compress via static API, then return data URI
    try {
      final bytes = _decodeDataUri(inputPath);
      final int scaleHeight = (options?['scaleHeight'] is int)
          ? options!['scaleHeight'] as int
          : 720;
      final int audioKbps = (options?['audioKbps'] is int)
          ? options!['audioKbps'] as int
          : 96;
      final int? targetKbps = (options?['targetKbps'] is int)
          ? options!['targetKbps'] as int
          : null;
      final int? crf = (options?['crf'] is int) ? options!['crf'] as int : null;
      final out = await VideoFilterService.compressVideo(
        input: bytes,
        scaleHeight: scaleHeight,
        targetKbps: targetKbps,
        audioKbps: audioKbps,
        crf: crf,
      );
      // Re-encode to data URI
      final b64 = base64Encode(out);
      return 'data:video/mp4;base64,$b64';
    } catch (e) {
      // If web logic fails, return original
      return inputPath;
    }
  }

  Future<String> applyFilterPath(
    String inputPath,
    String filterId,
    double intensity, {
    Map<String, dynamic>? options,
  }) async {
    // Delegate to platform implementation for both mobile and web.
    // Web impl leverages ffmpeg.wasm and its richer filter graph coverage.
    return await impl.applyFilterPathImpl(
      inputPath,
      filterId,
      intensity,
      options: options,
    );
  }

  // New: Extract a JPEG thumbnail from video bytes (returns null if not supported on platform)
  static Future<Uint8List?> extractThumbnail({
    required Uint8List input,
    double atSeconds = 0.5,
  }) {
    return impl.extractThumbnailImpl(input: input, atSeconds: atSeconds);
  }

  // New: Path-based thumbnail extraction (mobile path-based, web data URI handled by wrapper)
  Future<Uint8List?> extractThumbnailPath(
    String inputPath, {
    double atSeconds = 0.5,
  }) async {
    if (!kIsWeb) {
      return await impl.extractThumbnailPathImpl(
        inputPath,
        atSeconds: atSeconds,
      );
    }
    // Web: inputPath is expected to be a data URI. Decode and attempt byte-based extraction (may return null)
    try {
      final bytes = _decodeDataUri(inputPath);
      return await extractThumbnail(input: bytes, atSeconds: atSeconds);
    } catch (_) {
      return null;
    }
  }

  double getProgressInstance() {
    return impl.getProgressImpl();
  }

  // Server-side processing instance wrappers expected by CreatePostScreen
  static final Map<String, Map<String, dynamic>> _serverJobs = {};

  Future<String> startServerProcessingJob({
    required String sourceUrl,
    required String filterId,
    required double intensity,
    Map<String, dynamic>? options,
  }) async {
    // Stubbed: immediately create a completed job using sourceUrl
    final jobId = 'job_${DateTime.now().millisecondsSinceEpoch}';
    _serverJobs[jobId] = {
      'status': 'completed',
      'progress': 1.0,
      'resultUrl': sourceUrl,
      // Optional thumbnail passthrough if provided via options
      if ((options?['thumbnailUrl']) is String)
        'thumbnailUrl': options!['thumbnailUrl'],
    };
    return jobId;
  }

  Future<Map<String, dynamic>> getServerProcessingJobStatus(
    String jobId,
  ) async {
    // Stubbed: return completed status for known jobId or pending otherwise
    final job = _serverJobs[jobId];
    if (job != null) return job;
    return {'status': 'pending', 'progress': 0.0};
  }

  // Get video duration in seconds (0.0 if failed or unavailable)
  Future<double> getVideoDuration(String path) {
    return impl.getVideoDurationImpl(path);
  }

  // Helper for web fallback in compressVideoPath
  Uint8List _decodeDataUri(String dataUri) {
    final comma = dataUri.indexOf(',');
    if (comma == -1) return Uint8List(0);
    final b64 = dataUri.substring(comma + 1);
    return base64Decode(b64);
  }

  String _encodeDataUri(Uint8List bytes) {
    final b64 = base64Encode(bytes);
    return 'data:video/mp4;base64,$b64';
  }

  String _buildFilterGraph(String filterId, double t) {
    double lerp(double a, double b, double t) => a + (b - a) * t;
    switch (filterId) {
      case 'teal_orange':
        return 'colorbalance=bs=${lerp(0.0, -0.25, t)}:rm=${lerp(0.0, 0.30, t)},eq=contrast=${lerp(1.0, 1.20, t)}:saturation=${lerp(1.0, 1.35, t)}';
      case 'cinematic_blue':
        return 'colorbalance=bs=${lerp(0.0, 0.22, t)}:gs=${lerp(0.0, 0.12, t)},eq=contrast=${lerp(1.0, 1.18, t)}:brightness=${lerp(0.0, -0.06, t)}:saturation=${lerp(1.0, 1.18, t)}';
      case 'warm_skin_glow':
        return 'colorbalance=rm=${lerp(0.0, 0.28, t)}:gm=${lerp(0.0, 0.14, t)},eq=gamma=${lerp(1.0, 0.85, t)}:saturation=${lerp(1.0, 1.30, t)}';
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
      case 'vhs_retro':
        return 'noise=alls=${lerp(0.0, 25.0, t)}:allf=t+u,curves=preset=vintage,eq=saturation=${lerp(1.0, 0.65, t)}';
      case 'anime_ink':
        return 'unsharp=luma_msize_x=7:luma_msize_y=7:luma_amount=${lerp(0.0, 4.0, t)},eq=saturation=${lerp(1.0, 1.6, t)}';
      case 'slow_shutter':
        return 'tmix=frames=${lerp(1.0, 12.0, t).round()}';
      case 'hip_bum_enhancer':
        {
          final sx = (1.0 + (0.24 * t)).toStringAsFixed(3);
          return 'complex:'
                  '[0:v]split=2[base][tmp];'
                  '[tmp]crop=iw:ih*0.5:0:ih*0.5,scale=trunc(iw*' +
              sx +
              '/2)*2:ih,boxblur=2:2[low];'
                  '[base][low]overlay=x=(W-w)/2:y=H/2[vout]';
        }
      case 'original':
      default:
        return 'null';
    }
  }

  // New: Append a short outro segment to a video file by path.
  // On mobile, this uses FFmpeg to concatenate a black tail with an outro audio.
  // On web, returns null unless ffmpeg.wasm integration supports it.
  Future<String?> appendOutroToVideoPath(
    String inputPath, {
    Uint8List? outroAudioBytes,
    int outroSeconds = 2,
  }) async {
    return await impl.appendOutroToVideoPathImpl(
      inputPath,
      outroAudioBytes: outroAudioBytes,
      outroSeconds: outroSeconds,
    );
  }
}
