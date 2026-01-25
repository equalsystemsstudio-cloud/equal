// Stub for non-web platforms to satisfy conditional imports
import 'dart:typed_data';
import 'package:flutter_webrtc/flutter_webrtc.dart' show MediaStream;

class WebRecorderSession {
  final MediaStream? stream;
  final List<Object> chunks;
  final String mime;
  WebRecorderSession({this.stream, List<Object>? chunks, this.mime = 'video/webm'})
      : chunks = chunks ?? const [];
}

Future<MediaStream> webGetUserMedia(Map<String, dynamic> constraints) async {
  throw UnsupportedError('webGetUserMedia is only available on web');
}

Future<void> webAttachRenderer(dynamic renderer, MediaStream? stream) async {}

WebRecorderSession webStartRecording(MediaStream stream, {int timesliceMs = 0}) {
  throw UnsupportedError('webStartRecording is only available on web');
}

Future<WebRecorderSession> webStartRecordingAsync(dynamic stream, { int timesliceMs = 0, Map<String, dynamic>? constraints }) async {
  throw UnsupportedError('webStartRecordingAsync is only available on web');
}

Future<Uint8List> webStopRecording(WebRecorderSession session) async {
  throw UnsupportedError('webStopRecording is only available on web');
}