import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Theme chung của app (cách đặt theo Slot 7: ThemeData là nền tảng của UI).
abstract final class AppTheme {
  static ThemeData get light => ThemeData(
    useMaterial3: true,
    // fromSeed sinh cả bộ màu từ cam; copyWith ép màu chính đúng cam FPT.
    colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary)
        .copyWith(primary: AppColors.primary, onPrimary: Colors.white),
    scaffoldBackgroundColor: AppColors.pageBg,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.primaryDark,
      foregroundColor: Colors.white,
      elevation: 0,
    ),
    // Mọi ô nhập liệu: nền cam nhạt, bo góc, không viền.
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.fieldBg,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide.none,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
  );
}
