import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

/// Comprehensive Supabase Authentication Debugging Utility
/// This utility helps debug common authentication and RLS issues
class SupabaseAuthDebug {
  static final SupabaseClient _supabase = Supabase.instance.client;

  /// Safely format timestamp to avoid RangeError
  static String _safeFormatTimestamp(int timestamp) {
    try {
      // Try as seconds first (Unix timestamp)
      if (timestamp < 10000000000) {
        return DateTime.fromMillisecondsSinceEpoch(
          timestamp * 1000,
        ).toIso8601String();
      }
      // Try as milliseconds
      return DateTime.fromMillisecondsSinceEpoch(timestamp).toIso8601String();
    } catch (e) {
      return 'Invalid timestamp: $timestamp (Error: $e)';
    }
  }

  /// Debug current session state
  static Future<Map<String, dynamic>> debugSession() async {
    final session = _supabase.auth.currentSession;
    final user = _supabase.auth.currentUser;

    final debugInfo = {
      'hasSession': session != null,
      'hasUser': user != null,
      'sessionExpired': session?.isExpired ?? true,
      'accessToken': session?.accessToken != null
          ? (session!.accessToken.length > 20
                ? '${session.accessToken.substring(0, 20)}...'
                : session.accessToken)
          : 'null',
      'refreshToken': session?.refreshToken != null
          ? (session!.refreshToken!.length > 20
                ? '${session.refreshToken!.substring(0, 20)}...'
                : session.refreshToken!)
          : 'null',
      'userId': user?.id ?? 'null',
      'userEmail': user?.email ?? 'null',
      'userRole': user?.role ?? 'null',
      'sessionExpiresAt': session?.expiresAt != null
          ? _safeFormatTimestamp(session!.expiresAt!)
          : 'null',
      'tokenExpiresIn': session?.expiresIn ?? 0,
    };

    if (kDebugMode) {
      debugPrint(('=== SUPABASE SESSION DEBUG ===').toString());
      debugInfo.forEach((key, value) {
        debugPrint(('$key: $value').toString());
      });
      debugPrint(('==============================').toString());
    }

    return debugInfo;
  }

  /// Test RLS policies for users table
  static Future<Map<String, dynamic>> testRLSPolicies() async {
    final results = <String, dynamic>{};
    final user = _supabase.auth.currentUser;

    if (user == null) {
      results['error'] = 'No authenticated user';
      return results;
    }

    try {
      // Test SELECT policy
      final selectResult = await _supabase
          .from('users')
          .select('id, username, display_name')
          .eq('id', user.id)
          .maybeSingle();

      results['select_own_profile'] = selectResult != null
          ? 'SUCCESS'
          : 'FAILED';

      // Test UPDATE policy with a simple update
      final updateResult = await _supabase
          .from('users')
          .update({'updated_at': DateTime.now().toIso8601String()})
          .eq('id', user.id)
          .select()
          .maybeSingle();

      results['update_own_profile'] = updateResult != null
          ? 'SUCCESS'
          : 'FAILED';

      // Test INSERT policy (this should fail if user already exists)
      try {
        await _supabase.from('users').insert({
          'id': user.id,
          'username': 'test_${DateTime.now().millisecondsSinceEpoch}',
          'email': user.email,
        });
        results['insert_policy'] = 'UNEXPECTED_SUCCESS';
      } catch (e) {
        if (e.toString().contains('duplicate key')) {
          results['insert_policy'] = 'SUCCESS (duplicate key expected)';
        } else {
          results['insert_policy'] = 'FAILED: $e';
        }
      }
    } catch (e) {
      results['rls_test_error'] = e.toString();
    }

    if (kDebugMode) {
      debugPrint(('=== RLS POLICIES TEST ===').toString());
      results.forEach((key, value) {
        debugPrint(('$key: $value').toString());
      });
      debugPrint(('========================').toString());
    }

    return results;
  }

  /// Test database connection and basic queries
  static Future<Map<String, dynamic>> testDatabaseConnection() async {
    final results = <String, dynamic>{};

    try {
      // Test basic connection
      final response = await _supabase.from('users').select('count').limit(1);

      results['connection'] = 'SUCCESS';
      results['query_response'] = response.toString();
    } catch (e) {
      results['connection'] = 'FAILED';
      results['error'] = e.toString();
    }

    if (kDebugMode) {
      debugPrint(('=== DATABASE CONNECTION TEST ===').toString());
      results.forEach((key, value) {
        debugPrint(('$key: $value').toString());
      });
      debugPrint(('===============================').toString());
    }

    return results;
  }

