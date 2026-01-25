import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import '../../services/auth_service.dart';
import '../../services/preferences_service.dart';
import '../../services/push_notification_service.dart';
import '../../services/localization_service.dart';
import '../../services/analytics_service.dart';
import '../../services/ai_service.dart';
import '../../config/app_colors.dart';
import '../../config/feature_flags.dart';
import '../auth/login_screen.dart';
import 'blocked_users_screen.dart';
import 'privacy_settings_screen.dart';
import 'storage_management_screen.dart';
import '../debug_auth_screen.dart';
import 'edit_profile_screen.dart';
import '../../services/app_service.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../widgets/referral_dashboard_card.dart';
import '../legal/terms_of_service_screen.dart' as TermsScreen;
import '../legal/privacy_policy_screen.dart' as PrivacyScreen;
import '../legal/child_safety_standards_screen.dart';
import '../../services/location_service.dart';
import '../settings/safe_mode_screen.dart';
import 'package:url_launcher/url_launcher.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _authService = AuthService();
  final _preferencesService = PreferencesService();
  // ignore: unused_field
  final _analyticsService = AnalyticsService();
  final _aiService = AIService();
  final LocationService _locationService = LocationService();

  bool _notificationsEnabled = true;
  bool _darkModeEnabled = false;
  bool _autoPlayVideos = true;
  bool _saveToGallery = false;
  bool _highQualityUploads = true;
  bool _autoTranslateEnabled = LocalizationService.autoTranslateEnabled;
  String _selectedLanguage = 'English';
  bool _isLoading = true;
  // Runtime feature flags to control visibility without triggering dead_code
  final bool _enableAiConfigurationSection = false;
  final bool _enableContentSection = false;
  bool _locationConsentEnabled = false;
  String? _storedCountry;
  String? _storedCity;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    try {
      final notifications = await _preferencesService.getNotificationsEnabled();
      final darkMode = await _preferencesService.getDarkModeEnabled();
      final autoPlay = await _preferencesService.getAutoPlayVideos();
      final saveToGallery = await _preferencesService.getSaveToGallery();
      final highQuality = await _preferencesService.getHighQualityUploads();
      final language = await _preferencesService.getSelectedLanguage();
      final consent = await _locationService.getConsentChoice();
      final country = await _locationService.getStoredCountry();
      final city = await _locationService.getStoredCity();

      if (mounted) {
        setState(() {
          _notificationsEnabled = notifications;
          _darkModeEnabled = darkMode;
          _autoPlayVideos = autoPlay;
          _saveToGallery = saveToGallery;
          _highQualityUploads = highQuality;
          _selectedLanguage = language;
          _isLoading = false;
          _locationConsentEnabled = consent == true;
          _storedCountry = country;
          _storedCity = city;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
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
        title: Text(
          LocalizationService.t('settings'),
          style: const TextStyle(
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
                  // Account Section
                  _buildSection(
                    title: LocalizationService.t('account'),
                    children: [
                      _buildSettingsTile(
                        icon: Icons.person_outline,
                        title: LocalizationService.t('edit_profile'),
                        subtitle: LocalizationService.t(
                          'update_profile_information',
                        ),
                        onTap: () {
                          // Navigate to edit profile
                          if (!_authService.isAuthenticated) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const LoginScreen(),
                              ),
                            );
                            return;
                          }

                          // Fetch current user profile, then open EditProfileScreen
                          _authService.getCurrentUserProfile().then((profile) {
                            if (!context.mounted) return;
                            if (profile == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: const Text(
                                    'Unable to load profile. Please try again.',
                                  ),
                                  backgroundColor: AppColors.error,
                                ),
                              );
                              return;
                            }

                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    EditProfileScreen(userProfile: profile),
                              ),
                            );
                          });
                        },
                      ),
                      _buildSettingsTile(
                        icon: Icons.security,
                        title: LocalizationService.t('privacy_security'),
                        subtitle: LocalizationService.t(
                          'manage_privacy_settings',
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  const PrivacySettingsScreen(),
                            ),
                          );
                        },
                      ),
                      _buildSettingsTile(
                        icon: Icons.block,
                        title: LocalizationService.t('blocked_users'),
                        subtitle: LocalizationService.t(
                          'manage_blocked_accounts',
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const BlockedUsersScreen(),
                            ),
                          );
                        },
                      ),
                    ],
                  ),

                  // Preferences Section
                  _buildSection(
                    title: LocalizationService.t('preferences'),
                    children: [
                      _buildSwitchTile(
                        icon: Icons.notifications_outlined,
                        title: LocalizationService.t('push_notifications'),
                        subtitle: LocalizationService.t(
                          'receive_notifications_for_likes_comments_follows',
                        ),
                        value: _notificationsEnabled,
                        onChanged: (value) async {
                          // Guard unsupported platforms
                          if (kIsWeb) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  LocalizationService.t(
                                    'push_notifications_not_supported_web',
                                  ),
                                ),
                                backgroundColor: AppColors.error,
                              ),
                            );
                            if (mounted) {
                              setState(() {
                                _notificationsEnabled = false;
                              });
                            }
                            await _preferencesService.setNotificationsEnabled(
                              false,
                            );
                            HapticFeedback.lightImpact();
                            return;
                          }

                          if (mounted) {
                            setState(() {
                              _notificationsEnabled = value;
                            });
                          }
                          // Persist and wire into service
                          await PushNotificationService()
                              .setNotificationsEnabled(value);
                          await _preferencesService.setNotificationsEnabled(
                            value,
                          );
                          HapticFeedback.lightImpact();
                        },
                      ),
                      // Keep import but SafeMode hidden with feature flag; no UI reference remains when false.
                      if (FeatureFlags.showSafeModeToggle)
                        _buildSettingsTile(
                          icon: Icons.shield_outlined,
                          title: LocalizationService.t('safe_mode'),
                          subtitle: LocalizationService.t(
                            'hide_sensitive_content_with_blur',
                          ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const SafeModeScreen(),
                              ),
                            );
                          },
                        ),
                      if (FeatureFlags.showDarkModeToggle)
                        _buildSwitchTile(
                          icon: Icons.dark_mode_outlined,
                          title: LocalizationService.t('dark_mode'),
                          subtitle: LocalizationService.t(
                            'switch_to_dark_theme',
                          ),
                          value: _darkModeEnabled,
                          onChanged: (value) async {
                            if (mounted) {
                              setState(() {
                                _darkModeEnabled = value;
                              });
                            }
                            await _preferencesService.setDarkModeEnabled(value);
                            HapticFeedback.lightImpact();
                          },
                        ),
                      _buildSwitchTile(
                        icon: Icons.play_circle_outline,
                        title: LocalizationService.t('autoplay_videos'),
                        subtitle: LocalizationService.t(
                          'autoplay_videos_subtitle',
                        ),
                        value: _autoPlayVideos,
                        onChanged: (value) async {
                          if (mounted) {
                            setState(() {
                              _autoPlayVideos = value;
                            });
                          }
                          await _preferencesService.setAutoPlayVideos(value);
                          HapticFeedback.lightImpact();
                        },
                      ),
                      _buildSwitchTile(
                        icon: Icons.save_alt,
                        title: LocalizationService.t('save_to_gallery'),
                        subtitle: LocalizationService.t(
                          'save_to_gallery_subtitle',
                        ),
                        value: _saveToGallery,
                        onChanged: (value) async {
                          // Web: allow toggle to enable browser download
                          if (mounted) {
                            setState(() {
                              _saveToGallery = value;
                            });
                          }
                          await _preferencesService.setSaveToGallery(value);
                          HapticFeedback.lightImpact();
                        },
                      ),
                      _buildSwitchTile(
                        icon: Icons.high_quality,
                        title: LocalizationService.t('high_quality_uploads'),
                        subtitle: LocalizationService.t(
                          'high_quality_uploads_subtitle',
                        ),
                        value: _highQualityUploads,
                        onChanged: (value) async {
                          if (mounted) {
                            setState(() {
                              _highQualityUploads = value;
                            });
                          }
                          await _preferencesService.setHighQualityUploads(
                            value,
                          );
                          HapticFeedback.lightImpact();
                        },
                      ),
                      _buildSettingsTile(
                        icon: Icons.history,
                        title: LocalizationService.t('history'),
                        subtitle: LocalizationService.t('recently_viewed'),
                        onTap: () {
                          Navigator.pushNamed(context, '/history');
                        },
                      ),
                      _buildSwitchTile(
                        icon: Icons.location_on_outlined,
                        title: LocalizationService.t('location_consent'),
                        subtitle: LocalizationService.t(
                          'allow_location_based_feed',
                        ),
                        value: _locationConsentEnabled,
                        onChanged: (value) async {
                          if (mounted) {
                            setState(() {
                              _locationConsentEnabled = value;
                            });
                          }
                          await _locationService.setConsentChoice(value);
                          HapticFeedback.lightImpact();
                          if (value) {
                            final ok = await _locationService
                                .updateUserProfileLocation();
                            if (ok && mounted) {
                              final country = await _locationService
                                  .getStoredCountry();
                              final city = await _locationService
                                  .getStoredCity();
                              setState(() {
                                _storedCountry = country;
                                _storedCity = city;
                              });
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    LocalizationService.t(
                                      'location_updated_local_feed_enabled',
                                    ),
                                  ),
                                ),
                              );
                            }
                          }
                        },
                      ),
                      _buildSettingsTile(
                        icon: Icons.public,
                        title: LocalizationService.t('choose_country_city'),
                        subtitle:
                            ((_storedCountry ?? '').isNotEmpty ||
                                (_storedCity ?? '').isNotEmpty)
                            ? [
                                if ((_storedCountry ?? '').isNotEmpty)
                                  _storedCountry!,
                                if ((_storedCity ?? '').isNotEmpty)
                                  _storedCity!,
                              ].join(' • ')
                            : LocalizationService.t('not_set'),
                        onTap: _showManualLocationDialog,
                      ),
                      _buildSettingsTile(
                        icon: Icons.language,
                        title: LocalizationService.t('language'),
                        subtitle: _selectedLanguage,
                        onTap: () {
                          _showLanguageSelector();
                        },
                      ),
                    ],
                  ),

                  // Referral Program Section
                  _buildSection(
                    title: LocalizationService.t('referral_program'),
                    children: [
                      const Padding(
                        padding: EdgeInsets.all(12.0),
                        child: ReferralDashboardCard(),
                      ),
                      _buildSettingsTile(
                        icon: Icons.ios_share,
                        title:
                            '${LocalizationService.t('share')} ${LocalizationService.t('app_name')}',
                        subtitle: LocalizationService.t('invite_friends'),
                        onTap: _shareApp,
                      ),
                    ],
                  ),

                  // AI Configuration Section
                  if (_enableAiConfigurationSection == true)
                    _buildSection(
                      title: LocalizationService.t('ai_configuration'),
                      children: [
                        _buildSettingsTile(
                          icon: Icons.smart_toy,
                          title: LocalizationService.t('qwen_api_key'),
                          subtitle: LocalizationService.t(
                            'configure_qwen_api_key',
                          ),
                          onTap: () {
                            _showApiKeyDialog();
                          },
                        ),
                        _buildSettingsTile(
                          icon: Icons.tune,
                          title: LocalizationService.t('ai_preferences'),
                          subtitle: LocalizationService.t(
                            'customize_ai_generation_settings',
                          ),
                          onTap: () {
                            _showAiPreferencesDialog();
                          },
                        ),
                      ],
                    ),

                  // Content Section
                  if (_enableContentSection == true)
                    _buildSection(
                      title: LocalizationService.t('content'),
                      children: [
                        _buildSettingsTile(
                          icon: Icons.download,
                          title: LocalizationService.t('downloads'),
                          subtitle: LocalizationService.t(
                            'manage_downloaded_content',
                          ),
                          onTap: () {
                            // Navigate to downloads
                          },
                        ),
                        _buildSettingsTile(
                          icon: Icons.storage,
                          title: LocalizationService.t('storage_and_data'),
                          subtitle: LocalizationService.t(
                            'manage_app_storage_and_data_usage',
                          ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    const StorageManagementScreen(),
                              ),
                            );
                          },
                        ),
                        _buildSettingsTile(
                          icon: Icons.clear_all,
                          title: LocalizationService.t('clear_cache'),
                          subtitle: LocalizationService.t(
                            'free_up_storage_space',
                          ),
                          onTap: () {
                            _showClearCacheDialog();
                          },
                        ),
                      ],
                    ),

                  // Support Section
                  _buildSection(
                    title: LocalizationService.t('support'),
                    children: [
                      _buildSettingsTile(
                        icon: Icons.help_outline,
                        title: LocalizationService.t('help_center'),
                        subtitle: LocalizationService.t('get_help_support'),
                        onTap: () {
                          // Navigate to help center
                        },
                      ),
                      _buildSettingsTile(
                        icon: Icons.feedback_outlined,
                        title: LocalizationService.t('send_feedback'),
                        subtitle: LocalizationService.t('help_improve_app'),
                        onTap: () {
                          _showFeedbackDialog();
                        },
                      ),
                      _buildSettingsTile(
                        icon: Icons.info_outline,
                        title: LocalizationService.t('about'),
                        subtitle: LocalizationService.t('app_version_info'),
                        onTap: () {
                          _showAboutDialog();
                        },
                      ),
                      if (kDebugMode && false)
                        _buildSettingsTile(
                          icon: Icons.bug_report,
                          title: LocalizationService.t('debug_authentication'),
                          subtitle: LocalizationService.t(
                            'debug_supabase_auth_issues',
                          ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const DebugAuthScreen(),
                              ),
                            );
                          },
                        ),
                    ],
                  ),

                  // Legal Section
                  _buildSection(
                    title: LocalizationService.t('legal'),
                    children: [
                      _buildSettingsTile(
                        icon: Icons.description_outlined,
                        title: LocalizationService.t('terms_of_service'),
                        subtitle: LocalizationService.t(
                          'terms_of_service_subtitle',
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  const TermsScreen.TermsOfServiceScreen(),
                            ),
                          );
                        },
                      ),
                      _buildSettingsTile(
                        icon: Icons.privacy_tip_outlined,
                        title: LocalizationService.t('privacy_policy'),
                        subtitle: LocalizationService.t(
                          'privacy_policy_subtitle',
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  const PrivacyScreen.PrivacyPolicyScreen(),
                            ),
                          );
                        },
                      ),
                      _buildSettingsTile(
                        icon: Icons.child_care_outlined,
                        title: LocalizationService.t('child_safety_standards'),
                        subtitle: LocalizationService.t(
                          'child_safety_standards_subtitle',
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  const ChildSafetyStandardsScreen(),
                            ),
                          );
                        },
                      ),
                    ],
                  ),

                  // Danger Zone
                  _buildSection(
                    title: LocalizationService.t('account_actions'),
                    children: [
                      _buildSettingsTile(
                        icon: Icons.logout,
                        title: LocalizationService.t('sign_out'),
                        subtitle: LocalizationService.t('sign_out_subtitle'),
                        onTap: () {
                          _showSignOutDialog();
                        },
                        isDestructive: true,
                      ),
                      _buildSettingsTile(
                        icon: Icons.delete_forever,
                        title: LocalizationService.t('delete_account'),
                        subtitle: LocalizationService.t(
                          'delete_account_subtitle',
                        ),
                        onTap: () {
                          _showDeleteAccountDialog();
                        },
                        isDestructive: true,
                      ),
                    ],
                  ),

                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }

  void _showManualLocationDialog() {
    final countryController = TextEditingController(text: _storedCountry);
    final cityController = TextEditingController(text: _storedCity);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          LocalizationService.t('choose_country_city'),
          style: const TextStyle(color: AppColors.textPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: countryController,
              decoration: InputDecoration(
                labelText: LocalizationService.t('country'),
                labelStyle: TextStyle(color: AppColors.textSecondary),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.primary),
                ),
              ),
              style: const TextStyle(color: AppColors.textPrimary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: cityController,
              decoration: InputDecoration(
                labelText: LocalizationService.t('city'),
                labelStyle: TextStyle(color: AppColors.textSecondary),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.primary),
                ),
              ),
              style: const TextStyle(color: AppColors.textPrimary),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              LocalizationService.t('cancel'),
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () async {
              final country = countryController.text.trim();
              final city = cityController.text.trim();
              if (country.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      LocalizationService.t('country') +
                          ' ' +
                          LocalizationService.t('not_set'),
                    ),
                    backgroundColor: AppColors.error,
                  ),
                );
                return;
              }
              final ok = await _locationService.setManualLocation(
                country: country,
                city: city.isEmpty ? null : city,
              );
              if (!context.mounted) return;
              Navigator.pop(context);
              if (ok) {
                setState(() {
                  _storedCountry = country;
                  _storedCity = city.isEmpty ? null : city;
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      LocalizationService.t(
                        'location_updated_local_feed_enabled',
                      ),
                    ),
                    backgroundColor: AppColors.success,
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      LocalizationService.t('unable_to_load_profile'),
                    ),
                    backgroundColor: AppColors.error,
                  ),
                );
              }
              HapticFeedback.lightImpact();
            },
            child: Text(
              LocalizationService.t('save'),
              style: const TextStyle(color: AppColors.primary),
            ),
          ),
        ],
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
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
              letterSpacing: 0.5,
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border, width: 1),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: isDestructive
              ? AppColors.error.withValues(alpha: 0.1)
              : AppColors.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          icon,
          color: isDestructive ? AppColors.error : AppColors.primary,
          size: 20,
        ),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: isDestructive ? AppColors.error : AppColors.textPrimary,
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

  void _showLanguageSelector() {
    final languages = [
      'English',
      'Spanish',
      'French',
      'German',
      'Chinese',
      'Japanese',
      'Arabic',
      'Italian',
      'Portuguese',
      'Russian',
      'Korean',
      'Hindi',
      'Turkish',
      'Dutch',
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              LocalizationService.t('choose_language'),
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 300,
              child: ListView.builder(
                itemCount: languages.length,
                itemBuilder: (context, index) {
                  final language = languages[index];
                  final isSelected = language == _selectedLanguage;

                  return ListTile(
                    title: Text(
                      language,
                      style: TextStyle(
                        color: isSelected
                            ? AppColors.primary
                            : AppColors.textPrimary,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                    trailing: isSelected
                        ? Icon(Icons.check, color: AppColors.primary)
                        : null,
                    onTap: () async {
                      if (mounted) {
                        setState(() {
                          _selectedLanguage = language;
                        });
                      }
                      await _preferencesService.setSelectedLanguage(language);

                      // Map UI language name to language code
                      final Map<String, String> codeMap = {
                        'English': 'en',
                        'Spanish': 'es',
                        'French': 'fr',
                        'German': 'de',
                        'Chinese': 'zh',
                        'Japanese': 'ja',
                        'Arabic': 'ar',
                        'Italian': 'it',
                        'Portuguese': 'pt',
                        'Russian': 'ru',
                        'Korean': 'ko',
                        'Hindi': 'hi',
                        'Turkish': 'tr',
                        'Dutch': 'nl',
                      };
                      final code = codeMap[language];
                      if (code != null) {
                        await LocalizationService.setLanguage(code);
                        if (!context.mounted) return;
                      } else {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              LocalizationService.t('language_not_supported'),
                            ),
                            backgroundColor: AppColors.error,
                          ),
                        );
                      }
                      if (!context.mounted) return;
                      Navigator.pop(context);
                      HapticFeedback.lightImpact();
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showClearCacheDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          LocalizationService.t('clear_cache'),
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: Text(
          LocalizationService.t('clear_cache_desc'),
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              LocalizationService.t('cancel'),
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              HapticFeedback.lightImpact();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    LocalizationService.t('cache_cleared_successfully'),
                  ),
                  backgroundColor: AppColors.success,
                ),
              );
            },
            child: Text(
              LocalizationService.t('clear'),
              style: TextStyle(color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }

  void _showFeedbackDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          LocalizationService.t('send_feedback'),
          style: const TextStyle(color: AppColors.textPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              maxLines: 4,
              decoration: InputDecoration(
                hintText: LocalizationService.t('tell_us_what_you_think'),
                hintStyle: TextStyle(color: AppColors.textSecondary),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.primary),
                ),
              ),
              style: const TextStyle(color: AppColors.textPrimary),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              LocalizationService.t('cancel'),
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              HapticFeedback.lightImpact();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    LocalizationService.t('feedback_sent_thank_you'),
                  ),
                  backgroundColor: AppColors.success,
                ),
              );
            },
            child: Text(
              LocalizationService.t('send'),
              style: const TextStyle(color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }

  void _showApiKeyDialog() {
    final TextEditingController apiKeyController = TextEditingController();
    bool isObscured = true;

    // Load current API key
    _aiService.getApiKey().then((currentKey) {
      if (currentKey.isNotEmpty) {
        apiKeyController.text = currentKey;
      }
    });

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            LocalizationService.t('qwen_api_key'),
            style: const TextStyle(color: AppColors.textPrimary),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                LocalizationService.t('enter_qwen_api_key'),
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: apiKeyController,
                obscureText: isObscured,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: LocalizationService.t('api_key_hint'),
                  hintStyle: TextStyle(color: AppColors.textSecondary),
                  filled: true,
                  fillColor: AppColors.background,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: AppColors.textSecondary.withValues(alpha: 0.3),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: AppColors.textSecondary.withValues(alpha: 0.3),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.primary),
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      isObscured ? Icons.visibility : Icons.visibility_off,
                      color: AppColors.textSecondary,
                    ),
                    onPressed: () {
                      setState(() {
                        isObscured = !isObscured;
                      });
                    },
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                LocalizationService.t('get_api_key_from_console'),
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                LocalizationService.t('cancel'),
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
            TextButton(
              onPressed: () async {
                final apiKey = apiKeyController.text.trim();
                if (apiKey.isNotEmpty) {
                  // Validate API key
                  final isValid = _aiService.validateApiKey(apiKey);
                  if (!isValid) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          LocalizationService.t('invalid_api_key_format'),
                        ),
                        backgroundColor: AppColors.error,
                      ),
                    );
                    return;
                  }

                  try {
                    await _aiService.setApiKey(apiKey);
                    if (!context.mounted) return;
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          LocalizationService.t('api_key_saved_successfully'),
                        ),
                      ),
                    );
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          '${LocalizationService.t('error_saving_api_key')}: $e',
                        ),
                        backgroundColor: AppColors.error,
                      ),
                    );
                  }
                } else {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        LocalizationService.t('please_enter_valid_api_key'),
                      ),
                    ),
                  );
                }
              },
              child: Text(
                LocalizationService.t('save'),
                style: const TextStyle(color: AppColors.primary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAiPreferencesDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          LocalizationService.t('ai_preferences'),
          style: const TextStyle(color: AppColors.textPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.image, color: AppColors.primary),
              title: Text(
                LocalizationService.t('default_image_size'),
                style: const TextStyle(color: AppColors.textPrimary),
              ),
              subtitle: const Text(
                '1024x1024',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              onTap: () {
                // Show size selection dialog
              },
            ),
            ListTile(
              leading: const Icon(Icons.palette, color: AppColors.primary),
              title: Text(
                LocalizationService.t('default_art_style'),
                style: const TextStyle(color: AppColors.textPrimary),
              ),
              subtitle: Text(
                LocalizationService.t('realistic'),
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              onTap: () {
                // Show style selection dialog
              },
            ),
            ListTile(
              leading: const Icon(Icons.speed, color: AppColors.primary),
              title: const Text(
                'Generation Quality',
                style: TextStyle(color: AppColors.textPrimary),
              ),
              subtitle: const Text(
                'High Quality (slower)',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              onTap: () {
                // Show quality selection dialog
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Close',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  void _showAboutDialog() {
    showAboutDialog(
      context: context,
      applicationName: LocalizationService.t('app_name'),
      applicationVersion: '1.0.0',
      applicationIcon: SvgPicture.asset(
        'assets/icons/app_icon.svg',
        width: 60,
        height: 60,
      ),
      children: [
        Text(
          LocalizationService.t('application_description'),
          style: TextStyle(color: AppColors.textSecondary),
        ),
      ],
    );
  }

  Future<void> _shareApp() async {
    try {
      final appName = LocalizationService.t('app_name');
      final message =
          'Join me on ' +
          appName +
          '! Download ' +
          appName +
          ': https://play.google.com/store/apps/details?id=com.equal.app.equal';
      await Share.share(message, subject: 'Download ' + appName);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(LocalizationService.t('failed_to_share_post')),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  void _showSignOutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          LocalizationService.t('sign_out'),
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: Text(
          LocalizationService.t('confirm_sign_out'),
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              LocalizationService.t('cancel'),
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await AppService().signOut();
                // Navigation is handled by AuthWrapper via appStateStream
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        LocalizationService.t('failed_to_sign_out'),
                      ),
                      backgroundColor: AppColors.error,
                    ),
                  );
                }
              }
            },
            child: Text(
              LocalizationService.t('sign_out'),
              style: const TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }

  void _showDeleteAccountDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          LocalizationService.t('delete_account'),
          style: TextStyle(color: AppColors.error),
        ),
        content: Text(
          LocalizationService.t('delete_account_warning'),
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              LocalizationService.t('cancel'),
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              // Show progress dialog while preparing email
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (ctx) => AlertDialog(
                  backgroundColor: AppColors.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  content: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          LocalizationService.t('deleting_account'),
                          style: TextStyle(color: AppColors.textSecondary),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              );
              try {
                await _authService
                    .deleteAccount()
                    .timeout(const Duration(seconds: 30));
                if (context.mounted) {
                  // Close progress dialog on success
                  Navigator.of(context, rootNavigator: true).pop();
                  final messenger = ScaffoldMessenger.of(context);
                  // Ensure any existing banner is hidden before showing a new one
                  messenger.hideCurrentMaterialBanner();
                  messenger.showMaterialBanner(
                    MaterialBanner(
                      backgroundColor: AppColors.success.withValues(alpha: 0.1),
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      leading: Icon(Icons.check_circle, color: AppColors.success),
                      content: Text(
                        LocalizationService.t('we_will_process_delete_request'),
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 15,
                          height: 1.4,
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () async {
                            await Clipboard.setData(
                              const ClipboardData(text: 'support@equal-co.com'),
                            );
                            final copied = LocalizationService.t('copied');
                            final messenger = ScaffoldMessenger.of(context);
                            messenger.hideCurrentSnackBar();
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(copied),
                                backgroundColor: AppColors.success,
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          },
                          child: Text(
                            LocalizationService.t('copy'),
                            style: TextStyle(color: AppColors.success),
                          ),
                        ),
                        TextButton(
                          onPressed: () async {
                            try {
                              final uri = Uri.parse('mailto:support@equal-co.com');
                              await launchUrl(uri, mode: LaunchMode.platformDefault);
                            } catch (_) {}
                          },
                          child: Text(
                            LocalizationService.t('email_support'),
                            style: TextStyle(color: AppColors.success),
                          ),
                        ),
                        TextButton(
                          onPressed: () => messenger.hideCurrentMaterialBanner(),
                          child: Text(
                            LocalizationService.t('close'),
                            style: TextStyle(color: AppColors.success),
                          ),
                        ),
                      ],
                    ),
                  );
                }
              } on TimeoutException {
                if (context.mounted) {
                  // Close progress dialog
                  Navigator.of(context, rootNavigator: true).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        LocalizationService.t('failed_to_delete_account'),
                      ),
                      backgroundColor: AppColors.error,
                    ),
                  );
                }
                return;
              } catch (e) {
                if (context.mounted) {
                  // Close progress dialog
                  Navigator.of(context, rootNavigator: true).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        LocalizationService.t('failed_to_delete_account'),
                      ),
                      backgroundColor: AppColors.error,
                    ),
                  );
                }
                return;
              }
            },
            child: Text(
              LocalizationService.t('delete'),
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }
}
