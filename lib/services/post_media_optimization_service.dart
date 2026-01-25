import 'dart:typed_data';
import 'dart:io' show File;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../config/supabase_config.dart';
import '../models/post_model.dart';
import '../services/video_filter_service.dart';
import '../services/storage_service.dart';
import '../services/posts_service.dart';

class PostMediaOptimizationService {
  static PostMediaOptimizationService? _instance;
  PostMediaOptimizationService._();
  static PostMediaOptimizationService of() {
    _instance ??= PostMediaOptimizationService._();
    return _instance!;
  }

  // Use existing singletons via factory constructors
  final StorageService _storageService = StorageService();
  final PostsService _postsService = PostsService();

  /// Compresses an existing post video and updates its media_url.
  /// Returns the new media URL on success.
  Future<String> optimizePostVideo(
    PostModel post, {
    double targetSizeMb = 100.0,
    int initialScaleHeight = 720,
    int initialAudioKbps = 96,
    int? initialTargetKbps,
    int initialCrf = 28,
  }) async {
    if (post.mediaType != MediaType.video) {
      throw Exception('Post is not a video');
    }

    final String? currentUserId = SupabaseConfig.client.auth.currentUser?.id;
    if (currentUserId == null || currentUserId != post.userId) {
      throw Exception('Only the post owner can optimize the video');
    }

    // Ensure we have a valid media URL
    final String? mediaUrl = post.mediaUrl;
    if (mediaUrl == null || mediaUrl.isEmpty) {
      throw Exception('Post has no mediaUrl');
    }

    // Parse URL once
    final uri = Uri.parse(mediaUrl);

    try {
      if (kIsWeb) {
        // --- Web: bytes-based flow ---
        Uint8List workingBytes = await _downloadVideoBytesWithFallback(uri);

        // Iteratively compress to fit under target size using VideoFilterService
        int scaleHeight = initialScaleHeight;
        int audioKbps = initialAudioKbps;
        int? targetKbps = initialTargetKbps;
        int crf = initialCrf;

        for (int attempt = 0; attempt < 3; attempt++) {
          final out = await VideoFilterService.compressVideo(
            input: workingBytes,
            scaleHeight: scaleHeight,
            targetKbps: targetKbps,
            audioKbps: audioKbps,
            crf: crf,
          );
          workingBytes = out;
          if (workingBytes.length <= (targetSizeMb * 1024 * 1024)) {
            break;
          }
          if (targetKbps != null) {
            targetKbps = (targetKbps * 0.75).round().clamp(400, 1800);
          } else {
            crf = (crf + 4).clamp(28, 38);
            if (crf >= 36 && scaleHeight > 540) {
              scaleHeight = 540;
            } else if (crf >= 38 && scaleHeight > 480) {
              scaleHeight = 480;
            }
          }
        }

        final String fileName = path.setExtension(
          'optimized_${post.id}_${DateTime.now().millisecondsSinceEpoch}',
          '.mp4',
        );

        final uploadResult = await _storageService.uploadVideo(
          videoFile: null,
          userId: currentUserId,
          videoBytes: workingBytes,
          videoFileName: fileName,
        );
        final String newUrl = uploadResult['videoUrl']!;

        await _postsService.updatePostMediaFields(
          postId: post.id,
          mediaUrl: newUrl,
        );
        return newUrl;
      } else {
        // --- Mobile/Desktop: path-based flow to avoid memory issues ---
        final tempDir = await getTemporaryDirectory();
        final inPath = path.join(
          tempDir.path,
          'equal_opt_in_${DateTime.now().millisecondsSinceEpoch}.mp4',
        );

        // Stream download to file with storage fallback
        await _downloadVideoToFileWithFallback(uri, inPath);

        // Compress via path-based implementation to stay within size target
        final compressedPath = await VideoFilterService().compressVideoPath(
          inPath,
          maxSizeMB: targetSizeMb.round(),
          options: {
            'scaleHeight': initialScaleHeight,
            'audioKbps': initialAudioKbps,
            'crf': initialCrf,
          },
        );

        // Upload optimized file via File streaming
        final uploadResult = await _storageService.uploadVideo(
          videoFile: File(compressedPath),
          userId: currentUserId,
        );
        final String newUrl = uploadResult['videoUrl']!;

        await _postsService.updatePostMediaFields(
          postId: post.id,
          mediaUrl: newUrl,
        );
        return newUrl;
      }
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('download') || msg.contains('unsupported media url')) {
        throw Exception(
          'Could not download the original video. Please check your network and try again.',
        );
      } else if (msg.contains('upload') && msg.contains('size')) {
        throw Exception(
          'Upload size limit reached after optimization. Please trim the video or reduce resolution.',
        );
      } else {
        throw Exception('Optimization failed: $e');
      }
    }
  }

  /// Tries HTTP GET first; if it fails or returns non-200, attempts Supabase Storage download
  Future<Uint8List> _downloadVideoBytesWithFallback(Uri uri) async {
    // Attempt direct HTTP download
    try {
      final resp = await http.get(uri);
      if (resp.statusCode == 200) return resp.bodyBytes;
      // Continue to fallback on non-200
    } catch (_) {
      // Continue to fallback
    }

    // Fallback: Supabase Storage download for public URLs
    try {
      final segments = uri.pathSegments;
      // Expected format: /storage/v1/object/public/{bucket}/{filename...}
      final publicIndex = segments.indexOf('public');
      if (publicIndex != -1 && segments.length >= publicIndex + 2) {
        final bucket = segments[publicIndex + 1];
        final fileName = segments.sublist(publicIndex + 2).join('/');
        final bytes = await SupabaseConfig.client.storage
            .from(bucket)
            .download(fileName);
        return bytes;
      }
      throw Exception('Unsupported media URL format for storage fallback');
    } catch (e) {
      throw Exception('Failed to download existing video: $e');
    }
  }

  /// Stream video download directly to a local file. Falls back to
  /// Supabase Storage download if direct HTTP fails.
  Future<void> _downloadVideoToFileWithFallback(Uri uri, String outPath) async {
    // Attempt direct HTTP download streamed to file
    try {
      final req = http.Request('GET', uri);
      final resp = await req.send();
      if (resp.statusCode == 200) {
        final file = File(outPath);
        final sink = file.openWrite();
        await resp.stream.pipe(sink);
        await sink.close();
        return;
      }
    } catch (_) {
      // continue to fallback
    }

    // Fallback: Supabase Storage download to bytes, then write to file
    try {
      final segments = uri.pathSegments;
      final publicIndex = segments.indexOf('public');
      if (publicIndex != -1 && segments.length >= publicIndex + 2) {
        final bucket = segments[publicIndex + 1];
        final fileName = segments.sublist(publicIndex + 2).join('/');
        final bytes = await SupabaseConfig.client.storage
            .from(bucket)
            .download(fileName);
        final file = File(outPath);
        await file.writeAsBytes(bytes, flush: true);
        return;
      }
      throw Exception('Unsupported media URL format for storage fallback');
    } catch (e) {
      throw Exception('Failed to download existing video to file: $e');
    }
  }
}
