import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_webrtc/flutter_webrtc.dart' show MediaStream, navigator;
import 'dart:html' as html;
import 'dart:js_util' as js_util;
import 'package:js/js.dart' as js;

class WebRecorderSession {
  final html.MediaRecorder recorder;
  final List<html.Blob> chunks;
  final String mime;
  // Keep a reference to the html.MediaStream used for recording so we can stop tracks later
  final html.MediaStream? stream;
  WebRecorderSession(this.recorder, this.chunks, this.mime, [this.stream]);
}

Future<MediaStream> webGetUserMedia(Map<String, dynamic> constraints) async {
  try {
    debugPrint('webGetUserMedia: constraints=${constraints}');
    final stream = await navigator.mediaDevices.getUserMedia(constraints);
    try {
      final v = stream.getVideoTracks().length;
      final a = stream.getAudioTracks().length;
      debugPrint('webGetUserMedia: acquired stream tracks v=${v}, a=${a}');
    } catch (_) {}
    return stream;
  } catch (e) {
    // Extract DOM-style error information if available
    try {
      final name = js_util.getProperty(e as Object, 'name');
      final message = js_util.getProperty(e as Object, 'message');
      debugPrint('webGetUserMedia: error name=${name}, message=${message}, constraints=${constraints}');
    } catch (_) {
      debugPrint('webGetUserMedia: error ${e.toString()}, constraints=${constraints}');
    }
    rethrow;
  }
}

// Separate getter for a native html.MediaStream for cases like MediaRecorder
Future<html.MediaStream> webGetUserMediaHtml(Map<String, dynamic> constraints) async {
  final mediaDevices = html.window.navigator.mediaDevices;
  if (mediaDevices == null) {
    throw StateError('navigator.mediaDevices is not available');
  }
  // Page visibility can affect device capture on some browsers (especially mobile Safari)
  try {
    debugPrint('webGetUserMediaHtml: visibility=${html.document.visibilityState}');
  } catch (_) {}
  // Enumerate devices for context
  try {
    final ds = await mediaDevices.enumerateDevices();
    final cams = ds.where((d) => d.kind == 'videoinput').length;
    final mics = ds.where((d) => d.kind == 'audioinput').length;
    debugPrint('webGetUserMediaHtml: devices cameras=${cams}, mics=${mics}');
  } catch (_) {}
  try {
    debugPrint('webGetUserMediaHtml: constraints=${constraints}');
    final stream = await mediaDevices.getUserMedia(constraints);
    try {
      final v = stream.getVideoTracks().length;
      final a = stream.getAudioTracks().length;
      debugPrint('webGetUserMediaHtml: acquired html stream tracks v=${v}, a=${a}');
    } catch (_) {}
    return stream;
  } catch (e) {
    try {
      final name = js_util.getProperty(e as Object, 'name');
      final message = js_util.getProperty(e as Object, 'message');
      debugPrint('webGetUserMediaHtml: error name=${name}, message=${message}, constraints=${constraints}');
    } catch (_) {
      debugPrint('webGetUserMediaHtml: error ${e.toString()}, constraints=${constraints}');
    }
    rethrow;
  }
}

Future<void> webAttachRenderer(dynamic renderer, dynamic stream) async {
  // renderer is RTCVideoRenderer; accept either flutter_webrtc or html stream
  try {
    renderer.srcObject = stream;
  } catch (_) {}
}

String webPreferredMime() {
  final codecs = [
    'video/webm;codecs=vp9,opus',
    'video/webm;codecs=vp8,opus',
    'video/webm'
  ];
  for (final c in codecs) {
    if (html.MediaRecorder.isTypeSupported(c)) return c;
  }
  return 'video/webm';
}

