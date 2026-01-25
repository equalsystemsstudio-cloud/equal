import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';

class ReferralService {
  final SupabaseClient _client = Supabase.instance.client;

  Future<String?> getReferralCode() async {
    try {
      final res = await _client
          .rpc('get_or_create_referral_code')
          .timeout(const Duration(seconds: 5));
      if (res is String) return res;
      return res?.toString();
    } on TimeoutException {
      // Silent fallback when RPC is slow/missing
      return null;
    } catch (e) {
      // Suppress known schema cache errors for missing RPC definition
      if (e is PostgrestException && e.code == 'PGRST202') {
        return null;
      }
      if (kDebugMode) {
        debugPrint('ReferralService.getReferralCode error: $e');
      }
      return null;
    }
  }

  Future<Map<String, dynamic>> getReferralStats({String? userId}) async {
    try {
      final uid = userId ?? _client.auth.currentUser?.id;
      if (uid == null) return _emptyStats();
      final res = await _client
          .rpc('get_referral_stats', params: {'user_id': uid})
          .timeout(const Duration(seconds: 5));
      if (res is Map<String, dynamic>) {
        return {
          'total': res['total'] ?? 0,
          'verified': res['verified'] ?? 0,
          'next_milestone_remaining': res['next_milestone_remaining'] ?? 5,
          'awarded_milestones': res['awarded_milestones'] ?? 0,
          'total_awarded_months': res['total_awarded_months'] ?? 0,
        };
      }
      return _emptyStats();
    } on TimeoutException {
      return _emptyStats();
    } catch (e) {
      if (e is PostgrestException && e.code == 'PGRST202') {
        // RPC not defined — return empty stats silently
        return _emptyStats();
      }
      if (kDebugMode) {
        debugPrint('ReferralService.getReferralStats error: $e');
      }
      return _emptyStats();
    }
  }

  Future<bool> claimReferral(String code) async {
    try {
      final res = await _client
          .rpc('claim_referral', params: {'code': code})
          .timeout(const Duration(seconds: 5));
      return res == true;
    } on TimeoutException {
      return false;
    } catch (e) {
      if (e is PostgrestException && e.code == 'PGRST202') {
        // Missing RPC definition
        return false;
      }
      if (kDebugMode) {
        debugPrint('ReferralService.claimReferral error: $e');
      }
      return false;
    }
  }

  Future<bool> awardCreditsForVerifiedUser(String userId) async {
    // Optional manual call; normally handled by DB trigger on users.is_verified
    try {
      final res = await _client
          .rpc('award_credits_on_verification', params: {'referred': userId})
          .timeout(const Duration(seconds: 5));
      return res is Map<String, dynamic> &&
          (res['status'] == 'awarded' || res['status'] == 'already_awarded');
    } on TimeoutException {
      return false;
    } catch (e) {
      if (e is PostgrestException && e.code == 'PGRST202') {
        return false;
      }
      if (kDebugMode) {
        debugPrint('ReferralService.awardCreditsForVerifiedUser error: $e');
      }
      return false;
    }
  }

  Map<String, dynamic> _emptyStats() => {
        'total': 0,
        'verified': 0,
        'next_milestone_remaining': 5,
        'awarded_milestones': 0,
        'total_awarded_months': 0,
      };
}

