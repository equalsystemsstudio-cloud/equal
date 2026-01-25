import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as path;
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';

String _escape(String p) => p.replaceAll('"', '\\"');

Future<Uint8List> extractWavSnippetFromBytesImpl(
  Uint8List input, {
  int seconds = 20,
  int offsetSeconds = 0,
}) async {
  // Write input to a temporary file
  final tmpDir = Directory.systemTemp.createTempSync('equal_vid_');
  final inPath = path.join(tmpDir.path, 'input.mp4');
  final outPath = path.join(tmpDir.path, 'snippet.wav');
  final inFile = File(inPath);
  await inFile.writeAsBytes(input);

  // Build FFmpeg command to extract mono 44.1kHz PCM WAV snippet
  // Place -ss before -i for faster seeking when possible
  final ss = offsetSeconds > 0 ? '-ss $offsetSeconds' : '';
  final cmd =
      '-y $ss -i "${_escape(inPath)}" -vn -ac 1 -ar 44100 -sample_fmt s16 -t $seconds -f wav "${_escape(outPath)}"';
  final session = await FFmpegKit.execute(cmd);
  final rc = await session.getReturnCode();
  if (rc == null || !rc.isValueSuccess()) {
    try {
      tmpDir.deleteSync(recursive: true);
    } catch (_) {}
    throw Exception('FFmpeg WAV extract failed: ${rc?.getValue()}');
  }

  final outFile = File(outPath);
  final bytes = await outFile.readAsBytes();
  try {
    tmpDir.deleteSync(recursive: true);
  } catch (_) {}
  return bytes;
}

Future<Uint8List> extractWavSnippetFromAudioBytesImpl(
  Uint8List input, {
  int seconds = 20,
  int offsetSeconds = 0,
}) async {
  // Write input to a temporary file with generic extension to let FFmpeg probe format
  final tmpDir = Directory.systemTemp.createTempSync('equal_aud_');
  final inPath = path.join(tmpDir.path, 'input.bin');
  final outPath = path.join(tmpDir.path, 'snippet.wav');
  final inFile = File(inPath);
  await inFile.writeAsBytes(input);

  // Extract mono 44.1kHz PCM WAV snippet
  final ss = offsetSeconds > 0 ? '-ss $offsetSeconds' : '';
  final cmd =
      '-y $ss -i "${_escape(inPath)}" -vn -ac 1 -ar 44100 -sample_fmt s16 -t $seconds -f wav "${_escape(outPath)}"';
  final session = await FFmpegKit.execute(cmd);
  final rc = await session.getReturnCode();
  if (rc == null || !rc.isValueSuccess()) {
    try {
      tmpDir.deleteSync(recursive: true);
    } catch (_) {}
    throw Exception('FFmpeg WAV extract (audio) failed: ${rc?.getValue()}');
  }

  final outFile = File(outPath);
  final bytes = await outFile.readAsBytes();
  try {
    tmpDir.deleteSync(recursive: true);
  } catch (_) {}
  return bytes;
}