// New async variant that ensures we pass an html.MediaStream to MediaRecorder
Future<WebRecorderSession> webStartRecordingAsync(
  dynamic stream, {
  int timesliceMs = 0,
  Map<String, dynamic>? constraints,
}) async {
  final mime = webPreferredMime();

  html.MediaStream? htmlStream;

  if (stream != null) {
    // Try to unwrap flutter_webrtc's MediaStreamWeb into a dart:html MediaStream
    try {
      final candidate = js_util.getProperty(stream, 'jsStream');
      if (candidate is html.MediaStream) {
        htmlStream = candidate;
      }
    } catch (e) {}
    if (htmlStream == null) {
      try {
        final candidate2 = js_util.getProperty(stream, 'mediaStream');
        if (candidate2 is html.MediaStream) {
          htmlStream = candidate2;
        }
      } catch (e) {}
    }
    // Fallback to using the provided stream directly (previous working behavior)
    if (htmlStream == null) {
      debugPrint('webStartRecordingAsync: could not derive html.MediaStream from provided stream; falling back to direct stream');
      // Use the synchronous path that accepts dynamic stream and has worked previously
      final session = webStartRecording(stream, timesliceMs: timesliceMs);
      return session;
    }
  } else {
    // No stream provided: request a single native html stream for both preview and recording
    if (constraints == null) {
      throw ArgumentError('constraints are required when no stream is provided');
    }
    try {
      htmlStream = await webGetUserMediaHtml(constraints);
      // Attach immediate diagnostics
      try {
        final vTracks = htmlStream.getVideoTracks();
        final aTracks = htmlStream.getAudioTracks();
        debugPrint('webStartRecordingAsync: htmlStream tracks v=${vTracks.length}, a=${aTracks.length}');
      } catch (_) {}
    } catch (e) {
      debugPrint('webStartRecordingAsync: getUserMedia failed: ${e.toString()}');
      // Surface the specific NotReadableError cause to the caller
      rethrow;
    }
  }

  // Listen for track ended events to understand device interruptions
  try {
    for (final t in htmlStream.getTracks()) {
      js_util.callMethod(t, 'addEventListener', [
        'ended',
        js.allowInterop((_) {
          try {
            final kind = js_util.getProperty(t as Object, 'kind');
            final state = js_util.getProperty(t as Object, 'readyState');
            debugPrint('MediaStreamTrack ended: kind=${kind}, readyState=${state}');
          } catch (_) {
            debugPrint('MediaStreamTrack ended');
          }
        })
      ]);
    }
  } catch (_) {}

  html.MediaRecorder recorder;
  try {
    recorder = html.MediaRecorder(htmlStream!, {'mimeType': mime});
  } catch (e) {
    try {
      final name = js_util.getProperty(e as Object, 'name');
      final message = js_util.getProperty(e as Object, 'message');
      debugPrint('MediaRecorder ctor failed: name=${name}, message=${message}, mime=${mime}');
    } catch (_) {
      debugPrint('MediaRecorder ctor failed: ${e.toString()}, mime=${mime}');
    }
    rethrow;
  }
  final chunks = <html.Blob>[];

  // Diagnostics: recorder lifecycle events
  try {
    js_util.callMethod(recorder, 'addEventListener', [
      'start',
      js.allowInterop((_) {
        debugPrint('MediaRecorder event: start');
      })
    ]);
  } catch (_) {}

  try {
    js_util.callMethod(recorder, 'addEventListener', [
      'stop',
      js.allowInterop((_) {
        debugPrint('MediaRecorder event: stop');
      })
    ]);
  } catch (_) {}

  try {
    js_util.callMethod(recorder, 'addEventListener', [
      'pause',
      js.allowInterop((_) {
        debugPrint('MediaRecorder event: pause');
      })
    ]);
  } catch (_) {}

  try {
    js_util.callMethod(recorder, 'addEventListener', [
      'resume',
      js.allowInterop((_) {
        debugPrint('MediaRecorder event: resume');
      })
    ]);
  } catch (_) {}

  // Diagnostics: recorder 'error' events
  js_util.callMethod(recorder, 'addEventListener', [
    'error',
    js.allowInterop((event) {
      final name = js_util.getProperty(event as Object, 'name');
      final message = js_util.getProperty(event as Object, 'message');
      debugPrint('MediaRecorder error: name=${name}, message=${message}');
    })
  ]);

  // Attach event listener for 'dataavailable'
  js_util.callMethod(recorder, 'addEventListener', [
    'dataavailable',
    js.allowInterop((event) {
      final data = js_util.getProperty(event as Object, 'data');
      final time = DateTime.now().toIso8601String();
      if (data is html.Blob) {
        if (data.size > 0) {
          chunks.add(data);
          debugPrint('MediaRecorder dataavailable (${time}): size=${data.size} totalChunks=${chunks.length}');
        } else {
          debugPrint('MediaRecorder dataavailable (${time}): empty blob');
        }
      } else {
        debugPrint('MediaRecorder dataavailable (${time}): non-blob');
      }
    })
  ]);

  // If timesliceMs > 0, MediaRecorder will generate periodic dataavailable events
  if (timesliceMs > 0) {
    try {
      recorder.start(timesliceMs);
      debugPrint('MediaRecorder.start(${timesliceMs}) with mime=${mime}');
    } catch (e) {
      debugPrint('MediaRecorder.start(${timesliceMs}) failed: ${e.toString()}');
      rethrow;
    }
  } else {
    try {
      recorder.start();
      debugPrint('MediaRecorder.start() with mime=${mime}');
    } catch (e) {
      debugPrint('MediaRecorder.start() failed: ${e.toString()}');
      rethrow;
    }
  }
  return WebRecorderSession(recorder, chunks, mime, htmlStream);
}

