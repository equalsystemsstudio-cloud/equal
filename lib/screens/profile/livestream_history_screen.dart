import 'package:flutter/material.dart';
import '../../services/live_streaming_service.dart';
import '../live_stream_viewer_screen.dart';
import '../../services/auth_service.dart';
import '../../config/app_colors.dart';
import '../../services/localization_service.dart';

class LivestreamHistoryScreen extends StatefulWidget {
  final String? userId;
  final String? username;

  const LivestreamHistoryScreen({super.key, this.userId, this.username});

  @override
  State<LivestreamHistoryScreen> createState() =>
      _LivestreamHistoryScreenState();
}

class _LivestreamHistoryScreenState extends State<LivestreamHistoryScreen> {
  final _liveStreamingService = LiveStreamingService();
  final _authService = AuthService();

  List<LiveStreamModel> _streams = [];
  bool _isLoading = true;
  bool _isOwnProfile = false;

  @override
  void initState() {
    super.initState();
    _isOwnProfile =
        widget.userId == null || widget.userId == _authService.currentUser?.id;
    _loadStreams();
  }

  Future<void> _loadStreams() async {
    try {
      setState(() => _isLoading = true);

      final streams = await _liveStreamingService.getUserStreams(
        userId: widget.userId,
        limit: 50,
      );

      if (mounted) {
        setState(() {
          _streams = streams;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: LocalizedText('Error loading streams: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatDuration(DateTime? startedAt, DateTime? endedAt) {
    if (startedAt == null) return 'Unknown';

    final end = endedAt ?? DateTime.now();
    final duration = end.difference(startedAt);

    if (duration.inHours > 0) {
      return '${duration.inHours}h ${duration.inMinutes % 60}m';
    } else {
      return '${duration.inMinutes}m';
    }
  }

  String _formatDurationForStream(LiveStreamModel stream) {
    final seconds = stream.finalDuration;
    if (seconds != null && seconds > 0) {
      final mins = seconds ~/ 60;
      final hours = mins ~/ 60;
      if (hours > 0) {
        return '${hours}h ${mins % 60}m';
      } else {
        return '${mins}m';
      }
    }
    return _formatDuration(stream.startedAt, stream.endedAt);
  }

  String _formatDate(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays == 0) {
      return 'Today';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'live':
        return Colors.red;
      case 'ended':
        return Colors.green;
      case 'error':
        return Colors.orange;
      default:
        return AppColors.textSecondary;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'live':
        return Icons.circle;
      case 'ended':
        return Icons.check_circle;
      case 'error':
        return Icons.error;
      default:
        return Icons.help;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: Text(
          _isOwnProfile
              ? 'My Livestreams'
              : '${widget.username ?? "User"}\'s Livestreams',
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _streams.isEmpty
          ? _buildEmptyState()
          : _buildStreamsList(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.videocam_off, size: 64, color: AppColors.textSecondary),
          const SizedBox(height: 16),
          Text(
            _isOwnProfile ? 'No livestreams yet' : 'No livestreams found',
            style: const TextStyle(
              fontSize: 18,
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _isOwnProfile
                ? 'Start your first livestream to see it here!'
                : 'This user hasn\'t created any livestreams yet.',
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildStreamsList() {
    return RefreshIndicator(
      onRefresh: _loadStreams,
      color: AppColors.primary,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _streams.length,
        itemBuilder: (context, index) {
          final stream = _streams[index];
          return _buildStreamCard(stream);
        },
      ),
    );
  }

  Widget _buildStreamCard(LiveStreamModel stream) {
    final bool isLive = stream.status.toLowerCase() == 'live';
    return GestureDetector(
      onTap: isLive
          ? () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => LiveStreamViewerScreen(
                    streamId: stream.id,
                    title: stream.title,
                    description: stream.description,
                  ),
                ),
              );
            }
          : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with title and status
              Row(
                children: [
                  Expanded(
                    child: Text(
                      stream.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _getStatusColor(
                        stream.status,
                      ).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _getStatusIcon(stream.status),
                          size: 12,
                          color: _getStatusColor(stream.status),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          stream.status.toUpperCase(),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: _getStatusColor(stream.status),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              if (stream.description.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  stream.description,
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],

              const SizedBox(height: 12),

              // Stats row
              Row(
                children: [
                  _buildStatItem(
                    Icons.visibility,
                    '${stream.viewerCount} viewers',
                  ),
                  const SizedBox(width: 16),
                  _buildStatItem(
                    Icons.access_time,
                    _formatDurationForStream(stream),
                  ),
                  const Spacer(),
                  Text(
                    _formatDate(stream.startedAt),
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color:
                          (stream.provider == 'livekit'
                                  ? Colors.purple
                                  : Colors.green)
                              .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color:
                            (stream.provider == 'livekit'
                                    ? Colors.purple
                                    : Colors.green)
                                .withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      stream.provider.toUpperCase(),
                      style: TextStyle(
                        fontSize: 12,
                        color: (stream.provider == 'livekit'
                            ? Colors.purple
                            : Colors.green),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),

              if (stream.isEphemeral || stream.savedLocally) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (stream.isEphemeral)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.orange.withValues(alpha: 0.3),
                          ),
                        ),
                        child: const Text(
                          'EPHEMERAL',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    if (stream.savedLocally)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.blue.withValues(alpha: 0.3),
                          ),
                        ),
                        child: const Text(
                          'SAVED LOCALLY',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ],

              if (stream.tags.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: stream.tags.take(3).map((tag) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '#$tag',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],

              if (isLive) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => LiveStreamViewerScreen(
                            streamId: stream.id,
                            title: stream.title,
                            description: stream.description,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(
                      Icons.play_circle_fill,
                      color: Colors.white,
                    ),
                    label: const Text(
                      'Join Live',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatItem(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.textSecondary),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}
