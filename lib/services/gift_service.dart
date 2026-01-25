import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import 'auth_service.dart';
import '../models/gift_model.dart';

class GiftService {
  static final GiftService _instance = GiftService._internal();
  factory GiftService() => _instance;
  GiftService._internal();

  final SupabaseClient _client = SupabaseConfig.client;
  final AuthService _authService = AuthService();

  // Fetch catalog (with simple static fallback if table empty or missing)
  Future<List<GiftModel>> getCatalog() async {
    try {
      final rows = await _client
          .from('gifts_catalog')
          .select('*')
          .eq('is_active', true)
          .order('cost_coins', ascending: true);
      final list = (rows as List).map((j) => GiftModel.fromJson(Map<String, dynamic>.from(j))).toList();
      if (list.isNotEmpty) return list;
    } catch (_) {}

    // Fallback catalog
    return [
      GiftModel(id: 'fallback-gift', name: 'Gift Box', iconKey: 'gift', costCoins: 20, isActive: true),
      GiftModel(id: 'fallback-star', name: 'Star', iconKey: 'star', costCoins: 10, isActive: true),
      GiftModel(id: 'fallback-fire', name: 'Fire', iconKey: 'fire', costCoins: 15, isActive: true),
      GiftModel(id: 'fallback-heart', name: 'Heart', iconKey: 'heart', costCoins: 12, isActive: true),
    ];
  }

  // Ensure wallet exists (initialize with some starter coins for MVP)
  Future<int> ensureWallet() async {
      final user = _authService.currentUser;
      if (user == null) {
        throw Exception('User must be authenticated');
      }
      try {
        final existing = await _client
            .from('user_wallets')
            .select('coins')
            .eq('user_id', user.id)
            .maybeSingle();
        if (existing != null) {
          return (existing['coins'] as int?) ?? 0;
        }
      } catch (_) {}

      // Insert a new wallet with starter coins (e.g., 200 for testing)
      try {
        await _client.from('user_wallets').insert({
          'user_id': user.id,
          'coins': 200,
        });
        return 200;
      } catch (e) {
        // If RLS blocks, surface error
        throw Exception('Failed to initialize wallet: ${e.toString()}');
      }
  }

  Future<int> getBalance() async {
    final user = _authService.currentUser;
    if (user == null) {
      throw Exception('User must be authenticated');
    }
    final row = await _client
        .from('user_wallets')
        .select('coins')
        .eq('user_id', user.id)
        .maybeSingle();
    return (row?['coins'] as int?) ?? 0;
  }

  Future<void> creditCoins(int amount, {String? reason}) async {
    final user = _authService.currentUser;
    if (user == null) {
      throw Exception('User must be authenticated');
    }
    final current = await getBalance();
    final updated = current + amount;
    await _client.from('user_wallets').upsert({
      'user_id': user.id,
      'coins': updated,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  // Send a gift: deduct coins, insert transaction, broadcast realtime event
  Future<Map<String, dynamic>> sendGift({
    required String streamId,
    required String giftId,
  }) async {
    final user = _authService.currentUser;
    if (user == null) {
      throw Exception('User must be authenticated to send gifts');
    }

    // Load gift details
    late GiftModel gift;
    try {
      final row = await _client
          .from('gifts_catalog')
          .select('*')
          .eq('id', giftId)
          .single();
      gift = GiftModel.fromJson(Map<String, dynamic>.from(row));
    } catch (_) {
      // fallback lookup if using seeded IDs or local
      final catalog = await getCatalog();
      final found = catalog.firstWhere(
        (g) => g.id == giftId,
        orElse: () => throw Exception('Gift not found'),
      );
      gift = found;
    }

    // Ensure wallet and check balance
    final balance = await ensureWallet();
    if (balance < gift.costCoins) {
      throw Exception('Insufficient coins');
    }

    // Deduct coins (simple client-side upsert; for production use RPC/trigger)
    final newBalance = balance - gift.costCoins;
    await _client.from('user_wallets').upsert({
      'user_id': user.id,
      'coins': newBalance,
      'updated_at': DateTime.now().toIso8601String(),
    });

    // Insert transaction
    await _client.from('gift_transactions').insert({
      'stream_id': streamId,
      'sender_user_id': user.id,
      'gift_id': gift.id,
      'gift_name': gift.name,
      'coins_spent': gift.costCoins,
    });

    // Broadcast realtime event to stream channel
    final payload = {
      'type': 'gift',
      'stream_id': streamId,
      'user_id': user.id,
      'username': user.userMetadata?['username'] ?? 'Anonymous',
      'avatar_url': user.userMetadata?['avatar_url'],
      'gift_id': gift.id,
      'gift_name': gift.name,
      'icon_key': gift.iconKey,
      'coins_spent': gift.costCoins,
      'timestamp': DateTime.now().toIso8601String(),
    };

    // Use a transient channel for broadcast to avoid tight coupling
    final channel = _client.channel('stream_$streamId');
    await channel.subscribe();
    await channel.sendBroadcastMessage(event: 'stream_event', payload: payload);
    await _client.removeChannel(channel);

    return {
      'success': true,
      'new_balance': newBalance,
      'gift': {
        'id': gift.id,
        'name': gift.name,
        'icon_key': gift.iconKey,
        'cost_coins': gift.costCoins,
      }
    };
  }
}

