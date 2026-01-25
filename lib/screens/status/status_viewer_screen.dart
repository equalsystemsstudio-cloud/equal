import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/status_model.dart';
import '../../services/status_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart'
    show VideoPlayerController, VideoPlayer; // add video support
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import '../../services/localization_service.dart';
import '../../services/history_service.dart';

class StatusViewerScreen extends StatefulWidget {
  const StatusViewerScreen({
    super.key,
    required this.statuses,
    this.posterName,
    this.posterAvatarUrl,
    this.initialIndex,
  });
  final List<StatusModel> statuses; // statuses for a single user
  final String? posterName;
  final String? posterAvatarUrl;
  final int? initialIndex;

  @override
  State<StatusViewerScreen> createState() => _StatusViewerScreenState();
}

class _StatusViewerScreenState extends State<StatusViewerScreen> {
  late final PageController _pageController;
  Timer? _timer;
  Timer? _historyTimer;
  String? _pendingHistoryStatusId;
  int _index = 0;
  final Map<int, VideoPlayerController> _videoControllers =
      {}; // per-page controllers
  // Audio controllers per page
  final Map<int, AudioPlayer> _audioPlayers = {};
  final Map<int, Duration> _audioDurations = {};
  final Map<int, Duration> _audioPositions = {};
  final Map<int, bool> _audioPlaying = {};
  String? _resolvedPosterName;
  String? _resolvedPosterAvatar;
  // Added for view counter & viewer list
  bool _isOwner = false;
  final Map<String, int> _viewCounts = {};
  int _currentViewCount = 0;

  @override
  void initState() {
    super.initState();
    // Initialize index from optional initialIndex
    final idx = widget.initialIndex ?? 0;
    _index = idx < 0
        ? 0
        : (widget.statuses.isEmpty
              ? 0
              : (idx >= widget.statuses.length
                    ? widget.statuses.length - 1
                    : idx));
    _pageController = PageController(initialPage: _index);
    _markViewed();
    _startTimerForCurrent();
    _resolvePosterProfile();
    // Determine if current user is the owner of these statuses (single poster in this screen)
    final current = Supabase.instance.client.auth.currentUser;
    if (current != null && widget.statuses.isNotEmpty) {
      _isOwner = widget.statuses.first.userId == current.id;
    }
    if (_isOwner) {
      _loadViewCountForCurrent();
    }
  }

  Future<void> _resolvePosterProfile() async {
    try {
      if (widget.statuses.isEmpty) return;
      final uid = widget.statuses.first.userId;
      if (uid.isEmpty) return;
      final client = Supabase.instance.client;
      Map<String, dynamic>? prof;
      // Primary: users
      try {
        prof = await client
            .from('users')
            .select('display_name,username,avatar_url')
            .eq('id', uid)
            .maybeSingle();
      } catch (_) {}
      // Fallback: user_profiles (deprecated - skip)
      if (prof == null) {
        try {
          // no-op to avoid PGRST205
          prof = null;
        } catch (_) {}
      }
      // Fallback: profiles
      if (prof == null) {
        try {
          prof = await client
              .from('profiles')
              .select('display_name,full_name,username,avatar_url')
              .eq('id', uid)
              .maybeSingle();
        } catch (_) {}
      }
      if (!mounted) return;
      if (prof != null) {
        final dn = (prof['display_name'] as String?)?.trim();
        final fn = (prof['full_name'] as String?)?.trim();
        final un = (prof['username'] as String?)?.trim();
        final name = (dn != null && dn.isNotEmpty)
            ? dn
            : (fn != null && fn.isNotEmpty)
            ? fn
            : (un != null && un.isNotEmpty
                  ? (un.startsWith('@') ? un.substring(1) : un)
                  : null);
        final av = (prof['avatar_url'] as String?);
        setState(() {
          _resolvedPosterName = name;
          _resolvedPosterAvatar = (av != null && av.isNotEmpty) ? av : null;
        });
      }
    } catch (_) {
      // ignore resolution errors
    }
  }

