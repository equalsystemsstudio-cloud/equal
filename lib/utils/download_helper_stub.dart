/// Stubbed downloadJson for non-web platforms; no-op in this build.
Future<void> downloadJson(String jsonStr, String filename) async {
  // Download not supported on non-web in this build.
}

Future<void> downloadBytes(List<int> bytes, String filename, {String? mimeType}) async {
  // Download not supported on non-web in this build.
}