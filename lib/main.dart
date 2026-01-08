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
import 'package:flutter_localizations/flutter_localizations.dart';

import 'config/api_keys.dart';
import 'config/constants.dart';
import 'l10n/app_localizations.dart';

// 테마 모드 관리
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.dark);

// 언어 설정 관리
final ValueNotifier<Locale?> localeNotifier = ValueNotifier(null); // null = 기기 설정 따름

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

  // 상품 ID (constants.dart에서 가져옴)
  static String get entitlementId => ProductIds.entitlementId;
  static String get monthlyProductId => ProductIds.monthly;
  static String get yearlyProductId => ProductIds.yearly;
  static String get lifetimeProductId => ProductIds.lifetime;

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
      final apiKey = ApiKeys.revenueCat;

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
  static int get maxFreeSavesPerDay => AppConstants.maxFreeSavesPerDay;

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
      adUnitId: ApiKeys.interstitialAdUnitId,
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

  @override
  void initState() {
    super.initState();
    _loadAd();
  }

  void _loadAd() {
    _nativeAd = NativeAd(
      adUnitId: ApiKeys.nativeAdUnitId,
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
      // 스켈레톤 UI (실제 광고 레이아웃과 동일한 구조)
      return Container(
        height: 136,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
          color: AppColors.cardDark,
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              // 미디어 스켈레톤 (120x120)
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(width: 8),
              // 콘텐츠 영역
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 상단: 아이콘 + AD 배지
                    Row(
                      children: [
                        // 아이콘 스켈레톤
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // AD 배지 (실제 광고와 동일한 위치)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.proBadge,
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: Text(
                            AppLocalizations.of(context).nativeAdLabel,
                            style: const TextStyle(
                              color: Colors.black,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // 헤드라인 스켈레톤
                    Container(
                      height: 14,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const Spacer(),
                    // 하단: 바디 + CTA 버튼
                    Row(
                      children: [
                        // 바디 스켈레톤
                        Expanded(
                          child: Container(
                            height: 12,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // CTA 버튼 스켈레톤
                        Container(
                          width: 60,
                          height: 28,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
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
        return ValueListenableBuilder<Locale?>(
          valueListenable: localeNotifier,
          builder: (context, locale, child) {
            return MaterialApp(
              title: 'Cover',
              debugShowCheckedModeBanner: false,
              themeMode: themeMode,
              locale: locale,
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: AppLocalizations.supportedLocales,
              theme: ThemeData(
                colorScheme: ColorScheme.fromSeed(
                  seedColor: AppColors.primary,
                  brightness: Brightness.light,
                ),
                useMaterial3: true,
              ),
              darkTheme: ThemeData(
                colorScheme: ColorScheme.fromSeed(
                  seedColor: AppColors.primary,
                  brightness: Brightness.dark,
                ),
                useMaterial3: true,
                scaffoldBackgroundColor: Colors.black,
              ),
              home: const SplashScreen(),
            );
          },
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
    // 네이티브 스플래시와 동일하게 검은 화면만 표시 (온보딩 체크 중)
    return const Scaffold(
      backgroundColor: Colors.black,
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

  List<OnboardingPage> _getPages(AppLocalizations l10n) => [
    OnboardingPage(
      icon: Icons.shield,
      title: l10n.onboardingWelcomeTitle,
      description: l10n.onboardingWelcomeDesc,
      color: AppColors.primary,
    ),
    OnboardingPage(
      icon: Icons.blur_on,
      title: l10n.onboardingBlurTitle,
      description: l10n.onboardingBlurDesc,
      color: const Color(0xFF9C27B0),
    ),
    OnboardingPage(
      icon: Icons.text_fields,
      title: l10n.onboardingTextStickerTitle,
      description: l10n.onboardingTextStickerDesc,
      color: const Color(0xFF4CAF50),
    ),
    OnboardingPage(
      icon: Icons.share,
      title: l10n.onboardingSaveShareTitle,
      description: l10n.onboardingSaveShareDesc,
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

  void _nextPage(int pageCount) {
    if (_currentPage < pageCount - 1) {
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
    final l10n = AppLocalizations.of(context);
    final pages = _getPages(l10n);

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
                  l10n.skip,
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
                itemCount: pages.length,
                onPageChanged: (index) {
                  setState(() => _currentPage = index);
                },
                itemBuilder: (context, index) {
                  return _buildPage(pages[index]);
                },
              ),
            ),
            // Page indicator
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  pages.length,
                  (index) => AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: _currentPage == index ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _currentPage == index
                          ? pages[_currentPage].color
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
                  onPressed: () => _nextPage(pages.length),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: pages[_currentPage].color,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(
                    _currentPage == pages.length - 1 ? l10n.getStarted : l10n.next,
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
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l10n.imageLoadFailed}: $e')),
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
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l10n.get('cameraError')}: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SettingsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtitleColor = isDark ? Colors.white70 : Colors.black54;
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  children: [
                    // 설정 아이콘 (우상단)
                    Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        onPressed: _openSettings,
                        icon: Icon(
                          Icons.settings_outlined,
                          color: subtitleColor,
                          size: 28,
                        ),
                        tooltip: l10n.settings,
                      ),
                    ),
                    // 로고
                    Stack(
                      alignment: Alignment.bottomCenter,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 24),
                          child: Image.asset(
                            'assets/images/logo.png',
                            height: 240,
                          ),
                        ),
                        Text(
                          l10n.appName,
                          style: TextStyle(
                            fontSize: 56,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 48),
                    // 갤러리 버튼
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton.icon(
                        onPressed: _isLoading ? null : _pickFromGallery,
                        icon: const Icon(Icons.photo_library_rounded),
                        label: Text(l10n.gallery, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // 카메라 버튼
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: OutlinedButton.icon(
                        onPressed: _isLoading ? null : _pickFromCamera,
                        icon: const Icon(Icons.camera_alt_rounded),
                        label: Text(l10n.camera, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
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
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
            if (_isLoading)
              Container(
                color: Colors.black54,
                child: const Center(child: CircularProgressIndicator(color: AppColors.primary)),
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
  Color _highlighterColor = Colors.black;

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

  /// 오프셋을 이미지 경계 내로 제한하고 중앙 배치
  Offset _clampOffset(Offset offset, Size canvasSize) {
    if (_displayImage == null) return offset;

    // 이미지 fitting 계산 (ImageCanvasPainter와 동일한 로직)
    final imageSize = Size(
      _displayImage!.width.toDouble(),
      _displayImage!.height.toDouble(),
    );
    final fittedSize = applyBoxFit(BoxFit.contain, imageSize, canvasSize);
    final fittedWidth = fittedSize.destination.width;
    final fittedHeight = fittedSize.destination.height;

    // 이미지가 캔버스에서 중앙에 위치할 때의 오프셋 (scale 1.0 기준)
    final imageOffsetX = (canvasSize.width - fittedWidth) / 2;
    final imageOffsetY = (canvasSize.height - fittedHeight) / 2;

    // 스케일 적용 후 이미지 크기
    final scaledWidth = fittedWidth * _scale;
    final scaledHeight = fittedHeight * _scale;

    double clampedX = offset.dx;
    double clampedY = offset.dy;

    // X축 처리
    if (scaledWidth <= canvasSize.width) {
      // 이미지가 캔버스보다 작으면 중앙 배치
      clampedX = (canvasSize.width - scaledWidth) / 2 - imageOffsetX * _scale;
    } else {
      // 이미지가 캔버스보다 크면 경계 제한
      final minX = canvasSize.width - (imageOffsetX + fittedWidth) * _scale;
      final maxX = -imageOffsetX * _scale;
      clampedX = clampedX.clamp(minX, maxX);
    }

    // Y축 처리
    if (scaledHeight <= canvasSize.height) {
      // 이미지가 캔버스보다 작으면 중앙 배치
      clampedY = (canvasSize.height - scaledHeight) / 2 - imageOffsetY * _scale;
    } else {
      // 이미지가 캔버스보다 크면 경계 제한
      final minY = canvasSize.height - (imageOffsetY + fittedHeight) * _scale;
      final maxY = -imageOffsetY * _scale;
      clampedY = clampedY.clamp(minY, maxY);
    }

    return Offset(clampedX, clampedY);
  }

  // 이미지 회전
  int _rotation = 0; // 0, 90, 180, 270

  // Undo/Redo 스택
  final List<Uint8List> _undoStack = [];
  final List<Uint8List> _redoStack = [];

  // 스티커
  final List<StickerData> _stickers = [];
  int? _selectedStickerIndex;
  double _initialStickerScale = 1.0;
  double _initialStickerRotation = 0.0;

  // 텍스트 오버레이 관련
  final List<TextOverlayData> _textOverlays = [];
  int? _selectedTextIndex;
  double _initialTextScale = 1.0;
  Color _currentTextColor = Colors.white;
  Color _currentTextBgColor = Colors.black;
  bool _textHasBackground = true;

  // 도구 패널 표시 여부
  bool _toolsVisible = true;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void dispose() {
    // 메모리 누수 방지: ui.Image 리소스 해제
    _displayImage?.dispose();
    _originalDisplayImage?.dispose();
    super.dispose();
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
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l10n.imageLoadFailed}: $e')),
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
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l10n.processingFailed}: $e')),
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
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l10n.rotateFailed}: $e')),
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

    final l10n = AppLocalizations.of(context);
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
            toolbarTitle: l10n.cropImage,
            toolbarColor: Colors.black,
            toolbarWidgetColor: Colors.white,
            backgroundColor: Colors.black,
            activeControlsWidgetColor: AppColors.primary,
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
            cancelButtonTitle: l10n.cancel,
            doneButtonTitle: l10n.done,
            aspectRatioPresets: [
              CropAspectRatioPreset.original,
              CropAspectRatioPreset.square,
              CropAspectRatioPreset.ratio4x3,
              CropAspectRatioPreset.ratio16x9,
            ],
            aspectRatioLockEnabled: false,
            rotateButtonsHidden: true,
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
            SnackBar(
              content: Text(l10n.imageCropped),
              duration: const Duration(seconds: 1),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l10n.cropFailed}: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Offset? _canvasToImage(Offset canvasPoint, Size canvasSize) {
    if (_displayImage == null) return null;

    // 1. 확대/이동 변환 역적용 (터치 좌표 → 원본 캔버스 좌표)
    final transformedPoint = Offset(
      (canvasPoint.dx - _offset.dx) / _scale,
      (canvasPoint.dy - _offset.dy) / _scale,
    );

    final imageSize = Size(_displayImage!.width.toDouble(), _displayImage!.height.toDouble());
    final fittedSize = applyBoxFit(BoxFit.contain, imageSize, canvasSize);

    final offsetX = (canvasSize.width - fittedSize.destination.width) / 2;
    final offsetY = (canvasSize.height - fittedSize.destination.height) / 2;

    // 2. 변환된 좌표로 이미지 상대 좌표 계산
    final relativeX = (transformedPoint.dx - offsetX) / fittedSize.destination.width;
    final relativeY = (transformedPoint.dy - offsetY) / fittedSize.destination.height;

    // 확대 시 이미지 영역 밖도 허용 (경계 체크 완화)
    if (relativeX < -0.1 || relativeX > 1.1 || relativeY < -0.1 || relativeY > 1.1) {
      return null;
    }

    return Offset(
      (relativeX * imageSize.width).clamp(0, imageSize.width - 1),
      (relativeY * imageSize.height).clamp(0, imageSize.height - 1),
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
        title: Builder(
          builder: (context) {
            final l10n = AppLocalizations.of(context);
            return Text(l10n.edit, style: const TextStyle(color: Colors.white));
          },
        ),
        actions: [
          // 자르기 버튼
          Builder(
            builder: (context) {
              final l10n = AppLocalizations.of(context);
              return IconButton(
                icon: const Icon(Icons.crop, color: Colors.white),
                onPressed: _cropImage,
                tooltip: l10n.crop,
              );
            },
          ),
          // 회전 버튼
          Builder(
            builder: (context) {
              final l10n = AppLocalizations.of(context);
              return IconButton(
                icon: const Icon(Icons.rotate_right, color: Colors.white),
                onPressed: _rotateImage,
                tooltip: l10n.rotate,
              );
            },
          ),
          // 비교 모드 버튼
          Builder(
            builder: (context) {
              final l10n = AppLocalizations.of(context);
              return IconButton(
                icon: Icon(
                  Icons.compare,
                  color: _compareMode ? AppColors.primary : Colors.white,
                ),
                onPressed: () {
                  setState(() => _compareMode = !_compareMode);
                },
                tooltip: l10n.compareOriginal,
              );
            },
          ),
          // 줌 리셋
          if (_scale != 1.0)
            Builder(
              builder: (context) {
                final l10n = AppLocalizations.of(context);
                return IconButton(
                  icon: const Icon(Icons.fit_screen, color: Colors.white),
                  onPressed: _resetZoom,
                  tooltip: l10n.originalSize,
                );
              },
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
                                // 두 손가락: 핀치 줌 + 팬
                                setState(() {
                                  final newScale = (_previousScale * details.scale).clamp(
                                    AppConstants.minZoomScale,
                                    AppConstants.maxZoomScale,
                                  );
                                  final focalPoint = details.localFocalPoint;

                                  // 스케일 변화가 거의 없으면 팬만 적용
                                  if ((details.scale - 1.0).abs() < 0.02) {
                                    // 순수 팬 모드
                                    final newOffset = _previousOffset + details.focalPointDelta;
                                    _offset = _clampOffset(newOffset, canvasSize);
                                  } else {
                                    // 핀치 줌 - 초점 기준 확대/축소
                                    _scale = newScale;
                                    final newOffset = focalPoint - (focalPoint - _previousOffset) * (newScale / _previousScale);
                                    _offset = _clampOffset(newOffset, canvasSize);
                                  }
                                });
                              } else if (details.pointerCount == 1) {
                                // 한 손가락: 항상 그리기 (좌표 변환이 확대/이동 반영함)
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
                                  ..setEntry(0, 0, _scale)
                                  ..setEntry(1, 1, _scale)
                                  ..setEntry(0, 3, _offset.dx)
                                  ..setEntry(1, 3, _offset.dy),
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
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.visibility, color: Colors.white, size: 18),
                                      const SizedBox(width: 8),
                                      Text(AppLocalizations.of(context).original, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
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
            const LinearProgressIndicator(color: AppColors.primary),

          // 도구 패널 토글 버튼
          GestureDetector(
            onTap: () => setState(() => _toolsVisible = !_toolsVisible),
            child: Container(
              color: AppColors.cardDark,
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Builder(
                    builder: (context) {
                      final l10n = AppLocalizations.of(context);
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _toolsVisible ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
                            color: Colors.white70,
                            size: 20,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _toolsVisible ? l10n.hideTools : l10n.showTools,
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),

          // 하단 컨트롤 (고정 컴팩트 UI) - 애니메이션으로 숨기기/보이기
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            height: _toolsVisible ? null : 0,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: _toolsVisible ? 1.0 : 0.0,
              child: _toolsVisible ? Container(
                color: AppColors.cardDark,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 1. 도구 선택 - 그리드
                        Builder(
                          builder: (context) {
                            final l10n = AppLocalizations.of(context);
                            return Column(
                              children: [
                                // 1행: 블러, 모자이크, 채우기
                                Row(
                                  children: [
                                    Expanded(child: _buildGridToolChip(EditTool.blur, Icons.blur_on, l10n.blur)),
                                    const SizedBox(width: 6),
                                    Expanded(child: _buildGridToolChip(EditTool.mosaic, Icons.grid_view, l10n.mosaic)),
                                    const SizedBox(width: 6),
                                    Expanded(child: _buildGridToolChip(EditTool.highlighter, Icons.format_color_fill, l10n.fill)),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                // 2행: 지우개, 스티커, 텍스트
                                Row(
                                  children: [
                                    Expanded(child: _buildGridToolChip(EditTool.eraser, Icons.auto_fix_high, l10n.eraser)),
                                    const SizedBox(width: 6),
                                    Expanded(child: _buildGridToolChip(EditTool.sticker, Icons.emoji_emotions, l10n.sticker)),
                                    const SizedBox(width: 6),
                                    Expanded(child: _buildGridToolChip(EditTool.text, Icons.text_fields, l10n.text)),
                                  ],
                                ),
                              ],
                            );
                          },
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
                                Builder(
                                  builder: (context) {
                                    final l10n = AppLocalizations.of(context);
                                    return Row(
                                      mainAxisAlignment: MainAxisAlignment.start,
                                      children: [
                                        Text('${l10n.mode} ', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                                        const SizedBox(width: 8),
                                        _buildCompactModeChip(DrawMode.brush, Icons.brush),
                                        _buildCompactModeChip(DrawMode.rectangle, Icons.crop_square),
                                        _buildCompactModeChip(DrawMode.circle, Icons.circle_outlined),
                                        // 색상 선택 (채우기일 때만)
                                        if (_currentTool == EditTool.highlighter) ...[
                                          const SizedBox(width: 12),
                                          Container(width: 1, height: 24, color: Colors.white24),
                                          const SizedBox(width: 12),
                                          _buildColorChip(Colors.black, l10n.black),
                                          const SizedBox(width: 4),
                                          _buildColorChip(Colors.yellow, l10n.yellow),
                                          const SizedBox(width: 4),
                                          _buildColorChip(Colors.greenAccent, l10n.green),
                                          const SizedBox(width: 4),
                                          _buildColorChip(Colors.pinkAccent, l10n.pink),
                                          const SizedBox(width: 4),
                                          _buildColorChip(Colors.cyanAccent, l10n.cyan),
                                        ],
                                      ],
                                    );
                                  },
                                ),
                                const SizedBox(height: 10),
                                // 크기 슬라이더
                                Builder(
                                  builder: (context) {
                                    final l10n = AppLocalizations.of(context);
                                    return Column(
                                      children: [
                                        _buildSliderRow(
                                          label: l10n.size,
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
                                          label: l10n.intensity,
                                          value: _intensity,
                                          min: 0.1,
                                          max: 1.0,
                                          displayValue: '${(_intensity * 100).toInt()}%',
                                          onChanged: (v) => setState(() => _intensity = v),
                                          enabled: _currentTool != EditTool.eraser,
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ],
                            ),
                    ),

                  ],
                ),
              ),
            ),
          ) : const SizedBox.shrink(),
            ),
          ),

          // 3. 저장/공유 버튼 (항상 표시)
          Container(
            color: AppColors.cardDark,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: SizedBox(
                  height: 44,
                  child: Row(
                    children: [
                      Expanded(
                        child: Builder(
                          builder: (context) {
                            final l10n = AppLocalizations.of(context);
                            return ElevatedButton.icon(
                              onPressed: _isProcessing ? null : _saveImage,
                              icon: const Icon(Icons.save_alt, size: 18),
                              label: Text(l10n.save, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Builder(
                          builder: (context) {
                            final l10n = AppLocalizations.of(context);
                            return OutlinedButton.icon(
                              onPressed: _isProcessing ? null : _shareImage,
                              icon: const Icon(Icons.share, size: 18),
                              label: Text(l10n.share, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: const BorderSide(color: Colors.white38),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
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
              child: Text(AppLocalizations.of(context).original, style: const TextStyle(color: Colors.white, fontSize: 12)),
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
              child: Text(AppLocalizations.of(context).edited, style: const TextStyle(color: Colors.white, fontSize: 12)),
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
          color: isSelected ? AppColors.primary : Colors.white.withValues(alpha: 0.1),
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
            color: isSelected ? AppColors.primary : Colors.white.withValues(alpha: 0.1),
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
                    Builder(
                      builder: (context) {
                        final l10n = AppLocalizations.of(context);
                        return TabBar(
                          indicatorColor: AppColors.primary,
                          labelColor: Colors.white,
                          unselectedLabelColor: Colors.white54,
                          tabs: [
                            Tab(text: l10n.emoji),
                            Tab(text: l10n.shapes),
                            Tab(text: l10n.text),
                          ],
                        );
                      },
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
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.add, color: Colors.white, size: 20),
                    const SizedBox(width: 6),
                    Text(AppLocalizations.of(context).addSticker, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
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
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.add, color: Colors.white, size: 20),
                        const SizedBox(width: 6),
                        Text(AppLocalizations.of(context).addText, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
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
              Text('${AppLocalizations.of(context).textColor} ', style: const TextStyle(color: Colors.white54, fontSize: 11)),
              _buildTextColorChip(Colors.white, true),
              _buildTextColorChip(Colors.black, true),
              _buildTextColorChip(Colors.red, true),
              _buildTextColorChip(Colors.yellow, true),
              const SizedBox(width: 12),
              Text('${AppLocalizations.of(context).backgroundColor} ', style: const TextStyle(color: Colors.white54, fontSize: 11)),
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
            color: isSelected ? AppColors.primary : Colors.white38,
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
    final l10n = AppLocalizations.of(context);

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.enterText),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: l10n.enterTextHint,
            border: const OutlineInputBorder(),
          ),
          maxLines: 2,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                _addTextOverlay(controller.text);
              }
              Navigator.pop(dialogContext);
            },
            child: Text(l10n.add),
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
                    ? Border.all(color: AppColors.primary, width: 2)
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
            setState(() => _selectedStickerIndex = index);
            _initialStickerScale = sticker.scale;
            _initialStickerRotation = sticker.rotation;
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
                // 두 손가락 제스처: 스케일 + 회전
                if (details.pointerCount >= 2) {
                  sticker.scale = (_initialStickerScale * details.scale).clamp(0.3, 5.0);
                  sticker.rotation = _initialStickerRotation + details.rotation;
                }
              });
            }
          },
          child: Transform.scale(
            scale: _scale,
            child: Transform.rotate(
              angle: sticker.rotation,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // 스티커 본체
                  Container(
                    width: stickerSize,
                    height: sticker.isEmoji ? stickerSize : stickerSize * 0.5,
                    decoration: isSelected
                        ? BoxDecoration(
                            border: Border.all(color: AppColors.primary, width: 2),
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
                  // 선택 시 컨트롤 핸들 표시
                  if (isSelected) ...[
                    // 크기 조절 핸들 (우하단)
                    Positioned(
                      right: -12,
                      bottom: sticker.isEmoji ? -12 : -12 - stickerSize * 0.25,
                      child: GestureDetector(
                        onPanUpdate: (details) {
                          setState(() {
                            final delta = (details.delta.dx + details.delta.dy) / 2;
                            sticker.scale = (sticker.scale + delta / 50).clamp(0.3, 5.0);
                          });
                        },
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: const Icon(Icons.open_in_full, size: 14, color: Colors.white),
                        ),
                      ),
                    ),
                    // 회전 핸들 (상단 중앙)
                    Positioned(
                      left: stickerSize / 2 - 12,
                      top: -36,
                      child: Column(
                        children: [
                          GestureDetector(
                            onPanUpdate: (details) {
                              setState(() {
                                sticker.rotation += details.delta.dx / 50;
                              });
                            },
                            child: Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                              child: const Icon(Icons.rotate_right, size: 14, color: Colors.white),
                            ),
                          ),
                          Container(
                            width: 2,
                            height: 12,
                            color: AppColors.primary,
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
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
                    activeColor: AppColors.primary,
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
          color: isSelected ? AppColors.primary : Colors.white12,
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

  // 저장 (무료 사용자는 광고 먼저)
  Future<void> _saveImage() async {
    if (_currentBytes == null) return;

    // 무료 사용자는 광고 먼저 표시
    if (!SubscriptionService().isProUser) {
      setState(() => _isProcessing = true);
      AdService().showInterstitialAd(onAdClosed: () {
        _performSave();
      });
    } else {
      _performSave();
    }
  }

  Future<void> _performSave() async {
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
            rotation: s.rotation,
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
        // 저장 횟수 증가 (무료 사용자)
        await SaveLimitService.incrementSaveCount();

        // Analytics 이벤트
        AnalyticsService().logImageSaved(quality: '원본');

        if (!mounted) return;
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Text(l10n.saved),
              ],
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l10n.saveError}: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // 공유 (무료 사용자는 광고 먼저)
  Future<void> _shareImage() async {
    if (_currentBytes == null) return;

    // 무료 사용자는 광고 먼저 표시
    if (!SubscriptionService().isProUser) {
      setState(() => _isProcessing = true);
      AdService().showInterstitialAd(onAdClosed: () {
        _performShare();
      });
    } else {
      _performShare();
    }
  }

  Future<void> _performShare() async {
    if (_currentBytes == null) return;

    // iOS 공유 시트 위치를 위해 RenderBox 미리 획득
    final box = context.findRenderObject() as RenderBox?;
    final sharePosition = box != null
        ? box.localToGlobal(Offset.zero) & box.size
        : const Rect.fromLTWH(0, 0, 100, 100);

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
            rotation: s.rotation,
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

      // 임시 파일 생성
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final tempFile = File('${tempDir.path}/Cover_$timestamp.jpg');
      await tempFile.writeAsBytes(finalBytes);

      // 공유 (iOS에서는 sharePositionOrigin 필요)
      await Share.shareXFiles(
        [XFile(tempFile.path)],
        sharePositionOrigin: sharePosition,
      );

      // Analytics 이벤트
      AnalyticsService().logImageShared();

      // 임시 파일 삭제
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l10n.shareError}: $e'), backgroundColor: Colors.red),
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
  final double rotation;
  final bool isEmoji;

  StickerInfo({
    required this.content,
    required this.positionX,
    required this.positionY,
    required this.scale,
    required this.rotation,
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

    // 회전 값
    final cosR = cos(sticker.rotation);
    final sinR = sin(sticker.rotation);

    if (sticker.isEmoji) {
      // 이모지: 검은색 원으로 가리기 (회전해도 원은 동일)
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
      // 텍스트 라벨: 회전된 검은색 사각형으로 가리기
      final halfWidth = size ~/ 2;
      final halfHeight = size ~/ 4;

      // 회전된 사각형의 모든 점을 채우기 위해 더 넓은 범위 스캔
      final scanRange = (halfWidth > halfHeight ? halfWidth : halfHeight) + 5;
      for (int dy = -scanRange; dy <= scanRange; dy++) {
        for (int dx = -scanRange; dx <= scanRange; dx++) {
          // 역회전하여 원래 사각형 내부인지 확인
          final origDx = (dx * cosR + dy * sinR).round();
          final origDy = (-dx * sinR + dy * cosR).round();

          if (origDx.abs() <= halfWidth && origDy.abs() <= halfHeight) {
            final px = x + dx;
            final py = y + dy;
            if (px >= 0 && px < image.width && py >= 0 && py < image.height) {
              image.setPixel(px, py, img.ColorRgba8(0, 0, 0, 255));
            }
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
  // intensity 0.1~1.0 → alpha 0.1~1.0 (100% 불투명도 지원)
  final alpha = intensity.clamp(0.1, 1.0);
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
  // intensity 0.1~1.0 → alpha 0.1~1.0 (100% 불투명도 지원)
  final alpha = intensity.clamp(0.1, 1.0);
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
  void _showProSubscription(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _ProSubscriptionSheet(),
    );
  }

  // 앱스토어 ID
  static const String _appStoreId = '6756909105';

  Future<void> _rateApp(BuildContext context) async {
    final url = Platform.isIOS
        ? Uri.parse('https://apps.apple.com/app/id$_appStoreId?action=write-review')
        : Uri.parse('https://play.google.com/store/apps/details?id=com.devyulstudio.cover');

    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      if (context.mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.get('cannotOpenStore'))),
        );
      }
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
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settings),
        automaticallyImplyLeading: false,
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
                          Text(
                            l10n.removeAds,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            l10n.removeAdsDesc,
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

          // 지원
          _SectionHeader(title: l10n.support),
          _SettingsTile(
            icon: Icons.star_outline,
            title: l10n.rateApp,
            subtitle: l10n.rateAppDesc,
            onTap: () => _rateApp(context),
          ),

          const SizedBox(height: 8),

          // 앱 정보
          _SectionHeader(title: l10n.appInfo),
          _SettingsTile(
            icon: Icons.info_outline,
            title: l10n.version,
            subtitle: '1.0.0',
            onTap: null,
          ),
          _SettingsTile(
            icon: Icons.description_outlined,
            title: l10n.openSourceLicenses,
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
            title: l10n.privacyPolicy,
            onTap: () => _openUrl(l10n.privacyPolicyUrl),
          ),
          _SettingsTile(
            icon: Icons.article_outlined,
            title: l10n.termsOfService,
            onTap: () => _openUrl(l10n.termsOfServiceUrl),
          ),

          const SizedBox(height: 32),

          // 앱 정보 푸터
          Center(
            child: Column(
              children: [
                Text(
                  l10n.appName,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white54 : Colors.black38,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.appDescription,
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

  // 광고 제거 (평생 이용권) 패키지
  Package? get _lifetimePackage => _packages?.cast<Package?>().firstWhere(
    (p) => p?.storeProduct.identifier == SubscriptionService.lifetimeProductId,
    orElse: () => null,
  );

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
      final package = _lifetimePackage;
      if (package != null) {
        final success = await _subscriptionService.purchasePackage(package);

        if (success) {
          AnalyticsService().logSubscriptionStarted('ad_removal');
        }

        if (mounted) {
          final l10n = AppLocalizations.of(context);
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(success ? l10n.adsRemoved : l10n.get('purchaseCancelled')),
              backgroundColor: success ? Colors.green : Colors.orange,
            ),
          );
        }
      } else {
        if (mounted) {
          final l10n = AppLocalizations.of(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.get('cannotLoadProduct')),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l10n.error}: $e'), backgroundColor: Colors.red),
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
        final l10n = AppLocalizations.of(context);
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? l10n.restoreSuccess : l10n.restoreFailed),
            backgroundColor: success ? Colors.green : Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l10n.get('restoreError')}: $e'), backgroundColor: Colors.red),
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
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    final maxHeight = MediaQuery.of(context).size.height * 0.9;
    final l10n = AppLocalizations.of(context);

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 드래그 핸들 (고정)
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[400],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),

          // 스크롤 가능한 콘텐츠
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.only(bottom: bottomPadding + 16),
              child: Column(
                children: [
                  const SizedBox(height: 12),

                  // 헤더
                  const Icon(Icons.block, size: 48, color: Color(0xFF6366F1)),
                  const SizedBox(height: 12),
                  Text(
                    l10n.removeAds,
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.get('removeAdsFullDesc'),
                    style: TextStyle(color: Colors.grey[600], fontSize: 14),
                  ),

                  const SizedBox(height: 24),

                  // 혜택 설명
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          _buildFeatureRow(Icons.block, l10n.get('noAdsOnSave')),
                          _buildFeatureRow(Icons.flash_on, l10n.get('fastSave')),
                          _buildFeatureRow(Icons.all_inclusive, l10n.get('permanent')),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // 가격
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFF6366F1), width: 2),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _lifetimePackage?.storeProduct.priceString ?? '\$3.99',
                            style: const TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF6366F1),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            l10n.lifetime,
                            style: const TextStyle(fontSize: 16, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // 구매 버튼
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
                                l10n.get('purchaseRemoveAds'),
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                              ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // 하단 안내
                  Text(
                    l10n.get('oneTimePurchaseNote'),
                    style: TextStyle(color: Colors.grey[500], fontSize: 12),
                  ),
                  TextButton(
                    onPressed: _isLoading ? null : _restorePurchases,
                    child: Text(
                      l10n.restore,
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  ),

                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
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

  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, size: 24),
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle!) : null,
      onTap: onTap,
    );
  }
}
