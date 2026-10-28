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
      centerTitle: true,
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: Colors.black.withValues(alpha: 0.06),
          width: 0.8,
        ),
      ),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Colors.white,
      selectedItemColor: AppColors.primaryDark,
      unselectedItemColor: Colors.black45,
      selectedLabelStyle: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
      unselectedLabelStyle: TextStyle(fontWeight: FontWeight.w500, fontSize: 11),
      elevation: 4,
      type: BottomNavigationBarType.fixed,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Colors.white,
      selectedColor: AppColors.primary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Colors.grey.shade300, width: 0.8),
      ),
    ),
    // Mọi ô nhập liệu: giữ contentPadding 14x16 để không đẩy layout vượt 600px
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.fieldBg,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.grey.shade300, width: 0.8),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.grey.shade300, width: 0.8),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        side: const BorderSide(color: AppColors.primary, width: 1.2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
  );
}
