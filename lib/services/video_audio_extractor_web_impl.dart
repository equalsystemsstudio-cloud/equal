import 'dart:typed_data';
import 'dart:js' as js;
import 'dart:js_util' as js_util;

Future<Uint8List> extractWavSnippetFromBytesImpl(
  Uint8List input, {
  int seconds = 20,
  int offsetSeconds = 0,
}) async {
  final ffmpegInit = js_util.getProperty(js.context, 'equalInitFFmpeg');
  final extractFn = js_util.getProperty(
    js.context,
    'equalExtractAudioFFmpegWasm',
  );
  if (ffmpegInit == null || extractFn == null) {
    throw Exception('FFmpeg.wasm interop not available');
  }
  await js_util.promiseToFuture(
    js_util.callMethod(ffmpegInit, 'call', [js.context]),
  );
  final opts = {'seconds': seconds, 'offsetSeconds': offsetSeconds};
  final result = await js_util.promiseToFuture(
    js_util.callMethod(extractFn, 'call', [js.context, input.buffer, opts]),
  );
  // result is an ArrayBuffer; convert to Uint8List
  final bytes = Uint8List.view(result as ByteBuffer);
  return bytes;
}

Future<Uint8List> extractWavSnippetFromAudioBytesImpl(
  Uint8List input, {
  int seconds = 20,
  int offsetSeconds = 0,
}) async {
  // Same implementation as video; ffmpeg will probe the input format from bytes
  return await extractWavSnippetFromBytesImpl(
    input,
    seconds: seconds,
    offsetSeconds: offsetSeconds,
  );
}
