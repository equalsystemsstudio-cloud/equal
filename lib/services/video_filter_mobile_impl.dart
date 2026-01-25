import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';

import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/services.dart' show rootBundle;
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart'
    show FFmpegKit, FFmpegSession, ReturnCode, Log, Statistics;
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/media_information.dart';
import 'package:ffmpeg_kit_flutter_new/statistics.dart';
import 'dart:typed_data';
import 'body_segmentation_service.dart';

double _lastProgress = 0.0;
DateTime? _startTime;

// Apply filter to a local video file using FFmpegKit on mobile
Future<String> applyFilterPathImpl(
  String inputPath,
  String filterId,
  double intensity, {
  Map<String, dynamic>? options,
}) async {
  final dir = await getTemporaryDirectory();
  final outPath = p.join(
    dir.path,
    'equal_filtered_${DateTime.now().millisecondsSinceEpoch}.mp4',
  );

  try {
    final inFile = File(inputPath);
    if (!await inFile.exists()) {
      // If input path does not exist, just return the original path to avoid breaking flows.
      return inputPath;
    }

    // Build filter graph
    final t = intensity.clamp(0.0, 1.0);
    Map<String, double>? regionRect;
    if (filterId == 'hip_bum_enhancer') {
      try {
        regionRect = await BodySegmentationService().estimateHipRect(inputPath);
      } catch (_) {}
    }
    final rawGraph = _buildFilterGraph(filterId, t, rect: regionRect);

    // Speed option (0.5x - 2.0x supported directly). For >2x chain atempo twice.
    final speed = (options?['speed'] is num)
        ? (options!['speed'] as num).toDouble()
        : 1.0;
    final vspeed = speed <= 0 ? 1.0 : speed;
    final setpts = (1.0 / vspeed).toStringAsFixed(4);
    String atempo;
    if (vspeed < 0.5) {
      // Limit minimum to 0.5
      atempo = '0.5';
    } else if (vspeed > 2.0) {
      // Chain to approximate higher speeds
      final s = vspeed.clamp(2.0, 4.0);
      final a1 = (s / 2.0).toStringAsFixed(3);
      atempo = '2.0,atempo=$a1';
    } else {
      atempo = vspeed.toStringAsFixed(3);
    }

    // Compose filters
    final bool isComplex = rawGraph.startsWith('complex:');
    final String complex = isComplex
        ? rawGraph.substring(8) + ';[vout]setpts=' + setpts + '*PTS[v]'
        : '[0:v]' +
              (rawGraph.isNotEmpty && rawGraph != 'null' ? '$rawGraph,' : '') +
              'setpts=' +
              setpts +
              '*PTS[v]';

    // Reset progress
    _lastProgress = 0.0;
    _startTime = DateTime.now();

    // Run FFmpeg command
    final cmd = [
      '-y',
      '-i',
      _escape(inputPath),
      '-filter_complex',
      _escape(complex),
      '-map',
      '[v]',
      '-map',
      '[0:a]?',
      '-filter:a',
      'atempo=' + atempo,
      '-c:v',
      'libx264',
      '-preset',
      'veryfast',
      '-crf',
      '23',
      '-c:a',
      'aac',
      '-movflags',
      '+faststart',
      _escape(outPath),
    ].join(' ');

    final session = await FFmpegKit.executeAsync(
      cmd,
      (session) async {},
      (log) {
        // Optional: debugPrint('[FFmpeg] \"${log.getMessage()}\"');
      },
      (statistics) {
        _updateProgress(statistics, inputPath);
      },
    );

    // Wait for completion
    final returnCode = await session.getReturnCode();
    if (ReturnCode.isSuccess(returnCode)) {
      // Success
      if (await File(outPath).exists()) {
        return outPath;
      }
      // Fallback to input if output missing
      return inputPath;
    }

    // Failure -> fallback to original
    return inputPath;
  } catch (_) {
    // Fallback: return original path
    return inputPath;
  } finally {
    // Reset progress state for UI polling
    _startTime = null;
  }
}

