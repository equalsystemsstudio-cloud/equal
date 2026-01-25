import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:path/path.dart' as path;
import '../config/supabase_config.dart';
import 'media_upload_service.dart';
import 'localization_service.dart';
import '../services/video_filter_service.dart';
import '../services/moderation_service.dart';

// Conditional import for File class (mobile only)
import 'dart:io' show File;

class StorageService {
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  StorageService._internal();

  final SupabaseClient _client = SupabaseConfig.client;
  final MediaUploadService _mediaService = MediaUploadService();
  final ModerationService _moderationService = ModerationService();

  // Upload video file - Now using Cloudflare R2
  Future<Map<String, String>> uploadVideo({
    required dynamic videoFile, // File on mobile, bytes on web
    required String userId,
    dynamic thumbnailFile, // File on mobile, bytes on web
    Function(double)? onProgress,
    Uint8List? videoBytes, // For web uploads
    Uint8List? thumbnailBytes, // For web uploads
    String? videoFileName, // For web uploads
    String? thumbnailFileName, // For web uploads
  }) async {
    try {
      Uint8List videoFileBytes;
      String originalVideoFileName;

      if (videoBytes != null && videoFileName != null) {
        // Web upload using bytes
        videoFileBytes = videoBytes;
        originalVideoFileName = videoFileName;
        // Hard cap: reject files larger than 100MB with a clear message
        const int absoluteMaxBytes = 100 * 1024 * 1024; // 100MB
        if (videoFileBytes.length > absoluteMaxBytes) {
          throw Exception(
            LocalizationService.t(
              'post_size_limit',
            ).replaceAll('{limit}', '100'),
          );
        }
        // Allow all video formats on web; content type inferred from file extension during upload

        // Enforce SupabaseConfig.maxVideoSize on web uploads
        if (videoFileBytes.length > SupabaseConfig.maxVideoSize) {
          final mb = (videoFileBytes.length / (1024 * 1024)).toStringAsFixed(1);
          final maxMb = (SupabaseConfig.maxVideoSize / (1024 * 1024))
              .toStringAsFixed(0);
          throw Exception(
            LocalizationService.t(
              'upload_size_limit_exceeded_details',
            ).replaceAll('{limit}', maxMb).replaceAll('{current}', mb),
          );
        }
        // Skip NSFW frame moderation on web when compression/transcoding is disabled
      } else if (videoFile != null) {
        // Mobile upload using File (stream without loading entire bytes)
        String finalVideoPath = videoFile.path as String;
        originalVideoFileName = path.basename(finalVideoPath);
        final ext = path.extension(originalVideoFileName).toLowerCase();

        if (ext != '.mp4') {
          try {
            // Transcode non-MP4 inputs to MP4 using path-based compressor
            final compressedPath = await VideoFilterService().compressVideoPath(
              finalVideoPath,
              maxSizeMB: 100,
              options: {'scaleHeight': 720, 'audioKbps': 96, 'crf': 28},
            );
            finalVideoPath = compressedPath;
            originalVideoFileName = path.setExtension(
              originalVideoFileName,
              '.mp4',
            );
          } catch (_) {
            // If transcoding fails, proceed with original path
          }
        }

        // Hard cap: reject files larger than 100MB with a clear message
        try {
          final f0 = File(finalVideoPath);
          final size0 = await f0.length();
          const int absoluteMaxBytes = 100 * 1024 * 1024; // 100MB
          if (size0 > absoluteMaxBytes) {
            throw Exception(
              LocalizationService.t(
                'post_size_limit',
              ).replaceAll('{limit}', '100'),
            );
          }
        } catch (_) {}

        // Perform NSFW moderation on sampled frames before upload
        try {
          final frameTimes = [0.1, 0.35, 0.6, 0.8];
          final frames = <Uint8List>[];
          for (final t in frameTimes) {
            final f = await VideoFilterService().extractThumbnailPath(
              finalVideoPath,
              atSeconds: t,
            );
            if (f != null) frames.add(f);
          }
          if (frames.isNotEmpty) {
            final mod = await _moderationService.checkVideoFrames(frames);
            if (!mod.isAllowed) {
              await _moderationService.recordStrike(
                userId: userId,
                type: 'video_nsfw',
                score: mod.nsfwScore,
                details: {
                  'file': originalVideoFileName,
                  'reason': 'Explicit sexual content detected',
                },
              );
              throw Exception(
                'Upload rejected: explicit sexual content is not allowed. Accounts posting NSFW may be banned.',
              );
            }
          }
        } catch (_) {
          // If moderation fails, proceed without blocking
        }

        // Generate postId for video upload
        final postId = 'post_${DateTime.now().millisecondsSinceEpoch}';

        // Upload via File streaming
        final videoUrl = await _mediaService.uploadPostVideoFile(
          userId: userId,
          postId: postId,
          file: File(finalVideoPath),
          originalFileName: originalVideoFileName,
        );

        String? thumbnailUrl;

        // Upload thumbnail if provided
        if (thumbnailFile != null || thumbnailBytes != null) {
          Uint8List thumbnailFileBytes;

          if (thumbnailBytes != null && thumbnailFileName != null) {
            thumbnailFileBytes = thumbnailBytes;
          } else if (thumbnailFile != null) {
            thumbnailFileBytes = await thumbnailFile.readAsBytes();
          } else {
            throw Exception('Thumbnail file data is missing');
          }

          thumbnailUrl = await _mediaService.uploadThumbnail(
            userId: userId,
            postId: postId,
            thumbnailBytes: thumbnailFileBytes,
          );
        }

        return {
          'videoUrl': videoUrl,
          if (thumbnailUrl != null) 'thumbnailUrl': thumbnailUrl,
        };
      } else {
        throw Exception('Either videoFile or videoBytes must be provided');
      }

      // Web path: if we reached here, web bytes branch was selected above
      // Generate postId for video upload
      final postId = 'post_${DateTime.now().millisecondsSinceEpoch}';

      // Upload video using MediaUploadService (bytes)
      final videoUrl = await _mediaService.uploadPostVideo(
        userId: userId,
        postId: postId,
        videoBytes: videoFileBytes,
        originalFileName: originalVideoFileName,
      );

      String? thumbnailUrl;

      // Upload thumbnail if provided
      if (thumbnailFile != null || thumbnailBytes != null) {
        Uint8List thumbnailFileBytes;

        if (thumbnailBytes != null && thumbnailFileName != null) {
          thumbnailFileBytes = thumbnailBytes;
        } else if (thumbnailFile != null) {
          thumbnailFileBytes = await thumbnailFile.readAsBytes();
        } else {
          throw Exception('Thumbnail file data is missing');
        }

        thumbnailUrl = await _mediaService.uploadThumbnail(
          userId: userId,
          postId: postId,
          thumbnailBytes: thumbnailFileBytes,
        );
      }

      return {
        'videoUrl': videoUrl,
        if (thumbnailUrl != null) 'thumbnailUrl': thumbnailUrl,
      };
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Video upload error details: $e');
        debugPrint('Error type: ${e.runtimeType}');
      }

      // Provide more specific error messages
      final errorString = e.toString().toLowerCase();
      if (errorString.contains('network') ||
          errorString.contains('connection')) {
        throw Exception(
          'Network connection error. Please check your internet connection.',
        );
      } else if (errorString.contains('unauthorized') ||
          errorString.contains('401')) {
        throw Exception('Unauthorized access. Please log in again.');
      } else if (errorString.contains('forbidden') ||
          errorString.contains('403')) {
        throw Exception('Access forbidden. Please check your permissions.');
      } else if (errorString.contains('timeout')) {
        throw Exception(
          'Upload timeout. Please try again with a smaller file.',
        );
      } else if (errorString.contains('file size') ||
          errorString.contains('too large') ||
          errorString.contains('payload too large') ||
          errorString.contains('content-length')) {
        // Differentiate between our absolute cap (200MB) and upstream upload limits (~100MB)
        if (errorString.contains('200mb') ||
            errorString.contains('200 mb') ||
            errorString.contains('maxvideosize')) {
          throw Exception(
            'Video file is larger than 200MB. Files above 200MB cannot be uploaded.',
          );
        }
        throw Exception(
          'Upload size limit reached (100MB). Please trim the video or reduce resolution.',
        );
      } else if (errorString.contains('bucket')) {
        throw Exception('Storage bucket error. Please contact support.');
      } else {
        throw Exception('Failed to upload video: $e');
      }
    }
  }

  // Upload image file - Now using Cloudflare R2
  Future<String> uploadImage({
    required dynamic imageFile, // File on mobile, bytes on web
    required String userId,
    Function(double)? onProgress,
    Uint8List? imageBytes, // For web uploads
    String? fileName, // For web uploads
  }) async {
    try {
      Uint8List bytes;
      String originalFileName;

      if (imageBytes != null && fileName != null) {
        // Web upload using bytes
        bytes = imageBytes;
        originalFileName = fileName;
      } else if (imageFile != null) {
        // Mobile upload using File
        if (kIsWeb) {
          throw Exception(
            'File objects not supported on web. Use imageBytes instead.',
          );
        }
        bytes = await imageFile.readAsBytes();
        originalFileName = path.basename(imageFile.path);
      } else {
        throw Exception('Either imageFile or imageBytes must be provided');
      }

      // NSFW moderation before upload
      try {
        final mod = await _moderationService.checkImage(bytes);
        if (!mod.isAllowed) {
          await _moderationService.recordStrike(
            userId: userId,
            type: 'image_nsfw',
            score: mod.nsfwScore,
            details: {
              'file': originalFileName,
              'reason': 'Explicit sexual content detected',
            },
          );
          throw Exception(
            'Upload rejected: explicit sexual content is not allowed. Accounts posting NSFW may be banned.',
          );
        }
      } catch (_) {
        // If moderation fails, proceed without blocking
      }

      // Use MediaUploadService for post images
      return await _mediaService.uploadPostImage(
        userId: userId,
        postId: 'post_${DateTime.now().millisecondsSinceEpoch}',
        imageBytes: bytes,
        originalFileName: originalFileName,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Image upload error details: $e');
        debugPrint('Error type: ${e.runtimeType}');
      }

      // Provide more specific error messages
      final errorString = e.toString().toLowerCase();
      if (errorString.contains('network') ||
          errorString.contains('connection')) {
        throw Exception(LocalizationService.t('network_connection_error'));
      } else if (errorString.contains('unauthorized') ||
          errorString.contains('401')) {
        throw Exception(LocalizationService.t('unauthorized_access'));
      } else if (errorString.contains('forbidden') ||
          errorString.contains('403')) {
        throw Exception(LocalizationService.t('access_forbidden'));
      } else if (errorString.contains('timeout')) {
        throw Exception(
          LocalizationService.t('upload_timeout_try_smaller_file'),
        );
      } else if (errorString.contains('file size') ||
          errorString.contains('too large')) {
        throw Exception(
          LocalizationService.t(
            'file_size_exceeds_limit',
          ).replaceAll('{limit}', '50'),
        );
      } else if (errorString.contains('bucket')) {
        throw Exception(LocalizationService.t('storage_bucket_error'));
      } else {
        throw Exception('${LocalizationService.t('failed_upload_image')}: $e');
      }
    }
  }

  // Upload audio file
  Future<String> uploadAudio({
    required dynamic audioFile,
    required String userId,
    Function(double)? onProgress,
    Uint8List? audioBytes, // For web uploads
    String? fileName, // For web uploads
  }) async {
    try {
      if (audioBytes != null && fileName != null) {
        // Web upload using bytes
        final postId = 'post_${DateTime.now().millisecondsSinceEpoch}';
        return await _mediaService.uploadPostAudio(
          userId: userId,
          postId: postId,
          audioBytes: audioBytes,
          originalFileName: fileName,
        );
      } else if (audioFile != null) {
        // Mobile upload using File (streaming)
        final originalFileName = path.basename(audioFile.path);
        final postId = 'post_${DateTime.now().millisecondsSinceEpoch}';
        return await _mediaService.uploadPostAudioFile(
          userId: userId,
          postId: postId,
          file: File(audioFile.path as String),
          originalFileName: originalFileName,
        );
      } else {
        throw Exception('Either audioFile or audioBytes must be provided');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Audio upload error details: $e');
        debugPrint('Error type: ${e.runtimeType}');
      }

      // Provide more specific error messages
      final errorString = e.toString().toLowerCase();
      if (errorString.contains('network') ||
          errorString.contains('connection')) {
        throw Exception(LocalizationService.t('network_connection_error'));
      } else if (errorString.contains('unauthorized') ||
          errorString.contains('401')) {
        throw Exception(LocalizationService.t('unauthorized_access'));
      } else if (errorString.contains('forbidden') ||
          errorString.contains('403')) {
        throw Exception(LocalizationService.t('access_forbidden'));
      } else if (errorString.contains('timeout')) {
        throw Exception(
          LocalizationService.t('upload_timeout_try_smaller_file'),
        );
      } else if (errorString.contains('file size') ||
          errorString.contains('too large')) {
        throw Exception(
          LocalizationService.t(
            'file_size_exceeds_limit',
          ).replaceAll('{limit}', '100'),
        );
      } else if (errorString.contains('bucket')) {
        throw Exception(LocalizationService.t('storage_bucket_error'));
      } else {
        throw Exception('${LocalizationService.t('failed_upload_audio')}: $e');
      }
    }
  }

  // Upload avatar image - Now using Cloudflare R2
  Future<String> uploadAvatar({
    dynamic avatarFile, // Can be File or XFile
    required String userId,
    Uint8List? avatarBytes, // For web uploads
    String? fileName, // For web uploads
  }) async {
    try {
      Uint8List bytes;
      String originalFileName;

      if (avatarBytes != null && fileName != null) {
        // Web upload using bytes
        bytes = avatarBytes;
        originalFileName = fileName;
      } else if (avatarFile != null) {
        // Mobile upload using File
        if (kIsWeb) {
          throw Exception(
            'File objects not supported on web. Use avatarBytes instead.',
          );
        }
        if (kIsWeb) {
          throw UnsupportedError(
            'Use avatarBytes and fileName for web uploads',
          );
        } else {
          bytes = await avatarFile.readAsBytes();
          originalFileName = path.basename(avatarFile.path);
        }
      } else {
        throw Exception('Either avatarFile or avatarBytes must be provided');
      }

      // NSFW moderation before upload
      try {
        final mod = await _moderationService.checkImage(bytes);
        if (!mod.isAllowed) {
          await _moderationService.recordStrike(
            userId: userId,
            type: 'avatar_nsfw',
            score: mod.nsfwScore,
            details: {
              'file': originalFileName,
              'reason': 'Explicit sexual content detected',
            },
          );
          throw Exception(
            'Upload rejected: explicit sexual content is not allowed for profile images.',
          );
        }
      } catch (_) {
        // If moderation fails, proceed without blocking
      }

      // Use MediaUploadService for profile images
      return await _mediaService.uploadProfileImage(
        userId: userId,
        imageBytes: bytes,
        originalFileName: originalFileName,
      );
    } catch (e) {
      throw Exception('${LocalizationService.t('failed_upload_avatar')}: $e');
    }
  }

  // Validate file size
  bool validateFileSize(dynamic file, int maxSizeInMB) {
    if (kIsWeb) {
      // Web validation would need to be handled differently
      return true; // Skip validation on web for now
    } else {
      final fileSizeInMB = file.lengthSync() / (1024 * 1024);
      return fileSizeInMB <= maxSizeInMB;
    }
  }

  // Get file size
  Future<int> getFileSize(dynamic file) async {
    if (kIsWeb) {
      return 0; // Web file size handling would be different
    } else {
      return await file.length();
    }
  }

  // Upload from bytes - Now using Cloudflare R2
  Future<String> uploadFromBytes({
    required Uint8List bytes,
    required String fileName,
    required String bucket,
    required String userId, // Required for R2 uploads
    String? contentType,
    Function(double)? onProgress,
  }) async {
    try {
      // Generate postId for uploads that need it
      final postId = 'post_${DateTime.now().millisecondsSinceEpoch}';

      // Route to appropriate MediaUploadService method based on bucket
      if (bucket == SupabaseConfig.avatarsBucket) {
        return await _mediaService.uploadProfileImage(
          userId: userId,
          imageBytes: bytes,
          originalFileName: fileName,
        );
      } else if (bucket == SupabaseConfig.imagesBucket) {
        return await _mediaService.uploadPostImage(
          userId: userId,
          postId: postId,
          imageBytes: bytes,
          originalFileName: fileName,
        );
      } else if (bucket == SupabaseConfig.videosBucket) {
        return await _mediaService.uploadPostVideo(
          userId: userId,
          postId: postId,
          videoBytes: bytes,
          originalFileName: fileName,
        );
      } else if (bucket == SupabaseConfig.audiosBucket) {
        return await _mediaService.uploadAudio(
          userId: userId,
          postId: postId,
          audioBytes: bytes,
          originalFileName: fileName,
        );
      } else {
        throw Exception('Unsupported bucket: $bucket');
      }
    } catch (e) {
      throw Exception('Failed to upload from bytes: $e');
    }
  }

  // Download file
  Future<Uint8List> downloadFile(String bucket, String fileName) async {
    try {
      return await _client.storage.from(bucket).download(fileName);
    } catch (e) {
      throw Exception('Failed to download file: $e');
    }
  }

  // Delete file
  Future<void> deleteFile(String bucket, String fileName) async {
    try {
      await _client.storage.from(bucket).remove([fileName]);
    } catch (e) {
      throw Exception('Failed to delete file: $e');
    }
  }

  // Get content type from file path
  String _getContentType(String filePath) {
    final extension = path.extension(filePath).toLowerCase();

    switch (extension) {
      // Images
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.png':
        return 'image/png';
      case '.gif':
        return 'image/gif';
      case '.webp':
        return 'image/webp';
      case '.svg':
        return 'image/svg+xml';

      // Videos
      case '.mp4':
        return 'video/mp4';
      case '.mov':
        return 'video/quicktime';
      case '.avi':
        return 'video/x-msvideo';
      case '.webm':
        return 'video/webm';
      case '.mkv':
        return 'video/x-matroska';

      // Audio
      case '.mp3':
        return 'audio/mpeg';
      case '.wav':
        return 'audio/wav';
      case '.aac':
        return 'audio/aac';
      case '.ogg':
        return 'audio/ogg';
      case '.m4a':
        return 'audio/mp4';

      default:
        return 'application/octet-stream';
    }
  }

  // Validate file type
  bool validateFileType(String filePath, List<String> allowedExtensions) {
    final extension = path.extension(filePath).toLowerCase();
    return allowedExtensions.contains(extension);
  }

  // Compress image (basic implementation)
  Future<dynamic> compressImage(dynamic imageFile, {int quality = 85}) async {
    // This is a placeholder - in a real app, you'd use image compression packages
    // like flutter_image_compress or similar
    return imageFile;
  }

  // Generate thumbnail from video
  Future<dynamic> generateVideoThumbnail(dynamic videoFile) async {
    // This is a placeholder - in a real app, you'd use video_thumbnail package
    // or similar to generate thumbnails from videos
    return null;
  }
}
