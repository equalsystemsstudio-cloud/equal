import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../config/app_colors.dart';
import '../../widgets/custom_button.dart';
import '../../services/localization_service.dart';

class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  final AuthService _authService = AuthService();
  List<Map<String, dynamic>> _blockedUsers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBlockedUsers();
  }

  Future<void> _loadBlockedUsers() async {
    try {
      final blockedUsers = await _authService.getBlockedUsers();
      if (mounted) {
        setState(() {
          _blockedUsers = blockedUsers;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const LocalizedText('Failed to load blocked users'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _unblockUser(String userId, String username) async {
    final shouldUnblock = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          LocalizationService.t('unblock_user'),
          style: const TextStyle(color: AppColors.textPrimary),
        ),
        content: LocalizedText(
          'Are you sure you want to unblock $username? They will be able to see your profile and contact you again.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              LocalizationService.t('cancel'),
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              LocalizationService.t('unblock'),
              style: TextStyle(color: AppColors.primary),
            ),
          ),
        ],
      ),
    );

    if (shouldUnblock == true) {
      try {
        await _authService.unblockUser(userId);
        if (mounted) {
          setState(() {
            _blockedUsers.removeWhere((user) => user['blocked_id'] == userId);
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: LocalizedText('$username has been unblocked'),
              backgroundColor: AppColors.success,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const LocalizedText('failed_unblock_user'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const LocalizedText(
          'Blocked Users',
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
          : _blockedUsers.isEmpty
          ? _buildEmptyState()
          : _buildBlockedUsersList(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.block, size: 64, color: AppColors.textSecondary),
          const SizedBox(height: 16),
          const LocalizedText(
            'No Blocked Users',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          const LocalizedText(
            "You haven't blocked anyone yet",
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildBlockedUsersList() {
    return RefreshIndicator(
      onRefresh: _loadBlockedUsers,
      color: AppColors.primary,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _blockedUsers.length,
        itemBuilder: (context, index) {
          final blockedUser = _blockedUsers[index];
          final userData = blockedUser['users'];

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border, width: 1),
            ),
            child: Row(
              children: [
                // Avatar
                CircleAvatar(
                  radius: 24,
                  backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                  backgroundImage:
                      userData['avatar_url'] != null &&
                          userData['avatar_url'].isNotEmpty
                      ? NetworkImage(userData['avatar_url'])
                      : null,
                  child:
                      userData['avatar_url'] == null ||
                          userData['avatar_url'].isEmpty
                      ? Text(
                          (userData['username'] ?? 'U')[0].toUpperCase(),
                          style: TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 12),

                // User info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        userData['username'] ?? 'Unknown User',
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      if (userData['display_name'] != null &&
                          userData['display_name'].isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          userData['display_name'], // Fixed: use display_name instead of full_name
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Unblock button
                SizedBox(
                  width: 120,
                  height: 32,
                  child: CustomButton(
                    text: 'Unblock',
                    onPressed: () => _unblockUser(
                      blockedUser['blocked_id'],
                      userData['username'] ?? 'User',
                    ),
                    isOutlined: true,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
