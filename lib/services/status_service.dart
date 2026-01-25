import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';
import '../models/status_model.dart';
import 'package:flutter/foundation.dart';

class StatusService {
  StatusService(this.client);
  final SupabaseClient client;

  static StatusService of() => StatusService(Supabase.instance.client);

  Future<void> postTextStatus({
    required String userId,
    required String text,
    required Duration ttl,
    Color? backgroundColor,
  }) async {
    final now = DateTime.now().toUtc();
    final expiresAt = now.add(ttl);
    final bgHex = backgroundColor != null
        ? '#${(((backgroundColor.a) * 255.0).round() & 0xff).toRadixString(16).padLeft(2, '0')}${(((backgroundColor.r) * 255.0).round() & 0xff).toRadixString(16).padLeft(2, '0')}${(((backgroundColor.g) * 255.0).round() & 0xff).toRadixString(16).padLeft(2, '0')}${(((backgroundColor.b) * 255.0).round() & 0xff).toRadixString(16).padLeft(2, '0')}'.toUpperCase()
        : null;

    await client.from('statuses').insert({
      'user_id': userId,
      'type': 'text',
      'text_content': text,
      'bg_color': bgHex,
      'created_at': now.toIso8601String(),
      'expires_at': expiresAt.toIso8601String(),
    });
  }

  Future<void> postMediaStatus({
    required String userId,
    required String mediaUrl,
    required Duration ttl,
    required StatusType type,
  }) async {
    final now = DateTime.now().toUtc();
    final expiresAt = now.add(ttl);
    await client.from('statuses').insert({
      'user_id': userId,
      'type': type == StatusType.video ? 'video' : 'image',
      'media_url': mediaUrl,
      'created_at': now.toIso8601String(),
      'expires_at': expiresAt.toIso8601String(),
    });
  }

  Future<void> createStatus({
    required String userId,
    required String text,
    required Duration ttl,
    String? mediaUrl,
    String? mediaType,
    String? thumbnailUrl,
    bool isAiGenerated = false,
    Color? backgroundColor,
    Map<String, dynamic>? effects,
  }) async {
    final now = DateTime.now().toUtc();
    final expiresAt = now.add(ttl);
    final bgHex = backgroundColor != null
        ? '#${(((backgroundColor.a) * 255.0).round() & 0xff).toRadixString(16).padLeft(2, '0')}${(((backgroundColor.r) * 255.0).round() & 0xff).toRadixString(16).padLeft(2, '0')}${(((backgroundColor.g) * 255.0).round() & 0xff).toRadixString(16).padLeft(2, '0')}${(((backgroundColor.b) * 255.0).round() & 0xff).toRadixString(16).padLeft(2, '0')}'.toUpperCase()
        : null;

    // Determine the status type
    String statusType = 'text';
    if (mediaType != null) {
      switch (mediaType.toLowerCase()) {
        case 'image':
        case 'photo':
        case 'aiphoto':
        case 'ai_photo':
          // Store as regular image for now; we'll add AI flag once backend column exists
          statusType = 'image';
          break;
        case 'video':
          statusType = 'video';
          break;
        case 'audio':
          statusType = 'audio';
          break;
        default:
          statusType = 'text';
      }
    }

    if (kDebugMode) {
      debugPrint('[StatusService] createStatus: inserting for user $userId type $statusType mediaUrl=${mediaUrl ?? 'null'}');
    }

    final Map<String, dynamic> payload = {
       'user_id': userId,
       'type': statusType,
       'text_content': text.isNotEmpty ? text : null,
       'media_url': mediaUrl,
       'bg_color': bgHex,
       // 'is_ai_generated': isAiGenerated, // Temporarily omit if column may not exist
       'created_at': now.toIso8601String(),
       'expires_at': expiresAt.toIso8601String(),
     };

    // Only include thumbnail when provided to avoid schema errors on older databases
    if (thumbnailUrl != null && thumbnailUrl.isNotEmpty) {
      payload['thumbnail_url'] = thumbnailUrl;
    }

    if (effects != null && effects.isNotEmpty) {
      // Store as JSONB-compatible map; Supabase will handle map->json
      payload['effects'] = effects;
    }

    // Insert with graceful fallback if effects/thumbnail_url column doesn't exist yet
    try {
      await client.from('statuses').insert(payload);
    } catch (e) {
      final msg = e.toString().toLowerCase();
      final missingEffects = (msg.contains('effects') && (msg.contains('42703') || msg.contains('does not exist') || msg.contains('column') && msg.contains('not find')));
      final missingThumb = (msg.contains('thumbnail_url') && (msg.contains('42703') || msg.contains('does not exist') || msg.contains('column') && msg.contains('not find')));
      if (missingEffects || missingThumb) {
        if (kDebugMode) {
          debugPrint('[StatusService] missing columns detected; retrying insert without: '
              '${missingEffects ? 'effects ' : ''}'
              '${missingThumb ? 'thumbnail_url ' : ''}');
        }
        if (missingEffects) payload.remove('effects');
        if (missingThumb) payload.remove('thumbnail_url');
        await client.from('statuses').insert(payload);
      } else {
        rethrow;
      }
    }

     if (kDebugMode) {
       debugPrint('[StatusService] createStatus: insert completed for user $userId');
     }
  }

