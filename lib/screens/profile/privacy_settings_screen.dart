import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'dart:math';
import '../../services/preferences_service.dart';
import '../../services/auth_service.dart';
import '../../services/posts_service.dart';
import '../../services/database_service.dart';
import '../../config/app_colors.dart';
// Conditionally import web download helper only on web; stub elsewhere
import '../../utils/download_helper_stub.dart'
    if (dart.library.html) '../../utils/download_helper_web.dart';
import '../../services/app_service.dart';
import '../../services/localization_service.dart';

class PrivacySettingsScreen extends StatefulWidget {
  const PrivacySettingsScreen({super.key});

  @override
  State<PrivacySettingsScreen> createState() => _PrivacySettingsScreenState();
}

class _PrivacySettingsScreenState extends State<PrivacySettingsScreen> {
  final _preferencesService = PreferencesService();
  final _authService = AuthService();

  bool _isPrivateAccount = false;
  bool _allowTagging = true;
  bool _allowMentions = true;
  bool _showOnlineStatus = true;
  bool _allowMessageRequests = true;
  bool _showReadReceipts = true;
  bool _allowStoryReplies = true;
  bool _shareDataForAds = false;
  bool _allowAnalytics = true;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPrivacySettings();
  }

  Future<void> _loadPrivacySettings() async {
    try {
      // Load local preferences first as fallback
      final isPrivatePref = await _preferencesService.getPrivateAccount();
      final allowTagging = await _preferencesService.getAllowTagging();
      final allowMentions = await _preferencesService.getAllowMentions();
      final showOnline = await _preferencesService.getShowOnlineStatus();
      final allowMsgReq = await _preferencesService.getAllowMessageRequests();
      final readReceipts = await _preferencesService.getShowReadReceipts();
      final storyReplies = await _preferencesService.getAllowStoryReplies();
      final shareAds = await _preferencesService.getShareDataForAds();
      final analytics = await _preferencesService.getAllowAnalytics();

      // Try to get authoritative setting from backend profile
      Map<String, dynamic>? profile;
      try {
        profile = await _authService.getCurrentUserProfile();
      } catch (e) {
        if (kDebugMode) {
          debugPrint(
            ('PrivacySettings: Failed to fetch backend profile: $e').toString(),
          );
        }
      }
      final bool? isPrivateBackend = (profile != null)
          ? (profile['is_private'] as bool?)
          : null;

      setState(() {
        _isPrivateAccount = isPrivateBackend ?? isPrivatePref;
        _allowTagging = allowTagging;
        _allowMentions = allowMentions;
        _showOnlineStatus = showOnline;
        _allowMessageRequests = allowMsgReq;
        _showReadReceipts = readReceipts;
        _allowStoryReplies = storyReplies;
        _shareDataForAds = shareAds;
        _allowAnalytics = analytics;
        _isLoading = false;
      });

      // Keep local preference in sync with backend if available
      if (isPrivateBackend != null) {
        await _preferencesService.setPrivateAccount(isPrivateBackend);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint(('PrivacySettings: Error loading settings: $e').toString());
      }
      // On failure, fall back to local-only values
      final isPrivate = await _preferencesService.getPrivateAccount();
      final allowTagging = await _preferencesService.getAllowTagging();
      final allowMentions = await _preferencesService.getAllowMentions();
      final showOnline = await _preferencesService.getShowOnlineStatus();
      final allowMsgReq = await _preferencesService.getAllowMessageRequests();
      final readReceipts = await _preferencesService.getShowReadReceipts();
      final storyReplies = await _preferencesService.getAllowStoryReplies();
      final shareAds = await _preferencesService.getShareDataForAds();
      final analytics = await _preferencesService.getAllowAnalytics();

      if (!mounted) return;
      setState(() {
        _isPrivateAccount = isPrivate;
        _allowTagging = allowTagging;
        _allowMentions = allowMentions;
        _showOnlineStatus = showOnline;
        _allowMessageRequests = allowMsgReq;
        _showReadReceipts = readReceipts;
        _allowStoryReplies = storyReplies;
        _shareDataForAds = shareAds;
        _allowAnalytics = analytics;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Privacy & Security',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : SingleChildScrollView(
              child: Column(
                children: [
                  // Account Privacy Section
                  _buildSection(
                    title: 'Account Privacy',
                    children: [
                      _buildSwitchTile(
                        icon: Icons.lock_outline,
                        title: 'Private Account',
                        subtitle: 'Only approved trackers can see your posts',
                        value: _isPrivateAccount,
                        onChanged: (value) async {
                          final messenger = ScaffoldMessenger.of(context);
                          final previous = _isPrivateAccount;
                          setState(() {
                            _isPrivateAccount = value;
                          });
                          HapticFeedback.lightImpact();
                          try {
                            await _authService.updateProfile(isPrivate: value);
                            await _preferencesService.setPrivateAccount(value);
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                  _isPrivateAccount
                                      ? 'Your account is now private'
                                      : 'Your account is now public',
                                  style: const TextStyle(color: Colors.white),
                                ),
                                backgroundColor: AppColors.success,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          } catch (e) {
                            if (kDebugMode) {
                              debugPrint(
                                ('PrivacySettings: Failed to update account privacy: $e')
                                    .toString(),
                              );
                            }
                            // Revert UI and local preference on failure
                            if (!mounted) return;
                            setState(() {
                              _isPrivateAccount = previous;
                            });
                            await _preferencesService.setPrivateAccount(
                              previous,
                            );
                            messenger.showSnackBar(
                              SnackBar(
                                content: const LocalizedText(
                                  'failed_update_account_privacy',
                                ),
                                backgroundColor: AppColors.error,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        },
                      ),
                      _buildSwitchTile(
                        icon: Icons.alternate_email,
                        title: 'Allow Tagging',
                        subtitle: 'Let others tag you in their posts',
                        value: _allowTagging,
                        onChanged: (value) {
                          setState(() {
                            _allowTagging = value;
                          });
                          _preferencesService.setAllowTagging(value);
                          HapticFeedback.lightImpact();
                        },
                      ),
                      _buildSwitchTile(
                        icon: Icons.campaign_outlined,
                        title: 'Allow Mentions',
                        subtitle: 'Let others mention you in comments',
                        value: _allowMentions,
                        onChanged: (value) {
                          setState(() {
                            _allowMentions = value;
                          });
                          _preferencesService.setAllowMentions(value);
                          HapticFeedback.lightImpact();
                        },
                      ),
                    ],
                  ),

                  // Activity Status Section
                  _buildSection(
                    title: 'Activity Status',
                    children: [
                      _buildSwitchTile(
                        icon: Icons.circle,
                        title: 'Show Online Status',
                        subtitle: 'Let others see when you\'re active',
                        value: _showOnlineStatus,
                        onChanged: (value) {
                          setState(() {
                            _showOnlineStatus = value;
                          });
                          _preferencesService.setShowOnlineStatus(value);
                          HapticFeedback.lightImpact();
                          // Inline tip & snackbar confirmation
                          final tip = value
                              ? 'You will appear Active now in chats and as a viewer in live streams.'
                              : 'You\'ll no longer appear Active now in chats or as a viewer in live streams.';
                          // Show a subtle inline notification using SnackBar for consistency
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                tip,
                                style: const TextStyle(color: Colors.white),
                              ),
                              backgroundColor: value
                                  ? AppColors.success
                                  : AppColors.surface,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 72.0,
                          vertical: 4.0,
                        ),
                        child: Text(
                          _showOnlineStatus
                              ? 'Enabled: Others can see you\'re active in chats and streams.'
                              : 'Disabled: Your presence won\'t be broadcast in chats or streams.',
                          style: TextStyle(
                            fontSize: 12,
                            color: _showOnlineStatus
                                ? AppColors.textSecondary
                                : AppColors.textSecondary.withValues(
                                    alpha: 0.8,
                                  ),
                          ),
                        ),
                      ),
                      _buildSwitchTile(
                        icon: Icons.done_all,
                        title: 'Read Receipts',
                        subtitle: 'Show when you\'ve read messages',
                        value: _showReadReceipts,
                        onChanged: (value) {
                          setState(() {
                            _showReadReceipts = value;
                          });
                          _preferencesService.setShowReadReceipts(value);
                          HapticFeedback.lightImpact();
                          final tip = value
                              ? 'Senders will see when you\'ve read their messages.'
                              : 'Senders won\'t see read confirmations for new messages.';
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  tip,
                                  style: const TextStyle(color: Colors.white),
                                ),
                                backgroundColor: value
                                    ? AppColors.success
                                    : AppColors.surface,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        },
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 72.0,
                          vertical: 4.0,
                        ),
                        child: Text(
                          _showReadReceipts
                              ? 'Enabled: Your read status will be updated when viewing conversations.'
                              : 'Disabled: New messages won\'t be marked as read automatically.',
                          style: TextStyle(
                            fontSize: 12,
                            color: _showReadReceipts
                                ? AppColors.textSecondary
                                : AppColors.textSecondary.withValues(
                                    alpha: 0.8,
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  // Messages Section
                  _buildSection(
                    title: 'Messages',
                    children: [
                      _buildSwitchTile(
                        icon: Icons.message_outlined,
                        title: 'Message Requests',
                        subtitle: 'Allow messages from people you don\'t track',
                        value: _allowMessageRequests,
                        onChanged: (value) {
                          setState(() {
                            _allowMessageRequests = value;
                          });
                          _preferencesService.setAllowMessageRequests(value);
                          HapticFeedback.lightImpact();
                          // Inline tip & snackbar confirmation
                          final tip = value
                              ? 'Non-tracked people can start conversations with you. New chats may appear in Requests.'
                              : 'Only people you track can start conversations with you. Others won\'t be able to message you.';
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  tip,
                                  style: const TextStyle(color: Colors.white),
                                ),
                                backgroundColor: value
                                    ? AppColors.success
                                    : AppColors.surface,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        },
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 72.0,
                          vertical: 4.0,
                        ),
                        child: Text(
                          _allowMessageRequests
                              ? 'Enabled: People you don\'t track can message you and may appear in Requests.'
                              : 'Disabled: Only people you track can message you.',
                          style: TextStyle(
                            fontSize: 12,
                            color: _allowMessageRequests
                                ? AppColors.textSecondary
                                : AppColors.textSecondary.withValues(
                                    alpha: 0.8,
                                  ),
                          ),
                        ),
                      ),
                      _buildSwitchTile(
                        icon: Icons.reply_outlined,
                        title: 'Story Replies',
                        subtitle: 'Allow replies to your stories',
                        value: _allowStoryReplies,
                        onChanged: (value) {
                          setState(() {
                            _allowStoryReplies = value;
                          });
                          _preferencesService.setAllowStoryReplies(value);
                          HapticFeedback.lightImpact();
                          // Inline tip & snackbar confirmation
                          final tip = value
                              ? 'People will be able to reply to your stories.'
                              : 'Replies to your stories are blocked.';
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  tip,
                                  style: const TextStyle(color: Colors.white),
                                ),
                                backgroundColor: value
                                    ? AppColors.success
                                    : AppColors.surface,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        },
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 72.0,
                          vertical: 4.0,
                        ),
                        child: Text(
                          _allowStoryReplies
                              ? 'Enabled: People can send replies to your stories.'
                              : 'Disabled: Story replies are blocked.',
                          style: TextStyle(
                            fontSize: 12,
                            color: _allowStoryReplies
                                ? AppColors.textSecondary
                                : AppColors.textSecondary.withValues(
                                    alpha: 0.8,
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  // Data & Analytics Section
                  _buildSection(
                    title: 'Data & Analytics',
                    children: [
                      _buildSwitchTile(
                        icon: Icons.analytics_outlined,
                        title: 'Analytics',
                        subtitle: 'Help improve the app with usage data',
                        value: _allowAnalytics,
                        onChanged: (value) {
                          setState(() {
                            _allowAnalytics = value;
                          });
                          _preferencesService.setAllowAnalytics(value);
                          HapticFeedback.lightImpact();
                        },
                      ),
                      _buildSwitchTile(
                        icon: Icons.ads_click_outlined,
                        title: 'Personalized Ads',
                        subtitle: 'Use your data to show relevant ads',
                        value: _shareDataForAds,
                        onChanged: (value) {
                          setState(() {
                            _shareDataForAds = value;
                          });
                          _preferencesService.setShareDataForAds(value);
                          HapticFeedback.lightImpact();
                        },
                      ),
                    ],
                  ),

                  // Security Actions Section
                  _buildSection(
                    title: 'Security Actions',
                    children: [
                      _buildSettingsTile(
                        icon: Icons.security,
                        title: 'Two-Factor Authentication',
                        subtitle: 'Add an extra layer of security',
                        onTap: () {
                          _showTwoFactorDialog();
                        },
                      ),
                      _buildSettingsTile(
                        icon: Icons.devices,
                        title: 'Active Sessions',
                        subtitle: 'Manage your logged-in devices',
                        onTap: () {
                          _showActiveSessionsDialog();
                        },
                      ),
                      _buildSettingsTile(
                        icon: Icons.download_outlined,
                        title: 'Download Your Data',
                        subtitle: 'Get a copy of your account data',
                        onTap: () {
                          _showDownloadDataDialog();
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),
                ],
              ),
            ),
    );
  }

  Widget _buildSection({
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: AppColors.primary, size: 20),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimary,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
      ),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeColor: AppColors.primary,
      ),
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: AppColors.primary, size: 20),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimary,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
      ),
      trailing: Icon(Icons.chevron_right, color: AppColors.textSecondary),
      onTap: onTap,
    );
  }

  Future<void> _showTwoFactorDialog() async {
    final enabled = await _preferencesService.getTwoFactorEnabled();
    final recoveryCode = await _preferencesService.getTwoFactorRecoveryCode();
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) {
        bool localEnabled = enabled;
        String? localCode = recoveryCode;
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              backgroundColor: AppColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Text(
                'Two-Factor Authentication',
                style: TextStyle(color: AppColors.textPrimary),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    value: localEnabled,
                    onChanged: (v) async {
                      setLocalState(() => localEnabled = v);
                      await _preferencesService.setTwoFactorEnabled(v);
                      if (v && (localCode == null || localCode!.isEmpty)) {
                        // Generate a simple recovery code
                        final code = _generateRecoveryCode();
                        await _preferencesService.setTwoFactorRecoveryCode(
                          code,
                        );
                        setLocalState(() => localCode = code);
                      }
                    },
                    activeColor: AppColors.primary,
                    title: const Text(
                      'Enable Two-Factor Authentication',
                      style: TextStyle(color: AppColors.textPrimary),
                    ),
                    subtitle: const Text(
                      'Adds an extra layer of security to sign in.',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                  if (localEnabled && localCode != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.key, color: AppColors.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Recovery code: $localCode',
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Close',
                    style: TextStyle(color: AppColors.primary),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showActiveSessionsDialog() async {
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            LocalizationService.t('active_sessions'),
            style: const TextStyle(color: AppColors.textPrimary),
          ),
          content: Text(
            LocalizationService.t('sign_out_all_devices_desc'),
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                LocalizationService.t('close'),
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                try {
                  await AppService().signOut();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: LocalizedText(
                        LocalizationService.t('signed_out'),
                      ),
                    ),
                  );
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        LocalizationService.t('failed_to_sign_out'),
                      ),
                    ),
                  );
                }
              },
              child: Text(
                LocalizationService.t('sign_out'),
                style: const TextStyle(color: AppColors.error),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showDownloadDataDialog() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final auth = AuthService();
    final userId = auth.currentUser?.id;
    if (userId == null) {
      messenger.showSnackBar(
        SnackBar(content: LocalizedText('Please sign in to export data.')),
      );
      return;
    }

    // Collect user data
    final profile = await auth.getUserProfile();
    final posts = await PostsService().getUserPosts(userId: userId, limit: 100);
    final trackers = await DatabaseService().getTrackers(userId);

    final export = {
      'profile': profile,
      'posts': posts.map((p) => p.toJson()).toList(),
      'trackers': trackers,
      'exported_at': DateTime.now().toIso8601String(),
    };

    final jsonStr = const JsonEncoder.withIndent('  ').convert(export);

    if (kIsWeb) {
      await downloadJson(jsonStr, 'equal_export_$userId.json');
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: LocalizedText('Export started: JSON download generated.'),
        ),
      );
    } else {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            'Download Your Data',
            style: TextStyle(color: AppColors.textPrimary),
          ),
          content: const Text(
            'Export is supported on web in this build. Please use the web app to download your data.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => navigator.pop(),
              child: Text('Close', style: TextStyle(color: AppColors.primary)),
            ),
          ],
        ),
      );
    }
  }

  String _generateRecoveryCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rand = Random.secure();
    return List.generate(16, (_) => chars[rand.nextInt(chars.length)]).join();
  }
}