  /// Validate session and refresh if needed
  static Future<bool> validateAndRefreshSession() async {
    try {
      final session = _supabase.auth.currentSession;

      if (session == null) {
        if (kDebugMode) debugPrint(('No session found').toString());
        return false;
      }

      // Check if session is expired or will expire soon (within 5 minutes)
      final now = DateTime.now();
      final expiresAt = DateTime.fromMillisecondsSinceEpoch(
        session.expiresAt! * 1000,
      );
      final timeUntilExpiry = expiresAt.difference(now);

      if (timeUntilExpiry.inMinutes < 5) {
        if (kDebugMode) debugPrint(('Session expires soon, refreshing...').toString());

        final response = await _supabase.auth.refreshSession();

        if (response.session != null) {
          if (kDebugMode) debugPrint(('Session refreshed successfully').toString());
          return true;
        } else {
          if (kDebugMode) debugPrint(('Failed to refresh session').toString());
          return false;
        }
      }

      if (kDebugMode) debugPrint(('Session is valid').toString());
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint(('Session validation error: $e').toString());
      return false;
    }
  }

  /// Enhanced profile update with debugging
  static Future<Map<String, dynamic>> debugProfileUpdate(
    Map<String, dynamic> updates,
  ) async {
    final results = <String, dynamic>{};
    final user = _supabase.auth.currentUser;

    if (user == null) {
      results['error'] = 'No authenticated user';
      return results;
    }

    try {
      // Validate session first
      final sessionValid = await validateAndRefreshSession();
      results['session_valid'] = sessionValid;

      if (!sessionValid) {
        results['error'] = 'Invalid or expired session';
        return results;
      }

      // Add updated_at timestamp
      final updateData = Map<String, dynamic>.from(updates);
      updateData['updated_at'] = DateTime.now().toIso8601String();

      if (kDebugMode) {
        debugPrint(('=== PROFILE UPDATE DEBUG ===').toString());
        debugPrint(('User ID: ${user.id}').toString());
        debugPrint(('Update data: $updateData').toString());
        debugPrint(('===========================').toString());
      }

      // Perform the update with detailed error handling
      final response = await _supabase
          .from('users')
          .update(updateData)
          .eq('id', user.id)
          .select()
          .single();

      results['update_success'] = true;
      results['updated_data'] = response;

      if (kDebugMode) {
        debugPrint(('Update successful: $response').toString());
      }
    } catch (e) {
      results['update_success'] = false;
      results['error'] = e.toString();

      if (kDebugMode) {
        debugPrint(('Update failed: $e').toString());
        debugPrint(('Error type: ${e.runtimeType}').toString());
      }

      // Analyze common error types
      final errorStr = e.toString().toLowerCase();
      if (errorStr.contains('row level security')) {
        results['error_type'] = 'RLS_POLICY_VIOLATION';
        results['suggestion'] = 'Check RLS policies for users table';
      } else if (errorStr.contains('jwt')) {
        results['error_type'] = 'JWT_TOKEN_ISSUE';
        results['suggestion'] = 'Session token may be invalid or expired';
      } else if (errorStr.contains('permission')) {
        results['error_type'] = 'PERMISSION_DENIED';
        results['suggestion'] =
            'User may not have permission to update this record';
      } else {
        results['error_type'] = 'UNKNOWN';
        results['suggestion'] = 'Check Supabase logs for more details';
      }
    }

    return results;
  }

  /// Run comprehensive authentication diagnostics
  static Future<Map<String, dynamic>> runFullDiagnostics() async {
    if (kDebugMode) {
      debugPrint(('\n🔍 Running Supabase Authentication Diagnostics...').toString());
    }

    final diagnostics = <String, dynamic>{};

    // Test 1: Session state
    diagnostics['session'] = await debugSession();

    // Test 2: Database connection
    diagnostics['database'] = await testDatabaseConnection();

    // Test 3: RLS policies
    diagnostics['rls_policies'] = await testRLSPolicies();

    // Test 4: Session validation
    diagnostics['session_validation'] = await validateAndRefreshSession();

    if (kDebugMode) {
      debugPrint(('\n✅ Diagnostics completed!').toString());
      debugPrint(('Results: ${diagnostics.keys.join(", ")}').toString());
    }

    return diagnostics;
  }
}

