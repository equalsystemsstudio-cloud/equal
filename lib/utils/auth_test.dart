import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';

class AuthTest {
  static Future<bool> testSupabaseConnection() async {
    try {
      if (kDebugMode) {
        debugPrint(('Testing Supabase connection...').toString());
        debugPrint(('URL: ${SupabaseConfig.supabaseUrl}').toString());
        debugPrint(('Key: ${SupabaseConfig.supabaseAnonKey.substring(0, 20)}...').toString());
      }
      
      final client = Supabase.instance.client;
      
      // Test basic connection by checking auth status
      final user = client.auth.currentUser;
      if (kDebugMode) {
        debugPrint(('Current user: ${user?.id ?? 'Not authenticated'}').toString());
      }
      
      // Test database connection with a simple query
      try {
        await client
            .from('users')
            .select('count')
            .limit(1);
        
        if (kDebugMode) {
          debugPrint(('Database connection test: SUCCESS').toString());
        }
        return true;
      } catch (dbError) {
        if (kDebugMode) {
          debugPrint(('Database connection test failed: $dbError').toString());
        }
        return false;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint(('Supabase connection test failed: $e').toString());
      }
      return false;
    }
  }
  
  static Future<void> printAuthDiagnostics() async {
    if (kDebugMode) {
      final client = Supabase.instance.client;
      debugPrint(('=== Auth Diagnostics ===').toString());
      debugPrint(('Client initialized: true').toString());
      debugPrint(('Current session: ${client.auth.currentSession != null}').toString());
      debugPrint(('Current user: ${client.auth.currentUser?.id ?? 'None'}').toString());
      debugPrint(('Auth URL: ${SupabaseConfig.supabaseUrl}/auth/v1').toString());
      debugPrint(('========================').toString());
    }
  }
}
