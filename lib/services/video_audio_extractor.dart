import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'video_audio_extractor_mobile_impl.dart'
    if (dart.library.html) 'video_audio_extractor_web_impl.dart'
    as impl;

class VideoAudioExtractor {
  static Future<Uint8List> extractWavSnippetFromBytes(
    Uint8List input, {
    int seconds = 20,
    int offsetSeconds = 0,
  }) {
    return impl.extractWavSnippetFromBytesImpl(
      input,
      seconds: seconds,
      offsetSeconds: offsetSeconds,
    );
  }

  static Future<Uint8List> extractWavSnippetFromAudioBytes(
    Uint8List input, {
    int seconds = 20,
    int offsetSeconds = 0,
  }) {
    return impl.extractWavSnippetFromAudioBytesImpl(
      input,
      seconds: seconds,
      offsetSeconds: offsetSeconds,
    );
  }
}
