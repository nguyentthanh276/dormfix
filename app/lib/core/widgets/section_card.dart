import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Khối trắng bo góc, có tiêu đề (tùy chọn), dùng để nhóm thông tin trên màn hình.
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
        borderRadius: BorderRadius.circular(8),
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
