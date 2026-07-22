import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';

// ── RevenueCat keys ──────────────────────────────────────────────────────────
// FIX #1: 生产环境必须使用正式 RevenueCat API Key（前缀 goog_ 或 appl_）
//         测试 key（test_*）只能在沙盒环境使用，App Store / Play Store 真实购买无效。
const _rcKeyTest = 'test_NMbMWcFIGpMikMYQWgomGnqLwRq';
const _rcKeyProd = 'goog_hHQPxmGzZqNetGealNfJQGiTfgW';
String get _rcKey => kReleaseMode ? _rcKeyProd : _rcKeyTest;

// ── AdMob Ad Unit IDs ───────────────────────────────────────────────────────
// FIX #2: 插屏广告 ID 使用 '/' 分隔符（广告单元），而非 '~'（应用 ID）。
//         '~' 格式的应用 ID 仅用于 AdMob 初始化，广告加载必须用广告单元 ID。
// 插页式 Interstitial 单元（AdMob app ① ~3532564824）。横幅是另一个单元
// /4562575468（见 home_screen.dart 的 _admobBanner）。
const _admobInterstitial = 'ca-app-pub-1544282175684415/9693085396';

const _rcEntitlement     = 'pro';
const _prodMonthly       = 'bookly_pro_monthly';
const _prodYearly        = 'bookly_pro_yearly';

// ══════════════════════════════
// 🔧 DEBUG: 本地试用时临时设 true 解锁所有 Pro（仅开发测试）。
// 即使误留 true，release 构建也会强制忽略——见下方 _proBypass。
const _debugProMode = false;
// release 永久安全闸：_proBypass 在 release 构建里恒为 false（kReleaseMode 是
// 编译期 const），所以绝不会把 Pro 免费送给正式用户。代码里一律用 _proBypass。
const _proBypass = _debugProMode && !kReleaseMode;
// ══════════════════════════════
// ── Ad trigger settings ───────────────────────────────────────────────────────
// 每隔多少分钟可以触发一次广告（保存/分享动作）
const _adCooldownMinutes = 3;
// FIX #10: 连续加载失败上限，超过后停止重试
const _adMaxRetries      = 5;

class SubState extends ChangeNotifier {
  // FIX #7: 添加初始化状态，防止 PRO 用户在启动时短暂看到免费版界面
  bool       _initialized = false;
  bool       isPro        = _proBypass;
  String?    proExpires;
  // FIX #6: 记录 RevenueCat 初始化错误，供 UI 展示
  String?    initError;
  bool       adLoading    = false;
  Offerings? _offerings;
  bool       _configured = false;
  String?    _appUserId;

  // ── Interstitial ad ───────────────────────────────────────────────────────
  InterstitialAd? _interstitialAd;
  bool      _adReady    = false;
  // FIX #10: 广告加载失败重试计数器
  int       _adFailCount = 0;

  // ── Action-based cooldown ─────────────────────────────────────────────────
  DateTime? _lastAdShown;

  // FIX #7: 初始化完成前 hasAccess 返回 false，避免 UI 闪烁
  bool get hasAccess => _initialized && isPro;

