/// Global feature flags to toggle app functionality without removing code
class FeatureFlags {
  /// Toggle voice/video calling across the app
  static const bool callsEnabled = false;

  /// Toggle visibility of user status in UI (e.g., info dialogs)
  static const bool showUserStatus = false;

  /// Toggle quick emoji reactions in live streaming UI
  static const bool liveReactionsEnabled = false;

  /// Toggle visibility of Dark mode toggle in Settings
  static const bool showDarkModeToggle = false;

  /// Toggle visibility of Safe Mode setting in Settings
  static const bool showSafeModeToggle = false;

  /// Enable screenshot/demo mode (bypass auth and prompts where possible)
  static const bool screenshotDemoMode = true;

  /// When demo mode is enabled, preselect an initial tab index for screenshots.
  /// Tabs: 0=Home/Feed, 1=Discover, 2=Create, 3=Activity, 4=Profile
  static const int? screenshotInitialTabIndex = 0;
}
