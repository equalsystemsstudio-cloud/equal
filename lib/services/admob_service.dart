import '../utils/platform_info_io.dart' if (dart.library.html) '../utils/platform_info_web.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter/foundation.dart';

// Conditional imports for platform-specific implementations
import 'package:google_mobile_ads/google_mobile_ads.dart'
    if (dart.library.html) 'admob_service_web.dart';

class AdMobService {
  static final AdMobService _instance = AdMobService._internal();
  factory AdMobService() => _instance;
  AdMobService._internal();

  // Helper: Only enable ads on mobile platforms (Android/iOS)
  bool get _isMobilePlatform => isMobilePlatform();

  // Production AdMob App ID and Ad Unit IDs
  static const String _appId = 'ca-app-pub-7944884911591351~7448776102';
  static const String _bannerAdUnitId = 'ca-app-pub-7944884911591351/3509531097';
  static const String _interstitialAdUnitId = 'ca-app-pub-7944884911591351/2252289743';
  static const String _nativeAdUnitId = 'ca-app-pub-7944884911591351/7572581956';

  // Test Ad Unit IDs for development
  static const String _testBannerAdUnitId = 'ca-app-pub-3940256099942544/6300978111';
  static const String _testInterstitialAdUnitId = 'ca-app-pub-3940256099942544/1033173712';
  static const String _testNativeAdUnitId = 'ca-app-pub-3940256099942544/2247696110';

  InterstitialAd? _interstitialAd;
  bool _isInterstitialAdReady = false;

  // Initialize the Mobile Ads SDK
  Future<void> initialize() async {
    if (!_isMobilePlatform) {
      // Non-mobile platforms - ads not supported, return early
      if (kDebugMode) {
        debugPrint(('AdMob not supported on this platform').toString());
      }
      return;
    }

    try {
      await MobileAds.instance.initialize();
      if (kDebugMode) {
        debugPrint(('AdMob initialized successfully').toString());
      }
      _loadInterstitialAd();
    } catch (e) {
      if (kDebugMode) {
        debugPrint(('Failed to initialize AdMob: $e').toString());
      }
    }
  }

