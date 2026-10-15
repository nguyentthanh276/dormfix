import 'package:flutter/material.dart';

/// Bảng màu của app: cam FPT làm màu chính, nền sáng ấm.
abstract final class AppColors {
  static const primary = Color(0xFFF37021); // cam FPT
  static const primaryDark = Color(
    0xFFD4560C,
  ); // cam đậm: thanh tiêu đề, chữ nhấn
  static const accent = Color(0xFFFF9A3D); // cam sáng
  static const fieldBg = Color(0xFFFFEFE3); // nền ô nhập liệu
  static const pageBg = Color(0xFFFAF5F0); // nền trang
}
