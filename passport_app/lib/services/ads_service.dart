import 'dart:async';
import 'dart:io';

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// AdMob wrapper. Uses Google's official TEST ad unit ids, so ads render on a
/// real device without a configured AdMob account — the rewarded-video unlock
/// works end-to-end today. Swap these for real ids (and the manifest app id)
/// before release. All calls are defensive: an ad failure never blocks the
/// core photo flow.
class AdsService {
  static final AdsService instance = AdsService._();
  AdsService._();

  bool _initialized = false;

  // Google test unit ids (safe to ship in debug; replace for production).
  static String get _rewardedUnit => Platform.isIOS
      ? 'ca-app-pub-3940256099942544/1712485313'
      : 'ca-app-pub-3940256099942544/5224354917';
  static String get bannerUnit => Platform.isIOS
      ? 'ca-app-pub-3940256099942544/2934735716'
      : 'ca-app-pub-3940256099942544/6300978111';
  static String get _interstitialUnit => Platform.isIOS
      ? 'ca-app-pub-3940256099942544/4411468910'
      : 'ca-app-pub-3940256099942544/1033173712';

  Future<void> init() async {
    if (_initialized) return;
    try {
      await MobileAds.instance.initialize();
      _initialized = true;
    } catch (e) {
      debugPrint('AdMob init failed (non-fatal): $e');
    }
  }

  /// iOS App Tracking Transparency prompt. No-op on Android. Non-personalised
  /// ads are served unless the user authorises tracking.
  Future<void> requestTrackingIfNeeded() async {
    if (!Platform.isIOS) return;
    try {
      final status =
          await AppTrackingTransparency.trackingAuthorizationStatus;
      if (status == TrackingStatus.notDetermined) {
        await AppTrackingTransparency.requestTrackingAuthorization();
      }
    } catch (e) {
      debugPrint('ATT request failed (non-fatal): $e');
    }
  }

  /// Load and show a rewarded video. Resolves true only if the user earned the
  /// reward. Resolves false (without blocking) if no ad is available.
  Future<bool> showRewarded() async {
    if (!_initialized) await init();
    RewardedAd? ad;
    try {
      ad = await _loadRewarded();
    } catch (e) {
      debugPrint('Rewarded load failed: $e');
      return false;
    }
    if (ad == null) return false;

    // The reward callback fires asynchronously while the ad plays, and
    // `show()` returns before the user finishes it — so we must WAIT for the ad
    // to dismiss and only then report whether the reward was earned. Reading a
    // flag straight after `show()` raced ahead of the callback and denied the
    // unlock to users who watched the whole ad.
    final completer = Completer<bool>();
    var earned = false;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) {
        a.dispose();
        if (!completer.isCompleted) completer.complete(earned);
      },
      onAdFailedToShowFullScreenContent: (a, e) {
        a.dispose();
        if (!completer.isCompleted) completer.complete(false);
      },
    );
    await ad.show(onUserEarnedReward: (ad, reward) => earned = true);
    return completer.future;
  }

  Future<RewardedAd?> _loadRewarded() {
    final completer = Completer<RewardedAd?>();
    RewardedAd.load(
      adUnitId: _rewardedUnit,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) => completer.complete(ad),
        onAdFailedToLoad: (err) {
          debugPrint('Rewarded failed: $err');
          completer.complete(null);
        },
      ),
    );
    return completer.future;
  }

  /// Show a full-screen interstitial. Per the monetisation plan this is only
  /// shown AFTER a successful export, never mid-capture, and never to a paying
  /// user (the caller gates on that). Fully defensive: if no ad loads it just
  /// resolves without interrupting the user.
  Future<void> showInterstitial() async {
    if (!_initialized) await init();
    InterstitialAd? ad;
    try {
      ad = await _loadInterstitial();
    } catch (e) {
      debugPrint('Interstitial load failed: $e');
      return;
    }
    if (ad == null) return;

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) => a.dispose(),
      onAdFailedToShowFullScreenContent: (a, e) => a.dispose(),
    );
    await ad.show();
  }

  Future<InterstitialAd?> _loadInterstitial() {
    final completer = Completer<InterstitialAd?>();
    InterstitialAd.load(
      adUnitId: _interstitialUnit,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) => completer.complete(ad),
        onAdFailedToLoad: (err) {
          debugPrint('Interstitial failed: $err');
          completer.complete(null);
        },
      ),
    );
    return completer.future;
  }

  /// Create a fresh banner (caller disposes). Only used on non-capture screens.
  BannerAd createBanner() => BannerAd(
        adUnitId: bannerUnit,
        size: AdSize.banner,
        request: const AdRequest(),
        listener: BannerAdListener(
          onAdFailedToLoad: (ad, err) {
            debugPrint('Banner failed: $err');
            ad.dispose();
          },
        ),
      )..load();
}
