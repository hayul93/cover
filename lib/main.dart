import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:image_cropper/image_cropper.dart';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

// 테마 모드 관리
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.dark);

// ==================== Analytics 서비스 ====================

class AnalyticsService {
  static final AnalyticsService _instance = AnalyticsService._internal();
  factory AnalyticsService() => _instance;
  AnalyticsService._internal();

  FirebaseAnalytics? _analytics;
  bool _isInitialized = false;

  // 초기화
  Future<void> initialize() async {
    try {
      await Firebase.initializeApp();
      _analytics = FirebaseAnalytics.instance;
      _isInitialized = true;
      debugPrint('Firebase Analytics 초기화 완료');
    } catch (e) {
      debugPrint('Firebase Analytics 초기화 실패: $e');
      _isInitialized = false;
    }
  }

  // 이벤트 로깅
  Future<void> logEvent(String name, [Map<String, Object>? parameters]) async {
    if (!_isInitialized || _analytics == null) return;
    try {
      await _analytics!.logEvent(name: name, parameters: parameters);
    } catch (e) {
      debugPrint('Analytics 이벤트 로깅 실패: $e');
    }
  }

  // 화면 조회 로깅
  Future<void> logScreenView(String screenName) async {
    if (!_isInitialized || _analytics == null) return;
    try {
      await _analytics!.logScreenView(screenName: screenName);
    } catch (e) {
      debugPrint('Analytics 화면 로깅 실패: $e');
    }
  }

  // 사용자 속성 설정
  Future<void> setUserProperty(String name, String value) async {
    if (!_isInitialized || _analytics == null) return;
    try {
      await _analytics!.setUserProperty(name: name, value: value);
    } catch (e) {
      debugPrint('Analytics 사용자 속성 설정 실패: $e');
    }
  }

  // ==================== 앱 이벤트 ====================

  // 이미지 가져오기
  void logImageImported(String source) {
    logEvent('image_imported', {'source': source});
  }

  // 도구 사용
  void logToolUsed(String tool, {String? mode, String? shape}) {
    final params = <String, Object>{'tool': tool};
    if (mode != null) params['mode'] = mode;
    if (shape != null) params['shape'] = shape;
    logEvent('tool_used', params);
  }

  // 이미지 저장
  void logImageSaved({String? quality}) {
    logEvent('image_saved', quality != null ? {'quality': quality} : null);
  }

  // 이미지 공유
  void logImageShared() {
    logEvent('image_shared');
  }

  // 구독 시작
  void logSubscriptionStarted(String plan) {
    logEvent('subscription_started', {'plan': plan});
  }

  // 구독 화면 조회
  void logSubscriptionViewed() {
    logEvent('subscription_viewed');
  }

  // 설정 변경
  void logSettingsChanged(String setting, String value) {
    logEvent('settings_changed', {'setting': setting, 'value': value});
  }
}

// ==================== 구독 관리 서비스 ====================

class SubscriptionService {
  static final SubscriptionService _instance = SubscriptionService._internal();
  factory SubscriptionService() => _instance;
  SubscriptionService._internal();

  // RevenueCat API 키
  static const String _apiKeyIOS = 'appl_RTTbxEwnpxhUZNsrKdmimCGYjdy';
  static const String _apiKeyAndroid = 'goog_EwguVFnVbUlHDvtNRKoQVjXhlFW';

  // 상품 ID
  static const String entitlementId = 'pro';
  static const String monthlyProductId = 'cover_pro_monthly';
  static const String yearlyProductId = 'cover_pro_yearly';
  static const String lifetimeProductId = 'cover_pro_lifetime';

  // 구독 상태
  final ValueNotifier<bool> isPro = ValueNotifier(false);
  CustomerInfo? _customerInfo;
  bool _isConfigured = false;

  // 테스트 모드 (개발 중 Pro 기능 테스트용)
  static const bool _testModeEnabled = false; // 출시 모드
  bool _isTestPro = false; // 테스트 모드에서 Pro 상태 (false = 무료 사용자)

  // 초기화
  Future<void> initialize() async {
    try {
      final apiKey = Platform.isIOS ? _apiKeyIOS : _apiKeyAndroid;

      // 실제 API 키가 설정되지 않은 경우 건너뛰기
      if (apiKey.contains('YOUR_')) {
        debugPrint('RevenueCat: API 키가 설정되지 않음 - 테스트 모드');
        _isConfigured = false;
        return;
      }

      await Purchases.configure(PurchasesConfiguration(apiKey));
      _isConfigured = true;

      // Firebase App Instance ID를 RevenueCat에 연결 (구매 기록 추적용)
      try {
        final appInstanceId = await FirebaseAnalytics.instance.appInstanceId;
        if (appInstanceId != null) {
          await Purchases.setFirebaseAppInstanceId(appInstanceId);
        }
      } catch (e) {
        debugPrint('Firebase App Instance ID 설정 오류: $e');
      }

      // 구독 상태 확인
      await _refreshPurchaseStatus();

      // 구독 상태 변경 리스너
      Purchases.addCustomerInfoUpdateListener((info) {
        _customerInfo = info;
        _updateProStatus();
      });
    } catch (e) {
      debugPrint('RevenueCat 초기화 오류: $e');
      _isConfigured = false;
    }
  }

  // 구독 상태 새로고침
  Future<void> _refreshPurchaseStatus() async {
    if (!_isConfigured) return;
    try {
      _customerInfo = await Purchases.getCustomerInfo();
      _updateProStatus();
    } catch (e) {
      debugPrint('구독 상태 확인 오류: $e');
    }
  }

  // Pro 상태 업데이트
  void _updateProStatus() {
    final entitlement = _customerInfo?.entitlements.active[entitlementId];
    isPro.value = entitlement?.isActive ?? false;
  }

  // 상품 정보 가져오기
  Future<List<Package>?> getOfferings() async {
    if (!_isConfigured) return null;
    try {
      final offerings = await Purchases.getOfferings();
      return offerings.current?.availablePackages;
    } catch (e) {
      debugPrint('상품 정보 가져오기 오류: $e');
      return null;
    }
  }

  // 구매 처리
  Future<bool> purchasePackage(Package package) async {
    if (!_isConfigured) return false;
    try {
      final result = await Purchases.purchasePackage(package);
      _customerInfo = result;
      _updateProStatus();

      // Firebase Analytics에 구매 이벤트 기록
      if (isPro.value) {
        await FirebaseAnalytics.instance.logPurchase(
          currency: 'KRW',
          value: package.storeProduct.price,
          items: [
            AnalyticsEventItem(
              itemId: package.storeProduct.identifier,
              itemName: package.storeProduct.title,
              price: package.storeProduct.price,
            ),
          ],
        );
      }

      return isPro.value;
    } catch (e) {
      if (e is PurchasesErrorCode) {
        if (e == PurchasesErrorCode.purchaseCancelledError) {
          debugPrint('사용자가 구매를 취소함');
        }
      }
      debugPrint('구매 오류: $e');
      return false;
    }
  }

  // 구매 복원
  Future<bool> restorePurchases() async {
    if (!_isConfigured) return false;
    try {
      _customerInfo = await Purchases.restorePurchases();
      _updateProStatus();
      return isPro.value;
    } catch (e) {
      debugPrint('구매 복원 오류: $e');
      return false;
    }
  }

  // Pro 상태 확인
  bool get isProUser {
    // 테스트 모드에서는 _isTestPro 값 사용
    if (_testModeEnabled && !_isConfigured) {
      return _isTestPro;
    }
    return isPro.value;
  }

  // 테스트 모드에서 Pro 상태 토글 (설정 화면에서 사용)
  void toggleTestPro() {
    if (_testModeEnabled) {
      _isTestPro = !_isTestPro;
      isPro.value = _isTestPro;
    }
  }

  // 테스트 모드 여부
  bool get isTestMode => _testModeEnabled && !_isConfigured;
}

// ==================== 저장 횟수 제한 서비스 ====================

class SaveLimitService {
  static const String _saveCountKey = 'daily_save_count';
  static const String _saveDateKey = 'save_date';
  static const int maxFreeSavesPerDay = 5;

  // 오늘 저장 횟수 가져오기
  static Future<int> getTodaySaveCount() async {
    final prefs = await SharedPreferences.getInstance();
    final savedDate = prefs.getString(_saveDateKey);
    final today = DateTime.now().toIso8601String().substring(0, 10);

    // 날짜가 다르면 카운트 리셋
    if (savedDate != today) {
      await prefs.setString(_saveDateKey, today);
      await prefs.setInt(_saveCountKey, 0);
      return 0;
    }

    return prefs.getInt(_saveCountKey) ?? 0;
  }

  // 저장 가능 여부 확인
  static Future<bool> canSave() async {
    final subscription = SubscriptionService();
    if (subscription.isProUser) {
      return true;
    }
    final count = await getTodaySaveCount();
    return count < maxFreeSavesPerDay;
  }

  // 남은 저장 횟수
  static Future<int> getRemainingCount() async {
    final subscription = SubscriptionService();
    if (subscription.isProUser) {
      return -1; // 무제한
    }
    final count = await getTodaySaveCount();
    return maxFreeSavesPerDay - count;
  }

  // 저장 횟수 증가
  static Future<void> incrementSaveCount() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    await prefs.setString(_saveDateKey, today);
    final currentCount = await getTodaySaveCount();
    await prefs.setInt(_saveCountKey, currentCount + 1);
  }
}

// ==================== 광고 서비스 ====================

class AdService {
  static final AdService _instance = AdService._internal();
  factory AdService() => _instance;
  AdService._internal();

  // 전면 광고 ID (디버그: 테스트 ID, 릴리즈: 실제 ID)
  static String get interstitialAdUnitId {
    if (kDebugMode) {
      // 테스트 광고 ID
      return Platform.isIOS
          ? 'ca-app-pub-3940256099942544/4411468910'
          : 'ca-app-pub-3940256099942544/1033173712';
    }
    // 실제 광고 ID
    return Platform.isIOS
        ? 'ca-app-pub-3438920793636799/2729421253'
        : 'ca-app-pub-3438920793636799/8197370353';
  }

  InterstitialAd? _interstitialAd;
  bool _isInterstitialReady = false;

  // 초기화
  Future<void> initialize() async {
    try {
      await MobileAds.instance.initialize();
      _loadInterstitialAd();
    } catch (e) {
      debugPrint('AdMob 초기화 오류: $e');
    }
  }

  // 전면 광고 로드
  void _loadInterstitialAd() {
    InterstitialAd.load(
      adUnitId: interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _isInterstitialReady = true;
          _interstitialAd!.setImmersiveMode(true);
        },
        onAdFailedToLoad: (error) {
          debugPrint('전면 광고 로드 실패: $error');
          _isInterstitialReady = false;
        },
      ),
    );
  }

  // 전면 광고 표시 (Pro 유저가 아닌 경우만)
  Future<void> showInterstitialAd({VoidCallback? onAdClosed}) async {
    // Pro 유저는 광고 안 보여줌
    if (SubscriptionService().isProUser) {
      onAdClosed?.call();
      return;
    }

    if (_isInterstitialReady && _interstitialAd != null) {
      _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (ad) {
          ad.dispose();
          _isInterstitialReady = false;
          _loadInterstitialAd(); // 다음 광고 로드
          onAdClosed?.call();
        },
        onAdFailedToShowFullScreenContent: (ad, error) {
          ad.dispose();
          _isInterstitialReady = false;
          _loadInterstitialAd();
          onAdClosed?.call();
        },
      );
      await _interstitialAd!.show();
    } else {
      onAdClosed?.call();
    }
  }

}

// 네이티브 광고 위젯
class NativeAdWidget extends StatefulWidget {
  const NativeAdWidget({super.key});

  @override
  State<NativeAdWidget> createState() => _NativeAdWidgetState();
}

class _NativeAdWidgetState extends State<NativeAdWidget> {
  NativeAd? _nativeAd;
  bool _isLoaded = false;

  // 네이티브 광고 ID (디버그: 테스트 ID, 릴리즈: 실제 ID)
  static String get nativeAdUnitId {
    if (kDebugMode) {
      // 테스트 광고 ID
      return Platform.isIOS
          ? 'ca-app-pub-3940256099942544/3986624511'
          : 'ca-app-pub-3940256099942544/2247696110';
    }
    // 실제 광고 ID
    return Platform.isIOS
        ? 'ca-app-pub-3438920793636799/1091431175'
        : 'ca-app-pub-3438920793636799/3384027376';
  }

  @override
  void initState() {
    super.initState();
    _loadAd();
  }

  void _loadAd() {
    _nativeAd = NativeAd(
      adUnitId: nativeAdUnitId,
      listener: NativeAdListener(
        onAdLoaded: (ad) {
          if (mounted) {
            setState(() => _isLoaded = true);
          }
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('네이티브 광고 로드 실패: $error');
          ad.dispose();
        },
      ),
      request: const AdRequest(),
      factoryId: 'listTile',
    )..load();
  }

  @override
  void dispose() {
    _nativeAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Pro 유저는 광고 안 보여줌
    if (SubscriptionService().isProUser) {
      return const SizedBox.shrink();
    }

    if (!_isLoaded || _nativeAd == null) {
      return const SizedBox(height: 136);
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: 136,
          child: AdWidget(ad: _nativeAd!),
        ),
      ),
    );
  }
}

// 최근 편집 이미지 관리
class RecentImages {
  static const String _key = 'recent_images';
  static const int _maxImages = 20;

  static Future<List<String>> getRecentImages() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_key) ?? [];
  }

  static Future<void> addImage(String path) async {
    final prefs = await SharedPreferences.getInstance();
    final images = prefs.getStringList(_key) ?? [];
    images.remove(path);
    images.insert(0, path);
    if (images.length > _maxImages) {
      images.removeRange(_maxImages, images.length);
    }
    await prefs.setStringList(_key, images);
  }

  static Future<void> removeImage(String path) async {
    final prefs = await SharedPreferences.getInstance();
    final images = prefs.getStringList(_key) ?? [];
    images.remove(path);
    await prefs.setStringList(_key, images);
  }
}

// ==================== 워터마크 설정 (Pro 전용) ====================

enum WatermarkPosition {
  topLeft, topCenter, topRight,
  centerLeft, center, centerRight,
  bottomLeft, bottomCenter, bottomRight
}

