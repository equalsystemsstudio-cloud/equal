import 'dart:typed_data';
import 'package:universal_io/io.dart' show File;
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import 'localization_service.dart';

/// Service for handling media uploads to Supabase Storage
/// Primary storage solution for all media files
class MediaUploadService {
  static final MediaUploadService _instance = MediaUploadService._internal();
  factory MediaUploadService() => _instance;
  MediaUploadService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;

  /// Upload profile image to Supabase Storage
  Future<String> uploadProfileImage({
    required String userId,
    required Uint8List imageBytes,
    String? originalFileName,
  }) async {
    try {
      // Validate file size
      if (imageBytes.length > SupabaseConfig.maxImageSize) {
        final limit = (SupabaseConfig.maxImageSize ~/ (1024 * 1024)).toString();
        throw Exception(
          LocalizationService.t(
            'file_size_exceeds_limit',
          ).replaceAll('{limit}', limit),
        );
      }

      // Generate unique filename
      final extension = _getFileExtension(originalFileName) ?? 'jpg';
      final fileName =
          '${userId}_${DateTime.now().millisecondsSinceEpoch}.$extension';
      final filePath = '$userId/$fileName';

      // Upload to Supabase storage
      await _supabase.storage
          .from(SupabaseConfig.profileImagesBucket)
          .uploadBinary(
            filePath,
            imageBytes,
            fileOptions: FileOptions(
              contentType: _getContentType(extension),
              upsert: false,
              cacheControl: '3600',
            ),
          );

      final publicUrl = _supabase.storage
          .from(SupabaseConfig.profileImagesBucket)
          .getPublicUrl(filePath);

      return publicUrl;
    } catch (e) {
      throw Exception('Failed to upload profile image: $e');
    }
  }

  /// Upload post image to Supabase Storage
  Future<String> uploadPostImage({
    required String userId,
    required String postId,
    required Uint8List imageBytes,
    String? originalFileName,
  }) async {
    try {
      // Validate file size
      if (imageBytes.length > SupabaseConfig.maxImageSize) {
        final limit = (SupabaseConfig.maxImageSize ~/ (1024 * 1024)).toString();
        throw Exception(
          LocalizationService.t(
            'file_size_exceeds_limit',
          ).replaceAll('{limit}', limit),
        );
      }

      // Generate unique filename
      final extension = _getFileExtension(originalFileName) ?? 'jpg';
      final fileName =
          '$userId/${postId}_${DateTime.now().millisecondsSinceEpoch}.$extension';

      // Upload to Supabase storage
      await _supabase.storage
          .from(SupabaseConfig.postImagesBucket)
          .uploadBinary(
            fileName,
            imageBytes,
            fileOptions: FileOptions(
              contentType: _getContentType(extension),
              upsert: false,
              cacheControl: '3600',
            ),
          );

      final publicUrl = _supabase.storage
          .from(SupabaseConfig.postImagesBucket)
          .getPublicUrl(fileName);

      return publicUrl;
    } catch (e) {
      throw Exception('Failed to upload post image: $e');
    }
  }

  /// Upload post video to Supabase Storage
  Future<String> uploadPostVideo({
    required String userId,
    required String postId,
    required Uint8List videoBytes,
    String? originalFileName,
  }) async {
    try {
      // Validate file size
      if (videoBytes.length > SupabaseConfig.maxVideoSize) {
        final limit = (SupabaseConfig.maxVideoSize ~/ (1024 * 1024)).toString();
        throw Exception(
          LocalizationService.t(
            'file_size_exceeds_limit',
          ).replaceAll('{limit}', limit),
        );
      }

      // Generate unique filename
      final extension = _getFileExtension(originalFileName) ?? 'mp4';
      final fileName =
          '$userId/${postId}_${DateTime.now().millisecondsSinceEpoch}.$extension';

      // Upload to Supabase storage
      await _supabase.storage
          .from(SupabaseConfig.postVideosBucket)
          .uploadBinary(
            fileName,
            videoBytes,
            fileOptions: FileOptions(
              contentType: _getVideoContentType(extension),
              upsert: false,
              cacheControl: '3600',
            ),
          );

      final publicUrl = _supabase.storage
          .from(SupabaseConfig.postVideosBucket)
          .getPublicUrl(fileName);

      return publicUrl;
    } catch (e) {
      throw Exception('Failed to upload post video: $e');
    }
  }

