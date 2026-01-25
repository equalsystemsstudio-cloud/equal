import 'package:flutter/material.dart';
import '../../config/app_colors.dart';
import '../../services/localization_service.dart';

class TermsOfServiceScreen extends StatelessWidget {
  const TermsOfServiceScreen({super.key});

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
        title: Text(LocalizationService.t('terms_of_service')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const LocalizedText(
            'equal_terms_of_service',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const AutoTranslatedText(
            'Welcome to Equal. These Terms of Service ("Terms") govern your access to and use of Equal, including any content, functionality, and services offered on or through the Equal app and website. By using Equal, you agree to be bound by these Terms.',
            style: TextStyle(
              fontSize: 14,
              height: 1.6,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),

          const AutoTranslatedText(
            '1. Acceptance of Terms',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const AutoTranslatedText(
            'By creating an account or using Equal, you confirm that you have read, understood, and agree to these Terms and our Privacy Policy. If you do not agree, you must not use Equal.',
            style: TextStyle(
              fontSize: 14,
              height: 1.6,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),

          const AutoTranslatedText(
            '2. Eligibility',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const AutoTranslatedText(
            'You must be at least 13 years old (or the minimum age in your jurisdiction) to use Equal. If you are under the age of majority, you must have permission from a parent or legal guardian.',
            style: TextStyle(
              fontSize: 14,
              height: 1.6,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),

          const AutoTranslatedText(
            '3. Your Account',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const AutoTranslatedText(
            'You are responsible for the activity that occurs on your account and for keeping your login credentials secure. Notify us immediately of any unauthorized use of your account.',
            style: TextStyle(
              fontSize: 14,
              height: 1.6,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),

          const AutoTranslatedText(
            '4. Acceptable Use',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const AutoTranslatedText(
            'You agree not to use Equal to: (a) post or share unlawful, harmful, hateful, or violent content; (b) harass, threaten, or impersonate others; (c) violate any applicable law; (d) engage in spam or deceptive practices; or (e) attempt to circumvent security or platform restrictions.',
            style: TextStyle(
              fontSize: 14,
              height: 1.6,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),

          const AutoTranslatedText(
            '5. Content and Licenses',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const AutoTranslatedText(
            'You retain ownership of the content you post. By posting content on Equal, you grant us a non-exclusive, worldwide, royalty-free license to host, store, transmit, display, and distribute your content for the purpose of operating, improving, and promoting Equal. You are responsible for ensuring you have all rights necessary to post your content.',
            style: TextStyle(
              fontSize: 14,
              height: 1.6,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),

          const AutoTranslatedText(
            '6. Messaging and Interactions',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const AutoTranslatedText(
            'Equal may provide messaging and social features. You agree to use these features responsibly. We may moderate content or restrict features to maintain safety, but we do not guarantee we will monitor all content.',
            style: TextStyle(
              fontSize: 14,
              height: 1.6,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),

          const AutoTranslatedText(
            '7. Privacy',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const AutoTranslatedText(
            'Your use of Equal is subject to our Privacy Policy, which explains how we collect, use, and protect your information. Please review it carefully.',
            style: TextStyle(
              fontSize: 14,
              height: 1.6,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),

          const AutoTranslatedText(
            '8. Intellectual Property',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const AutoTranslatedText(
            'Equal, including its design, trademarks, and software, is owned by us or our licensors. You may not copy, modify, or distribute any part of Equal without our permission.',
            style: TextStyle(
              fontSize: 14,
              height: 1.6,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),

          const AutoTranslatedText(
            '9. Third-Party Services',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const AutoTranslatedText(
            'Equal may integrate third-party services (e.g., storage, analytics, ads). Your use of those services is subject to their terms and policies. We are not responsible for any third-party content or services.',
            style: TextStyle(
              fontSize: 14,
              height: 1.6,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),

          const AutoTranslatedText(
            '10. Termination',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const AutoTranslatedText(
            'We may suspend or terminate your access to Equal at any time if you violate these Terms or if necessary to protect our users or platform. You may delete your account at any time via the app settings.',
            style: TextStyle(
              fontSize: 14,
              height: 1.6,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),

          const AutoTranslatedText(
            '11. Disclaimers',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const AutoTranslatedText(
            'Equal is provided "as is" and "as available" without warranties of any kind. We do not warrant that the service will be uninterrupted, secure, or error-free.',
            style: TextStyle(
              fontSize: 14,
              height: 1.6,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),

          const AutoTranslatedText(
            '12. Limitation of Liability',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const AutoTranslatedText(
            'To the maximum extent permitted by law, we shall not be liable for any indirect, incidental, special, consequential, or punitive damages arising out of or relating to your use of Equal.',
            style: TextStyle(
              fontSize: 14,
              height: 1.6,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),

          const AutoTranslatedText(
            '13. Changes to the Service and Terms',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const AutoTranslatedText(
            'We may update Equal and these Terms from time to time. Continued use after changes take effect means you accept the updated Terms. We will notify users of material changes within the app.',
            style: TextStyle(
              fontSize: 14,
              height: 1.6,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),

          const AutoTranslatedText(
            '14. Governing Law',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const AutoTranslatedText(
            'These Terms are governed by the laws of your country or region of residence, unless local law requires otherwise. Any disputes will be resolved in the courts located in that jurisdiction.',
            style: TextStyle(
              fontSize: 14,
              height: 1.6,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),

          const AutoTranslatedText(
            '15. Contact Us',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const AutoTranslatedText(
            'If you have questions about these Terms, contact us in-app via Settings → Send Feedback or at support@equal-co.com (if available).',
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
