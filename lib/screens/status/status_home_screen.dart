import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/app_colors.dart';
import '../../models/status_model.dart';
import '../../services/status_service.dart';
import 'status_viewer_screen.dart';
import 'status_create_screen.dart';
import '../../services/localization_service.dart';
import '../../services/live_streaming_service.dart';
import '../live_stream_viewer_screen.dart';

class StatusHomeScreen extends StatefulWidget {
  const StatusHomeScreen({super.key});

  @override
  State<StatusHomeScreen> createState() => _StatusHomeScreenState();
}

class _StatusHomeScreenState extends State<StatusHomeScreen>
    with SingleTickerProviderStateMixin {
  final _client = Supabase.instance.client;
  final _service = StatusService.of();

  bool _loading = true;
  String _query = '';
  List<StatusModel> _recent = [];
  List<StatusModel> _viewed = [];
  List<StatusModel> _mine = [];
  RealtimeChannel? _statusSubscription;
  RealtimeChannel? _viewsSubscription;
  final LiveStreamingService _liveStreamingService = LiveStreamingService();
  Map<String, Map<String, dynamic>> _activeStreamsByUserId = {};
  RealtimeChannel? _liveStreamsSubscription;

  @override
  void initState() {
    super.initState();
    _loadAll();
    _subscribeToStatusChanges();
    _subscribeToViewsChanges();
    _refreshActiveStreams();
    _subscribeToLiveStreams();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    final user = _client.auth.currentUser;
    if (user == null) {
      setState(() {
        _recent = [];
        _viewed = [];
        _mine = [];
        _loading = false;
      });
      if (kDebugMode) {
        debugPrint(('[StatusHome] _loadAll: no authenticated user').toString());
      }
      return;
    }

    try {
      // Debug: print follows and visible status counts per followed user
      await _service.debugPrintFollowsAndStatusCounts(user.id);

      final recent = await _service.fetchActiveStatusesForFeed(user.id);

      // Viewed: join status_views -> statuses with profile. If embed fails, fallback to manual profile fetch.
      List<StatusModel> viewed;
      try {
        final viewedRes = await _client
            .from('status_views')
            .select('status_id, statuses(id,user_id,type,text_content,media_url,bg_color,created_at,expires_at,users!statuses_user_id_fkey(username,display_name,avatar_url))')
            .eq('viewer_id', user.id)
            .order('viewed_at', ascending: false);
        viewed = (viewedRes as List).map((e) {
          final s = e['statuses'] as Map<String, dynamic>?;
          if (s == null) return null;
          final u = s['users'] as Map<String, dynamic>?; // embedded via statuses(..., users(...))
          return StatusModel.fromMap({
            ...s,
            'username': u?['username'],
            'display_name': u?['display_name'],
            'avatar_url': u?['avatar_url'],
          });
        }).whereType<StatusModel>().toList();
      } catch (eViewed) {
        if (kDebugMode) {
          debugPrint(('[StatusHome] viewed embed join failed, falling back: $eViewed').toString());
        }
        // Fallback: fetch views with statuses only, then bulk fetch profiles
        final viewedRes = await _client
            .from('status_views')
            .select('status_id, statuses(id,user_id,type,text_content,media_url,bg_color,created_at,expires_at)')
            .eq('viewer_id', user.id)
            .order('viewed_at', ascending: false);
        final statusMaps = (viewedRes as List)
            .map((e) => e['statuses'] as Map<String, dynamic>?)
            .whereType<Map<String, dynamic>>()
            .toList();
        final userIds = statusMaps
            .map((m) => m['user_id']?.toString())
            .whereType<String>()
            .toSet()
            .toList();
        Map<String, Map<String, dynamic>> profilesById = {};
        // Primary: users
        if (userIds.isNotEmpty) {
          try {
            final pr1 = await _client
                .from('users')
                .select('id,username,display_name,avatar_url')
                .inFilter('id', userIds);
            for (final p in pr1) {
              final pm = p;
              profilesById[pm['id'].toString()] = pm;
            }
                    } catch (_) {}
          // Fallback: user_profiles (deprecated - skip)
          final missing1 = userIds.where((id) => !profilesById.containsKey(id)).toList();
          if (missing1.isNotEmpty) {
            try {
              // no-op to avoid PGRST205
            } catch (_) {}
          }
          // Fallback: profiles
          final missing2 = userIds.where((id) => !profilesById.containsKey(id)).toList();
          if (missing2.isNotEmpty) {
            try {
              final pr3 = await _client
                  .from('profiles')
                  .select('id,username,full_name,display_name,avatar_url')
                  .inFilter('id', missing2);
              for (final p in pr3) {
                final pm = p;
                profilesById[pm['id'].toString()] = pm;
              }
                        } catch (_) {}
          }
        }
        viewed = statusMaps.map((s) {
          final pid = s['user_id']?.toString();
          final prof = pid != null ? profilesById[pid] : null;
          final dn = (prof?['display_name'] as String?)?.trim();
          final fn = (prof?['full_name'] as String?)?.trim();
          final un = (prof?['username'] as String?)?.trim();
          final effectiveDisplay = (dn != null && dn.isNotEmpty) ? dn : (fn != null && fn.isNotEmpty) ? fn : un;
          return StatusModel.fromMap({
            ...s,
            'username': un,
            'display_name': effectiveDisplay,
            'avatar_url': prof?['avatar_url'],
          });
        }).toList();
      }

      final mine = await _service.fetchUserStatuses(user.id);

      if (kDebugMode) {
        debugPrint(('[StatusHome] _loadAll user: ${user.id}').toString());
        debugPrint(('[StatusHome] recent count: ${recent.length}').toString());
        debugPrint(('[StatusHome] viewed count: ${viewed.length}').toString());
        debugPrint(('[StatusHome] mine count: ${mine.length}').toString());
      }

      // Filter out expired statuses from viewed
      viewed = viewed.where((s) => !s.isExpired).toList();

      setState(() {
        _recent = recent;
        _viewed = viewed;
        _mine = mine;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: LocalizedText('Failed to load statuses: $e')),
        );
      }
      if (kDebugMode) {
        debugPrint(('[StatusHome] _loadAll error: $e').toString());
      }
    }
  }

  Map<String, List<StatusModel>> _groupByUser(List<StatusModel> statuses) {
    final m = <String, List<StatusModel>>{};
    for (final s in statuses) {
      m.putIfAbsent(s.userId, () => []).add(s);
    }
    return m;
  }

  List<_UserStory> _toStories(List<StatusModel> statuses) {
    final grouped = _groupByUser(statuses);
    final stories = <_UserStory>[];
    final viewedIds = _viewed.map((s) => s.id).toSet();
    for (final entry in grouped.entries) {
      final first = entry.value.first;
      final hasUnseen = entry.value.any((s) => !viewedIds.contains(s.id));
      final live = _activeStreamsByUserId[entry.key];
      stories.add(
        _UserStory(
          userId: entry.key,
          name: (first.displayName != null && first.displayName!.trim().isNotEmpty)
              ? first.displayName!
              : (() {
                    final u = first.username ?? 'User';
                    return u.startsWith('@') ? u.substring(1) : u;
                  })(),
          avatarUrl: first.userAvatar,
          statuses: entry.value,
          hasUnseen: hasUnseen,
          isLive: live != null,
          liveStreamId: live != null ? (live['id']?.toString()) : null,
        ),
      );
    }
    stories.sort((a, b) => b.latest.createdAt.compareTo(a.latest.createdAt));
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      return stories.where((s) => s.name.toLowerCase().contains(q)).toList();
    }
    return stories;
  }

  void _openCreate() async {
    final posted = await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const StatusCreateScreen()),
    );
    if (posted == true) {
      _loadAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text(
            LocalizationService.t('statuses'),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          actions: [
            IconButton(
              tooltip: LocalizationService.t('create_status'),
              icon: const Icon(Icons.add_circle_outline),
              onPressed: _openCreate,
            ),
            IconButton(
              tooltip: LocalizationService.t('refresh'),
              icon: const Icon(Icons.refresh),
              onPressed: _loadAll,
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: LocalizationService.t('recent')),
              Tab(text: LocalizationService.t('viewed')),
              Tab(text: LocalizationService.t('my')),
            ],
          ),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: _SearchBar(
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : TabBarView(
                      children: [
                        _StoriesList(stories: _toStories(_recent)),
                        _StoriesList(stories: _toStories(_viewed)),
                        _MyStatusesList(statuses: _mine, onRefresh: _loadAll),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _subscribeToStatusChanges() {
    _statusSubscription = _client
        .channel('public:statuses')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'statuses',
          callback: (payload) {
            _loadAll();
          },
        )
        .subscribe();
  }

  void _subscribeToViewsChanges() {
    _viewsSubscription = _client
        .channel('public:status_views')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'status_views',
          callback: (payload) {
            _loadAll();
          },
        )
        .subscribe();
  }

  Future<void> _refreshActiveStreams() async {
    try {
      final streams = await _liveStreamingService.getActiveLiveStreams();
      final Map<String, Map<String, dynamic>> byUser = {};
      for (final s in streams) {
        final uid = s['user_id']?.toString();
        if (uid == null || uid.isEmpty) continue;
        // Keep the most recently updated stream per user
        DateTime parseTime(Map<String, dynamic> m) {
          final u = (m['updated_at'] ?? m['started_at'])?.toString();
          final dt = DateTime.tryParse(u ?? '');
          return dt ?? DateTime.fromMillisecondsSinceEpoch(0);
        }
        final existing = byUser[uid];
        if (existing == null) {
          byUser[uid] = s;
        } else {
          if (parseTime(s).isAfter(parseTime(existing))) {
            byUser[uid] = s;
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _activeStreamsByUserId = byUser;
      });
      if (kDebugMode) {
        debugPrint('[StatusHome] Active live streams users: ${_activeStreamsByUserId.keys.length}');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[StatusHome] _refreshActiveStreams error: $e');
      }
    }
  }

  void _subscribeToLiveStreams() {
    _liveStreamsSubscription = _client
        .channel('public:live_streams')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'live_streams',
          callback: (payload) {
            // Whenever a live stream row changes, refresh our cache
            _refreshActiveStreams();
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    _statusSubscription?.unsubscribe();
    _viewsSubscription?.unsubscribe();
    _liveStreamsSubscription?.unsubscribe();
    super.dispose();
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.onChanged});
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: LocalizationService.t('search_statuses_hint'),
        filled: true,
        fillColor: AppColors.surface,
        prefixIcon: const Icon(Icons.search),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.border),
        ),
      ),
    );
  }
}