void _updateProgress(Statistics s, String inputPath) {
  try {
    final size = File(inputPath).lengthSync();
    if (size <= 0) {
      _lastProgress = 0.0;
      return;
    }
    // Heuristic: progress by processed size if available, otherwise by time
    final timeMs = s.getTime();
    if (timeMs != null && timeMs > 0) {
      // Assume typical max duration unknown; use moving ratio up to 0.9 then jump to 1.0 at completion
      final elapsed = timeMs / 1000.0;
      final estTotal = (elapsed / (_lastProgress > 0.01 ? _lastProgress : 0.1))
          .clamp(1.0, 600.0);
      final ratio = (elapsed / estTotal).clamp(0.0, 0.95);
      _lastProgress = ratio;
    } else {
      _lastProgress = (_lastProgress + 0.02).clamp(0.0, 0.9);
    }
  } catch (_) {
    _lastProgress = (_lastProgress + 0.01).clamp(0.0, 0.9);
  }
}

double getProgressImpl() => _lastProgress.clamp(0.0, 1.0);

String _buildFilterGraph(
  String filterId,
  double t, {
  Map<String, double>? rect,
}) {
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
      {
        final sx = (1.0 + (0.12 * t)).toStringAsFixed(3);
        if (rect != null) {
          final rx = (rect['x'] ?? 0.0).clamp(0.0, 1.0);
          final ry = (rect['y'] ?? 0.5).clamp(0.0, 1.0);
          final rw = (rect['w'] ?? 1.0).clamp(0.05, 1.0);
          final rh = (rect['h'] ?? 0.5).clamp(0.05, 1.0);
          return 'complex:'
              '[0:v]split=2[base][tmp];'
              '[tmp]crop=w=trunc(iw*${rw}/2)*2:h=trunc(ih*${rh}/2)*2:x=trunc(iw*${rx}):y=trunc(ih*${ry}),scale=trunc(iw*${sx}/2)*2:ih,boxblur=2:2[region];'
              '[base][region]overlay=x=trunc(W*${rx}):y=trunc(H*${ry})[vout]';
        }
        // Fallback: widen lower half horizontally and overlay back with slight blur for seam softening
        return 'complex:'
            '[0:v]split=2[base][tmp];'
            '[tmp]crop=iw:ih*0.5:0:ih*0.5,scale=trunc(iw*${sx}/2)*2:ih,boxblur=2:2[low];'
            '[base][low]overlay=x=(W-w)/2:y=H/2[vout]';
      }
    case 'original':
    default:
      return 'null';
  }
}

Future<double> getVideoDurationImpl(String path) async {
  try {
    final session = await FFprobeKit.getMediaInformation(path);
    final info = session.getMediaInformation();
    if (info != null) {
      final durationStr = info.getDuration();
      if (durationStr != null) {
        return double.tryParse(durationStr) ?? 0.0;
      }
    }
  } catch (e) {
    debugPrint('Error getting video duration: $e');
  }
  return 0.0;
}

String _escape(String s) {
  // Wrap in quotes to handle spaces and special characters
  if (!s.startsWith('"')) {
    return '"${s.replaceAll('"', '\\"')}"';
  }
  return s;
}

