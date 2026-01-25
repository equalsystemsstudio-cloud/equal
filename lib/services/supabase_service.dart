import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:functions_client/src/types.dart';
import '../config/supabase_config.dart';
import 'enhanced_notification_service.dart';
import 'dart:convert';

class SupabaseService {
  
  static SupabaseClient get client => Supabase.instance.client;
  
  static Future<void> initialize() async {
    await Supabase.initialize(
      url: SupabaseConfig.supabaseUrl,
      anonKey: SupabaseConfig.supabaseAnonKey,
      debug: true,
    );
  }
  
  // Authentication methods
  static Future<AuthResponse> signUp({
    required String email,
    required String password,
    Map<String, dynamic>? data,
  }) async {
    return await client.auth.signUp(
      email: email,
      password: password,
      data: data,
    );
  }
  
  static Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    return await client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }
  
  static Future<void> signOut() async {
    await client.auth.signOut();
  }
  
  static User? get currentUser => client.auth.currentUser;
  
  static bool get isAuthenticated => currentUser != null;
  
  // Posts methods
  static Future<List<Map<String, dynamic>>> getPosts({
    int limit = 20,
    int offset = 0,
  }) async {
    final response = await client
        .from('posts')
        .select('*, users(*)')
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    
    return List<Map<String, dynamic>>.from(response);
  }
  
  static Future<Map<String, dynamic>> createPost({
    required String content,
    String? mediaUrl,
    String? mediaType,
    List<String>? hashtags,
    String? location,
    Map<String, dynamic>? aiMetadata,
    String? musicId,
  }) async {
    final payload = {
      'user_id': currentUser!.id,
      'content': content,
      'media_url': mediaUrl,
      'type': mediaType,
      'hashtags': hashtags,
      'location': location,
      'ai_metadata': aiMetadata,
      'music_id': musicId,
      'created_at': DateTime.now().toIso8601String(),
    };

    dynamic response;
    try {
      response = await client.from('posts').insert(payload).select().single();
    } catch (e) {
      final errStr = e.toString();
      final err = errStr.toLowerCase();
      bool retried = false;

      // Extract missing column if present
      String? missingColumn;
      final colMatch = RegExp(
        r"could not find the '([^']+)' column",
        caseSensitive: false,
      ).firstMatch(errStr);
      if (colMatch != null && colMatch.groupCount >= 1) {
        missingColumn = colMatch.group(1);
      }

      // Optional/extra fields that may not exist
      final optionalColumns = <String>{
        'hashtags',
        'location',
        'ai_metadata',
        'music_id',
      };

      if (err.contains('pgrst204') || err.contains('schema cache')) {
        for (final c in optionalColumns) {
          if (payload.containsKey(c)) {
            payload.remove(c);
            retried = true;
          }
        }
        if (retried) {
          response = await client.from('posts').insert(payload).select().single();
        } else if (missingColumn != null && payload.containsKey(missingColumn)) {
          payload.remove(missingColumn);
          response = await client.from('posts').insert(payload).select().single();
        } else {
          rethrow;
        }
      } else {
        rethrow;
      }
    }

    return Map<String, dynamic>.from(response as Map);
  }
  
  static Future<void> likePost(String postId) async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return;
  
    // Upsert like record
    await client
        .from('likes')
        .upsert({'post_id': postId, 'user_id': userId})
        .select();
  
    // Increment like count via RPC
    try {
      await client.rpc('increment_post_likes_count', params: {'post_id': postId});
    } catch (e) {
      debugPrint('RPC increment_post_likes_count failed, applying fallback: $e');
      try {
        final postRow = await client
            .from('posts')
            .select('likes_count')
            .eq('id', postId)
            .maybeSingle();
        final current = (postRow?['likes_count'] as int?) ?? 0;
        await client
            .from('posts')
            .update({'likes_count': current + 1})
            .eq('id', postId);
      } catch (inner) {
        debugPrint('Fallback increment likes_count failed: $inner');
      }
    }
  
    // Create like notification for post owner (if not self-like)
    try {
      final postOwnerRow = await client
          .from('posts')
          .select('user_id')
          .eq('id', postId)
          .maybeSingle();
      final String? postOwnerId = postOwnerRow != null ? postOwnerRow['user_id'] as String? : null;
      if (postOwnerId != null) {
        // Determine liker name
        String likerName = 'Someone';
        try {
          final profile = await client
              .from('users')
              .select('display_name,username')
              .eq('id', userId)
              .maybeSingle();
          if (profile != null) {
            final dp = (profile['display_name'] as String?)?.trim();
            final up = (profile['username'] as String?)?.trim();
            likerName = (dp != null && dp.isNotEmpty) ? dp : (up ?? 'Someone');
          }
        } catch (_) {}
  
        await EnhancedNotificationService().createLikeNotification(
          postOwnerId: postOwnerId,
          likerName: likerName,
          postId: postId,
        );
        debugPrint('supabase_service.likePost: createLikeNotification called for postId=$postId, postOwnerId=$postOwnerId, actorId=$userId');
      }
    } catch (_) {}
  }
  
  static Future<void> unlikePost(String postId) async {
    await client
        .from('likes')
        .delete()
        .eq('user_id', currentUser!.id)
        .eq('post_id', postId);
  }
  
  // Profile methods
  static Future<Map<String, dynamic>?> getProfile(String userId) async {
    try {
      // 1) Primary: users table
      Map<String, dynamic>? userRow = await client
          .from('users')
          .select('id, username, display_name, avatar_url, bio')
          .eq('id', userId)
          .maybeSingle();

      // If users table has usable profile info, return it
      String uname = (userRow?['username'] as String?)?.trim() ?? '';
      String dname = (userRow?['display_name'] as String?)?.trim() ?? '';
      if (userRow != null && (uname.isNotEmpty || dname.isNotEmpty)) {
        return userRow;
      }

      // 2) Fallback: profiles table (if exists)
      Map<String, dynamic>? profileRow;
      try {
        profileRow = await client
            .from('profiles')
            .select('id, username, display_name, avatar_url, bio')
            .eq('id', userId)
            .maybeSingle();
      } catch (_) {
        profileRow = null; // profiles table may not exist in some deployments
      }
      String pun = (profileRow?['username'] as String?)?.trim() ?? '';
      String pdn = (profileRow?['display_name'] as String?)?.trim() ?? '';
      if (profileRow != null && (pun.isNotEmpty || pdn.isNotEmpty)) {
        // Merge missing fields from users if needed
        return {
          'id': userId,
          'username': pun.isNotEmpty ? pun : uname,
          'display_name': pdn.isNotEmpty ? pdn : dname,
          'avatar_url': profileRow['avatar_url'] ?? userRow?['avatar_url'],
          'bio': profileRow['bio'] ?? userRow?['bio'],
        };
      }

      // 3) Fallback: user_profiles table (legacy)
      Map<String, dynamic>? legacyRow;
      try {
        legacyRow = await client
            .from('user_profiles')
            .select('id, username, display_name, avatar_url, bio')
            .eq('id', userId)
            .maybeSingle();
      } catch (_) {
        legacyRow = null;
      }
      String lun = (legacyRow?['username'] as String?)?.trim() ?? '';
      String ldn = (legacyRow?['display_name'] as String?)?.trim() ?? '';
      if (legacyRow != null && (lun.isNotEmpty || ldn.isNotEmpty)) {
        return legacyRow;
      }

      // If all sources failed to provide a usable profile, still return users row (if any)
      return userRow;
    } catch (_) {
      // Gracefully handle any errors and return null
      return null;
    }
  }
  
  static Future<Map<String, dynamic>> updateProfile({
    required String userId,
    String? username,
    String? fullName,
    String? bio,
    String? avatarUrl,
  }) async {
    final response = await client.from('users').upsert({
      'id': userId,
      'username': username,
      'display_name': fullName,  // Fixed: use display_name instead of full_name
      'bio': bio,
      'avatar_url': avatarUrl,
      'updated_at': DateTime.now().toIso8601String(),
    }).select().single();
    
    return response;
  }
  
  // Storage methods
  static Future<String> uploadFile({
    required String bucket,
    required String path,
    required List<int> fileBytes,
    String? contentType,
  }) async {
    await client.storage.from(bucket).uploadBinary(
      path,
      Uint8List.fromList(fileBytes),
      fileOptions: FileOptions(
        contentType: contentType,
        upsert: true,
      ),
    );
    
    return client.storage.from(bucket).getPublicUrl(path);
  }
  
  static Future<void> deleteFile({
    required String bucket,
    required String path,
  }) async {
    await client.storage.from(bucket).remove([path]);
  }
  
  // Real-time subscriptions
  static RealtimeChannel subscribeToTable({
    required String table,
    required void Function(PostgresChangePayload) callback,
  }) {
    return client
        .channel('public:$table')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: table,
          callback: callback,
        )
        .subscribe();
  }
  
  static void unsubscribe(RealtimeChannel channel) {
    client.removeChannel(channel);
  }
  
  static Future<Map<String, dynamic>> invokeFunction({
    required String name,
    Map<String, dynamic>? body,
    String method = 'POST',
  }) async {
    final response = await client.functions.invoke(
      name,
      body: body ?? {},
      method: HttpMethod.values.firstWhere(
        (m) => m.name.toUpperCase() == method.toUpperCase(),
        orElse: () => HttpMethod.post,
      ),
    );
    // FunctionsClient returns FunctionResponse with .data which may be Map or String
    final data = response.data;
    if (data is Map<String, dynamic>) return data;
    if (data is String) {
      try {
        return json.decode(data) as Map<String, dynamic>;
      } catch (_) {
        return {'raw': data};
      }
    }
    // Fallback: wrap unknown types
    return {'data': data};
  }
  
  static Future<String> fetchZegoToken({
    required String userId,
    required String role, // e.g., 'host' or 'viewer'
    required String roomId,
    List<String>? streamIdList,
    int effectiveTimeInSeconds = 3600,
  }) async {
    final payload = {
      'user_id': userId,
      'role': role,
      'room_id': roomId,
      if (streamIdList != null) 'stream_id_list': streamIdList,
      'effective_time_in_seconds': effectiveTimeInSeconds,
    };
    final res = await invokeFunction(name: 'zego_token', body: payload);
    final token = res['token'] as String?;
    if (token == null || token.isEmpty) {
      throw Exception('Failed to fetch Zego token');
    }
    return token;
  }
}
