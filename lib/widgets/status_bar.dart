import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/status_service.dart';
import '../models/status_model.dart';
import '../screens/status/status_viewer_screen.dart';
import '../screens/status/status_create_screen.dart';

class StatusBar extends StatefulWidget implements PreferredSizeWidget {
  const StatusBar({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(72);

  @override
  State<StatusBar> createState() => _StatusBarState();
}

class _StatusBarState extends State<StatusBar> {
  final _service = StatusService.of();
  List<StatusModel> _statuses = [];
  bool _loading = true;
  Set<String> _viewedIds = <String>{};
  String? _myAvatar;
  RealtimeChannel? _statusSubscription;
  RealtimeChannel? _viewsSubscription;

  @override
  void initState() {
    super.initState();
    _load();
    _subscribeToStatusChanges();
    _subscribeToViewsChanges();
  }

  Future<void> _load() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) {
      setState(() {
        _loading = false;
        _statuses = [];
        _viewedIds = <String>{};
        _myAvatar = null;
      });
      return;
    }
    try {
      // fetch feed statuses
      final res = await _service
          .fetchActiveStatusesForFeed(user.id)
          .timeout(const Duration(seconds: 4), onTimeout: () => <StatusModel>[]) // fast timeout
          .catchError((_) => <StatusModel>[]);

      // fetch viewed status ids for current user
      final viewsRes = await client
          .from('status_views')
          .select('status_id')
          .eq('viewer_id', user.id)
          .timeout(const Duration(seconds: 4), onTimeout: () => <Map<String, dynamic>>[])
          .catchError((_) => <Map<String, dynamic>>[]);
      final viewedIds = <String>{};
      for (final v in (viewsRes as List)) {
        final id = v['status_id']?.toString();
        if (id != null) viewedIds.add(id);
      }

      // fetch current user's avatar
      Map<String, dynamic>? prof;
      try {
        prof = await client
            .from('users')
            .select('id,username,display_name,avatar_url')
            .eq('id', user.id)
            .maybeSingle();
      } catch (_) {}
      if (prof == null) {
        try {
          // deprecated user_profiles table; skip
          prof = null;
        } catch (_) {}
      }
      if (prof == null) {
        try {
          prof = await client
              .from('profiles')
              .select('id,username,full_name,display_name,avatar_url')
              .eq('id', user.id)
              .maybeSingle();
        } catch (_) {}
      }
      final dn = (prof?['display_name'] as String?)?.trim();
      final fn = (prof?['full_name'] as String?)?.trim();
      final un = (prof?['username'] as String?)?.trim();
      // ignore: unused_local_variable
      final effectiveDisplay = (dn != null && dn.isNotEmpty) ? dn : (fn != null && fn.isNotEmpty) ? fn : un;
      final myAvatar = (prof != null && prof['avatar_url'] is String) ? prof['avatar_url'] as String : null;

      if (mounted) {
        setState(() {
          _statuses = res;
          _viewedIds = viewedIds;
          _myAvatar = myAvatar;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  void _subscribeToStatusChanges() {
    final client = Supabase.instance.client;
    _statusSubscription = client
        .channel('public:statuses')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'statuses',
          callback: (payload) {
            // Reload on any insert/update/delete that the current user is authorized to see
            _load();
          },
        )
        .subscribe();
  }

  void _subscribeToViewsChanges() {
    final client = Supabase.instance.client;
    _viewsSubscription = client
        .channel('public:status_views')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'status_views',
          callback: (payload) {
            // Reload when views change to update seen/unseen indicators
            _load();
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    _statusSubscription?.unsubscribe();
    _viewsSubscription?.unsubscribe();
    super.dispose();
  }

  void _openCreate() async {
    final posted = await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const StatusCreateScreen()),
    );
    if (posted == true) {
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final grouped = <String, List<StatusModel>>{};
    for (final s in _statuses) {
      grouped.putIfAbsent(s.userId, () => []).add(s);
    }
    final userIds = grouped.keys.toList();

    // Compute current user's latest photo (if any) to use for the "Add" bubble
    String? myLatestPhotoUrl;
    if (user != null) {
      final mine = grouped[user.id];
      if (mine != null) {
        for (final s in mine) {
          if (s.type == StatusType.image && (s.mediaUrl?.isNotEmpty ?? false)) {
            myLatestPhotoUrl = s.mediaUrl;
            break;
          } else if (s.type == StatusType.video && (s.thumbnailUrl?.isNotEmpty ?? false)) {
            myLatestPhotoUrl = s.thumbnailUrl;
            break;
          }
        }
      }
    }

    return Container(
      color: Colors.transparent,
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Status',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                TextButton.icon(
                  onPressed: _openCreate,
                  icon: const Icon(Icons.add_circle_outline),
                  label: const Text('Add'),
                )
              ],
            ),
          ),
          SizedBox(
            height: 64,
            child: _loading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: (user != null ? 1 : 0) + userIds.length,
                    itemBuilder: (_, i) {
                      if (user != null && i == 0) {
                        // Use latest posted photo if available, otherwise fallback to profile avatar
                        return _AddStatusItem(onTap: _openCreate, avatarUrl: myLatestPhotoUrl ?? _myAvatar);
                      }
                      final idx = user != null ? i - 1 : i;
                      final uid = userIds[idx];
                      final statuses = grouped[uid]!;
                      final first = statuses.first;
                      final name = (first.displayName != null && first.displayName!.trim().isNotEmpty)
                          ? first.displayName!
                          : (() {
                              final u = first.username?.trim();
                              if (u != null && u.isNotEmpty) {
                                return u.startsWith('@') ? u.substring(1) : u;
                              }
                              return 'User';
                            })();
                      final fallbackAvatar = first.userAvatar;

                      // Find the latest posted photo for this user
                      String? latestPhotoUrl;
                      for (final s in statuses) {
                        if (s.type == StatusType.image && (s.mediaUrl?.isNotEmpty ?? false)) {
                          latestPhotoUrl = s.mediaUrl;
                          break;
                        } else if (s.type == StatusType.video && (s.thumbnailUrl?.isNotEmpty ?? false)) {
                          latestPhotoUrl = s.thumbnailUrl;
                          break;
                        }
                      }

                      final effectiveAvatar = latestPhotoUrl ?? fallbackAvatar;
                      final hasUnseen = statuses.any((s) => !_viewedIds.contains(s.id));
                      return _StatusItem(
                        name: name,
                        avatarUrl: effectiveAvatar,
                        hasUnseen: hasUnseen,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => StatusViewerScreen(
                                statuses: statuses,
                                posterName: (name.startsWith('@') ? name.substring(1) : name),
                                posterAvatarUrl: fallbackAvatar,
                              ),
                             ),
                           );
                         },
                       );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _AddStatusItem extends StatelessWidget {
  const _AddStatusItem({required this.onTap, this.avatarUrl});
  final VoidCallback onTap;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 12.0),
      child: Column(
        children: [
          GestureDetector(
            onTap: onTap,
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                // Gradient ring avatar (always accent for your own)
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: const [
                        Color(0xFF8AB4F8), // bluish
                        Color(0xFFFFFFFF), // whitish
                        Color(0xFFFFD700), // goldish
                      ],
                      stops: const [0.0, 0.5, 1.0],
                    ),
                    boxShadow: const [
                      BoxShadow(color: Color(0x668AB4F8), blurRadius: 8, spreadRadius: 1),
                    ],
                  ),
                ),
                Container(
                  width: 46,
                  height: 46,
                  margin: const EdgeInsets.all(1),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black,
                  ),
                  child: CircleAvatar(
                    radius: 22,
                    backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl!) : null,
                    child: avatarUrl == null ? const Icon(Icons.person, color: Colors.white) : null,
                  ),
                ),
                CircleAvatar(
                  radius: 9,
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  child: Icon(Icons.add, color: Theme.of(context).colorScheme.primary, size: 14),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text('Your status', style: Theme.of(context).textTheme.bodySmall)
        ],
      ),
    );
  }
}

class _StatusItem extends StatelessWidget {
  const _StatusItem({required this.name, required this.avatarUrl, required this.hasUnseen, required this.onTap});
  final String name;
  final String? avatarUrl;
  final bool hasUnseen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Gradient ringGradient = hasUnseen
        ? const LinearGradient(
            colors: [
              Color(0xFF8AB4F8), // bluish
              Color(0xFFFFFFFF), // whitish
              Color(0xFFFFD700), // goldish
            ],
            stops: [0.0, 0.5, 1.0],
          )
        : LinearGradient(
            colors: [
              Colors.grey.shade500,
              Colors.grey.shade800,
            ],
          );

    return Padding(
      padding: const EdgeInsets.only(right: 12.0),
      child: Column(
        children: [
          GestureDetector(
            onTap: onTap,
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: ringGradient,
                boxShadow: hasUnseen
                    ? const [BoxShadow(color: Color(0x668AB4F8), blurRadius: 8, spreadRadius: 1)]
                    : null,
              ),
              child: Container(
                margin: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black,
                ),
                child: CircleAvatar(
                  radius: 22,
                  backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl!) : null,
                  child: avatarUrl == null ? const Icon(Icons.person, color: Colors.white) : null,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: 56,
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}