  void _startTimerForCurrent() {
    _timer?.cancel();
    final s = widget.statuses[_index];
    if (s.type == StatusType.video &&
        s.mediaUrl != null &&
        s.mediaUrl!.isNotEmpty) {
      _initVideo(_index);
    } else if (s.type == StatusType.audio &&
        s.mediaUrl != null &&
        s.mediaUrl!.isNotEmpty) {
      _initAudio(_index);
      // Do not auto-advance for audio; user controls playback
    } else {
      _timer = Timer.periodic(const Duration(seconds: 4), (_) => _advance());
    }
  }

  Future<void> _initVideo(int i) async {
    _timer?.cancel();
    final s = widget.statuses[i];
    final url = s.mediaUrl;
    if (url == null || url.isEmpty) return;

    // pause all other controllers
    for (final entry in _videoControllers.entries) {
      if (entry.key != i) {
        entry.value.pause();
      }
    }

    var controller = _videoControllers[i];
    if (controller == null) {
      try {
        controller = VideoPlayerController.networkUrl(Uri.parse(url));
        _videoControllers[i] = controller;
        await controller.initialize();
        controller.setLooping(true);
        if (kIsWeb) {
          // Mute to satisfy autoplay policies on web
          await controller.setVolume(0.0);
        }
        await controller.play();
        controller.addListener(() {
          final v = controller!;
          final value = v.value;
          if (value.hasError) {
            // On error, just auto-advance to avoid blank state
            _advance();
            return;
          }
          if (value.isInitialized) {
            // If video finished, advance to next automatically
            if (!value.isPlaying && value.position >= value.duration) {
              _advance();
            }
          }
        });
        if (mounted) setState(() {});
      } catch (_) {
        // On error, just auto-advance to avoid blank state
        _advance();
      }
    } else {
      // already exists
      if (!controller.value.isInitialized) {
        try {
          await controller.initialize();
          controller.setLooping(true);
          if (kIsWeb) {
            await controller.setVolume(0.0);
          }
        } catch (_) {}
      }
      controller.play();
      if (mounted) setState(() {});
    }
  }

  Future<void> _initAudio(int i) async {
    final s = widget.statuses[i];
    final url = s.mediaUrl;
    if (url == null || url.isEmpty) return;

    // Pause all other audio players
    for (final entry in _audioPlayers.entries) {
      if (entry.key != i) {
        try {
          await entry.value.pause();
        } catch (_) {}
        _audioPlaying[entry.key] = false;
      }
    }

    var player = _audioPlayers[i];
    if (player == null) {
      try {
        player = AudioPlayer();
        _audioPlayers[i] = player;
        // Set up listeners
        player.onDurationChanged.listen((d) {
          setState(() => _audioDurations[i] = d);
        });
        player.onPositionChanged.listen((p) {
          setState(() => _audioPositions[i] = p);
        });
        player.onPlayerStateChanged.listen((state) {
          setState(() => _audioPlaying[i] = state == PlayerState.playing);
        });
        await player.setSource(UrlSource(url));
        // Apply audio effects (playback rate and volume) from status.effects
        final effects = s.effects;
        double rate = 1.0;
        double volume = 1.0;
        if (effects != null) {
          final sp = effects['speed'];
          final vol = effects['volume'];
          if (sp is num) rate = sp.toDouble();
          if (vol is num) volume = vol.toDouble();
        }
        try {
          await player.setPlaybackRate(rate);
          await player.setVolume(volume.clamp(0.0, 1.0));
        } catch (_) {}
        setState(() {
          _audioDurations[i] = _audioDurations[i] ?? Duration.zero;
          _audioPositions[i] = _audioPositions[i] ?? Duration.zero;
          _audioPlaying[i] = false;
        });
      } catch (_) {
        // Ignore audio init errors
      }
    }
  }