  // ── Init ──────────────────────────────────────────────────────────────────
  Future<void> init() async {
    // FIX #8: dev 守卫——若误把 _debugProMode 设 true 又跑 release 语义，立即报错。
    // （即便没触发，_proBypass 在 release 也恒为 false，Pro 不会泄漏。）
    assert(() { if (kReleaseMode && _debugProMode) throw FlutterError('_debugProMode must be false in release mode'); return true; }());

    // RevenueCat
    try {
      await Purchases.setLogLevel(LogLevel.error);
      final uid = Supabase.instance.client.auth.currentUser?.id;
      await Purchases.configure(PurchasesConfiguration(_rcKey)..appUserID = uid);
      _configured = true;
      _appUserId = uid;

      // FIX #4: 注册 CustomerInfo 更新监听器，实时检测订阅状态变化
      //         （续费失败、过期、恢复、其他设备购买等场景）
      Purchases.addCustomerInfoUpdateListener((info) {
        _applyInfo(info);
        notifyListeners();
      });

      final info = await Purchases.getCustomerInfo();
      _applyInfo(info);
      _offerings = await Purchases.getOfferings();
    } catch (e) {
      // FIX #6: 区分网络错误 vs 配置错误，提供明确的用户提示
      final msg = e is PlatformException ? e.message : e.toString();
      initError = 'RevenueCat init failed: $msg';
      debugPrint(initError);
    }

    // AdMob
    try { await MobileAds.instance.initialize(); } catch (_) {}

    if (!isPro) {
      _loadInterstitialAd();
    }

    // FIX #7: 标记初始化完成，解除 UI 锁定状态
    _initialized = true;
    notifyListeners();
  }

  void _applyInfo(CustomerInfo info) {
    if (_proBypass) return;
    final ent  = info.entitlements.active[_rcEntitlement];
    isPro      = ent != null;
    proExpires = ent?.expirationDate;
    // FIX #12: 状态变更时同步广告加载/卸载逻辑，防止遗漏
    _syncAdsAfterAccessChange();
  }

  Future<void> identifyUser(String? uid) async {
    if (_proBypass || !_configured || uid == null || uid == _appUserId) return;
    try {
      final result = await Purchases.logIn(uid);
      _appUserId = uid;
      _applyInfo(result.customerInfo);
      _offerings = await Purchases.getOfferings();
      notifyListeners();
    } catch (e) {
      debugPrint('RevenueCat login failed: $e');
    }
  }

  Future<void> forgetUser() async {
    if (_proBypass || !_configured) return;
    try {
      final info = await Purchases.logOut();
      _appUserId = null;
      _applyInfo(info);
    } catch (e) {
      debugPrint('RevenueCat logout failed: $e');
      _appUserId = null;
      // FIX: logout 失败时确保恢复到免费状态
      isPro = false;
      proExpires = null;
      _syncAdsAfterAccessChange();
    }
    notifyListeners();
  }

