import 'package:flutter/material.dart';
import 'constants.dart';

/// SnackBar 헬퍼 확장
extension SnackBarHelper on BuildContext {
  /// 성공 메시지 표시
  void showSuccessSnackBar(String message, {IconData icon = Icons.check_circle}) {
    ScaffoldMessenger.of(this).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: AppColors.success,
      ),
    );
  }

  /// 에러 메시지 표시
  void showErrorSnackBar(String message, {IconData icon = Icons.error}) {
    ScaffoldMessenger.of(this).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: AppColors.error,
      ),
    );
  }

  /// 정보 메시지 표시
  void showInfoSnackBar(String message, {IconData icon = Icons.info}) {
    ScaffoldMessenger.of(this).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: AppColors.info,
      ),
    );
  }

  /// 경고 메시지 표시
  void showWarningSnackBar(String message, {IconData icon = Icons.warning}) {
    ScaffoldMessenger.of(this).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: AppColors.warning,
      ),
    );
  }
}

/// 공통 위젯 스타일
class AppStyles {
  AppStyles._();

  /// 카드 데코레이션 (다크 모드)
  static BoxDecoration get cardDecoration => BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      );

  /// 버튼 스타일 (프라이머리)
  static ButtonStyle get primaryButtonStyle => ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      );

  /// 아웃라인 버튼 스타일
  static ButtonStyle get outlineButtonStyle => OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: const BorderSide(color: Colors.white24),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      );
}
