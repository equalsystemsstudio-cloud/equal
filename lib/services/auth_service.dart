import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'enhanced_notification_service.dart';
import 'dart:async';
import 'dart:io';
import 'package:url_launcher/url_launcher.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;
  bool _isRefreshing = false;

  // Get current user
  User? get currentUser => _supabase.auth.currentUser;

  // Check if user is authenticated
  bool get isAuthenticated => currentUser != null;

  // Get auth state stream
  Stream<AuthState> get authStateChanges => _supabase.auth.onAuthStateChange;

  // Check if session is expired and refresh if needed
  Future<bool> _ensureValidSession() async {
    if (_isRefreshing) {
      // Wait for ongoing refresh to complete
      while (_isRefreshing) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      return isAuthenticated;
    }

    final session = _supabase.auth.currentSession;
    if (session == null) return false;

    // Check if token is expired or will expire in the next 5 minutes
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(
      session.expiresAt! * 1000,
    );
    final now = DateTime.now();
    final timeUntilExpiry = expiresAt.difference(now);

    if (timeUntilExpiry.inMinutes <= 5) {
      if (kDebugMode) {
        debugPrint(
          '🔄 Token expires in ${timeUntilExpiry.inMinutes} minutes, refreshing...',
        );
      }
      return await _refreshSession();
    }

    return true;
  }

  // Refresh the current session
  Future<bool> _refreshSession() async {
    if (_isRefreshing) return isAuthenticated;

    _isRefreshing = true;
    try {
      final response = await _supabase.auth.refreshSession();
      if (kDebugMode) {
        debugPrint('✅ Session refreshed successfully');
      }
      return response.session != null;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Failed to refresh session: $e');
      }
      // If refresh fails, sign out the user
      await signOut();
      return false;
    } finally {
      _isRefreshing = false;
    }
  }

  // Wrapper for authenticated operations
  Future<T> _withValidSession<T>(Future<T> Function() operation) async {
    try {
      final isValid = await _ensureValidSession();
      if (!isValid) {
        throw Exception('Session expired. Please log in again.');
      }
      return await operation();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Auth operation error: $e');
      }
      rethrow;
    }
  }

  // Sign up with email and password
  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String fullName,
    required String username,
    DateTime? dateOfBirth,
  }) async {
    try {
      final response = await _supabase.auth.signUp(
        email: email,
        password: password,
        emailRedirectTo: 'equal://auth/callback',
        data: {
          'display_name':
              fullName, // Fixed: use display_name instead of full_name
          'username': username,
          'avatar_url': '',
          'bio': '',
          'followers_count': 0,
          'following_count': 0,
          'posts_count': 0,
          'verified': false,
          'created_at': DateTime.now().toIso8601String(),
          if (dateOfBirth != null)
            'date_of_birth': dateOfBirth.toIso8601String(),
        },
      );

      if (response.user != null) {
        // Create user profile in profiles table
        await _createUserProfile(response.user!);
      }

      return response;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Sign up error: $e');
      }
      rethrow;
    }
  }

  // Sign in with email and password
  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    const int maxAttempts = 3;
    int attempt = 0;

    while (true) {
      attempt++;
      try {
        final response = await _supabase.auth.signInWithPassword(
          email: email,
          password: password,
        );

        // Check if email is verified
        if (response.user != null && response.user!.emailConfirmedAt == null) {
          await signOut();
          throw const AuthException(
            'Please verify your email before logging in.',
            statusCode: '403',
          );
        }

        return response;
      } on AuthRetryableFetchException catch (e) {
        if (kDebugMode) {
          debugPrint(
            'Sign in retryable fetch error (attempt $attempt/$maxAttempts): $e',
          );
        }
        if (attempt >= maxAttempts) {
          rethrow;
        }
        final delayMs = 500 * (1 << (attempt - 1)); // 500ms, 1000ms, 2000ms
        await Future.delayed(Duration(milliseconds: delayMs));
        continue;
      } on SocketException catch (e) {
        if (kDebugMode) {
          debugPrint(
            'Sign in network error (attempt $attempt/$maxAttempts): $e',
          );
        }
        if (attempt >= maxAttempts) {
          rethrow;
        }
        final delayMs = 500 * (1 << (attempt - 1));
        await Future.delayed(Duration(milliseconds: delayMs));
        continue;
      } on TimeoutException catch (e) {
        if (kDebugMode) {
          debugPrint('Sign in timeout (attempt $attempt/$maxAttempts): $e');
        }
        if (attempt >= maxAttempts) {
          rethrow;
        }
        final delayMs = 500 * (1 << (attempt - 1));
        await Future.delayed(Duration(milliseconds: delayMs));
        continue;
      } catch (e) {
        if (kDebugMode) {
          debugPrint('Sign in error: $e');
        }
        rethrow;
      }
    }
  }

  // Sign out
  Future<void> signOut() async {
    try {
      await _supabase.auth.signOut();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Sign out error: $e');
      }
      rethrow;
    }
  }

  // Reset password via OTP
  Future<void> resetPassword(String email) async {
    try {
      await _supabase.auth.signInWithOtp(email: email, shouldCreateUser: false);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Reset password error: $e');
      }
      rethrow;
    }
  }

  // Verify OTP for password recovery
  Future<AuthResponse> verifyOtp({
    required String email,
    required String token,
  }) async {
    try {
      return await _supabase.auth.verifyOTP(
        email: email,
        token: token,
        type: OtpType.email,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Verify OTP error: $e');
      }
      rethrow;
    }
  }

  // Update user profile with enhanced session validation
  Future<UserResponse> updateProfile({
    String? fullName,
    String? username,
    String? bio,
    String? avatarUrl,
    bool? isPrivate,
  }) async {
    try {
      final isValid = await _ensureValidSession();
      if (!isValid) {
        throw Exception('Session expired. Please log in again.');
      }
      if (currentUser == null) {
        throw Exception('User not authenticated. Please log in again.');
      }

      final updates = <String, dynamic>{};
      if (fullName != null) {
        updates['display_name'] =
            fullName; // Fixed: use display_name instead of full_name
      }
      if (username != null) updates['username'] = username;
      if (bio != null) updates['bio'] = bio;
      if (avatarUrl != null) updates['avatar_url'] = avatarUrl;
      if (isPrivate != null) updates['is_private'] = isPrivate;
      updates['updated_at'] = DateTime.now().toIso8601String();

      // Remove any null values that might cause issues
      updates.removeWhere((key, value) => value == null);

      if (kDebugMode) {
        debugPrint(
          ('🔥 AUTH SERVICE - Updating profile with data: $updates').toString(),
        );
        debugPrint(
          ('🔥 AUTH SERVICE - Current user ID: ${currentUser!.id}').toString(),
        );
        debugPrint(('🔥 AUTH SERVICE - Session valid: $isValid').toString());
      }

      // Check if username is available before updating
      if (username != null) {
        final currentProfile = await getCurrentUserProfile();
        if (currentProfile != null && currentProfile['username'] != username) {
          final isAvailable = await isUsernameAvailable(username);
          if (!isAvailable) {
            throw Exception(
              'Username already exists. Please choose a different username.',
            );
          }
        }
      }

      // Update auth user metadata
      final response = await _supabase.auth.updateUser(
        UserAttributes(data: updates),
      );

      if (response.user == null) {
        throw Exception('Failed to update auth user metadata');
      }

      if (kDebugMode) {
        debugPrint(
          ('Auth update response: ${response.user?.userMetadata}').toString(),
        );
      }

      // Update the users table with RLS-compliant query
      if (kDebugMode) {
        debugPrint(('=== ATTEMPTING DATABASE UPDATE ===').toString());
        debugPrint(('User ID: ${currentUser!.id}').toString());
        debugPrint(('Update data: $updates').toString());
        debugPrint(
          (
            'Session: ${_supabase.auth.currentSession?.accessToken.substring(0, 20)}...',
          ).toString(),
        );
      }

      final dbResponse = await _supabase
          .from('users')
          .update(updates)
          .eq('id', currentUser!.id)
          .select()
          .single();

      if (kDebugMode) {
        debugPrint(('Database update response: $dbResponse').toString());
        debugPrint(('=== UPDATE SUCCESSFUL ===').toString());
      }

      return response;
    } catch (e) {
      if (kDebugMode) {
        debugPrint(('=== UPDATE PROFILE ERROR ===').toString());
        debugPrint(('Error details: $e').toString());
        debugPrint(('Error type: ${e.runtimeType}').toString());
        debugPrint(('Current user ID: ${currentUser?.id}').toString());
        debugPrint(
          ('Session exists: ${_supabase.auth.currentSession != null}')
              .toString(),
        );
        debugPrint(
          ('Session expired: ${_supabase.auth.currentSession?.isExpired}')
              .toString(),
        );

        // Provide specific error analysis
        final errorStr = e.toString().toLowerCase();
        if (errorStr.contains('row level security') ||
            errorStr.contains('rls')) {
          debugPrint(
            (
              '❌ RLS Policy Issue: User may not have permission to update their profile',
            ).toString(),
          );
          debugPrint(
            (
              'Check that RLS policy allows users to update their own records',
            ).toString(),
          );
        } else if (errorStr.contains('jwt') || errorStr.contains('token')) {
          debugPrint(
            ('❌ JWT Token Issue: Session may be invalid or expired').toString(),
          );
        } else if (errorStr.contains('permission') ||
            errorStr.contains('unauthorized')) {
          debugPrint(
            ('❌ Permission Issue: User lacks necessary permissions').toString(),
          );
        } else if (errorStr.contains('network') ||
            errorStr.contains('connection')) {
          debugPrint(('❌ Network Issue: Connection problem').toString());
        } else if (errorStr.contains('constraint') ||
            errorStr.contains('unique')) {
          debugPrint(
            ('❌ Database Constraint: Likely duplicate username').toString(),
          );
        } else {
          debugPrint(('❌ Unknown Error Type').toString());
        }
        debugPrint(('=== END ERROR DEBUG ===').toString());
      }
      rethrow;
    }
  }

  // Get user profile
  Future<Map<String, dynamic>?> getUserProfile([String? userId]) async {
    try {
      return await _withValidSession(() async {
        final id = userId ?? currentUser?.id;
        if (id == null) return null;

        final response = await _supabase
            .from('users')
            .select()
            .eq('id', id)
            .maybeSingle();

        // Auto-create profile if missing for current user
        if (response == null && currentUser != null && currentUser!.id == id) {
          await _createUserProfile(currentUser!);
          return await _supabase
              .from('users')
              .select()
              .eq('id', id)
              .maybeSingle();
        }

        return response;
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Get user profile error: $e');
      }
      return null;
    }
  }

  // Get current user profile
  Future<Map<String, dynamic>?> getCurrentUserProfile() async {
    return getUserProfile();
  }

  // Backwards-compatible helper expected by some screens
  Future<Map<String, dynamic>?> getCurrentUser() async {
    return getCurrentUserProfile();
  }

  // Create user profile in database
  Future<void> _createUserProfile(User user) async {
    try {
      await _supabase.from('users').insert({
        'id': user.id,
        'email': user.email,
        'display_name':
            user.userMetadata?['display_name'] ??
            '', // Fixed: use display_name instead of full_name
        'username':
            ((user.userMetadata?['username'] as String?)?.trim().isNotEmpty ==
                true)
            ? (user.userMetadata?['username'] as String)
            : (user.email?.split('@').first ?? user.id.substring(0, 8)),
        'avatar_url': user.userMetadata?['avatar_url'] ?? '',
        'bio': user.userMetadata?['bio'] ?? '',
        'followers_count': 0,
        'following_count': 0,
        'posts_count': 0,
        'is_verified': false,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Create user profile error: $e');
      }
      // Don't rethrow as this is not critical for auth
    }
  }

  // Check if username is available
  Future<bool> isUsernameAvailable(String username) async {
    try {
      // Don't require authentication for username availability check
      // This allows checking during registration when user isn't authenticated yet
      final response = await _supabase
          .from('users')
          .select('username')
          .eq('username', username.toLowerCase())
          .maybeSingle();

      return response == null;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Check username availability error: $e');
      }
      return false;
    }
  }

  // Follow user
  Future<void> followUser(String userId) async {
    try {
      final isValid = await _ensureValidSession();
      if (!isValid) {
        throw Exception('Session expired. Please log in again.');
      }

      if (currentUser == null) {
        throw Exception('User not authenticated');
      }

      // Ensure follower record exists in users (avoid FK violation)
      try {
        final followerRow = await _supabase
            .from('users')
            .select('id')
            .eq('id', currentUser!.id)
            .maybeSingle();
        if (followerRow == null) {
          await _createUserProfile(currentUser!);
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('Ensure follower profile error: $e');
        }
        // Don't abort: attempt follow insert anyway
      }

      // Ensure target user record exists (best-effort check)
      try {
        final targetRow = await _supabase
            .from('users')
            .select('id')
            .eq('id', userId)
            .maybeSingle();
        if (targetRow == null) {
          // We cannot create other user's profile; surface meaningful error
          throw Exception('Target profile not found');
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('Ensure target profile error: $e');
        }
        // Proceed; insert may fail and be caught later
      }

      // Avoid duplicate follow attempts if already following
      try {
        final alreadyFollowing = await isFollowing(userId);
        if (alreadyFollowing) {
          return;
        }
      } catch (_) {}

      // Insert follow relationship (critical path)
      try {
        await _supabase.from('follows').insert({
          'follower_id': currentUser!.id,
          'following_id': userId,
          'created_at': DateTime.now().toIso8601String(),
        });
      } catch (e) {
        if (kDebugMode) {
          debugPrint('Follow insert error: $e');
        }
        // If duplicate unique constraint violation occurs, treat as already-following
        if (e is PostgrestException && e.code == '23505') {
          // Duplicate key: follows(follower_id, following_id) already exists
          return; // No need to update counts or notify
        }
        rethrow;
      }

      // Update follower count for the followed user (non-critical; fallback to direct update if RPC missing)
      try {
        await _supabase.rpc(
          'increment_followers_count',
          params: {'user_id': userId},
        );
      } catch (e) {
        if (kDebugMode) {
          debugPrint(
            'RPC increment_followers_count failed, applying fallback: $e',
          );
        }
        try {
          final row = await _supabase
              .from('users')
              .select('followers_count')
              .eq('id', userId)
              .maybeSingle();
          final current = (row?['followers_count'] as int?) ?? 0;
          await _supabase
              .from('users')
              .update({'followers_count': current + 1})
              .eq('id', userId);
        } catch (inner) {
          if (kDebugMode) {
            debugPrint('Fallback followers_count update failed: $inner');
          }
        }
      }

      // Update following count for current user (non-critical; fallback to direct update if RPC missing)
      try {
        await _supabase.rpc(
          'increment_following_count',
          params: {'user_id': currentUser!.id},
        );
      } catch (e) {
        if (kDebugMode) {
          debugPrint(
            'RPC increment_following_count failed, applying fallback: $e',
          );
        }
        try {
          final row = await _supabase
              .from('users')
              .select('following_count')
              .eq('id', currentUser!.id)
              .maybeSingle();
          final current = (row?['following_count'] as int?) ?? 0;
          await _supabase
              .from('users')
              .update({'following_count': current + 1})
              .eq('id', currentUser!.id);
        } catch (inner) {
          if (kDebugMode) {
            debugPrint('Fallback following_count update failed: $inner');
          }
        }
      }

      // Immediately notify the tracked user with follower username
      try {
        final followerUsername =
            currentUser!.userMetadata?['username'] ?? 'Someone';
        await EnhancedNotificationService().createFollowNotification(
          followedUserId: userId,
          followerName: followerUsername,
        );
      } catch (e) {
        if (kDebugMode) {
          debugPrint('Failed to create follow notification: $e');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Follow user error: $e');
      }
      rethrow;
    }
  }

  // Unfollow user
  Future<void> unfollowUser(String userId) async {
    try {
      final isValid = await _ensureValidSession();
      if (!isValid) {
        throw Exception('Session expired. Please log in again.');
      }

      if (currentUser == null) {
        throw Exception('User not authenticated');
      }

      // Delete follow relationship
      await _supabase
          .from('follows')
          .delete()
          .eq('follower_id', currentUser!.id)
          .eq('following_id', userId);

      // Send untracking notification to the user
      try {
        final unfollowerName =
            currentUser!.userMetadata?['username'] ?? 'Someone';
        await EnhancedNotificationService().createUnfollowNotification(
          unfollowedUserId: userId,
          unfollowerName: unfollowerName,
        );
      } catch (e) {
        if (kDebugMode) {
          debugPrint('Failed to create unfollow notification: $e');
        }
      }

      // Update follower count for the unfollowed user (non-critical; fallback if RPC missing)
      try {
        await _supabase.rpc(
          'decrement_followers_count',
          params: {'user_id': userId},
        );
      } catch (e) {
        if (kDebugMode) {
          debugPrint(
            'RPC decrement_followers_count failed, applying fallback: $e',
          );
        }
        try {
          final row = await _supabase
              .from('users')
              .select('followers_count')
              .eq('id', userId)
              .maybeSingle();
          final current = (row?['followers_count'] as int?) ?? 0;
          await _supabase
              .from('users')
              .update({'followers_count': current > 0 ? current - 1 : 0})
              .eq('id', userId);
        } catch (inner) {
          if (kDebugMode) {
            debugPrint('Fallback followers_count decrement failed: $inner');
          }
        }
      }

      // Update following count for current user (non-critical; fallback if RPC missing)
      try {
        await _supabase.rpc(
          'decrement_following_count',
          params: {'user_id': currentUser!.id},
        );
      } catch (e) {
        if (kDebugMode) {
          debugPrint(
            'RPC decrement_following_count failed, applying fallback: $e',
          );
        }
        try {
          final row = await _supabase
              .from('users')
              .select('following_count')
              .eq('id', currentUser!.id)
              .maybeSingle();
          final current = (row?['following_count'] as int?) ?? 0;
          await _supabase
              .from('users')
              .update({'following_count': current > 0 ? current - 1 : 0})
              .eq('id', currentUser!.id);
        } catch (inner) {
          if (kDebugMode) {
            debugPrint('Fallback following_count decrement failed: $inner');
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Unfollow user error: $e');
      }
      rethrow;
    }
  }

  // Check if current user is following another user
  Future<bool> isFollowing(String userId) async {
    try {
      if (currentUser == null) return false;

      final response = await _supabase
          .from('follows')
          .select()
          .eq('follower_id', currentUser!.id)
          .eq('following_id', userId)
          .maybeSingle();

      return response != null;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Check following status error: $e');
      }
      return false;
    }
  }

  // Report user
  Future<void> reportUser(
    String userId,
    String reason, {
    String? details,
  }) async {
    try {
      if (currentUser == null) {
        throw Exception('User not authenticated');
      }

      await _supabase.from('reports').insert({
        'reporter_id': currentUser!.id,
        'reported_user_id': userId,
        'reason': reason,
        if (details != null) 'details': details,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Report user error: $e');
      }
      rethrow;
    }
  }

  // Block user
  Future<void> blockUser(String userId) async {
    try {
      if (currentUser == null) {
        throw Exception('User not authenticated');
      }

      await _supabase.from('blocks').insert({
        'blocker_id': currentUser!.id,
        'blocked_id': userId,
        'created_at': DateTime.now().toIso8601String(),
      });

      // Also unfollow if following
      final isFollowingUser = await isFollowing(userId);
      if (isFollowingUser) {
        await unfollowUser(userId);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Block user error: $e');
      }
      rethrow;
    }
  }

  // Unblock user
  Future<void> unblockUser(String userId) async {
    try {
      if (currentUser == null) {
        throw Exception('User not authenticated');
      }

      await _supabase
          .from('blocks')
          .delete()
          .eq('blocker_id', currentUser!.id)
          .eq('blocked_id', userId);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Unblock user error: $e');
      }
      rethrow;
    }
  }

  // Get blocked users
  Future<List<Map<String, dynamic>>> getBlockedUsers() async {
    try {
      if (currentUser == null) return [];

      final response = await _supabase
          .from('blocks')
          .select(
            'blocked_id, users!blocks_blocked_id_fkey(id, username, display_name, avatar_url)',
          ) // Fixed: use display_name instead of full_name
          .eq('blocker_id', currentUser!.id);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Get blocked users error: $e');
      }
      return [];
    }
  }

  // Check if user is blocked
  Future<bool> isBlocked(String userId) async {
    try {
      if (currentUser == null) return false;

      final response = await _supabase
          .from('blocks')
          .select('id')
          .eq('blocker_id', currentUser!.id)
          .eq('blocked_id', userId)
          .maybeSingle();

      return response != null;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Check blocked user error: $e');
      }
      return false;
    }
  }

  // Check if current user is blocked by another user
  Future<bool> isBlockedBy(String userId) async {
    try {
      if (currentUser == null) return false;

      final response = await _supabase
          .from('blocks')
          .select('id')
          .eq('blocker_id', userId)
          .eq('blocked_id', currentUser!.id)
          .maybeSingle();

      return response != null;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Check blocked by user error: $e');
      }
      return false;
    }
  }

  // Delete account
  Future<void> deleteAccount() async {
    try {
      final user = currentUser;
      if (user == null) return;

      final subject = Uri.encodeComponent('Account deletion request');
      final body = Uri.encodeComponent(
        'Please delete my account.\n\nUser ID: ${user.id}\nEmail: ${user.email ?? ''}\nRequested at: ${DateTime.now().toIso8601String()}',
      );
      final uri = Uri.parse(
        'mailto:support@equal-co.com?subject=$subject&body=$body',
      );

      final canLaunch = await canLaunchUrl(uri);
      if (!canLaunch) {
        throw Exception('No email app available');
      }

      final launched = await launchUrl(uri, mode: LaunchMode.platformDefault);

      if (!launched) {
        throw Exception('Failed to open email composer');
      }

      if (kDebugMode) {
        debugPrint('Opened email composer for account deletion request');
      }
      // We do NOT sign out here; support will process the request manually.
    } on TimeoutException {
      if (kDebugMode) {
        debugPrint('Delete account timed out');
      }
      throw Exception('Delete account timed out');
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Delete account error: $e');
      }
      rethrow;
    }
  }
}
