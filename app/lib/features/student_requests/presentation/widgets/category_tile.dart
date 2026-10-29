import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../models/incident_category.dart';
import 'category_icon.dart';

/// Ô chọn loại sự cố: biểu tượng và tên, đổi sang nền cam khi được chọn.
class CategoryTile extends StatelessWidget {
  final IncidentCategory category;
  final bool selected;
  final VoidCallback onTap;

  const CategoryTile({
    super.key,
    required this.category,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.primary : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected
              ? AppColors.primary
              : Colors.black.withValues(alpha: 0.08),
          width: selected ? 1.5 : 0.8,
        ),
      ),
      elevation: selected ? 2 : 0,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              categoryIcon(category.name),
              color: selected ? Colors.white : AppColors.primaryDark,
              size: 28,
            ),
            const SizedBox(height: 6),
            Text(
              category.name,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: selected ? Colors.white : Colors.black87,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