  /// Upload post video to Supabase Storage (mobile File streaming)
  Future<String> uploadPostVideoFile({
    required String userId,
    required String postId,
    required File file,
    String? originalFileName,
  }) async {
    try {
      // Generate unique filename using provided name or file path
      final extension =
          _getFileExtension(originalFileName ?? path.basename(file.path)) ??
          'mp4';
      final fileName =
          '$userId/${postId}_${DateTime.now().millisecondsSinceEpoch}.$extension';

      // Upload using File (streaming on mobile)
      await _supabase.storage
          .from(SupabaseConfig.postVideosBucket)
          .upload(fileName, file);

      final publicUrl = _supabase.storage
          .from(SupabaseConfig.postVideosBucket)
          .getPublicUrl(fileName);

      return publicUrl;
    } catch (e) {
      throw Exception('Failed to upload post video (file): $e');
    }
  }

  /// Upload post audio to Supabase Storage
  Future<String> uploadPostAudio({
    required String userId,
    required String postId,
    required Uint8List audioBytes,
    String? originalFileName,
  }) async {
    try {
      // Validate file size
      if (audioBytes.length > SupabaseConfig.maxAudioSize) {
        final limit = (SupabaseConfig.maxAudioSize ~/ (1024 * 1024)).toString();
        throw Exception(
          LocalizationService.t(
            'file_size_exceeds_limit',
          ).replaceAll('{limit}', limit),
        );
      }

      // Generate unique filename
      final extension = _getFileExtension(originalFileName) ?? 'mp3';
      final fileName =
          '$userId/${postId}_${DateTime.now().millisecondsSinceEpoch}.$extension';

      // Upload to Supabase storage
      await _supabase.storage
          .from(SupabaseConfig.postAudioBucket)
          .uploadBinary(
            fileName,
            audioBytes,
            fileOptions: FileOptions(
              contentType: _getAudioContentType(extension),
              upsert: false,
              cacheControl: '3600',
            ),
          );

      final publicUrl = _supabase.storage
          .from(SupabaseConfig.postAudioBucket)
          .getPublicUrl(fileName);

      return publicUrl;
    } catch (e) {
      throw Exception('Failed to upload post audio: $e');
    }
  }

  /// Upload post audio to Supabase Storage (mobile File streaming)
  Future<String> uploadPostAudioFile({
    required String userId,
    required String postId,
    required File file,
    String? originalFileName,
  }) async {
    try {
      // Generate unique filename using provided name or file path
      final extension =
          _getFileExtension(originalFileName ?? path.basename(file.path)) ??
          'mp3';
      final fileName =
          '$userId/${postId}_${DateTime.now().millisecondsSinceEpoch}.$extension';

      // Upload using File (streaming on mobile)
      await _supabase.storage
          .from(SupabaseConfig.postAudioBucket)
          .upload(fileName, file);

      final publicUrl = _supabase.storage
          .from(SupabaseConfig.postAudioBucket)
          .getPublicUrl(fileName);

      return publicUrl;
    } catch (e) {
      throw Exception('Failed to upload post audio (file): $e');
    }
  }

