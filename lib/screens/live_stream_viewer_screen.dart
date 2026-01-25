import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/live_streaming_service.dart';
import '../services/gift_service.dart';
import '../services/history_service.dart';

class LiveStreamViewerScreen extends StatefulWidget {
  final String streamId;
  final String? title;
  final String? description;

  const LiveStreamViewerScreen({
    super.key,
    required this.streamId,
    this.title,
    this.description,
  });

  @override
  State<LiveStreamViewerScreen> createState() => _LiveStreamViewerScreenState();
}

class _LiveStreamViewerScreenState extends State<LiveStreamViewerScreen> {
  final LiveStreamingService _liveStreamingService = LiveStreamingService();
  final RTCVideoRenderer _rtcRenderer = RTCVideoRenderer();
  final GiftService _giftService = GiftService();
  bool _isViewing = false; // ignore: unused_field
  int _viewerCount = 0;
  String? _error;
  Map<String, dynamic>? _activeGift;
  bool _showGiftOverlay = false;
  int _walletBalance = 0;
  late final StreamSubscription _giftsSub;
  // Debug event buffer
  final List<Map<String, dynamic>> _debugEvents = [];
  late StreamSubscription _statusSub;
  late StreamSubscription _viewersSub;
  bool _isDisposed = false;
  Timer? _historyTimer;
  bool _historyAdded = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _rtcRenderer.initialize();
    // Subscribe for remote stream updates
    _statusSub = _liveStreamingService.streamStatusStream.listen((event) {
      if (_isDisposed || !mounted) return;
      _recordDebugEvent(event);
      if (_isDisposed || !mounted) return;
      if (event['type'] == 'viewer_remote_stream_updated') {
        final remote = _liveStreamingService.viewerRemoteStream;
        if (remote != null) {
          if (_isDisposed || !mounted) return;
          setState(() {
            _rtcRenderer.srcObject = remote;
            _error = null;
          });
        }
      } else if (event['type'] == 'viewer_handshake_timeout') {
        final msg =
            (event['message'] as String?) ??
            'Connection is taking longer than expected.';
        if (_isDisposed || !mounted) return;
        setState(() {
          _error = msg;
        });
      } else if (event['type'] == 'error') {
        final msg = (event['message'] as String?) ?? 'An error occurred.';
        if (_isDisposed || !mounted) return;
        setState(() {
          _error = msg;
        });
      }
    });
    // Subscribe to presence viewer count updates
    _viewersSub = _liveStreamingService.viewersStream.listen((viewers) {
      if (_isDisposed || !mounted) return;
      setState(() {
        _viewerCount = viewers.length;
      });
    });
    // Subscribe to gift events for overlay
    _giftsSub = _liveStreamingService.giftsStream.listen((gift) {
      if (_isDisposed) return;
      _triggerGiftOverlay(gift);
    });
    // Preload wallet balance
    try {
      final bal = await _giftService.ensureWallet();
      if (_isDisposed || !mounted) return;
      setState(() {
        _walletBalance = bal;
      });
    } catch (_) {}
    await _startViewing();
  }

  Future<void> _startViewing() async {
    try {
      await _liveStreamingService.startViewingStream(widget.streamId);
      if (!mounted) return;
      setState(() {
        _isViewing = true;
      });
      _historyTimer?.cancel();
      _historyAdded = false;
      _historyTimer = Timer(const Duration(seconds: 7), () async {
        if (!mounted || _isDisposed || !_isViewing) return;
        if (_historyAdded) return;
        try {
          await HistoryService.addLiveStreamView(
            streamId: widget.streamId,
            title: widget.title,
            description: widget.description,
          );
        } catch (_) {}
        if (mounted) {
          setState(() {
            _historyAdded = true;
          });
        } else {
          _historyAdded = true;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    }
  }

  Future<void> _stopViewing() async {
    await _liveStreamingService.stopViewingStream();
    if (!mounted) return;
    _historyTimer?.cancel();
    setState(() {
      _isViewing = false;
      _viewerCount = 0;
      _rtcRenderer.srcObject = null;
      _historyAdded = false;
    });
  }

  void _triggerGiftOverlay(Map<String, dynamic> gift) {
    if (!mounted) return;
    setState(() {
      _activeGift = gift;
      _showGiftOverlay = true;
    });
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      setState(() {
        _showGiftOverlay = false;
      });
    });
  }

  IconData _iconForGiftKey(String? key) {
    switch (key) {
      case 'gift':
        return Icons.card_giftcard;
      case 'star':
        return Icons.star_rounded;
      case 'fire':
        return Icons.local_fire_department_rounded;
      case 'heart':
        return Icons.favorite_rounded;
      default:
        return Icons.emoji_objects_rounded;
    }
  }

  Future<void> _openGiftSheet() async {
    final catalog = await _giftService.getCatalog();
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: false,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Send a Gift',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Row(
                        children: [
                          const Icon(
                            Icons.monetization_on_rounded,
                            color: Colors.amber,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '$_walletBalance',
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  GridView.builder(
                    shrinkWrap: true,
                    itemCount: catalog.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          childAspectRatio: 0.9,
                        ),
                    itemBuilder: (_, i) {
                      final g = catalog[i];
                      final disabled = _walletBalance < g.costCoins;
                      return InkWell(
                        onTap: disabled
                            ? null
                            : () async {
                                try {
                                  final res = await _giftService.sendGift(
                                    streamId: widget.streamId,
                                    giftId: g.id,
                                  );
                                  setModalState(() {
                                    _walletBalance =
                                        (res['new_balance'] as int?) ??
                                        _walletBalance - g.costCoins;
                                  });
                                  if (!mounted) return;
                                  Navigator.of(ctx).pop();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Sent ${g.name}!')),
                                  );
                                } catch (e) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(e.toString()),
                                      backgroundColor: Colors.redAccent,
                                    ),
                                  );
                                }
                              },
                        child: Container(
                          decoration: BoxDecoration(
                            color: disabled ? Colors.white10 : Colors.white12,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: disabled ? Colors.white12 : Colors.white24,
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(
                            vertical: 12,
                            horizontal: 8,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _iconForGiftKey(g.iconKey),
                                color: Colors.white,
                                size: 28,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                g.name,
                                style: const TextStyle(color: Colors.white70),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.monetization_on_rounded,
                                    color: Colors.amber,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${g.costCoins}',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () async {
                      try {
                        await _giftService.creditCoins(
                          20,
                          reason: 'Watch reward',
                        );
                        final bal = await _giftService.getBalance();
                        setModalState(() {
                          _walletBalance = bal;
                        });
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Credited 20 coins')),
                        );
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(e.toString()),
                            backgroundColor: Colors.redAccent,
                          ),
                        );
                      }
                    },
                    child: const Text(
                      'Earn 20 coins',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _recordDebugEvent(Map<String, dynamic> event) {
    try {
      final enriched = {'ts': DateTime.now().toIso8601String(), ...event};
      _debugEvents.add(enriched);
      if (_debugEvents.length > 50) {
        _debugEvents.removeAt(0);
      }
    } catch (_) {}
  }

  Future<void> _openDebugSheet() async {
    final diagnostics = await _collectDiagnostics();
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Live Viewer Debug',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      runSpacing: 8,
                      spacing: 12,
                      children: [
                        _buildChip(
                          'Viewing',
                          diagnostics['isViewing']?.toString() ?? 'false',
                        ),
                        _buildChip(
                          'Stream ID',
                          diagnostics['streamId']?.toString() ?? 'N/A',
                        ),
                        _buildChip(
                          'Viewer Count',
                          diagnostics['viewerCount']?.toString() ?? '0',
                        ),
                        _buildChip(
                          'Supabase Remote Stream',
                          diagnostics['supabaseRemoteStream'] == true
                              ? 'Present'
                              : 'Missing',
                        ),
                        _buildChip(
                          'PeerConnection',
                          diagnostics['peerConnectionPresent'] == true
                              ? 'Present'
                              : 'Null',
                        ),
                        _buildChip(
                          'Peer Stats Count',
                          diagnostics['peerStatsCount']?.toString() ?? '0',
                        ),
                      ],
                    ),
                    if (diagnostics['error'] != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Error: ${diagnostics['error']}',
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        ElevatedButton.icon(
                          icon: const Icon(Icons.replay_circle_filled),
                          label: const Text('Retry Handshake'),
                          onPressed: () async {
                            await _liveStreamingService.retryViewerHandshake();
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Retrying viewer handshake…'),
                              ),
                            );
                          },
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.switch_access_shortcut_add),
                          label: const Text('Force Fallback to Supabase'),
                          onPressed: () async {
                            await _liveStreamingService
                                .forceFallbackToSupabase();
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Forcing fallback to Supabase RTC…',
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.copy_all_rounded),
                          label: const Text('Copy Event Log'),
                          onPressed: () async {
                            final text = _debugEvents
                                .map((e) => e.toString())
                                .join('\n');
                            await Clipboard.setData(ClipboardData(text: text));
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Copied last 50 events to clipboard.',
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Recent Events',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 180,
                      child: ListView.builder(
                        itemCount: _debugEvents.length,
                        itemBuilder: (ctx, i) {
                          final ev = _debugEvents[_debugEvents.length - 1 - i];
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Text(
                              ev.toString(),
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<Map<String, dynamic>> _collectDiagnostics() async {
    final pc = _liveStreamingService.viewerPeerConnection;
    int statsCount = 0;
    try {
      if (pc != null) {
        final stats = await pc.getStats();
        statsCount = (stats.length);
      }
    } catch (_) {}
    return {
      'isViewing': _isViewing,
      'streamId': widget.streamId,
      'viewerCount': _viewerCount,
      'error': _error,
      'supabaseRemoteStream': _rtcRenderer.srcObject != null,
      'peerConnectionPresent': pc != null,
      'peerStatsCount': statsCount,
    };
  }

  Widget _buildChip(String label, String value) {
    return Chip(
      label: Text(
        '$label: $value',
        style: const TextStyle(color: Colors.white70),
      ),
      backgroundColor: Colors.black54,
    );
  }

  @override
  void dispose() {
    _isDisposed = true;
    _historyTimer?.cancel();
    _rtcRenderer.srcObject = null;
    _rtcRenderer.dispose();
    try {
      _statusSub.cancel();
    } catch (_) {}
    try {
      _viewersSub.cancel();
    } catch (_) {}
    try {
      _giftsSub.cancel();
    } catch (_) {}
    _liveStreamingService.stopViewingStream();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(widget.title ?? 'Live Stream'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bug_report_rounded),
            onPressed: _openDebugSheet,
            tooltip: 'Debug',
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () async {
              final navigator = Navigator.of(context);
              await _stopViewing();
              if (navigator.canPop()) navigator.pop();
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: (_rtcRenderer.srcObject != null
                ? RTCVideoView(_rtcRenderer)
                : const Center(
                    child: Text(
                      'Connecting to live stream...',
                      style: TextStyle(color: Colors.white70),
                    ),
                  )),
          ),
          Positioned(
            left: 16,
            top: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  const Icon(Icons.visibility, color: Colors.white70, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    '$_viewerCount watching',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
          ),
          // Gift overlay animation (simple fade/scale)
          if (_showGiftOverlay && _activeGift != null)
            Align(
              alignment: Alignment.center,
              child: AnimatedScale(
                scale: _showGiftOverlay ? 1.0 : 0.8,
                duration: const Duration(milliseconds: 300),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 300),
                  opacity: _showGiftOverlay ? 1.0 : 0.0,
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _iconForGiftKey(_activeGift?['icon_key'] as String?),
                          color: Colors.white,
                          size: 56,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _activeGift?['gift_name'] as String? ?? 'Gift',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${_activeGift?['username'] ?? 'Someone'} sent ${_activeGift?['coins_spent'] ?? ''} coins',
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          // Gift button
          Positioned(
            right: 16,
            bottom: 24,
            child: FloatingActionButton(
              backgroundColor: Colors.pinkAccent,
              onPressed: _openGiftSheet,
              child: const Icon(Icons.card_giftcard_rounded),
            ),
          ),
          if (_error != null)
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
