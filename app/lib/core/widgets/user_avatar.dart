import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Ảnh đại diện tròn lấy chữ cái cuối của tên.
class UserAvatar extends StatelessWidget {
  final String name;
  final double radius;

  const UserAvatar(this.name, {super.key, this.radius = 20});

  @override
  Widget build(BuildContext context) {
    final parts = name.trim().split(' ');
    final initial = parts.isEmpty || parts.last.isEmpty ? '?' : parts.last[0];
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.primary.withAlpha(40),
      child: Text(
        initial,
        style: TextStyle(
          color: AppColors.primaryDark,
          fontWeight: FontWeight.bold,
          fontSize: radius * 0.8,
        ),
      ),
    );
  }
}
