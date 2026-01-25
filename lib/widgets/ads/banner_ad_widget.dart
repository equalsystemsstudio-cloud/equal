import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../../utils/platform_info_io.dart' if (dart.library.html) '../../utils/platform_info_web.dart';
import '../../services/admob_service.dart';

// Import google_mobile_ads for mobile; stub for web
import 'package:google_mobile_ads/google_mobile_ads.dart'
    if (dart.library.html) 'google_mobile_ads_web.dart' as ads;

// Web-compatible AdSize stub
class _WebAdSize {
  final int width;
  final int height;
  const _WebAdSize(this.width, this.height);
  
  static const _WebAdSize banner = _WebAdSize(320, 50);
  static const _WebAdSize largeBanner = _WebAdSize(320, 100);
}

// Web-compatible AdWidget stub
class _WebAdWidget extends StatelessWidget {
  final dynamic ad;
  const _WebAdWidget({required this.ad});
  
  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey[300],
      child: const Center(
        child: Text('Ad Placeholder'),
      ),
    );
  }
}

class BannerAdWidget extends StatefulWidget {
  final dynamic adSize; // Can be AdSize on mobile or _WebAdSize on web
  final EdgeInsets margin;
  final bool showForViralPost;
  final int likesCount;
  final int commentsCount;
  final bool adsEnabled;

  const BannerAdWidget({
    super.key,
    this.adSize,
    this.margin = const EdgeInsets.symmetric(vertical: 8.0),
    this.showForViralPost = false,
    this.likesCount = 0,
    this.commentsCount = 0,
    this.adsEnabled = false,
  });

  @override
  State<BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends State<BannerAdWidget> {
  dynamic _bannerAd;
  bool _isAdLoaded = false;
  bool _isAdFailed = false;
  final AdMobService _adMobService = AdMobService();

  @override
  void initState() {
    super.initState();
    _loadBannerAd();
  }

  void _loadBannerAd() {
    // Don't load ads on web or non-mobile platforms
    if (kIsWeb || !isMobilePlatform()) {
      setState(() {
        _isAdLoaded = false;
        _isAdFailed = false;
      });
      return;
    }

    // Check if ads should be shown for this post
    if (widget.showForViralPost) {
      bool shouldShow = _adMobService.shouldShowAdsForPost(
        likesCount: widget.likesCount,
        commentsCount: widget.commentsCount,
        adsEnabled: widget.adsEnabled,
      );
      
      if (!shouldShow) {
        return; // Don't load ad if criteria not met
      }
    }

    // Create banner ad only on mobile platforms
    _bannerAd = _adMobService.createBannerAd(
      adSize: widget.adSize ?? (kIsWeb ? _WebAdSize.banner : ads.AdSize.banner),
      onAdLoaded: (ad) {
        if (mounted) {
          setState(() {
            _isAdLoaded = true;
            _isAdFailed = false;
          });
        }
      },
      onAdFailedToLoad: (ad, error) {
        if (mounted) {
          setState(() {
            _isAdLoaded = false;
            _isAdFailed = true;
          });
        }
        ad?.dispose();
      },
    );

    _bannerAd?.load();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Don't show anything on web or non-mobile platforms
    if (kIsWeb || !isMobilePlatform()) {
      return const SizedBox.shrink();
    }

    // Don't show if ad criteria not met for viral posts
    if (widget.showForViralPost) {
      bool shouldShow = _adMobService.shouldShowAdsForPost(
        likesCount: widget.likesCount,
        commentsCount: widget.commentsCount,
        adsEnabled: widget.adsEnabled,
      );
      
      if (!shouldShow) {
        return const SizedBox.shrink();
      }
    }

    if (_isAdLoaded && _bannerAd != null) {
      return Container(
        margin: widget.margin,
        alignment: Alignment.center,
        width: (widget.adSize ?? (kIsWeb ? _WebAdSize.banner : ads.AdSize.banner)).width.toDouble(),
        height: (widget.adSize ?? (kIsWeb ? _WebAdSize.banner : ads.AdSize.banner)).height.toDouble(),
        child: kIsWeb ? _WebAdWidget(ad: _bannerAd) : ads.AdWidget(ad: _bannerAd),
      );
    } else if (_isAdFailed) {
      // Show placeholder or nothing when ad fails
      return Container(
        margin: widget.margin,
        height: 50,
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(
          child: Text(
            'Ad Space',
            style: TextStyle(
              color: Colors.grey,
              fontSize: 12,
            ),
          ),
        ),
      );
    } else {
      // Loading state
      return Container(
        margin: widget.margin,
        height: 50,
        child: const Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
          ),
        ),
      );
    }
  }
}

// Viral Post Banner Ad Widget
class ViralPostBannerAd extends StatelessWidget {
  final int likesCount;
  final int commentsCount;
  final bool adsEnabled;
  final EdgeInsets margin;

  const ViralPostBannerAd({
    super.key,
    required this.likesCount,
    required this.commentsCount,
    required this.adsEnabled,
    this.margin = const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
  });

  @override
  Widget build(BuildContext context) {
    return BannerAdWidget(
      showForViralPost: true,
      likesCount: likesCount,
      commentsCount: commentsCount,
      adsEnabled: adsEnabled,
      margin: margin,
      adSize: kIsWeb ? _WebAdSize.largeBanner : ads.AdSize.largeBanner,
    );
  }
}