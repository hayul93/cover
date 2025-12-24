import 'dart:io';
import 'package:flutter/foundation.dart';

/// API 키 설정
/// 보안: 이 키들은 공개 앱에서 사용되는 클라이언트 키입니다.
/// 서버 키나 비밀 키는 절대 포함하지 마세요.
class ApiKeys {
  ApiKeys._();

  // ==================== RevenueCat ====================

  static const String _revenueCatIOS = 'appl_RTTbxEwnpxhUZNsrKdmimCGYjdy';
  static const String _revenueCatAndroid = 'goog_EwguVFnVbUlHDvtNRKoQVjXhlFW';

  static String get revenueCat => Platform.isIOS ? _revenueCatIOS : _revenueCatAndroid;

  // ==================== AdMob ====================

  // 테스트 광고 ID (Google 공식 테스트 ID)
  static const String _testInterstitialIOS = 'ca-app-pub-3940256099942544/4411468910';
  static const String _testInterstitialAndroid = 'ca-app-pub-3940256099942544/1033173712';
  static const String _testNativeIOS = 'ca-app-pub-3940256099942544/3986624511';
  static const String _testNativeAndroid = 'ca-app-pub-3940256099942544/2247696110';

  // 실제 광고 ID
  static const String _prodInterstitialIOS = 'ca-app-pub-3438920793636799/2729421253';
  static const String _prodInterstitialAndroid = 'ca-app-pub-3438920793636799/8197370353';
  static const String _prodNativeIOS = 'ca-app-pub-3438920793636799/1091431175';
  static const String _prodNativeAndroid = 'ca-app-pub-3438920793636799/3384027376';

  /// 전면 광고 ID (디버그 모드에서는 테스트 ID 사용)
  static String get interstitialAdUnitId {
    if (kDebugMode) {
      return Platform.isIOS ? _testInterstitialIOS : _testInterstitialAndroid;
    }
    return Platform.isIOS ? _prodInterstitialIOS : _prodInterstitialAndroid;
  }

  /// 네이티브 광고 ID (디버그 모드에서는 테스트 ID 사용)
  static String get nativeAdUnitId {
    if (kDebugMode) {
      return Platform.isIOS ? _testNativeIOS : _testNativeAndroid;
    }
    return Platform.isIOS ? _prodNativeIOS : _prodNativeAndroid;
  }
}
