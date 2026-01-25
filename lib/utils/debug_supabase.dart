import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseDebugger {
  static final _supabase = Supabase.instance.client;

  static Future<Map<String, dynamic>> runDiagnostics() async {
    final results = <String, dynamic>{};

    try {
      // Test basic connection
      results['connection_test'] = await _testConnection();

      // Test authentication
      results['auth_test'] = await _testAuth();

      // Test database access
      results['database_test'] = await _testDatabase();

      // Test storage access
      results['storage_test'] = await _testStorage();

      // Test RLS policies
      results['rls_test'] = await _testRLSPolicies();
    } catch (e) {
      results['error'] = e.toString();
    }

    return results;
  }

  static Future<Map<String, dynamic>> _testConnection() async {
    try {
      final response = await _supabase.from('users').select('count').count();
      return {
        'success': true,
        'message': 'Connection successful',
        'user_count': response.count,
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> _testAuth() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        return {'success': false, 'message': 'No authenticated user'};
      }

      return {
        'success': true,
        'user_id': user.id,
        'email': user.email,
        'session_valid': !(_supabase.auth.currentSession?.isExpired ?? true),
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> _testDatabase() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        return {
          'success': false,
          'message': 'No authenticated user for database test',
        };
      }

      // Test reading user profile
      final profile = await _supabase
          .from('users')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      return {
        'success': true,
        'profile_exists': profile != null,
        'profile_data': profile,
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> _testStorage() async {
    try {
      // Test listing buckets
      final buckets = await _supabase.storage.listBuckets();

      final bucketNames = buckets.map((b) => b.name).toList();

      return {
        'success': true,
        'buckets': bucketNames,
        'profile_images_exists': bucketNames.contains('profile-images'),
        'post_images_exists': bucketNames.contains('post-images'),
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> _testRLSPolicies() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        return {
          'success': false,
          'message': 'No authenticated user for RLS test',
        };
      }

      // Test inserting a dummy post
      final testPost = {
        'user_id': user.id,
        'type': 'text',
        'caption': 'Test post for RLS validation',
        'is_public': true,
        'allow_comments': true,
        'allow_duets': true,
      };

      final insertResult = await _supabase
          .from('posts')
          .insert(testPost)
          .select()
          .single();

      // Clean up test post
      await _supabase.from('posts').delete().eq('id', insertResult['id']);

      return {
        'success': true,
        'message': 'RLS policies working correctly',
        'test_post_id': insertResult['id'],
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  static void printResults(Map<String, dynamic> results) {
    if (kDebugMode) {
      debugPrint(('\n=== SUPABASE DIAGNOSTICS ===').toString());
      results.forEach((key, value) {
        debugPrint(('$key: $value').toString());
      });
      debugPrint(('=== END DIAGNOSTICS ===\n').toString());
    }
  }
}

