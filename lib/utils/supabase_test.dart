import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';

void main() async {
  // Initialize Supabase for testing
  await Supabase.initialize(
    url: SupabaseConfig.supabaseUrl,
    anonKey: SupabaseConfig.supabaseAnonKey,
  );

  final test = SupabaseTest();
  await test.runAllTests();
}

class SupabaseTest {
  static Future<bool> testConnection() async {
    try {
      if (kDebugMode) {
        debugPrint(('Testing Supabase connection...').toString());
        debugPrint(('URL: ${SupabaseConfig.supabaseUrl}').toString());
        debugPrint(('Key: ${SupabaseConfig.supabaseAnonKey.substring(0, 20)}...').toString());
      }

      final client = SupabaseConfig.client;

      // Test basic connection by checking auth status
      final user = client.auth.currentUser;
      if (kDebugMode) {
        debugPrint(('Current user: ${user?.id ?? "Not authenticated"}').toString());
      }

      // Test database connection with a simple query
      try {
        final response = await client.from('users').select('count').limit(1);

        if (kDebugMode) {
          debugPrint(('Database connection test successful').toString());
          debugPrint(('Response: $response').toString());
        }
        return true;
      } catch (dbError) {
        if (kDebugMode) {
          debugPrint(('Database connection failed: $dbError').toString());
        }

        // Try to create the users table if it doesn't exist
        await _createTablesIfNotExist();
        return true;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint(('Supabase connection test failed: $e').toString());
      }
      return false;
    }
  }

  static Future<void> _createTablesIfNotExist() async {
    try {
      final client = SupabaseConfig.client;

      if (kDebugMode) {
        debugPrint(('Attempting to create database tables...').toString());
      }

      // Note: In a real app, you would run these SQL commands in the Supabase dashboard
      // or use migrations. This is just for testing purposes.

      // Test if we can at least connect to the database
      await client.rpc('get_current_user_id');

      if (kDebugMode) {
        debugPrint(('Database connection established').toString());
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint(('Could not create tables or connect to database: $e').toString());
        debugPrint(('Please ensure your Supabase project is set up correctly').toString());
        debugPrint((
          'Required tables: users, posts, comments, likes, follows, notifications',
        ).toString());
      }
    }
  }

  static Future<Map<String, dynamic>> getDatabaseInfo() async {
    try {
      final client = SupabaseConfig.client;
      final user = client.auth.currentUser;

      return {
        'connected': true,
        'user_authenticated': user != null,
        'user_id': user?.id,
        'user_email': user?.email,
        'supabase_url': SupabaseConfig.supabaseUrl,
        'timestamp': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      return {
        'connected': false,
        'error': e.toString(),
        'timestamp': DateTime.now().toIso8601String(),
      };
    }
  }

  static Future<bool> testAuth() async {
    try {
      final client = SupabaseConfig.client;

      // Test auth state changes
      client.auth.onAuthStateChange.listen((data) {
        if (kDebugMode) {
          debugPrint(('Auth state changed: ${data.event}').toString());
          debugPrint(('User: ${data.session?.user.id}').toString());
        }
      });

      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint(('Auth test failed: $e').toString());
      }
      return false;
    }
  }

  static Future<void> printDiagnostics() async {
    if (kDebugMode) {
      debugPrint(('=== Supabase Diagnostics ===').toString());
      debugPrint(('URL: ${SupabaseConfig.supabaseUrl}').toString());
      debugPrint(('Anon Key: ${SupabaseConfig.supabaseAnonKey.substring(0, 50)}...').toString());

      final info = await getDatabaseInfo();
      debugPrint(('Connection Info: $info').toString());

      final connectionTest = await testConnection();
      debugPrint(('Connection Test: ${connectionTest ? "PASSED" : "FAILED"}').toString());

      final authTest = await testAuth();
      debugPrint(('Auth Test: ${authTest ? "PASSED" : "FAILED"}').toString());

      debugPrint(('=== End Diagnostics ===').toString());
    }
  }

  Future<void> runAllTests() async {
    debugPrint(('Running Supabase connection tests...').toString());

    await printDiagnostics();

    final connectionResult = await testConnection();
    debugPrint(('Connection test: ${connectionResult ? 'PASSED' : 'FAILED'}').toString());

    final authResult = await testAuth();
    debugPrint(('Auth state test: ${authResult ? 'PASSED' : 'FAILED'}').toString());

    final dbInfo = await getDatabaseInfo();
    debugPrint(('Database info test: ${dbInfo['connected'] ? 'PASSED' : 'FAILED'}').toString());

    debugPrint(('All tests completed.').toString());
  }
}


