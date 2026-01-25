import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

class PreferencesService {
  static const String _notificationsKey = 'notifications_enabled';
  static const String _darkModeKey = 'dark_mode_enabled';
  static const String _autoPlayVideosKey = 'auto_play_videos';
  static const String _saveToGalleryKey = 'save_to_gallery';
  static const String _highQualityUploadsKey = 'high_quality_uploads';
  static const String _selectedLanguageKey = 'selected_language_name';
  static const String _qwenApiKeyKey = 'qwen_api_key';
  static const String _pendingReferralCodeKey = 'pending_referral_code';

  // Notifiers
  static final ValueNotifier<bool> darkModeNotifier = ValueNotifier<bool>(
    false,
  );
  // Add privacy notifiers for real-time updates
  static final ValueNotifier<bool> showOnlineStatusNotifier =
      ValueNotifier<bool>(true);
  static final ValueNotifier<bool> readReceiptsNotifier = ValueNotifier<bool>(
    true,
  );

  // Privacy & Security
  static const String _privateAccountKey = 'privacy_private_account';
  static const String _allowTaggingKey = 'privacy_allow_tagging';
  static const String _allowMentionsKey = 'privacy_allow_mentions';
  static const String _showOnlineStatusKey = 'privacy_show_online_status';
  static const String _allowMessageRequestsKey =
      'privacy_allow_message_requests';
  static const String _showReadReceiptsKey = 'privacy_show_read_receipts';
  static const String _allowStoryRepliesKey = 'privacy_allow_story_replies';
  static const String _shareDataForAdsKey = 'privacy_share_data_for_ads';
  static const String _allowAnalyticsKey = 'privacy_allow_analytics';
  static const String _twoFactorEnabledKey = 'security_2fa_enabled';
  static const String _twoFactorRecoveryCodeKey = 'security_2fa_recovery_code';

  // Notifications
  Future<bool> getNotificationsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_notificationsKey) ?? true;
  }

  Future<void> setNotificationsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_notificationsKey, enabled);
  }

  // Dark Mode
  Future<bool> getDarkModeEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_darkModeKey) ?? false;
    // Keep notifier in sync for real-time theme updates
    darkModeNotifier.value = enabled;
    return enabled;
  }

  Future<void> setDarkModeEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_darkModeKey, enabled);
    // Notify listeners so app theme updates instantly
    darkModeNotifier.value = enabled;
  }

  // Auto Play Videos
  Future<bool> getAutoPlayVideos() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoPlayVideosKey) ?? true;
  }

  Future<void> setAutoPlayVideos(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoPlayVideosKey, enabled);
  }

  // Save to Gallery
  Future<bool> getSaveToGallery() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_saveToGalleryKey) ?? false;
  }

  Future<void> setSaveToGallery(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_saveToGalleryKey, enabled);
  }

  // High Quality Uploads
  Future<bool> getHighQualityUploads() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_highQualityUploadsKey) ?? true;
  }

  Future<void> setHighQualityUploads(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_highQualityUploadsKey, enabled);
  }

  // Selected Language
  Future<String> getSelectedLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_selectedLanguageKey) ?? 'English';
  }

  Future<void> setSelectedLanguage(String language) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_selectedLanguageKey, language);
  }

  // Qwen API Key
  Future<String> getQwenApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_qwenApiKeyKey) ?? '';
  }

  Future<void> setQwenApiKey(String apiKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_qwenApiKeyKey, apiKey);
  }

  Future<void> clearQwenApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_qwenApiKeyKey);
  }

  // Pending Referral Code (captured from deep links)
  Future<String?> getPendingReferralCode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_pendingReferralCodeKey);
  }

  Future<void> setPendingReferralCode(String code) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingReferralCodeKey, code);
  }

  Future<void> clearPendingReferralCode() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingReferralCodeKey);
  }

  // Privacy & Security getters/setters
  Future<bool> getPrivateAccount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_privateAccountKey) ?? false;
  }

  Future<void> setPrivateAccount(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_privateAccountKey, enabled);
  }

  Future<bool> getAllowTagging() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_allowTaggingKey) ?? true;
  }

  Future<void> setAllowTagging(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_allowTaggingKey, enabled);
  }

  Future<bool> getAllowMentions() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_allowMentionsKey) ?? true;
  }

  Future<void> setAllowMentions(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_allowMentionsKey, enabled);
  }

  Future<bool> getShowOnlineStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_showOnlineStatusKey) ?? true;
    // Keep notifier in sync for real-time presence updates
    showOnlineStatusNotifier.value = enabled;
    return enabled;
  }

  Future<void> setShowOnlineStatus(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showOnlineStatusKey, enabled);
    // Notify listeners so presence can update instantly
    showOnlineStatusNotifier.value = enabled;
  }

  Future<bool> getAllowMessageRequests() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_allowMessageRequestsKey) ?? true;
  }

  Future<void> setAllowMessageRequests(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_allowMessageRequestsKey, enabled);
  }

  Future<bool> getShowReadReceipts() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_showReadReceiptsKey) ?? true;
    // Keep notifier in sync so messaging can update behavior immediately
    readReceiptsNotifier.value = enabled;
    return enabled;
  }

  Future<void> setShowReadReceipts(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showReadReceiptsKey, enabled);
    // Notify listeners for immediate UI/behavior updates
    readReceiptsNotifier.value = enabled;
  }

  Future<bool> getAllowStoryReplies() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_allowStoryRepliesKey) ?? true;
  }

  Future<void> setAllowStoryReplies(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_allowStoryRepliesKey, enabled);
  }

  Future<bool> getShareDataForAds() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_shareDataForAdsKey) ?? false;
  }

  Future<void> setShareDataForAds(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_shareDataForAdsKey, enabled);
  }

  Future<bool> getAllowAnalytics() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_allowAnalyticsKey) ?? true;
  }

  Future<void> setAllowAnalytics(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_allowAnalyticsKey, enabled);
  }

  Future<bool> getTwoFactorEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_twoFactorEnabledKey) ?? false;
  }

  Future<void> setTwoFactorEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_twoFactorEnabledKey, enabled);
  }

  Future<String?> getTwoFactorRecoveryCode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_twoFactorRecoveryCodeKey);
  }

  Future<void> setTwoFactorRecoveryCode(String code) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_twoFactorRecoveryCodeKey, code);
  }

  // Clear all preferences
  Future<void> clearAllPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}
