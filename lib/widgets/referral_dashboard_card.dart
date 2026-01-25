import 'package:flutter/material.dart';
import '../services/referral_service.dart';
import '../services/localization_service.dart';
import '../config/app_colors.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

class ReferralDashboardCard extends StatefulWidget {
  const ReferralDashboardCard({super.key});

  @override
  State<ReferralDashboardCard> createState() => _ReferralDashboardCardState();
}

class _ReferralDashboardCardState extends State<ReferralDashboardCard> {
  final ReferralService _referralService = ReferralService();
  String? _code;
  Map<String, dynamic> _stats = {
    'total': 0,
    'verified': 0,
    'next_milestone_remaining': 5,
    'awarded_milestones': 0,
    'total_awarded_months': 0,
  };
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
    });
    final code = await _referralService.getReferralCode();
    final stats = await _referralService.getReferralStats();
    if (!mounted) return;
    setState(() {
      _code = code;
      _stats = stats;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      child: _loading ? _buildLoading() : _buildContent(),
    );
  }

  Widget _buildLoading() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          LocalizationService.t('referral_program'),
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        LinearProgressIndicator(
          value: null,
          color: AppColors.primary,
          backgroundColor: AppColors.surfaceVariant,
        ),
        const SizedBox(height: 8),
        Text(
          LocalizationService.t('earn_blue_tick_months'),
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
      ],
    );
  }

  Widget _buildContent() {
    final verified = (_stats['verified'] as int?) ?? 0;
    final total = (_stats['total'] as int?) ?? 0;
    final remaining = (_stats['next_milestone_remaining'] as int?) ?? 5;
    final months = (_stats['total_awarded_months'] as int?) ?? 0;
    final progress = (verified % 5) / 5.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                LocalizationService.t('referral_program'),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (_code != null) ...[
              _buildCopyCodeButton(),
              const SizedBox(width: 8),
              _buildShareButton(),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Text(
          LocalizationService.t('earn_blue_tick_months'),
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 12),
        if (_code != null) _buildCodeRow(_code!),
        const SizedBox(height: 12),
        _buildProgressBar(progress),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                '${LocalizationService.t('verified_referrals')}: $verified/$total',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                ),
              ),
            ),
            Text(
              '${LocalizationService.t('months_awarded')}: $months',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          LocalizationService.t(
            'next_reward_in_n',
          ).replaceAll('{n}', remaining.toString()),
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildCodeRow(String code) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  LocalizationService.t('your_referral_code'),
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  code,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: code));
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(LocalizationService.t('copied')),
                  backgroundColor: AppColors.success,
                ),
              );
            },
            child: Text(
              LocalizationService.t('copy'),
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCopyCodeButton() {
    return TextButton(
      onPressed: () async {
        if (_code == null) return;
        await Clipboard.setData(ClipboardData(text: _code!));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(LocalizationService.t('copied')),
            backgroundColor: AppColors.success,
          ),
        );
      },
      child: Text(
        LocalizationService.t('copy'),
        style: const TextStyle(
          color: AppColors.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildShareButton() {
    return TextButton(
      onPressed: () async {
        try {
          if (_code == null) return;
          final link = 'https://equal.app/ref/${_code!}';
          final message = LocalizationService.t(
            'share_referral_link_message',
          ).replaceAll('{code}', _code!).replaceAll('{link}', link);
          await Share.share(message);
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(LocalizationService.t('failed_to_share_referral')),
              backgroundColor: AppColors.error,
            ),
          );
        }
      },
      child: Text(
        LocalizationService.t('share'),
        style: const TextStyle(
          color: AppColors.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildProgressBar(double progress) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: LinearProgressIndicator(
        value: progress,
        minHeight: 12,
        color: AppColors.primary,
        backgroundColor: AppColors.surfaceVariant,
      ),
    );
  }
}