class _StoriesList extends StatelessWidget {
  const _StoriesList({required this.stories});
  final List<_UserStory> stories;

  @override
  Widget build(BuildContext context) {
    if (stories.isEmpty) {
      return Center(child: Text(LocalizationService.t('no_statuses_yet')));
    }
    return RefreshIndicator(
      onRefresh: () async {
        // Triggered by parent refresh button; do nothing here.
      },
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 12),
        itemCount: stories.length,
        itemBuilder: (context, i) {
          final s = stories[i];
          return ListTile(
            leading: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _GradientRingAvatar(
                  avatarUrl: s.avatarUrl,
                  hasUnseen: s.hasUnseen,
                  latestStatus: s.isLive ? null : s.latest,
                  isLive: s.isLive,
                ),
                if (s.isLive) const SizedBox(height: 4),
                if (s.isLive)
                  const Text(
                    'LIVE',
                    style: TextStyle(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
            title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(
              '${s.statuses.length} ${LocalizationService.t('statuses')} • ${_relativeTime(s.latest.createdAt)}',
            ),
            trailing: s.isLive && (s.liveStreamId != null && s.liveStreamId!.isNotEmpty)
                ? ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () {
                      final streamId = s.liveStreamId!;
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => LiveStreamViewerScreen(streamId: streamId),
                        ),
                      );
                    },
                  child: const LocalizedText('join'),
                  )
                : null,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => StatusViewerScreen(
                    statuses: s.statuses.reversed.toList(),
                    posterName: s.name,
                    posterAvatarUrl: s.avatarUrl,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _MyStatusesList extends StatelessWidget {
  const _MyStatusesList({required this.statuses, required this.onRefresh});
  final List<StatusModel> statuses;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 12),
        itemCount: statuses.length + 1,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, i) {
          if (i == 0) {
            return ListTile(
              leading: const Icon(Icons.person),
              title: Text(LocalizationService.t('my')),
              subtitle: Text('${statuses.length} ${LocalizationService.t('statuses')}'),
              trailing: TextButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const StatusCreateScreen()),
                  );
                },
                icon: const Icon(Icons.add_circle_outline),
                label: Text(LocalizationService.t('add')),
              ),
            );
          }
          final s = statuses[i - 1];
          return ListTile(
            leading: _GradientRingAvatar(avatarUrl: s.userAvatar, hasUnseen: false, latestStatus: s),
            title: Text(_typeLabel(s.type)),
            subtitle: Text(_relativeTime(s.createdAt)),
            onTap: () {
              () async {
                // Resolve poster profile just-in-time to avoid RLS join issues
                String resolvedName = (() {
                  final dn = s.displayName?.trim();
                  if (dn != null && dn.isNotEmpty) return dn;
                  final un = s.username?.trim();
                  if (un != null && un.isNotEmpty) {
                    return un.startsWith('@') ? un.substring(1) : un;
                  }
                  return 'User';
                })();
                String? resolvedAvatar = s.userAvatar;
                try {
                  final client = Supabase.instance.client;
                  Map<String, dynamic>? prof;
                  // Primary: users
                  try {
                    prof = await client
                        .from('users')
                        .select('display_name,username,avatar_url')
                        .eq('id', s.userId)
                        .maybeSingle();
                  } catch (_) {}
                  if (prof == null) {
                    try {
                      // deprecated user_profiles table; skip to avoid PGRST205
                      prof = null;
                    } catch (_) {}
                  }
                  if (prof == null) {
                    try {
                      prof = await client
                          .from('profiles')
                          .select('display_name,full_name,username,avatar_url')
                          .eq('id', s.userId)
                          .maybeSingle();
                    } catch (_) {}
                  }
                  if (prof != null) {
                    final dn = (prof['display_name'] as String?)?.trim();
                    final fn = (prof['full_name'] as String?)?.trim();
                    final un = (prof['username'] as String?)?.trim();
                    resolvedName = (dn != null && dn.isNotEmpty)
                        ? dn
                        : (fn != null && fn.isNotEmpty
                            ? fn
                            : (un != null && un.isNotEmpty
                                ? (un.startsWith('@') ? un.substring(1) : un)
                                : resolvedName));
                    final av = (prof['avatar_url'] as String?);
                    if (av != null && av.isNotEmpty) {
                      resolvedAvatar = av;
                    }
                  }
                } catch (_) {
                  // ignore and use existing fallbacks
                }

                if (!context.mounted) return;
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => StatusViewerScreen(
                      statuses: [s],
                      posterName: resolvedName,
                      posterAvatarUrl: resolvedAvatar,
                    ),
                  ),
                );
              }();
            },
          );
        },
      ),
    );
  }
}

