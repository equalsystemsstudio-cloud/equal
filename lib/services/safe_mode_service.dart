import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SafeModeService {
  final SupabaseClient _client = Supabase.instance.client;

  Future<bool> getSafeMode() async {
    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) return true; // default safe
      final data = await _client
          .from('users')
          .select('safe_mode')
          .eq('id', uid)
          .maybeSingle();
      final val = data?['safe_mode'];
      return (val is bool) ? val : true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SafeModeService] getSafeMode error: $e');
      }
      return true;
    }
  }

  Future<bool> setSafeMode(bool enabled) async {
    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) return false;
      final res = await _client
          .from('users')
          .update({'safe_mode': enabled})
          .eq('id', uid);
      if (kDebugMode) {
        debugPrint('[SafeModeService] setSafeMode result: $res');
      }
      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SafeModeService] setSafeMode error: $e');
      }
      return false;
    }
  }
}