class WatermarkSettings {
  static const String _enabledKey = 'watermark_enabled';
  static const String _textKey = 'watermark_text';
  static const String _positionKey = 'watermark_position';
  static const String _opacityKey = 'watermark_opacity';

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? false;
  }

  static Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, enabled);
  }

  static Future<String> getText() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_textKey) ?? 'Cover';
  }

  static Future<void> setText(String text) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_textKey, text);
  }

  static Future<WatermarkPosition> getPosition() async {
    final prefs = await SharedPreferences.getInstance();
    final index = prefs.getInt(_positionKey) ?? 8; // default: bottomRight
    return WatermarkPosition.values[index];
  }

  static Future<void> setPosition(WatermarkPosition position) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_positionKey, position.index);
  }

  static Future<double> getOpacity() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_opacityKey) ?? 0.5;
  }

  static Future<void> setOpacity(double opacity) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_opacityKey, opacity);
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase Analytics 초기화
  await AnalyticsService().initialize();

  // RevenueCat 초기화
  await SubscriptionService().initialize();

  // AdMob 초기화
  await AdService().initialize();

  runApp(const CoverApp());
}

class CoverApp extends StatelessWidget {
  const CoverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, themeMode, child) {
        return MaterialApp(
          title: 'Cover',
          debugShowCheckedModeBanner: false,
          themeMode: themeMode,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF2196F3),
              brightness: Brightness.light,
            ),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF2196F3),
              brightness: Brightness.dark,
            ),
            useMaterial3: true,
            scaffoldBackgroundColor: Colors.black,
          ),
          home: const SplashScreen(),
        );
      },
    );
  }
}

