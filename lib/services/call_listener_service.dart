import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'calling_service.dart';
import '../screens/calling/calling_screen.dart';
import 'push_notification_service.dart';
import '../config/feature_flags.dart';

class CallListenerService {
  static final CallListenerService _instance = CallListenerService._internal();
  factory CallListenerService() => _instance;
  CallListenerService._internal();

  // ignore: unused_field
  final CallingService _callingService = CallingService();
  StreamSubscription<List<Map<String, dynamic>>>? _callSubscription;
  RealtimeChannel? _fallbackChannel;
  BuildContext? _context;
  String? _currentUserId;

  bool _isListening = false;
  CallModel? _activeCall;

  /// Initialize the call listener with the current context and user ID
  void initialize(BuildContext context, String userId) {
    if (!FeatureFlags.callsEnabled) {
      // Calls disabled: do not start listening
      _context = context;
      _currentUserId = userId;
      return;
    }
    _context = context;
    _currentUserId = userId;
    startListening();
  }

  /// Start listening for incoming calls
  void startListening() {
    if (!FeatureFlags.callsEnabled) return;
    if (_isListening || _currentUserId == null) return;

    _isListening = true;

    // Listen for new calls where the current user is the receiver
    try {
      _callSubscription = Supabase.instance.client
          .from('calls')
          .stream(primaryKey: ['id'])
          .eq('receiver_id', _currentUserId!)
          .listen(
            (data) {
              _handleCallUpdates(data);
            },
            onError: (error) {
              // Gracefully handle missing table or RLS errors
              debugPrint('Call listener error: $error');
              _isListening = false;
              // Fallback to realtime channel subscription for inserts only
              try {
                final uid = _currentUserId!;
                _fallbackChannel = Supabase.instance.client
                    .channel('calls:$uid')
                    .onPostgresChanges(
                      event: PostgresChangeEvent.insert,
                      schema: 'public',
                      table: 'calls',
                      filter: PostgresChangeFilter(
                        type: PostgresChangeFilterType.eq,
                        column: 'receiver_id',
                        value: uid,
                      ),
                      callback: (payload) {
                        final rec = payload.newRecord;
                        if (rec is Map<String, dynamic>) {
                          _handleCallUpdates([rec]);
                        } else if (rec is Map) {
                          _handleCallUpdates([Map<String, dynamic>.from(rec)]);
                        }
                      },
                    )
                    .subscribe();
                _isListening = true;
              } catch (e) {
                debugPrint('Call listener fallback subscribe failed: $e');
              }
            },
          );
    } catch (e) {
      // Prevent app crash if calls table is missing (PGRST205)
      debugPrint('Failed to start call listener: $e');
      _isListening = false;
      // Fallback attempt even if stream setup threw synchronously
      try {
        final uid = _currentUserId!;
        _fallbackChannel = Supabase.instance.client
            .channel('calls:$uid')
            .onPostgresChanges(
              event: PostgresChangeEvent.insert,
              schema: 'public',
              table: 'calls',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'receiver_id',
                value: uid,
              ),
              callback: (payload) {
                final rec = payload.newRecord;
                if (rec is Map<String, dynamic>) {
                  _handleCallUpdates([rec]);
                } else if (rec is Map) {
                  _handleCallUpdates([Map<String, dynamic>.from(rec)]);
                }
              },
            )
            .subscribe();
        _isListening = true;
      } catch (e2) {
        debugPrint('Call listener fallback subscribe failed: $e2');
      }
    }
  }

  /// Stop listening for calls
  void stopListening() {
    _isListening = false;
    _callSubscription?.cancel();
    _callSubscription = null;
    try {
      _fallbackChannel?.unsubscribe();
    } catch (_) {}
    _fallbackChannel = null;
  }

  /// Handle call updates from the database
  void _handleCallUpdates(List<Map<String, dynamic>> callsData) {
    if (_context == null || !_context!.mounted) return;

    for (final raw in callsData) {
      try {
        final Map<String, dynamic> callData = Map<String, dynamic>.from(raw);
        final call = CallModel.fromMap(callData);

        // Skip invalid records
        if (call.id.isEmpty) continue;

        // Only handle calls where current user is receiver
        if (call.receiverId != _currentUserId) continue;

        // Handle new incoming calls
        if (call.status == CallStatus.calling && _activeCall?.id != call.id) {
          _showIncomingCall(call);
        }

        // Update active call status
        if (_activeCall?.id == call.id) {
          _activeCall = call;

          // If call ended or declined, clear active call
          if (call.status == CallStatus.ended ||
              call.status == CallStatus.declined ||
              call.status == CallStatus.missed) {
            _activeCall = null;
          }
        }
      } catch (e) {
        debugPrint(('Error handling call update: $e').toString());
        // continue processing other updates
      }
    }
  }

  /// Show incoming call screen
  void _showIncomingCall(CallModel call) {
    if (!FeatureFlags.callsEnabled) return;
    if (_context == null || !_context!.mounted) return;

    _activeCall = call;

    // Mark the call as ringing when the incoming screen is shown so
    // the caller side receives accurate status updates via realtime.
    // Ignore any errors to avoid blocking the UI flow.
    try {
      Supabase.instance.client
          .from('calls')
          .update({'status': CallStatus.ringing.name})
          .eq('id', call.id);
    } catch (e) {
      debugPrint('CallListenerService: failed to mark call as ringing: $e');
    }

    try {
      final NavigatorState? navFromKey =
          PushNotificationService.navigatorKey.currentState;
      final NavigatorState nav = navFromKey ?? Navigator.of(_context!);
      nav
          .push(
            MaterialPageRoute(
              builder: (context) => CallingScreen(call: call, isIncoming: true),
              fullscreenDialog: true,
            ),
          )
          .then((_) {
            // Clear active call when screen is dismissed
            if (_activeCall?.id == call.id) {
              _activeCall = null;
            }
          });
    } catch (e) {
      debugPrint(('Failed to navigate to CallingScreen: $e').toString());
      // Navigation failed; clear active call to avoid stuck state
      if (_activeCall?.id == call.id) {
        _activeCall = null;
      }
    }
  }

  /// Update context (useful when navigating between screens)
  void updateContext(BuildContext context) {
    _context = context;
  }

  /// Get current active call
  CallModel? get activeCall => _activeCall;

  /// Check if currently in a call
  bool get isInCall => _activeCall != null;

  /// Dispose resources
  void dispose() {
    stopListening();
    _context = null;
    _currentUserId = null;
    _activeCall = null;
  }
}
