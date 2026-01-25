import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../services/history_service.dart';
import '../services/localization_service.dart';
import '../services/status_service.dart';
import 'status/status_viewer_screen.dart';
import 'live_stream_viewer_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../config/app_colors.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final StatusService _statusService = StatusService(Supabase.instance.client);
  String _filter = 'all'; // all | post | status | stream

  @override
  void initState() {
    super.initState();
    // Ensure notifier has data if not yet initialized
    HistoryService.init();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: Text(
          LocalizationService.t('history'),
          style: const TextStyle(color: AppColors.textPrimary),
        ),
      ),
      body: ValueListenableBuilder<List<HistoryEntry>>(
        valueListenable: HistoryService.entriesNotifier,
        builder: (context, entries, _) {
          final filtered = _applyFilter(entries);
          final grouped = _groupEntries(filtered);
          return ListView(
            children: [
              _buildHeroHeader(entries),
              if (entries.isEmpty) ...[
                _buildEmptyState(context),
              ] else ...[
                _buildFiltersHeader(),
                for (final section in grouped.keys) ...[
                  _buildSectionHeader(section),
                  ...grouped[section]!.map(_historyCard),
                ],
              ],
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeroHeader(List<HistoryEntry> entries) {
    final hasItems = entries.isNotEmpty;
    return Container(
      height: 140,
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withOpacity(0.18),
            AppColors.accent.withOpacity(0.14),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: AppColors.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          fit: StackFit.expand,
          children: [
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(color: Colors.transparent),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          LocalizationService.t('history'),
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          hasItems
                              ? LocalizationService.t('recent_activity')
                              : LocalizationService.t('history_empty_title'),
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (hasItems)
                    FilledButton.icon(
                      onPressed: () async {
                        final confirmed = await _confirmClearDialog(context);
                        if (confirmed != true) return;
                        await HistoryService.clear();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                LocalizationService.t('history_cleared'),
                              ),
                            ),
                          );
                        }
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary.withOpacity(0.15),
                        foregroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                      ),
                      icon: const Icon(Icons.delete_outline, size: 20),
                      label: Text(LocalizationService.t('clear_history')),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          const SizedBox(height: 8),
          Container(
            height: 120,
            decoration: BoxDecoration(
              color: AppColors.surface.withOpacity(0.6),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                    child: Container(color: Colors.transparent),
                  ),
                  Center(
                    child: SvgPicture.asset(
                      'assets/icons/equal_logo.svg',
                      width: 120,
                      height: 120,
                      colorFilter: const ColorFilter.mode(
                        AppColors.accentLight,
                        BlendMode.srcIn,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            LocalizationService.t('history_empty_subtitle'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FilledButton(
                onPressed: () {
                  Navigator.pushNamed(context, '/main');
                },
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent.withOpacity(0.18),
                  foregroundColor: AppColors.accent,
                ),
                child: Text(LocalizationService.t('search')),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: () {
                  Navigator.pushNamed(context, '/main-feed');
                },
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary.withOpacity(0.18),
                  foregroundColor: AppColors.primary,
                ),
                child: Text(LocalizationService.t('discover')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFiltersHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _filterChip('all', LocalizationService.t('all')),
            const SizedBox(width: 8),
            _filterChip('post', LocalizationService.t('posts')),
            const SizedBox(width: 8),
            _filterChip('status', LocalizationService.t('statuses')),
            const SizedBox(width: 8),
            _filterChip('stream', LocalizationService.t('streams')),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(String value, String label) {
    final selected = _filter == value;
    final icon = _iconForFilter(value);
    final labelColor = selected
        ? AppColors.textPrimary
        : AppColors.textSecondary;
    return ChoiceChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: labelColor),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: labelColor)),
        ],
      ),
      backgroundColor: AppColors.surfaceVariant,
      selectedColor: AppColors.primaryLight,
      shape: StadiumBorder(
        side: BorderSide(
          color: selected ? AppColors.primaryLight : AppColors.border,
        ),
      ),
      selected: selected,
      onSelected: (_) => setState(() => _filter = value),
    );
  }

  Widget _buildSectionHeader(String sectionKey) {
    String title;
    switch (sectionKey) {
      case 'today':
        title = LocalizationService.t('today');
        break;
      case 'yesterday':
        title = LocalizationService.t('yesterday');
        break;
      case 'this_week':
        title = LocalizationService.t('this_week');
        break;
      default:
        title = LocalizationService.t('older');
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Icon(
            _iconForSection(sectionKey),
            size: 18,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Divider(color: AppColors.divider, thickness: 0.5)),
        ],
      ),
    );
  }

  List<HistoryEntry> _applyFilter(List<HistoryEntry> entries) {
    switch (_filter) {
      case 'post':
        return entries.where((e) => e.type == 'post').toList();
      case 'status':
        return entries.where((e) => e.type == 'status').toList();
      case 'stream':
        return entries.where((e) => e.type == 'stream').toList();
      default:
        return entries;
    }
  }

  Map<String, List<HistoryEntry>> _groupEntries(List<HistoryEntry> entries) {
    final now = DateTime.now().toUtc();
    final startOfToday = DateTime.utc(now.year, now.month, now.day);
    final startOfYesterday = startOfToday.subtract(const Duration(days: 1));
    final startOfWeek = startOfToday.subtract(Duration(days: now.weekday - 1));

    final Map<String, List<HistoryEntry>> groups = {
      'today': [],
      'yesterday': [],
      'this_week': [],
      'older': [],
    };

    for (final e in entries) {
      final viewed = e.viewedAt.toUtc();
      if (viewed.isAfter(startOfToday)) {
        groups['today']!.add(e);
      } else if (viewed.isAfter(startOfYesterday)) {
        groups['yesterday']!.add(e);
      } else if (viewed.isAfter(startOfWeek)) {
        groups['this_week']!.add(e);
      } else {
        groups['older']!.add(e);
      }
    }

    // Remove empty sections
    groups.removeWhere((_, list) => list.isEmpty);
    return groups;
  }

  Widget _historyCard(HistoryEntry e) {
    final key = '${e.type}:${e.id}';
    return Dismissible(
      key: ValueKey(key),
      background: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.error,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Icon(Icons.delete_outline, color: Colors.white),
          ),
        ),
      ),
      secondaryBackground: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.error,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Icon(Icons.delete_outline, color: Colors.white),
          ),
        ),
      ),
      onDismissed: (_) async {
        await HistoryService.removeEntryByKey(e.type, e.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(LocalizationService.t('removed_from_history')),
            ),
          );
        }
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: const Border.fromBorderSide(
            BorderSide(color: AppColors.border),
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withOpacity(0.07),
                    Colors.white.withOpacity(0.03),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: InkWell(
                onTap: () => _openHistoryItem(context, e),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      _buildLeading(e),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    e.title?.isNotEmpty == true
                                        ? e.title!
                                        : _localizedFallbackTitle(e),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                _typeBadge(e.type),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _subtitleText(e),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: () => _openHistoryItem(context, e),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary.withOpacity(0.14),
                          foregroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                        ),
                        icon: Icon(_actionIconFor(e), size: 20),
                        label: Text(_actionLabelFor(e)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLeading(HistoryEntry e) {
    final thumb = e.thumbnailUrl;
    if (thumb != null && thumb.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image(
          image: CachedNetworkImageProvider(thumb),
          width: 56,
          height: 56,
          fit: BoxFit.cover,
        ),
      );
    }
    return CircleAvatar(
      radius: 26,
      backgroundColor: AppColors.surfaceVariant,
      child: Icon(_iconForType(e.type), color: AppColors.textSecondary),
    );
  }

  Widget _typeBadge(String type) {
    String text;
    Color color;
    switch (type) {
      case 'post':
        text = LocalizationService.t('post_singular');
        color = AppColors.info;
        break;
      case 'status':
        text = LocalizationService.t('status');
        color = AppColors.accent;
        break;
      case 'stream':
        text = LocalizationService.t('live_stream');
        color = AppColors.live;
        break;
      default:
        text = LocalizationService.t('item');
        color = AppColors.textSecondary;
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  String _localizedFallbackTitle(HistoryEntry e) {
    switch (e.type) {
      case 'post':
        return LocalizationService.t('post_singular');
      case 'status':
        return LocalizationService.t('status');
      case 'stream':
        return LocalizationService.t('live_stream');
      default:
        return LocalizationService.t('item');
    }
  }

  String _actionLabelFor(HistoryEntry e) {
    if (e.type == 'post') return LocalizationService.t('open_item');
    return LocalizationService.t('watch_again');
  }

  String _subtitleText(HistoryEntry e) {
    final parts = <String>[];
    if ((e.subtitle ?? '').isNotEmpty) parts.add(e.subtitle!);
    parts.add(_formatViewedAt(e.viewedAt));
    return parts.join(' • ');
  }

  String _formatViewedAt(DateTime dt) {
    final locale = LocalizationService.resolveTimeagoLocale(
      LocalizationService.currentLanguage,
    );
    return timeago.format(dt.toUtc(), locale: locale);
  }

  Future<void> _openHistoryItem(BuildContext context, HistoryEntry e) async {
    try {
      switch (e.type) {
        case 'post':
          Navigator.pushNamed(context, '/post_detail', arguments: e.id);
          break;
        case 'status':
          final userId = e.userId;
          if (userId == null || userId.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  LocalizationService.t('cannot_open_status_missing_poster'),
                ),
              ),
            );
            return;
          }
          final statuses = await _statusService.fetchUserStatuses(userId);
          if (statuses.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  LocalizationService.t('no_active_statuses_to_view'),
                ),
              ),
            );
            return;
          }
          final idx = statuses.indexWhere((s) => s.id == e.id);
          final initialIndex = idx >= 0 ? idx : 0;
          if (!mounted) return;
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => StatusViewerScreen(
                statuses: statuses,
                posterName: e.subtitle,
                posterAvatarUrl: e.thumbnailUrl,
                initialIndex: initialIndex,
              ),
            ),
          );
          break;
        case 'stream':
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => LiveStreamViewerScreen(
                streamId: e.id,
                title: e.title,
                description: e.subtitle,
              ),
            ),
          );
          break;
        default:
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(LocalizationService.t('unsupported_item_type')),
            ),
          );
          break;
      }
    } catch (err) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(LocalizationService.normalize(err.toString()))),
      );
    }
  }

  IconData _iconForType(String t) {
    switch (t) {
      case 'post':
        return Icons.description_outlined;
      case 'status':
        return Icons.photo_camera_outlined;
      case 'stream':
        return Icons.live_tv_outlined;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }

  IconData _actionIconFor(HistoryEntry e) {
    if (e.type == 'post') return Icons.open_in_new;
    return Icons.play_circle_outline;
  }

  IconData _iconForFilter(String value) {
    switch (value) {
      case 'post':
        return Icons.description_outlined;
      case 'status':
        return Icons.photo_camera_outlined;
      case 'stream':
        return Icons.live_tv_outlined;
      default:
        return Icons.layers_outlined;
    }
  }

  IconData _iconForSection(String key) {
    switch (key) {
      case 'today':
        return Icons.today;
      case 'yesterday':
        return Icons.calendar_today;
      case 'this_week':
        return Icons.date_range;
      default:
        return Icons.history;
    }
  }

  Future<bool?> _confirmClearDialog(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(LocalizationService.t('clear_history')),
          content: Text(LocalizationService.t('confirm_clear_history_message')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(LocalizationService.t('cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(LocalizationService.t('clear_history')),
            ),
          ],
        );
      },
    );
  }
}
