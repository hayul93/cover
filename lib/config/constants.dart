import 'package:flutter/material.dart';

/// 앱 전역 상수
class AppConstants {
  AppConstants._();

  // ==================== 앱 정보 ====================

  static const String appName = 'Cover';
  static const String developerName = 'DevyulStudio';
  static const String supportEmail = 'parksy785@gmail.com';

  // ==================== 제한 설정 ====================

  /// 무료 사용자 일일 저장 횟수 제한
  static const int maxFreeSavesPerDay = 5;

  /// Undo/Redo 최대 단계
  static const int maxUndoSteps = 10;

  /// 최근 이미지 최대 개수
  static const int maxRecentImages = 20;

  // ==================== 기본값 ====================

  /// 기본 브러시 크기
  static const double defaultBrushSize = 30.0;

  /// 기본 블러 강도
  static const double defaultBlurIntensity = 15.0;

  /// 기본 모자이크 강도
  static const double defaultMosaicIntensity = 15.0;

  /// 기본 형광펜 투명도
  static const double defaultHighlighterOpacity = 0.5;

  // ==================== 범위 설정 ====================

  /// 브러시 크기 범위
  static const double minBrushSize = 5.0;
  static const double maxBrushSize = 100.0;

  /// 블러 강도 범위
  static const double minBlurIntensity = 5.0;
  static const double maxBlurIntensity = 50.0;

  /// 모자이크 강도 범위
  static const double minMosaicIntensity = 5.0;
  static const double maxMosaicIntensity = 50.0;

  /// 줌 범위
  static const double minZoomScale = 1.0;
  static const double maxZoomScale = 5.0;
}

/// 앱 컬러 팔레트
class AppColors {
  AppColors._();

  // ==================== 브랜드 컬러 ====================

  /// 프라이머리 컬러 (블루)
  static const Color primary = Color(0xFF2196F3);

  /// 세컨더리 컬러 (퍼플)
  static const Color secondary = Color(0xFF9C27B0);

  // ==================== 배경 컬러 ====================

  /// 다크 배경
  static const Color backgroundDark = Colors.black;

  /// 카드/패널 배경
  static const Color cardDark = Color(0xFF1A1A1A);

  /// 서피스 다크
  static const Color surfaceDark = Color(0xFF121212);

  // ==================== 텍스트 컬러 ====================

  /// 다크 테마 메인 텍스트
  static const Color textPrimaryDark = Colors.white;

  /// 다크 테마 서브 텍스트
  static const Color textSecondaryDark = Colors.white70;

  /// 라이트 테마 메인 텍스트
  static const Color textPrimaryLight = Color(0xFF212121);

  /// 라이트 테마 서브 텍스트
  static const Color textSecondaryLight = Color(0xFF757575);

  // ==================== 상태 컬러 ====================

  /// 성공
  static const Color success = Color(0xFF4CAF50);

  /// 경고
  static const Color warning = Color(0xFFFF9800);

  /// 에러
  static const Color error = Color(0xFFF44336);

  /// 정보
  static const Color info = Color(0xFF2196F3);

  // ==================== Pro 관련 ====================

  /// Pro 배지 배경
  static const Color proBadge = Color(0xFFFFCC66);

  /// Pro 그라데이션
  static const List<Color> proGradient = [
    Color(0xFFFFD700),
    Color(0xFFFFA500),
  ];

  // ==================== 형광펜 색상 ====================

  static const List<Color> highlighterColors = [
    Colors.black,
    Color(0xFFFFEB3B), // 노랑
    Color(0xFF4CAF50), // 초록
    Color(0xFF2196F3), // 파랑
    Color(0xFFFF5722), // 주황
    Color(0xFFE91E63), // 핑크
    Color(0xFF9C27B0), // 보라
    Colors.white,
  ];

  // ==================== 텍스트 색상 옵션 ====================

  static const List<Color> textColors = [
    Colors.white,
    Colors.black,
    Color(0xFFFF5252), // 빨강
    Color(0xFFFFEB3B), // 노랑
    Color(0xFF4CAF50), // 초록
    Color(0xFF2196F3), // 파랑
    Color(0xFFE91E63), // 핑크
    Color(0xFF9C27B0), // 보라
  ];
}

/// 구독 상품 ID
class ProductIds {
  ProductIds._();

  static const String entitlementId = 'pro';
  static const String monthly = 'cover_pro_monthly';
  static const String yearly = 'cover_pro_yearly';
  static const String lifetime = 'cover_pro_lifetime';
}
