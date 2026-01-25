import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../config/api_config.dart';

class ModerationResult {
  final bool isAllowed;
  final double nsfwScore;
  final Map<String, dynamic>? raw;
  const ModerationResult({
    required this.isAllowed,
    required this.nsfwScore,
    this.raw,
  });
}

class ModerationService {
  static final ModerationService _instance = ModerationService._internal();
  factory ModerationService() => _instance;
  ModerationService._internal();

  final SupabaseClient _client = SupabaseConfig.client;

  // Labels commonly returned by NSFW classifiers to indicate explicit sexual content.
  static const Set<String> _nsfwLabels = {
    'porn',
    'sexual',
    'explicit',
    'erotica',
    'hentai',
    'nudity',
    'sexy',
    'nsfw',
  };

  Future<ModerationResult> checkImage(Uint8List imageBytes) async {
    try {
      final response = await _invokeHuggingFaceProxy(imageBytes);
      final parsed = _safeParseResponse(response);
      final score = _extractNSFWScore(parsed);
      final allowed = score < ApiConfig.nsfwThreshold;
      return ModerationResult(
        isAllowed: allowed,
        nsfwScore: score,
        raw: parsed,
      );
    } catch (_) {
      // If the proxy/model isn't configured or fails, default to allow
      return const ModerationResult(isAllowed: true, nsfwScore: 0.0);
    }
  }

  Future<ModerationResult> checkVideoFrames(List<Uint8List> frames) async {
    if (frames.isEmpty) {
      return const ModerationResult(isAllowed: true, nsfwScore: 0.0);
    }
    double maxScore = 0.0;
    Map<String, dynamic>? lastRaw;
    for (final f in frames) {
      try {
        final response = await _invokeHuggingFaceProxy(f);
        final parsed = _safeParseResponse(response);
        final score = _extractNSFWScore(parsed);
        if (score > maxScore) {
          maxScore = score;
          lastRaw = parsed;
        }
        // Early exit if already above threshold
        if (maxScore >= ApiConfig.nsfwThreshold) {
          break;
        }
      } catch (_) {
        // Ignore errors per-frame, continue evaluating others
      }
    }
    final allowed = maxScore < ApiConfig.nsfwThreshold;
    return ModerationResult(
      isAllowed: allowed,
      nsfwScore: maxScore,
      raw: lastRaw,
    );
  }

  // Attempt to record a moderation strike in a database table (if it exists).
  Future<void> recordStrike({
    required String userId,
    required String type, // e.g., 'image_nsfw' or 'video_nsfw'
    required double score,
    Map<String, dynamic>? details,
  }) async {
    try {
      await _client.from('moderation_events').insert({
        'user_id': userId,
        'event_type': type,
        'score': score,
        'details': details != null ? jsonEncode(details) : null,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (_) {
      // Gracefully ignore if table/policies aren’t set up.
    }
  }

  Future<dynamic> _invokeHuggingFaceProxy(Uint8List imageBytes) async {
    final String b64 = base64Encode(imageBytes);
    final String dataUri = 'data:image/jpeg;base64,$b64';

    // Invoke Supabase Edge Function hf_proxy with model query param.
    final path = 'hf_proxy?model=${ApiConfig.huggingFaceNSFWModel}';
    final response = await _client.functions.invoke(
      path,
      body: {'inputs': dataUri},
      headers: {
        'x-hf-token': ApiConfig.huggingFaceApiToken,
        'content-type': 'application/json',
      },
    );
    return response.data;
  }

  Map<String, dynamic>? _safeParseResponse(dynamic data) {
    try {
      if (data == null) return null;
      if (data is Map<String, dynamic>) return data;
      if (data is List) {
        return {'list': data};
      }
      if (data is String && data.isNotEmpty) {
        final decoded = jsonDecode(data);
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is List) return {'list': decoded};
      }
    } catch (_) {}
    return null;
  }

  double _extractNSFWScore(Map<String, dynamic>? parsed) {
    if (parsed == null) return 0.0;
    // Many HF classifiers return a list of {label, score}
    final list = parsed['list'];
    double maxScore = 0.0;
    if (list is List) {
      for (final item in list) {
        try {
          final label = (item['label'] ?? '').toString().toLowerCase();
          final scoreRaw = item['score'];
          final score = scoreRaw is num
              ? scoreRaw.toDouble()
              : double.tryParse('$scoreRaw') ?? 0.0;
          if (_nsfwLabels.contains(label)) {
            if (score > maxScore) maxScore = score;
          }
        } catch (_) {}
      }
    }
    // Fallback: support structures like { nsfw: 0.9, nudity: 0.8 }
    for (final key in _nsfwLabels) {
      final v = parsed[key];
      if (v is num && v.toDouble() > maxScore) maxScore = v.toDouble();
      if (v is String) {
        final d = double.tryParse(v);
        if (d != null && d > maxScore) maxScore = d;
      }
    }
    return maxScore.clamp(0.0, 1.0);
  }
}