  // ── Load interstitial ad ──────────────────────────────────────────────────
  void _loadInterstitialAd() {
    if (isPro) return;
    // 占位符 ID 必然加载失败，直接跳过，避免空耗 5 次重试
    // TODO: 在 AdMob Console 创建插屏广告单元并替换 _admobInterstitial 后，此行自动失效
    if (_admobInterstitial.contains('PLACEHOLDER')) return;
    // FIX #10: 连续失败超过上限则停止重试，防止死循环
    if (_adFailCount >= _adMaxRetries) return;
    InterstitialAd.load(
      adUnitId: _admobInterstitial,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _adReady = true;
          _adFailCount = 0;
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              _interstitialAd = null;
              _adReady = false;
              _loadInterstitialAd(); // 预加载下一条
            },
            onAdFailedToShowFullScreenContent: (ad, _) {
              ad.dispose();
              _interstitialAd = null;
              _adReady = false;
              _loadInterstitialAd();
            },
          );
        },
        onAdFailedToLoad: (_) {
          _adReady = false;
          _adFailCount++;
          // 连续失败后延长重试间隔：前3次 30s，之后 120s
          final delay = _adFailCount <= 3
              ? const Duration(seconds: 30)
              : const Duration(seconds: 120);
          Future.delayed(delay, _loadInterstitialAd);
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

  // ── Called on SAVE action ─────────────────────────────────────────────────
  void onSaveAction() {
    if (isPro) return;
    final now = DateTime.now();
    if (_lastAdShown == null ||
        now.difference(_lastAdShown!).inMinutes >= _adCooldownMinutes) {
      _showInterstitialAd();
    }
  }

  // ── Called on SHARE/EXPORT action ────────────────────────────────────────
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
      final offering = _offerings!.current;
      final pkgs = offering?.availablePackages ?? [];
      if (pkgs.isEmpty) return false;
      final pkg = pkgs.where((p) => _matchesProductId(p, productId)).firstOrNull ??
          (yearly ? offering?.annual : offering?.monthly);
      if (pkg == null) {
        // FIX #9: 打印可用 packages 便于调试产品 ID 不匹配问题
        debugPrint('⚠️ RevenueCat: No package found for $productId. '
            'Available: ${pkgs.map((p) => p.identifier).join(', ')}');
        return false;
      }
      debugPrint('Purchasing RevenueCat package: ${pkg.identifier} / ${pkg.storeProduct.identifier}');
      final result = await Purchases.purchasePackage(pkg);
      _applyInfo(result.customerInfo);
      notifyListeners();
      return isPro;
    } catch (e) {
      debugPrint('RevenueCat purchase failed: $e');
      return false;
    }
  }

  Future<bool> restorePurchases() async {
    try {
      final info = await Purchases.restorePurchases();
      _applyInfo(info);
      notifyListeners();
      return isPro;
    } catch (_) { return false; }
  }

  bool _matchesProductId(Package pkg, String productId) {
    final storeId = pkg.storeProduct.identifier;
    return storeId == productId ||
        storeId.startsWith('$productId:') ||
        pkg.identifier == productId ||
        pkg.identifier.startsWith('$productId:');
  }

  // ── Localized store prices ─────────────────────────────────────────────────
  // FIX (Google Play 订阅政策): 价格必须读取 Google Play 本地化后的 priceString，
  // 不能硬编码 RM，否则与结账界面币种不一致会被拒审。
  Package? _findPackage(bool yearly) {
    final offering = _offerings?.current;
    if (offering == null) return null;
    final productId = yearly ? _prodYearly : _prodMonthly;
    return offering.availablePackages
            .where((p) => _matchesProductId(p, productId)).firstOrNull ??
        (yearly ? offering.annual : offering.monthly);
  }

  /// e.g. "RM 9.90" in Malaysia — always matches the Google Play checkout currency.
  String? get monthlyPriceString => _findPackage(false)?.storeProduct.priceString;
  String? get yearlyPriceString  => _findPackage(true)?.storeProduct.priceString;

  /// Free-trial length (in days) of a plan's Google Play offer, or null if the
  /// plan has no free-trial phase. Reads the offer configured in Play Console,
  /// so no code change is needed when you add/remove the trial — the paywall
  /// surfaces it automatically.
  int? get monthlyTrialDays => _trialDays(_findPackage(false));
  int? get yearlyTrialDays  => _trialDays(_findPackage(true));

  int? _trialDays(Package? pkg) {
    final period = pkg?.storeProduct.defaultOption?.freePhase?.billingPeriod;
    if (period == null) return null;
    switch (period.unit) {
      case PeriodUnit.day:   return period.value;
      case PeriodUnit.week:  return period.value * 7;
      case PeriodUnit.month: return period.value * 30;
      case PeriodUnit.year:  return period.value * 365;
      case PeriodUnit.unknown: return null;
    }
  }

  /// Savings badge computed from real store prices (null until prices load).
  String? get yearlySavingsLabel {
    final m = _findPackage(false)?.storeProduct.price;
    final y = _findPackage(true)?.storeProduct.price;
    if (m == null || y == null || m <= 0) return null;
    final pct = ((1 - y / (m * 12)) * 100).round();
    return pct >= 1 ? 'Save $pct%' : null;
  }

  void _syncAdsAfterAccessChange() {
    if (isPro) {
      _interstitialAd?.dispose();
      _interstitialAd = null;
      _adReady = false;
    } else if (!_adReady && _interstitialAd == null) {
      _loadInterstitialAd();
    }
  }

  @override
  void dispose() {
    _interstitialAd?.dispose();
    super.dispose();
  }
}