  void _advance() {
    if (_index < widget.statuses.length - 1) {
      // Pause current audio if any
      final ap = _audioPlayers[_index];
      if (ap != null) {
        try {
          ap.pause();
        } catch (_) {}
        _audioPlaying[_index] = false;
      }
      _index++;
      _pageController.animateToPage(
        _index,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
      _markViewed();
      _startTimerForCurrent();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  void _markViewed() {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    if (widget.statuses.isEmpty) return;
    final status = widget.statuses[_index];
    // Do not mark a view when the owner views their own status
    if (status.userId == user.id) return;
    StatusService.of().markViewed(statusId: status.id, viewerId: user.id);
    _historyTimer?.cancel();
    _pendingHistoryStatusId = status.id;
    _historyTimer = Timer(const Duration(seconds: 7), () {
      if (!mounted) return;
      if (widget.statuses.isEmpty) return;
      if (_index < 0 || _index >= widget.statuses.length) return;
      final current = widget.statuses[_index];
      if (_pendingHistoryStatusId != current.id) return;
      try {
        HistoryService.addStatusView(current);
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _historyTimer?.cancel();
    for (final c in _videoControllers.values) {
      c.dispose();
    }
    for (final p in _audioPlayers.values) {
      try {
        p.dispose();
      } catch (_) {}
    }
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final statuses = widget.statuses;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Stack(
          children: [
            PageView.builder(
              controller: _pageController,
              itemCount: statuses.length,
              onPageChanged: (i) {
                setState(() => _index = i);
                // Pause other audio players
                for (final entry in _audioPlayers.entries) {
                  if (entry.key != i) {
                    try {
                      entry.value.pause();
                    } catch (_) {}
                    _audioPlaying[entry.key] = false;
                  }
                }
                _markViewed();
                if (_isOwner) {
                  // Update cached count synchronously, then refresh from server
                  final s = statuses[i];
                  setState(() {
                    _currentViewCount = _viewCounts[s.id] ?? 0;
                  });
                  _loadViewCountForIndex(i);
                }
                _startTimerForCurrent();
              },
              itemBuilder: (_, i) {
                final s = statuses[i];
                switch (s.type) {
                  case StatusType.text:
                    return Container(
                      color: s.backgroundColor ?? Colors.black,
                      alignment: Alignment.center,
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Text(
                          s.text ?? '',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    );
                  case StatusType.image:
                    return SizedBox.expand(
                      child: Stack(
                        children: [
                          // Image content
                          Positioned.fill(
                            child: Container(
                              color: Colors.black,
                              alignment: Alignment.center,
                              child: s.mediaUrl != null
                                  ? CachedNetworkImage(
                                      imageUrl: s.mediaUrl!,
                                      fit: BoxFit.contain,
                                      filterQuality: FilterQuality.high,
                                      progressIndicatorBuilder:
                                          (context, url, downloadProgress) {
                                            final progress =
                                                downloadProgress.progress;
                                            return Center(
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  const CircularProgressIndicator(
                                                    color: Colors.white,
                                                  ),
                                                  if (progress != null)
                                                    Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                            top: 8.0,
                                                          ),
                                                      child: Text(
                                                        '${(progress * 100).toStringAsFixed(0)}%',
                                                        style: const TextStyle(
                                                          color: Colors.white70,
                                                        ),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            );
                                          },
                                      errorWidget: (context, url, error) {
                                        return const Center(
                                          child: Text(
                                            'Couldn\'t load image',
                                            style: TextStyle(
                                              color: Colors.white70,
                                            ),
                                          ),
                                        );
                                      },
                                    )
                                  : const SizedBox(),
                            ),
                          ),
                          // Caption overlay (if any)
                          if ((s.text ?? '').isNotEmpty)
                            Positioned(
                              left: 16,
                              right: 16,
                              bottom: 24,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.50),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  s.text!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  case StatusType.video:
                    final controller = _videoControllers[i];
                    if (controller != null && controller.value.isInitialized) {
                      return Center(
                        child: AspectRatio(
                          aspectRatio: controller.value.aspectRatio,
                          child: VideoPlayer(controller),
                        ),
                      );
                    }
                    return const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    );
                  case StatusType.audio:
                    final duration = _audioDurations[i] ?? Duration.zero;
                    final position = _audioPositions[i] ?? Duration.zero;
                    final isPlaying = _audioPlaying[i] ?? false;
                    final progress = (duration.inMilliseconds > 0)
                        ? position.inMilliseconds / duration.inMilliseconds
                        : 0.0;
                    return SizedBox.expand(
                      child: Stack(
                        children: [
                          // Background
                          Positioned.fill(
                            child: Container(
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Color(0xFF667eea),
                                    Color(0xFF764ba2),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          // Center content
                          Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 120,
                                  height: 120,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.white.withValues(alpha: 0.1),
                                    border: Border.all(
                                      color: Colors.white.withValues(
                                        alpha: 0.3,
                                      ),
                                      width: 2,
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.music_note,
                                    size: 60,
                                    color: Colors.white.withValues(alpha: 0.85),
                                  ),
                                ),
                                const SizedBox(height: 24),
                                // Progress slider
                                SizedBox(
                                  width: 260,
                                  child: Slider(
                                    value: progress.clamp(0.0, 1.0),
                                    onChanged: (value) {
                                      final d =
                                          _audioDurations[i] ?? Duration.zero;
                                      final target = Duration(
                                        milliseconds: (value * d.inMilliseconds)
                                            .round(),
                                      );
                                      final player = _audioPlayers[i];
                                      if (player != null) {
                                        player.seek(target);
                                      }
                                    },
                                    activeColor: Colors.white,
                                    inactiveColor: Colors.white24,
                                  ),
                                ),
                                // Time labels
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8.0,
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        _formatDuration(position),
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 12,
                                        ),
                                      ),
                                      Text(
                                        _formatDuration(duration),
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 20),
                                // Play/Pause button
                                GestureDetector(
                                  onTap: () async {
                                    final player = _audioPlayers[i];
                                    if (player == null) return;
                                    try {
                                      if (isPlaying) {
                                        await player.pause();
                                      } else {
                                        if (position == Duration.zero) {
                                          await player.play(
                                            UrlSource(s.mediaUrl!),
                                          );
                                          // Reapply audio effects after starting playback
                                          final effects = s.effects;
                                          double rate = 1.0;
                                          double volume = 1.0;
                                          if (effects != null) {
                                            final sp = effects['speed'];
                                            final vol = effects['volume'];
                                            if (sp is num) rate = sp.toDouble();
                                            if (vol is num)
                                              volume = vol.toDouble();
                                          }
                                          try {
                                            await player.setPlaybackRate(rate);
                                            await player.setVolume(
                                              volume.clamp(0.0, 1.0),
                                            );
                                          } catch (_) {}
                                        } else {
                                          await player.resume();
                                          // Reapply audio effects after resume
                                          final effects = s.effects;
                                          double rate = 1.0;
                                          double volume = 1.0;
                                          if (effects != null) {
                                            final sp = effects['speed'];
                                            final vol = effects['volume'];
                                            if (sp is num) rate = sp.toDouble();
                                            if (vol is num)
                                              volume = vol.toDouble();
                                          }
                                          try {
                                            await player.setPlaybackRate(rate);
                                            await player.setVolume(
                                              volume.clamp(0.0, 1.0),
                                            );
                                          } catch (_) {}
                                        }
                                      }
                                    } catch (_) {}
                                  },
                                  child: Container(
                                    width: 64,
                                    height: 64,
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.white,
                                    ),
                                    child: Icon(
                                      isPlaying
                                          ? Icons.pause
                                          : Icons.play_arrow,
                                      size: 32,
                                      color: const Color(0xFF667eea),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Caption overlay
                          if ((s.text ?? '').isNotEmpty)
                            Positioned(
                              left: 16,
                              right: 16,
                              bottom: 24,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.50),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  s.text!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                }
              },
            ),
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: LinearProgressIndicator(
                          value: (statuses.isEmpty)
                              ? 0
                              : (_index + 1) / statuses.length,
                          backgroundColor: Colors.white24,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Poster username & avatar
                  if (statuses.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.40),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Builder(
                        builder: (_) {
                          final avatarUrl =
                              _resolvedPosterAvatar ??
                              widget.posterAvatarUrl ??
                              statuses[_index].userAvatar;
                          final providedName = widget.posterName?.trim();
                          final rawDisplayName = statuses[_index].displayName
                              ?.trim();
                          final rawUsername = statuses[_index].username?.trim();
                          String display = '';
                          // Prefer resolved profile first, then passed-in name, then status fields
                          if (_resolvedPosterName != null &&
                              _resolvedPosterName!.isNotEmpty) {
                            display = _resolvedPosterName!;
                          } else if (providedName != null &&
                              providedName.isNotEmpty) {
                            display = providedName;
                          }
                          if (display.isEmpty) {
                            final resolved = _resolvedPosterName;
                            if (resolved != null && resolved.isNotEmpty) {
                              display = resolved;
                            } else if (rawDisplayName != null &&
                                rawDisplayName.isNotEmpty) {
                              display = rawDisplayName;
                            } else if (rawUsername != null &&
                                rawUsername.isNotEmpty) {
                              // Mirror home/feed: use username without leading '@'
                              display = rawUsername.startsWith('@')
                                  ? rawUsername.substring(1)
                                  : rawUsername;
                            } else {
                              display = 'User';
                            }
                          }
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircleAvatar(
                                radius: 16,
                                backgroundColor: Colors.white24,
                                backgroundImage:
                                    (avatarUrl != null && avatarUrl.isNotEmpty)
                                    ? NetworkImage(avatarUrl)
                                    : null,
                                child: (avatarUrl == null || avatarUrl.isEmpty)
                                    ? const Icon(
                                        Icons.person,
                                        color: Colors.white,
                                      )
                                    : null,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                display,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
            // Owner-only viewers eye overlay
            if (_isOwner)
              Positioned(
                bottom: 16,
                right: 16,
                child: GestureDetector(
                  onTap: _showViewersModal,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.remove_red_eye,
                          color: Colors.white,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Builder(
                          builder: (_) {
                            final s = widget.statuses[_index];
                            final count =
                                _viewCounts[s.id] ?? _currentViewCount;
                            return Text(
                              count.toString(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Viewers eye overlay helpers (moved inside State class)
  Future<void> _loadViewCountForCurrent() async {
    await _loadViewCountForIndex(_index);
  }

  Future<void> _loadViewCountForIndex(int i) async {
    try {
      if (!_isOwner) return;
      if (i < 0 || i >= widget.statuses.length) return;
      final status = widget.statuses[i];
      final count = await StatusService.of().getStatusViewCount(status.id);
      if (!mounted) return;
      setState(() {
        _viewCounts[status.id] = count;
        if (_index == i) {
          _currentViewCount = count;
        }
      });
    } catch (_) {}
  }

  Future<void> _showViewersModal() async {
    try {
      if (!_isOwner) return;
      final status = widget.statuses[_index];
      final viewers = await StatusService.of().listStatusViewers(status.id);
      if (!mounted) return;
      showModalBottomSheet(
        context: context,
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (ctx) {
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: const [
                      Icon(Icons.remove_red_eye, color: Colors.white),
                      SizedBox(width: 8),
                      const LocalizedText(
                        'viewed_by',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(color: Colors.white24, height: 1),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: viewers.length,
                    separatorBuilder: (_, __) =>
                        const Divider(color: Colors.white24, height: 1),
                    itemBuilder: (_, idx) {
                      final v = viewers[idx];
                      final name = ((v['display_name'] as String?)?.trim())
                          .toString();
                      final username = ((v['username'] as String?)?.trim())
                          .toString();
                      final title = (name.isNotEmpty)
                          ? name
                          : (username.isNotEmpty
                                ? (username.startsWith('@')
                                      ? username.substring(1)
                                      : username)
                                : 'User');
                      final avatarUrl = v['avatar_url'] as String?;
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.white24,
                          backgroundImage:
                              (avatarUrl != null && avatarUrl.isNotEmpty)
                              ? NetworkImage(avatarUrl)
                              : null,
                          child: (avatarUrl == null || avatarUrl.isEmpty)
                              ? const Icon(Icons.person, color: Colors.white)
                              : null,
                        ),
                        title: Text(
                          title,
                          style: const TextStyle(color: Colors.white),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      );
    } catch (_) {}
  }
}

String _formatDuration(Duration duration) {
  String twoDigits(int n) => n.toString().padLeft(2, '0');
  final minutes = twoDigits(duration.inMinutes.remainder(60));
  final seconds = twoDigits(duration.inSeconds.remainder(60));
  return '$minutes:$seconds';
}
