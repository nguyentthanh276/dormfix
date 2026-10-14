import 'package:flutter/material.dart';

/// Bảng màu FPT: cam là màu chính, xanh là màu phụ, nền trắng.
abstract final class AppColors {
  static const orange = Color(0xFFF37021);
  static const blue = Color(0xFF0066B3);
  static const white = Color(0xFFFFFFFF);
}

abstract final class AppTheme {
  static ThemeData get light {
    // fromSeed sinh cả bộ màu từ cam; copyWith ép các màu chính đúng màu FPT.
    final scheme = ColorScheme.fromSeed(seedColor: AppColors.orange).copyWith(
      primary: AppColors.orange,
      onPrimary: AppColors.white,
      secondary: AppColors.blue,
      surface: AppColors.white,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.white,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.white,
        foregroundColor: AppColors.orange,
        surfaceTintColor: AppColors.white,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
      cardTheme: CardThemeData(
        color: AppColors.white,
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