WebRecorderSession webStartRecording(dynamic stream, {int timesliceMs = 0}) {
  final mime = webPreferredMime();
  // Accept either flutter_webrtc MediaStream or dart:html MediaStream at runtime
  final recorder = html.MediaRecorder(stream, {'mimeType': mime});
  final chunks = <html.Blob>[];

  // Attach event listener for 'dataavailable'
  js_util.callMethod(recorder, 'addEventListener', [
    'dataavailable',
    js.allowInterop((event) {
      final data = js_util.getProperty(event as Object, 'data');
      final time = DateTime.now().toIso8601String();
      if (data is html.Blob) {
        if (data.size > 0) {
          chunks.add(data);
          debugPrint('MediaRecorder(SYNC) dataavailable (${time}): size=${data.size} totalChunks=${chunks.length}');
        } else {
          debugPrint('MediaRecorder(SYNC) dataavailable (${time}): empty blob');
        }
      } else {
        debugPrint('MediaRecorder(SYNC) dataavailable (${time}): non-blob');
      }
    })
  ]);

  // If timesliceMs > 0, MediaRecorder will generate periodic dataavailable events
  if (timesliceMs > 0) {
    recorder.start(timesliceMs);
    debugPrint('MediaRecorder(SYNC).start(${timesliceMs}) with mime=${mime}');
  } else {
    recorder.start();
    debugPrint('MediaRecorder(SYNC).start() with mime=${mime}');
  }
  return WebRecorderSession(recorder, chunks, mime);
}