  /// Upload video thumbnail to Supabase Storage
  Future<String> uploadVideoThumbnail({
    required String userId,
    required String postId,
    required Uint8List thumbnailBytes,
  }) async {
    try {
      // Generate unique filename
      final fileName =
          '$userId/${postId}_thumbnail_${DateTime.now().millisecondsSinceEpoch}.jpg';

      // Upload to Supabase storage
      await _supabase.storage
          .from(SupabaseConfig.thumbnailsBucket)
          .uploadBinary(
            fileName,
            thumbnailBytes,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: false,
              cacheControl: '3600',
            ),
          );

      final publicUrl = _supabase.storage
          .from(SupabaseConfig.thumbnailsBucket)
          .getPublicUrl(fileName);

      return publicUrl;
    } catch (e) {
      throw Exception('Failed to upload video thumbnail: $e');
    }
  }

  /// Delete file from Supabase Storage
  Future<void> deleteFile(String fileUrl) async {
    try {
      // Extract bucket and filename from Supabase URL
      final uri = Uri.parse(fileUrl);
      final pathSegments = uri.pathSegments;

      if (pathSegments.length < 4) {
        throw Exception('Invalid Supabase file URL format');
      }

      // Supabase URL format: /storage/v1/object/public/{bucket}/{filename}
      final bucket = pathSegments[4];
      final fileName = pathSegments.sublist(5).join('/');

      await _supabase.storage.from(bucket).remove([fileName]);
    } catch (e) {
      throw Exception('Failed to delete file: $e');
    }
  }

  /// Upload file from XFile (ImagePicker result)
  Future<String> uploadFromXFile({
    required XFile file,
    required String bucket,
    required String userId,
    String? postId,
  }) async {
    try {
      final bytes = await file.readAsBytes();
      final fileName = file.name;

      switch (bucket) {
        case SupabaseConfig.profileImagesBucket:
          return await uploadProfileImage(
            userId: userId,
            imageBytes: bytes,
            originalFileName: fileName,
          );
        case SupabaseConfig.postImagesBucket:
          return await uploadPostImage(
            userId: userId,
            postId: postId ?? 'unknown',
            imageBytes: bytes,
            originalFileName: fileName,
          );
        case SupabaseConfig.postVideosBucket:
          return await uploadPostVideo(
            userId: userId,
            postId: postId ?? 'unknown',
            videoBytes: bytes,
            originalFileName: fileName,
          );
        case SupabaseConfig.postAudioBucket:
          return await uploadPostAudio(
            userId: userId,
            postId: postId ?? 'unknown',
            audioBytes: bytes,
            originalFileName: fileName,
          );
        default:
          throw Exception('Unsupported bucket: $bucket');
      }
    } catch (e) {
      throw Exception('Failed to upload file from XFile: $e');
    }
  }

  /// Upload file from File object
  Future<String> uploadFromFile({
    required dynamic file,
    required String bucket,
    required String userId,
    String? postId,
  }) async {
    try {
      final bytes = await file.readAsBytes();
      final fileName = path.basename(file.path);

      switch (bucket) {
        case SupabaseConfig.profileImagesBucket:
          return await uploadProfileImage(
            userId: userId,
            imageBytes: bytes,
            originalFileName: fileName,
          );
        case SupabaseConfig.postImagesBucket:
          return await uploadPostImage(
            userId: userId,
            postId: postId ?? 'unknown',
            imageBytes: bytes,
            originalFileName: fileName,
          );
        case SupabaseConfig.postVideosBucket:
          return await uploadPostVideo(
            userId: userId,
            postId: postId ?? 'unknown',
            videoBytes: bytes,
            originalFileName: fileName,
          );
        case SupabaseConfig.postAudioBucket:
          return await uploadPostAudio(
            userId: userId,
            postId: postId ?? 'unknown',
            audioBytes: bytes,
            originalFileName: fileName,
          );
        default:
          throw Exception('Unsupported bucket: $bucket');
      }
    } catch (e) {
      throw Exception('Failed to upload file: $e');
    }
  }

  // Helper methods

  String? _getFileExtension(String? fileName) {
    if (fileName == null) return null;
    final lastDot = fileName.lastIndexOf('.');
    if (lastDot == -1) return null;
    return fileName.substring(lastDot + 1).toLowerCase();
  }

  String _getContentType(String extension) {
    switch (extension.toLowerCase()) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'svg':
        return 'image/svg+xml';
      default:
        return 'image/jpeg';
    }
  }

  String _getVideoContentType(String extension) {
    switch (extension.toLowerCase()) {
      case 'mp4':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'avi':
        return 'video/x-msvideo';
      case 'webm':
        return 'video/webm';
      case 'mkv':
        return 'video/x-matroska';
      case 'm4v':
        return 'video/x-m4v';
      case 'ogv':
        return 'video/ogg';
      case '3gp':
        return 'video/3gpp';
      default:
        return 'video/mp4';
    }
  }

  String _getAudioContentType(String extension) {
    switch (extension.toLowerCase()) {
      case 'mp3':
        return 'audio/mpeg';
      case 'wav':
        return 'audio/wav';
      case 'ogg':
        return 'audio/ogg';
      case 'm4a':
        return 'audio/mp4';
      default:
        return 'audio/mpeg';
    }
  }

  // Wrapper methods for backward compatibility

  /// Upload thumbnail (wrapper for uploadVideoThumbnail)
  Future<String> uploadThumbnail({
    required String userId,
    required String postId,
    required Uint8List thumbnailBytes,
  }) async {
    return await uploadVideoThumbnail(
      userId: userId,
      postId: postId,
      thumbnailBytes: thumbnailBytes,
    );
  }

  /// Upload audio (wrapper for uploadPostAudio)
  Future<String> uploadAudio({
    required String userId,
    required String postId,
    required Uint8List audioBytes,
    String? originalFileName,
  }) async {
    return await uploadPostAudio(
      userId: userId,
      postId: postId,
      audioBytes: audioBytes,
      originalFileName: originalFileName,
    );
  }
}
