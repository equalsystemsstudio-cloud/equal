import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/post_model.dart';
import '../models/status_model.dart';

/// Lightweight local history tracker for recently viewed content.
/// Stores a bounded list in SharedPreferences and exposes a ValueNotifier
/// so UI can react in real time.
class HistoryEntry {
  final String type; // 'post' | 'status' | 'stream'
  final String id; // postId | statusId | streamId
  final String? userId;
  final String? title; // post content snippet OR stream title OR status text
  final String? subtitle; // username/displayName
  final String? thumbnailUrl; // thumbnail or avatar
  final String? mediaUrl; // image/video/audio url
  final DateTime viewedAt;
  final Map<String, dynamic>? extra;

  HistoryEntry({
    required this.type,
    required this.id,
    this.userId,
    this.title,
    this.subtitle,
    this.thumbnailUrl,
    this.mediaUrl,
    DateTime? viewedAt,
    this.extra,
  }) : viewedAt = viewedAt ?? DateTime.now().toUtc();

  Map<String, dynamic> toMap() {
    return {
      'type': type,
      'id': id,
      'userId': userId,
      'title': title,
      'subtitle': subtitle,
      'thumbnailUrl': thumbnailUrl,
      'mediaUrl': mediaUrl,
      'viewedAt': viewedAt.toIso8601String(),
      'extra': extra,
    };
  }

  factory HistoryEntry.fromMap(Map<String, dynamic> map) {
    return HistoryEntry(
      type: map['type']?.toString() ?? 'post',
      id: map['id']?.toString() ?? '',
      userId: map['userId'] as String?,
      title: map['title'] as String?,
      subtitle: map['subtitle'] as String?,
      thumbnailUrl: map['thumbnailUrl'] as String?,
      mediaUrl: map['mediaUrl'] as String?,
      viewedAt: DateTime.tryParse(map['viewedAt']?.toString() ?? '')?.toUtc(),
      extra: (map['extra'] is Map<String, dynamic>)
          ? Map<String, dynamic>.from(map['extra'] as Map)
          : null,
    );
  }
}

class HistoryService {
  static const String _prefsKey = 'history_entries_v1';
  static const int _maxEntries = 100;
  static final ValueNotifier<List<HistoryEntry>> entriesNotifier =
      ValueNotifier<List<HistoryEntry>>([]);

  static Future<void> init() async {
    final list = await getEntries();
    entriesNotifier.value = list;
  }

  static String _dedupeKey(HistoryEntry e) => '${e.type}:${e.id}';

  static Future<List<HistoryEntry>> getEntries() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .map((v) => HistoryEntry.fromMap(Map<String, dynamic>.from(v)))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
    entriesNotifier.value = [];
  }

  static Future<void> addEntry(HistoryEntry entry) async {
    final prefs = await SharedPreferences.getInstance();
    final current = await getEntries();
    // Remove duplicates by type+id
    final key = _dedupeKey(entry);
    final filtered = current.where((e) => _dedupeKey(e) != key).toList();
    // Insert at beginning
    filtered.insert(0, entry);
    // Trim to max
    while (filtered.length > _maxEntries) {
      filtered.removeLast();
    }
    final encoded = jsonEncode(filtered.map((e) => e.toMap()).toList());
    await prefs.setString(_prefsKey, encoded);
    entriesNotifier.value = filtered;
  }

  // Convenience helpers
  static Future<void> addPostView(PostModel post) async {
    final snippet = (post.content ?? '').trim();
    await addEntry(
      HistoryEntry(
        type: 'post',
        id: post.id,
        userId: post.userId,
        title: snippet.isNotEmpty ? snippet : 'Post',
        subtitle: post.username,
        thumbnailUrl: post.thumbnailUrl?.isNotEmpty == true
            ? post.thumbnailUrl
            : post.userAvatar,
        mediaUrl: post.mediaUrl,
        extra: {'mediaType': post.mediaType.toString().split('.').last},
      ),
    );
  }

  static Future<void> addStatusView(StatusModel status) async {
    final t = (status.text ?? '').trim();
    await addEntry(
      HistoryEntry(
        type: 'status',
        id: status.id,
        userId: status.userId,
        title: t.isNotEmpty ? t : 'Status',
        subtitle: status.username ?? status.displayName,
        thumbnailUrl: status.thumbnailUrl ?? status.userAvatar,
        mediaUrl: status.mediaUrl,
        extra: {'statusType': status.type.toString()},
      ),
    );
  }

  static Future<void> addLiveStreamView({
    required String streamId,
    String? title,
    String? description,
  }) async {
    await addEntry(
      HistoryEntry(
        type: 'stream',
        id: streamId,
        title: (title ?? '').isNotEmpty ? title : 'Live Stream',
        subtitle: (description ?? '').isNotEmpty ? description : null,
        thumbnailUrl: null,
        mediaUrl: null,
      ),
    );
  }

  static Future<void> removeEntryByKey(String type, String id) async {
    final prefs = await SharedPreferences.getInstance();
    final current = await getEntries();
    final key = _dedupeKey(HistoryEntry(type: type, id: id));
    final filtered = current.where((e) => _dedupeKey(e) != key).toList();
    final encoded = jsonEncode(filtered.map((e) => e.toMap()).toList());
    await prefs.setString(_prefsKey, encoded);
    entriesNotifier.value = filtered;
  }
}