Future<String> compressVideoPathImpl(
  String inputPath, {
  int maxSizeMB = 100,
  Map<String, dynamic>? options,
}) async {
  final inFile = File(inputPath);
  if (!await inFile.exists()) return inputPath;

  // If already under cap, return original
  final sizeBytes = await inFile.length();
  if (sizeBytes <= maxSizeMB * 1024 * 1024) return inputPath;

  final dir = await getTemporaryDirectory();
  final outPath = p.join(
    dir.path,
    'equal_compressed_${DateTime.now().millisecondsSinceEpoch}.mp4',
  );

  // Options with iterative strategy
  int scaleHeight = (options?['scaleHeight'] is int)
      ? options!['scaleHeight'] as int
      : 720;
  final int audioKbps = (options?['audioKbps'] is int)
      ? options!['audioKbps'] as int
      : 96;
  int? targetKbps = (options?['targetKbps'] is int)
      ? options!['targetKbps'] as int
      : null;
  int crf = (options?['crf'] is int) ? options!['crf'] as int : 28;

  // Smart bitrate calculation based on duration to ensure size constraint
  final duration = await getVideoDurationImpl(inputPath);
  if (duration > 0) {
    // Calculate max video bitrate to fit in maxSizeMB
    // Total bits available = maxSizeMB * 8 * 1024 * 1024
    // Available kbps = (Total bits / duration) / 1000
    // Subtract audio bitrate and apply safety margin (0.9)
    final totalBits = maxSizeMB * 8 * 1024 * 1024;
    final maxTotalKbps = (totalBits / duration) / 1000;
    final maxVideoKbps = (maxTotalKbps - audioKbps) * 0.9;

    if (maxVideoKbps > 0) {
      final limitKbps = maxVideoKbps.floor();
      // If no target set, or target is too high for the size limit, override it
      if (targetKbps == null || targetKbps > limitKbps) {
        debugPrint(
          '[VideoFilter] Overriding targetKbps $targetKbps -> $limitKbps for duration ${duration}s to fit ${maxSizeMB}MB',
        );
        targetKbps = limitKbps;
        // Ensure reasonable minimum to avoid unwatchable quality
        if (targetKbps < 100) targetKbps = 100;
      }
    }
  }

  Future<String> _runOnce(String inPath, String outPath) async {
    final vf = 'scale=-2:${scaleHeight}';
    final cmdParts = [
      '-y',
      '-i',
      _escape(inPath),
      '-vf',
      _escape(vf),
      '-c:v',
      'libx264',
      '-preset',
      'veryfast',
      ...(targetKbps != null
          ? [
              '-b:v',
              '${targetKbps}k',
              '-maxrate',
              '${(targetKbps! * 1.5).round()}k',
              '-bufsize',
              '${(targetKbps! * 2).round()}k',
            ]
          : ['-crf', '$crf']),
      '-c:a',
      'aac',
      '-b:a',
      '${audioKbps}k',
      '-movflags',
      '+faststart',
      _escape(outPath),
    ];

    final cmd = cmdParts.join(' ');
    debugPrint('[VideoFilter] Running: $cmd');

    _lastProgress = 0.0;
    _startTime = DateTime.now();
    final completer = Completer<int>();

    await FFmpegKit.executeAsync(
      cmd,
      (session) async {
        final rc = await session.getReturnCode();
        completer.complete(rc?.getValue() ?? 1);
      },
      null,
      (statistics) {
        _updateProgress(statistics, inPath);
      },
    );

    final rc = await completer.future;
    _startTime = null;

    if (ReturnCode.isSuccess(ReturnCode(rc))) {
      return outPath;
    } else {
      debugPrint('[VideoFilter] Failed with RC $rc');
      return inPath;
    }
  }

  String currentPath = inputPath;
  for (int attempt = 0; attempt < 8; attempt++) {
    final outAttemptPath = p.join(
      dir.path,
      'equal_compressed_${DateTime.now().millisecondsSinceEpoch}_$attempt.mp4',
    );
    final producedPath = await _runOnce(currentPath, outAttemptPath);
    if (producedPath != currentPath) {
      currentPath = producedPath;
    }
    // Check size
    try {
      final outSize = await File(currentPath).length();
      if (outSize <= maxSizeMB * 1024 * 1024) {
        return currentPath;
      }
    } catch (_) {}

    // If we are here, it's still too big. Tighten settings for next internal iteration.
    // (Note: StorageService also has an outer loop, but this internal loop helps if VideoFilter is used standalone)
    if (targetKbps != null) {
      targetKbps = (targetKbps * 0.70).round().clamp(100, 1800);
    } else {
      crf = (crf + 2).clamp(26, 42);
    }
    if (scaleHeight > 480)
      scaleHeight = 480;
    else if (scaleHeight > 360)
      scaleHeight = 360;
  }

  return currentPath;
}