// ==================== Splash Screen ====================

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkFirstLaunch();
  }

  Future<void> _checkFirstLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    final hasSeenOnboarding = prefs.getBool('has_seen_onboarding') ?? false;

    if (!mounted) return;

    if (hasSeenOnboarding) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const HomeScreen()),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const OnboardingScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: const Color(0xFF2196F3),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(
                Icons.shield,
                size: 60,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Cover',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== Onboarding Screen ====================

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<OnboardingPage> _pages = [
    OnboardingPage(
      icon: Icons.shield,
      title: '개인정보를 안전하게',
      description: '사진 속 민감한 정보를\n3초 만에 블러 처리하세요',
      color: const Color(0xFF2196F3),
    ),
    OnboardingPage(
      icon: Icons.blur_on,
      title: '다양한 편집 도구',
      description: '블러, 모자이크, 검정 바,\n하이라이터 등 다양한 도구 제공',
      color: const Color(0xFF9C27B0),
    ),
    OnboardingPage(
      icon: Icons.text_fields,
      title: '텍스트 & 스티커',
      description: '텍스트와 스티커로\n더 창의적인 편집이 가능해요',
      color: const Color(0xFF4CAF50),
    ),
    OnboardingPage(
      icon: Icons.share,
      title: '저장 & 공유',
      description: '편집한 이미지를 갤러리에 저장하고\n바로 공유하세요',
      color: const Color(0xFFFF9800),
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_seen_onboarding', true);

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const HomeScreen()),
    );
  }

  void _nextPage() {
    if (_currentPage < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _completeOnboarding();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Skip button
            Align(
              alignment: Alignment.topRight,
              child: TextButton(
                onPressed: _completeOnboarding,
                child: Text(
                  '건너뛰기',
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 16,
                  ),
                ),
              ),
            ),
            // Page content
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _pages.length,
                onPageChanged: (index) {
                  setState(() => _currentPage = index);
                },
                itemBuilder: (context, index) {
                  return _buildPage(_pages[index]);
                },
              ),
            ),
            // Page indicator
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  _pages.length,
                  (index) => AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: _currentPage == index ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _currentPage == index
                          ? _pages[_currentPage].color
                          : Colors.grey[700],
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
            ),
            // Next/Start button
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _nextPage,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _pages[_currentPage].color,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(
                    _currentPage == _pages.length - 1 ? '시작하기' : '다음',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPage(OnboardingPage page) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 160,
            height: 160,
            decoration: BoxDecoration(
              color: page.color.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              page.icon,
              size: 80,
              color: page.color,
            ),
          ),
          const SizedBox(height: 48),
          Text(
            page.title,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            page.description,
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[400],
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class OnboardingPage {
  final IconData icon;
  final String title;
  final String description;
  final Color color;

  OnboardingPage({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
  });
}

// ==================== Home Screen ====================

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ImagePicker _picker = ImagePicker();
  bool _isLoading = false;
  List<String> _recentImages = [];

  @override
  void initState() {
    super.initState();
    _loadRecentImages();
  }

  Future<void> _loadRecentImages() async {
    final images = await RecentImages.getRecentImages();
    // 존재하는 파일만 필터링
    final existingImages = <String>[];
    for (final path in images) {
      if (await File(path).exists()) {
        existingImages.add(path);
      }
    }
    if (mounted) {
      setState(() => _recentImages = existingImages);
    }
  }

  Future<void> _pickFromGallery() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 100,
      );

      if (image != null && mounted) {
        AnalyticsService().logImageImported('gallery');
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => EditorScreen(imageFile: File(image.path)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('이미지를 불러올 수 없습니다: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickFromCamera() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 100,
      );

      if (image != null && mounted) {
        AnalyticsService().logImageImported('camera');
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => EditorScreen(imageFile: File(image.path)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('카메라를 사용할 수 없습니다: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _openRecentImage(String path) async {
    final file = File(path);
    if (await file.exists()) {
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => EditorScreen(imageFile: file),
          ),
        ).then((_) => _loadRecentImages());
      }
    } else {
      await RecentImages.removeImage(path);
      _loadRecentImages();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('파일을 찾을 수 없습니다')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtitleColor = isDark ? Colors.white70 : Colors.black54;

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  children: [
                    const SizedBox(height: 40),
                    Stack(
                      alignment: Alignment.bottomCenter,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 24),
                          child: Image.asset(
                            'assets/images/logo.png',
                            height: 280,
                          ),
                        ),
                        Text(
                          'Cover',
                          style: TextStyle(
                            fontSize: 56,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 48),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton.icon(
                        onPressed: _isLoading ? null : _pickFromGallery,
                        icon: const Icon(Icons.photo_library_rounded),
                        label: const Text('갤러리', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2196F3),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: OutlinedButton.icon(
                        onPressed: _isLoading ? null : _pickFromCamera,
                        icon: const Icon(Icons.camera_alt_rounded),
                        label: const Text('카메라', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: textColor,
                          side: BorderSide(color: subtitleColor),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                        ),
                      ),
                    ),
                    // 네이티브 광고
                    const SizedBox(height: 24),
                    const NativeAdWidget(),

                    // 최근 편집 이미지
                    if (_recentImages.isNotEmpty) ...[
                      const SizedBox(height: 48),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '최근 이미지',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: textColor,
                            ),
                          ),
                          TextButton(
                            onPressed: () async {
                              final prefs = await SharedPreferences.getInstance();
                              await prefs.remove('recent_images');
                              _loadRecentImages();
                            },
                            child: Text(
                              '모두 지우기',
                              style: TextStyle(color: subtitleColor, fontSize: 14),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 120,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: _recentImages.length,
                          itemBuilder: (context, index) {
                            final path = _recentImages[index];
                            return Padding(
                              padding: EdgeInsets.only(
                                right: index < _recentImages.length - 1 ? 12 : 0,
                              ),
                              child: GestureDetector(
                                onTap: () => _openRecentImage(path),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: SizedBox(
                                    width: 120,
                                    height: 120,
                                    child: Image.file(
                                      File(path),
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, stackTrace) {
                                        return Container(
                                          color: Colors.grey[800],
                                          child: const Icon(Icons.broken_image, color: Colors.white38),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
            if (_isLoading)
              Container(
                color: Colors.black54,
                child: const Center(child: CircularProgressIndicator(color: Color(0xFF2196F3))),
              ),
            // 설정 버튼 (Stack 위에 표시)
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: Icon(Icons.settings_outlined, color: subtitleColor),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const SettingsScreen()),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== Editor Screen ====================

enum EditTool { blur, mosaic, eraser, blackBar, highlighter, sticker, text }

enum DrawMode { brush, rectangle, circle }

// 텍스트 오버레이 데이터 모델
class TextOverlayData {
  String text;
  Offset position; // 정규화된 좌표 (0.0 ~ 1.0)
  double scale;
  double rotation;
  Color color;
  Color backgroundColor;
  bool hasBackground;
  String fontStyle; // 'normal', 'bold', 'italic'

  TextOverlayData({
    required this.text,
    required this.position,
    this.scale = 1.0,
    this.rotation = 0.0,
    this.color = Colors.white,
    this.backgroundColor = Colors.black,
    this.hasBackground = true,
    this.fontStyle = 'bold',
  });
}

// 스티커 데이터 모델
class StickerData {
  String content; // 이모지 또는 텍스트
  Offset position;
  double scale;
  double rotation;
  bool isEmoji;

  StickerData({
    required this.content,
    required this.position,
    this.scale = 1.0,
    this.rotation = 0.0,
    this.isEmoji = true,
  });

  StickerData copyWith({
    String? content,
    Offset? position,
    double? scale,
    double? rotation,
    bool? isEmoji,
  }) {
    return StickerData(
      content: content ?? this.content,
      position: position ?? this.position,
      scale: scale ?? this.scale,
      rotation: rotation ?? this.rotation,
      isEmoji: isEmoji ?? this.isEmoji,
    );
  }
}

// 스티커 프리셋
class StickerPresets {
  static const List<String> emojis = [
    '😊', '😎', '🙈', '😴', '🤫', '🫣',
    '❤️', '⭐', '✨', '🔥', '💯', '👍',
    '🚫', '⛔', '🔒', '👀', '💬', '📍',
  ];

  static const List<String> shapes = [
    '⬛', '⬜', '🔴', '🟡', '🟢', '🔵',
    '◼️', '◻️', '●', '○', '★', '♥️',
  ];

  static const List<String> labels = [
    'PRIVATE',
    'CENSORED',
    'BLOCKED',
    'NO PHOTO',
    '비공개',
    '모자이크',
  ];
}

// 브러시 프리셋
enum BrushPreset { small, medium, large }

// 이미지 품질 프리셋
enum ImageQuality { low, medium, high, original }

extension ImageQualitySettings on ImageQuality {
  int get jpegQuality {
    switch (this) {
      case ImageQuality.low:
        return 60;
      case ImageQuality.medium:
        return 80;
      case ImageQuality.high:
        return 90;
      case ImageQuality.original:
        return 100;
    }
  }

  String get label {
    switch (this) {
      case ImageQuality.low:
        return '낮음';
      case ImageQuality.medium:
        return '중간';
      case ImageQuality.high:
        return '높음';
      case ImageQuality.original:
        return '원본';
    }
  }

  String get description {
    switch (this) {
      case ImageQuality.low:
        return '60% • 파일 크기 최소';
      case ImageQuality.medium:
        return '80% • 균형잡힌 품질';
      case ImageQuality.high:
        return '90% • 고품질';
      case ImageQuality.original:
        return '100% • 최고 품질';
    }
  }
}

extension BrushPresetSize on BrushPreset {
  double get size {
    switch (this) {
      case BrushPreset.small:
        return 25.0;
      case BrushPreset.medium:
        return 50.0;
      case BrushPreset.large:
        return 80.0;
    }
  }

  String get label {
    switch (this) {
      case BrushPreset.small:
        return 'S';
      case BrushPreset.medium:
        return 'M';
      case BrushPreset.large:
        return 'L';
    }
  }
}

class EditorScreen extends StatefulWidget {
  final File imageFile;
  const EditorScreen({super.key, required this.imageFile});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  // 이미지 데이터
  Uint8List? _originalBytes;
  Uint8List? _currentBytes;
  ui.Image? _displayImage;
  ui.Image? _originalDisplayImage; // 원본 이미지 캐시

  // 비교 모드
  bool _showingOriginal = false;
  bool _compareMode = false;
  double _compareSliderValue = 0.5;

  // 편집 상태
  EditTool _currentTool = EditTool.blur;
  DrawMode _drawMode = DrawMode.brush;
  double _brushSize = 40.0;
  double _intensity = 0.5;
  bool _isProcessing = false;
  Color _highlighterColor = Colors.yellow;

  // 현재 스트로크
  List<Offset> _currentStroke = [];

  // 도형 그리기용
  Offset? _shapeStart;
  Offset? _shapeEnd;

  // 핀치 줌
  double _scale = 1.0;
  double _previousScale = 1.0;
  Offset _offset = Offset.zero;
  Offset _previousOffset = Offset.zero;

  // 이미지 회전
  int _rotation = 0; // 0, 90, 180, 270

  // Undo/Redo 스택
  final List<Uint8List> _undoStack = [];
  final List<Uint8List> _redoStack = [];

  // 스티커
  final List<StickerData> _stickers = [];
  int? _selectedStickerIndex;
  Offset? _stickerDragStart;
  double _initialStickerScale = 1.0;

  // 텍스트 오버레이 관련
  final List<TextOverlayData> _textOverlays = [];
  int? _selectedTextIndex;
  double _initialTextScale = 1.0;
  Color _currentTextColor = Colors.white;
  Color _currentTextBgColor = Colors.black;
  bool _textHasBackground = true;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    setState(() => _isProcessing = true);

    try {
      final bytes = await widget.imageFile.readAsBytes();

      // 이미지 리사이즈 (최대 1500px)
      final resizedBytes = await compute(_resizeImage, bytes);

      _originalBytes = resizedBytes;
      _currentBytes = resizedBytes;

      await _updateDisplayImage(resizedBytes);

      // 원본 이미지 캐시
      final codec = await ui.instantiateImageCodec(resizedBytes);
      final frame = await codec.getNextFrame();
      _originalDisplayImage = frame.image;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('이미지 로드 실패: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  static Uint8List _resizeImage(Uint8List bytes) {
    final image = img.decodeImage(bytes);
    if (image == null) return bytes;

    const maxSize = 1500;
    if (image.width <= maxSize && image.height <= maxSize) {
      return bytes;
    }

    final resized = img.copyResize(
      image,
      width: image.width > image.height ? maxSize : null,
      height: image.height >= image.width ? maxSize : null,
      interpolation: img.Interpolation.linear,
    );

    return Uint8List.fromList(img.encodeJpg(resized, quality: 90));
  }

  Future<void> _updateDisplayImage(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    if (mounted) {
      setState(() => _displayImage = frame.image);
    }
  }

  void _onPanStart(DragStartDetails details, Size canvasSize) {
    if (_isProcessing || _displayImage == null) return;

    final imagePoint = _canvasToImage(details.localPosition, canvasSize);
    if (imagePoint != null) {
      setState(() {
        if (_drawMode == DrawMode.brush) {
          _currentStroke = [imagePoint];
        } else {
          _shapeStart = imagePoint;
          _shapeEnd = imagePoint;
        }
      });
    }
  }

  void _onPanUpdate(DragUpdateDetails details, Size canvasSize) {
    if (_isProcessing || _displayImage == null) return;

    final imagePoint = _canvasToImage(details.localPosition, canvasSize);
    if (imagePoint != null) {
      setState(() {
        if (_drawMode == DrawMode.brush) {
          _currentStroke.add(imagePoint);
        } else {
          _shapeEnd = imagePoint;
        }
      });
    }
  }

  void _onPanEnd(DragEndDetails details) async {
    if (_drawMode == DrawMode.brush && _currentStroke.isEmpty) return;
    if (_drawMode != DrawMode.brush && (_shapeStart == null || _shapeEnd == null)) return;
    if (_currentBytes == null) return;

    setState(() => _isProcessing = true);

    try {
      // Undo 스택에 현재 상태 저장
      _undoStack.add(_currentBytes!);
      _redoStack.clear();
      if (_undoStack.length > 10) _undoStack.removeAt(0);

      // 처리 요청 생성
      final request = ProcessRequest(
        imageBytes: _currentBytes!,
        points: _drawMode == DrawMode.brush
            ? _currentStroke.map((p) => [p.dx, p.dy]).toList()
            : [],
        brushSize: _brushSize,
        intensity: _intensity,
        tool: _currentTool,
        originalBytes: _originalBytes!,
        drawMode: _drawMode,
        shapeStart: _shapeStart != null ? [_shapeStart!.dx, _shapeStart!.dy] : null,
        shapeEnd: _shapeEnd != null ? [_shapeEnd!.dx, _shapeEnd!.dy] : null,
        highlighterColor: _highlighterColor.toARGB32(),
      );

      final processedBytes = await compute(_processImage, request);

      _currentBytes = processedBytes;
      await _updateDisplayImage(processedBytes);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('처리 실패: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _currentStroke = [];
          _shapeStart = null;
          _shapeEnd = null;
          _isProcessing = false;
        });
      }
    }
  }

  void _rotateImage() async {
    if (_currentBytes == null || _isProcessing) return;

    setState(() => _isProcessing = true);

    try {
      _undoStack.add(_currentBytes!);
      _redoStack.clear();
      if (_undoStack.length > 10) _undoStack.removeAt(0);

      final rotatedBytes = await compute(_rotateImageBytes, _currentBytes!);
      _currentBytes = rotatedBytes;

      // 원본도 회전 (지우개가 올바르게 동작하도록)
      _originalBytes = await compute(_rotateImageBytes, _originalBytes!);

      await _updateDisplayImage(rotatedBytes);

      setState(() => _rotation = (_rotation + 90) % 360);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('회전 실패: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _resetZoom() {
    setState(() {
      _scale = 1.0;
      _offset = Offset.zero;
    });
  }

  Future<void> _cropImage() async {
    if (_currentBytes == null || _isProcessing) return;

    setState(() => _isProcessing = true);

    try {
      // 현재 이미지를 임시 파일로 저장
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/crop_temp_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await tempFile.writeAsBytes(_currentBytes!);

      // image_cropper 실행
      final croppedFile = await ImageCropper().cropImage(
        sourcePath: tempFile.path,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: '이미지 자르기',
            toolbarColor: Colors.black,
            toolbarWidgetColor: Colors.white,
            backgroundColor: Colors.black,
            activeControlsWidgetColor: const Color(0xFF2196F3),
            initAspectRatio: CropAspectRatioPreset.original,
            lockAspectRatio: false,
            aspectRatioPresets: [
              CropAspectRatioPreset.original,
              CropAspectRatioPreset.square,
              CropAspectRatioPreset.ratio4x3,
              CropAspectRatioPreset.ratio16x9,
              CropAspectRatioPreset.ratio3x2,
            ],
          ),
          IOSUiSettings(
            title: '이미지 자르기',
            cancelButtonTitle: '취소',
            doneButtonTitle: '완료',
            aspectRatioPresets: [
              CropAspectRatioPreset.original,
              CropAspectRatioPreset.square,
              CropAspectRatioPreset.ratio4x3,
              CropAspectRatioPreset.ratio16x9,
              CropAspectRatioPreset.ratio3x2,
            ],
            aspectRatioLockEnabled: false,
            resetAspectRatioEnabled: true,
            rotateButtonsHidden: false,
            rotateClockwiseButtonHidden: true,
          ),
        ],
      );

      // 임시 파일 삭제
      if (await tempFile.exists()) {
        await tempFile.delete();
      }

      if (croppedFile != null) {
        // Undo 스택에 현재 상태 저장
        _undoStack.add(_currentBytes!);
        _redoStack.clear();
        if (_undoStack.length > 10) _undoStack.removeAt(0);

        // 자른 이미지 로드
        final croppedBytes = await File(croppedFile.path).readAsBytes();

        // 원본도 업데이트 (지우개가 올바르게 동작하도록)
        _originalBytes = croppedBytes;
        _currentBytes = croppedBytes;

        await _updateDisplayImage(croppedBytes);

        // 자른 파일 삭제
        if (await File(croppedFile.path).exists()) {
          await File(croppedFile.path).delete();
        }

        // 줌 리셋
        _resetZoom();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('이미지가 잘렸습니다'),
              duration: Duration(seconds: 1),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('자르기 실패: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Offset? _canvasToImage(Offset canvasPoint, Size canvasSize) {
    if (_displayImage == null) return null;

    final imageSize = Size(_displayImage!.width.toDouble(), _displayImage!.height.toDouble());
    final fittedSize = applyBoxFit(BoxFit.contain, imageSize, canvasSize);

    final offsetX = (canvasSize.width - fittedSize.destination.width) / 2;
    final offsetY = (canvasSize.height - fittedSize.destination.height) / 2;

    final relativeX = (canvasPoint.dx - offsetX) / fittedSize.destination.width;
    final relativeY = (canvasPoint.dy - offsetY) / fittedSize.destination.height;

    if (relativeX < 0 || relativeX > 1 || relativeY < 0 || relativeY > 1) {
      return null;
    }

    return Offset(
      relativeX * imageSize.width,
      relativeY * imageSize.height,
    );
  }

  void _undo() {
    if (_undoStack.isEmpty || _isProcessing) return;

    setState(() => _isProcessing = true);

    _redoStack.add(_currentBytes!);
    _currentBytes = _undoStack.removeLast();

    _updateDisplayImage(_currentBytes!).then((_) {
      if (mounted) setState(() => _isProcessing = false);
    });
  }

  void _redo() {
    if (_redoStack.isEmpty || _isProcessing) return;

    setState(() => _isProcessing = true);

    _undoStack.add(_currentBytes!);
    _currentBytes = _redoStack.removeLast();

    _updateDisplayImage(_currentBytes!).then((_) {
      if (mounted) setState(() => _isProcessing = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('편집', style: TextStyle(color: Colors.white)),
        actions: [
          // 자르기 버튼
          IconButton(
            icon: const Icon(Icons.crop, color: Colors.white),
            onPressed: _cropImage,
            tooltip: '자르기',
          ),
          // 회전 버튼
          IconButton(
            icon: const Icon(Icons.rotate_right, color: Colors.white),
            onPressed: _rotateImage,
            tooltip: '회전',
          ),
          // 비교 모드 버튼
          IconButton(
            icon: Icon(
              Icons.compare,
              color: _compareMode ? const Color(0xFF2196F3) : Colors.white,
            ),
            onPressed: () {
              setState(() => _compareMode = !_compareMode);
            },
            tooltip: '원본 비교',
          ),
          // 줌 리셋
          if (_scale != 1.0)
            IconButton(
              icon: const Icon(Icons.fit_screen, color: Colors.white),
              onPressed: _resetZoom,
              tooltip: '원래 크기',
            ),
          IconButton(
            icon: Icon(Icons.undo, color: _undoStack.isNotEmpty ? Colors.white : Colors.white38),
            onPressed: _undoStack.isNotEmpty ? _undo : null,
          ),
          IconButton(
            icon: Icon(Icons.redo, color: _redoStack.isNotEmpty ? Colors.white : Colors.white38),
            onPressed: _redoStack.isNotEmpty ? _redo : null,
          ),
        ],
      ),
      body: Column(
        children: [
          // 캔버스 영역
          Expanded(
            child: _displayImage == null
                ? const Center(child: CircularProgressIndicator())
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final canvasSize = Size(constraints.maxWidth, constraints.maxHeight);
                      return Stack(
                        children: [
                          GestureDetector(
                            onScaleStart: (details) {
                              _previousScale = _scale;
                              _previousOffset = _offset;
                              if (details.pointerCount == 1) {
                                _onPanStart(DragStartDetails(localPosition: details.localFocalPoint), canvasSize);
                              }
                            },
                            onScaleUpdate: (details) {
                              if (details.pointerCount == 2) {
                                // 핀치 줌
                                setState(() {
                                  _scale = (_previousScale * details.scale).clamp(0.5, 4.0);
                                  _offset = details.localFocalPoint - (_previousOffset + details.localFocalPoint) * details.scale + _previousOffset;
                                });
                              } else if (details.pointerCount == 1) {
                                _onPanUpdate(DragUpdateDetails(
                                  localPosition: details.localFocalPoint,
                                  globalPosition: details.focalPoint,
                                  delta: details.focalPointDelta,
                                ), canvasSize);
                              }
                            },
                            onScaleEnd: (details) {
                              if (details.pointerCount <= 1) {
                                _onPanEnd(DragEndDetails());
                              }
                            },
                            onLongPressStart: (_) {
                              if (_originalDisplayImage != null) {
                                setState(() => _showingOriginal = true);
                              }
                            },
                            onLongPressEnd: (_) {
                              setState(() => _showingOriginal = false);
                            },
                            child: ClipRect(
                              child: Transform(
                                transform: Matrix4.identity()
                                  ..translate(_offset.dx, _offset.dy)
                                  ..scale(_scale),
                                child: CustomPaint(
                                  size: canvasSize,
                                  painter: ImageCanvasPainter(
                                    image: _showingOriginal && _originalDisplayImage != null
                                        ? _originalDisplayImage!
                                        : _displayImage!,
                                    currentStroke: _showingOriginal ? [] : _currentStroke,
                                    brushSize: _brushSize,
                                    tool: _currentTool,
                                    drawMode: _drawMode,
                                    shapeStart: _showingOriginal ? null : _shapeStart,
                                    shapeEnd: _showingOriginal ? null : _shapeEnd,
                                    highlighterColor: _highlighterColor,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          // 원본 표시 중 오버레이
                          if (_showingOriginal)
                            Positioned(
                              top: 16,
                              left: 0,
                              right: 0,
                              child: Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.7),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.visibility, color: Colors.white, size: 18),
                                      SizedBox(width: 8),
                                      Text('원본', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          // 비교 모드 슬라이더 오버레이
                          if (_compareMode && _originalDisplayImage != null)
                            Positioned.fill(
                              child: _buildCompareOverlay(canvasSize),
                            ),
                          // 스티커 렌더링
                          if (!_showingOriginal)
                            ..._buildStickerWidgets(canvasSize),
                          // 텍스트 렌더링
                          if (!_showingOriginal)
                            ..._buildTextWidgets(canvasSize),
                        ],
                      );
                    },
                  ),
          ),

          // 로딩 표시
          if (_isProcessing)
            const LinearProgressIndicator(color: Color(0xFF2196F3)),

          // 하단 컨트롤 (고정 컴팩트 UI)
          Container(
            color: const Color(0xFF1A1A1A),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 1. 도구 선택 - 그리드
                    Column(
                      children: [
                        // 1행: 블러, 모자이크, 검은바, 형광펜
                        Row(
                          children: [
                            Expanded(child: _buildGridToolChip(EditTool.blur, Icons.blur_on, '블러')),
                            const SizedBox(width: 6),
                            Expanded(child: _buildGridToolChip(EditTool.mosaic, Icons.grid_view, '모자이크')),
                            const SizedBox(width: 6),
                            Expanded(child: _buildGridToolChip(EditTool.blackBar, Icons.rectangle, '검은바')),
                            const SizedBox(width: 6),
                            Expanded(child: _buildGridToolChip(EditTool.highlighter, Icons.highlight, '형광펜')),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // 2행: 지우개, 스티커, 텍스트
                        Row(
                          children: [
                            Expanded(child: _buildGridToolChip(EditTool.eraser, Icons.auto_fix_high, '지우개')),
                            const SizedBox(width: 6),
                            Expanded(child: _buildGridToolChip(EditTool.sticker, Icons.emoji_emotions, '스티커')),
                            const SizedBox(width: 6),
                            Expanded(child: _buildGridToolChip(EditTool.text, Icons.text_fields, '텍스트')),
                            const SizedBox(width: 6),
                            // 빈 공간
                            const Expanded(child: SizedBox()),
                          ],
                        ),
                      ],
                    ),

                    const SizedBox(height: 10),

                    // 2. 옵션 영역 - 고정 높이로 레이아웃 유지
                    SizedBox(
                      height: 130,
                      child: _currentTool == EditTool.sticker
                          ? _buildStickerControls()
                          : _currentTool == EditTool.text
                              ? _buildTextControls()
                              : Column(
                              children: [
                                // 모드 선택
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Text('모드 ', style: TextStyle(color: Colors.white54, fontSize: 11)),
                                    const SizedBox(width: 8),
                                    _buildCompactModeChip(DrawMode.brush, Icons.brush),
                                    _buildCompactModeChip(DrawMode.rectangle, Icons.crop_square),
                                    _buildCompactModeChip(DrawMode.circle, Icons.circle_outlined),
                                    // 색상 선택 (형광펜일 때만)
                                    if (_currentTool == EditTool.highlighter) ...[
                                      const SizedBox(width: 12),
                                      Container(width: 1, height: 24, color: Colors.white24),
                                      const SizedBox(width: 12),
                                      _buildColorChip(Colors.yellow, '노랑'),
                                      const SizedBox(width: 4),
                                      _buildColorChip(Colors.greenAccent, '초록'),
                                      const SizedBox(width: 4),
                                      _buildColorChip(Colors.pinkAccent, '분홍'),
                                      const SizedBox(width: 4),
                                      _buildColorChip(Colors.cyanAccent, '하늘'),
                                      const SizedBox(width: 4),
                                      _buildColorChip(Colors.orangeAccent, '주황'),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 10),
                                // 크기 슬라이더
                                _buildSliderRow(
                                  label: '크기',
                                  value: _brushSize,
                                  min: 10,
                                  max: 120,
                                  displayValue: '${_brushSize.toInt()}',
                                  onChanged: (v) => setState(() => _brushSize = v),
                                  presets: true,
                                ),
                                const SizedBox(height: 6),
                                // 강도 슬라이더
                                _buildSliderRow(
                                  label: '강도',
                                  value: _intensity,
                                  min: 0.1,
                                  max: 1.0,
                                  displayValue: '${(_intensity * 100).toInt()}%',
                                  onChanged: (v) => setState(() => _intensity = v),
                                  enabled: _currentTool != EditTool.eraser && _currentTool != EditTool.blackBar,
                                ),
                              ],
                            ),
                    ),

                    const SizedBox(height: 12),

                    // 3. 저장/공유 버튼
                    SizedBox(
                      height: 44,
                      child: Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _isProcessing ? null : _showSaveOptionsDialog,
                              icon: const Icon(Icons.save_alt, size: 18),
                              label: const Text('저장', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF2196F3),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _isProcessing ? null : _shareImage,
                              icon: const Icon(Icons.share, size: 18),
                              label: const Text('공유', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: const BorderSide(color: Colors.white38),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 비교 모드 오버레이
  Widget _buildCompareOverlay(Size canvasSize) {
    return GestureDetector(
      onHorizontalDragUpdate: (details) {
        setState(() {
          _compareSliderValue = (details.localPosition.dx / canvasSize.width).clamp(0.0, 1.0);
        });
      },
      onTapDown: (details) {
        setState(() {
          _compareSliderValue = (details.localPosition.dx / canvasSize.width).clamp(0.0, 1.0);
        });
      },
      child: Stack(
        children: [
          // 원본 이미지 (왼쪽)
          ClipRect(
            clipper: _CompareClipper(_compareSliderValue, isLeft: true),
            child: CustomPaint(
              size: canvasSize,
              painter: _CompareImagePainter(
                image: _originalDisplayImage!,
                scale: _scale,
                offset: _offset,
                rotation: _rotation,
              ),
            ),
          ),
          // 슬라이더 라인
          Positioned(
            left: canvasSize.width * _compareSliderValue - 2,
            top: 0,
            bottom: 0,
            child: Container(
              width: 4,
              color: Colors.white,
              child: Center(
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.compare_arrows, size: 20, color: Colors.black87),
                ),
              ),
            ),
          ),
          // 라벨
          Positioned(
            top: 16,
            left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Text('원본', style: TextStyle(color: Colors.white, fontSize: 12)),
            ),
          ),
          Positioned(
            top: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Text('편집', style: TextStyle(color: Colors.white, fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGridToolChip(EditTool tool, IconData icon, String label) {
    final isSelected = _currentTool == tool;
    return GestureDetector(
      onTap: () {
        setState(() => _currentTool = tool);
        AnalyticsService().logToolUsed(tool.name);
        if (tool == EditTool.sticker) {
          _showStickerPicker();
        } else if (tool == EditTool.text) {
          _showTextInputDialog();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF2196F3) : Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.white : Colors.white70,
              size: 20,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white70,
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactModeChip(DrawMode mode, IconData icon) {
    final isSelected = _drawMode == mode;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: GestureDetector(
        onTap: () => setState(() => _drawMode = mode),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF2196F3) : Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: isSelected ? Colors.white : Colors.white70, size: 18),
        ),
      ),
    );
  }

  // 스티커 선택 바텀시트
  void _showStickerPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.5,
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A1A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // 핸들
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // 탭
            Expanded(
              child: DefaultTabController(
                length: 3,
                child: Column(
                  children: [
                    const TabBar(
                      indicatorColor: Color(0xFF2196F3),
                      labelColor: Colors.white,
                      unselectedLabelColor: Colors.white54,
                      tabs: [
                        Tab(text: '이모지'),
                        Tab(text: '도형'),
                        Tab(text: '텍스트'),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          // 이모지 탭
                          _buildStickerGrid(StickerPresets.emojis, true),
                          // 도형 탭
                          _buildStickerGrid(StickerPresets.shapes, true),
                          // 텍스트 탭
                          _buildLabelGrid(StickerPresets.labels),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStickerGrid(List<String> items, bool isEmoji) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 6,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        return GestureDetector(
          onTap: () {
            Navigator.pop(context);
            _addSticker(items[index], isEmoji);
          },
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                items[index],
                style: const TextStyle(fontSize: 28),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLabelGrid(List<String> labels) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 2.5,
      ),
      itemCount: labels.length,
      itemBuilder: (context, index) {
        return GestureDetector(
          onTap: () {
            Navigator.pop(context);
            _addSticker(labels[index], false);
          },
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white24),
            ),
            child: Center(
              child: Text(
                labels[index],
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _addSticker(String content, bool isEmoji) {
    // 이미지 중앙에 스티커 추가
    if (_displayImage == null) return;

    setState(() {
      _stickers.add(StickerData(
        content: content,
        position: const Offset(0.5, 0.5), // 정규화된 좌표 (0~1)
        scale: 1.0,
        isEmoji: isEmoji,
      ));
      _selectedStickerIndex = _stickers.length - 1;
    });
  }

  Widget _buildStickerControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Row(
        children: [
          // 스티커 추가 버튼
          Expanded(
            child: GestureDetector(
              onTap: _showStickerPicker,
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF2196F3),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add, color: Colors.white, size: 20),
                    SizedBox(width: 6),
                    Text('스티커 추가', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ),
          if (_stickers.isNotEmpty) ...[
            const SizedBox(width: 10),
            // 선택된 스티커 삭제 버튼
            GestureDetector(
              onTap: _selectedStickerIndex != null ? _deleteSelectedSticker : null,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _selectedStickerIndex != null
                      ? Colors.red.withValues(alpha: 0.8)
                      : Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Icon(
                  Icons.delete_outline,
                  color: _selectedStickerIndex != null ? Colors.white : Colors.white38,
                  size: 20,
                ),
              ),
            ),
            const SizedBox(width: 6),
            // 모든 스티커 삭제 버튼
            GestureDetector(
              onTap: _clearAllStickers,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: const Icon(Icons.clear_all, color: Colors.white70, size: 20),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _deleteSelectedSticker() {
    if (_selectedStickerIndex != null && _selectedStickerIndex! < _stickers.length) {
      setState(() {
        _stickers.removeAt(_selectedStickerIndex!);
        _selectedStickerIndex = _stickers.isEmpty ? null : (_stickers.length - 1);
      });
    }
  }

  void _clearAllStickers() {
    setState(() {
      _stickers.clear();
      _selectedStickerIndex = null;
    });
  }

  // ========== 텍스트 오버레이 관련 ==========

  Widget _buildTextControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              // 텍스트 추가 버튼
              Expanded(
                child: GestureDetector(
                  onTap: _showTextInputDialog,
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2196F3),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add, color: Colors.white, size: 20),
                        SizedBox(width: 6),
                        Text('텍스트 추가', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ),
              if (_textOverlays.isNotEmpty) ...[
                const SizedBox(width: 10),
                // 선택된 텍스트 삭제 버튼
                GestureDetector(
                  onTap: _selectedTextIndex != null ? _deleteSelectedText : null,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: _selectedTextIndex != null
                          ? Colors.red.withValues(alpha: 0.8)
                          : Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Icon(
                      Icons.delete_outline,
                      color: _selectedTextIndex != null ? Colors.white : Colors.white38,
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // 모든 텍스트 삭제 버튼
                GestureDetector(
                  onTap: _clearAllTexts,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: const Icon(Icons.clear_all, color: Colors.white70, size: 20),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          // 색상 선택
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('글자 ', style: TextStyle(color: Colors.white54, fontSize: 11)),
              _buildTextColorChip(Colors.white, true),
              _buildTextColorChip(Colors.black, true),
              _buildTextColorChip(Colors.red, true),
              _buildTextColorChip(Colors.yellow, true),
              const SizedBox(width: 12),
              const Text('배경 ', style: TextStyle(color: Colors.white54, fontSize: 11)),
              _buildTextColorChip(Colors.black, false),
              _buildTextColorChip(Colors.white, false),
              _buildTextColorChip(Colors.transparent, false),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTextColorChip(Color color, bool isTextColor) {
    final isSelected = isTextColor
        ? _currentTextColor == color
        : (color == Colors.transparent ? !_textHasBackground : _currentTextBgColor == color && _textHasBackground);

    return GestureDetector(
      onTap: () {
        setState(() {
          if (isTextColor) {
            _currentTextColor = color;
          } else {
            if (color == Colors.transparent) {
              _textHasBackground = false;
            } else {
              _textHasBackground = true;
              _currentTextBgColor = color;
            }
          }
          // 선택된 텍스트가 있으면 바로 적용
          if (_selectedTextIndex != null && _selectedTextIndex! < _textOverlays.length) {
            if (isTextColor) {
              _textOverlays[_selectedTextIndex!].color = color;
            } else {
              _textOverlays[_selectedTextIndex!].hasBackground = color != Colors.transparent;
              if (color != Colors.transparent) {
                _textOverlays[_selectedTextIndex!].backgroundColor = color;
              }
            }
          }
        });
      },
      child: Container(
        width: 24,
        height: 24,
        margin: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          color: color == Colors.transparent ? null : color,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? const Color(0xFF2196F3) : Colors.white38,
            width: isSelected ? 3 : 1,
          ),
        ),
        child: color == Colors.transparent
            ? const Icon(Icons.not_interested, size: 16, color: Colors.white54)
            : null,
      ),
    );
  }

  void _showTextInputDialog() {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('텍스트 입력'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '텍스트를 입력하세요',
            border: OutlineInputBorder(),
          ),
          maxLines: 2,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                _addTextOverlay(controller.text);
              }
              Navigator.pop(context);
            },
            child: const Text('추가'),
          ),
        ],
      ),
    );
  }

  void _addTextOverlay(String text) {
    setState(() {
      _textOverlays.add(TextOverlayData(
        text: text,
        position: const Offset(0.5, 0.5),
        color: _currentTextColor,
        backgroundColor: _currentTextBgColor,
        hasBackground: _textHasBackground,
      ));
      _selectedTextIndex = _textOverlays.length - 1;
    });
  }

  void _deleteSelectedText() {
    if (_selectedTextIndex != null && _selectedTextIndex! < _textOverlays.length) {
      setState(() {
        _textOverlays.removeAt(_selectedTextIndex!);
        _selectedTextIndex = _textOverlays.isEmpty ? null : (_textOverlays.length - 1);
      });
    }
  }

  void _clearAllTexts() {
    setState(() {
      _textOverlays.clear();
      _selectedTextIndex = null;
    });
  }

  List<Widget> _buildTextWidgets(Size canvasSize) {
    if (_displayImage == null) return [];

    final imageAspect = _displayImage!.width / _displayImage!.height;
    final canvasAspect = canvasSize.width / canvasSize.height;

    double imageWidth, imageHeight;
    double offsetX = 0, offsetY = 0;

    if (imageAspect > canvasAspect) {
      imageWidth = canvasSize.width;
      imageHeight = canvasSize.width / imageAspect;
      offsetY = (canvasSize.height - imageHeight) / 2;
    } else {
      imageHeight = canvasSize.height;
      imageWidth = canvasSize.height * imageAspect;
      offsetX = (canvasSize.width - imageWidth) / 2;
    }

    return _textOverlays.asMap().entries.map((entry) {
      final index = entry.key;
      final textData = entry.value;
      final isSelected = _selectedTextIndex == index;

      final baseSize = 16.0 * textData.scale;
      final x = offsetX + textData.position.dx * imageWidth;
      final y = offsetY + textData.position.dy * imageHeight;

      return Positioned(
        left: x * _scale + _offset.dx,
        top: y * _scale + _offset.dy,
        child: GestureDetector(
          onTap: () {
            setState(() => _selectedTextIndex = index);
          },
          onScaleStart: (details) {
            setState(() => _selectedTextIndex = index);
            _initialTextScale = textData.scale;
          },
          onScaleUpdate: (details) {
            if (_selectedTextIndex == index) {
              setState(() {
                final dx = details.focalPointDelta.dx / (imageWidth * _scale);
                final dy = details.focalPointDelta.dy / (imageHeight * _scale);
                textData.position = Offset(
                  (textData.position.dx + dx).clamp(0.0, 1.0),
                  (textData.position.dy + dy).clamp(0.0, 1.0),
                );
                if (details.scale != 1.0) {
                  textData.scale = (_initialTextScale * details.scale).clamp(0.5, 4.0);
                }
              });
            }
          },
          child: Transform.scale(
            scale: _scale,
            child: Container(
              padding: textData.hasBackground
                  ? const EdgeInsets.symmetric(horizontal: 12, vertical: 6)
                  : EdgeInsets.zero,
              decoration: BoxDecoration(
                color: textData.hasBackground ? textData.backgroundColor : null,
                borderRadius: BorderRadius.circular(4),
                border: isSelected
                    ? Border.all(color: const Color(0xFF2196F3), width: 2)
                    : null,
              ),
              child: Text(
                textData.text,
                style: TextStyle(
                  color: textData.color,
                  fontSize: baseSize,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      );
    }).toList();
  }

  List<Widget> _buildStickerWidgets(Size canvasSize) {
    if (_displayImage == null) return [];

    // 이미지 영역 계산
    final imageAspect = _displayImage!.width / _displayImage!.height;
    final canvasAspect = canvasSize.width / canvasSize.height;

    double imageWidth, imageHeight;
    double offsetX = 0, offsetY = 0;

    if (imageAspect > canvasAspect) {
      imageWidth = canvasSize.width;
      imageHeight = canvasSize.width / imageAspect;
      offsetY = (canvasSize.height - imageHeight) / 2;
    } else {
      imageHeight = canvasSize.height;
      imageWidth = canvasSize.height * imageAspect;
      offsetX = (canvasSize.width - imageWidth) / 2;
    }

    return _stickers.asMap().entries.map((entry) {
      final index = entry.key;
      final sticker = entry.value;
      final isSelected = _selectedStickerIndex == index;

      // 스티커 기본 크기 (이모지 vs 텍스트)
      final baseSize = sticker.isEmoji ? 60.0 : 80.0;
      final stickerSize = baseSize * sticker.scale;

      // 정규화된 좌표를 실제 좌표로 변환
      final x = offsetX + sticker.position.dx * imageWidth - stickerSize / 2;
      final y = offsetY + sticker.position.dy * imageHeight - stickerSize / 2;

      return Positioned(
        left: x * _scale + _offset.dx,
        top: y * _scale + _offset.dy,
        child: GestureDetector(
          onTap: () {
            setState(() => _selectedStickerIndex = index);
          },
          onScaleStart: (details) {
            setState(() {
              _selectedStickerIndex = index;
              _stickerDragStart = sticker.position;
            });
            _initialStickerScale = sticker.scale;
          },
          onScaleUpdate: (details) {
            if (_selectedStickerIndex == index) {
              setState(() {
                // 드래그: focalPointDelta를 정규화된 좌표로 변환
                final dx = details.focalPointDelta.dx / (imageWidth * _scale);
                final dy = details.focalPointDelta.dy / (imageHeight * _scale);
                sticker.position = Offset(
                  (sticker.position.dx + dx).clamp(0.0, 1.0),
                  (sticker.position.dy + dy).clamp(0.0, 1.0),
                );
                // 스케일 (두 손가락 제스처)
                if (details.scale != 1.0) {
                  sticker.scale = (_initialStickerScale * details.scale).clamp(0.5, 3.0);
                }
              });
            }
          },
          child: Transform.scale(
            scale: _scale,
            child: Container(
              width: stickerSize,
              height: sticker.isEmoji ? stickerSize : stickerSize * 0.5,
              decoration: isSelected
                  ? BoxDecoration(
                      border: Border.all(color: const Color(0xFF2196F3), width: 2),
                      borderRadius: BorderRadius.circular(8),
                    )
                  : null,
              child: Center(
                child: sticker.isEmoji
                    ? Text(
                        sticker.content,
                        style: TextStyle(fontSize: stickerSize * 0.7),
                      )
                    : Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          sticker.content,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: stickerSize * 0.2,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ),
      );
    }).toList();
  }

  Widget _buildSliderRow({
    required String label,
    required double value,
    required double min,
    required double max,
    required String displayValue,
    required ValueChanged<double> onChanged,
    bool enabled = true,
    bool presets = false,
  }) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.3,
      child: IgnorePointer(
        ignoring: !enabled,
        child: SizedBox(
          height: 32,
          child: Row(
            children: [
              SizedBox(
                width: 30,
                child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
              ),
              if (presets) ...[
                for (final preset in BrushPreset.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: _buildPresetButton(preset),
                  ),
              ],
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                  ),
                  child: Slider(
                    value: value,
                    min: min,
                    max: max,
                    activeColor: const Color(0xFF2196F3),
                    inactiveColor: Colors.white24,
                    onChanged: onChanged,
                  ),
                ),
              ),
              SizedBox(
                width: 36,
                child: Text(
                  displayValue,
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildColorChip(Color color, String label) {
    final isSelected = _highlighterColor == color;
    return GestureDetector(
      onTap: () => setState(() => _highlighterColor = color),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.7),
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? Colors.white : Colors.transparent,
            width: 2,
          ),
        ),
      ),
    );
  }

  Widget _buildPresetButton(BrushPreset preset) {
    final isSelected = (_brushSize - preset.size).abs() < 5;
    return GestureDetector(
      onTap: () => setState(() => _brushSize = preset.size),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF2196F3) : Colors.white12,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            preset.label,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.white70,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }

  void _showSaveOptionsDialog() async {
    if (_currentBytes == null) return;

    final isPro = SubscriptionService().isProUser;
    final remainingCount = await SaveLimitService.getRemainingCount();

    // 무료 사용자가 저장 횟수를 모두 사용한 경우
    if (!isPro && remainingCount <= 0) {
      if (!mounted) return;
      _showUpgradeDialog(
        title: '일일 저장 횟수 초과',
        message: '오늘의 무료 저장 횟수(${SaveLimitService.maxFreeSavesPerDay}회)를 모두 사용했습니다.\nPro로 업그레이드하면 무제한으로 저장할 수 있습니다.',
      );
      return;
    }

    // 예상 파일 크기 계산
    final originalSize = _currentBytes!.length;
    String estimateSize(ImageQuality quality) {
      final estimatedBytes = (originalSize * quality.jpegQuality / 100).round();
      if (estimatedBytes < 1024) {
        return '$estimatedBytes B';
      } else if (estimatedBytes < 1024 * 1024) {
        return '${(estimatedBytes / 1024).toStringAsFixed(1)} KB';
      } else {
        return '${(estimatedBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
      }
    }

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A1A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 핸들
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // 타이틀
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    const Icon(Icons.high_quality, color: Colors.white, size: 24),
                    const SizedBox(width: 12),
                    const Text(
                      '저장 품질 선택',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    // 남은 저장 횟수 표시 (무료 사용자만)
                    if (!isPro)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: remainingCount <= 2
                              ? Colors.orange.withValues(alpha: 0.2)
                              : Colors.white.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '오늘 $remainingCount회 남음',
                          style: TextStyle(
                            color: remainingCount <= 2 ? Colors.orange : Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // 품질 옵션 (무료 사용자는 medium까지만)
              ...ImageQuality.values.map((quality) => _buildQualityOption(
                    quality,
                    estimateSize(quality),
                    isPro: isPro,
                  )),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQualityOption(ImageQuality quality, String estimatedSize, {required bool isPro}) {
    final isRecommended = quality == ImageQuality.high;
    // 무료 사용자는 medium(80%)까지만 사용 가능
    final isProOnly = !isPro && (quality == ImageQuality.high || quality == ImageQuality.original);
    final isDisabled = isProOnly;

    return InkWell(
      onTap: isDisabled
          ? () {
              Navigator.pop(context);
              _showUpgradeDialog(
                title: '고화질은 Pro 전용',
                message: '${quality.label} 화질(${quality.jpegQuality}%)로 저장하려면\nPro로 업그레이드하세요.',
              );
            }
          : () {
              Navigator.pop(context);
              _saveImageWithQuality(quality);
            },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isDisabled
                    ? Colors.white.withValues(alpha: 0.04)
                    : isRecommended
                        ? const Color(0xFF2196F3).withValues(alpha: 0.2)
                        : Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  '${quality.jpegQuality}%',
                  style: TextStyle(
                    color: isDisabled
                        ? Colors.white30
                        : isRecommended
                            ? const Color(0xFF2196F3)
                            : Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        quality.label,
                        style: TextStyle(
                          color: isDisabled ? Colors.white38 : Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (isProOnly) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'PRO',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ] else if (isRecommended && isPro) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2196F3),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            '추천',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    quality.description,
                    style: TextStyle(
                      color: isDisabled ? Colors.white24 : Colors.white54,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '~$estimatedSize',
              style: TextStyle(
                color: isDisabled ? Colors.white24 : Colors.white54,
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              isDisabled ? Icons.lock : Icons.chevron_right,
              color: isDisabled ? Colors.white24 : Colors.white38,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  // Pro 업그레이드 다이얼로그 표시
  void _showUpgradeDialog({required String title, required String message}) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.star, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(color: Colors.white, fontSize: 18),
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('나중에'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _showProSubscriptionSheet();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFD700),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Pro 보기'),
          ),
        ],
      ),
    );
  }

  // Pro 구독 시트 표시
  void _showProSubscriptionSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _ProSubscriptionSheet(),
    );
  }

  Future<void> _saveImageWithQuality(ImageQuality quality) async {
    if (_currentBytes == null) return;

    setState(() => _isProcessing = true);

    try {
      // 스티커가 있으면 합성
      Uint8List finalBytes = _currentBytes!;
      if (_stickers.isNotEmpty) {
        finalBytes = await compute(compositeStickers, CompositeRequest(
          imageBytes: finalBytes,
          stickers: _stickers.map((s) => StickerInfo(
            content: s.content,
            positionX: s.position.dx,
            positionY: s.position.dy,
            scale: s.scale,
            isEmoji: s.isEmoji,
          )).toList(),
        ));
      }

      // 텍스트 오버레이가 있으면 합성
      if (_textOverlays.isNotEmpty) {
        finalBytes = await compute(compositeTexts, TextCompositeRequest(
          imageBytes: finalBytes,
          texts: _textOverlays.map((t) => TextOverlayInfo(
            text: t.text,
            positionX: t.position.dx,
            positionY: t.position.dy,
            scale: t.scale,
            colorR: (t.color.r * 255.0).round().clamp(0, 255),
            colorG: (t.color.g * 255.0).round().clamp(0, 255),
            colorB: (t.color.b * 255.0).round().clamp(0, 255),
            bgColorR: (t.backgroundColor.r * 255.0).round().clamp(0, 255),
            bgColorG: (t.backgroundColor.g * 255.0).round().clamp(0, 255),
            bgColorB: (t.backgroundColor.b * 255.0).round().clamp(0, 255),
            hasBackground: t.hasBackground,
          )).toList(),
        ));
      }

      // 워터마크 적용 (Pro 유저만)
      debugPrint('워터마크 체크 - Pro: ${SubscriptionService().isProUser}');
      if (SubscriptionService().isProUser) {
        final watermarkEnabled = await WatermarkSettings.isEnabled();
        debugPrint('워터마크 활성화: $watermarkEnabled');
        if (watermarkEnabled) {
          final text = await WatermarkSettings.getText();
          final position = await WatermarkSettings.getPosition();
          final opacity = await WatermarkSettings.getOpacity();
          debugPrint('워터마크 적용 - 텍스트: $text, 위치: ${position.index}, 투명도: $opacity');

          finalBytes = await compute(compositeWatermark, WatermarkRequest(
            imageBytes: finalBytes,
            watermark: WatermarkInfo(
              text: text,
              positionIndex: position.index,
              opacity: opacity,
            ),
          ));
          debugPrint('워터마크 적용 완료');
        }
      }

      // 파일명 생성
      final timestamp = DateTime.now().toString().replaceAll(RegExp(r'[^0-9]'), '').substring(0, 14);
      final fileName = 'Cover_$timestamp';

      // 임시 파일에 저장 후 갤러리에 추가
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/$fileName.jpg');
      await tempFile.writeAsBytes(finalBytes);

      // 갤러리에 저장
      await Gal.putImage(tempFile.path, album: 'Cover');

      // 임시 파일 삭제
      await tempFile.delete();

      if (mounted) {
        // 최근 이미지에 원본 경로 추가
        await RecentImages.addImage(widget.imageFile.path);

        // 저장 횟수 증가 (무료 사용자)
        await SaveLimitService.incrementSaveCount();

        // Analytics 이벤트
        AnalyticsService().logImageSaved(quality: quality.label);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Text('${quality.label} 품질로 저장되었습니다'),
              ],
            ),
            backgroundColor: Colors.green,
          ),
        );

        // 저장 완료 후 전면 광고 표시 (Pro 유저 제외)
        AdService().showInterstitialAd();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('저장 오류: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _shareImage() async {
    if (_currentBytes == null) return;

    setState(() => _isProcessing = true);

    try {
      // 임시 파일 생성
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final tempFile = File('${tempDir.path}/Cover_$timestamp.jpg');
      await tempFile.writeAsBytes(_currentBytes!);

      // 공유
      await Share.shareXFiles(
        [XFile(tempFile.path)],
        text: 'Cover로 편집한 이미지',
      );

      // Analytics 이벤트
      AnalyticsService().logImageShared();

      // 임시 파일 삭제
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('공유 오류: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }
}

// ==================== Image Processing ====================

// 스티커 합성을 위한 데이터 클래스
class StickerInfo {
  final String content;
  final double positionX;
  final double positionY;
  final double scale;
  final bool isEmoji;

  StickerInfo({
    required this.content,
    required this.positionX,
    required this.positionY,
    required this.scale,
    required this.isEmoji,
  });
}

class CompositeRequest {
  final Uint8List imageBytes;
  final List<StickerInfo> stickers;

  CompositeRequest({
    required this.imageBytes,
    required this.stickers,
  });
}

// 스티커 합성 함수 (Isolate에서 실행)
Uint8List compositeStickers(CompositeRequest request) {
  final image = img.decodeImage(request.imageBytes);
  if (image == null) return request.imageBytes;

  for (final sticker in request.stickers) {
    // 스티커 위치 계산 (정규화된 좌표 -> 실제 좌표)
    final x = (sticker.positionX * image.width).toInt();
    final y = (sticker.positionY * image.height).toInt();

    // 스티커 크기 계산
    final baseSize = sticker.isEmoji ? 60 : 80;
    final size = (baseSize * sticker.scale).toInt();

    if (sticker.isEmoji) {
      // 이모지: 검은색 원으로 가리기 (이모지는 이미지로 렌더링 어려움)
      final halfSize = size ~/ 2;
      for (int dy = -halfSize; dy < halfSize; dy++) {
        for (int dx = -halfSize; dx < halfSize; dx++) {
          if (dx * dx + dy * dy <= halfSize * halfSize) {
            final px = x + dx;
            final py = y + dy;
            if (px >= 0 && px < image.width && py >= 0 && py < image.height) {
              image.setPixel(px, py, img.ColorRgba8(0, 0, 0, 255));
            }
          }
        }
      }
    } else {
      // 텍스트 라벨: 검은색 사각형으로 가리기
      final halfWidth = size ~/ 2;
      final halfHeight = size ~/ 4;
      for (int dy = -halfHeight; dy < halfHeight; dy++) {
        for (int dx = -halfWidth; dx < halfWidth; dx++) {
          final px = x + dx;
          final py = y + dy;
          if (px >= 0 && px < image.width && py >= 0 && py < image.height) {
            image.setPixel(px, py, img.ColorRgba8(0, 0, 0, 255));
          }
        }
      }
    }
  }

  return Uint8List.fromList(img.encodeJpg(image, quality: 95));
}

// 텍스트 오버레이 정보 클래스
class TextOverlayInfo {
  final String text;
  final double positionX;
  final double positionY;
  final double scale;
  final int colorR;
  final int colorG;
  final int colorB;
  final int bgColorR;
  final int bgColorG;
  final int bgColorB;
  final bool hasBackground;

  TextOverlayInfo({
    required this.text,
    required this.positionX,
    required this.positionY,
    required this.scale,
    required this.colorR,
    required this.colorG,
    required this.colorB,
    required this.bgColorR,
    required this.bgColorG,
    required this.bgColorB,
    required this.hasBackground,
  });
}

class TextCompositeRequest {
  final Uint8List imageBytes;
  final List<TextOverlayInfo> texts;

  TextCompositeRequest({
    required this.imageBytes,
    required this.texts,
  });
}

// 텍스트 합성 함수 (Isolate에서 실행)
Uint8List compositeTexts(TextCompositeRequest request) {
  final image = img.decodeImage(request.imageBytes);
  if (image == null) return request.imageBytes;

  for (final textInfo in request.texts) {
    // 텍스트 위치 계산 (정규화된 좌표 -> 실제 좌표)
    final x = (textInfo.positionX * image.width).toInt();
    final y = (textInfo.positionY * image.height).toInt();

    // 텍스트 크기 계산 (scale 기반)
    final baseWidth = (textInfo.text.length * 12 * textInfo.scale).toInt();
    final baseHeight = (24 * textInfo.scale).toInt();
    final padding = (4 * textInfo.scale).toInt();

    final halfWidth = baseWidth ~/ 2 + padding;
    final halfHeight = baseHeight ~/ 2 + padding;

    // 배경이 있으면 배경 사각형 그리기
    if (textInfo.hasBackground) {
      final bgColor = img.ColorRgba8(textInfo.bgColorR, textInfo.bgColorG, textInfo.bgColorB, 255);
      for (int dy = -halfHeight; dy < halfHeight; dy++) {
        for (int dx = -halfWidth; dx < halfWidth; dx++) {
          final px = x + dx;
          final py = y + dy;
          if (px >= 0 && px < image.width && py >= 0 && py < image.height) {
            image.setPixel(px, py, bgColor);
          }
        }
      }
    }

    // 텍스트 색상으로 테두리 표시 (텍스트 자체는 이미지로 렌더링 어려움)
    final textColor = img.ColorRgba8(textInfo.colorR, textInfo.colorG, textInfo.colorB, 255);
    final borderWidth = (2 * textInfo.scale).toInt().clamp(1, 4);

    // 상단 테두리
    for (int dy = -halfHeight; dy < -halfHeight + borderWidth; dy++) {
      for (int dx = -halfWidth; dx < halfWidth; dx++) {
        final px = x + dx;
        final py = y + dy;
        if (px >= 0 && px < image.width && py >= 0 && py < image.height) {
          image.setPixel(px, py, textColor);
        }
      }
    }
    // 하단 테두리
    for (int dy = halfHeight - borderWidth; dy < halfHeight; dy++) {
      for (int dx = -halfWidth; dx < halfWidth; dx++) {
        final px = x + dx;
        final py = y + dy;
        if (px >= 0 && px < image.width && py >= 0 && py < image.height) {
          image.setPixel(px, py, textColor);
        }
      }
    }
    // 좌측 테두리
    for (int dy = -halfHeight; dy < halfHeight; dy++) {
      for (int dx = -halfWidth; dx < -halfWidth + borderWidth; dx++) {
        final px = x + dx;
        final py = y + dy;
        if (px >= 0 && px < image.width && py >= 0 && py < image.height) {
          image.setPixel(px, py, textColor);
        }
      }
    }
    // 우측 테두리
    for (int dy = -halfHeight; dy < halfHeight; dy++) {
      for (int dx = halfWidth - borderWidth; dx < halfWidth; dx++) {
        final px = x + dx;
        final py = y + dy;
        if (px >= 0 && px < image.width && py >= 0 && py < image.height) {
          image.setPixel(px, py, textColor);
        }
      }
    }
  }

  return Uint8List.fromList(img.encodeJpg(image, quality: 95));
}

// 워터마크 정보 클래스
class WatermarkInfo {
  final String text;
  final int positionIndex; // 0-8 (topLeft to bottomRight)
  final double opacity;

  WatermarkInfo({
    required this.text,
    required this.positionIndex,
    required this.opacity,
  });
}

class WatermarkRequest {
  final Uint8List imageBytes;
  final WatermarkInfo watermark;

  WatermarkRequest({
    required this.imageBytes,
    required this.watermark,
  });
}

// 워터마크 합성 함수 (Isolate에서 실행)
Uint8List compositeWatermark(WatermarkRequest request) {
  final image = img.decodeImage(request.imageBytes);
  if (image == null) return request.imageBytes;

  final watermark = request.watermark;
  final text = watermark.text;
  if (text.isEmpty) return request.imageBytes;

  // 폰트 크기 계산 (이미지 크기에 비례)
  final scale = (image.width / 800).clamp(0.5, 3.0);
  final font = img.arial24;

  // 텍스트 크기 추정
  final charWidth = 14 * scale;
  final charHeight = 24 * scale;
  final textWidth = (text.length * charWidth).toInt();
  final textHeight = charHeight.toInt();
  final padding = (10 * scale).toInt();

  // 위치 계산 (9개 위치)
  final margin = (image.width * 0.03).toInt();
  int x, y;

  // 열 위치 (0: left, 1: center, 2: right)
  final col = watermark.positionIndex % 3;
  if (col == 0) {
    x = margin;
  } else if (col == 1) {
    x = (image.width - textWidth - padding * 2) ~/ 2;
  } else {
    x = image.width - textWidth - padding * 2 - margin;
  }

  // 행 위치 (0: top, 1: center, 2: bottom)
  final row = watermark.positionIndex ~/ 3;
  if (row == 0) {
    y = margin;
  } else if (row == 1) {
    y = (image.height - textHeight - padding * 2) ~/ 2;
  } else {
    y = image.height - textHeight - padding * 2 - margin;
  }

  final alpha = (watermark.opacity * 255).toInt().clamp(0, 255);

  // 반투명 배경 사각형 그리기
  final bgWidth = textWidth + padding * 2;
  final bgHeight = textHeight + padding * 2;

  for (int dy = 0; dy < bgHeight; dy++) {
    for (int dx = 0; dx < bgWidth; dx++) {
      final px = x + dx;
      final py = y + dy;
      if (px >= 0 && px < image.width && py >= 0 && py < image.height) {
        final oldPixel = image.getPixel(px, py);
        // 반투명 검은 배경 (50% 투명도 * 사용자 설정 투명도)
        final bgAlpha = 0.5 * watermark.opacity;
        final newR = (oldPixel.r * (1 - bgAlpha)).toInt().clamp(0, 255);
        final newG = (oldPixel.g * (1 - bgAlpha)).toInt().clamp(0, 255);
        final newB = (oldPixel.b * (1 - bgAlpha)).toInt().clamp(0, 255);
        image.setPixel(px, py, img.ColorRgba8(newR, newG, newB, 255));
      }
    }
  }

  // 텍스트 그리기 (흰색, 그림자 효과) - 중앙 정렬
  final textX = x + (bgWidth - textWidth) ~/ 2;
  final textY = y + (bgHeight - textHeight) ~/ 2;

  // 그림자 (검은색, 약간 오프셋)
  img.drawString(
    image,
    text,
    font: font,
    x: textX + 1,
    y: textY + 1,
    color: img.ColorRgba8(0, 0, 0, (alpha * 0.5).toInt()),
  );

  // 메인 텍스트 (흰색)
  img.drawString(
    image,
    text,
    font: font,
    x: textX,
    y: textY,
    color: img.ColorRgba8(255, 255, 255, alpha),
  );

  return Uint8List.fromList(img.encodeJpg(image, quality: 95));
}

class ProcessRequest {
  final Uint8List imageBytes;
  final List<List<double>> points;
  final double brushSize;
  final double intensity;
  final EditTool tool;
  final Uint8List originalBytes;
  final DrawMode drawMode;
  final List<double>? shapeStart;
  final List<double>? shapeEnd;
  final int highlighterColor;

  ProcessRequest({
    required this.imageBytes,
    required this.points,
    required this.brushSize,
    required this.intensity,
    required this.tool,
    required this.originalBytes,
    this.drawMode = DrawMode.brush,
    this.shapeStart,
    this.shapeEnd,
    this.highlighterColor = 0xFFFFFF00,
  });
}

// 이미지 회전 함수
Uint8List _rotateImageBytes(Uint8List bytes) {
  final image = img.decodeImage(bytes);
  if (image == null) return bytes;

  final rotated = img.copyRotate(image, angle: 90);
  return Uint8List.fromList(img.encodeJpg(rotated, quality: 90));
}

// 연속된 포인트들 사이를 보간하여 부드러운 선을 만드는 함수
List<Offset> _interpolatePoints(List<Offset> points, double maxDistance) {
  if (points.length < 2) return points;

  final result = <Offset>[points[0]];

  for (int i = 1; i < points.length; i++) {
    final prev = points[i - 1];
    final curr = points[i];
    final dx = curr.dx - prev.dx;
    final dy = curr.dy - prev.dy;
    final distance = sqrt(dx * dx + dy * dy);

    if (distance > maxDistance) {
      // 두 점 사이에 중간 점들을 추가
      final steps = (distance / maxDistance).ceil();
      for (int j = 1; j < steps; j++) {
        final t = j / steps;
        result.add(Offset(
          prev.dx + dx * t,
          prev.dy + dy * t,
        ));
      }
    }
    result.add(curr);
  }

  return result;
}

Uint8List _processImage(ProcessRequest request) {
  final image = img.decodeImage(request.imageBytes);
  if (image == null) return request.imageBytes;

  final rawPoints = request.points.map((p) => Offset(p[0], p[1])).toList();
  final radius = (request.brushSize / 2).toInt();

  // 포인트들 사이를 보간하여 끊김 없이 연결
  final maxGap = (radius * 0.5).clamp(2.0, 10.0);
  final points = _interpolatePoints(rawPoints, maxGap);

  // 도형 모드인 경우
  if (request.drawMode != DrawMode.brush && request.shapeStart != null && request.shapeEnd != null) {
    final start = Offset(request.shapeStart![0], request.shapeStart![1]);
    final end = Offset(request.shapeEnd![0], request.shapeEnd![1]);

    switch (request.tool) {
      case EditTool.blur:
        _applyShapeBlur(image, start, end, request.drawMode, request.intensity);
        break;
      case EditTool.mosaic:
        _applyShapeMosaic(image, start, end, request.drawMode, request.intensity);
        break;
      case EditTool.blackBar:
        _applyShapeBlackBar(image, start, end, request.drawMode);
        break;
      case EditTool.eraser:
        final original = img.decodeImage(request.originalBytes);
        if (original != null) {
          _applyShapeEraser(image, original, start, end, request.drawMode);
        }
        break;
      case EditTool.highlighter:
        _applyShapeHighlighter(image, start, end, request.drawMode, request.highlighterColor, request.intensity);
        break;
      case EditTool.sticker:
      case EditTool.text:
        break; // 스티커/텍스트는 별도 레이어에서 처리
    }
  } else {
    // 브러시 모드
    switch (request.tool) {
      case EditTool.blur:
        _applyBlur(image, points, radius, request.intensity);
        break;
      case EditTool.mosaic:
        _applyMosaic(image, points, radius, request.intensity);
        break;
      case EditTool.blackBar:
        _applyBlackBar(image, points, radius);
        break;
      case EditTool.highlighter:
        _applyHighlighter(image, points, radius, request.highlighterColor, request.intensity);
        break;
      case EditTool.eraser:
        final original = img.decodeImage(request.originalBytes);
        if (original != null) {
          _applyEraser(image, original, points, radius);
        }
        break;
      case EditTool.sticker:
      case EditTool.text:
        break; // 스티커/텍스트는 별도 레이어에서 처리
    }
  }

  return Uint8List.fromList(img.encodeJpg(image, quality: 90));
}

void _applyBlur(img.Image image, List<Offset> points, int radius, double intensity) {
  final blurRadius = (intensity * 15).toInt().clamp(1, 20);

  // 영향받는 영역 계산
  int minX = image.width, minY = image.height, maxX = 0, maxY = 0;

  for (final point in points) {
    final cx = point.dx.toInt();
    final cy = point.dy.toInt();
    minX = min(minX, cx - radius);
    minY = min(minY, cy - radius);
    maxX = max(maxX, cx + radius);
    maxY = max(maxY, cy + radius);
  }

  minX = minX.clamp(0, image.width - 1);
  minY = minY.clamp(0, image.height - 1);
  maxX = maxX.clamp(0, image.width - 1);
  maxY = maxY.clamp(0, image.height - 1);

  // 마스크 생성
  final mask = List.generate(
    maxY - minY + 1,
    (_) => List.filled(maxX - minX + 1, false),
  );

  for (final point in points) {
    final cx = point.dx.toInt();
    final cy = point.dy.toInt();

    for (int dy = -radius; dy <= radius; dy++) {
      for (int dx = -radius; dx <= radius; dx++) {
        final x = cx + dx;
        final y = cy + dy;

        if (x < minX || x > maxX || y < minY || y > maxY) continue;

        final dist = sqrt(dx * dx + dy * dy);
        if (dist <= radius) {
          mask[y - minY][x - minX] = true;
        }
      }
    }
  }

  // 블러 적용
  for (int y = minY; y <= maxY; y++) {
    for (int x = minX; x <= maxX; x++) {
      if (!mask[y - minY][x - minX]) continue;

      int r = 0, g = 0, b = 0, count = 0;

      for (int ky = -blurRadius; ky <= blurRadius; ky++) {
        for (int kx = -blurRadius; kx <= blurRadius; kx++) {
          final nx = (x + kx).clamp(0, image.width - 1);
          final ny = (y + ky).clamp(0, image.height - 1);

          final pixel = image.getPixel(nx, ny);
          r += pixel.r.toInt();
          g += pixel.g.toInt();
          b += pixel.b.toInt();
          count++;
        }
      }

      if (count > 0) {
        image.setPixelRgba(x, y, r ~/ count, g ~/ count, b ~/ count, 255);
      }
    }
  }
}

void _applyMosaic(img.Image image, List<Offset> points, int radius, double intensity) {
  final blockSize = (intensity * 20).toInt().clamp(4, 30);

  // 영향받는 픽셀 수집
  final affectedPixels = <String, bool>{};

  for (final point in points) {
    final cx = point.dx.toInt();
    final cy = point.dy.toInt();

    for (int dy = -radius; dy <= radius; dy++) {
      for (int dx = -radius; dx <= radius; dx++) {
        final x = cx + dx;
        final y = cy + dy;

        if (x < 0 || x >= image.width || y < 0 || y >= image.height) continue;

        final dist = sqrt(dx * dx + dy * dy);
        if (dist <= radius) {
          // 블록 단위로 그룹화
          final bx = (x ~/ blockSize) * blockSize;
          final by = (y ~/ blockSize) * blockSize;
          affectedPixels['$bx,$by'] = true;
        }
      }
    }
  }

  // 각 블록에 모자이크 적용
  for (final key in affectedPixels.keys) {
    final parts = key.split(',');
    final bx = int.parse(parts[0]);
    final by = int.parse(parts[1]);

    int r = 0, g = 0, b = 0, count = 0;

    // 블록 평균 색상 계산
    for (int y = by; y < by + blockSize && y < image.height; y++) {
      for (int x = bx; x < bx + blockSize && x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        r += pixel.r.toInt();
        g += pixel.g.toInt();
        b += pixel.b.toInt();
        count++;
      }
    }

    if (count > 0) {
      final avgR = r ~/ count;
      final avgG = g ~/ count;
      final avgB = b ~/ count;

      // 블록에 평균 색상 적용
      for (int y = by; y < by + blockSize && y < image.height; y++) {
        for (int x = bx; x < bx + blockSize && x < image.width; x++) {
          image.setPixelRgba(x, y, avgR, avgG, avgB, 255);
        }
      }
    }
  }
}

void _applyEraser(img.Image image, img.Image original, List<Offset> points, int radius) {
  for (final point in points) {
    final cx = point.dx.toInt();
    final cy = point.dy.toInt();

    for (int dy = -radius; dy <= radius; dy++) {
      for (int dx = -radius; dx <= radius; dx++) {
        final x = cx + dx;
        final y = cy + dy;

        if (x < 0 || x >= image.width || y < 0 || y >= image.height) continue;

        final dist = sqrt(dx * dx + dy * dy);
        if (dist <= radius) {
          final originalPixel = original.getPixel(x, y);
          image.setPixel(x, y, originalPixel);
        }
      }
    }
  }
}

// 검은 바 적용 (브러시 모드)
void _applyBlackBar(img.Image image, List<Offset> points, int radius) {
  for (final point in points) {
    final cx = point.dx.toInt();
    final cy = point.dy.toInt();

    for (int dy = -radius; dy <= radius; dy++) {
      for (int dx = -radius; dx <= radius; dx++) {
        final x = cx + dx;
        final y = cy + dy;

        if (x < 0 || x >= image.width || y < 0 || y >= image.height) continue;

        final dist = sqrt(dx * dx + dy * dy);
        if (dist <= radius) {
          image.setPixelRgba(x, y, 0, 0, 0, 255);
        }
      }
    }
  }
}

// 형광펜 적용 (브러시 모드)
void _applyHighlighter(img.Image image, List<Offset> points, int radius, int colorValue, double intensity) {
  final color = Color(colorValue);
  final alpha = (intensity * 0.5).clamp(0.2, 0.6);
  final colorR = (color.r * 255).round().clamp(0, 255);
  final colorG = (color.g * 255).round().clamp(0, 255);
  final colorB = (color.b * 255).round().clamp(0, 255);

  for (final point in points) {
    final cx = point.dx.toInt();
    final cy = point.dy.toInt();

    for (int dy = -radius; dy <= radius; dy++) {
      for (int dx = -radius; dx <= radius; dx++) {
        final x = cx + dx;
        final y = cy + dy;

        if (x < 0 || x >= image.width || y < 0 || y >= image.height) continue;

        final dist = sqrt(dx * dx + dy * dy);
        if (dist <= radius) {
          final pixel = image.getPixel(x, y);
          final newR = ((pixel.r * (1 - alpha)) + (colorR * alpha)).toInt().clamp(0, 255);
          final newG = ((pixel.g * (1 - alpha)) + (colorG * alpha)).toInt().clamp(0, 255);
          final newB = ((pixel.b * (1 - alpha)) + (colorB * alpha)).toInt().clamp(0, 255);
          image.setPixelRgba(x, y, newR, newG, newB, 255);
        }
      }
    }
  }
}

// ==================== 도형 모드 함수들 ====================

bool _isInShape(int x, int y, Offset start, Offset end, DrawMode mode) {
  final minX = min(start.dx, end.dx).toInt();
  final maxX = max(start.dx, end.dx).toInt();
  final minY = min(start.dy, end.dy).toInt();
  final maxY = max(start.dy, end.dy).toInt();

  if (mode == DrawMode.rectangle) {
    return x >= minX && x <= maxX && y >= minY && y <= maxY;
  } else {
    // 원형 (타원)
    final centerX = (start.dx + end.dx) / 2;
    final centerY = (start.dy + end.dy) / 2;
    final radiusX = (end.dx - start.dx).abs() / 2;
    final radiusY = (end.dy - start.dy).abs() / 2;

    if (radiusX == 0 || radiusY == 0) return false;

    final dx = (x - centerX) / radiusX;
    final dy = (y - centerY) / radiusY;
    return (dx * dx + dy * dy) <= 1;
  }
}

void _applyShapeBlur(img.Image image, Offset start, Offset end, DrawMode mode, double intensity) {
  final blurRadius = (intensity * 15).toInt().clamp(1, 20);
  final minX = max(0, min(start.dx, end.dx).toInt());
  final maxX = min(image.width - 1, max(start.dx, end.dx).toInt());
  final minY = max(0, min(start.dy, end.dy).toInt());
  final maxY = min(image.height - 1, max(start.dy, end.dy).toInt());

  // 영역 복사본 만들기
  final tempImage = img.Image.from(image);

  for (int y = minY; y <= maxY; y++) {
    for (int x = minX; x <= maxX; x++) {
      if (!_isInShape(x, y, start, end, mode)) continue;

      int r = 0, g = 0, b = 0, count = 0;

      for (int ky = -blurRadius; ky <= blurRadius; ky++) {
        for (int kx = -blurRadius; kx <= blurRadius; kx++) {
          final nx = (x + kx).clamp(0, image.width - 1);
          final ny = (y + ky).clamp(0, image.height - 1);

          final pixel = tempImage.getPixel(nx, ny);
          r += pixel.r.toInt();
          g += pixel.g.toInt();
          b += pixel.b.toInt();
          count++;
        }
      }

      if (count > 0) {
        image.setPixelRgba(x, y, r ~/ count, g ~/ count, b ~/ count, 255);
      }
    }
  }
}

void _applyShapeMosaic(img.Image image, Offset start, Offset end, DrawMode mode, double intensity) {
  final blockSize = (intensity * 20).toInt().clamp(4, 30);
  final minX = max(0, min(start.dx, end.dx).toInt());
  final maxX = min(image.width - 1, max(start.dx, end.dx).toInt());
  final minY = max(0, min(start.dy, end.dy).toInt());
  final maxY = min(image.height - 1, max(start.dy, end.dy).toInt());

  for (int by = minY; by <= maxY; by += blockSize) {
    for (int bx = minX; bx <= maxX; bx += blockSize) {
      int r = 0, g = 0, b = 0, count = 0;

      // 블록 평균 색상 계산
      for (int y = by; y < by + blockSize && y <= maxY; y++) {
        for (int x = bx; x < bx + blockSize && x <= maxX; x++) {
          if (!_isInShape(x, y, start, end, mode)) continue;
          final pixel = image.getPixel(x, y);
          r += pixel.r.toInt();
          g += pixel.g.toInt();
          b += pixel.b.toInt();
          count++;
        }
      }

      if (count > 0) {
        final avgR = r ~/ count;
        final avgG = g ~/ count;
        final avgB = b ~/ count;

        for (int y = by; y < by + blockSize && y <= maxY; y++) {
          for (int x = bx; x < bx + blockSize && x <= maxX; x++) {
            if (!_isInShape(x, y, start, end, mode)) continue;
            image.setPixelRgba(x, y, avgR, avgG, avgB, 255);
          }
        }
      }
    }
  }
}

void _applyShapeBlackBar(img.Image image, Offset start, Offset end, DrawMode mode) {
  final minX = max(0, min(start.dx, end.dx).toInt());
  final maxX = min(image.width - 1, max(start.dx, end.dx).toInt());
  final minY = max(0, min(start.dy, end.dy).toInt());
  final maxY = min(image.height - 1, max(start.dy, end.dy).toInt());

  for (int y = minY; y <= maxY; y++) {
    for (int x = minX; x <= maxX; x++) {
      if (_isInShape(x, y, start, end, mode)) {
        image.setPixelRgba(x, y, 0, 0, 0, 255);
      }
    }
  }
}

void _applyShapeHighlighter(img.Image image, Offset start, Offset end, DrawMode mode, int colorValue, double intensity) {
  final color = Color(colorValue);
  final alpha = (intensity * 0.5).clamp(0.2, 0.6);
  final colorR = (color.r * 255).round().clamp(0, 255);
  final colorG = (color.g * 255).round().clamp(0, 255);
  final colorB = (color.b * 255).round().clamp(0, 255);
  final minX = max(0, min(start.dx, end.dx).toInt());
  final maxX = min(image.width - 1, max(start.dx, end.dx).toInt());
  final minY = max(0, min(start.dy, end.dy).toInt());
  final maxY = min(image.height - 1, max(start.dy, end.dy).toInt());

  for (int y = minY; y <= maxY; y++) {
    for (int x = minX; x <= maxX; x++) {
      if (!_isInShape(x, y, start, end, mode)) continue;

      final pixel = image.getPixel(x, y);
      final newR = ((pixel.r * (1 - alpha)) + (colorR * alpha)).toInt().clamp(0, 255);
      final newG = ((pixel.g * (1 - alpha)) + (colorG * alpha)).toInt().clamp(0, 255);
      final newB = ((pixel.b * (1 - alpha)) + (colorB * alpha)).toInt().clamp(0, 255);
      image.setPixelRgba(x, y, newR, newG, newB, 255);
    }
  }
}

void _applyShapeEraser(img.Image image, img.Image original, Offset start, Offset end, DrawMode mode) {
  final minX = max(0, min(start.dx, end.dx).toInt());
  final maxX = min(image.width - 1, max(start.dx, end.dx).toInt());
  final minY = max(0, min(start.dy, end.dy).toInt());
  final maxY = min(image.height - 1, max(start.dy, end.dy).toInt());

  for (int y = minY; y <= maxY; y++) {
    for (int x = minX; x <= maxX; x++) {
      if (_isInShape(x, y, start, end, mode)) {
        final originalPixel = original.getPixel(x, y);
        image.setPixel(x, y, originalPixel);
      }
    }
  }
}

// ==================== Compare Mode Classes ====================

class _CompareClipper extends CustomClipper<Rect> {
  final double sliderValue;
  final bool isLeft;

  _CompareClipper(this.sliderValue, {this.isLeft = true});

  @override
  Rect getClip(Size size) {
    if (isLeft) {
      return Rect.fromLTWH(0, 0, size.width * sliderValue, size.height);
    } else {
      return Rect.fromLTWH(size.width * sliderValue, 0, size.width * (1 - sliderValue), size.height);
    }
  }

  @override
  bool shouldReclip(_CompareClipper oldClipper) {
    return sliderValue != oldClipper.sliderValue;
  }
}

class _CompareImagePainter extends CustomPainter {
  final ui.Image image;
  final double scale;
  final Offset offset;
  final int rotation;

  _CompareImagePainter({
    required this.image,
    required this.scale,
    required this.offset,
    required this.rotation,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final imageSize = Size(image.width.toDouble(), image.height.toDouble());
    final fittedSize = applyBoxFit(BoxFit.contain, imageSize, size);

    final offsetX = (size.width - fittedSize.destination.width) / 2;
    final offsetY = (size.height - fittedSize.destination.height) / 2;

    final destRect = Rect.fromLTWH(
      offsetX + offset.dx,
      offsetY + offset.dy,
      fittedSize.destination.width * scale,
      fittedSize.destination.height * scale,
    );

    final srcRect = Rect.fromLTWH(0, 0, imageSize.width, imageSize.height);

    canvas.save();
    if (rotation != 0) {
      final center = Offset(size.width / 2, size.height / 2);
      canvas.translate(center.dx, center.dy);
      canvas.rotate(rotation * 3.14159 / 180);
      canvas.translate(-center.dx, -center.dy);
    }
    canvas.drawImageRect(image, srcRect, destRect, Paint());
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CompareImagePainter oldDelegate) {
    return image != oldDelegate.image ||
        scale != oldDelegate.scale ||
        offset != oldDelegate.offset ||
        rotation != oldDelegate.rotation;
  }
}

// ==================== Canvas Painter ====================

class ImageCanvasPainter extends CustomPainter {
  final ui.Image image;
  final List<Offset> currentStroke;
  final double brushSize;
  final EditTool tool;
  final DrawMode drawMode;
  final Offset? shapeStart;
  final Offset? shapeEnd;
  final Color highlighterColor;

  ImageCanvasPainter({
    required this.image,
    required this.currentStroke,
    required this.brushSize,
    required this.tool,
    required this.drawMode,
    this.shapeStart,
    this.shapeEnd,
    this.highlighterColor = Colors.yellow,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 이미지 그리기
    final imageSize = Size(image.width.toDouble(), image.height.toDouble());
    final fittedSize = applyBoxFit(BoxFit.contain, imageSize, size);

    final offsetX = (size.width - fittedSize.destination.width) / 2;
    final offsetY = (size.height - fittedSize.destination.height) / 2;

    final destRect = Rect.fromLTWH(
      offsetX,
      offsetY,
      fittedSize.destination.width,
      fittedSize.destination.height,
    );

    final srcRect = Rect.fromLTWH(0, 0, imageSize.width, imageSize.height);

    canvas.drawImageRect(image, srcRect, destRect, Paint());

    final scaleX = fittedSize.destination.width / imageSize.width;
    final scaleY = fittedSize.destination.height / imageSize.height;

    // 도형 미리보기
    if (drawMode != DrawMode.brush && shapeStart != null && shapeEnd != null) {
      final startX = offsetX + shapeStart!.dx * scaleX;
      final startY = offsetY + shapeStart!.dy * scaleY;
      final endX = offsetX + shapeEnd!.dx * scaleX;
      final endY = offsetY + shapeEnd!.dy * scaleY;

      final shapePaint = Paint()
        ..color = _getStrokeColor()
        ..style = PaintingStyle.fill;

      if (drawMode == DrawMode.rectangle) {
        canvas.drawRect(
          Rect.fromPoints(Offset(startX, startY), Offset(endX, endY)),
          shapePaint,
        );
      } else {
        // 원형 (타원)
        final rect = Rect.fromPoints(Offset(startX, startY), Offset(endX, endY));
        canvas.drawOval(rect, shapePaint);
      }
    }

    // 브러시 스트로크 미리보기
    if (drawMode == DrawMode.brush && currentStroke.isNotEmpty) {
      final strokePaint = Paint()
        ..color = _getStrokeColor()
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke
        ..strokeWidth = brushSize * scaleX;

      final path = Path();
      for (int i = 0; i < currentStroke.length; i++) {
        final point = currentStroke[i];
        final canvasX = offsetX + point.dx * scaleX;
        final canvasY = offsetY + point.dy * scaleY;

        if (i == 0) {
          path.moveTo(canvasX, canvasY);
        } else {
          path.lineTo(canvasX, canvasY);
        }
      }

      canvas.drawPath(path, strokePaint);
    }
  }

  Color _getStrokeColor() {
    switch (tool) {
      case EditTool.blur:
        return Colors.blue.withValues(alpha: 0.4);
      case EditTool.mosaic:
        return Colors.purple.withValues(alpha: 0.4);
      case EditTool.eraser:
        return Colors.white.withValues(alpha: 0.4);
      case EditTool.blackBar:
        return Colors.black.withValues(alpha: 0.7);
      case EditTool.highlighter:
        return highlighterColor.withValues(alpha: 0.5);
      case EditTool.sticker:
      case EditTool.text:
        return Colors.transparent;
    }
  }

  @override
  bool shouldRepaint(covariant ImageCanvasPainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.currentStroke != currentStroke ||
        oldDelegate.brushSize != brushSize ||
        oldDelegate.tool != tool ||
        oldDelegate.drawMode != drawMode ||
        oldDelegate.shapeStart != shapeStart ||
        oldDelegate.shapeEnd != shapeEnd ||
        oldDelegate.highlighterColor != highlighterColor;
  }
}

// ==================== Settings Screen ====================

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _watermarkEnabled = false;
  bool _isPro = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final enabled = await WatermarkSettings.isEnabled();
    final isPro = SubscriptionService().isProUser;
    if (mounted) {
      setState(() {
        _watermarkEnabled = enabled;
        _isPro = isPro;
      });
    }
  }

  void _showWatermarkSettings() {
    if (!_isPro) {
      _showProSubscription(context);
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _WatermarkSettingsSheet(
        onSettingsChanged: () {
          _loadSettings();
        },
      ),
    );
  }

  void _showProSubscription(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _ProSubscriptionSheet(),
    );
  }

  // 앱스토어 ID (출시 후 실제 ID로 변경)
  static const String _appStoreId = '6740097791';

  Future<void> _rateApp(BuildContext context) async {
    final url = Platform.isIOS
        ? Uri.parse('https://apps.apple.com/app/id$_appStoreId?action=write-review')
        : Uri.parse('https://play.google.com/store/apps/details?id=com.devyulstudio.cover');

    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('앱스토어를 열 수 없습니다')),
        );
      }
    }
  }

  Future<void> _sendEmail() async {
    // 기기 정보 수집
    String deviceInfo = '';
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final deviceInfoPlugin = DeviceInfoPlugin();

      if (Platform.isIOS) {
        final iosInfo = await deviceInfoPlugin.iosInfo;
        deviceInfo = '''
---
앱 버전: ${packageInfo.version} (${packageInfo.buildNumber})
기기 모델: ${iosInfo.model}
기기 이름: ${iosInfo.name}
시스템: ${iosInfo.systemName} ${iosInfo.systemVersion}
''';
      } else if (Platform.isAndroid) {
        final androidInfo = await deviceInfoPlugin.androidInfo;
        deviceInfo = '''
---
앱 버전: ${packageInfo.version} (${packageInfo.buildNumber})
기기 모델: ${androidInfo.model}
제조사: ${androidInfo.manufacturer}
시스템: Android ${androidInfo.version.release} (SDK ${androidInfo.version.sdkInt})
''';
      }
    } catch (e) {
      deviceInfo = '\n---\n기기 정보를 가져올 수 없습니다.';
    }

    final uri = Uri(
      scheme: 'mailto',
      path: 'parksy785@gmail.com',
      queryParameters: {
        'subject': '[Cover 앱 문의]',
        'body': '\n\n문의 내용을 입력해주세요.\n$deviceInfo',
      },
    );

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('설정'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        children: [
          // Pro 구독 배너
          Padding(
            padding: const EdgeInsets.all(16),
            child: GestureDetector(
              onTap: () => _showProSubscription(context),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.workspace_premium, color: Colors.white, size: 28),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Cover Pro',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '모든 기능을 무제한으로',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward_ios, color: Colors.white70, size: 16),
                  ],
                ),
              ),
            ),
          ),

          // 워터마크 설정 (Pro 전용)
          const _SectionHeader(title: '워터마크'),
          _SettingsTile(
            icon: Icons.branding_watermark,
            title: '워터마크 추가',
            subtitle: _watermarkEnabled ? '활성화됨' : '비활성화됨',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!_isPro)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'PRO',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
              ],
            ),
            onTap: _showWatermarkSettings,
          ),

          const SizedBox(height: 8),

          // 지원
          const _SectionHeader(title: '지원'),
          _SettingsTile(
            icon: Icons.star_outline,
            title: '앱 리뷰 작성',
            subtitle: '별점과 리뷰로 응원해주세요',
            onTap: () => _rateApp(context),
          ),
          _SettingsTile(
            icon: Icons.mail_outline,
            title: '문의하기',
            subtitle: 'parksy785@gmail.com',
            onTap: _sendEmail,
          ),

          const SizedBox(height: 8),

          // 앱 정보
          const _SectionHeader(title: '정보'),
          _SettingsTile(
            icon: Icons.info_outline,
            title: '버전',
            subtitle: '1.0.0',
            onTap: null,
          ),
          _SettingsTile(
            icon: Icons.description_outlined,
            title: '오픈소스 라이선스',
            onTap: () {
              showLicensePage(
                context: context,
                applicationName: 'Cover',
                applicationVersion: '1.0.0',
              );
            },
          ),
          _SettingsTile(
            icon: Icons.privacy_tip_outlined,
            title: '개인정보 처리방침',
            onTap: () => _openUrl('https://devyulstudio.notion.site/cover-privacy-policy'),
          ),
          _SettingsTile(
            icon: Icons.article_outlined,
            title: '이용약관',
            onTap: () => _openUrl('https://devyulstudio.notion.site/cover-terms-of-service'),
          ),

          const SizedBox(height: 32),

          // 앱 정보 푸터
          Center(
            child: Column(
              children: [
                Text(
                  'Cover',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white54 : Colors.black38,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '개인정보를 안전하게',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white38 : Colors.black26,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// Pro 구독 바텀시트
class _ProSubscriptionSheet extends StatefulWidget {
  const _ProSubscriptionSheet();

  @override
  State<_ProSubscriptionSheet> createState() => _ProSubscriptionSheetState();
}

class _ProSubscriptionSheetState extends State<_ProSubscriptionSheet> {
  final SubscriptionService _subscriptionService = SubscriptionService();
  List<Package>? _packages;
  bool _isLoading = false;
  int _selectedPlanIndex = 0; // 0: 평생, 1: 연간, 2: 월간

  @override
  void initState() {
    super.initState();
    _loadOfferings();
    AnalyticsService().logSubscriptionViewed();
  }

  Future<void> _loadOfferings() async {
    final packages = await _subscriptionService.getOfferings();
    if (mounted) {
      setState(() => _packages = packages);
    }
  }

  Future<void> _purchase() async {
    if (_isLoading) return;

    setState(() => _isLoading = true);

    try {
      // 실제 패키지가 있으면 구매 진행
      if (_packages != null && _packages!.isNotEmpty) {
        final package = _packages![_selectedPlanIndex];
        final success = await _subscriptionService.purchasePackage(package);

        if (success) {
          final plan = _selectedPlanIndex == 0 ? 'lifetime' : (_selectedPlanIndex == 1 ? 'yearly' : 'monthly');
          AnalyticsService().logSubscriptionStarted(plan);
        }

        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(success ? 'Pro 구독이 활성화되었습니다!' : '구매가 취소되었습니다'),
              backgroundColor: success ? Colors.green : Colors.orange,
            ),
          );
        }
      } else {
        // 테스트 모드 (API 키 미설정)
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('RevenueCat API 키를 설정해주세요'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('오류: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _restorePurchases() async {
    setState(() => _isLoading = true);

    try {
      final success = await _subscriptionService.restorePurchases();

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? '구독이 복원되었습니다!' : '복원할 구독이 없습니다'),
            backgroundColor: success ? Colors.green : Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('복원 오류: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[400],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),

          // 헤더
          const Icon(Icons.workspace_premium, size: 48, color: Color(0xFF6366F1)),
          const SizedBox(height: 12),
          const Text(
            'Cover Pro',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            '모든 프리미엄 기능을 무제한으로 사용하세요',
            style: TextStyle(color: Colors.grey[600], fontSize: 14),
          ),

          const SizedBox(height: 24),

          // 기능 목록
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                _buildFeatureRow(Icons.high_quality, '원본 화질 저장'),
                _buildFeatureRow(Icons.all_inclusive, '무제한 저장'),
                _buildFeatureRow(Icons.branding_watermark, '워터마크 기능'),
                _buildFeatureRow(Icons.emoji_emotions, '50+ 프리미엄 스티커'),
                _buildFeatureRow(Icons.block, '광고 제거'),
                _buildFeatureRow(Icons.support_agent, '우선 고객 지원'),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // 가격 옵션
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                _buildPriceOption(
                  context,
                  index: 0,
                  title: '평생 이용권',
                  price: _packages != null && _packages!.length > 2
                      ? _packages![2].storeProduct.priceString
                      : '₩22,000',
                  subtitle: '한 번 결제로 영구 사용',
                  isPopular: true,
                  badge: '인기',
                  isLifetime: true,
                ),
                const SizedBox(height: 12),
                _buildPriceOption(
                  context,
                  index: 1,
                  title: '연간',
                  price: _packages != null && _packages!.isNotEmpty
                      ? _packages![0].storeProduct.priceString
                      : '₩15,000/년',
                  subtitle: '월 ₩1,250 (43% 할인)',
                  isPopular: false,
                ),
                const SizedBox(height: 12),
                _buildPriceOption(
                  context,
                  index: 2,
                  title: '월간',
                  price: _packages != null && _packages!.length > 1
                      ? _packages![1].storeProduct.priceString
                      : '₩2,200/월',
                  subtitle: '',
                  isPopular: false,
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // 구독 버튼
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _purchase,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        _selectedPlanIndex == 0 ? '평생 이용권 구매하기' : '구독 시작하기',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // 하단 안내
          Text(
            _selectedPlanIndex == 0
                ? '한 번 결제로 모든 기능을 영구적으로 사용하세요'
                : '구독 시작 시 즉시 결제됩니다',
            style: TextStyle(color: Colors.grey[500], fontSize: 12),
          ),
          TextButton(
            onPressed: _isLoading ? null : _restorePurchases,
            child: Text(
              '이전 구매 복원',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildFeatureRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF6366F1), size: 22),
          const SizedBox(width: 12),
          Text(text, style: const TextStyle(fontSize: 15)),
        ],
      ),
    );
  }

  Widget _buildPriceOption(
    BuildContext context, {
    required int index,
    required String title,
    required String price,
    required String subtitle,
    required bool isPopular,
    String? badge,
    bool isLifetime = false,
  }) {
    final isSelected = _selectedPlanIndex == index;
    final badgeColor = isLifetime ? const Color(0xFFFF9800) : const Color(0xFF6366F1);
    return GestureDetector(
      onTap: () => setState(() => _selectedPlanIndex = index),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected ? badgeColor : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
          color: isSelected ? badgeColor.withValues(alpha: 0.1) : null,
        ),
        child: Row(
          children: [
            // 선택 표시
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? badgeColor : Colors.grey[400]!,
                  width: 2,
                ),
                color: isSelected ? badgeColor : Colors.transparent,
              ),
              child: isSelected
                  ? const Icon(Icons.check, color: Colors.white, size: 16)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: badgeColor,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            badge,
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                      if (isLifetime) ...[
                        const SizedBox(width: 8),
                        const Icon(Icons.all_inclusive, size: 16, color: Color(0xFFFF9800)),
                      ],
                    ],
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(subtitle, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                  ],
                ],
              ),
            ),
            Text(
              price,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, size: 24),
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle!) : null,
      trailing: trailing,
      onTap: onTap,
    );
  }
}

// ==================== 워터마크 설정 시트 ====================

class _WatermarkSettingsSheet extends StatefulWidget {
  final VoidCallback? onSettingsChanged;

  const _WatermarkSettingsSheet({this.onSettingsChanged});

  @override
  State<_WatermarkSettingsSheet> createState() => _WatermarkSettingsSheetState();
}

class _WatermarkSettingsSheetState extends State<_WatermarkSettingsSheet> {
  bool _enabled = false;
  String _text = 'Cover';
  WatermarkPosition _position = WatermarkPosition.bottomRight;
  double _opacity = 0.5;
  final TextEditingController _textController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final enabled = await WatermarkSettings.isEnabled();
    final text = await WatermarkSettings.getText();
    final position = await WatermarkSettings.getPosition();
    final opacity = await WatermarkSettings.getOpacity();

    if (mounted) {
      setState(() {
        _enabled = enabled;
        _text = text;
        _position = position;
        _opacity = opacity;
        _textController.text = text;
      });
    }
  }

  Future<void> _saveSettings() async {
    await WatermarkSettings.setEnabled(_enabled);
    await WatermarkSettings.setText(_text);
    await WatermarkSettings.setPosition(_position);
    await WatermarkSettings.setOpacity(_opacity);
    widget.onSettingsChanged?.call();
  }

  String _getPositionName(WatermarkPosition position) {
    switch (position) {
      case WatermarkPosition.topLeft:
        return '좌상단';
      case WatermarkPosition.topCenter:
        return '상단 중앙';
      case WatermarkPosition.topRight:
        return '우상단';
      case WatermarkPosition.centerLeft:
        return '좌측 중앙';
      case WatermarkPosition.center:
        return '중앙';
      case WatermarkPosition.centerRight:
        return '우측 중앙';
      case WatermarkPosition.bottomLeft:
        return '좌하단';
      case WatermarkPosition.bottomCenter:
        return '하단 중앙';
      case WatermarkPosition.bottomRight:
        return '우하단';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),

            // 헤더
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.branding_watermark,
                    color: Color(0xFF6366F1),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '워터마크 설정',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        '저장 시 이미지에 워터마크가 추가됩니다',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // 워터마크 활성화 토글
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey.shade900 : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '워터마크 사용',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Switch(
                    value: _enabled,
                    onChanged: (value) {
                      setState(() => _enabled = value);
                      _saveSettings();
                    },
                    activeTrackColor: const Color(0xFF6366F1),
                  ),
                ],
              ),
            ),
          ),

          if (_enabled) ...[
            const SizedBox(height: 16),

            // 워터마크 텍스트
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _textController,
                decoration: InputDecoration(
                  labelText: '워터마크 텍스트',
                  hintText: '예: © 2024 My Brand',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixIcon: const Icon(Icons.text_fields),
                ),
                onChanged: (value) {
                  _text = value;
                  _saveSettings();
                },
              ),
            ),

            const SizedBox(height: 16),

            // 위치 선택
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '위치',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey.shade900 : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: GridView.count(
                      crossAxisCount: 3,
                      shrinkWrap: true,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      physics: const NeverScrollableScrollPhysics(),
                      children: WatermarkPosition.values.map((position) {
                        final isSelected = _position == position;
                        return GestureDetector(
                          onTap: () {
                            setState(() => _position = position);
                            _saveSettings();
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFF6366F1)
                                  : (isDark ? Colors.grey.shade800 : Colors.white),
                              borderRadius: BorderRadius.circular(8),
                              border: isSelected
                                  ? null
                                  : Border.all(color: Colors.grey.shade300),
                            ),
                            child: Center(
                              child: Icon(
                                Icons.circle,
                                size: 12,
                                color: isSelected
                                    ? Colors.white
                                    : Colors.grey.shade400,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Center(
                    child: Text(
                      _getPositionName(_position),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // 투명도
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '투명도',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        '${(_opacity * 100).toInt()}%',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: _opacity,
                    min: 0.1,
                    max: 1.0,
                    divisions: 9,
                    activeColor: const Color(0xFF6366F1),
                    onChanged: (value) {
                      setState(() => _opacity = value);
                    },
                    onChangeEnd: (value) {
                      _saveSettings();
                    },
                  ),
                ],
              ),
            ),

            // 미리보기
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                height: 80,
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.blue.shade900,
                      Colors.purple.shade900,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Stack(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    Positioned(
                      left: _position.index % 3 == 0 ? 12 : null,
                      right: _position.index % 3 == 2 ? 12 : null,
                      top: _position.index ~/ 3 == 0 ? 12 : null,
                      bottom: _position.index ~/ 3 == 2 ? 12 : null,
                      child: Center(
                        child: Opacity(
                          opacity: _opacity,
                          child: Text(
                            _text.isEmpty ? 'Cover' : _text,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              shadows: [
                                Shadow(
                                  offset: Offset(1, 1),
                                  blurRadius: 2,
                                  color: Colors.black54,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 24),

          // 닫기 버튼
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  '완료',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),

          SizedBox(height: MediaQuery.of(context).padding.bottom + 20),
          ],
        ),
      ),
    );
  }
}
