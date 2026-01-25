import 'package:flutter/material.dart';
import '../../config/app_colors.dart';
import '../../services/localization_service.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final titleStyle = TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w700,
      color: AppColors.textPrimary,
    );
    final bodyStyle = TextStyle(
      fontSize: 14,
      height: 1.6,
      color: AppColors.textSecondary,
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        title: Text(LocalizationService.t('privacy_policy')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const LocalizedText(
            'equal_privacy_policy',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const AutoTranslatedText(
            'This Privacy Policy explains how Equal collects, uses, and protects your information when you use our app and services. By using Equal, you consent to the practices described here.',
            style: TextStyle(
              fontSize: 14,
              height: 1.6,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),

          const AutoTranslatedText(
            '1. Information We Collect',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const AutoTranslatedText(
            'We collect: (a) Account information (name, username, email); (b) Content you create (posts, messages, comments); (c) Usage data (interactions, device information, logs); and (d) Optional data you provide (profile details, preferences).',
            style: TextStyle(
              fontSize: 14,
              height: 1.6,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),

          const AutoTranslatedText(
            '2. How We Use Your Information',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const AutoTranslatedText(
            'We use information to operate and improve Equal, personalize your experience, enable messaging and social features, ensure safety, and comply with legal obligations.',
            style: TextStyle(
              fontSize: 14,
              height: 1.6,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),

          const AutoTranslatedText(
            '3. Data Sharing',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const AutoTranslatedText(
            'We do not sell your personal information. We may share data with service providers (e.g., hosting, analytics, ads) under strict agreements, and when required by law. Public content you post may be visible to others.',
            style: TextStyle(
              fontSize: 14,
              height: 1.6,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),

          const AutoTranslatedText(
            '4. Messaging and Privacy',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const AutoTranslatedText(
            'Messages and interactions may be stored to provide features like unread counts and conversation history. We implement access controls (including Row Level Security) to restrict access to your conversations.',
            style: TextStyle(
              fontSize: 14,
              height: 1.6,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),

          const AutoTranslatedText(
            '5. Cookies and Similar Technologies',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const AutoTranslatedText(
            'Equal may use cookies or local storage on web to remember preferences, track engagement, and improve performance. You can control these in your browser settings.',
            style: TextStyle(
              fontSize: 14,
              height: 1.6,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),

          const AutoTranslatedText(
            '6. Data Security',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const AutoTranslatedText(
            'We use technical and organizational measures to protect your data. No system is 100% secure, but we strive to safeguard information through encryption, access controls, and best practices.',
            style: TextStyle(
              fontSize: 14,
              height: 1.6,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),

          const AutoTranslatedText(
            '7. Your Rights and Choices',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const AutoTranslatedText(
            'You may access, update, or delete your account data within the app. You can manage privacy settings, control notifications, and request a copy of your data via Settings.',
            style: TextStyle(
              fontSize: 14,
              height: 1.6,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),

          const AutoTranslatedText(
            '8. Data Retention',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const AutoTranslatedText(
            'We retain data as long as needed to provide services and meet legal requirements. You can delete your account to remove your profile and personal content from Equal.',
            style: TextStyle(
              fontSize: 14,
              height: 1.6,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),

          const AutoTranslatedText(
            '9. Children’s Privacy',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const AutoTranslatedText(
            'Equal is not directed to children under 13. If we learn that a child under 13 has provided personal information, we will take steps to delete it.',
            style: TextStyle(
              fontSize: 14,
              height: 1.6,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),

          const AutoTranslatedText(
            '10. International Data Transfers',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const AutoTranslatedText(
            'Your information may be processed in countries where our service providers operate. We implement safeguards for cross-border data transfers where required.',
            style: TextStyle(
              fontSize: 14,
              height: 1.6,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),

          const AutoTranslatedText(
            '11. Changes to This Policy',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const AutoTranslatedText(
            'We may update this Privacy Policy from time to time. We will notify users of material changes within the app. Continued use after changes means you accept the updated Policy.',
            style: TextStyle(
              fontSize: 14,
              height: 1.6,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),

          const AutoTranslatedText(
            '12. Contact Us',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const AutoTranslatedText(
            'If you have privacy questions or requests, contact us in-app via Settings → Send Feedback or at privacy@equal.app (if available).',
            style: TextStyle(
              fontSize: 14,
              height: 1.6,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 24),

          const AutoTranslatedText(
            'Last updated: 2025-01-01',
            style: TextStyle(
              fontSize: 14,
              height: 1.6,
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}