// Remove duplicate progress getter
// Path-based wrappers to satisfy VideoFilterService facade on mobile
// DELETE WRAPPER: applyFilterPathImpl(String, ... ) calling applyFilterImpl. It is now the primary path-based impl above.
// DELETE WRAPPER: compressVideoPathImpl(String, ...) calling compressVideoImpl. It is now the primary path-based impl above.
Future<Uint8List> applyFilterImpl({
  required Uint8List input,
  required String filterGraph,
  double speed = 1.0,
}) async {
  final tempDir = await getTemporaryDirectory();
  final inPath = '${tempDir.path}/input.mp4';
  final outPath = '${tempDir.path}/output.mp4';
  await File(inPath).writeAsBytes(input);

  final hasSpeed = speed != 1.0;
  final atempo = hasSpeed ? (speed.clamp(0.5, 2.0)) : 1.0;
  final args = [
    '-y',
    '-i',
    inPath,
    '-vf',
    filterGraph,
    if (hasSpeed) ...['-filter:a', 'atempo=$atempo'],
    '-c:v',
    'libx264',
    '-preset',
    'fast',
    '-crf',
    '23',
    '-c:a',
    hasSpeed ? 'aac' : 'copy',
    outPath,
  ].join(' ');

  final session = await FFmpegKit.execute(args);
  final rc = await session.getReturnCode();
  if (ReturnCode.isSuccess(rc)) {
    final data = await File(outPath).readAsBytes();
    return Uint8List.fromList(data);
  }
  throw Exception('FFmpeg applyFilter failed: ${rc?.getValue()}');
}

Future<Uint8List> compressVideoImpl({
  required Uint8List input,
  int scaleHeight = 720,
  int? targetKbps,
  int audioKbps = 96,
  int? crf,
}) async {
  final tempDir = await getTemporaryDirectory();
  final inPath = '${tempDir.path}/input.mp4';
  final outPath = '${tempDir.path}/output.mp4';
  await File(inPath).writeAsBytes(input);

  final scaleFilter = 'scale=-2:$scaleHeight';
  final useBitrate = targetKbps != null;
  final args = [
    '-y',
    '-i',
    inPath,
    '-vf',
    scaleFilter,
    '-c:v',
    'libx264',
    '-preset',
    'veryfast',
    if (useBitrate) ...[
      '-b:v',
      '${targetKbps}k',
      '-maxrate',
      '${targetKbps}k',
      '-bufsize',
      '${(targetKbps! * 2)}k',
    ] else ...[
      '-crf',
      '${crf ?? 28}',
    ],
    '-c:a',
    'aac',
    '-b:a',
    '${audioKbps}k',
    '-movflags',
    '+faststart',
    outPath,
  ].join(' ');

  final session = await FFmpegKit.execute(args);
  final rc = await session.getReturnCode();
  if (ReturnCode.isSuccess(rc)) {
    final data = await File(outPath).readAsBytes();
    return Uint8List.fromList(data);
  }
  throw Exception('FFmpeg compress failed: ${rc?.getValue()}');
}

Future<Uint8List?> extractThumbnailImpl({
  required Uint8List input,
  double atSeconds = 0.5,
}) async {
  try {
    final tempDir = await getTemporaryDirectory();
    final inPath =
        '${tempDir.path}/thumb_input_${DateTime.now().millisecondsSinceEpoch}.mp4';
    final outPath =
        '${tempDir.path}/thumb_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await File(inPath).writeAsBytes(input);

    final cmd = [
      '-y',
      '-ss',
      atSeconds.toStringAsFixed(3),
      '-i',
      _escape(inPath),
      '-frames:v',
      '1',
      '-q:v',
      '2',
      _escape(outPath),
    ].join(' ');

    final session = await FFmpegKit.execute(cmd);
    final rc = await session.getReturnCode();
    if (ReturnCode.isSuccess(rc)) {
      if (await File(outPath).exists()) {
        final data = await File(outPath).readAsBytes();
        return Uint8List.fromList(data);
      }
    }
    return null;
  } catch (_) {
    return null;
  }
}

Future<Uint8List?> extractThumbnailPathImpl(
  String inputPath, {
  double atSeconds = 0.5,
}) async {
  try {
    if (!await File(inputPath).exists()) return null;
    final tempDir = await getTemporaryDirectory();
    final outPath =
        '${tempDir.path}/thumb_${DateTime.now().millisecondsSinceEpoch}.jpg';

    final cmd = [
      '-y',
      '-ss',
      atSeconds.toStringAsFixed(3),
      '-i',
      _escape(inputPath),
      '-frames:v',
      '1',
      '-q:v',
      '2',
      _escape(outPath),
    ].join(' ');

    final session = await FFmpegKit.execute(cmd);
    final rc = await session.getReturnCode();
    if (ReturnCode.isSuccess(rc)) {
      if (await File(outPath).exists()) {
        final data = await File(outPath).readAsBytes();
        return Uint8List.fromList(data);
      }
    }
    return null;
  } catch (_) {
    return null;
  }
}

