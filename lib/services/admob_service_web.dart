// Web stubs for google_mobile_ads to allow Flutter web builds
// These classes provide minimal APIs used in AdMobService on web.

class MobileAds {
  static final MobileAds instance = MobileAds._();
  MobileAds._();
  Future<void> initialize() async {}
}

class Ad {}

class AdError {}

class LoadAdError {}

class AdRequest {
  const AdRequest();
}

class FullScreenContentCallback {
  final void Function(InterstitialAd)? onAdDismissedFullScreenContent;
  final void Function(InterstitialAd, AdError)? onAdFailedToShowFullScreenContent;
  const FullScreenContentCallback({this.onAdDismissedFullScreenContent, this.onAdFailedToShowFullScreenContent});
}

class InterstitialAd {
  FullScreenContentCallback? fullScreenContentCallback;
  void show() {}
  void dispose() {}
  static void load({required String adUnitId, required AdRequest request, required InterstitialAdLoadCallback adLoadCallback}) {
    adLoadCallback.onAdFailedToLoad(LoadAdError());
  }
}

class InterstitialAdLoadCallback {
  final void Function(InterstitialAd ad) onAdLoaded;
  final void Function(LoadAdError error) onAdFailedToLoad;
  InterstitialAdLoadCallback({required this.onAdLoaded, required this.onAdFailedToLoad});
}

class AdSize {
  static const AdSize banner = AdSize(width: 320, height: 50);
  final int width;
  final int height;
  const AdSize({required this.width, required this.height});
}

class BannerAd extends Ad {
  final String adUnitId;
  final AdSize size;
  final AdRequest request;
  final BannerAdListener listener;
  BannerAd({required this.adUnitId, required this.size, required this.request, required this.listener});
  void load() {}
  void dispose() {}
}

class BannerAdListener {
  final void Function(dynamic ad)? onAdLoaded;
  final void Function(dynamic ad, dynamic error)? onAdFailedToLoad;
  final void Function(Ad ad)? onAdOpened;
  final void Function(Ad ad)? onAdClosed;
  BannerAdListener({this.onAdLoaded, this.onAdFailedToLoad, this.onAdOpened, this.onAdClosed});
}

class TemplateType {
  static const TemplateType medium = TemplateType._('medium');
  final String value;
  const TemplateType._(this.value);
}

class NativeTemplateFontStyle {
  static const NativeTemplateFontStyle bold = NativeTemplateFontStyle._('bold');
  static const NativeTemplateFontStyle normal = NativeTemplateFontStyle._('normal');
  final String value;
  const NativeTemplateFontStyle._(this.value);
}

class NativeTemplateTextStyle {
  final dynamic textColor;
  final dynamic backgroundColor;
  final NativeTemplateFontStyle style;
  final double size;
  NativeTemplateTextStyle({this.textColor, this.backgroundColor, required this.style, required this.size});
}

class NativeTemplateStyle {
  final TemplateType templateType;
  final dynamic mainBackgroundColor;
  final double cornerRadius;
  final NativeTemplateTextStyle? callToActionTextStyle;
  final NativeTemplateTextStyle? primaryTextStyle;
  final NativeTemplateTextStyle? secondaryTextStyle;
  final NativeTemplateTextStyle? tertiaryTextStyle;
  NativeTemplateStyle({required this.templateType, this.mainBackgroundColor, this.cornerRadius = 0.0, this.callToActionTextStyle, this.primaryTextStyle, this.secondaryTextStyle, this.tertiaryTextStyle});
}

class NativeAd extends Ad {
  final String adUnitId;
  final AdRequest request;
  final NativeAdListener listener;
  final NativeTemplateStyle? nativeTemplateStyle;
  NativeAd({required this.adUnitId, required this.request, required this.listener, this.nativeTemplateStyle});
  void load() {}
  void dispose() {}
}

class NativeAdListener {
  final void Function(dynamic ad)? onAdLoaded;
  final void Function(dynamic ad, dynamic error)? onAdFailedToLoad;
  final void Function(Ad ad)? onAdOpened;
  final void Function(Ad ad)? onAdClosed;
  final void Function(Ad ad)? onAdImpression;
  NativeAdListener({this.onAdLoaded, this.onAdFailedToLoad, this.onAdOpened, this.onAdClosed, this.onAdImpression});
}