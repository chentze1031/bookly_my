import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

const _rcKey         = 'goog_fmJwLiMicCjgynOjRxGdlItPFUb';
const _admobRewarded = 'ca-app-pub-1544282175684415/1380164927'; 
const _rcEntitlement = 'pro';
const _prodMonthly   = 'bookly_pro_monthly';
const _prodYearly    = 'bookly_pro_yearly';
const _adsNeeded     = 3;
const freeTxLimit    = 30;
const _dayPassMs     = 24 * 3600 * 1000;

class SubState extends ChangeNotifier {
  bool    isPro      = false;
  String? proExpires;
  int     adsToday   = 0;
  String  adDate     = '';
  int?    dayPassExp;
  bool    adLoading  = false;
  Offerings? _offerings;

  bool get dayPassActive =>
      dayPassExp != null && DateTime.now().millisecondsSinceEpoch < dayPassExp!;

  bool get hasAccess => isPro || dayPassActive;

  bool canAddTx(int monthCount) => hasAccess || monthCount < freeTxLimit;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final savedDate = prefs.getString('bly_ad_date') ?? '';
    if (savedDate == today) adsToday = prefs.getInt('bly_ads_today') ?? 0;
    adDate = today;
    final dp = prefs.getInt('bly_day_pass');
    if (dp != null && DateTime.now().millisecondsSinceEpoch < dp) dayPassExp = dp;

    try {
      await Purchases.setLogLevel(LogLevel.error);
      await Purchases.configure(PurchasesConfiguration(_rcKey));
      final info = await Purchases.getCustomerInfo();
      _applyInfo(info);
      _offerings = await Purchases.getOfferings();
    } catch (_) {}

    try { await MobileAds.instance.initialize(); } catch (_) {}
    notifyListeners();
  }

  void _applyInfo(CustomerInfo info) {
    final ent = info.entitlements.active[_rcEntitlement];
    isPro      = ent != null;
    proExpires = ent?.expirationDate;
  }

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
      // purchases_flutter 8.x: purchasePackage returns CustomerInfo directly
      final customerInfo = await Purchases.purchasePackage(pkg);
      _applyInfo(customerInfo);  
      notifyListeners();
      return isPro;
    } catch (_) { return false; }
  }

  Future<bool> restorePurchases() async {
    try {
      final info = await Purchases.restorePurchases();
      _applyInfo(info);
      notifyListeners();
      return isPro;
    } catch (_) { return false; }
  }

  Future<bool> watchRewardedAd() async {
    adLoading = true;
    notifyListeners();

    final completer = Completer<bool>();

    RewardedAd.load(
      adUnitId: _admobRewarded,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              if (!completer.isCompleted) completer.complete(false);
            },
            onAdFailedToShowFullScreenContent: (ad, _) {
              ad.dispose();
              if (!completer.isCompleted) completer.complete(false);
            },
          );
          ad.show(onUserEarnedReward: (_, __) {
            if (!completer.isCompleted) completer.complete(true);
          });
        },
        onAdFailedToLoad: (_) {
          if (!completer.isCompleted) completer.complete(false);
        },
      ),
    );

    final earned = await completer.future;

    if (earned) {
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final count = adDate == today ? adsToday + 1 : 1;
      adsToday = count;
      adDate   = today;
      if (count >= _adsNeeded) {
        dayPassExp = DateTime.now().millisecondsSinceEpoch + _dayPassMs;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('bly_day_pass', dayPassExp!);
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('bly_ad_date', today);
      await prefs.setInt('bly_ads_today', adsToday);
    }

    adLoading = false;
    notifyListeners();
    return earned;
  }
}
