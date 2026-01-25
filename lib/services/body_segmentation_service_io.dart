import 'dart:io';
import 'dart:math' as math;

import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

class BodySegmentationService {
  /// Estimates a hip/lower-body region from a single keyframe using ML Kit Pose Detection.
  /// Returns a normalized rectangle {x, y, w, h} in [0,1] coordinates relative to the video frame.
  /// If detection fails, falls back to lower-half region.
  Future<Map<String, double>> estimateHipRect(String videoPath) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final framePath = p.join(tempDir.path, 'equal_keyframe_${DateTime.now().millisecondsSinceEpoch}.jpg');

      // Extract one frame using FFmpeg; rely on first keyframe as a quick heuristic
      final cmd = '-y -i "${_escape(videoPath)}" -frames:v 1 -q:v 2 "$framePath"';
      final session = await FFmpegKit.execute(cmd);
      final rc = await session.getReturnCode();
      if (rc == null || rc.getValue() != 0 || !await File(framePath).exists()) {
        // Fallback: lower half
        return { 'x': 0.0, 'y': 0.5, 'w': 1.0, 'h': 0.5 };
      }

      final options = PoseDetectorOptions();
      final detector = PoseDetector(options: options);
      final inputImage = InputImage.fromFilePath(framePath);
      final poses = await detector.processImage(inputImage);
      await detector.close();

      if (poses.isEmpty) {
        return { 'x': 0.0, 'y': 0.5, 'w': 1.0, 'h': 0.5 };
      }
      final pose = poses.first;

      PoseLandmark? leftHip = pose.landmarks[PoseLandmarkType.leftHip];
      PoseLandmark? rightHip = pose.landmarks[PoseLandmarkType.rightHip];
      PoseLandmark? leftKnee = pose.landmarks[PoseLandmarkType.leftKnee];
      PoseLandmark? rightKnee = pose.landmarks[PoseLandmarkType.rightKnee];

      if (leftHip == null || rightHip == null || leftKnee == null || rightKnee == null) {
        return { 'x': 0.0, 'y': 0.5, 'w': 1.0, 'h': 0.5 };
      }

      // Compute a region spanning horizontally between hips, and vertically from hips down towards knees.
      final hipXMin = math.min(leftHip.x, rightHip.x);
      final hipXMax = math.max(leftHip.x, rightHip.x);
      final hipY = (leftHip.y + rightHip.y) / 2.0;
      final kneeY = (leftKnee.y + rightKnee.y) / 2.0;

      // Expand horizontally by a margin for bum/hip coverage; clamp into [0,1] after normalization
      final widthPx = hipXMax - hipXMin;
      final marginPx = widthPx * 0.35; // 35% margin
      double x0 = hipXMin - marginPx;
      double x1 = hipXMax + marginPx;

      // Vertical bounds: from hips down to midway between hips and knees, with margin
      final y0 = hipY - (widthPx * 0.10);
      final y1 = hipY + (kneeY - hipY) * 0.75;

      // We don't know image dimensions here; ML Kit provides pixel coordinates relative to the input image.
      // Normalize using the detected bounding box of all landmarks as an approximation.
      final xs = pose.landmarks.values.map((l) => l.x).toList();
      final ys = pose.landmarks.values.map((l) => l.y).toList();
      final minX = xs.reduce(math.min);
      final maxX = xs.reduce(math.max);
      final minY = ys.reduce(math.min);
      final maxY = ys.reduce(math.max);
      final spanX = (maxX - minX).abs() < 1e-3 ? 1.0 : (maxX - minX);
      final spanY = (maxY - minY).abs() < 1e-3 ? 1.0 : (maxY - minY);

      double nx0 = (x0 - minX) / spanX;
      double nx1 = (x1 - minX) / spanX;
      double ny0 = (y0 - minY) / spanY;
      double ny1 = (y1 - minY) / spanY;

      nx0 = nx0.clamp(0.0, 1.0);
      nx1 = nx1.clamp(0.0, 1.0);
      ny0 = ny0.clamp(0.0, 1.0);
      ny1 = ny1.clamp(0.0, 1.0);

      // Ensure minimum size
      if ((nx1 - nx0) < 0.20) {
        final mid = (nx0 + nx1) / 2.0;
        nx0 = (mid - 0.10).clamp(0.0, 1.0);
        nx1 = (mid + 0.10).clamp(0.0, 1.0);
      }
      if ((ny1 - ny0) < 0.20) {
        final mid = (ny0 + ny1) / 2.0;
        ny0 = (mid - 0.10).clamp(0.0, 1.0);
        ny1 = (mid + 0.10).clamp(0.0, 1.0);
      }

      final rect = {
        'x': nx0,
        'y': ny0,
        'w': (nx1 - nx0),
        'h': (ny1 - ny0),
      };
      return rect;
    } catch (_) {
      // Fallback: lower half
      return { 'x': 0.0, 'y': 0.5, 'w': 1.0, 'h': 0.5 };
    }
  }

  String _escape(String s) => s.replaceAll('"', '\\"');
}
