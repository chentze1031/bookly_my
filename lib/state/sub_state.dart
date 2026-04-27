import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

const _rcKey            = 'goog_fmJwLiMicCjgynOjRxGdlItPFUb';
const _admobInterstitial = 'ca-app-pub-1544282175684415/1380164927'; // ← 替换为你的 Interstitial Ad Unit ID
const _rcEntitlement    = 'pro';
const _prodMonthly      = 'bookly_pro_monthly';
const _prodYearly       = 'bookly_pro_yearly';

// ══════════════════════════════
// 🔧 DEBUG: 设为 true 关闭所有付费限制
const _debugProMode = true;
// ══════════════════════════════
// ── Ad trigger settings ───────────────────────────────────────────────────────
// 每隔多少分钟可以触发一次广告（保存/分享动作）
const _adCooldownMinutes = 4;
// 每隔多少分钟计时器自动触发广告（用户持续使用中）
const _adTimerMinutes    = 6;

class SubState extends ChangeNotifier {
  bool    isPro      = _debugProMode;
  String? proExpires;
  bool    adLoading  = _debugProMode;
  Offerings? _offerings;

  // ── Interstitial ad ───────────────────────────────────────────────────────
  InterstitialAd? _interstitialAd;
  bool _adReady = false;

  // ── Action-based cooldown ─────────────────────────────────────────────────
  // Track last time ad was shown (save/share trigger)
  DateTime? _lastAdShown;

  // ── Timer-based trigger ───────────────────────────────────────────────────
  Timer? _adTimer;

  bool get hasAccess => isPro;
  
  // ── Init ──────────────────────────────────────────────────────────────────
  Future<void> init() async {
    // RevenueCat
    try {
      await Purchases.setLogLevel(LogLevel.error);
      await Purchases.configure(PurchasesConfiguration(_rcKey));
      final info = await Purchases.getCustomerInfo();
      _applyInfo(info);
      _offerings = await Purchases.getOfferings();
    } catch (_) {}

    // AdMob
    try { await MobileAds.instance.initialize(); } catch (_) {}

    // Load first interstitial ad + show on launch
    if (!isPro && !_debugProMode) {
  _loadInterstitialAd(showAfterLoad: true);
  _startAdTimer();
    }

    notifyListeners();
  }

  void _applyInfo(CustomerInfo info) {
   if (_debugProMode) return; 
   final ent = info.entitlements.active[_rcEntitlement];
   isPro      = ent != null;
   proExpires = ent?.expirationDate;
  }

  // ── Load interstitial ad ──────────────────────────────────────────────────
  void _loadInterstitialAd({bool showAfterLoad = false}) {
    if (isPro) return;
    InterstitialAd.load(
      adUnitId: _admobInterstitial,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _adReady = true;
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              _interstitialAd = null;
              _adReady = false;
              _lastAdShown = DateTime.now();
              _loadInterstitialAd(); // preload next
            },
            onAdFailedToShowFullScreenContent: (ad, _) {
              ad.dispose();
              _interstitialAd = null;
              _adReady = false;
              _loadInterstitialAd();
            },
          );
          // Show immediately after load (launch trigger)
          if (showAfterLoad) {
            // Small delay so home screen renders first
            Future.delayed(const Duration(milliseconds: 800), () {
              _showInterstitialAd();
            });
          }
        },
        onAdFailedToLoad: (_) {
          _adReady = false;
          // retry after 30s
          Future.delayed(const Duration(seconds: 30), _loadInterstitialAd);
        },
      ),
    );
  }

  // ── Show interstitial ad ──────────────────────────────────────────────────
  void _showInterstitialAd() {
    if (!_adReady || _interstitialAd == null || isPro) return;
    _interstitialAd!.show();
    _lastAdShown = DateTime.now();
  }

  // ── Timer: show ad every N minutes while app is open ─────────────────────
  void _startAdTimer() {
    _adTimer?.cancel();
    _adTimer = Timer.periodic(
      Duration(minutes: _adTimerMinutes),
      (_) {
        if (!isPro) _showInterstitialAd();
      },
    );
  }

  void _stopAdTimer() {
    _adTimer?.cancel();
    _adTimer = null;
  }

  // ── Called on SAVE action (save invoice / save payroll) ───────────────────
  void onSaveAction() {
    if (isPro) return;
    final now = DateTime.now();
    if (_lastAdShown == null ||
        now.difference(_lastAdShown!).inMinutes >= _adCooldownMinutes) {
      _showInterstitialAd();
    }
  }

  // ── Called on SHARE/EXPORT action (export PDF) ────────────────────────────
  void onShareAction() {
    if (isPro) return;
    final now = DateTime.now();
    if (_lastAdShown == null ||
        now.difference(_lastAdShown!).inMinutes >= _adCooldownMinutes) {
      _showInterstitialAd();
    }
  }

  // ── Subscription ──────────────────────────────────────────────────────────
  Future<bool> purchasePlan(bool yearly) async {
    if (_offerings == null) {
      try { _offerings = await Purchases.getOfferings(); } catch (_) { return false; }
    }
    try {
      final productId = yearly ? _prodYearly : _prodMonthly;
      final pkgs = _offerings!.current?.availablePackages ?? [];
      if (pkgs.isEmpty) return false;
      final pkg = pkgs.firstWhere(
        (p) => p.storeProduct.identifier == productId,
        orElse: () => pkgs.first,
      );
      final customerInfo = await Purchases.purchasePackage(pkg);
      _applyInfo(customerInfo);
      if (isPro) {
        _stopAdTimer();
        _interstitialAd?.dispose();
        _interstitialAd = null;
        _adReady = false;
      }
      notifyListeners();
      return isPro;
    } catch (_) { return false; }
  }

  Future<bool> restorePurchases() async {
    try {
      final info = await Purchases.restorePurchases();
      _applyInfo(info);
      if (isPro) {
        _stopAdTimer();
        _interstitialAd?.dispose();
        _interstitialAd = null;
        _adReady = false;
      }
      notifyListeners();
      return isPro;
    } catch (_) { return false; }
  }

  @override
  void dispose() {
    _stopAdTimer();
    _interstitialAd?.dispose();
    super.dispose();
  }
}
