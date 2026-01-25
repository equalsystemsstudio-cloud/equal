import 'dart:convert';
import 'dart:typed_data';
import 'dart:io' show File;
import 'package:http/http.dart' as http;
import 'package:dart_tags/dart_tags.dart';
import 'package:flutter/foundation.dart';

class MusicBrainzService {
  static final MusicBrainzService _instance = MusicBrainzService._internal();
  factory MusicBrainzService() => _instance;
  MusicBrainzService._internal();

  // Respect MusicBrainz rate limits: no more than 1 request/sec
  static const Duration _minInterval = Duration(seconds: 1);
  DateTime _lastRequest = DateTime.fromMillisecondsSinceEpoch(0);

  // Set a proper User-Agent per MusicBrainz web service requirements
  // Ideally replace with your app name/version and contact email in production.
  static const String _userAgent = 'EqualApp/1.0 (contact@equal.app)';

  Future<Map<String, dynamic>?> detect({
    Uint8List? bytes,
    File? file,
    String? fileName,
    String? titleHint,
    String? artistHint,
  }) async {
    try {
      final Uint8List srcBytes = bytes ?? await file!.readAsBytes();

      // Parse ID3 tags for title/artist
      final tags = await _parseId3(srcBytes);
      String? title = tags['title'] as String?;
      String? artist = tags['artist'] as String?;

      // Apply provided hints if tags are missing
      if ((title == null || title.isEmpty) && (titleHint != null && titleHint.trim().isNotEmpty)) {
        title = titleHint.trim();
      }
      if ((artist == null || artist.isEmpty) && (artistHint != null && artistHint.trim().isNotEmpty)) {
        artist = artistHint.trim();
      }

      // Fallback: try derive from file name pattern "Artist - Title"
      if ((title == null || title.isEmpty) && (artist == null || artist.isEmpty) && fileName != null) {
        final name = fileName.replaceAll(RegExp(r'\.(mp3|wav|m4a|flac)$', caseSensitive: false), '');
        if (name.contains(' - ')) {
          final parts = name.split(' - ');
          if (parts.length >= 2) {
            artist = parts.first.trim();
            title = parts.sublist(1).join(' - ').trim();
          }
        } else {
          // If we already have an artist hint, treat the remaining filename as title
          if ((title == null || title.isEmpty) && (artist != null && artist.isNotEmpty)) {
            title = name.trim();
          } else {
            title = name.trim();
          }
        }
      }

      if (title == null || title.isEmpty) {
        return {
          'source': 'musicbrainz',
          'match': false,
          'reason': 'no_title_metadata',
          'tags': tags,
        };
      }

      // Build query; include artist if available
      final query = artist != null && artist.isNotEmpty
          ? 'recording:"${_escape(title)}" AND artist:"${_escape(artist)}"'
          : 'recording:"${_escape(title)}"';

      final uri = Uri.parse('https://musicbrainz.org/ws/2/recording?query=$query&fmt=json');

      // Respect minimal interval
      final now = DateTime.now();
      final diff = now.difference(_lastRequest);
      if (diff < _minInterval) {
        await Future.delayed(_minInterval - diff);
      }

      final resp = await http.get(uri, headers: {
        'User-Agent': _userAgent,
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 10));
      _lastRequest = DateTime.now();

      if (resp.statusCode != 200) {
        return {
          'source': 'musicbrainz',
          'match': false,
          'reason': 'http_${resp.statusCode}',
          'tags': tags,
        };
      }

      final jsonResp = jsonDecode(resp.body) as Map<String, dynamic>;
      final recordings = (jsonResp['recordings'] as List<dynamic>?) ?? const [];
      if (recordings.isEmpty) {
        return {
          'source': 'musicbrainz',
          'match': false,
          'reason': 'no_recordings_found',
          'tags': tags,
        };
      }

      // Choose best match by score
      Map<String, dynamic> best = recordings.first as Map<String, dynamic>;
      for (final r in recordings) {
        final m = r as Map<String, dynamic>;
        if ((m['score'] as int? ?? 0) > (best['score'] as int? ?? 0)) {
          best = m;
        }
      }

      final recordingId = best['id'] as String?; // MBID
      final bestTitle = best['title'] as String? ?? title;
      final artistCredit = best['artist-credit'] as List<dynamic>?;
      final resolvedArtist = artistCredit != null && artistCredit.isNotEmpty
          ? (artistCredit.first as Map<String, dynamic>)['name'] as String?
          : artist;

      return {
        'source': 'musicbrainz',
        'match': true,
        'score': best['score'],
        'recordingId': recordingId,
        'title': bestTitle,
        'artist': resolvedArtist,
        'tags': tags,
        'raw': best,
      };
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[MusicBrainzService] detection error: $e');
      }
      return {
        'source': 'musicbrainz',
        'match': false,
        'reason': 'exception',
        'error': e.toString(),
      };
    }
  }

  Future<Map<String, dynamic>> _parseId3(Uint8List bytes) async {
    try {
      final tp = TagProcessor();
      // dart_tags ^0.4.1 expects a Future<List<int>>? for getTagsFromByteArray
      // Wrap the Uint8List in a Future to match the expected signature
      final result = await tp.getTagsFromByteArray(Future.value(bytes));
      if (result.isNotEmpty) {
        final tag = result.first;
        final map = Map<String, dynamic>.from(tag.tags ?? const {});
        return {
          'title': (map['title'] ?? map['Title'] ?? '').toString(),
          'artist': (map['artist'] ?? map['Artist'] ?? '').toString(),
          'album': (map['album'] ?? map['Album'] ?? '').toString(),
          'year': (map['year'] ?? map['Year'] ?? '').toString(),
          'genre': (map['genre'] ?? map['Genre'] ?? '').toString(),
        };
      }
      return {};
    } catch (_) {
      return {};
    }
  }

  String _escape(String s) {
    return s.replaceAll('"', '\\"');
  }
}