  // Load interstitial ad
  void _loadInterstitialAd() {
    if (!_isMobilePlatform) return;

    InterstitialAd.load(
      adUnitId: kDebugMode ? _testInterstitialAdUnitId : _interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (InterstitialAd ad) {
          _interstitialAd = ad;
          _isInterstitialAdReady = true;
          if (kDebugMode) {
            debugPrint(('Interstitial ad loaded').toString());
          }
        },
        onAdFailedToLoad: (LoadAdError error) {
          _isInterstitialAdReady = false;
          if (kDebugMode) {
            debugPrint(('Interstitial ad failed to load: $error').toString());
          }
        },
      ),
    );
  }

  // Show interstitial ad
  void showInterstitialAd() {
    if (!_isMobilePlatform) {
      if (kDebugMode) {
        debugPrint(('Interstitial ads are only supported on mobile (Android/iOS).').toString());
      }
      return;
    }

    if (_isInterstitialAdReady && _interstitialAd != null) {
      _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (InterstitialAd ad) {
          ad.dispose();
          _loadInterstitialAd(); // Load next ad
        },
        onAdFailedToShowFullScreenContent: (InterstitialAd ad, AdError error) {
          ad.dispose();
          _loadInterstitialAd(); // Load next ad
        },
      );
      _interstitialAd!.show();
      _isInterstitialAdReady = false;
    } else {
      if (kDebugMode) {
        debugPrint(('Interstitial ad not ready').toString());
      }
    }
  }

  // Create banner ad
  BannerAd? createBannerAd({
    dynamic adSize,
    required Function(dynamic) onAdLoaded,
    required Function(dynamic, dynamic) onAdFailedToLoad,
  }) {
    if (!_isMobilePlatform) {
      // Return null for non-mobile platforms
      return null;
    }

    // Convert PlatformAdSize to AdSize for mobile
    AdSize mobileAdSize = AdSize.banner;
    if (adSize != null) {
      if (adSize.width == 320 && adSize.height == 50) {
        mobileAdSize = AdSize.banner;
      }
    }

    return BannerAd(
      adUnitId: kDebugMode ? _testBannerAdUnitId : _bannerAdUnitId,
      size: mobileAdSize,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: onAdLoaded,
        onAdFailedToLoad: onAdFailedToLoad,
        onAdOpened: (Ad ad) {
          if (kDebugMode) {
            debugPrint(('Banner ad opened').toString());
          }
        },
        onAdClosed: (Ad ad) {
          if (kDebugMode) {
            debugPrint(('Banner ad closed').toString());
          }
        },
      ),
    );
  }

  // Create native ad
  NativeAd? createNativeAd({
    required Function(dynamic) onAdLoaded,
    required Function(dynamic, dynamic) onAdFailedToLoad,
  }) {
    if (!_isMobilePlatform) {
      // Return null for non-mobile platforms
      return null;
    }

    return NativeAd(
      adUnitId: kDebugMode ? _testNativeAdUnitId : _nativeAdUnitId,
      request: const AdRequest(),
      listener: NativeAdListener(
        onAdLoaded: onAdLoaded,
        onAdFailedToLoad: onAdFailedToLoad,
        onAdOpened: (Ad ad) {
          if (kDebugMode) {
            debugPrint(('Native ad opened').toString());
          }
        },
        onAdClosed: (Ad ad) {
          if (kDebugMode) {
            debugPrint(('Native ad closed').toString());
          }
        },
        onAdImpression: (Ad ad) {
          if (kDebugMode) {
            debugPrint(('Native ad impression recorded').toString());
          }
        },
      ),
      nativeTemplateStyle: _createNativeTemplateStyle(),
    );
  }

  // Helper method to create native template style (mobile only)
  NativeTemplateStyle _createNativeTemplateStyle() {
    if (!_isMobilePlatform) {
      // Should not be used on non-mobile platforms; return a basic style as fallback
      return NativeTemplateStyle(templateType: TemplateType.medium);
    }
    
    return NativeTemplateStyle(
      templateType: TemplateType.medium,
      mainBackgroundColor: const material.Color(0xFF1a1a1a),
      cornerRadius: 12.0,
      callToActionTextStyle: NativeTemplateTextStyle(
        textColor: material.Colors.white,
        backgroundColor: const material.Color(0xFF6C5CE7),
        style: NativeTemplateFontStyle.bold,
        size: 16.0,
      ),
      primaryTextStyle: NativeTemplateTextStyle(
        textColor: material.Colors.white,
        style: NativeTemplateFontStyle.bold,
        size: 16.0,
      ),
      secondaryTextStyle: NativeTemplateTextStyle(
        textColor: const material.Color(0xFFB0B0B0),
        style: NativeTemplateFontStyle.normal,
        size: 14.0,
      ),
      tertiaryTextStyle: NativeTemplateTextStyle(
        textColor: const material.Color(0xFF888888),
        style: NativeTemplateFontStyle.normal,
        size: 12.0,
      ),
    );
  }

  // Check if ads should be shown for a post (viral posts with 1K+ reactions, 250+ comments)
  bool shouldShowAdsForPost({
    required int likesCount,
    required int commentsCount,
    required bool adsEnabled,
  }) {
    // Only show ads if:
    // 1. Post has ads enabled
    // 2. Post meets viral thresholds (1K+ likes, 250+ comments)
    return adsEnabled && likesCount >= 1000 && commentsCount >= 250;
  }

  // Calculate estimated revenue for a post
  double calculateEstimatedRevenue({
    required int impressions,
    required int clicks,
    required String adType,
  }) {
    // Estimated CPM (Cost Per Mille) rates
    const double bannerCPM = 0.50; // $0.50 per 1000 impressions
    const double interstitialCPM = 2.00; // $2.00 per 1000 impressions
    const double nativeCPM = 1.50; // $1.50 per 1000 impressions

    double cpm;
    switch (adType.toLowerCase()) {
      case 'banner':
        cpm = bannerCPM;
        break;
      case 'interstitial':
        cpm = interstitialCPM;
        break;
      case 'native':
        cpm = nativeCPM;
        break;
      default:
        cpm = bannerCPM;
    }

    // Revenue = (Impressions / 1000) * CPM
    return (impressions / 1000) * cpm;
  }

  // Dispose of ads
  void dispose() {
    if (!_isMobilePlatform) return;
    
    _interstitialAd?.dispose();
    _interstitialAd = null;
    _isInterstitialAdReady = false;
  }

  // Get ad unit IDs (for debugging)
  Map<String, String> getAdUnitIds() {
    return {
      'app_id': _appId,
      'banner': kDebugMode ? _testBannerAdUnitId : _bannerAdUnitId,
      'interstitial': kDebugMode ? _testInterstitialAdUnitId : _interstitialAdUnitId,
      'native': kDebugMode ? _testNativeAdUnitId : _nativeAdUnitId,
    };
  }
}