Future<Uint8List> webStopRecording(WebRecorderSession session) async {
  final recorder = session.recorder;
  final completer = Completer<Uint8List>();
  bool completed = false;
  bool stopped = false;

  void completeWithChunks() {
    if (completer.isCompleted) return;
    final blob = html.Blob(session.chunks, session.mime);
    debugPrint('webStopRecording: COMPLETE with chunks=${session.chunks.length} blob.size=${blob.size}');
    final start = DateTime.now();
    try {
      js_util
          .promiseToFuture<Object>(js_util.callMethod(blob, 'arrayBuffer', []))
          .then((result) {
        final ms = DateTime.now().difference(start).inMilliseconds;
        debugPrint('webStopRecording: arrayBuffer resolved after ${ms}ms, bytes=${blob.size}, type=${result.runtimeType}');
        Uint8List bytes;
        if (result is ByteBuffer) {
          bytes = Uint8List.view(result);
        } else if (result is Uint8List) {
          bytes = result;
        } else {
          debugPrint('webStopRecording: arrayBuffer result unexpected type=${result.runtimeType}, falling back to FileReader');
          final reader = html.FileReader();
          reader.readAsArrayBuffer(blob);
          reader.onLoadEnd.listen((_) {
            final res = reader.result;
            final ms2 = DateTime.now().difference(start).inMilliseconds;
            debugPrint('webStopRecording: FileReader onLoadEnd after ${ms2}ms, bytes=${blob.size}, type=${res.runtimeType}');
            Uint8List bytes2;
            if (res is ByteBuffer) {
              bytes2 = Uint8List.view(res);
            } else if (res is Uint8List) {
              bytes2 = res;
            } else {
              debugPrint('webStopRecording: FileReader result unexpected type=${res.runtimeType}, completing with empty bytes');
              bytes2 = Uint8List(0);
            }
            if (!completer.isCompleted) {
              completer.complete(bytes2);
            }
          });
          return;
        }
        if (!completer.isCompleted) {
          completer.complete(bytes);
        }
      }).catchError((error) {
        debugPrint('webStopRecording: arrayBuffer() failed: ${error}, falling back to FileReader');
        final reader = html.FileReader();
        reader.readAsArrayBuffer(blob);
        reader.onLoadEnd.listen((_) {
          final res = reader.result;
          final ms2 = DateTime.now().difference(start).inMilliseconds;
          debugPrint('webStopRecording: FileReader onLoadEnd after ${ms2}ms, bytes=${blob.size}, type=${res.runtimeType}');
          Uint8List bytes2;
          if (res is ByteBuffer) {
            bytes2 = Uint8List.view(res);
          } else if (res is Uint8List) {
            bytes2 = res;
          } else {
            debugPrint('webStopRecording: FileReader result unexpected type=${res.runtimeType}, completing with empty bytes');
            bytes2 = Uint8List(0);
          }
          if (!completer.isCompleted) {
            completer.complete(bytes2);
          }
        });
      });
    } catch (e) {
      debugPrint('webStopRecording: exception starting arrayBuffer: ${e}, falling back to FileReader');
      final reader = html.FileReader();
      reader.readAsArrayBuffer(blob);
      reader.onLoadEnd.listen((_) {
        final res = reader.result;
        final ms2 = DateTime.now().difference(start).inMilliseconds;
        debugPrint('webStopRecording: FileReader onLoadEnd after ${ms2}ms, bytes=${blob.size}, type=${res.runtimeType}');
        Uint8List bytes2;
        if (res is ByteBuffer) {
          bytes2 = Uint8List.view(res);
        } else if (res is Uint8List) {
          bytes2 = res;
        } else {
          debugPrint('webStopRecording: FileReader result unexpected type=${res.runtimeType}, completing with empty bytes');
          bytes2 = Uint8List(0);
        }
        if (!completer.isCompleted) {
          completer.complete(bytes2);
        }
      });
    }
  }

  // Capture final chunk(s) and any errors during stop; defer completion until after final dataavailable
  try {
    js_util.callMethod(recorder, 'addEventListener', [
      'dataavailable',
      js.allowInterop((event) {
        final data = js_util.getProperty(event as Object, 'data');
        final time = DateTime.now().toIso8601String();
        if (data is html.Blob && data.size > 0) {
          session.chunks.add(data);
          debugPrint('webStopRecording: dataavailable (${time}) size=${data.size} totalChunks=${session.chunks.length}');
        } else {
          debugPrint('webStopRecording: dataavailable (${time}) empty');
        }
        // If stop already fired, allow a brief moment for the last chunk to be appended before completing
        if (stopped && !completer.isCompleted) {
          // Use a micro-delay to batch any synchronous dataavailable(s) emitted after stop
          Timer(const Duration(milliseconds: 50), () {
            completeWithChunks();
          });
        }
      })
    ]);
  } catch (_) {}

  try {
    js_util.callMethod(recorder, 'addEventListener', [
      'error',
      js.allowInterop((event) {
        final name = js_util.getProperty(event as Object, 'name');
        final message = js_util.getProperty(event as Object, 'message');
        debugPrint('MediaRecorder error during stop: name=${name}, message=${message}');
        // Complete with what we have to avoid hanging
        completeWithChunks();
        completeWithChunks();
      })
    ]);
  } catch (_) {}

  // Attach 'stop' event listener; don't complete immediately, wait for final dataavailable
  try {
    js_util.callMethod(recorder, 'addEventListener', [
      'stop',
      js.allowInterop((_) async {
        stopped = true;
        debugPrint('webStopRecording: STOP event fired');
        // Give the browser a short window to deliver the final dataavailable
        Timer(const Duration(milliseconds: 150), () {
          completeWithChunks();
        });
      })
    ]);
  } catch (_) {}

  // Request a final dataavailable flush before stopping
  try { js_util.callMethod(recorder, 'requestData', []); debugPrint('webStopRecording: requestData() called before stop'); } catch (_) {}

  try {
    recorder.stop();
    debugPrint('webStopRecording: recorder.stop() called');
  } catch (e) {
    debugPrint('webStopRecording: recorder.stop() threw: ${e.toString()}');
    // Complete with whatever chunks we already have
    completeWithChunks();
  }

  // Timeout fallback: if stop/dataavailable don't fire, complete with existing chunks
  Timer(const Duration(seconds: 3), () {
    debugPrint('webStopRecording: timeout fallback fired');
    completeWithChunks();
  });

  return completer.future;
}