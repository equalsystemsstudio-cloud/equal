import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'create_post_screen.dart';
import 'photo_creation_screen.dart';
import 'text_creation_screen.dart';
import 'audio_creation_screen.dart';
import 'live_streaming_screen.dart';
import 'ai_generation_screen.dart';
import 'main_screen.dart';
import '../services/localization_service.dart';
import '../config/app_colors.dart';
import 'dart:ui' as ui;
import '../services/auth_service.dart'
    ;
import '../services/content_service.dart'
    ;

// ignore_for_file: unused_element
class ContentTypeSelectionScreen extends StatefulWidget {
  final String? parentPostId;
  const ContentTypeSelectionScreen({super.key, this.parentPostId});

  @override
  State<ContentTypeSelectionScreen> createState() =>
      _ContentTypeSelectionScreenState();
}

class _ContentTypeSelectionScreenState extends State<ContentTypeSelectionScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _headerController = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat();

  final AuthService _authService = AuthService();
  final ContentService _contentService = ContentService();

  @override
  void dispose() {
    _headerController.dispose();
    super.dispose();
  }

  // Sanitize localization output for UI display: hide '-' and '_' between words
  String _tx(String key) =>
      LocalizationService.t(key).replaceAll(RegExp(r'[_-]+'), ' ').trim();

  @override
  Widget build(BuildContext context) {
    final bool reduceMotion = MediaQuery.of(context).accessibleNavigation;
    // Keep shimmer respectful of accessibility preferences
    try {
      if (reduceMotion && _headerController.isAnimating) {
        _headerController.stop();
      } else if (!reduceMotion && !_headerController.isAnimating) {
        _headerController.repeat();
      }
    } catch (_) {
      // Safeguard: controller may have been disposed due to route changes
    }

    // Make cards taller in portrait to avoid tile Column overflows
    final Orientation orientation = MediaQuery.of(context).orientation;
    final double cardAspect = orientation == Orientation.portrait ? 0.84 : 1.12;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => const MainScreen()),
            (route) => false,
          ),
        ),
        title: LocalizedText(
          'create_content',
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Shimmering luxe header
            reduceMotion
                ? LocalizedText(
                    'what_would_you_like_to_create',
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                    ),
                  )
                : AnimatedBuilder(
                    animation: _headerController,
                    builder: (context, child) {
                      return ShaderMask(
                        shaderCallback: (Rect bounds) {
                          final double t = _headerController.value;
                          return LinearGradient(
                            begin: Alignment(-1.0 + t * 2, 0),
                            end: Alignment(1.0 + t * 2, 0),
                            colors: [
                              Colors.white.withOpacity(0.85),
                              Colors.white,
                              Colors.white.withOpacity(0.85),
                            ],
                            stops: const [0.35, 0.5, 0.65],
                          ).createShader(bounds);
                        },
                        blendMode: BlendMode.srcATop,
                        child: LocalizedText(
                          'what_would_you_like_to_create',
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.3,
                          ),
                        ),
                      );
                    },
                  ),
            const SizedBox(height: 6),
            // Subtle gradient underline
            Container(
              height: 2,
              width: 160,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF7C4DFF), Color(0xFFEC407A)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.all(Radius.circular(2)),
              ),
            ),
            const SizedBox(height: 10),
            LocalizedText(
              'choose_content_type_to_get_started',
              style: GoogleFonts.poppins(
                color: Colors.white70,
                fontSize: 15,
                fontWeight: FontWeight.w400,
              ),
            ),
            const SizedBox(height: 32),
            Expanded(
              child: GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 18,
                mainAxisSpacing: 18,
                childAspectRatio: cardAspect,
                children: [
                  _StaggeredReveal(
                    index: 0,
                    reduceMotion: reduceMotion,
                    child: _ContentTypeTile(
                      icon: Icons.videocam,
                      title: 'video',
                      subtitle: 'video_record_or_upload',
                      color: Colors.red,
                      onTap: () => _navigateToVideoCreation(context),
                    ),
                  ),
                  _StaggeredReveal(
                    index: 1,
                    reduceMotion: reduceMotion,
                    child: _ContentTypeTile(
                      icon: Icons.camera_alt,
                      title: 'photo',
                      subtitle: 'photo_take_or_upload',
                      color: Colors.blue,
                      onTap: () => _navigateToPhotoCreation(context),
                    ),
                  ),
                  _StaggeredReveal(
                    index: 2,
                    reduceMotion: reduceMotion,
                    child: _ContentTypeTile(
                      icon: Icons.text_fields,
                      title: 'text',
                      subtitle: 'text_write_your_thoughts',
                      color: Colors.green,
                      onTap: () => _navigateToTextCreation(context),
                    ),
                  ),
                  _StaggeredReveal(
                    index: 3,
                    reduceMotion: reduceMotion,
                    child: _ContentTypeTile(
                      icon: Icons.mic,
                      title: 'audio',
                      subtitle: 'audio_record_voice_note',
                      color: Colors.orange,
                      onTap: () => _navigateToAudioCreation(context),
                    ),
                  ),
                  _StaggeredReveal(
                    index: 4,
                    reduceMotion: reduceMotion,
                    child: _ContentTypeTile(
                      icon: Icons.live_tv,
                      title: 'go_live',
                      subtitle: 'start_live_streaming',
                      color: Colors.purple,
                      onTap: () => _attemptGoLive(context),
                    ),
                  ),
                  _StaggeredReveal(
                    index: 5,
                    reduceMotion: reduceMotion,
                    child: _ContentTypeTile(
                      icon: Icons.auto_awesome,
                      title: 'ai_generate',
                      subtitle: 'create_with_ai',
                      color: Colors.pink,
                      onTap: () => _navigateToAIGeneration(context),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Modern, animated tile is defined at top-level below.
  // See the _ContentTypeTile class at the end of this file.

  void _navigateToVideoCreation(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            CreatePostScreen(parentPostId: widget.parentPostId),
      ),
    );
  }

  void _navigateToPhotoCreation(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PhotoCreationScreen(
          preGeneratedImage: null,
          parentPostId: widget.parentPostId,
        ),
      ),
    );
  }

  void _navigateToTextCreation(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            TextCreationScreen(parentPostId: widget.parentPostId),
      ),
    );
  }

  void _navigateToAudioCreation(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            AudioCreationScreen(parentPostId: widget.parentPostId),
      ),
    );
  }

  void _navigateToLiveStream(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const LiveStreamingScreen()),
    );
  }

  void _navigateToAIGeneration(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AIGenerationScreen()),
    );
  }

  void _showComingSoon(BuildContext context, String feature) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: LocalizedText(
          'coming_soon',
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: AutoTranslatedText(
          '${LocalizationService.t('feature_coming_soon')} $feature',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: LocalizedText(
              'ok',
              style: GoogleFonts.poppins(
                color: Colors.blue,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _attemptGoLive(BuildContext context) async {
    try {
      final bool eligible = await _checkGoLiveEligibility();
      if (!mounted) return;
      // Always show the dialog with dynamic statuses and Apply CTA
      _showGoLiveRequirementsDialog(context, eligibleOverride: eligible);
    } catch (e) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.grey[900],
          title: LocalizedText(
            'go_live',
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: AutoTranslatedText(
            'An error occurred while checking eligibility. Please try again later.',
            style: TextStyle(color: AppColors.textPrimary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: LocalizedText(
                'ok',
                style: GoogleFonts.poppins(
                  color: Colors.blue,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }
  }

  Future<bool> _checkGoLiveEligibility() async {
    if (!_authService.isAuthenticated) {
      return false;
    }

    final profile = await _authService.getCurrentUserProfile();
    if (profile == null) {
      return false;
    }

    DateTime? birthDate;
    final dynamic bdRaw = profile['birth_date'] ?? profile['date_of_birth'] ?? profile['dob'];
    if (bdRaw is String) {
      birthDate = DateTime.tryParse(bdRaw);
    } else if (bdRaw is DateTime) {
      birthDate = bdRaw;
    }
    final bool is18OrOlder = birthDate != null ? _calculateAgeYears(birthDate) >= 18 : false;

    DateTime? createdAt;
    final dynamic caRaw = profile['created_at'];
    if (caRaw is String) {
      createdAt = DateTime.tryParse(caRaw);
    } else if (caRaw is DateTime) {
      createdAt = caRaw;
    }
    final bool has10DaysUsage = createdAt != null ? DateTime.now().difference(createdAt).inDays >= 10 : false;

    final int followers = (profile['followers_count'] as int?) ?? 0;
    final bool has1kFollowers = followers >= 1000;

    final analytics = await _contentService.getUserAnalytics();
    final int totalEngagement = (analytics['total_engagement'] as int?) ??
        ((analytics['total_likes'] as int?) ?? 0) +
        ((analytics['total_comments'] as int?) ?? 0) +
        ((analytics['total_shares'] as int?) ?? 0);
    final bool has5kReactions = totalEngagement >= 5000;

    return is18OrOlder && has10DaysUsage && has1kFollowers && has5kReactions;
  }

  int _calculateAgeYears(DateTime birthDate) {
    final today = DateTime.now();
    int age = today.year - birthDate.year;
    final hadBirthdayThisYear = (today.month > birthDate.month) ||
        (today.month == birthDate.month && today.day >= birthDate.day);
    if (!hadBirthdayThisYear) {
      age -= 1;
    }
    return age;
  }

  Future<Map<String, dynamic>> _getGoLiveEligibilityDetails() async {
    final profile = await _authService.getCurrentUserProfile();
    if (profile == null) {
      return {
        'ageYears': null,
        'is18OrOlder': false,
        'daysSinceCreated': null,
        'has10DaysUsage': false,
        'followersCount': 0,
        'has1kFollowers': false,
        'totalEngagement': 0,
        'has5kReactions': false,
        'eligible': false,
      };
    }

    // Age
    DateTime? birthDate;
    final dynamic bdRaw = profile['birth_date'] ?? profile['date_of_birth'] ?? profile['dob'];
    if (bdRaw is String) {
      birthDate = DateTime.tryParse(bdRaw);
    } else if (bdRaw is DateTime) {
      birthDate = bdRaw;
    }
    final int? ageYears = birthDate != null ? _calculateAgeYears(birthDate) : null;
    final bool is18OrOlder = (ageYears ?? 0) >= 18;

    // Account age
    DateTime? createdAt;
    final dynamic caRaw = profile['created_at'];
    if (caRaw is String) {
      createdAt = DateTime.tryParse(caRaw);
    } else if (caRaw is DateTime) {
      createdAt = caRaw;
    }
    final int? daysSinceCreated = createdAt != null ? DateTime.now().difference(createdAt).inDays : null;
    final bool has10DaysUsage = (daysSinceCreated ?? 0) >= 10;

    // Followers
    final int followersCount = (profile['followers_count'] as int?) ?? 0;
    final bool has1kFollowers = followersCount >= 1000;

    // Engagement
    final analytics = await _contentService.getUserAnalytics();
    final int totalEngagement = (analytics['total_engagement'] as int?) ??
        ((analytics['total_likes'] as int?) ?? 0) +
        ((analytics['total_comments'] as int?) ?? 0) +
        ((analytics['total_shares'] as int?) ?? 0);
    final bool has5kReactions = totalEngagement >= 5000;

    final bool eligible = is18OrOlder && has10DaysUsage && has1kFollowers && has5kReactions;

    return {
      'ageYears': ageYears,
      'is18OrOlder': is18OrOlder,
      'daysSinceCreated': daysSinceCreated,
      'has10DaysUsage': has10DaysUsage,
      'followersCount': followersCount,
      'has1kFollowers': has1kFollowers,
      'totalEngagement': totalEngagement,
      'has5kReactions': has5kReactions,
      'eligible': eligible,
    };
  }

  void _showGoLiveRequirementsDialog(BuildContext context, {bool? eligibleOverride}) {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              children: [
                BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: const SizedBox.shrink(),
                ),
                Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xD9101012), Color(0xD9201A24)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: Border.all(color: const Color(0x33FFFFFF)),
                    boxShadow: const [
                      BoxShadow(color: Color(0x33000000), blurRadius: 24, offset: Offset(0, 12)),
                    ],
                  ),
                  child: FutureBuilder<Map<String, dynamic>>(
                    future: _getGoLiveEligibilityDetails(),
                    builder: (context, snapshot) {
                      final bool loading = !snapshot.hasData;
                      final data = snapshot.data ?? {};
                      final bool eligible = eligibleOverride ?? (data['eligible'] as bool? ?? false);

                      Widget checkRow({required IconData icon, required String title, required String subtitle, required bool ok}) {
                        return Container(
                          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.04),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white.withOpacity(0.06)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: ok
                                        ? [const Color(0xFF00E676), const Color(0xFF1DE9B6)]
                                        : [const Color(0xFFFF5252), const Color(0xFFFF1744)],
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(icon, color: Colors.white, size: 22),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    LocalizedText(
                                      title,
                                      style: GoogleFonts.poppins(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    AutoTranslatedText(
                                      subtitle,
                                      style: TextStyle(color: Colors.white70, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(ok ? Icons.check_circle : Icons.error_outline,
                                  color: ok ? const Color(0xFF69F0AE) : const Color(0xFFFF5252))
                            ],
                          ),
                        );
                      }

                      return Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Header
                            Row(
                              children: [
                                const Icon(Icons.live_tv, color: Colors.white, size: 22),
                                const SizedBox(width: 8),
                                LocalizedText(
                                  'go_live',
                                  style: GoogleFonts.poppins(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const Spacer(),
                                IconButton(
                                  icon: const Icon(Icons.close, color: Colors.white70),
                                  onPressed: () => Navigator.pop(ctx),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),

                            // Requirement list
                            if (loading) ...[
                              const Center(child: Padding(
                                padding: EdgeInsets.symmetric(vertical: 24),
                                child: CircularProgressIndicator(color: Colors.white),
                              ))
                            ] else ...[
                              checkRow(
                                icon: Icons.cake,
                                title: 'age_requirement',
                                subtitle: LocalizationService.t('age_requirement_subtitle')
                                    .replaceAll('{years}', '${data['ageYears'] ?? '-'}'),
                                ok: data['is18OrOlder'] as bool? ?? false,
                              ),
                              const SizedBox(height: 10),
                              checkRow(
                                icon: Icons.event_available,
                                title: 'usage_requirement',
                                subtitle: LocalizationService.t('usage_requirement_subtitle')
                                    .replaceAll('{days}', '${data['daysSinceCreated'] ?? '-'}'),
                                ok: data['has10DaysUsage'] as bool? ?? false,
                              ),
                              const SizedBox(height: 10),
                              checkRow(
                                icon: Icons.people_alt,
                                title: 'trackers_requirement',
                                subtitle: LocalizationService.t('trackers_requirement_subtitle')
                                    .replaceAll('{count}', '${data['followersCount'] ?? 0}'),
                                ok: data['has1kFollowers'] as bool? ?? false,
                              ),
                              const SizedBox(height: 10),
                              checkRow(
                                icon: Icons.favorite_border,
                                title: 'reactions_requirement',
                                subtitle: LocalizationService.t('reactions_requirement_subtitle')
                                    .replaceAll('{count}', '${data['totalEngagement'] ?? 0}'),
                                ok: data['has5kReactions'] as bool? ?? false,
                              ),
                            ],

                            const SizedBox(height: 16),
                            LocalizedText(
                              'apply_here_if_requirements_met',
                              style: TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                            const SizedBox(height: 10),

                            // Super modern Apply button (gradient + glow)
                            AnimatedOpacity(
                              opacity: (eligible && !loading) ? 1.0 : 0.5,
                              duration: const Duration(milliseconds: 250),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: (eligible && !loading)
                                    ? () {
                                        Navigator.pop(ctx);
                                        _navigateToLiveStream(context);
                                      }
                                    : null,
                                child: Container(
                                  height: 48,
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [Color(0xFF7C4DFF), Color(0xFFEC407A)],
                                      begin: Alignment.centerLeft,
                                      end: Alignment.centerRight,
                                    ),
                                    borderRadius: BorderRadius.circular(14),
                                    boxShadow: const [
                                      BoxShadow(color: Color(0x667C4DFF), blurRadius: 24, offset: Offset(0, 12)),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.rocket_launch, color: Colors.white),
                                      const SizedBox(width: 8),
                                      Text(
                                        LocalizationService.t('apply'),
                                        style: GoogleFonts.poppins(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 15,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),

                            // Helper text when not eligible
                            if (!eligible && !loading)
                              LocalizedText(
                                'complete_requirements_to_enable_apply',
                                style: TextStyle(color: Colors.white54, fontSize: 12),
                              ),
                            const SizedBox(height: 8),
                          ],
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
  }
}

// Top-level modern, animated tile purely for UI polish
class _ContentTypeTile extends StatefulWidget {
  const _ContentTypeTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  State<_ContentTypeTile> createState() => _ContentTypeTileState();
}

class _ContentTypeTileState extends State<_ContentTypeTile> {
  bool _hovering = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final bool reduceMotion = MediaQuery.of(context).accessibleNavigation;
    final Color accent = widget.color;
    final double effectiveScale = reduceMotion
        ? 1.0
        : (_pressed ? 0.985 : (_hovering ? 1.015 : 1.0));
    final double liftY = reduceMotion ? 0.0 : (_hovering ? -2.0 : 0.0);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: Duration(milliseconds: reduceMotion ? 0 : 220),
          curve: Curves.easeOutCubic,
          transform: Matrix4.identity()
            ..translate(0.0, liftY)
            ..scale(effectiveScale),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: accent.withOpacity(
                  _hovering && !reduceMotion ? 0.30 : 0.18,
                ),
                blurRadius: _hovering && !reduceMotion ? 28 : 20,
                spreadRadius: 0.5,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Stack(
              children: [
                // Glass backdrop blur layer
                BackdropFilter(
                  filter: ui.ImageFilter.blur(
                    sigmaX: _hovering && !reduceMotion ? 9 : 6,
                    sigmaY: _hovering && !reduceMotion ? 9 : 6,
                  ),
                  child: Container(color: Colors.black.withOpacity(0.20)),
                ),
                // Border + subtle gradient tint
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.06),
                      width: 1,
                    ),
                    gradient: LinearGradient(
                      colors: [
                        Colors.black.withOpacity(0.30),
                        Colors.black.withOpacity(0.15),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                ),
                // Content
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Icon with gradient halo
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [
                              accent.withOpacity(0.22),
                              accent.withOpacity(0.05),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: accent.withOpacity(
                                _hovering && !reduceMotion ? 0.36 : 0.22,
                              ),
                              blurRadius: _hovering && !reduceMotion ? 22 : 14,
                              spreadRadius: 0,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Icon(widget.icon, color: accent, size: 28),
                      ),
                      const SizedBox(height: 10),
                      // Title (prefer dictionary value, then auto-translate if needed)
                      AutoTranslatedText(
                        LocalizationService.t(widget.title),
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 16.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      // Subtitle
                      Builder(
                        builder: (context) {
                          final bool isPhotoSubtitle =
                              widget.subtitle == 'photo_take_or_upload';
                          if (isPhotoSubtitle &&
                              LocalizationService.currentLanguage == 'fr') {
                            return Text(
                              'Prendre une photo ou en importer une',
                              style: GoogleFonts.poppins(
                                color: Colors.white70,
                                fontSize: 12.0,
                                fontWeight: FontWeight.w400,
                                height: 1.15,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              softWrap: true,
                            );
                          }
                          return LocalizedText(
                            widget.subtitle,
                            style: GoogleFonts.poppins(
                              color: Colors.white70,
                              fontSize: 12.0,
                              fontWeight: FontWeight.w400,
                              height: 1.15,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            softWrap: true,
                          );
                        },
                      ),
                      const SizedBox(height: 4),
                      // Optional badge for eye-candy only
                      Builder(
                        builder: (context) {
                          final isAi = widget.title.toLowerCase().contains(
                            'ai',
                          );
                          final isLive = widget.title.toLowerCase().contains(
                            'live',
                          );
                          if (!isAi && !isLive) return const SizedBox.shrink();
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: (isAi ? accent : Colors.purple)
                                  .withOpacity(0.16),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: (isAi ? accent : Colors.purple),
                                width: 0.8,
                              ),
                            ),
                            child: AutoTranslatedText(
                              isAi ? 'New' : 'Live',
                              style: GoogleFonts.poppins(
                                color: (isAi ? accent : Colors.purple),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.2,
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Cinematic staggered reveal wrapper for grid children
class _StaggeredReveal extends StatefulWidget {
  const _StaggeredReveal({
    required this.index,
    required this.child,
    required this.reduceMotion,
  });
  final int index;
  final Widget child;
  final bool reduceMotion;
  @override
  State<_StaggeredReveal> createState() => _StaggeredRevealState();
}

class _StaggeredRevealState extends State<_StaggeredReveal> {
  bool _visible = false;
  @override
  void initState() {
    super.initState();
    if (widget.reduceMotion) {
      _visible = true;
    } else {
      Future.delayed(Duration(milliseconds: 80 * (widget.index + 1)), () {
        if (mounted) setState(() => _visible = true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _visible ? 1.0 : 0.0,
      duration: Duration(milliseconds: widget.reduceMotion ? 0 : 420),
      curve: Curves.easeOutCubic,
      child: AnimatedSlide(
        offset: _visible ? Offset.zero : const Offset(0.0, 0.08),
        duration: Duration(milliseconds: widget.reduceMotion ? 0 : 420),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}
