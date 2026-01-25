import 'package:flutter/material.dart';
import '../../config/app_colors.dart';
import '../../services/localization_service.dart';

class ChildSafetyStandardsScreen extends StatelessWidget {
  const ChildSafetyStandardsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        title: Text(LocalizationService.t('child_safety_standards')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          LocalizedText(
            'child_safety_standards',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(height: 8),
          AutoTranslatedText(
            'Equal Systems Studio (Equal) maintains published standards that explicitly prohibit Child Sexual Abuse and Exploitation (CSAE). These standards apply across the Equal app and related services.',
            style: TextStyle(
              fontSize: 14,
              height: 1.6,
              color: AppColors.textSecondary,
            ),
          ),
          SizedBox(height: 16),

          AutoTranslatedText(
            '1. Explicit Prohibition of CSAE',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(height: 8),
          AutoTranslatedText(
            'Equal strictly prohibits any content or behavior that involves child sexual abuse or exploitation, including CSAM, grooming, solicitation, or any facilitation of harm to minors. Violations may lead to immediate account suspension or termination and reporting to relevant authorities.',
            style: TextStyle(
              fontSize: 14,
              height: 1.6,
              color: AppColors.textSecondary,
            ),
          ),
          SizedBox(height: 16),

          AutoTranslatedText(
            '2. Reporting and Moderation',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(height: 8),
          AutoTranslatedText(
            'We provide in-app feedback via Settings → Send Feedback for reporting concerns, including potential CSAE. We prioritize child safety reports and may restrict content or accounts while we review.',
            style: TextStyle(
              fontSize: 14,
              height: 1.6,
              color: AppColors.textSecondary,
            ),
          ),
          SizedBox(height: 16),

          AutoTranslatedText(
            '3. Child Safety Point of Contact',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(height: 8),
          AutoTranslatedText(
            'For urgent child safety issues, contact us at support@equal-co.com. Include “Child Safety” in the subject line and provide relevant details. We will treat these reports with priority.',
            style: TextStyle(
              fontSize: 14,
              height: 1.6,
              color: AppColors.textSecondary,
            ),
          ),
          SizedBox(height: 16),

          AutoTranslatedText(
            '4. Addressing CSAM and Escalation',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(height: 8),
          AutoTranslatedText(
            'If we detect or receive reports of Child Sexual Abuse Material (CSAM), we will promptly remove the content, restrict involved accounts, and escalate to relevant authorities or trusted organizations where applicable. We keep detailed records of such actions and may preserve evidence as required by law.',
            style: TextStyle(
              fontSize: 14,
              height: 1.6,
              color: AppColors.textSecondary,
            ),
          ),
          SizedBox(height: 16),

          AutoTranslatedText(
            '5. Compliance with Laws',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(height: 8),
          AutoTranslatedText(
            'Equal complies with applicable child safety laws and regulations and will cooperate with law enforcement where required. We may update these standards periodically.',
            style: TextStyle(
              fontSize: 14,
              height: 1.6,
              color: AppColors.textSecondary,
            ),
          ),
          SizedBox(height: 16),

          AutoTranslatedText(
            '6. Last Updated',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(height: 8),
          AutoTranslatedText(
            'Last updated: 2025-01-05',
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