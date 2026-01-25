import 'dart:html' as html;

/// Triggers a download of the provided JSON string as a file in the browser.
Future<void> downloadJson(String jsonStr, String filename) async {
  final blob = html.Blob([jsonStr], 'application/json');
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)..download = filename;
  anchor.click();
  html.Url.revokeObjectUrl(url);
}

/// Triggers a download of the provided bytes as a file in the browser.
Future<void> downloadBytes(List<int> bytes, String filename, {String? mimeType}) async {
  final blob = html.Blob([bytes], mimeType ?? 'application/octet-stream');
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)..download = filename;
  anchor.click();
  html.Url.revokeObjectUrl(url);
}