  Future<List<StatusModel>> fetchActiveStatusesForFeed(String currentUserId) async {
    try {
      final nowIso = DateTime.now().toUtc().toIso8601String();

      // Fetch following list (assuming a follows table with follower_id, following_id)
      final followingRes = await client
          .from('follows')
          .select('following_id')
          .eq('follower_id', currentUserId);

      if (kDebugMode) {
        debugPrint('[StatusService] follows rows for $currentUserId: ${followingRes.length}');
            }

      final followingIds = (followingRes as List)
          .map((e) => e['following_id'].toString())
          .toList();
      if (!followingIds.contains(currentUserId)) {
        followingIds.add(currentUserId);
      }

      if (followingIds.isEmpty) {
        if (kDebugMode) {
          debugPrint('[StatusService] No following IDs for user: $currentUserId');
        }
        return [];
      }

      if (kDebugMode) {
        debugPrint('[StatusService] Following IDs for $currentUserId: ${followingIds.join(', ')}');
      }

      // Always fetch statuses without relying on a users join, then bulk-fetch profiles and merge.
      List<dynamic> res;
      try {
        res = await client
            .from('statuses')
            .select('id,user_id,type,text_content,media_url,thumbnail_url,bg_color,created_at,expires_at,effects')
            .inFilter('user_id', followingIds)
            .gt('expires_at', nowIso)
            .order('created_at', ascending: false);
      } catch (_) {
        // Fallback if effects/thumbnail_url column is missing
        res = await client
            .from('statuses')
            .select('id,user_id,type,text_content,media_url,bg_color,created_at,expires_at')
            .inFilter('user_id', followingIds)
            .gt('expires_at', nowIso)
            .order('created_at', ascending: false);
      }

      final list = (res as List);
      if (kDebugMode) {
        debugPrint('[StatusService] statuses fetched: ${list.length}');
        final ids = list.map((e) => (e as Map<String, dynamic>)['id']).toList();
        debugPrint('[StatusService] status IDs: $ids');
        for (final e in list) {
          final m = e as Map<String, dynamic>;
          final sid = m['id']?.toString() ?? 'unknown';
          final uid = m['user_id']?.toString() ?? '';
          debugPrint('[StatusService] status $sid belongs to user ${uid.isEmpty ? '(empty)' : uid}');
          if (uid.isEmpty) {
            debugPrint('[StatusService][WARN] status $sid has empty user_id; this can cause grouping issues');
          }
        }
      }

      final userIds = list
          .map((e) => (e as Map<String, dynamic>)['user_id'].toString())
          .toSet()
          .toList();

      Map<String, Map<String, dynamic>> profilesById = {};
      try {
        if (userIds.isNotEmpty) {
          // Primary: public.users
          try {
            final res = await client
                .from('users')
                .select('id,username,display_name,avatar_url')
                .inFilter('id', userIds);
            for (final p in res) {
              final pm = p;
              profilesById[pm['id'].toString()] = pm;
            }
                    } catch (_) {}

          // Fallback: user_profiles (deprecated - skip)
          final missingFromPrimary = userIds.where((id) => !profilesById.containsKey(id)).toList();
          if (missingFromPrimary.isNotEmpty) {
            try {
              // no-op to avoid PGRST205
            } catch (_) {}
          }

          // Fallback: profiles (includes optional full_name)
          final missingIds = userIds.where((id) => !profilesById.containsKey(id)).toList();
          if (missingIds.isNotEmpty) {
            try {
              final altRes = await client
                  .from('profiles')
                  .select('id,username,full_name,display_name,avatar_url')
                  .inFilter('id', missingIds);
              for (final p in altRes) {
                final pm = p;
                profilesById[pm['id'].toString()] = pm;
              }
                        } catch (_) {}
          }
        }
      } catch (eProf) {
        if (kDebugMode) {
          debugPrint('[StatusService] fetchActiveStatusesForFeed profile fetch failed: ${eProf.toString()}');
        }
      }

      if (kDebugMode) {
        debugPrint('[StatusService] Fetched ${list.length} statuses for user: $currentUserId; profiles loaded for ${profilesById.length} users');
      }

      return list.map((e) {
        final map = e as Map<String, dynamic>;
        final pid = map['user_id'].toString();
        final profile = profilesById[pid];
        final dn = (profile?['display_name'] as String?)?.trim();
        final fn = (profile?['full_name'] as String?)?.trim();
        final un = (profile?['username'] as String?)?.trim();
        final effectiveDisplay = (dn != null && dn.isNotEmpty)
            ? dn
            : (fn != null && fn.isNotEmpty)
                ? fn
                : un;
        final withProfile = {
          ...map,
          'username': un,
          'display_name': effectiveDisplay,
          'avatar_url': profile?['avatar_url'],
        };
        return StatusModel.fromMap(withProfile);
      }).toList();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[StatusService] fetchActiveStatusesForFeed error: ${e.toString()}');
      }
      return [];
    }
  }

  Future<List<StatusModel>> fetchUserStatuses(String userId) async {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    try {
      List<dynamic> res;
      try {
        res = await client
            .from('statuses')
            .select('id,user_id,type,text_content,media_url,thumbnail_url,bg_color,created_at,expires_at,effects')
            .eq('user_id', userId)
            .gt('expires_at', nowIso)
            .order('created_at', ascending: false);
      } catch (_) {
        res = await client
            .from('statuses')
            .select('id,user_id,type,text_content,media_url,bg_color,created_at,expires_at')
            .eq('user_id', userId)
            .gt('expires_at', nowIso)
            .order('created_at', ascending: false);
      }

      final list = (res as List);
      return list.map((e) => StatusModel.fromMap(e as Map<String, dynamic>)).toList();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[StatusService] fetchUserStatuses error: ${e.toString()}');
      }
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> listViewers(String statusId) async {
    try {
      final res = await client
          .from('status_views')
          .select('viewer_id, viewed_at')
          .eq('status_id', statusId)
          .order('viewed_at', ascending: false);
      return (res as List).map((e) => e as Map<String, dynamic>).toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> markViewed({required String statusId, required String viewerId}) async {
    try {
      await client.from('status_views').insert({
        'status_id': statusId,
        'viewer_id': viewerId,
        'viewed_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (_) {}
  }

  Future<int> getViewCount(String statusId) async {
    try {
      final res = await client
          .from('status_views')
          .select('count')
          .eq('status_id', statusId)
          .count(CountOption.exact);
      return res.count;
    } catch (_) {
      return 0;
    }
  }

  // Compatibility wrappers for newer API used by StatusViewerScreen
  Future<int> getStatusViewCount(String statusId) async {
    return await getViewCount(statusId);
  }

  Future<List<Map<String, dynamic>>> listStatusViewers(String statusId) async {
    return await listViewers(statusId);
  }

  // Debug helper used by StatusHomeScreen; safe no-op in production
  Future<void> debugPrintFollowsAndStatusCounts(String userId) async {
    try {
      final List<dynamic> follows = await client
          .from('follows')
          .select('following_id')
          .eq('follower_id', userId);
      final List<dynamic> statuses = await client
          .from('statuses')
          .select('id')
          .eq('user_id', userId);
      if (kDebugMode) {
        final followsCount = follows.length;
        final statusesCount = statuses.length;
        debugPrint('[StatusService] Debug: user $userId follows=$followsCount statuses=$statusesCount');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[StatusService] debugPrintFollowsAndStatusCounts error: ${e.toString()}');
      }
    }
  }

  Future<bool> hasUnseenStatusesForUser({required String ownerUserId, required String viewerUserId}) async {
    try {
      // Fetch active statuses for the owner
      final nowIso = DateTime.now().toUtc().toIso8601String();
      final res = await client
          .from('statuses')
          .select('id')
          .eq('user_id', ownerUserId)
          .gt('expires_at', nowIso);
      final ids = List<String>.from((res as List).map((e) => e['id'].toString()));
      if (ids.isEmpty) return false; // No active statuses to view
  
      // Fetch status views by the viewer for those statuses
      final views = await client
          .from('status_views')
          .select('status_id')
          .inFilter('status_id', ids)
          .eq('viewer_id', viewerUserId);
      final seen = (views as List).map((e) => e['status_id'].toString()).toSet();
  
      // Unseen exists if any status id is not in seen set
      return ids.any((id) => !seen.contains(id));
    } catch (_) {
      return false;
    }
  }
}