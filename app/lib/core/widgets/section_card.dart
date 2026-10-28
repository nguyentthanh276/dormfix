import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Khối trắng bo góc, đổ bóng nhẹ, dùng để nhóm thông tin trên màn hình.
class SectionCard extends StatelessWidget {
  final String? title;
  final Widget child;

  const SectionCard({super.key, this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.black.withValues(alpha: 0.05),
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Text(
              title!,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: AppColors.primaryDark,
                letterSpacing: 0.1,
              ),
            ),
            const SizedBox(height: 10),
          ],
          child,
        ],
      ),
    );
  }
}
