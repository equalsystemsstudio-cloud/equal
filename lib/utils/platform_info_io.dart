import 'dart:io' show Platform;

/// Returns true if running on a mobile platform (Android/iOS)
bool isMobilePlatform() {
  return Platform.isAndroid || Platform.isIOS;
}