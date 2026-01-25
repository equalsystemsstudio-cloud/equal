import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../../utils/platform_info_io.dart' if (dart.library.html) '../../utils/platform_info_web.dart';
import '../../services/admob_service.dart';

// Conditionally import google_mobile_ads for mobile, stub for web
import 'package:google_mobile_ads/google_mobile_ads.dart'
    if (dart.library.html) 'google_mobile_ads_web.dart' as ads;

// Web-compatible AdWidget stub
class _WebAdWidget extends StatelessWidget {
  final dynamic ad;
  const _WebAdWidget({required this.ad});
  
  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey[300],
      child: const Center(
        child: Text('Native Ad Placeholder'),
      ),
    );
  }
}

class NativeAdWidget extends StatefulWidget {
  final double height;
  final EdgeInsets margin;
  final bool showForViralPost;
  final int likesCount;
  final int commentsCount;
  final bool adsEnabled;

  const NativeAdWidget({
    super.key,
    this.height = 300,
    this.margin = const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
    this.showForViralPost = false,
    this.likesCount = 0,
    this.commentsCount = 0,
    this.adsEnabled = false,
  });

  @override
  State<NativeAdWidget> createState() => _NativeAdWidgetState();
}

class _NativeAdWidgetState extends State<NativeAdWidget> {
  dynamic _nativeAd;
  bool _isAdLoaded = false;
  bool _isAdFailed = false;
  final AdMobService _adMobService = AdMobService();

  @override
  void initState() {
    super.initState();
    _loadNativeAd();
  }

  void _loadNativeAd() {
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

    // Create native ad only on mobile platforms
    _nativeAd = _adMobService.createNativeAd(
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

    _nativeAd?.load();
  }

  @override
  void dispose() {
    _nativeAd?.dispose();
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

    if (_isAdLoaded && _nativeAd != null) {
      return Container(
        margin: widget.margin,
        height: widget.height,
        decoration: BoxDecoration(
          color: const Color(0xFF1a1a1a),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFF2A2A2A),
            width: 1,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: kIsWeb ? _WebAdWidget(ad: _nativeAd) : ads.AdWidget(ad: _nativeAd),
        ),
      );
    } else if (_isAdFailed) {
      // Show placeholder when ad fails
      return Container(
        margin: widget.margin,
        height: widget.height,
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: Text(
            'Native Ad Space',
            style: TextStyle(
              color: Colors.grey,
              fontSize: 14,
            ),
          ),
        ),
      );
    } else {
      // Loading state
      return Container(
        margin: widget.margin,
        height: widget.height,
        decoration: BoxDecoration(
          color: const Color(0xFF1a1a1a),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFF2A2A2A),
            width: 1,
          ),
        ),
        child: const Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6C5CE7)),
          ),
        ),
      );
    }
  }
}

// Feed Native Ad Widget for viral posts
class FeedNativeAd extends StatelessWidget {
  final int likesCount;
  final int commentsCount;
  final bool adsEnabled;
  final EdgeInsets margin;

  const FeedNativeAd({
    super.key,
    this.likesCount = 0,
    this.commentsCount = 0,
    this.adsEnabled = true,
    this.margin = const EdgeInsets.symmetric(vertical: 16.0, horizontal: 16.0),
  });

  @override
  Widget build(BuildContext context) {
    return NativeAdWidget(
      showForViralPost: true,
      likesCount: likesCount,
      commentsCount: commentsCount,
      adsEnabled: adsEnabled,
      margin: margin,
      height: 280,
    );
  }
}