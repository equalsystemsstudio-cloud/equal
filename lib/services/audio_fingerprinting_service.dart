import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class AudioFingerprintService {
  static final AudioFingerprintService _instance = AudioFingerprintService._internal();
  factory AudioFingerprintService() => _instance;
  AudioFingerprintService._internal();

  Map<String, dynamic>? _normalizeAcoustId(Map<String, dynamic> data) {
    try {
      final results = data['results'];
      if (results is List && results.isNotEmpty) {
        // Pick the best result (highest score)
        Map<String, dynamic>? best;
        double bestScore = -1;
        for (final r in results) {
          if (r is Map<String, dynamic>) {
            final s = (r['score'] is num) ? (r['score'] as num).toDouble() : 0.0;
            if (s > bestScore) {
              bestScore = s;
              best = r;
            }
          }
        }
        if (best != null) {
          final recordings = best['recordings'];
          String? title;
          String? artist;
          String? recordingId;
          if (recordings is List && recordings.isNotEmpty) {
            final rec = recordings.first;
            if (rec is Map<String, dynamic>) {
              title = rec['title'] as String?;
              recordingId = rec['id'] as String?; // MusicBrainz Recording MBID
              final artists = rec['artists'];
              if (artists is List && artists.isNotEmpty) {
                final a0 = artists.first;
                if (a0 is Map<String, dynamic>) {
                  artist = a0['name'] as String?;
                }
              }
            }
          }
          return {
            'match': true,
            'source': 'acoustid',
            'confidence': bestScore,
            if (title != null) 'title': title,
            if (artist != null) 'artist': artist,
            if (recordingId != null) 'recordingId': recordingId,
            'raw': data,
          };
        }
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> detectFromBytes(Uint8List bytes, {String? fileName}) async {
    try {
      final client = Supabase.instance.client;
      final base64Audio = base64Encode(bytes);
      final res = await client.functions.invoke('recognize_audio',
        body: {
          'audioBase64': base64Audio,
          'fileName': fileName,
        },
      );
      final data = res.data;
      if (data is Map<String, dynamic>) {
        final norm = _normalizeAcoustId(data);
        if (norm != null) return norm;
        return data;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> detectFromUrl(String mediaUrl) async {
    try {
      final resp = await http.get(Uri.parse(mediaUrl)).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        return await detectFromBytes(resp.bodyBytes, fileName: mediaUrl.split('/').last);
      }
    } catch (_) {}
    return null;
  }
}