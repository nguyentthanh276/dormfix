import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Giao diện khi danh sách rỗng: biểu tượng và một dòng chữ trang nhã.
class EmptyView extends StatelessWidget {
  final String text;

  const EmptyView(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.fieldBg,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.inbox_outlined,
                  size: 52,
                  color: AppColors.primary.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                text,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