Future<void> startServerProcessingImpl(Uint8List input) async {}
Future<Map<String, dynamic>> getServerProcessingStatusImpl(String id) async =>
    {};

Future<Uint8List> combineSideBySideImpl({
  required Uint8List left,
  required Uint8List right,
  int scaleHeight = 720,
  bool mute = false,
  int? crf,
}) async {
  final tempDir = await getTemporaryDirectory();
  final leftPath = '${tempDir.path}/left.mp4';
  final rightPath = '${tempDir.path}/right.mp4';
  final outPath = '${tempDir.path}/combined.mp4';
  await File(leftPath).writeAsBytes(left);
  await File(rightPath).writeAsBytes(right);

  final vf = 'scale=-2:$scaleHeight';
  final complex =
      '[0:v]$vf,setsar=1[leftv];[1:v]$vf,setsar=1[rightv];[leftv][rightv]hstack=inputs=2[vout]';

  final args = [
    '-y',
    '-i',
    leftPath,
    '-i',
    rightPath,
    '-filter_complex',
    complex,
    '-map',
    '[vout]',
    if (!mute) ...['-map', '0:a:0?'],
    '-c:v',
    'libx264',
    '-preset',
    'veryfast',
    '-crf',
    '${crf ?? 23}',
    if (!mute) ...['-c:a', 'aac'],
    outPath,
  ].join(' ');

  final session = await FFmpegKit.execute(args);
  final rc = await session.getReturnCode();
  if (ReturnCode.isSuccess(rc)) {
    final data = await File(outPath).readAsBytes();
    return Uint8List.fromList(data);
  }
  throw Exception('FFmpeg combine failed: ${rc?.getValue()}');
}