class _GradientRingAvatar extends StatelessWidget {
  const _GradientRingAvatar({this.avatarUrl, this.hasUnseen = false, this.latestStatus, this.isLive = false});
  final String? avatarUrl;
  final bool hasUnseen;
  final StatusModel? latestStatus;
  final bool isLive;

  @override
  Widget build(BuildContext context) {
    final Gradient ringGradient = isLive
        ? const LinearGradient(
            colors: [
              Color(0xFFFF3B30), // red
              Color(0xFFB00020), // dark red
            ],
          )
        : hasUnseen
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

    Widget _buildPreview(double size) {
      if (isLive) {
        // Always show profile avatar when live
        return CircleAvatar(
          backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl!) : null,
          child: avatarUrl == null ? const Icon(Icons.person, color: Colors.white) : null,
        );
      }
      final s = latestStatus;
      if (s != null) {
        switch (s.type) {
          case StatusType.image:
            if (s.mediaUrl != null && s.mediaUrl!.isNotEmpty) {
              return CircleAvatar(
                backgroundImage: NetworkImage(s.mediaUrl!),
              );
            }
            break;
          case StatusType.text:
            return ClipOval(
              child: Container(
                width: size,
                height: size,
                color: s.backgroundColor ?? Colors.black,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Text(
                  (s.text ?? '').trim(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 10, color: Colors.white, height: 1.1),
                ),
              ),
            );
          case StatusType.video:
            return ClipOval(
              child: Container(
                width: size,
                height: size,
                color: Colors.black,
                alignment: Alignment.center,
                child: const Icon(Icons.play_circle_fill, color: Colors.white70, size: 22),
              ),
            );
          case StatusType.audio:
            return ClipOval(
              child: Container(
                width: size,
                height: size,
                color: Colors.black,
                alignment: Alignment.center,
                child: const Icon(Icons.graphic_eq, color: Colors.white70, size: 22),
              ),
            );
        }
      }
      // Fallback to profile avatar
      return CircleAvatar(
        backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl!) : null,
        child: avatarUrl == null ? const Icon(Icons.person, color: Colors.white) : null,
      );
    }

    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: ringGradient,
            boxShadow: (isLive || hasUnseen)
                ? const [
                    BoxShadow(
                      color: Color(0x33FF3B30),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
        ),
        Container(
          width: 44,
          height: 44,
          decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.black),
          child: _buildPreview(44),
        ),
      ],
    );
  }
}

class _UserStory {
  _UserStory({
    required this.userId,
    required this.name,
    required this.statuses,
    this.avatarUrl,
    this.hasUnseen = false,
    this.isLive = false,
    this.liveStreamId,
  });
  final String userId;
  final String name;
  final String? avatarUrl;
  final List<StatusModel> statuses;
  final bool hasUnseen;
  final bool isLive;
  final String? liveStreamId;

  StatusModel get latest => statuses.first;
}

String _relativeTime(DateTime dt) {
  final diff = DateTime.now().toUtc().difference(dt);
  if (diff.inMinutes < 1) return LocalizationService.t('just_now');
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ${LocalizationService.t('ago')}';
  if (diff.inHours < 24) return '${diff.inHours}h ${LocalizationService.t('ago')}';
  return '${diff.inDays}d ${LocalizationService.t('ago')}';
}

String _typeLabel(StatusType type) {
  switch (type) {
    case StatusType.text:
      return LocalizationService.t('text');
    case StatusType.image:
      return LocalizationService.t('photo');
    case StatusType.video:
      return LocalizationService.t('video');
    case StatusType.audio:
      return LocalizationService.t('audio');
  }
}
