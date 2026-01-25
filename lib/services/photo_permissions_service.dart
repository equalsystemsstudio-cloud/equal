import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

/// Centralized helper for handling PhotoManager permissions and platform guards.
class PhotoPermissionsService {
  /// Ensures photo library access is granted on supported platforms.
  /// Returns true if permission is granted, false otherwise.
  /// Shows user-facing guidance when access is denied or unsupported.
  static Future<bool> ensurePhotoAccess(BuildContext context) async {
    // Web is not supported by photo_manager for saving to gallery.
    if (kIsWeb) {
      _showInfo(context, 'Saving to gallery is not supported on Web.');
      return false;
    }

    // Guard unsupported desktop platforms.
    if (!Platform.isAndroid && !Platform.isIOS && !Platform.isMacOS) {
      _showInfo(context, 'Saving to gallery is not supported on this platform.');
      return false;
    }

    final PermissionState ps = await PhotoManager.requestPermissionExtend();
    if (ps.isAuth) {
      return true;
    }

    // Permission not granted: guide the user to settings.
    if (!context.mounted) {
      return false;
    }
    _showPermissionDenied(context);
    return false;
  }

  static void _showInfo(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  static void _showPermissionDenied(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Allow photo library access to save to gallery'),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'Settings',
          onPressed: () {
            PhotoManager.openSetting();
          },
        ),
      ),
    );
  }
}