// Append a short black-tail video with an outro audio to the end of a video file.
// Returns output path on success, or null on failure.
Future<String?> appendOutroToVideoPathImpl(
  String inputPath, {
  Uint8List? outroAudioBytes,
  int outroSeconds = 2,
}) async {
  try {
    final inFile = File(inputPath);
    if (!await inFile.exists()) return null;

    final dir = await getTemporaryDirectory();
    final outPath = p.join(
      dir.path,
      'equal_outro_${DateTime.now().millisecondsSinceEpoch}.mp4',
    );
    String? outroPath;
    if (outroAudioBytes != null) {
      // Pick a sensible extension based on simple header detection
      // MP3 files often start with 'ID3' or 0xFF 0xFB sync bytes; MP4/M4A has 'ftyp'
      final isMp3 =
          (outroAudioBytes.length >= 3 &&
              String.fromCharCodes(outroAudioBytes.sublist(0, 3)) == 'ID3') ||
          (outroAudioBytes.length >= 2 &&
              outroAudioBytes[0] == 0xFF &&
              (outroAudioBytes[1] & 0xE0) == 0xE0);
      final ext = isMp3 ? 'mp3' : 'm4a';
      outroPath = p.join(
        dir.path,
        'outro_${DateTime.now().millisecondsSinceEpoch}.$ext',
      );
      await File(outroPath).writeAsBytes(outroAudioBytes);
    }

    // Try to load app logo from assets; optional.
    String? logoPath;
    try {
      final logoData = await rootBundle.load('assets/images/app_icon.png');
      logoPath = p.join(
        dir.path,
        'logo_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await File(logoPath).writeAsBytes(logoData.buffer.asUint8List());
    } catch (_) {
      logoPath = null;
    }

    // Build primary FFmpeg command with video+audio concat and logo overlay.
    // Inputs:
    // 0: original video
    // 1: generated black video of length outroSeconds
    // 2: outro audio (asset) OR generated sine tone
    // 3: logo image (optional)
    final cmdWithAudio = <String>[
      '-y',
      '-i',
      _escape(inputPath),
      '-f',
      'lavfi',
      '-t',
      '$outroSeconds',
      '-i',
      'color=c=black:s=1280x720',
      if (outroPath != null) ...[
        '-i',
        _escape(outroPath),
      ] else ...[
        '-f',
        'lavfi',
        '-t',
        '$outroSeconds',
        '-i',
        'sine=frequency=600:sample_rate=44100',
      ],
      if (logoPath != null) ...['-loop', '1', '-i', _escape(logoPath!)],
      '-filter_complex',
      _escape(
        '[0:v]scale=-2:720,format=yuv420p[v0];'
        '[1:v]format=yuv420p[v1];'
        '${logoPath != null ? '[3:v]scale=300:-1,format=rgba,fade=t=in:st=0:d=0.25:alpha=1,fade=t=out:st=' + (outroSeconds - 0.25).toStringAsFixed(2) + ':d=0.25:alpha=1[lg];[v1][lg]overlay=x=(main_w-overlay_w)/2:y=(main_h-overlay_h)-60-10*sin(2*PI*t):format=auto[v1o];' : '[v1]copy[v1o];'}'
        '[0:a]aformat=sample_rates=44100:channel_layouts=stereo[a0];'
        '[2:a]aformat=sample_rates=44100:channel_layouts=stereo[a1];'
        '[v0][a0][v1o][a1]concat=n=2:v=1:a=1[v][a]',
      ),
      '-map',
      '[v]',
      '-map',
      '[a]',
      '-c:v',
      'libx264',
      '-preset',
      'veryfast',
      '-crf',
      '23',
      '-c:a',
      'aac',
      '-movflags',
      '+faststart',
      _escape(outPath),
    ];

    _lastProgress = 0.0;
    _startTime = DateTime.now();
    final session = await FFmpegKit.executeAsync(
      cmdWithAudio.join(' '),
      (session) async {},
      null,
      (statistics) {
        _updateProgress(statistics, inputPath);
      },
    );
    final rc = await session.getReturnCode();
    if (ReturnCode.isSuccess(rc)) {
      if (await File(outPath).exists()) {
        return outPath;
      }
      return null;
    }
    // Fallback: concat video only and overlay logo; drop audio mapping.
    final outPathVideoOnly = p.join(
      dir.path,
      'equal_outro_vo_${DateTime.now().millisecondsSinceEpoch}.mp4',
    );
    final cmdVideoOnly = <String>[
      '-y',
      '-i',
      _escape(inputPath),
      '-f',
      'lavfi',
      '-t',
      '$outroSeconds',
      '-i',
      'color=c=black:s=1280x720',
      if (logoPath != null) ...['-loop', '1', '-i', _escape(logoPath!)],
      '-filter_complex',
      _escape(
        '[0:v]scale=-2:720,format=yuv420p[v0];'
        '[1:v]format=yuv420p[v1];'
        '${logoPath != null ? '[2:v]scale=300:-1,format=rgba,fade=t=in:st=0:d=0.25:alpha=1,fade=t=out:st=' + (outroSeconds - 0.25).toStringAsFixed(2) + ':d=0.25:alpha=1[lg];[v1][lg]overlay=x=(main_w-overlay_w)/2:y=(main_h-overlay_h)-60-10*sin(2*PI*t):format=auto[v1o];' : '[v1]copy[v1o];'}'
        '[v0][v1o]concat=n=2:v=1[outv]',
      ),
      '-map',
      '[outv]',
      '-c:v',
      'libx264',
      '-preset',
      'veryfast',
      '-crf',
      '23',
      '-movflags',
      '+faststart',
      _escape(outPathVideoOnly),
    ];

    final session2 = await FFmpegKit.executeAsync(
      cmdVideoOnly.join(' '),
      (session) async {},
      null,
      (statistics) {
        _updateProgress(statistics, inputPath);
      },
    );
    final rc2 = await session2.getReturnCode();
    if (ReturnCode.isSuccess(rc2)) {
      if (await File(outPathVideoOnly).exists()) {
        return outPathVideoOnly;
      }
    }
    return null;
  } catch (_) {
    return null;
  } finally {
    _startTime = null;
  }
}
